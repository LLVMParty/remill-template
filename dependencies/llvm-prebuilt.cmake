include_guard()

set(LLVM_PREBUILT_VERSION "21.1.6" CACHE STRING "LLVM prebuilt package version")
set(LLVM_PREBUILT_BASE_URL "https://github.com/LLVMParty/llvm-builds/releases/download/v${LLVM_PREBUILT_VERSION}" CACHE STRING "Base URL for LLVM prebuilt packages")

# CMAKE_SYSTEM_NAME and CMAKE_SYSTEM_PROCESSOR describe the target platform
# after project() has run (from the toolchain file when cross-compiling, or the
# host platform otherwise).
string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" LLVM_PREBUILT_ARCH)
if(LLVM_PREBUILT_ARCH MATCHES "^(x86_64|amd64)$")
    set(LLVM_PREBUILT_ARCH "x86_64")
elseif(LLVM_PREBUILT_ARCH MATCHES "^(aarch64|arm64)$")
    set(LLVM_PREBUILT_ARCH "aarch64")
else()
    message(FATAL_ERROR "Unsupported target architecture for prebuilt LLVM: ${CMAKE_SYSTEM_PROCESSOR}")
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    if(LLVM_PREBUILT_ARCH STREQUAL "aarch64")
        set(LLVM_PREBUILT_PLATFORM "linux-aarch64")
        set(LLVM_PREBUILT_SHA256 "e8a1fbc55c79829c95acb43a8d030d98019ed7ce1f37190f0b42c480ff0dac60")
    elseif(LLVM_PREBUILT_ARCH STREQUAL "x86_64")
        set(LLVM_PREBUILT_PLATFORM "linux-x86_64")
        set(LLVM_PREBUILT_SHA256 "044b81eb35eea66c7d30211b04cbbd75c969e40e19746ba78a5e0949899b9d78")
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    if(LLVM_PREBUILT_ARCH STREQUAL "aarch64")
        set(LLVM_PREBUILT_PLATFORM "macos-arm64")
        set(LLVM_PREBUILT_SHA256 "a20fc529a9a98d0fd135075d108de8b7a1080e23ee1eaa9c234d95b77e7ed17e")
    elseif(LLVM_PREBUILT_ARCH STREQUAL "x86_64")
        set(LLVM_PREBUILT_PLATFORM "macos-x86_64")
        set(LLVM_PREBUILT_SHA256 "4b752368d4e06d4db2ab39191bbbfce6bca9f0acf4f3490cc1ab56c26fce8c36")
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    # The Windows package is MSVC-ABI only.
    if(NOT (MSVC OR CMAKE_CXX_SIMULATE_ID STREQUAL "MSVC"))
        message(FATAL_ERROR
            "The prebuilt LLVM Windows package requires the MSVC ABI "
            "(cl.exe, clang-cl.exe, or clang.exe with an MSVC target). "
            "Detected compiler: ${CMAKE_CXX_COMPILER_ID} "
            "(simulate: ${CMAKE_CXX_SIMULATE_ID})")
    endif()

    if(LLVM_PREBUILT_ARCH STREQUAL "x86_64")
        set(LLVM_PREBUILT_PLATFORM "windows-x86_64")
        set(LLVM_PREBUILT_SHA256 "487c54cd16209aa1bdeabc79508167177d4e461e8504029d98bb04473d9164a4")
    endif()
endif()

if(NOT DEFINED LLVM_PREBUILT_PLATFORM)
    message(FATAL_ERROR "No prebuilt LLVM package available for ${CMAKE_SYSTEM_NAME} ${CMAKE_SYSTEM_PROCESSOR}")
endif()

set(LLVM_PREBUILT_FILENAME "llvm-${LLVM_PREBUILT_VERSION}-${LLVM_PREBUILT_PLATFORM}.zip")
set(LLVM_PREBUILT_URL "${LLVM_PREBUILT_BASE_URL}/${LLVM_PREBUILT_FILENAME}")
set(LLVM_PREBUILT_ARCHIVE "${CMAKE_CURRENT_BINARY_DIR}/downloads/${LLVM_PREBUILT_FILENAME}")
set(LLVM_PREBUILT_STAMP "${CMAKE_INSTALL_PREFIX}/.llvm-prebuilt-${LLVM_PREBUILT_VERSION}-${LLVM_PREBUILT_PLATFORM}")
set(LLVM_DIR "${CMAKE_INSTALL_PREFIX}/lib/cmake/llvm" CACHE PATH "Path to LLVMConfig.cmake" FORCE)

message(STATUS "Fetching prebuilt LLVM: ${LLVM_PREBUILT_FILENAME}")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/downloads")
file(DOWNLOAD
    "${LLVM_PREBUILT_URL}"
    "${LLVM_PREBUILT_ARCHIVE}"
    EXPECTED_HASH "SHA256=${LLVM_PREBUILT_SHA256}"
    SHOW_PROGRESS
    STATUS LLVM_PREBUILT_DOWNLOAD_STATUS
    LOG LLVM_PREBUILT_DOWNLOAD_LOG
)
list(GET LLVM_PREBUILT_DOWNLOAD_STATUS 0 LLVM_PREBUILT_DOWNLOAD_CODE)
if(NOT LLVM_PREBUILT_DOWNLOAD_CODE EQUAL 0)
    list(GET LLVM_PREBUILT_DOWNLOAD_STATUS 1 LLVM_PREBUILT_DOWNLOAD_MESSAGE)
    message(FATAL_ERROR
        "Failed to download ${LLVM_PREBUILT_URL}: ${LLVM_PREBUILT_DOWNLOAD_MESSAGE}\n"
        "${LLVM_PREBUILT_DOWNLOAD_LOG}")
endif()

if(NOT EXISTS "${LLVM_PREBUILT_STAMP}" OR NOT EXISTS "${LLVM_DIR}/LLVMConfig.cmake")
    message(STATUS "Extracting ${LLVM_PREBUILT_FILENAME} to ${CMAKE_INSTALL_PREFIX}")
    file(ARCHIVE_EXTRACT
        INPUT "${LLVM_PREBUILT_ARCHIVE}"
        DESTINATION "${CMAKE_INSTALL_PREFIX}"
    )
    file(WRITE "${LLVM_PREBUILT_STAMP}"
        "LLVM_PREBUILT_VERSION=${LLVM_PREBUILT_VERSION}\n"
        "LLVM_PREBUILT_PLATFORM=${LLVM_PREBUILT_PLATFORM}\n"
        "LLVM_PREBUILT_SHA256=${LLVM_PREBUILT_SHA256}\n"
    )
else()
    message(STATUS "Prebuilt LLVM already installed at ${CMAKE_INSTALL_PREFIX}")
endif()

if(NOT EXISTS "${LLVM_DIR}/LLVMConfig.cmake")
    message(FATAL_ERROR "Prebuilt LLVM did not provide ${LLVM_DIR}/LLVMConfig.cmake")
endif()

message(STATUS "Prebuilt LLVM available at: ${CMAKE_INSTALL_PREFIX}")
