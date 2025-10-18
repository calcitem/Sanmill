---
name: "C++ Code Formatter"
description: "Format C++ code in Sanmill project to ensure consistent code style; use when formatting C++ code or checking code style compliance."
---

# C++ Code Formatter

## Purpose

This skill helps format Sanmill's C++ code to ensure code style consistency and maintainability across the codebase.

## Use Cases

- Format C++ code after modifications
- Check code style compliance
- Format code before committing
- Batch format project C++ files
- Validate code style in CI/CD pipelines

## Quick Commands

### Using Project Script (Recommended)

```bash
# Format all C++ and Dart code (will auto-commit)
./format.sh

# Format without auto-commit
./format.sh s
```

The script formats:
- All `.h` and `.cpp` files in `src/`, `include/`, `tests/`
- All Dart files in the project
- Uses project's `.clang-format` configuration

### Manual Formatting

```bash
# Format single file
clang-format -i src/position.cpp

# Format multiple files
clang-format -i src/*.cpp src/*.h

# Check without modifying (dry-run)
clang-format --dry-run --Werror src/position.cpp
```

## Configuration

### Project Configuration Files
- **`.clang-format`** - C++ formatting rules (project root)
- **`CPPLINT.cfg`** - Code style checking rules
- **`.editorconfig`** - Editor-specific settings

### View Current Configuration
```bash
cat .clang-format
```

## Code Style Checking

```bash
# Check specific file with cpplint
cpplint --config=CPPLINT.cfg src/position.cpp

# The configuration file defines which checks to enable/disable
```

## Git Integration

### Pre-commit Workflow
```bash
# 1. Make code changes
# 2. Format code
./format.sh s

# 3. Review changes
git diff

# 4. If correct, commit
git add .
git commit -m "Your commit message"
```

### Format Only Staged Files
```bash
git diff --cached --name-only --diff-filter=ACM | \
grep -E '\.(cpp|h|cc|hpp)$' | \
xargs clang-format -i
```

## Common Issues & Solutions

### 1. Format Breaks Code Structure
- **Check**: Verify `.clang-format` configuration
- **Check**: Ensure clang-format version matches team standard
- **Workaround**: Use `// clang-format off` and `// clang-format on` for special blocks

### 2. Batch Formatting Creates Large Changes
- **Solution**: Format in batches and commit separately
- **Label**: Use clear commit message like "style: Format C++ code"
- **Communicate**: Notify team members to sync

### 3. Format Conflicts Between Developers
- **Ensure**: All use same `.clang-format` file
- **Ensure**: All use same clang-format version
- **Establish**: Team formatting conventions

## Best Practices

1. **Format frequently**: Format after each significant change
2. **Format before commits**: Always format before committing
3. **Review formatting changes**: Don't blindly commit formatting
4. **Use project script**: Prefer `./format.sh` over manual commands
5. **Separate formatting commits**: Keep formatting separate from logic changes
6. **Don't hand-edit formatting**: Let tools do the work

## Tools Required

### clang-format
```bash
# Check if installed
clang-format --version

# Install on Ubuntu/Debian
sudo apt-get install clang-format

# Install on macOS
brew install clang-format
```

### cpplint (Optional)
For additional style checking beyond formatting.

## Output Format

Formatting operations should report:
- ✓ Files formatted successfully
- ⚠ Files with style violations
- ✗ Files that failed to format
- 📊 Total files processed
- 💡 Style improvement recommendations

## Reference Resources

- **Configuration**: `.clang-format`, `CPPLINT.cfg`, `.editorconfig` (project root)
- **Format script**: `format.sh` (project root)
- **clang-format docs**: https://clang.llvm.org/docs/ClangFormat.html
- **C++ source locations**: `src/`, `include/`, `tests/`
