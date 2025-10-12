# Sanmill Maintenance Phase Development Guide

## Overview

Sanmill project has entered the maintenance phase. This document provides streamlined development guidance for maintainers and AI assistants. Focus areas:
- Maintenance and bug fixes for existing features
- Adding and extending new modules
- Code quality preservation

## 🚀 Quick Start

### For Maintainers
```bash
# 1. Read core documentation
cat AGENTS.md                    # Primary development guidelines
cat src/docs/CPP_COMPONENTS.md   # C++ component catalog
cat src/ui/flutter_app/docs/COMPONENTS.md  # Flutter component catalog

# 2. Familiarize with workflows
cat src/docs/CPP_WORKFLOWS.md    # C++ workflows
cat src/ui/flutter_app/docs/WORKFLOWS.md  # Flutter workflows

# 3. Code formatting (required before commit)
./format.sh s
```

### For AI Assistants
**Required reading priority**:
1. `AGENTS.md` - Project development constraints and guidelines
2. Relevant component API documentation (`src/docs/api/` or `src/ui/flutter_app/docs/api/`)
3. Technology-specific workflow documentation

## 📋 Common Maintenance Tasks

### 1. Bug Fixes
**Workflow**: `src/docs/CPP_WORKFLOWS.md#workflow-6` or `src/ui/flutter_app/docs/WORKFLOWS.md#workflow-4`

**Steps**:
1. Reproduce the bug
2. Locate relevant components (check component catalogs)
3. Read relevant API documentation
4. Fix and add regression tests
5. Run `./format.sh s`
6. Commit

### 2. Adding UI Components
**Workflow**: `src/ui/flutter_app/docs/WORKFLOWS.md#workflow-1`

**Checklist**:
- [ ] Check `COMPONENTS.md` to avoid duplication
- [ ] Use existing templates
- [ ] Add localization strings
- [ ] Add tests
- [ ] Update component catalog

### 3. Adding Game Rules
**Detailed guide**: `docs/guides/ADDING_NEW_GAME_RULES.md`

**Simplified steps**:
1. Add new rule to `RULES[]` array in `src/rule.cpp`
2. Update `N_RULES` constant in `src/rule.h`
3. Add corresponding enum value and settings class in Flutter
4. Add localization strings
5. Test

### 4. Performance Optimization
**Workflow**: `src/docs/CPP_WORKFLOWS.md#workflow-4`

**Key file**: `src/docs/PERFORMANCE_GUIDE.md`

### 5. Adding Engine Options
**Workflow**: `src/docs/CPP_WORKFLOWS.md#workflow-5`

## 📁 Core Documentation Structure

### Essential Documentation (Maintenance Phase)
```
Project Root/
├── AGENTS.md                    # Primary development guidelines
├── src/docs/
│   ├── CPP_COMPONENTS.md        # C++ component catalog
│   ├── CPP_WORKFLOWS.md         # C++ workflows
│   ├── TROUBLESHOOTING.md       # Common issues
│   └── api/                     # C++ API documentation
└── src/ui/flutter_app/docs/
    ├── COMPONENTS.md            # Flutter component catalog
    ├── WORKFLOWS.md             # Flutter workflows
    ├── BEST_PRACTICES.md        # Best practices
    └── api/                     # Flutter API documentation
```

### Specialized Guides
```
docs/guides/
└── ADDING_NEW_GAME_RULES.md     # Game rule addition guide
```

## 🛠️ Practical Tools

### Basic Tools (No Additional Dependencies)
```bash
./format.sh s              # Code formatting (required before commit)
make test                   # C++ tests
flutter test                # Flutter tests
```

### Optional Tools (Requires Python)
```bash
python tools/context_optimizer.py           # Context optimization
.github/automation/context_updater.sh       # Documentation updates
```

## 🎯 Maintenance Phase Priorities

### Priority 1: Code Quality Maintenance
- Bug fixes
- Performance optimization
- Code refactoring

### Priority 2: Feature Extension
- Adding UI components
- Adding game rules
- Adding engine options

### Priority 3: Documentation Maintenance
- Keep API documentation synchronized
- Update component catalogs
- Fix outdated information

## 📝 Simplified Commit Workflow

```bash
# 1. Modify code
# 2. Run formatting (required)
./format.sh s

# 3. Commit
git add .
git commit -m "Concise commit message

Detailed explanation of changes and reasoning."
```

## 🔗 Quick Reference

### C++ Development
- **Component lookup**: `src/docs/CPP_COMPONENTS.md`
- **API reference**: `src/docs/api/Position.md`, `src/docs/api/SearchEngine.md`
- **Workflows**: `src/docs/CPP_WORKFLOWS.md`
- **Troubleshooting**: `src/docs/TROUBLESHOOTING.md`

### Flutter Development
- **Component lookup**: `src/ui/flutter_app/docs/COMPONENTS.md`
- **Workflows**: `src/ui/flutter_app/docs/WORKFLOWS.md`
- **Best practices**: `src/ui/flutter_app/docs/BEST_PRACTICES.md`
- **State management**: `src/ui/flutter_app/docs/STATE_MANAGEMENT.md`

---

**Version**: 1.0.0  
**Maintainer**: Sanmill Development Team  
**License**: GPL v3