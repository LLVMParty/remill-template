#include <cstdlib>
#include <filesystem>

#include "exepath.hpp"

#include <glog/logging.h>
#include <remill/Arch/Arch.h>
#include <remill/Arch/Instruction.h>
#include <remill/Arch/Name.h>
#include <remill/BC/ABI.h>
#include <remill/BC/IntrinsicTable.h>
#include <remill/BC/Lifter.h>
#include <remill/BC/Optimizer.h>
#include <remill/BC/Util.h>
#include <remill/BC/Version.h>
#include <remill/OS/OS.h>
#include <remill/Version/Version.h>

#include <llvm/Demangle/Demangle.h>
#include <llvm/IR/PassManager.h>
#include <llvm/IRReader/IRReader.h>
#include <llvm/Linker/Linker.h>
#include <llvm/Passes/PassBuilder.h>
#include <llvm/Support/SourceMgr.h>
#include <llvm/Transforms/IPO/GlobalDCE.h>

/// Hotpatch remill semantics by loading a bitcode module and linking it.
///
/// Remill instruction selection works via ISEL_* global variables that point to
/// semantic functions. For example, ISEL_CPUID points to the function that
/// implements the CPUID instruction.
///
/// To hotpatch an instruction:
/// 1. Create a .cpp file with the remill runtime headers
/// 2. Define a semantic function using DEF_SEM(name) { ... }
/// 3. Register it with DEF_ISEL(INSTRUCTION_NAME) = semantic_function;
/// 4. Compile to bitcode and link into the semantics module
///
/// See helpers/x86_64/RemillHotpatch.cpp for an example.
static bool hotpatchRemill(llvm::Module &module,
                           const std::string &hotpatchPath) {
  if (!std::filesystem::exists(hotpatchPath)) {
    llvm::errs() << "Hotpatch file not found: " << hotpatchPath << "\n";
    return false;
  }

  llvm::SMDiagnostic error;
  auto patchModule =
      llvm::parseIRFile(hotpatchPath, error, module.getContext());
  if (!patchModule) {
    llvm::errs() << "Failed to parse hotpatch module: " << error.getMessage()
                 << "\n";
    return false;
  }

  // Prepare the patch module to be compatible with the semantics module
  patchModule->setDataLayout(module.getDataLayout());
  patchModule->setTargetTriple(module.getTargetTriple());

  // Rename existing ISEL_ globals to avoid conflicts during linking
  // The hotpatch module's ISEL_ globals will take precedence
  for (const auto &global : patchModule->globals()) {
    const auto &globalName = global.getName().str();
    // Check if this is a hotpatch ISEL global variable
    if (globalName.rfind("ISEL_", 0) == 0) {
      // Find and rename the existing global in the semantics module
      auto *existingGlobal = module.getGlobalVariable(globalName);
      if (existingGlobal) {
        existingGlobal->setName(globalName + "_original");
        llvm::outs() << "Hotpatching: " << globalName << "\n";
      }
    }
  }

  // Link the hotpatch module into the semantics module
  // OverrideFromSrc ensures the hotpatch definitions take precedence
  if (llvm::Linker::linkModules(module, std::move(patchModule),
                                llvm::Linker::Flags::OverrideFromSrc)) {
    llvm::errs() << "Failed to link hotpatch module\n";
    return false;
  }

  return true;
}

int main(int argc, char **argv) {
  google::InitGoogleLogging(argv[0]);

  llvm::LLVMContext context;
  auto arch = remill::Arch::Get(context, "linux", "amd64");
  if (!arch) {
    llvm::outs() << "Failed to get architecture\n";
    return EXIT_FAILURE;
  }

  auto semantics = remill::LoadArchSemantics(arch.get());
  if (!semantics) {
    llvm::outs() << "Failed to load architecture semantics\n";
    return EXIT_FAILURE;
  }

  // Apply hotpatch to remill semantics
  // The hotpatch module is built by the helpers target
  // (helpers/x86_64/RemillHotpatch.cpp) It provides custom implementations for
  // specific instructions like CPUID
  auto hotpatchPath = executableDir() / "helpers/x86_64/RemillHotpatch.bc";
  if (argc > 1) {
    hotpatchPath = argv[1];
  }

  if (std::filesystem::exists(hotpatchPath)) {
    llvm::outs() << "Applying hotpatch from: " << hotpatchPath.string() << "\n";
    if (!hotpatchRemill(*semantics, hotpatchPath.string())) {
      llvm::outs() << "Warning: Failed to apply hotpatch\n";
    }
  } else {
    llvm::outs() << "No hotpatch file found at: " << hotpatchPath.string()
                 << "\n";
  }

  auto intrinsics = arch->GetInstrinsicTable();
  if (!intrinsics) {
    llvm::outs() << "Failed to get intrinsic table\n";
    return EXIT_FAILURE;
  }

  // Example 1: Lift a simple instruction (mov rcx, 1337)
  llvm::outs() << "\n=== Lifting: mov rcx, 1337 ===\n";
  {
    uint8_t instr_bytes[] = {0x48, 0xc7, 0xc1, 0x39, 0x05, 0x00, 0x00};
    std::string_view instr_view(reinterpret_cast<char *>(instr_bytes),
                                sizeof(instr_bytes));
    remill::Instruction instruction;
    remill::DecodingContext decoding_context = arch->CreateInitialContext();
    if (!arch->DecodeInstruction(0x1000, instr_view, instruction,
                                 decoding_context)) {
      llvm::outs() << "Failed to decode instruction\n";
      return EXIT_FAILURE;
    }

    auto function = arch->DefineLiftedFunction("lifted_mov", semantics.get());
    auto block = &function->getEntryBlock();
    auto lifter = instruction.GetLifter();
    auto status = lifter->LiftIntoBlock(instruction, block);
    if (status != remill::kLiftedInstruction) {
      llvm::outs() << "Failed to lift instruction\n";
      return EXIT_FAILURE;
    }

    llvm::IRBuilder<> ir(block);
    ir.CreateRet(remill::LoadMemoryPointer(block, *intrinsics));

    remill::OptimizeModule(arch.get(), semantics.get(), {function});
    llvm::outs() << "[optimized]\n";
    function->print(llvm::outs());
  }

  // Example 2: Lift CPUID instruction (demonstrates hotpatching)
  llvm::outs() << "\n=== Lifting: cpuid ===\n";
  {
    uint8_t instr_bytes[] = {0x0f, 0xa2}; // cpuid
    std::string_view instr_view(reinterpret_cast<char *>(instr_bytes),
                                sizeof(instr_bytes));
    remill::Instruction instruction;
    remill::DecodingContext decoding_context = arch->CreateInitialContext();
    if (!arch->DecodeInstruction(0x2000, instr_view, instruction,
                                 decoding_context)) {
      llvm::outs() << "Failed to decode CPUID instruction\n";
      return EXIT_FAILURE;
    }

    auto function = arch->DefineLiftedFunction("lifted_cpuid", semantics.get());
    auto block = &function->getEntryBlock();
    auto lifter = instruction.GetLifter();
    auto status = lifter->LiftIntoBlock(instruction, block);
    if (status != remill::kLiftedInstruction) {
      llvm::outs() << "Failed to lift CPUID instruction\n";
      return EXIT_FAILURE;
    }

    llvm::IRBuilder<> ir(block);
    ir.CreateRet(remill::LoadMemoryPointer(block, *intrinsics));

    // Print unoptimized to see the hotpatched implementation
    llvm::outs() << "[unoptimized]\n";
    function->print(llvm::outs());

    remill::OptimizeModule(arch.get(), semantics.get(), {function});
    llvm::outs() << "\n[optimized]\n";
    function->print(llvm::outs());
  }

  return EXIT_SUCCESS;
}
