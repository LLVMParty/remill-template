#include <cstdlib>

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

#include <llvm/IR/PassManager.h>
#include <llvm/Passes/PassBuilder.h>
#include <llvm/Transforms/IPO/GlobalDCE.h>

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

  // mov rcx, 0x1337
  uint8_t instr_bytes[] = {0x48, 0xc7, 0xc1, 0x37, 0x13, 0x00, 0x00};
  std::string_view instr_view(reinterpret_cast<char *>(instr_bytes),
                              sizeof(instr_bytes));
  remill::Instruction instruction;
  remill::DecodingContext decoding_context = arch->CreateInitialContext();
  if (!arch->DecodeInstruction(0x1000, instr_view, instruction,
                               decoding_context)) {
    llvm::outs() << "Failed to decode instruction\n";
    return EXIT_FAILURE;
  }

  auto function = llvm::Function::Create(arch->LiftedFunctionType(),
                                         llvm::Function::ExternalLinkage,
                                         "lifted_example", semantics.get());

  llvm::BasicBlock *block =
      llvm::BasicBlock::Create(context, "entry", function);

  auto lifter = instruction.GetLifter();
  auto status = lifter->LiftIntoBlock(instruction, block);
  if (status != remill::kLiftedInstruction) {
    llvm::outs() << "Failed to lift instruction\n";
    return EXIT_FAILURE;
  }

  function->print(llvm::outs());

  return EXIT_SUCCESS;
}
