# Get the remill include directories from the target
if(NOT TARGET remill_settings)
    message(FATAL_ERROR "Could not find target 'remill_settings' (did remill update?)")
endif()
get_target_property(HELPER_REMILL_INCLUDE_DIR remill_settings INTERFACE_INCLUDE_DIRECTORIES)
if(HELPER_REMILL_INCLUDE STREQUAL "HELPER_REMILL_INCLUDE_DIR-NOTFOUND")
    message(FATAL_ERROR "Could not determine remill include directory")
endif()
set(HELPER_REMILL_SYSROOT_DIR "${HELPER_REMILL_INCLUDE_DIR}/remill/Arch/Runtime/sysroot")
if(NOT EXISTS "${HELPER_REMILL_SYSROOT_DIR}")
    message(FATAL_ERROR "Could not find remill sysroot directory: ${HELPER_REMILL_SYSROOT_DIR}")
endif()

# Locate the clang executable
set(HELPER_CLANG_EXECUTABLE ${LLVM_TOOLS_BINARY_DIR}/clang++${CMAKE_EXECUTABLE_SUFFIX})
if(NOT EXISTS "${HELPER_CLANG_EXECUTABLE}")
    message(FATAL_ERROR "Could not find: ${HELPER_CLANG_EXECUTABLE}")
endif()

message(STATUS "[helpers] Remill include: ${HELPER_REMILL_INCLUDE_DIR}")
message(STATUS "[helpers] Remill sysroot: ${HELPER_REMILL_SYSROOT_DIR}")
message(STATUS "[helpers] Clang: ${HELPER_CLANG_EXECUTABLE}")

add_custom_target(helpers)

function(add_helper arch)
    set(HELPER_FLAGS ${ARGN})
    # Generate a CMake script to compile the helpers
    # This allows the user to do project-specific helpers and easily recompile them
    message(STATUS "[helpers] Adding architecture: ${arch}")
    message(STATUS "[helpers] Additional flags: ${HELPER_FLAGS}")

    # TODO: These flags are not exactly the same as remill's
    set(HELPER_CLANG_FLAGS
        ${HELPER_FLAGS}
        -ffreestanding
        --sysroot=${HELPER_REMILL_SYSROOT_DIR}
        -nostdinc++
        -isystem ${HELPER_REMILL_SYSROOT_DIR}

        -emit-llvm
        -std=c++17
        -O3
        -Werror
        -Wno-gnu-inline-cpp-without-extern
        -Wno-return-type-c-linkage

        -fno-discard-value-names
        -fstrict-aliasing
        -fno-vectorize
        -fno-slp-vectorize
        -mllvm -enable-tbaa=true

        "-I${HELPER_REMILL_INCLUDE_DIR}"
    )

    set(HELPER_BINARY_DIR "${CMAKE_BINARY_DIR}/helpers/${arch}")
    set(HELPER_SCRIPT "${HELPER_BINARY_DIR}/build.cmake")
    set(HELPER_DIR "${CMAKE_CURRENT_SOURCE_DIR}/${arch}")
    configure_file("build.cmake.in" "${HELPER_SCRIPT}" @ONLY)

    # Determine the inputs/outputs for the custom command
    set(HELPER_SOURCES
        "${HELPER_DIR}/RemillHelpers.cpp"
        "${HELPER_DIR}/RemillHotpatch.cpp"
    )
    set(HELPER_OUTPUTS "")
    foreach(source ${HELPER_SOURCES})
        if(EXISTS "${source}")
            get_filename_component(name "${source}" NAME_WE)
            list(APPEND HELPER_OUTPUTS
                "${HELPER_BINARY_DIR}/${name}.ll"
                "${HELPER_BINARY_DIR}/${name}.bc"
            )
        endif()
    endforeach()

    # Create a custom target to build it automatically when any of the sources are updated
    add_custom_command(
        OUTPUT ${HELPER_OUTPUTS}
        COMMAND "${CMAKE_COMMAND}" -P "${HELPER_SCRIPT}"
        DEPENDS ${HELPER_SOURCES} ${HELPER_SCRIPT}
        WORKING_DIRECTORY "${HELPER_BINARY_DIR}"
        COMMENT "Building helpers for ${arch}"
    )
    add_custom_target("helpers-${arch}" ALL
        DEPENDS ${HELPER_OUTPUTS}
        SOURCES ${HELPER_SOURCES}
    )
    add_dependencies(helpers "helpers-${arch}")
endfunction()

add_helper(aarch64 -target aarch64-none-elf -DADDRESS_SIZE_BITS=64)
add_helper(x86_64 -target x86_64-none-elf -DADDRESS_SIZE_BITS=64 -mlong-double-80)
add_helper(x86_32 -target i386-none-elf -DADDRESS_SIZE_BITS=32 -mlong-double-80)
