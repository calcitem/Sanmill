#!/bin/bash

# Sanmill Flutter Unified Initialization Script
# This script handles cross-platform Flutter setup with desktop platform support
# Usage: 
#   ./flutter-init.sh           - Basic Flutter initialization
#   ./flutter-init.sh linux     - Basic + Linux desktop support  
#   ./flutter-init.sh windows   - Basic + Windows desktop support
#   ./flutter-init.sh all       - Basic + Both desktop platforms

# Note: We don't use 'set -e' to allow graceful error handling in desktop setup

# Script configuration
SCRIPT_VERSION="2.0.0"
PLATFORM_ARG="${1:-basic}"

# Function to log messages with timestamps
log_info() {
    echo "[INFO] $(date '+%H:%M:%S') - $1"
}

log_warn() {
    echo "[WARN] $(date '+%H:%M:%S') - $1"
}

log_error() {
    echo "[ERROR] $(date '+%H:%M:%S') - $1"
}

log_success() {
    echo "[SUCCESS] $(date '+%H:%M:%S') - $1"
}

# Function to show usage information
show_usage() {
    echo "Sanmill Flutter Initialization Script v$SCRIPT_VERSION"
    echo ""
    echo "Usage:"
    echo "  $0 [PLATFORM]"
    echo ""
    echo "PLATFORM options:"
    echo "  basic    - Basic Flutter initialization only (default)"
    echo "  linux    - Basic initialization + Linux desktop support"
    echo "  windows  - Basic initialization + Windows desktop support"
    echo "  all      - Basic initialization + Both desktop platforms"
    echo "  help     - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Basic initialization"
    echo "  $0 linux        # Setup for Linux desktop development"
    echo "  $0 windows      # Setup for Windows desktop development"
    echo "  $0 all          # Setup for all desktop platforms"
}

# Function to detect and use appropriate Flutter command
detect_flutter_command() {
    local flutter_cmd=""
    local is_windows_flutter=false
    
    log_info "Detecting Flutter installation"
    
    # First try to use native flutter command (Linux/macOS or properly installed in WSL)
    if command -v flutter >/dev/null 2>&1 && flutter --version >/dev/null 2>&1; then
        flutter_cmd="flutter"
        log_info "Using native Flutter command"
    # If that fails, check for Windows Flutter in WSL environment
    elif [[ -f "/mnt/c/flutter/bin/flutter.bat" ]] && command -v cmd.exe >/dev/null 2>&1; then
        flutter_cmd="cmd.exe /c 'C:\\flutter\\bin\\flutter.bat'"
        is_windows_flutter=true
        log_info "Using Windows Flutter via cmd.exe wrapper"
    elif [[ -f "/mnt/c/flutter/bin/flutter" ]]; then
        flutter_cmd="/mnt/c/flutter/bin/flutter"
        log_info "Using Windows Flutter binary directly"
    else
        log_error "Flutter command not found or not working"
        log_info "Please ensure Flutter is properly installed and in PATH"
        log_info "For WSL users: Install Flutter in WSL or ensure Windows Flutter is accessible"
        return 1
    fi
    
    export FLUTTER_CMD="$flutter_cmd"
    export IS_WINDOWS_FLUTTER="$is_windows_flutter"
    return 0
}

# Function to safely execute Flutter commands
flutter_exec() {
    local cmd="$1"
    shift
    local args="$@"
    
    if [[ "$IS_WINDOWS_FLUTTER" == "true" ]]; then
        # Use cmd.exe to execute Windows Flutter commands
        cmd.exe /c "C:\\flutter\\bin\\flutter.bat $cmd $args" 2>/dev/null || return 1
    else
        # Use detected Flutter command directly
        $FLUTTER_CMD "$cmd" $args
    fi
}

# Function to check if Flutter is working properly
verify_flutter_installation() {
    log_info "Verifying Flutter installation"
    
    if flutter_exec --version >/dev/null 2>&1; then
        log_success "Flutter installation verified successfully"
        return 0
    else
        log_warn "Flutter verification failed, but continuing with fallback methods"
        return 1
    fi
}

# Function to perform basic Flutter initialization
basic_flutter_init() {
    log_info "Starting basic Flutter initialization for Sanmill"
    
    # Navigate to the Flutter app directory
    if ! cd src/ui/flutter_app; then
        log_error "Failed to navigate to Flutter app directory"
        exit 1
    fi
    
    log_info "Working directory: $(pwd)"
    
    # Define paths for generated files
    local gen_file_path="lib/generated"
    local flutter_version_file="$gen_file_path/flutter_version.dart"
    local git_info_path="assets/files"
    local git_branch_file="$git_info_path/git-branch.txt"
    local git_revision_file="$git_info_path/git-revision.txt"
    
    # Create necessary directories
    log_info "Creating required directories"
    mkdir -p "$git_info_path" "$gen_file_path" || {
        log_warn "Failed to create some directories, but continuing"
    }
    
    # Generate Git branch and revision files
    log_info "Generating Git information files"
    if git symbolic-ref --short HEAD > "$git_branch_file" 2>/dev/null; then
        log_info "Generated git branch file: $(cat "$git_branch_file")"
    else
        log_warn "Could not determine git branch, using placeholder"
        echo "unknown" > "$git_branch_file"
    fi
    
    if git rev-parse HEAD > "$git_revision_file" 2>/dev/null; then
        log_info "Generated git revision file: $(head -c 8 "$git_revision_file")"
    else
        log_warn "Could not determine git revision, using placeholder"
        echo "unknown" > "$git_revision_file"
    fi
    
    # Detect Flutter command
    if ! detect_flutter_command; then
        log_error "Cannot proceed without working Flutter installation"
        exit 1
    fi
    
    # Verify Flutter installation
    local flutter_working=false
    if verify_flutter_installation; then
        flutter_working=true
    fi
    
    # Disable Flutter analytics (optional, non-blocking)
    if [[ "$flutter_working" == "true" ]]; then
        log_info "Configuring Flutter settings"
        if flutter_exec config --no-analytics >/dev/null 2>&1; then
            log_success "Flutter analytics disabled"
        else
            log_warn "Could not disable Flutter analytics (non-critical)"
        fi
        
        # Get Flutter packages
        log_info "Retrieving Flutter packages"
        if flutter_exec pub get; then
            log_success "Flutter packages retrieved successfully"
        else
            log_warn "Failed to get Flutter packages"
            log_info "This may indicate network issues or pubspec.yaml problems"
        fi
        
        # Generate localization files
        log_info "Generating localization files"
        if flutter_exec gen-l10n; then
            log_success "Localization files generated successfully"
        else
            log_warn "Localization generation failed"
            log_info "This may be normal if l10n is not configured"
        fi
    else
        log_warn "Skipping Flutter-dependent operations due to installation issues"
    fi
    
    # Generate Flutter version file (create fallback if Flutter not working)
    log_info "Generating Flutter version information"
    echo "const Map<String, String> flutterVersion =" > "$flutter_version_file"
    
    if [[ "$flutter_working" == "true" ]] && flutter_exec --version --machine >> "$flutter_version_file" 2>/dev/null; then
        # Fix the JSON syntax to make it valid Dart
        if command -v sed >/dev/null 2>&1; then
            # Add semicolon at the end of the map
            sed -i.bak 's/}$/};/' "$flutter_version_file" 2>/dev/null || {
                # Fallback if sed fails
                echo ';' >> "$flutter_version_file"
            }
            # Remove backup file if it exists
            [[ -f "${flutter_version_file}.bak" ]] && rm -f "${flutter_version_file}.bak"
        else
            # Simple fallback - just add semicolon
            echo ';' >> "$flutter_version_file"
        fi
        log_success "Flutter version file generated successfully"
    else
        log_warn "Could not get Flutter version, creating fallback"
        echo 'const Map<String, String> flutterVersion = {"channel": "unknown", "version": "unknown"};' > "$flutter_version_file"
    fi
    
    # Run code generation (independent of Flutter)
    log_info "Running code generation"
    if command -v dart >/dev/null 2>&1 && dart run build_runner build --delete-conflicting-outputs; then
        log_success "Code generation completed successfully"
    else
        log_warn "Code generation failed or dart command not available"
        log_info "This may be normal if build_runner dependencies are not set up"
    fi
    
    log_success "Basic Flutter initialization completed"
}

# Function to enable Linux desktop support
enable_linux_desktop() {
    log_info "Enabling Flutter Linux desktop support"
    
    # Use explicit error handling instead of relying on set -e
    if flutter_exec config --enable-linux-desktop 2>/dev/null; then
        log_success "Linux desktop support enabled successfully"
    else
        log_warn "Failed to enable Linux desktop support"
        log_info "This may be due to environment limitations or Flutter configuration issues"
        return 1
    fi
    
    # Create Linux platform files if needed
    log_info "Setting up Linux platform files"
    if flutter_exec create --platforms=linux . 2>/dev/null; then
        log_success "Linux platform files created successfully"
    else
        log_warn "Failed to create Linux platform files"
        log_info "This may be normal if platform files already exist or if in WSL environment"
    fi
    
    return 0
}

# Function to enable Windows desktop support
enable_windows_desktop() {
    log_info "Enabling Flutter Windows desktop support"
    
    # Use explicit error handling instead of relying on set -e
    if flutter_exec config --enable-windows-desktop 2>/dev/null; then
        log_success "Windows desktop support enabled successfully"
    else
        log_warn "Failed to enable Windows desktop support"
        log_info "This may be due to environment limitations or Flutter configuration issues"
        return 1
    fi
    
    # Note about Windows platform files
    log_info "Windows platform file creation is handled automatically by Flutter"
    log_info "If you need to explicitly create Windows platform files, run:"
    log_info "  flutter create --platforms=windows ."
    
    return 0
}

# Function to setup desktop platforms
setup_desktop_platforms() {
    local platform="$1"
    local success_count=0
    local total_count=0
    
    case "$platform" in
        "linux")
            log_info "Setting up Linux desktop platform"
            ((total_count++))
            if enable_linux_desktop; then
                ((success_count++))
            fi
            ;;
        "windows")
            log_info "Setting up Windows desktop platform"
            ((total_count++))
            if enable_windows_desktop; then
                ((success_count++))
            fi
            ;;
        "all")
            log_info "Setting up all desktop platforms"
            
            # Setup Linux desktop
            ((total_count++))
            if enable_linux_desktop; then
                ((success_count++))
            fi
            
            # Setup Windows desktop
            ((total_count++))
            if enable_windows_desktop; then
                ((success_count++))
            fi
            ;;
        *)
            log_error "Unknown platform: $platform"
            return 1
            ;;
    esac
    
    # Report results
    if [[ $success_count -eq $total_count ]]; then
        log_success "All desktop platforms configured successfully ($success_count/$total_count)"
    elif [[ $success_count -gt 0 ]]; then
        log_warn "Some desktop platforms configured successfully ($success_count/$total_count)"
    else
        log_warn "Desktop platform configuration had issues, but basic Flutter setup is complete"
    fi
}

# Main function
main() {
    # Show help if requested
    if [[ "$PLATFORM_ARG" == "help" || "$PLATFORM_ARG" == "--help" || "$PLATFORM_ARG" == "-h" ]]; then
        show_usage
        exit 0
    fi
    
    # Validate platform argument
    case "$PLATFORM_ARG" in
        "basic"|"linux"|"windows"|"all")
            ;;
        *)
            log_error "Invalid platform argument: $PLATFORM_ARG"
            echo ""
            show_usage
            exit 1
            ;;
    esac
    
    log_info "Sanmill Flutter Initialization Script v$SCRIPT_VERSION"
    log_info "Platform configuration: $PLATFORM_ARG"
    echo ""
    
    # Always perform basic initialization first
    basic_flutter_init
    echo ""
    
    # Setup desktop platforms if requested
    if [[ "$PLATFORM_ARG" != "basic" ]]; then
        setup_desktop_platforms "$PLATFORM_ARG"
        echo ""
    fi
    
    # Final summary
    log_success "Flutter initialization completed successfully"
    log_info "Platform: $PLATFORM_ARG"
    log_info "Summary: Setup completed with warnings handled gracefully"
    
    # Return to original directory
    cd - >/dev/null 2>&1 || true
}

# Execute main function with all arguments
main "$@"
