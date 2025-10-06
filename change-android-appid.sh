#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

# Script to change Android application ID for Sanmill Flutter app
# Usage: ./change-android-appid.sh <old_appid> <new_appid>
# Example: ./change-android-appid.sh com.calcitem.sanmill com.calcitem.sanmill68

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check arguments
if [ $# -ne 2 ]; then
    print_error "Usage: $0 <old_appid> <new_appid>"
    print_error "Example: $0 com.calcitem.sanmill com.calcitem.sanmill68"
    exit 1
fi

OLD_APPID="$1"
NEW_APPID="$2"

# Validate appid format
if [[ ! "$OLD_APPID" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]]; then
    print_error "Invalid old appid format: $OLD_APPID"
    exit 1
fi

if [[ ! "$NEW_APPID" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]]; then
    print_error "Invalid new appid format: $NEW_APPID"
    exit 1
fi

print_info "Changing Android Application ID from '$OLD_APPID' to '$NEW_APPID'"

# Convert appid to path (com.calcitem.sanmill -> com/calcitem/sanmill)
OLD_PATH="${OLD_APPID//./\/}"
NEW_PATH="${NEW_APPID//./\/}"

# Convert appid to JNI format (com.calcitem.sanmill -> com_calcitem_sanmill)
OLD_JNI="${OLD_APPID//./_}"
NEW_JNI="${NEW_APPID//./_}"

FLUTTER_APP_DIR="src/ui/flutter_app"
ANDROID_DIR="$FLUTTER_APP_DIR/android"

# Check if flutter app directory exists
if [ ! -d "$FLUTTER_APP_DIR" ]; then
    print_error "Flutter app directory not found: $FLUTTER_APP_DIR"
    exit 1
fi

# Step 1: Update build.gradle files
print_info "Step 1: Updating build.gradle files..."
GRADLE_FILES=(
    "$ANDROID_DIR/app/build.gradle"
    "$ANDROID_DIR/app/build.gradle_github"
    "$ANDROID_DIR/app/build.gradle_fdroid"
)

for gradle_file in "${GRADLE_FILES[@]}"; do
    if [ -f "$gradle_file" ]; then
        print_info "  Updating $gradle_file"
        sed -i "s/namespace \"$OLD_APPID\"/namespace \"$NEW_APPID\"/g" "$gradle_file"
        sed -i "s/applicationId \"$OLD_APPID\"/applicationId \"$NEW_APPID\"/g" "$gradle_file"
    else
        print_warn "  File not found: $gradle_file"
    fi
done

# Step 2: Update AndroidManifest.xml files
print_info "Step 2: Updating AndroidManifest.xml files..."
MANIFEST_FILES=(
    "$ANDROID_DIR/app/src/main/AndroidManifest.xml"
    "$ANDROID_DIR/app/src/debug/AndroidManifest.xml"
    "$ANDROID_DIR/app/src/profile/AndroidManifest.xml"
)

for manifest_file in "${MANIFEST_FILES[@]}"; do
    if [ -f "$manifest_file" ]; then
        print_info "  Updating $manifest_file"
        sed -i "s/package=\"$OLD_APPID\"/package=\"$NEW_APPID\"/g" "$manifest_file"
    else
        print_warn "  File not found: $manifest_file"
    fi
done

# Step 3: Update Java files and move to new directory
print_info "Step 3: Updating Java files..."
OLD_JAVA_DIR="$ANDROID_DIR/app/src/main/java/$OLD_PATH"
NEW_JAVA_DIR="$ANDROID_DIR/app/src/main/java/$NEW_PATH"

if [ -d "$OLD_JAVA_DIR" ]; then
    # Create new directory
    print_info "  Creating new directory: $NEW_JAVA_DIR"
    mkdir -p "$NEW_JAVA_DIR"
    
    # Update package declaration in Java files and copy to new location
    for java_file in "$OLD_JAVA_DIR"/*.java; do
        if [ -f "$java_file" ]; then
            filename=$(basename "$java_file")
            print_info "  Processing $filename"
            sed "s/package $OLD_APPID;/package $NEW_APPID;/g" "$java_file" > "$NEW_JAVA_DIR/$filename"
        fi
    done
    
    # Update MethodChannel names in MainActivity.java if it exists
    MAIN_ACTIVITY="$NEW_JAVA_DIR/MainActivity.java"
    if [ -f "$MAIN_ACTIVITY" ]; then
        print_info "  Updating MethodChannel names in MainActivity.java"
        sed -i "s/\"$OLD_APPID\//\"$NEW_APPID\//g" "$MAIN_ACTIVITY"
    fi
    
    # Remove old directory
    print_info "  Removing old directory: $OLD_JAVA_DIR"
    rm -rf "$OLD_JAVA_DIR"
else
    print_warn "  Old Java directory not found: $OLD_JAVA_DIR"
fi

# Step 4: Update Flutter Dart MethodChannel names
print_info "Step 4: Updating Flutter Dart MethodChannel names..."
DART_FILES=(
    "$FLUTTER_APP_DIR/lib/game_page/services/engine/engine.dart"
    "$FLUTTER_APP_DIR/lib/shared/services/native_methods.dart"
    "$FLUTTER_APP_DIR/lib/shared/services/system_ui_service.dart"
)

for dart_file in "${DART_FILES[@]}"; do
    if [ -f "$dart_file" ]; then
        print_info "  Updating $dart_file"
        sed -i "s/'$OLD_APPID\//'$NEW_APPID\//g" "$dart_file"
        sed -i "s/\"$OLD_APPID\//\"$NEW_APPID\//g" "$dart_file"
    else
        print_warn "  File not found: $dart_file"
    fi
done

# Step 5: Update JNI function names in C++ code
print_info "Step 5: Updating JNI function names in C++ code..."
JNI_FILE="$FLUTTER_APP_DIR/command/mill_engine.cpp"

if [ -f "$JNI_FILE" ]; then
    print_info "  Updating $JNI_FILE"
    sed -i "s/Java_${OLD_JNI}_MillEngine_/Java_${NEW_JNI}_MillEngine_/g" "$JNI_FILE"
else
    print_warn "  File not found: $JNI_FILE"
fi

# Step 6: Summary
print_info ""
print_info "=========================================="
print_info "Application ID change completed!"
print_info "=========================================="
print_info "Old Application ID: $OLD_APPID"
print_info "New Application ID: $NEW_APPID"
print_info ""
print_info "Modified files:"
print_info "  - ${#GRADLE_FILES[@]} build.gradle files"
print_info "  - ${#MANIFEST_FILES[@]} AndroidManifest.xml files"
print_info "  - Java files in $NEW_JAVA_DIR"
print_info "  - ${#DART_FILES[@]} Dart files"
print_info "  - 1 C++ JNI file"
print_info ""
print_warn "Next steps:"
print_warn "  1. Review changes: git diff"
print_warn "  2. Run formatting: ./format.sh s"
print_warn "  3. Test the app to ensure everything works"
print_warn "  4. Commit changes: git add . && git commit"
print_info ""

