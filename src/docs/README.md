# C++ Engine Documentation

Welcome to the Sanmill C++ engine documentation. This documentation provides comprehensive guidance for AI agents and developers working on the game engine.

## 📚 Documentation Structure

### Getting Started

**New to the codebase?** Start here:

1. **[ARCHITECTURE.md](CPP_ARCHITECTURE.md)** - Understand the overall system design
2. **[COMPONENTS.md](CPP_COMPONENTS.md)** - Explore available components
3. **[GETTING_STARTED.md](examples/)** - Run your first examples

### Core Documentation

#### Architecture & Design

- **[CPP_ARCHITECTURE.md](CPP_ARCHITECTURE.md)** - Complete architecture overview
  - Design philosophy and principles
  - Layer-by-layer breakdown
  - Data flow and communication patterns
  - Performance characteristics
  - Integration points

- **[CPP_COMPONENTS.md](CPP_COMPONENTS.md)** - Comprehensive component catalog
  - 40+ documented components
  - Dependencies and relationships
  - Usage patterns
  - Performance-critical identification

#### API Reference

Detailed API documentation for core classes:

- **[api/Position.md](api/Position.md)** - Board state management
  - 100+ methods documented
  - Move execution and undo
  - Mill detection
  - Game phase tracking
  - Performance notes

- **[api/SearchEngine.md](api/SearchEngine.md)** - Search coordination
  - Search lifecycle
  - Algorithm selection
  - Time management
  - Database integration

- **[api/Search.md](api/Search.md)** - Search algorithms
  - Alpha-Beta pruning
  - MTD(f) search
  - Principal Variation Search
  - Quiescence search
  - Optimization techniques

#### Protocols & Systems

- **[UCI_PROTOCOL.md](UCI_PROTOCOL.md)** - Communication protocol
  - Complete UCI command reference
  - Mill-specific extensions
  - FEN format specification
  - Move notation
  - Engine options

- **[RULE_SYSTEM_GUIDE.md](RULE_SYSTEM_GUIDE.md)** - Game rules system
  - Rule structure (30+ fields)
  - Adding new variants
  - Validation rules
  - Cross-language mapping (C++ ↔ Flutter)

#### Development Workflows

- **[CPP_WORKFLOWS.md](CPP_WORKFLOWS.md)** - Step-by-step development guides
  - Add new search algorithm
  - Modify evaluation function
  - Add UCI command
  - Optimize performance
  - Add engine option
  - Fix search bugs
  - Add opening book moves
  - Implement new rule variant

#### Troubleshooting

- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions
  - Compilation errors
  - Runtime errors
  - Search problems
  - UCI communication issues
  - Performance issues
  - Testing issues
  - Build system issues

### Code Examples

Practical examples demonstrating common tasks:

- **[examples/basic_search.cpp](examples/basic_search.cpp)** - Basic search usage
- **[examples/position_manipulation.cpp](examples/position_manipulation.cpp)** - Position operations

## 🎯 Quick Navigation

### By Task

**I want to...**

- **Understand the architecture** → [CPP_ARCHITECTURE.md](CPP_ARCHITECTURE.md)
- **Find a specific component** → [CPP_COMPONENTS.md](CPP_COMPONENTS.md)
- **Use Position API** → [api/Position.md](api/Position.md)
- **Implement search algorithm** → [CPP_WORKFLOWS.md](CPP_WORKFLOWS.md#workflow-1)
- **Add UCI command** → [CPP_WORKFLOWS.md](CPP_WORKFLOWS.md#workflow-3)
- **Add game rule** → [RULE_SYSTEM_GUIDE.md](RULE_SYSTEM_GUIDE.md)
- **Fix a bug** → [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **Learn by example** → [examples/](examples/)

### By Component

- **Position** → [api/Position.md](api/Position.md), [COMPONENTS.md#position](CPP_COMPONENTS.md#position)
- **SearchEngine** → [api/SearchEngine.md](api/SearchEngine.md), [COMPONENTS.md#searchengine](CPP_COMPONENTS.md#searchengine)
- **Search Algorithms** → [api/Search.md](api/Search.md), [COMPONENTS.md#search-namespace](CPP_COMPONENTS.md#search-namespace)
- **UCI** → [UCI_PROTOCOL.md](UCI_PROTOCOL.md), [COMPONENTS.md#uci](CPP_COMPONENTS.md#uci)
- **Rules** → [RULE_SYSTEM_GUIDE.md](RULE_SYSTEM_GUIDE.md), [COMPONENTS.md#rule](CPP_COMPONENTS.md#rule)

### By Problem

**I'm experiencing...**

- **Compilation error** → [TROUBLESHOOTING.md#compilation-issues](TROUBLESHOOTING.md#compilation-issues)
- **Segmentation fault** → [TROUBLESHOOTING.md#runtime-errors](TROUBLESHOOTING.md#runtime-errors)
- **Search problems** → [TROUBLESHOOTING.md#search-problems](TROUBLESHOOTING.md#search-problems)
- **Performance issues** → [TROUBLESHOOTING.md#performance-issues](TROUBLESHOOTING.md#performance-issues)
- **UCI communication failure** → [TROUBLESHOOTING.md#uci-communication-issues](TROUBLESHOOTING.md#uci-communication-issues)

## 🚀 For AI Agents

### Essential Reading

Before modifying C++ code, read:

1. **Architecture** ([CPP_ARCHITECTURE.md](CPP_ARCHITECTURE.md)) - Understand system design
2. **Relevant Component** ([COMPONENTS.md](CPP_COMPONENTS.md)) - Find what you need to modify
3. **API Documentation** ([api/](api/)) - Understand how to use APIs correctly
4. **Workflow** ([CPP_WORKFLOWS.md](CPP_WORKFLOWS.md)) - Follow established patterns

### Common Tasks

- **Adding feature** → Check [WORKFLOWS.md](CPP_WORKFLOWS.md) for step-by-step guide
- **Fixing bug** → Follow [WORKFLOWS.md#workflow-6](CPP_WORKFLOWS.md#workflow-6)
- **Optimizing** → See [WORKFLOWS.md#workflow-4](CPP_WORKFLOWS.md#workflow-4)
- **Understanding code** → Use [COMPONENTS.md](CPP_COMPONENTS.md) to locate components

### Performance-Critical Code

⚠️ **Ultra-Critical** (>40% CPU time):
- `Search::search()` - Main search loop
- `Position::do_move()` / `undo_move()` - Move execution

🔥 **Critical** (10-40% CPU time):
- `MoveGen::generate_legal_moves()`
- `Position::is_all_in_mills()`

See [CPP_COMPONENTS.md#performance-critical-components](CPP_COMPONENTS.md#performance-critical-components)

### Cross-References

**C++ ↔ Flutter**:
- Position: C++ `src/position.cpp` ↔ Dart `lib/game_page/services/engine/position.dart`
- Engine: C++ `src/search_engine.cpp` ↔ Dart `lib/game_page/services/engine/engine.dart`
- Rules: C++ `src/rule.cpp` ↔ Dart `lib/rule_settings/models/rule_settings.dart`

## 📖 Documentation Standards

### For Developers

When modifying code:

1. **Update relevant API docs** if public interface changes
2. **Add usage examples** for complex features
3. **Update component descriptions** if responsibilities change
4. **Document non-obvious decisions** in code comments

### For AI Agents

When generating code:

1. **Consult API documentation** before using unfamiliar APIs
2. **Follow established patterns** from workflows
3. **Check performance notes** for critical paths
4. **Validate against examples**

## 🔗 Related Documentation

### Project-Wide

- **[AGENTS.md](../../AGENTS.md)** - AI agent development guidelines
- **[Contributing Guidelines](../../CONTRIBUTING.md)** - Contribution process
- **[README.md](../../README.md)** - Project overview

### Flutter Documentation

- **[Flutter Architecture](../ui/flutter_app/docs/ARCHITECTURE.md)** - Flutter app architecture
- **[Flutter Components](../ui/flutter_app/docs/COMPONENTS.md)** - Flutter component catalog
- **[Flutter Workflows](../ui/flutter_app/docs/WORKFLOWS.md)** - Flutter development workflows

### Context Engineering

- **[docs/](../../docs/)** - Project-wide documentation
- **[Adding New Game Rules](../../docs/guides/ADDING_NEW_GAME_RULES.md)** - Comprehensive rule addition guide

## 📊 Documentation Map

```
src/docs/
├── README.md (this file)
│
├── Architecture & Design
│   ├── CPP_ARCHITECTURE.md      ← System architecture
│   └── CPP_COMPONENTS.md        ← Component catalog
│
├── API Reference
│   └── api/
│       ├── Position.md          ← Position class API
│       ├── SearchEngine.md      ← SearchEngine class API
│       └── Search.md            ← Search algorithms API
│
├── Protocols & Systems
│   ├── UCI_PROTOCOL.md          ← UCI protocol specification
│   └── RULE_SYSTEM_GUIDE.md     ← Rule system guide
│
├── Development
│   ├── CPP_WORKFLOWS.md         ← Development workflows
│   ├── TROUBLESHOOTING.md       ← Issue resolution
│   └── examples/                ← Code examples
│       ├── basic_search.cpp
│       └── position_manipulation.cpp
│
└── [Future additions]
    ├── PERFORMANCE_GUIDE.md     ← Optimization guide (planned)
    ├── TESTING_GUIDE.md         ← Testing strategies (planned)
    └── CONTRIBUTING_CPP.md      ← C++ contribution guide (planned)
```

## 🎓 Learning Path

### Beginner

1. Read [CPP_ARCHITECTURE.md](CPP_ARCHITECTURE.md) - Understand overall design
2. Run [examples/basic_search.cpp](examples/basic_search.cpp) - See engine in action
3. Read [api/Position.md](api/Position.md) - Learn core Position API
4. Try [CPP_WORKFLOWS.md#workflow-5](CPP_WORKFLOWS.md#workflow-5) - Add simple engine option

### Intermediate

1. Read [api/SearchEngine.md](api/SearchEngine.md) - Understand search coordination
2. Read [api/Search.md](api/Search.md) - Learn search algorithms
3. Try [CPP_WORKFLOWS.md#workflow-2](CPP_WORKFLOWS.md#workflow-2) - Modify evaluation
4. Try [CPP_WORKFLOWS.md#workflow-3](CPP_WORKFLOWS.md#workflow-3) - Add UCI command

### Advanced

1. Study [ARCHITECTURE.md#performance](CPP_ARCHITECTURE.md#performance-characteristics)
2. Try [CPP_WORKFLOWS.md#workflow-1](CPP_WORKFLOWS.md#workflow-1) - Implement search algorithm
3. Try [CPP_WORKFLOWS.md#workflow-4](CPP_WORKFLOWS.md#workflow-4) - Optimize performance
4. Read [RULE_SYSTEM_GUIDE.md](RULE_SYSTEM_GUIDE.md) - Master rule system

## ❓ Getting Help

### Documentation Issues

If documentation is:
- **Unclear**: Open issue with "docs:" prefix
- **Incorrect**: Create PR with fix
- **Missing**: Request new documentation

### Code Issues

1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Search existing GitHub issues
3. Create new issue with:
   - System info
   - Steps to reproduce
   - Expected vs actual behavior
   - Relevant code snippets

## 📝 Version Information

**Documentation Version**: 1.0.0  
**Engine Version**: See [include/version.h](../../include/version.h)  
**Maintainer**: Sanmill Development Team

## 📄 License

All documentation is licensed under GPL v3, same as the project.

---

**Ready to start coding?** Pick a task from [CPP_WORKFLOWS.md](CPP_WORKFLOWS.md) or browse [examples/](examples/)!

