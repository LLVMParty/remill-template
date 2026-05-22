# Automatically use the default dependency prefix and normalize relative prefix
# entries before find_package() calls run.

set(DEFAULT_DEPENDENCIES_PREFIX "${CMAKE_SOURCE_DIR}/dependencies/install")

if(NOT CMAKE_PREFIX_PATH AND "$ENV{CMAKE_PREFIX_PATH}" STREQUAL "")
    set(_missing_default_dependencies "")
    foreach(_required_path IN ITEMS
        "${DEFAULT_DEPENDENCIES_PREFIX}/.build_config"
        "${DEFAULT_DEPENDENCIES_PREFIX}/lib/cmake/llvm/LLVMConfig.cmake"
        "${DEFAULT_DEPENDENCIES_PREFIX}/lib/cmake/XED/XEDConfig.cmake"
        "${DEFAULT_DEPENDENCIES_PREFIX}/lib/cmake/gflags/gflags-config.cmake"
        "${DEFAULT_DEPENDENCIES_PREFIX}/lib/cmake/glog/glog-config.cmake"
        "${DEFAULT_DEPENDENCIES_PREFIX}/lib/cmake/sleigh/sleighConfig.cmake"
    )
        if(NOT EXISTS "${_required_path}")
            list(APPEND _missing_default_dependencies "${_required_path}")
        endif()
    endforeach()

    if(_missing_default_dependencies)
        string(REPLACE ";" "\n  " _missing_default_dependencies_message "${_missing_default_dependencies}")
        message(FATAL_ERROR
            "Default dependency prefix is missing or incomplete: ${DEFAULT_DEPENDENCIES_PREFIX}\n"
            "Missing:\n  ${_missing_default_dependencies_message}\n\n"
            "To build the dependencies, run:\n"
            "  git submodule update --init --recursive\n"
            "  cmake -G Ninja -B dependencies/build -S dependencies -DCMAKE_BUILD_TYPE=RelWithDebInfo\n"
            "  cmake --build dependencies/build\n\n"
            "Alternatively specify the prefix manually:\n"
            "  cmake -G Ninja -B build -DCMAKE_PREFIX_PATH:PATH=/path/to/dependencies/install")
    endif()

    set(CMAKE_PREFIX_PATH "${DEFAULT_DEPENDENCIES_PREFIX}" CACHE PATH "CMake package search prefixes" FORCE)
    message(STATUS "Using default dependency prefix: ${CMAKE_PREFIX_PATH}")
endif()

# Normalize relative CMAKE_PREFIX_PATH entries so find_package can locate
# packages under prefixes such as "dependencies/install" consistently.
if(CMAKE_PREFIX_PATH)
    set(_normalized_cmake_prefix_path "")

    foreach(_prefix IN LISTS CMAKE_PREFIX_PATH)
        if(IS_ABSOLUTE "${_prefix}")
            list(APPEND _normalized_cmake_prefix_path "${_prefix}")
        elseif(EXISTS "${CMAKE_SOURCE_DIR}/${_prefix}")
            get_filename_component(_absolute_prefix "${_prefix}" ABSOLUTE BASE_DIR "${CMAKE_SOURCE_DIR}")
            list(APPEND _normalized_cmake_prefix_path "${_absolute_prefix}")
        elseif(EXISTS "${CMAKE_BINARY_DIR}/${_prefix}")
            get_filename_component(_absolute_prefix "${_prefix}" ABSOLUTE BASE_DIR "${CMAKE_BINARY_DIR}")
            list(APPEND _normalized_cmake_prefix_path "${_absolute_prefix}")
        else()
            list(APPEND _normalized_cmake_prefix_path "${_prefix}")
        endif()
    endforeach()

    if(NOT _normalized_cmake_prefix_path STREQUAL CMAKE_PREFIX_PATH)
        set(CMAKE_PREFIX_PATH "${_normalized_cmake_prefix_path}" CACHE PATH "CMake package search prefixes" FORCE)
        message(STATUS "CMAKE_PREFIX_PATH: ${CMAKE_PREFIX_PATH}")
    endif()
endif()
