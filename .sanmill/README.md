# Sanmill Maintenance Phase Documentation System

## Overview

Sanmill project has entered the maintenance phase. This system provides streamlined, practical documentation support for maintainers and AI assistants.

**Goal**: Quickly locate components and efficiently complete maintenance tasks  
**Principle**: Pragmatism, avoid over-engineering  
**Focus**: Bug fixes, feature extensions, code quality maintenance

## 🚀 Quick Start

### For Maintainers

```bash
# 1. Read core documentation
cat AGENTS.md                                    # Primary development guidelines
cat .sanmill/MAINTENANCE_GUIDE.md               # Maintenance phase guide

# 2. Check component catalogs
cat src/docs/CPP_COMPONENTS.md                  # C++ components
cat src/ui/flutter_app/docs/COMPONENTS.md       # Flutter components

# 3. Familiarize with workflows
cat src/docs/CPP_WORKFLOWS.md                   # C++ workflows
cat src/ui/flutter_app/docs/WORKFLOWS.md        # Flutter workflows

# 4. Code formatting (required before commit)
./format.sh s
```

### For AI Assistants

**Required reading priority**:
1. `AGENTS.md` - Project development constraints and guidelines
2. Relevant component catalog (`CPP_COMPONENTS.md` or `COMPONENTS.md`)
3. Corresponding workflow documentation (`CPP_WORKFLOWS.md` or `WORKFLOWS.md`)
4. Specific API documentation (`src/docs/api/` or `src/ui/flutter_app/docs/api/`)

## 📁 Documentation Structure (Maintenance Phase Simplified)

### Core Documentation
```
Project Root/
├── AGENTS.md                        # Primary development guidelines (must read)
└── .sanmill/
    ├── MAINTENANCE_GUIDE.md         # Maintenance phase guide (new)
    └── docs/guides/
        └── ADDING_NEW_GAME_RULES.md # Game rule addition guide
```

### Technical Documentation
```
src/docs/                           # C++ engine documentation
├── CPP_COMPONENTS.md               # Component catalog
├── CPP_WORKFLOWS.md                # Workflows
├── TROUBLESHOOTING.md              # Troubleshooting
└── api/                            # API documentation

src/ui/flutter_app/docs/            # Flutter application documentation
├── COMPONENTS.md                   # Component catalog
├── WORKFLOWS.md                    # Workflows
├── BEST_PRACTICES.md               # Best practices
└── api/                            # API documentation
```

### Retained Tools (Optional)
```
.sanmill/tools/
├── context_optimizer.py           # Basic context optimization
└── automation/context_updater.sh  # Documentation update script
```

## 📋 Common Maintenance Tasks

### 1. Bug Fixes
- **Locate components**: Check `CPP_COMPONENTS.md` or `COMPONENTS.md`
- **Workflows**: `CPP_WORKFLOWS.md#workflow-6` or `WORKFLOWS.md#workflow-4`
- **Troubleshooting**: `src/docs/TROUBLESHOOTING.md`

### 2. Adding UI Components
- **Workflow**: `src/ui/flutter_app/docs/WORKFLOWS.md#workflow-1`
- **Template reference**: `src/ui/flutter_app/docs/templates/`
- **Component check**: Ensure no duplication with existing components

### 3. Adding Game Rules
- **Detailed guide**: `.sanmill/docs/guides/ADDING_NEW_GAME_RULES.md`
- **Rule system**: `src/docs/RULE_SYSTEM_GUIDE.md`

### 4. Performance Optimization
- **Performance guide**: `src/docs/PERFORMANCE_GUIDE.md`
- **Workflow**: `src/docs/CPP_WORKFLOWS.md#workflow-4`

### 5. Adding Engine Options
- **Workflow**: `src/docs/CPP_WORKFLOWS.md#workflow-5`

## 🛠️ Practical Tools

### Basic Tools (No Additional Dependencies)
```bash
./format.sh s              # Code formatting (required before commit)
make test                   # C++ tests
flutter test                # Flutter tests
```

### Optional Tools (Requires Python Dependencies)
```bash
python .sanmill/tools/context_optimizer.py  # Basic context optimization
.sanmill/automation/context_updater.sh      # Documentation maintenance script
```

## 📖 Maintenance Phase Usage Examples

### C++ Engine Maintenance

```bash
# 1. Locate relevant components
cat src/docs/CPP_COMPONENTS.md | grep "Search"

# 2. Check API documentation
cat src/docs/api/Position.md

# 3. Follow workflows
cat src/docs/CPP_WORKFLOWS.md  # Find relevant workflow

# 4. Implement, test, commit
./format.sh s
git commit  # Follow AGENTS.md rules
```

### Flutter UI Maintenance

```bash
# 1. Check existing components
cat src/ui/flutter_app/docs/COMPONENTS.md | grep "GameBoard"

# 2. Check API documentation
cat src/ui/flutter_app/docs/api/GameController.md

# 3. Use templates (if creating new component)
cat src/ui/flutter_app/docs/templates/widget_template.dart

# 4. Follow workflows and best practices
cat src/ui/flutter_app/docs/WORKFLOWS.md
cat src/ui/flutter_app/docs/BEST_PRACTICES.md
```

## ✅ Maintenance Phase Best Practices

### For Maintainers

1. **Check documentation before coding**: Review component catalogs and API docs
2. **Follow workflows**: Use standard workflows for consistency
3. **Avoid reinventing the wheel**: Check existing components
4. **Maintain code quality**: Run `./format.sh s` and tests
5. **Update documentation**: Synchronize documentation when changing public APIs

### For AI Assistants

1. **Read AGENTS.md first**: Understand project constraints and guidelines
2. **Check component catalogs**: Avoid duplicate implementations
3. **Follow existing patterns**: Reference similar existing implementations
4. **Add tests**: Add tests for all changes
5. **Keep it simple**: Avoid over-design, focus on solving specific problems

## 📊 Documentation Quality Metrics

**Coverage**:
- C++ Engine: 40+ components documented
- Flutter App: 70+ components documented
- API Documentation: 8+ core classes with complete API documentation
- Workflows: 18 standardized workflows

## 🔧 Documentation Updates for Maintenance Phase

### When to Update Documentation
- Adding new public API → Update API docs
- Adding new component → Update component catalog
- Changing architecture → Update ARCHITECTURE.md
- New development patterns → Update WORKFLOWS.md or BEST_PRACTICES.md

### Simplified Update Process
1. **Modify code**
2. **Update relevant documentation** (if public API)
3. **Run tests**
4. **Format code**: `./format.sh s`
5. **Commit**

## ❓ Frequently Asked Questions

**Q: How to quickly find relevant code?**  
A: Check component catalogs (`CPP_COMPONENTS.md` or `COMPONENTS.md`), then check corresponding API documentation

**Q: How to add new features?**  
A: Check corresponding workflow documentation (`CPP_WORKFLOWS.md` or `WORKFLOWS.md`)

**Q: How to fix bugs?**  
A: Follow bug fix workflows, reference `TROUBLESHOOTING.md`

**Q: What to do before committing?**  
A: Run `./format.sh s` to format code, run tests, follow `AGENTS.md` commit rules

## 📞 Getting Help

- **GitHub Issues**: Report bugs or request features
- **Documentation**: Check `src/docs/` and `src/ui/flutter_app/docs/`
- **Community**: GitHub Discussions

## 🔗 Related Documentation

- [AGENTS.md](../AGENTS.md) - AI assistant development guidelines
- [MAINTENANCE_GUIDE.md](MAINTENANCE_GUIDE.md) - Maintenance phase guide
- [src/docs/](../src/docs/) - C++ engine documentation
- [src/ui/flutter_app/docs/](../src/ui/flutter_app/docs/) - Flutter application documentation

## 📈 System Status

**Core Documentation**: ✅ Complete and up-to-date  
**Component Catalogs**: ✅ Complete coverage  
**Workflows**: ✅ Standardized and practical  
**API Documentation**: ✅ Core APIs documented  
**Complex Tools**: ✅ Removed for maintenance phase simplicity

---

**Version**: 2.0.0 (Maintenance Phase Simplified)  
**Maintainer**: Sanmill Development Team  
**License**: GPL v3