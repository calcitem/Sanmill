#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

# Automated integration test runner with OS detection and directory handling

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect operating system
detect_os() {
    local os_type=""

    case "$(uname -s)" in
        Linux*)
            os_type="linux"
            ;;
        Darwin*)
            os_type="macos"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            os_type="windows"
            ;;
        *)
            print_error "Unsupported operating system: $(uname -s)"
            exit 1
            ;;
    esac

    echo "$os_type"
}

# Get script directory (repository root)
get_script_dir() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$script_dir"
}

# Change to flutter app directory
change_to_flutter_dir() {
    local repo_root="$1"
    local flutter_dir="$repo_root/src/ui/flutter_app"

    if [ ! -d "$flutter_dir" ]; then
        print_error "Flutter app directory not found: $flutter_dir"
        exit 1
    fi

    cd "$flutter_dir"
    print_info "Changed directory to: $(pwd)"
}

# Check if Flutter is available
check_flutter() {
    if ! command -v flutter &> /dev/null; then
        print_error "Flutter command not found. Please install Flutter first."
        exit 1
    fi

    print_info "Flutter version:"
    flutter --version | head -n 1
}

# Run single test case
run_single_test() {
    local device="$1"

    print_info "Running single test case on device: $device"
    print_info "Test file: integration_test/automated_move_single_test.dart"
    echo ""

    flutter test integration_test/automated_move_single_test.dart -d "$device"
}

# Run complete integration tests
run_full_test() {
    local device="$1"

    print_info "Running complete integration tests on device: $device"
    print_info "Test file: integration_test/automated_move_integration_test.dart"
    echo ""

    flutter test integration_test/automated_move_integration_test.dart -d "$device"
}

# Print usage information
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Automated integration test runner for Sanmill.

OPTIONS:
    -s, --single     Run single test case (automated_move_single_test.dart)
    -f, --full       Run complete integration tests (automated_move_integration_test.dart)
    -d, --device     Specify device (linux/macos/windows), auto-detect if not specified
    -h, --help       Show this help message

EXAMPLES:
    # Run single test with auto-detected OS
    $0 --single

    # Run full tests with auto-detected OS
    $0 --full

    # Run single test on Linux
    $0 --single --device linux

    # Run full tests on macOS
    $0 --full --device macos

EOF
}

# Main function
main() {
    local test_type=""
    local device=""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--single)
                test_type="single"
                shift
                ;;
            -f|--full)
                test_type="full"
                shift
                ;;
            -d|--device)
                device="$2"
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    # Validate test type
    if [ -z "$test_type" ]; then
        print_error "Test type not specified. Use --single or --full"
        print_usage
        exit 1
    fi

    print_info "Starting integration test runner..."
    echo ""

    # Detect or validate device
    if [ -z "$device" ]; then
        device=$(detect_os)
        print_info "Auto-detected operating system: $device"
    else
        # Validate provided device
        case "$device" in
            linux|macos|windows)
                print_info "Using specified device: $device"
                ;;
            *)
                print_error "Invalid device: $device. Use linux, macos, or windows"
                exit 1
                ;;
        esac
    fi
    echo ""

    # Get repository root and change to flutter directory
    local repo_root=$(get_script_dir)
    print_info "Repository root: $repo_root"
    change_to_flutter_dir "$repo_root"
    echo ""

    # Check Flutter installation
    check_flutter
    echo ""

    # Run the appropriate test
    case "$test_type" in
        single)
            run_single_test "$device"
            ;;
        full)
            run_full_test "$device"
            ;;
    esac

    echo ""
    print_success "Test execution completed!"
}

# Run main function with all arguments
main "$@"
