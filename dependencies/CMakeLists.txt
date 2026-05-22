# https://alexreinking.com/blog/how-to-use-cmake-without-the-agonizing-pain-part-1.html
cmake_minimum_required(VERSION 3.21)

# Default to a Release config. Required before project() because Windows defaults to Debug
set(CMAKE_BUILD_TYPE "Release" CACHE STRING "")
if(CMAKE_BUILD_TYPE STREQUAL "")
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "" FORCE)
endif()

project(dependencies)

option(USE_EXTERNAL_LLVM "Do not build/provision LLVM as part of the superbuild, use an external one instead" OFF)
option(DOWNLOAD_PREBUILT_LLVM "Download and extract a prebuilt LLVM into the install prefix" ON)
option(USE_SANITIZERS "Use ASan and UBSan" OFF)
option(ENABLE_SLEIGH "Build and install sleigh into the dependencies prefix" ON)

if(USE_EXTERNAL_LLVM)
    if(CMAKE_HOST_SYSTEM_NAME MATCHES "Darwin" AND NOT CMAKE_PREFIX_PATH)
        execute_process(
            COMMAND brew --prefix llvm
            RESULT_VARIABLE BREW_LLVM
            OUTPUT_VARIABLE BREW_LLVM_PREFIX
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        if(BREW_LLVM EQUAL 0 AND EXISTS "${BREW_LLVM_PREFIX}")
            set(CMAKE_PREFIX_PATH "${BREW_LLVM_PREFIX}")
            message(STATUS "Found LLVM keg installed by Homebrew at ${BREW_LLVM_PREFIX}")
        else()
            message(WARNING "LLVM not found, to install: brew install llvm")
        endif()
    endif()
    find_package(LLVM CONFIG REQUIRED)
    message(STATUS "LLVM ${LLVM_PACKAGE_VERSION}: ${LLVM_DIR}")
endif()

if(USE_SANITIZERS)
    list(APPEND CMAKE_C_FLAGS "-fsanitize=address,undefined")
    list(APPEND CMAKE_CXX_FLAGS "-fsanitize=address,undefined")
endif()

include(superbuild.cmake)

set(remill_dependencies_dir "${CMAKE_CURRENT_LIST_DIR}/remill/dependencies")
if(NOT EXISTS "${remill_dependencies_dir}/xed.cmake" OR NOT EXISTS "${remill_dependencies_dir}/build_ppc_e200_sla.cmake")
    message(FATAL_ERROR "Remill submodule dependencies not found. Did you run 'git submodule update --init --recursive'?")
endif()

simple_git(https://github.com/gflags/gflags 52e94563eba1968783864942fedf6e87e3c611f4
)
simple_git(https://github.com/google/glog v0.7.1
    "-DGFLAGS_USE_TARGET_NAMESPACE:STRING=ON"
    "-DBUILD_TESTING:STRING=OFF"
)
simple_git(https://github.com/google/googletest v1.17.0
    "-Dgtest_force_shared_crt:STRING=ON"
    "-DGFLAGS_USE_TARGET_NAMESPACE:STRING=ON"
)

# Reuse remill's XED recipe and XEDConfig.cmake.in verbatim. Current remill
# uses CMAKE_CURRENT_SOURCE_DIR for its template lookup; keep this compatibility
# shim until the CMAKE_CURRENT_LIST_DIR fix is available upstream.
set(_dependencies_current_source_dir "${CMAKE_CURRENT_SOURCE_DIR}")
set(CMAKE_CURRENT_SOURCE_DIR "${remill_dependencies_dir}")
include("${remill_dependencies_dir}/xed.cmake")
set(CMAKE_CURRENT_SOURCE_DIR "${_dependencies_current_source_dir}")
unset(_dependencies_current_source_dir)

set(LLVM_CONFIG "${CMAKE_INSTALL_PREFIX}/lib/cmake/llvm/LLVMConfig.cmake")
if(USE_EXTERNAL_LLVM)
    # Create a forwarding LLVMConfig.cmake file that adds the external LLVM to CMAKE_PREFIX_PATH
    # and then includes the external LLVMConfig.cmake
    if(NOT EXISTS "${LLVM_DIR}/LLVMConfig.cmake")
        message(FATAL_ERROR "LLVMConfig.cmake not found in LLVM_DIR (${LLVM_DIR})")
    endif()
    file(WRITE "${CMAKE_INSTALL_PREFIX}/lib/cmake/llvm/LLVMConfig.cmake"
        "if(NOT \"${LLVM_INSTALL_PREFIX}\" IN_LIST CMAKE_PREFIX_PATH)\n"
        "  list(PREPEND CMAKE_PREFIX_PATH \"${LLVM_INSTALL_PREFIX}\")\n"
        "  set(CMAKE_PREFIX_PATH \"\${CMAKE_PREFIX_PATH}\" CACHE PATH \"\" FORCE)\n"
        "  message(STATUS \"Updating CMAKE_PREFIX_PATH: \${CMAKE_PREFIX_PATH}\")\n"
        "endif()\n"
        "include(\"${LLVM_DIR}/LLVMConfig.cmake\")\n"
    )
elseif(DOWNLOAD_PREBUILT_LLVM)
    include(llvm-prebuilt.cmake)
else()
    file(REMOVE "${LLVM_CONFIG}")
    include(llvm.cmake)
endif()

if(ENABLE_SLEIGH)
    file(GLOB sleigh_patches LIST_DIRECTORIES FALSE
        "${remill_dependencies_dir}/sleigh_patches/*.patch"
    )
    list(SORT sleigh_patches)

    if(NOT sleigh_patches)
        message(FATAL_ERROR "ENABLE_SLEIGH did not find any patches in sleigh_patches")
    endif()

    string(REPLACE ";" "\\;" sleigh_patches_arg "${sleigh_patches}")

    simple_git(https://github.com/lifting-bits/sleigh 7c6b742
        "-Dsleigh_ADDITIONAL_PATCHES:STRING=${sleigh_patches_arg}"
        "-Dsleigh_ENABLE_TESTS:BOOL=OFF"
        "-Dsleigh_RELEASE_TYPE:STRING=HEAD"
        "-Dsleigh_BUILD_SUPPORT:BOOL=ON"
        "-Dsleigh_BUILD_SLEIGHSPECS:BOOL=ON"
    )

    ExternalProject_Add_Step(sleigh ppc_e200_spec_install
        COMMAND
            "${CMAKE_COMMAND}"
            "-Dinstall_prefix:PATH=${CMAKE_INSTALL_PREFIX}"
            "-Dbinary_dir:PATH=<BINARY_DIR>"
            -P "${remill_dependencies_dir}/build_ppc_e200_sla.cmake"
        DEPENDEES install
    )
endif()
