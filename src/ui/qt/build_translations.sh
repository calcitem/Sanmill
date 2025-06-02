#!/bin/bash

echo "Building translation files..."

# Create translations directory if it doesn't exist
mkdir -p translations

# Compile .ts files to .qm files using lrelease
echo "Compiling English translation..."
lrelease translations/mill-pro_en.ts -qm translations/mill-pro_en.qm

echo "Compiling German translation..."
lrelease translations/mill-pro_de.ts -qm translations/mill-pro_de.qm

echo "Compiling Hungarian translation..."
lrelease translations/mill-pro_hu.ts -qm translations/mill-pro_hu.qm

echo "Compiling Chinese translation..."
lrelease translations/mill-pro_zh_CN.ts -qm translations/mill-pro_zh_CN.qm

echo "Translation files built successfully!" 