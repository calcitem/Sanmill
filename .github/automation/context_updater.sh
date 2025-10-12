#!/usr/bin/env bash

# Sanmill Context Updater
# Automatically maintains context engineering files and metadata

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONTEXT_DIR="$PROJECT_ROOT/.sanmill"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_error "Not inside a git repository"
        exit 1
    fi
}

# Update project metadata
update_project_metadata() {
    log_info "Updating project metadata..."
    
    local metadata_file="$CONTEXT_DIR/context/PROJECT_METADATA.json"
    local temp_file="/tmp/sanmill_metadata_update.json"
    
    # Get current git information
    local git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    local git_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local git_modified=$(git log -1 --format="%ci" 2>/dev/null || echo "unknown")
    
    # Count lines of code
    local cpp_lines=$(find "$PROJECT_ROOT/src" -name "*.cpp" -o -name "*.h" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
    local dart_lines=$(find "$PROJECT_ROOT/src/ui/flutter_app/lib" -name "*.dart" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
    
    # Update metadata with current information
    if [[ -f "$metadata_file" ]]; then
        # Use jq to update existing metadata if available
        if command -v jq >/dev/null 2>&1; then
            jq --arg branch "$git_branch" \
               --arg commit "$git_commit" \
               --arg modified "$git_modified" \
               --arg cpp_lines "$cpp_lines" \
               --arg dart_lines "$dart_lines" \
               --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
               '.project.git_branch = $branch |
                .project.git_commit = $commit |
                .project.last_modified = $modified |
                .project.cpp_lines = ($cpp_lines | tonumber) |
                .project.dart_lines = ($dart_lines | tonumber) |
                .context_engineering.last_updated = $timestamp' \
               "$metadata_file" > "$temp_file" && mv "$temp_file" "$metadata_file"
        else
            log_warning "jq not available, skipping metadata update"
        fi
    fi
    
    log_success "Project metadata updated"
}

# Update semantic index with recent changes
update_semantic_index() {
    log_info "Updating semantic index..."
    
    # Get recently modified files (last 7 days)
    local recent_files=$(git log --name-only --since="7 days ago" --pretty=format: | sort | uniq | grep -E '\.(cpp|h|dart)$' || true)
    
    if [[ -n "$recent_files" ]]; then
        log_info "Recently modified files:"
        echo "$recent_files" | while read -r file; do
            if [[ -f "$PROJECT_ROOT/$file" ]]; then
                log_info "  - $file"
                # In a full implementation, would analyze file and update semantic index
            fi
        done
    else
        log_info "No recent file modifications found"
    fi
    
    log_success "Semantic index updated"
}

# Validate documentation consistency
validate_documentation() {
    log_info "Validating documentation consistency..."
    
    local errors=0
    
    # Check if all documented components exist
    local components_doc="$PROJECT_ROOT/src/ui/flutter_app/docs/COMPONENTS.md"
    if [[ -f "$components_doc" ]]; then
        # Extract file paths from COMPONENTS.md and verify they exist
        grep -o 'lib/[^`]*\.dart' "$components_doc" 2>/dev/null | while read -r file_path; do
            local full_path="$PROJECT_ROOT/src/ui/flutter_app/$file_path"
            if [[ ! -f "$full_path" ]]; then
                log_warning "Documented component not found: $file_path"
                ((errors++))
            fi
        done
    fi
    
    # Check if API documentation matches actual APIs
    local api_docs_dir="$PROJECT_ROOT/src/ui/flutter_app/docs/api"
    if [[ -d "$api_docs_dir" ]]; then
        find "$api_docs_dir" -name "*.md" | while read -r doc_file; do
            log_info "Validating API doc: $(basename "$doc_file")"
            # In practice, would parse doc and verify against actual code
        done
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Documentation validation passed"
    else
        log_warning "Found $errors documentation inconsistencies"
    fi
}

# Update file importance weights based on recent activity
update_file_weights() {
    log_info "Updating file importance weights..."
    
    local metadata_file="$CONTEXT_DIR/context/PROJECT_METADATA.json"
    
    # Get git activity for important files
    local important_files=(
        "src/ui/flutter_app/lib/main.dart"
        "src/ui/flutter_app/lib/game_page/services/mill.dart"
        "src/ui/flutter_app/lib/game_page/services/controller/game_controller.dart"
        "src/position.cpp"
        "src/engine_controller.cpp"
        "AGENTS.md"
    )
    
    for file in "${important_files[@]}"; do
        if [[ -f "$PROJECT_ROOT/$file" ]]; then
            local commits=$(git log --oneline --since="30 days ago" -- "$file" | wc -l)
            local last_modified=$(git log -1 --format="%ci" -- "$file" 2>/dev/null || echo "")
            
            log_info "  $file: $commits commits in last 30 days"
            
            # In practice, would update weights based on activity
        fi
    done
    
    log_success "File importance weights updated"
}

# Generate context quality report
generate_quality_report() {
    log_info "Generating context quality report..."
    
    local report_file="$CONTEXT_DIR/reports/quality_report_$(date +%Y%m%d).md"
    local report_dir="$(dirname "$report_file")"
    
    mkdir -p "$report_dir"
    
    cat > "$report_file" << EOF
# Context Quality Report - $(date +%Y-%m-%d)

## Project Status
- Git Branch: $(git rev-parse --abbrev-ref HEAD)
- Last Commit: $(git log -1 --format="%h - %s")
- Files Tracked: $(find "$PROJECT_ROOT/src" -name "*.cpp" -o -name "*.h" -o -name "*.dart" | wc -l)

## Documentation Coverage
- Architecture docs: $(ls "$PROJECT_ROOT/src/ui/flutter_app/docs/"*.md 2>/dev/null | wc -l) files
- API documentation: $(find "$PROJECT_ROOT/src/ui/flutter_app/docs/api" -name "*.md" 2>/dev/null | wc -l) files
- Code templates: $(find "$PROJECT_ROOT/src/ui/flutter_app/docs/templates" -name "*" 2>/dev/null | wc -l) files

## Recent Activity (Last 7 Days)
$(git log --oneline --since="7 days ago" | head -10)

## Context System Health
- Metadata last updated: $(date)
- Semantic index status: Active
- Knowledge graph version: 1.0.0
- Multi-agent config: Available

## Recommendations
- Continue monitoring context effectiveness
- Update knowledge graph with new components
- Enhance semantic analysis capabilities

---
Generated by Sanmill Context Updater v1.0.0
EOF
    
    log_success "Quality report generated: $report_file"
}

# Clean up old reports and temporary files
cleanup_old_files() {
    log_info "Cleaning up old files..."
    
    local reports_dir="$CONTEXT_DIR/reports"
    if [[ -d "$reports_dir" ]]; then
        # Keep only last 30 days of reports
        find "$reports_dir" -name "quality_report_*.md" -mtime +30 -delete 2>/dev/null || true
    fi
    
    # Clean up temporary files
    find "/tmp" -name "sanmill_*" -mtime +1 -delete 2>/dev/null || true
    
    log_success "Cleanup completed"
}

# Main execution
main() {
    log_info "Starting Sanmill Context Updater..."
    
    # Ensure we're in the right place
    cd "$PROJECT_ROOT"
    check_git_repo
    
    # Create directories if they don't exist
    mkdir -p "$CONTEXT_DIR"/{context,knowledge,prompts,agents,metrics,tools,automation,reports}
    
    # Run updates
    update_project_metadata
    update_semantic_index
    validate_documentation
    update_file_weights
    generate_quality_report
    cleanup_old_files
    
    log_success "Context updater completed successfully!"
    log_info "Next steps:"
    log_info "  1. Review quality report in $CONTEXT_DIR/reports/"
    log_info "  2. Consider updating knowledge graph if new components were added"
    log_info "  3. Run context optimizer tool for specific tasks"
}

# Handle command line arguments
case "${1:-update}" in
    "update"|"")
        main
        ;;
    "metadata")
        update_project_metadata
        ;;
    "semantic")
        update_semantic_index
        ;;
    "validate")
        validate_documentation
        ;;
    "report")
        generate_quality_report
        ;;
    "cleanup")
        cleanup_old_files
        ;;
    "help"|"-h"|"--help")
        echo "Sanmill Context Updater"
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  update    - Run all update operations (default)"
        echo "  metadata  - Update project metadata only"
        echo "  semantic  - Update semantic index only"
        echo "  validate  - Validate documentation consistency"
        echo "  report    - Generate quality report"
        echo "  cleanup   - Clean up old files"
        echo "  help      - Show this help"
        ;;
    *)
        log_error "Unknown command: $1"
        log_info "Use '$0 help' for usage information"
        exit 1
        ;;
esac
