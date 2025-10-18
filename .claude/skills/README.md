---
# Sanmill Claude Code Skills

Custom Claude Code Skills for the Sanmill project. These Skills extend Claude Code's capabilities with project-specific workflows and automation.

## What are Skills?

Skills are modular components that package instructions, workflows, and best practices. Claude Code automatically invokes relevant Skills based on your requests.

Each Skill is a directory containing a `SKILL.md` file with:
- **YAML frontmatter**: Name and description for auto-detection
- **Markdown content**: Instructions, commands, and workflows

## Available Skills

### 1. New Rule Completeness Validator
**Directory**: `game-rule-validator/`
**Purpose**: Validate completeness when adding new game rules

Ensures all necessary files are modified when adding game rule variants (typically 70-80 files including localizations). Provides comprehensive checklists for C++ engine, Flutter UI, tests, and documentation.

**Trigger examples**:
- "Check if I missed any files when adding the new rule"
- "Validate new game rule implementation"

### 2. Flutter Test Runner
**Directory**: `flutter-test-runner/`
**Purpose**: Run and manage Flutter test suite

Provides commands and workflows for unit tests, widget tests, and integration tests. Includes coverage generation and common troubleshooting.

**Trigger examples**:
- "Run Flutter tests"
- "Generate test coverage report"

### 3. C++ Code Formatter
**Directory**: `cpp-formatter/`
**Purpose**: Format C++ code for style consistency

Uses project's `format.sh` script and `.clang-format` configuration to ensure consistent code style across the codebase.

**Trigger examples**:
- "Format C++ code"
- "Check code style"

## How to Use Skills

### Automatic Invocation
Claude Code automatically selects and uses Skills based on your request:

```
You: "I just added a new game rule, did I miss anything?"
→ Triggers: New Rule Completeness Validator
```

Skills work in the background - you don't need to explicitly call them.

### Manual Reference
Browse individual `SKILL.md` files for detailed workflows and commands.

## Creating Custom Skills

### Basic Structure

```
.claude/skills/my-skill/
└── SKILL.md
```

### SKILL.md Format

```markdown
---
name: "Skill Name"
description: "What it does and when to use it"
---

# Skill Name

## Purpose
...

## Use Cases
...

## Quick Commands
...
```

### Key Guidelines

1. **Clear description**: Explain both what the Skill does AND when to use it
2. **Concise content**: Focus on commands and workflows, avoid long explanations
3. **Minimal file lists**: Avoid listing many specific files (hard to maintain)
4. **Reference docs**: Point to authoritative sources instead of duplicating
5. **Project-specific**: Use actual project scripts and configurations

### YAML Frontmatter

- **name** (required): Display name (max 64 chars)
- **description** (required): Purpose and trigger conditions (max 200 chars)
  - Claude uses this to decide when to invoke the Skill

## Skill Locations

### Project-level (Current)
```
/home/user/Sanmill/.claude/skills/
```
- Specific to Sanmill project
- Shared with team via Git
- Recommended for project workflows

### User-level (Optional)
```
~/.claude/skills/
```
- Available across all projects
- Personal preferences and general tools
- Not shared with team

## Best Practices

1. **Keep Skills focused**: One Skill = one workflow
2. **Update regularly**: Remove outdated information
3. **Test descriptions**: Ensure Claude triggers them correctly
4. **Reference existing**: Look at project Skills as templates
5. **Avoid duplication**: Point to docs instead of copying content

## Maintenance

When project structure changes:
- Update Skill documentation
- Test that Skills still trigger correctly
- Remove references to deleted files/scripts
- Add new workflows as separate Skills

## Reference Resources

- **Official documentation**: https://www.anthropic.com/news/skills
- **GitHub repository**: https://github.com/anthropics/skills
- **Claude Code docs**: https://docs.claude.com/en/docs/claude-code
- **Project guide**: `docs/guides/ADDING_NEW_GAME_RULES.md`

## Contributing

To add or improve Skills:

1. Create/edit Skill in `.claude/skills/your-skill/`
2. Write clear `SKILL.md` with proper frontmatter
3. Test by making relevant requests to Claude Code
4. Commit and push to share with team

```bash
git add .claude/skills/
git commit -m "Add/update Claude Code skill: <skill-name>"
git push
```

Team members get the Skills automatically when they pull.

---

**Note**: Skills are loaded automatically by Claude Code. No installation or configuration needed - just create the directory structure and `SKILL.md` file.
