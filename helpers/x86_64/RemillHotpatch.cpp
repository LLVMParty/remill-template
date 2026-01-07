#include <remill/Arch/Runtime/Definitions.h>
#include <remill/Arch/Runtime/HyperCall.h>
#include <remill/Arch/Runtime/Intrinsics.h>
#include <remill/Arch/Runtime/Operators.h>
#include <remill/Arch/Runtime/Types.h>
#include <remill/Arch/X86/Runtime/State.h>
#include <remill/Arch/X86/Runtime/Types.h>

// CPUID implementation

typedef struct {
  uint32_t eax;
  uint32_t ebx;
  uint32_t ecx;
  uint32_t edx;
} CPUIDResult;

extern "C" void __remill_cpuid(Memory *memory, CPUIDResult *result,
                               uint32_t eax, uint32_t ecx);

DEF_SEM(CPUID) {
  CPUIDResult result;
  __remill_cpuid(memory, &result, state.gpr.rax.dword, state.gpr.rcx.dword);
  state.gpr.rax.qword = result.eax;
  state.gpr.rbx.qword = result.ebx;
  state.gpr.rcx.qword = result.ecx;
  state.gpr.rdx.qword = result.edx;
  return memory;
}

DEF_ISEL(CPUID) = CPUID;
