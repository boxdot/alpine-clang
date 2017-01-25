#!/bin/sh
set -ex

version=release_39
prefix=/tmp/llvm
src=$prefix/src

install_tools() {
    apk --no-cache add build-base git cmake ninja python2
}

download() {
    mkdir -p $src

    url=https://github.com/llvm-mirror
    git clone --depth 1 --branch $version --single-branch $url/llvm.git $src

    ( cd $src/tools && git clone --depth 1 --branch $version $url/clang.git )
    ( cd $src/projects && git clone --depth 1 --branch $version $url/compiler-rt )
    ( cd $src/projects && git clone --depth 1 --branch $version $url/libcxx )
    ( cd $src/projects && git clone --depth 1 --branch $version $url/libcxxabi )
    ( cd $src/projects && git clone --depth 1 --branch $version $url/libunwind )
}

apply_patch() {
    cd $src
    patch -p1 < /root/llvm-0001-Fix-build-with-musl-libc.patch
    patch -p1 < /root/llvm-0002-Fix-DynamicLibrary-to-build-with-musl-libc.patch

    cd $src/projects/libcxx
    patch -p1 < /root/cxx-0001-Check-for-musl-libcs-max_align_t.patch
    # TODO: this patch should not be needed, since we set the
    #       DLIBCXX_HAS_MUSL_LIBC flag in the configuration. However, for some
    #       files in libc++abi the flag is not propagated. Bug?!
    patch -p1 < /root/cxx-0002-Enable-musl-libc-in-config.patch
}

# stage 0: build only clang
stage0() {
    mkdir -p $src/stage0
    cd $src/stage0
    cmake .. -GNinja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=$prefix/stage0 \
        -DLLVM_BINUTILS_INCDIR=/usr/include \
        -DLLVM_BUILD_DOCS=NO \
        -DLLVM_BUILD_EXAMPLES=NO \
        -DLLVM_BUILD_RUNTIME:BOOL=OFF \
        -DLLVM_BUILD_TESTS=NO \
        -DLLVM_DEFAULT_TARGET_TRIPLE=x86_64-alpine-linux-musl \
        -DLLVM_ENABLE_ASSERTIONS=NO \
        -DLLVM_ENABLE_CXX1Y=YES \
        -DLLVM_ENABLE_FFI=NO \
        -DLLVM_ENABLE_LIBCXX=NO \
        -DLLVM_ENABLE_PIC=YES \
        -DLLVM_ENABLE_RTTI=YES \
        -DLLVM_ENABLE_SPHINX=NO \
        -DLLVM_ENABLE_TERMINFO=YES \
        -DLLVM_ENABLE_ZLIB=YES \
        -DLLVM_HOST_TRIPLE=x86_64-alpine-linux-musl \
        -DLLVM_INCLUDE_EXAMPLES=NO
    ninja clang
    ninja install-clang
    cmake -P tools/clang/lib/Headers/cmake_install.cmake
}

# compile libc++, libc++abi and libunwind with clang from stage0

# TODO: Technically, there will be no runtime dependency to gcc and libstdc++
#       in these libraries, however we used at least libstdc++ to compile
#       libc++.
# TODO: compiler-rt is compiled, but not installed.
stage1() {
    mkdir -p $src/stage1
    cd $src/stage1
    cmake .. -GNinja \
        -DCMAKE_C_COMPILER=$prefix/stage0/bin/clang \
        -DCMAKE_CXX_COMPILER=$prefix/stage0/bin/clang++ \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DLLVM_BINUTILS_INCDIR=/usr/include \
        -DLLVM_BUILD_DOCS=NO \
        -DLLVM_BUILD_EXAMPLES=NO \
        -DLLVM_BUILD_RUNTIME:BOOL=ON \
        -DLLVM_BUILD_TESTS=NO \
        -DLLVM_DEFAULT_TARGET_TRIPLE=x86_64-alpine-linux-musl \
        -DLLVM_ENABLE_ASSERTIONS=NO \
        -DLLVM_ENABLE_CXX1Y=YES \
        -DLLVM_ENABLE_FFI=NO \
        -DLLVM_ENABLE_LIBCXX=NO \
        -DLLVM_ENABLE_PIC=YES \
        -DLLVM_ENABLE_RTTI=YES \
        -DLLVM_ENABLE_SPHINX=NO \
        -DLLVM_ENABLE_TERMINFO=YES \
        -DLLVM_ENABLE_ZLIB=YES \
        -DLLVM_HOST_TRIPLE=x86_64-alpine-linux-musl \
        -DLLVM_INCLUDE_EXAMPLES=NO \
        \
        -DLIBCXX_HAS_MUSL_LIBC:BOOL=ON \
        -DLIBCXX_HAS_GCC_S_LIB:BOOL=OFF \
        -DLIBCXXABI_TARGET_TRIPLE=x86_64-alpine-linux-musl \
        -DLIBCXXABI_USE_COMPILER_RT:BOOL=ON \
        -DLIBCXXABI_USE_LLVM_UNWINDER:BOOL=ON \
        \
        -DLIBUNWIND_TARGET_TRIPLE=x86_64-alpine-linux-musl \
        \
        -DCOMPILER_RT_DEFAULT_TARGET_TRIPLE=x86_64-alpine-linux-musl \
        -DCOMPILER_RT_BUILD_BUILTINS=ON \
        -DCOMPILER_RT_BUILD_SANITIZERS=ON
    ninja cxx
    ninja install-libcxx install-libcxxabi
    cmake -P projects/libunwind/cmake_install.cmake
}

# compile clang with clang from stage0, and libc++, libc++abi and libunwind
# from stage1
stage2() {
    mkdir -p $src/stage2
    cd $src/stage2
    cmake .. -GNinja \
        -DCMAKE_C_COMPILER=$prefix/stage0/bin/clang \
        -DCMAKE_CXX_COMPILER=$prefix/stage0/bin/clang++ \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DLLVM_BINUTILS_INCDIR=/usr/include \
        -DLLVM_BUILD_DOCS=NO \
        -DLLVM_BUILD_EXAMPLES=NO \
        -DLLVM_BUILD_RUNTIME:BOOL=OFF \
        -DLLVM_BUILD_TESTS=NO \
        -DLLVM_DEFAULT_TARGET_TRIPLE=x86_64-alpine-linux-musl \
        -DLLVM_ENABLE_ASSERTIONS=NO \
        -DLLVM_ENABLE_CXX1Y=YES \
        -DLLVM_ENABLE_FFI=NO \
        -DLLVM_ENABLE_LIBCXX=YES \
        -DLLVM_ENABLE_LIBCXXABI=YES \
        -DLLVM_ENABLE_PIC=YES \
        -DLLVM_ENABLE_RTTI=YES \
        -DLLVM_ENABLE_SPHINX=NO \
        -DLLVM_ENABLE_TERMINFO=YES \
        -DLLVM_ENABLE_ZLIB=YES \
        -DLLVM_HOST_TRIPLE=x86_64-alpine-linux-musl \
        -DLLVM_INCLUDE_EXAMPLES=NO \
        \
        -DCLANG_DEFAULT_CXX_STDLIB=libc++
    ninja clang
    ninja install-clang
    cmake -P tools/clang/lib/Headers/cmake_install.cmake
}

cleanup() {
    rm -rf /tmp/llvm
    apk del --purge build-base python2
    # TODO: I would like to remove gcc as well, however we still need gcc for crtbegin.o, etc... Can
    #       we use something, which corresponds to those object files from llvm/clang?
    apk --no-cache add binutils libc-dev make gcc
}

install_tools
download
apply_patch
stage0
stage1
stage2
cleanup
