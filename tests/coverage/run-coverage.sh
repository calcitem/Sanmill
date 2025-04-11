#!/bin/bash

# Exit the script immediately if any command exits with a non-zero status
set -e

# Change directory to the source code directory
# Adjust the path as needed based on the script's location
cd ../../src || { echo "Error: Failed to change directory to ../../src"; exit 1; }

# Run the make command with coverage enabled using multiple parallel jobs
# The 'coverage=yes' parameter ensures coverage flags are set
make coverage coverage=yes -j || { echo "Error: Make command failed"; exit 1; }

# Define the path to the generated coverage report
COVERAGE_REPORT="coverage/coverage.html"

# Check if the coverage report exists
if [ ! -f "$COVERAGE_REPORT" ]; then
    echo "Error: Coverage report not found at $COVERAGE_REPORT"
    exit 1
fi

# Function to open the coverage report in the default web browser based on the operating system
open_coverage_report() {
    local report_path="$1"
    
    # Detect the operating system
    local OS_NAME="$(uname -s)"
    
    case "$OS_NAME" in
        Darwin)
            # macOS: Use 'open' to launch Google Chrome with the coverage report
            open "$report_path"
            ;;
        Linux)
            # Linux: Use 'xdg-open' to launch the default web browser with the coverage report
            xdg-open "$report_path"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            # Windows (Cygwin, MinGW, MSYS): Use 'start' to launch the default web browser with the coverage report
            # 'cmd.exe /C start' is used to ensure compatibility within these environments
            cmd.exe /C start "$report_path"
            ;;
        *)
            # Unsupported OS: Inform the user to open the coverage report manually
            echo "Warning: Unsupported OS. Please open $report_path manually in your web browser."
            ;;
    esac
}

# Call the function to open the coverage report
open_coverage_report "$COVERAGE_REPORT"

