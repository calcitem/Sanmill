# Documentation Maintenance Guide

## Overview

This guide explains how to maintain, update, and create documentation for the Sanmill Flutter application. High-quality documentation is crucial for both human developers and AI agents working on the project.

**Target Audience**: Developers and documentation maintainers

## Documentation Philosophy

### Core Principles

1. **Documentation is Code**: Treat docs with the same rigor as source code
2. **AI-First Design**: Write docs that AI agents can parse and understand
3. **Single Source of Truth**: Avoid redundancy; link instead of duplicating
4. **Always Up-to-Date**: Update docs simultaneously with code changes
5. **Example-Driven**: Show, don't just tell

### Why Documentation Matters for AI

In traditional development, poor documentation is frustrating. With AI agents:
- **Poor documentation → AI generates incorrect code**
- **Good documentation → AI generates high-quality, consistent code**

Documentation is literally the "SDK" (Software Development Kit) that AI uses to understand and work with our codebase.

## Documentation Structure

### Current Documentation

```
src/ui/flutter_app/docs/
├── ARCHITECTURE.md          # System architecture overview
├── COMPONENTS.md            # Component catalog
├── STATE_MANAGEMENT.md      # State management patterns
├── WORKFLOWS.md             # Development workflows
├── BEST_PRACTICES.md        # Code quality guidelines
├── GETTING_STARTED.md       # Developer onboarding
├── DOCUMENTATION_GUIDE.md   # This file
├── api/                     # API documentation
│   ├── GameController.md
│   ├── Engine.md
│   ├── Position.md
│   └── widgets/             # UI component docs
├── examples/                # Code examples
└── templates/               # Code templates
```

### Documentation Categories

| Category | Purpose | Examples |
|----------|---------|----------|
| **Architecture** | Explain system design | ARCHITECTURE.md |
| **Reference** | API documentation | api/*.md |
| **Guide** | How-to instructions | WORKFLOWS.md |
| **Tutorial** | Learning material | GETTING_STARTED.md |
| **Standards** | Rules and conventions | BEST_PRACTICES.md |

## When to Update Documentation

### Always Update

**When you:**
- Add a new component/service/widget
- Change a public API (method signature, parameters)
- Add a new setting or configuration option
- Introduce a new design pattern
- Add a new workflow or process
- Fix a significant bug that reveals a documentation gap

### Sometimes Update

**When you:**
- Refactor internal implementation (update if behavior changes)
- Add minor helper methods (document in code, not necessarily in docs)
- Fix typos or minor bugs (usually code comments are sufficient)

### Example Decision Tree

```
Did you add a new public API?
├─ Yes → Update API documentation (api/*.md)
└─ No → Did you change how something works?
    ├─ Yes → Update relevant guide (WORKFLOWS.md, etc.)
    └─ No → Did you add a new concept/pattern?
        ├─ Yes → Update ARCHITECTURE.md
        └─ No → Code comments might be sufficient
```

## Documentation Types

### 1. Architecture Documentation

**File**: `ARCHITECTURE.md`

**Update when**:
- Adding new architectural layer
- Introducing new design pattern
- Changing technology stack
- Modifying module structure

**Format**:
```markdown
## New Section

Brief overview of the concept.

### Key Points
- Point 1
- Point 2

### Example
\`\`\`dart
// Example code
\`\`\`

### Diagram (optional)
\`\`\`
ASCII art or description
\`\`\`
```

---

### 2. Component Catalog

**File**: `COMPONENTS.md`

**Update when**:
- Adding new reusable component
- Changing component public API
- Deprecating old component

**Template**:
```markdown
### ComponentName
**Location**: `lib/path/to/component.dart`

**Purpose**: Brief description

**Key Responsibilities**:
- Responsibility 1
- Responsibility 2

**Public API**:
- `method1()`: Description
- `property1`: Description

**Dependencies**: List of dependencies

**Usage Context**: When to use this component

**Example**:
\`\`\`dart
final component = ComponentName();
component.method1();
\`\`\`
```

---

### 3. API Documentation

**Files**: `api/*.md`

**Update when**:
- Adding new public method/property
- Changing method signature
- Adding new parameter
- Changing behavior

**Template**:
```markdown
#### `methodName()`
\`\`\`dart
ReturnType methodName(ParamType param) async
\`\`\`

Brief description of what this method does.

**Parameters**:
- `param` (ParamType): Description

**Returns**: `ReturnType` - Description

**Side Effects**:
- Effect 1
- Effect 2

**Example**:
\`\`\`dart
final result = await obj.methodName(value);
\`\`\`

**Use Cases**:
- Use case 1
- Use case 2

**Errors**:
- Throws `ExceptionType` if condition
```

---

### 4. Workflows

**File**: `WORKFLOWS.md`

**Update when**:
- Establishing new development process
- Changing existing workflow
- Adding common task procedure

**Template**:
```markdown
## Workflow N: Task Name

### Goal
Clear statement of what this workflow achieves.

### Steps

#### 1. Step Name
Description of step.

\`\`\`bash
# Commands to run
\`\`\`

\`\`\`dart
// Code to write
\`\`\`

#### 2. Next Step
...

### Example: Concrete Use Case
Complete example showing the workflow in action.
```

---

### 5. Code Examples

**Directory**: `docs/examples/`

**Create when**:
- Introducing complex pattern
- Showing best practice implementation
- Demonstrating component integration

**Structure**:
```
examples/
├── state_management/
│   ├── hive_persistence.dart
│   └── notifier_pattern.dart
├── widgets/
│   ├── custom_painter_example.dart
│   └── animation_example.dart
└── README.md  # Index of all examples
```

**Format**:
```dart
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// example_name.dart

/// Example: [What this demonstrates]
///
/// This example shows how to [explanation].
///
/// Key concepts:
/// - Concept 1
/// - Concept 2
///
/// See also:
/// - [Related doc](../path/to/doc.md)

import 'package:flutter/material.dart';

void main() {
  runApp(const ExampleApp());
}

// Well-commented example code...
```

---

### 6. Code Templates

**Directory**: `docs/templates/`

**Create when**:
- Establishing standard structure for common components
- Providing boilerplate for frequent tasks

**Examples**:
- `widget_template.dart`: Standard widget structure
- `service_template.dart`: Standard service structure
- `settings_page_template.dart`: Settings page structure

---

## Writing Effective Documentation

### Style Guidelines

#### 1. Be Concise and Clear

```markdown
❌ Bad: Verbose
This method performs an operation that will result in the execution of a move on the game board, which will then update the internal state representation.

✅ Good: Clear
Executes a move on the board and updates game state.
```

#### 2. Use Active Voice

```markdown
❌ Bad: Passive
The move is validated by the Position class.

✅ Good: Active
The Position class validates the move.
```

#### 3. Provide Examples

```markdown
❌ Bad: Abstract only
Use the GameController to manage game state.

✅ Good: Concrete example
\`\`\`dart
final controller = GameController();
await controller.newGame();
controller.doMove(move);
\`\`\`
```

#### 4. Explain Why, Not Just What

```markdown
❌ Bad: What only
Use RepaintBoundary around CustomPaint.

✅ Good: Why and what
Use RepaintBoundary around CustomPaint to isolate expensive
repaints from the rest of the widget tree, improving performance
by 8-10ms per frame.
```

#### 5. Structure for Scanning

Use:
- **Headings** to organize sections
- **Lists** for multiple items
- **Tables** for comparisons
- **Code blocks** for examples
- **Bold** for key terms

```markdown
✅ Good: Scannable

### Key Concepts

**State Management**:
- **Persistent**: Stored in Hive
- **Transient**: Held in ValueNotifier
- **Session**: Managed by GameController

| State Type | Storage | Example |
|------------|---------|---------|
| Persistent | Hive | Settings |
| Transient | ValueNotifier | UI messages |
```

#### 6. Link Generously

```markdown
✅ Good: Cross-referenced
See [GameController API](api/GameController.md) for details.
Refer to [State Management](STATE_MANAGEMENT.md) for patterns.
```

#### 7. Keep Examples Realistic

```dart
// ❌ Bad: Toy example
final controller = Controller();
controller.doThing();

// ✅ Good: Realistic example
final controller = GameController();
await controller.newGame();

if (controller.isControllerReady) {
  final move = Move(from: 5, to: 10);
  await controller.doMove(move);
}
```

---

## Markdown Best Practices

### Headers

Use ATX-style headers (`#`), not Setext-style:

```markdown
✅ Good:
## Section Title

❌ Bad:
Section Title
-------------
```

### Code Blocks

Always specify language for syntax highlighting:

````markdown
✅ Good:
```dart
void main() {}
```

❌ Bad:
```
void main() {}
```
````

### Lists

Use consistent markers:

```markdown
✅ Good:
- Item 1
- Item 2
  - Subitem 2.1
  - Subitem 2.2

❌ Bad:
* Item 1
- Item 2
  * Subitem 2.1
  + Subitem 2.2
```

### Links

Use reference-style for repeated links:

```markdown
✅ Good:
[Flutter docs][flutter] and [Dart docs][dart] are helpful.

[flutter]: https://flutter.dev/docs
[dart]: https://dart.dev/guides

❌ Bad:
[Flutter docs](https://flutter.dev/docs) and
[Dart docs](https://dart.dev/guides) are helpful.
```

---

## Documentation Review Checklist

Before finalizing documentation:

### Content

- [ ] Accurate (matches current implementation)
- [ ] Complete (covers all public API)
- [ ] Clear (understandable to target audience)
- [ ] Concise (no unnecessary verbosity)
- [ ] Examples provided
- [ ] Links to related docs

### Structure

- [ ] Proper heading hierarchy (H1 → H2 → H3)
- [ ] Scannable (uses lists, tables, bold)
- [ ] Well-organized (logical flow)
- [ ] Table of contents (for long docs)

### Quality

- [ ] No typos or grammatical errors
- [ ] Code examples work (tested)
- [ ] Links work (not broken)
- [ ] Formatting consistent
- [ ] Follows style guide

### AI-Friendliness

- [ ] Structured format (Markdown)
- [ ] Clear section headers
- [ ] Code examples are complete
- [ ] Explicit (not implicit) information
- [ ] No ambiguous references

---

## AI-Assisted Documentation

### Using AI to Generate Documentation

AI can help write documentation, but always review and refine:

**Good prompts**:
```
"Document the GameController.newGame() method in our API doc format.
Include parameters, return value, side effects, example usage, and
use cases."

"Create a workflow for adding a new settings option, following the
format in WORKFLOWS.md. Include all steps from model update to UI
integration."
```

**Always verify**:
- Accuracy (AI might hallucinate)
- Completeness (AI might miss edge cases)
- Consistency (matches existing style)

### Maintaining AI-Generated Docs

When AI generates code:
- **Require** AI to update documentation
- **Review** documentation for accuracy
- **Refine** for clarity and style

---

## Documentation Maintenance Schedule

### After Every Code Change

- Update inline code comments (docstrings)
- Update relevant API docs if public API changed

### Weekly

- Review recent code changes
- Check for documentation gaps
- Update examples if patterns evolved

### Monthly

- Audit all documentation for accuracy
- Update version numbers/dates
- Fix broken links
- Refresh examples

### Before Each Release

- Comprehensive documentation review
- Update ARCHITECTURE.md with new features
- Refresh GETTING_STARTED.md if setup changed
- Verify all examples work with new version

---

## Common Documentation Mistakes

### 1. Outdated Examples

```markdown
❌ Bad: Old API
\`\`\`dart
controller.makeMove(move);  // Outdated - method renamed
\`\`\`

✅ Good: Current API
\`\`\`dart
controller.doMove(move);  // Current method name
\`\`\`
```

### 2. Missing Context

```markdown
❌ Bad: No context
Call `setup()` first.

✅ Good: With context
Before calling `newGame()`, ensure the controller is initialized
by calling `setup()`:
\`\`\`dart
await controller.setup();
await controller.newGame();
\`\`\`
```

### 3. Unclear References

```markdown
❌ Bad: Ambiguous
Use the notifier to update the UI.

✅ Good: Specific
Use `controller.headerTipNotifier` to update the header message:
\`\`\`dart
controller.headerTipNotifier.showTip('Your turn!');
\`\`\`
```

### 4. No Examples

```markdown
❌ Bad: Theory only
ValueNotifier provides reactive state updates.

✅ Good: With example
ValueNotifier provides reactive state updates:
\`\`\`dart
final notifier = ValueNotifier<int>(0);

ValueListenableBuilder<int>(
  valueListenable: notifier,
  builder: (context, value, _) => Text('$value'),
)

notifier.value = 5;  // UI rebuilds automatically
\`\`\`
```

### 5. Incomplete API Docs

```markdown
❌ Bad: Minimal
#### `makeMove()`
Makes a move.

✅ Good: Complete
#### `makeMove()`
\`\`\`dart
Future<bool> makeMove(Move move) async
\`\`\`

Execute a move on the board.

**Parameters**:
- `move` (Move): The move to execute

**Returns**: `Future<bool>` - `true` if successful

**Side Effects**:
- Updates Position
- Records in GameRecorder
- Triggers animations
- Updates notifiers

**Example**:
\`\`\`dart
final move = Move(from: 5, to: 10);
final success = await controller.makeMove(move);
\`\`\`

**Throws**: `AssertionError` if move is null
```

---

## Tools and Automation

### Documentation Linting

Use `markdownlint` to check docs:

```bash
npm install -g markdownlint-cli

markdownlint docs/**/*.md
```

### Link Checking

Use `markdown-link-check`:

```bash
npm install -g markdown-link-check

markdown-link-check docs/**/*.md
```

### Spell Checking

Use `cspell`:

```bash
npm install -g cspell

cspell "docs/**/*.md"
```

---

## Getting Help

### Questions About Documentation?

1. Check existing documentation structure
2. Look at similar examples
3. Ask in GitHub Discussions
4. Tag documentation maintainers

### Proposing Documentation Changes?

1. Open an issue describing the gap
2. Submit a pull request with the fix
3. Follow this guide's standards

---

## Summary

**Key Takeaways**:

1. **Update docs with code** - Never leave docs for later
2. **Write for AI** - Clear structure, complete examples
3. **Show, don't tell** - Provide concrete examples
4. **Link generously** - Create web of knowledge
5. **Review regularly** - Keep docs accurate and current

**Good documentation = Better code quality = Faster development**

---

## References

- [Markdown Guide](https://www.markdownguide.org/)
- [Write the Docs](https://www.writethedocs.org/)
- [Google Developer Documentation Style Guide](https://developers.google.com/style)

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

