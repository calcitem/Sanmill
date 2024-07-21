#!/bin/bash
set -e

# Clean repository
git clean -fdx

# Detect Qt installation and set Qt6_DIR
Qt6_BIN=$(dirname "$(which qmake 2>/dev/null)")
Qt6_DIR="${Qt6_BIN%/bin}"

if [[ -z "$Qt6_DIR" ]]; then
    echo "Qt6 installation not found."
    exit 1
fi

# Detect system architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    ARCH="ARM64"
else
    ARCH="x86_64"
fi

# Detect compiler version
if command -v gcc > /dev/null; then
    GCC_VER=$(gcc -dumpversion)
    echo "GCC version $GCC_VER detected."
    C_COMPILER=gcc
    CXX_COMPILER=g++
elif command -v clang > /dev/null; then
    CLANG_VER=$(clang --version | grep version | awk '{print $3}')
    echo "Clang version $CLANG_VER detected."
    C_COMPILER=clang
    CXX_COMPILER=clang++
else
    echo "No suitable compiler found."
    exit 1
fi

# Function to generate and build project
build_project() {
    local build_type=$1
    local generator=$2

    cmake -G "$generator" -DCMAKE_PREFIX_PATH="$Qt6_DIR" -DCMAKE_BUILD_TYPE="$build_type" $EXTRA_CMAKE_FLAGS -DCMAKE_C_COMPILER=$C_COMPILER -DCMAKE_CXX_COMPILER=$CXX_COMPILER .
    cmake --build . --target mill-pro --config "$build_type" -j
}

# Detect operating system
OS=$(uname)

if [[ "$OS" == "Darwin" ]]; then
    # macOS: Generate and build project using Xcode
    build_project Debug "Xcode"
    build_project Release "Xcode"
else
    # Linux: Generate and build project using Unix Makefiles
    build_project Debug "Unix Makefiles"
    build_project Release "Unix Makefiles"
fi
