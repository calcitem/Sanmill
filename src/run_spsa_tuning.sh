#!/bin/bash

# SPSA Parameter Tuning Script for Sanmill
# This script provides an easy way to run SPSA parameter tuning with common configurations

set -e

# Default values
ITERATIONS=1000
GAMES=100
THREADS=8
CONFIG_FILE=""
PARAMS_FILE=""
OUTPUT_FILE="tuned_parameters.txt"
LOG_FILE="spsa_tuning.log"
RESUME_FILE=""
INTERACTIVE=false
QUICK_MODE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to show usage
show_usage() {
    echo "SPSA Parameter Tuning Script for Sanmill"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -i, --iterations N      Number of iterations (default: 1000)"
    echo "  -g, --games N           Games per evaluation (default: 100)"
    echo "  -t, --threads N         Number of threads (default: 8)"
    echo "  -c, --config FILE       Configuration file"
    echo "  -p, --params FILE       Initial parameters file"
    echo "  -o, --output FILE       Output file for best parameters (default: tuned_parameters.txt)"
    echo "  -l, --log FILE          Log file (default: spsa_tuning.log)"
    echo "  -r, --resume FILE       Resume from checkpoint file"
    echo "  -I, --interactive       Run in interactive mode"
    echo "  -q, --quick             Quick mode (fewer games, iterations)"
    echo "  --clean                 Clean previous results and start fresh"
    echo ""
    echo "Predefined configurations:"
    echo "  --fast                  Fast tuning (200 iterations, 50 games)"
    echo "  --standard              Standard tuning (1000 iterations, 100 games)"
    echo "  --thorough              Thorough tuning (2000 iterations, 200 games)"
    echo "  --ultra                 Ultra thorough (5000 iterations, 500 games)"
    echo ""
    echo "Examples:"
    echo "  $0 --fast                           # Quick tuning session"
    echo "  $0 --standard --threads 16          # Standard tuning with 16 threads"
    echo "  $0 --config my_config.txt           # Use custom configuration"
    echo "  $0 --resume checkpoint.txt          # Resume previous session"
    echo "  $0 --interactive                    # Interactive mode"
}

# Function to check if file exists
check_file() {
    if [[ -n "$1" && ! -f "$1" ]]; then
        print_error "File not found: $1"
        exit 1
    fi
}

# Function to create backup of existing files
backup_file() {
    if [[ -f "$1" ]]; then
        local backup_name="${1}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$1" "$backup_name"
        print_info "Backed up $1 to $backup_name"
    fi
}

# Function to clean previous results
clean_results() {
    print_info "Cleaning previous results..."
    
    # Backup important files before cleaning
    backup_file "$LOG_FILE"
    backup_file "$OUTPUT_FILE"
    backup_file "spsa_checkpoint.txt"
    
    # Remove temporary files
    rm -f spsa_checkpoint.txt
    rm -f best_parameters.txt
    rm -f final_parameters.txt
    rm -f final_checkpoint.txt
    
    print_success "Cleaned previous results"
}

# Function to compile SPSA tuner if needed
compile_tuner() {
    if [[ ! -f "spsa_tuner" ]]; then
        print_info "SPSA tuner not found, compiling..."
        if [[ -f "spsa_tuner_makefile" ]]; then
            make -f spsa_tuner_makefile
            if [[ $? -eq 0 ]]; then
                print_success "Successfully compiled SPSA tuner"
            else
                print_error "Failed to compile SPSA tuner"
                exit 1
            fi
        else
            print_error "Makefile not found. Please compile manually."
            exit 1
        fi
    fi
}

# Function to create example files if they don't exist
create_examples() {
    if [[ ! -f "spsa_config_example.txt" || ! -f "spsa_params_example.txt" ]]; then
        print_info "Creating example configuration files..."
        if [[ -f "spsa_tuner_makefile" ]]; then
            make -f spsa_tuner_makefile examples
        fi
    fi
}

# Function to validate configuration
validate_config() {
    if [[ $ITERATIONS -lt 1 ]]; then
        print_error "Iterations must be at least 1"
        exit 1
    fi
    
    if [[ $GAMES -lt 10 ]]; then
        print_error "Games per evaluation must be at least 10"
        exit 1
    fi
    
    if [[ $THREADS -lt 1 ]]; then
        print_error "Thread count must be at least 1"
        exit 1
    fi
}

# Function to show configuration summary
show_config() {
    echo ""
    print_info "Configuration Summary:"
    echo "  Iterations: $ITERATIONS"
    echo "  Games per evaluation: $GAMES"
    echo "  Threads: $THREADS"
    echo "  Output file: $OUTPUT_FILE"
    echo "  Log file: $LOG_FILE"
    
    if [[ -n "$CONFIG_FILE" ]]; then
        echo "  Config file: $CONFIG_FILE"
    fi
    
    if [[ -n "$PARAMS_FILE" ]]; then
        echo "  Initial parameters: $PARAMS_FILE"
    fi
    
    if [[ -n "$RESUME_FILE" ]]; then
        echo "  Resume from: $RESUME_FILE"
    fi
    
    echo ""
}

# Function to estimate runtime
estimate_runtime() {
    local total_games=$((ITERATIONS * GAMES * 2))  # 2 evaluations per iteration
    local games_per_minute=60  # Rough estimate: 1 game per second
    local estimated_minutes=$((total_games / games_per_minute / THREADS))
    
    print_info "Estimated runtime: ~$estimated_minutes minutes with $THREADS threads"
    print_info "Total games to be played: ~$total_games"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -i|--iterations)
            ITERATIONS="$2"
            shift 2
            ;;
        -g|--games)
            GAMES="$2"
            shift 2
            ;;
        -t|--threads)
            THREADS="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -p|--params)
            PARAMS_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -r|--resume)
            RESUME_FILE="$2"
            shift 2
            ;;
        -I|--interactive)
            INTERACTIVE=true
            shift
            ;;
        -q|--quick)
            QUICK_MODE=true
            ITERATIONS=200
            GAMES=50
            shift
            ;;
        --clean)
            clean_results
            exit 0
            ;;
        --fast)
            ITERATIONS=200
            GAMES=50
            print_info "Using fast configuration"
            shift
            ;;
        --standard)
            ITERATIONS=1000
            GAMES=100
            print_info "Using standard configuration"
            shift
            ;;
        --thorough)
            ITERATIONS=2000
            GAMES=200
            print_info "Using thorough configuration"
            shift
            ;;
        --ultra)
            ITERATIONS=5000
            GAMES=500
            print_info "Using ultra thorough configuration"
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    echo "========================================"
    echo "SPSA Parameter Tuning for Sanmill"
    echo "========================================"
    
    # Validate input files
    check_file "$CONFIG_FILE"
    check_file "$PARAMS_FILE"
    check_file "$RESUME_FILE"
    
    # Validate configuration
    validate_config
    
    # Show configuration
    show_config
    
    # Estimate runtime
    estimate_runtime
    
    # Compile tuner if needed
    compile_tuner
    
    # Create example files
    create_examples
    
    # Ask for confirmation unless in quick mode
    if [[ "$QUICK_MODE" != true && "$INTERACTIVE" != true ]]; then
        echo ""
        read -p "Continue with tuning? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Tuning cancelled"
            exit 0
        fi
    fi
    
    # Build command line arguments
    local cmd_args=()
    cmd_args+=("--iterations" "$ITERATIONS")
    cmd_args+=("--games" "$GAMES")
    cmd_args+=("--threads" "$THREADS")
    cmd_args+=("--output" "$OUTPUT_FILE")
    cmd_args+=("--log" "$LOG_FILE")
    
    if [[ -n "$CONFIG_FILE" ]]; then
        cmd_args+=("--config" "$CONFIG_FILE")
    fi
    
    if [[ -n "$PARAMS_FILE" ]]; then
        cmd_args+=("--params" "$PARAMS_FILE")
    fi
    
    if [[ -n "$RESUME_FILE" ]]; then
        cmd_args+=("--resume" "$RESUME_FILE")
    fi
    
    if [[ "$INTERACTIVE" == true ]]; then
        cmd_args+=("--interactive")
    fi
    
    # Start tuning
    print_info "Starting SPSA parameter tuning..."
    print_info "Command: ./spsa_tuner ${cmd_args[*]}"
    
    # Run the tuner
    if ./spsa_tuner "${cmd_args[@]}"; then
        print_success "Tuning completed successfully!"
        
        if [[ -f "$OUTPUT_FILE" ]]; then
            print_success "Best parameters saved to: $OUTPUT_FILE"
        fi
        
        if [[ -f "$LOG_FILE" ]]; then
            print_info "Detailed log available in: $LOG_FILE"
        fi
        
        # Show final results summary
        if [[ -f "$OUTPUT_FILE" ]]; then
            echo ""
            print_info "Final optimized parameters:"
            echo "----------------------------------------"
            cat "$OUTPUT_FILE" | grep -v "^#" | head -10
            echo "----------------------------------------"
        fi
        
    else
        print_error "Tuning failed or was interrupted"
        
        if [[ -f "spsa_checkpoint.txt" ]]; then
            print_info "You can resume with: $0 --resume spsa_checkpoint.txt"
        fi
        
        exit 1
    fi
}

# Run main function
main "$@"
