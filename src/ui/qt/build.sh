#!/bin/bash
set -e

echo "Building Mill Game with multi-language support..."

# Clean repository
git clean -fdx

# Function to detect Qt installation
detect_qt_installation() {
    # Try to find qmake in PATH first
    local qmake_path=$(which qmake 2>/dev/null || true)
    
    if [[ -n "$qmake_path" ]]; then
        Qt_BASE_DIR=$(dirname "$(dirname "$qmake_path")")
        echo "Qt installation detected via qmake: $Qt_BASE_DIR"
        return 0
    fi
    
    # Common Qt installation paths to check
    local qt_paths=(
        "/opt/Qt/6.9.0/gcc_64"
        "/opt/Qt/6.6.0/gcc_64" 
        "/opt/Qt/6.5.0/gcc_64"
        "/usr/lib/qt6"
        "/usr/local/qt6"
        "$HOME/Qt/6.9.0/gcc_64"
        "$HOME/Qt/6.6.0/gcc_64"
        "/opt/homebrew/opt/qt6"  # macOS Homebrew
        "/usr/local/opt/qt6"     # macOS Homebrew (Intel)
    )
    
    for path in "${qt_paths[@]}"; do
        if [[ -d "$path" && -f "$path/bin/qmake" ]]; then
            Qt_BASE_DIR="$path"
            echo "Qt installation found at: $Qt_BASE_DIR"
            return 0
        fi
    done
    
    return 1
}

# Detect Qt installation
if ! detect_qt_installation; then
    echo "Error: Qt6 installation not found."
    echo "Please ensure Qt6 is installed and either:"
    echo "1. qmake is in your PATH, or"
    echo "2. Qt is installed in one of the standard locations"
    echo ""
    echo "Standard locations checked:"
    echo "  - /opt/Qt/*/gcc_64"
    echo "  - /usr/lib/qt6"
    echo "  - /usr/local/qt6"
    echo "  - \$HOME/Qt/*/gcc_64"
    echo "  - /opt/homebrew/opt/qt6 (macOS)"
    exit 1
fi

echo "Qt Base Directory: $Qt_BASE_DIR"

# Set Qt-related paths
QT_BIN_DIR="$Qt_BASE_DIR/bin"
export PATH="$QT_BIN_DIR:$PATH"

# Check if lrelease tool is available for translation compilation
if command -v lrelease >/dev/null 2>&1; then
    echo "lrelease tool found. Translation compilation will be available."
    lrelease_version=$(lrelease -version 2>&1 | head -1 || echo "Version unknown")
    echo "lrelease version: $lrelease_version"
else
    echo "Warning: lrelease tool not found in PATH."
    echo "Translation files may not be compiled properly."
    echo "Please ensure Qt LinguistTools are installed."
    echo "Qt tools directory: $QT_BIN_DIR"
fi

# Detect system architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    ARCH="ARM64"
    echo "Architecture detected: ARM64"
else
    ARCH="x86_64"
    echo "Architecture detected: x86_64"
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
    echo "Error: No suitable compiler found."
    echo "Please install gcc or clang."
    exit 1
fi

# Compile translation files before building
echo ""
echo "======================================"
echo "Compiling translation files..."
echo "======================================"
if [ -f "build_translations.sh" ]; then
    chmod +x build_translations.sh
    ./build_translations.sh
    if [ $? -ne 0 ]; then
        echo "Warning: Translation compilation failed, but continuing with build..."
    fi
else
    echo "Warning: build_translations.sh not found. Skipping translation compilation."
fi

# Function to generate and build project
build_project() {
    local build_type=$1
    local generator=$2

    echo ""
    echo "======================================"
    echo "Building $build_type version with $generator..."
    echo "======================================"
    
    # Clean CMake cache if it exists to avoid configuration conflicts
    if [ -f "CMakeCache.txt" ]; then
        echo "Cleaning existing CMake cache..."
        rm -f "CMakeCache.txt"
    fi
    
    # Set CMAKE_PREFIX_PATH to Qt base directory
    export CMAKE_PREFIX_PATH="$Qt_BASE_DIR"
    
    echo "CMAKE_PREFIX_PATH: $CMAKE_PREFIX_PATH"
    echo "Qt Base Directory: $Qt_BASE_DIR"
    
    echo "Running CMake configuration..."
    cmake -G "$generator" \
          -DCMAKE_PREFIX_PATH="$Qt_BASE_DIR" \
          -DCMAKE_BUILD_TYPE="$build_type" \
          $EXTRA_CMAKE_FLAGS \
          -DCMAKE_C_COMPILER=$C_COMPILER \
          -DCMAKE_CXX_COMPILER=$CXX_COMPILER .
    
    if [ $? -ne 0 ]; then
        echo "Error: CMake configuration failed for $build_type build."
        echo ""
        echo "Troubleshooting tips:"
        echo "1. Verify Qt installation at: $Qt_BASE_DIR"
        echo "2. Check if Qt LinguistTools component is installed"
        echo "3. Ensure compiler is properly installed"
        echo "4. Try cleaning the build directory and running again"
        exit 1
    fi
    
    echo "Building project..."
    cmake --build . --target mill-pro --config "$build_type" -j
    
    if [ $? -ne 0 ]; then
        echo "Error: $build_type build failed."
        exit 1
    fi
    
    echo "$build_type build completed successfully."
    
    # Copy translation files to build directory if they exist
    copy_translation_files "$build_type"
}

# Function to copy translation files to build directories
copy_translation_files() {
    local build_type=$1
    
    if ls translations/*.qm 1> /dev/null 2>&1; then
        echo "Copying translation files for $build_type build..."
        
        # Create translations directory in the appropriate build location
        if [[ "$OS" == "Darwin" ]]; then
            # macOS: Copy to app bundle if it exists, otherwise to build directory
            if [ -d "$build_type/mill-pro.app" ]; then
                mkdir -p "$build_type/mill-pro.app/Contents/Resources/translations"
                cp translations/*.qm "$build_type/mill-pro.app/Contents/Resources/translations/"
                echo "Translation files copied to $build_type/mill-pro.app/Contents/Resources/translations/"
            else
                mkdir -p "$build_type/translations"
                cp translations/*.qm "$build_type/translations/"
                echo "Translation files copied to $build_type/translations/"
            fi
        else
            # Linux: Copy to build directory
            mkdir -p "$build_type/translations"
            cp translations/*.qm "$build_type/translations/"
            echo "Translation files copied to $build_type/translations/"
        fi
    else
        echo "Warning: No compiled translation files found for $build_type build."
    fi
}

# Detect operating system
OS=$(uname)
echo "Operating System: $OS"

if [[ "$OS" == "Darwin" ]]; then
    # macOS: Generate and build project using Xcode
    echo "Building for macOS using Xcode generator..."
    build_project Debug "Xcode"
    build_project Release "Xcode"
    
    echo ""
    echo "======================================"
    echo "macOS Build Summary"
    echo "======================================"
    echo "Debug build: Debug/mill-pro"
    echo "Release build: Release/mill-pro"
    if [ -d "Debug/mill-pro.app" ]; then
        echo "Debug app bundle: Debug/mill-pro.app"
    fi
    if [ -d "Release/mill-pro.app" ]; then
        echo "Release app bundle: Release/mill-pro.app"
    fi
    
else
    # Linux: Generate and build project using Unix Makefiles
    echo "Building for Linux using Unix Makefiles..."
    build_project Debug "Unix Makefiles"
    build_project Release "Unix Makefiles"
    
    echo ""
    echo "======================================"
    echo "Linux Build Summary"
    echo "======================================"
    echo "Debug executable: Debug/mill-pro"
    echo "Release executable: Release/mill-pro"
fi

echo ""
echo "Multi-language support:"
if ls translations/*.qm 1> /dev/null 2>&1; then
    echo "  ✓ Translation files available in both Debug and Release builds"
    echo "  ✓ Supported languages: English, German, Hungarian, Simplified Chinese"
    echo "  ✓ Translation files location: translations/ directory in build output"
else
    echo "  ✗ Translation files not found - multi-language features may not work"
    echo "  ℹ Run ./build_translations.sh to compile translation files"
fi

echo ""
echo "======================================"
echo "Build completed successfully!"
echo "======================================"
