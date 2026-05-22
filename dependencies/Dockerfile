ARG LLVM_VERSION=22.04-llvm19.1.7

FROM ghcr.io/llvmparty/packages/ubuntu:${LLVM_VERSION} AS build
WORKDIR /tmp
COPY \
    CMakeLists.txt  \
    superbuild.cmake \
    llvm-prebuilt.cmake \
    XEDConfig.cmake.in \
    ./
COPY remill/dependencies ./remill/dependencies

# Build dependencies
RUN \
mkdir /dependencies && \
cmake -B build "-DCMAKE_INSTALL_PREFIX=/dependencies" && \
cmake --build build && \
rm -rf build

# Actual final image
FROM ghcr.io/llvmparty/packages/ubuntu:${LLVM_VERSION} AS dependencies

COPY --from=build /dependencies /dependencies
ENV CMAKE_PREFIX_PATH="/dependencies" \
    LD_LIBRARY_PATH="/dependencies/lib" \
    PATH="/dependencies/bin:$PATH"
