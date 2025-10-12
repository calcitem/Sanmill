# Sanmill Documentation

## Overview

This directory contains project-wide documentation for the Sanmill Mill game project. For code-specific documentation, see the respective source directories.

## 📚 Documentation Structure

### Project Documentation (`docs/`)
```
docs/
├── README.md                       # This file
├── MAINTENANCE_GUIDE.md            # Maintenance phase development guide
├── AI_CONTEXT_GUIDE.md             # AI assistant context guide
├── ai-collaboration.md             # AI collaboration principles
└── guides/
    └── ADDING_NEW_GAME_RULES.md    # Game rule addition guide
```

### Code-Specific Documentation
```
src/docs/                           # C++ engine documentation
├── CPP_COMPONENTS.md               # Component catalog
├── CPP_WORKFLOWS.md                # Development workflows
├── TROUBLESHOOTING.md              # Common issues
└── api/                            # API reference

src/ui/flutter_app/docs/            # Flutter application documentation
├── COMPONENTS.md                   # Component catalog
├── WORKFLOWS.md                    # Development workflows
├── BEST_PRACTICES.md               # Code quality standards
└── api/                            # API reference
```

## 🎯 Quick Navigation

### For Maintainers
- **Start here**: [MAINTENANCE_GUIDE.md](MAINTENANCE_GUIDE.md)
- **Development guidelines**: [../AGENTS.md](../AGENTS.md)
- **Component lookup**: [../src/docs/CPP_COMPONENTS.md](../src/docs/CPP_COMPONENTS.md) or [../src/ui/flutter_app/docs/COMPONENTS.md](../src/ui/flutter_app/docs/COMPONENTS.md)

### For AI Assistants
- **Context guide**: [AI_CONTEXT_GUIDE.md](AI_CONTEXT_GUIDE.md)
- **Development constraints**: [../AGENTS.md](../AGENTS.md)
- **Workflow reference**: [../src/docs/CPP_WORKFLOWS.md](../src/docs/CPP_WORKFLOWS.md) or [../src/ui/flutter_app/docs/WORKFLOWS.md](../src/ui/flutter_app/docs/WORKFLOWS.md)

### For Specific Tasks
- **Adding game rules**: [guides/ADDING_NEW_GAME_RULES.md](guides/ADDING_NEW_GAME_RULES.md)
- **Bug fixing**: [../src/docs/TROUBLESHOOTING.md](../src/docs/TROUBLESHOOTING.md)
- **Performance optimization**: [../src/docs/PERFORMANCE_GUIDE.md](../src/docs/PERFORMANCE_GUIDE.md)

## 📋 Documentation Categories

| Category | Purpose | Location | Examples |
|----------|---------|----------|----------|
| **Project-wide** | General project documentation | `docs/` | This README, maintenance guides |
| **C++ Engine** | Engine-specific documentation | `src/docs/` | API docs, workflows, troubleshooting |
| **Flutter App** | UI-specific documentation | `src/ui/flutter_app/docs/` | Components, workflows, best practices |
| **Development** | Development process docs | Root directory | AGENTS.md, CONTRIBUTING.md |

## 🛠️ Essential Tools

### Basic Tools (No Dependencies)
```bash
./format.sh s              # Code formatting (required before commit)
make test                   # C++ tests
flutter test                # Flutter tests
```

### Optional Tools
```bash
# Maintenance automation (requires Python)
python tools/context_optimizer.py          # Context optimization
.github/automation/context_updater.sh      # Documentation updates
```

## 📝 Contributing to Documentation

### When to Update Documentation
- Adding new public API → Update API docs
- Adding new component → Update component catalog
- Changing workflows → Update workflow docs
- Fixing significant bugs → Update troubleshooting guides

### Documentation Standards
- Use English for all documentation
- Include code examples for complex concepts
- Keep documentation synchronized with code changes
- Follow existing documentation patterns

## 🔗 Related Resources

- **Main project README**: [../README.md](../README.md)
- **Contributing guidelines**: [../CONTRIBUTING.md](../CONTRIBUTING.md)
- **Development guidelines**: [../AGENTS.md](../AGENTS.md)

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3
