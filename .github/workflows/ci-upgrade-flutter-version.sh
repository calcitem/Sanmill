#!/bin/bash

# Get the version of Flutter
FLUTTER_VERSION=$(flutter --version | awk 'NR==1{print $2}')

# Export the version for use in sed
export FLUTTER_VERSION

# Determine operating system
OS="$(uname)"

# Find all .yml files in the current directory and replace the version
case "$OS" in
  Linux* | MINGW64_NT*)
    find . -name '*.yml' -exec sh -c '
      sed -i "s/flutter-version: .*/flutter-version: '\''${FLUTTER_VERSION}'\''/" $1
    ' sh {} \;
    ;;
  Darwin*)
    find . -name '*.yml' -exec sh -c '
      sed -i "" "s/flutter-version: .*/flutter-version: '\''${FLUTTER_VERSION}'\''/" $1
    ' sh {} \;
    ;;
esac

# Add all changed files to git
git add .

# Commit the changes
git commit -m "ci: Upgrade Flutter to v${FLUTTER_VERSION}"

# Push the changes
#git push
