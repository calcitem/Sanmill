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
if command -v gcc > /devontinue; then
    GCC_VER=$(gcc -dumpversion)
    echo "GCC version $GCC_VER detected."
elif command -v clang > /dev/null; then
    CLANG_VER=$(clang --version | grep version | awk '{print $3}')
    echo "Clang version $CLANG_VER detected."
else
    echo "No suitable compiler found."
    exit 1
fi

# Generate project files for Debug
cmake -G "Unix Makefiles" -DCMAKE_PREFIX_PATH="$Qt6_DIR" -DCMAKE_BUILD_TYPE=Debug $EXTRA_CMAKE_FLAGS -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=Debug .

# Build and deploy Debug version
cmake --build . --target mill-pro --config Debug -j

# Generate project files for Release
cmake -G "Unix Makefiles" -DCMAKE_PREFIX_PATH="$Qt6_DIR" -DCMAKE_BUILD_TYPE=Release $EXTRA_CMAKE_FLAGS -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=Release .

# Build and deploy Release version
cmake --build . --target mill-pro --config Release -j
