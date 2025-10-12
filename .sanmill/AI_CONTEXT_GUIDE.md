# Sanmill AI Context Engineering Guide

## Quick Start (Maintenance Phase Simplified)

### For AI Agents
**Required reading priority**:
1. **AGENTS.md** (root directory) - Project development guidelines and constraints
2. **Component catalogs** - Quickly locate relevant code:
   - C++: `src/docs/CPP_COMPONENTS.md`
   - Flutter: `src/ui/flutter_app/docs/COMPONENTS.md`
3. **Workflows** - Standard development processes:
   - C++: `src/docs/CPP_WORKFLOWS.md`
   - Flutter: `src/ui/flutter_app/docs/WORKFLOWS.md`
4. **API documentation** (as needed):
   - C++: `src/docs/api/`
   - Flutter: `src/ui/flutter_app/docs/api/`

**For Cursor IDE**:
```
# Essential context (required)
@AGENTS.md @.sanmill/MAINTENANCE_GUIDE.md

# Task-specific context
@src/ui/flutter_app/docs/WORKFLOWS.md#workflow-1  # Add UI component
@src/docs/CPP_WORKFLOWS.md#workflow-6             # Fix C++ bug
@src/docs/CPP_COMPONENTS.md                       # C++ component lookup
@src/ui/flutter_app/docs/COMPONENTS.md            # Flutter component lookup
```

### For Maintainers
**Practical tools**:
```bash
# Basic tools (recommended)
./format.sh s                               # Code formatting (required before commit)
cat src/docs/CPP_COMPONENTS.md | grep "ComponentName"  # Find C++ components
cat src/ui/flutter_app/docs/COMPONENTS.md | grep "ComponentName"  # Find Flutter components

# Optional tools (requires Python)
python .sanmill/tools/context_optimizer.py --task "fix bug" --target-file "src/position.cpp"
.sanmill/automation/context_updater.sh      # Documentation maintenance script
```

## Core Principles (Maintenance Phase)

### 1. Documentation as Primary Interface
High-quality documentation serves as the main interface for AI agents to understand the codebase.

### 2. Component-Driven Development
Use component catalogs to quickly locate and understand existing code before making changes.

### 3. Workflow-Based Consistency
Follow established workflows to ensure consistent development patterns across the project.

### 4. Pragmatic Approach
Focus on practical, working solutions rather than complex theoretical frameworks.

## Task Type Context Mapping (Simplified)

### Common Maintenance Tasks

#### Bug Fixes (fix_bug)
**Required context**:
- Target component documentation
- `src/docs/TROUBLESHOOTING.md` or `src/ui/flutter_app/docs/WORKFLOWS.md#workflow-4`
- `AGENTS.md#testing-validation`

#### Add UI Component (add_widget)
**Required context**:
- `src/ui/flutter_app/docs/WORKFLOWS.md#workflow-1`
- `src/ui/flutter_app/docs/COMPONENTS.md`
- `src/ui/flutter_app/docs/templates/widget_template.dart`

#### Add Game Rule (add_rule)
**Required context**:
- `.sanmill/docs/guides/ADDING_NEW_GAME_RULES.md`
- `src/docs/RULE_SYSTEM_GUIDE.md`
- `src/rule.cpp` and `src/rule.h`

### Component Discovery (Simplified)

#### Finding Components
1. **Check component catalogs**: `CPP_COMPONENTS.md` or `COMPONENTS.md`
2. **Search by keyword**: `grep -i "ComponentName" docs/COMPONENTS.md`
3. **Check API docs**: Look in `api/` directories

#### Locating Related Code
1. **Dependencies**: Check component documentation for dependencies
2. **Usage**: Look for similar existing implementations
3. **Tests**: Check `tests/` directories for examples

## Maintenance Phase Workflow

### Standard Development Flow
```
1. Identify task type (bug fix, add component, etc.)
2. Read relevant documentation:
   - Component catalog (CPP_COMPONENTS.md or COMPONENTS.md)
   - Workflow documentation (CPP_WORKFLOWS.md or WORKFLOWS.md)
   - API documentation (if needed)
3. Implement following existing patterns
4. Add tests
5. Format and commit: ./format.sh s
```

### Quick Reference Commands
```bash
# C++ Engine
cd src && make test              # Run C++ tests
cd src && make bench             # Performance benchmark

# Flutter Application
cd src/ui/flutter_app && flutter test    # Run Flutter tests
cd src/ui/flutter_app && flutter run     # Run application

# Code formatting
./format.sh s                   # Format all code

# Documentation generation
cd src/ui/flutter_app && flutter gen-l10n  # Generate localization
```

## Cross-Language Component Mapping

### Key Component Relationships
```
Position: 
  C++: src/position.cpp
  Dart: src/ui/flutter_app/lib/game_page/services/engine/position.dart

Engine:
  C++: src/engine_controller.cpp
  Dart: src/ui/flutter_app/lib/game_page/services/engine/engine.dart

Rules:
  C++: src/rule.cpp (RULES array + global rule struct)
  Dart: src/ui/flutter_app/lib/rule_settings/models/rule_settings.dart
```

## Best Practices for Maintenance Phase

### For AI Agents Working on C++
1. **Read** `src/docs/CPP_COMPONENTS.md` to find relevant components
2. **Check** `src/docs/api/` for API documentation
3. **Follow** workflows from `src/docs/CPP_WORKFLOWS.md`
4. **Run tests** after changes: `make test`
5. **Format code**: `./format.sh s`

### For AI Agents Working on Flutter
1. **Read** `src/ui/flutter_app/docs/COMPONENTS.md` to avoid duplication
2. **Check** `src/ui/flutter_app/docs/api/` for API documentation
3. **Follow** workflows from `src/ui/flutter_app/docs/WORKFLOWS.md`
4. **Apply** standards from `src/ui/flutter_app/docs/BEST_PRACTICES.md`
5. **Run tests**: `flutter test`
6. **Format code**: `./format.sh s`

## Error Prevention Patterns

### C++ Specific
- **No try-catch**: Use `assert()` instead of try-catch blocks
- **No wrapper functions**: Modify original functions directly
- **Performance critical**: Measure impact for Position, Search, do_move functions

### Flutter Specific
- **No hardcoded strings**: Use `S.of(context).stringKey` for localization
- **Proper disposal**: Implement `dispose()` method for StatefulWidgets
- **Accessibility**: Add semantic labels for all interactive elements

---

**Maintainer**: Sanmill Development Team  
**Version**: 3.0.0 (Maintenance Phase Simplified)  
**License**: GPL v3