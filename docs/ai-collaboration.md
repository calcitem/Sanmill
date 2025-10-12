# Sanmill AI Context Engineering Documentation

## Overview

This directory contains supplementary documentation for AI-assisted development in the Sanmill project. These documents describe principles and best practices for making codebases AI-friendly.

**Note**: The primary documentation for development is located in:
- `AGENTS.md` (root) - Main AI agent guidelines
- `src/docs/` - C++ engine documentation
- `src/ui/flutter_app/docs/` - Flutter application documentation

## Available Documents

**⚠️ Most content has been consolidated into main guides**

| Document | Purpose | Status |
|----------|---------|--------|
| [guides/ADDING_NEW_GAME_RULES.md](guides/ADDING_NEW_GAME_RULES.md) | Complete guide for adding game rule variants | Active |
| [guides/README.md](guides/README.md) | Guide index and structure | Active |
| ~~AI_FRIENDLY_DEVELOPMENT.md~~ | Principles for AI collaboration | Merged into main guides |
| ~~DOCUMENTATION_STANDARDS.md~~ | Documentation standards | Merged into main guides |
| ~~SEMANTIC_CODE_ORGANIZATION.md~~ | Code organization principles | Merged into main guides |

## Quick Start

### For Developers

1. Read `../../AGENTS.md` for project-specific AI collaboration guidelines
2. Consult `../AI_CONTEXT_GUIDE.md` for context optimization strategies
3. Follow established workflows for your technology stack

### For AI Agents

1. **Primary Resource**: `../../AGENTS.md` - Complete project guidelines
2. **Context Optimization**: `../AI_CONTEXT_GUIDE.md` - Task-specific context mapping
3. **Architecture Understanding**:
   - C++: `../../src/docs/CPP_ARCHITECTURE.md`
   - Flutter: `../../src/ui/flutter_app/docs/ARCHITECTURE.md`
4. **Component Catalogs**:
   - C++: `../../src/docs/CPP_COMPONENTS.md`
   - Flutter: `../../src/ui/flutter_app/docs/COMPONENTS.md`
5. **Development Workflows**:
   - C++: `../../src/docs/CPP_WORKFLOWS.md`
   - Flutter: `../../src/ui/flutter_app/docs/WORKFLOWS.md`

## Documentation Philosophy

### Documentation as SDK

Sanmill uses a **documentation-first approach** where high-quality documentation serves as the primary interface for AI agents. Instead of complex automation systems, we provide comprehensive, well-structured documentation that enables AI agents to understand the codebase and contribute effectively.

### Key Principles

1. **Clear Structure**: Consistent organization across all documentation
2. **Complete Information**: All necessary context in one place
3. **Practical Examples**: Working code examples for all concepts
4. **Cross-References**: Extensive linking between related topics
5. **Current Content**: Documentation updated with code changes

## Actual Tools Available

The project includes simple, practical tools:

- **format.sh**: Code formatting (C++ and Dart)
- **context_optimizer.py**: Context optimization (requires Python dependencies)
- **cpp_ast_extractor.py**: C++ AST analysis
- See `docs/README.md` for details on available tools

## Related Documentation

- [../../AGENTS.md](../../AGENTS.md) - **Start here** for AI agent guidelines
- [../AI_CONTEXT_GUIDE.md](../AI_CONTEXT_GUIDE.md) - AI context optimization guide
- [../CONTEXT_ENGINEERING_SUMMARY.md](../CONTEXT_ENGINEERING_SUMMARY.md) - System overview
- [../README.md](../README.md) - Context engineering system overview

---

**Maintainer**: Sanmill Development Team
