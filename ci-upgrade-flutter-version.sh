#!/bin/bash

# Get the version of Flutter by executing the `flutter` command and using `awk` to parse the output
FLUTTER_VERSION=$(flutter --version | awk 'NR==1{print $2}')

# Export the FLUTTER_VERSION variable so it can be used in the subshell spawned by find/exec
export FLUTTER_VERSION

# Determine the operating system type using `uname`
OS="$(uname)"

# Navigate to the .github/workflows directory to perform version replacement in YAML files
cd .github/workflows

# Based on the OS type, find all .yml files and replace the flutter-version with the retrieved FLUTTER_VERSION
case "$OS" in
  Linux* | MINGW64_NT*)
    # For Linux and Windows (MINGW), using sed without an empty argument for in-place editing
    find . -name '*.yml' -exec sh -c '
      sed -i "s/flutter-version: .*/flutter-version: '\''${FLUTTER_VERSION}'\''/" $1
    ' sh {} \;
    ;;
  Darwin*)
    # For macOS, using sed with an empty argument "" for in-place editing
    find . -name '*.yml' -exec sh -c '
      sed -i "" "s/flutter-version: .*/flutter-version: '\''${FLUTTER_VERSION}'\''/" $1
    ' sh {} \;
    ;;
esac

# Navigate back to the root directory
cd ../..

# Navigate to the snap directory
cd snap

# Again, based on the OS type, find all .yml files and replace the flutter Linux version string
case "$OS" in
  Linux* | MINGW64_NT*)
    find . -name '*.yaml' -exec sh -c '
      sed -i "s/flutter_linux_[0-9]*\.[0-9]*\.[0-9]*/flutter_linux_'${FLUTTER_VERSION}'/" $1
    ' sh {} \;
    ;;
  Darwin*)
    find . -name '*.yaml' -exec sh -c '
      sed -i "" "s/flutter_linux_[0-9]*\.[0-9]*\.[0-9]*/flutter_linux_'${FLUTTER_VERSION}'/" $1
    ' sh {} \;
    ;;
esac

# Navigate back to the root directory
cd ..

# Add all changed files to the staging area of git
git add .

# Commit the changes with a message indicating the upgrade of Flutter version
git commit -m "ci: Upgrade Flutter to v${FLUTTER_VERSION}"

# Uncomment the line below if you want to push changes automatically. Be sure to check the changes before pushing.
#git push
