# dependencies

Standalone dependencies for remill based on [LLVMParty/packages](https://github.com/LLVMParty/packages) (superbuild pattern).

This builds remill's third-party dependencies (gflags, glog, XED, and sleigh). By default it also downloads and extracts the LLVMParty LLVM 21.1.6 prebuilt for the current target into the install prefix. Set `USE_EXTERNAL_LLVM=ON` to use an existing LLVM, or `DOWNLOAD_PREBUILT_LLVM=OFF` to compile LLVM 21.1.6 from source instead. Remill itself is built by the main project via `add_subdirectory(dependencies/remill)`, and this superbuild reuses remill's own sleigh patches from `dependencies/remill/dependencies`.

## Building

```sh
git submodule update --init --recursive
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

This will create a [CMake prefix](https://cmake.org/cmake/help/latest/command/find_package.html#search-procedure). The main project automatically detects the default `dependencies/install` prefix; for non-default locations, pass it with `-DCMAKE_PREFIX_PATH:PATH=/path/to/dependencies/install`. See [presentation.md](https://github.com/LLVMParty/packages/blob/main/presentation.md) and [dependencies.md](https://github.com/LLVMParty/packages/blob/main/dependencies.md) for more information.

## Docker

```sh
export TAG="ghcr.io/llvmparty/remill-template/dependencies:22.04-llvm21.1.1"
docker buildx build --platform linux/arm64 -t "$TAG" .
docker buildx build --platform linux/amd64 -t "$TAG" .
docker buildx build --platform linux/arm64,linux/amd64 -t "$TAG" .
docker push "$TAG"
```
