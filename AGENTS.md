# AGENT INSTRUCTIONS

## Commit Workflow
- Before staging or committing changes, run `./format.sh s` from the
  repository root and wait for it to finish.
- Only run `git add` and `git commit` after the formatting script has
  completed successfully.

## Commit Message Rules
- Every commit message must include a body paragraph in addition to the
  subject line.
- Wrap all lines in the commit subject and body at 72 characters.

## Documentation
- After finishing your code changes, do not create new Markdown documents
  solely to summarize the modifications.

## Code Quality and Style Guidelines

### General Principles
- Generated code should prioritize high maintainability, generality,
  extensibility, and reusability.

### Error Handling
- Do not use try/catch blocks in C++ code.
- Avoid fallback mechanisms in code to prevent hiding issues.
- Use assertions for error handling instead of fallback schemes, so errors
  are surfaced rather than masked.

### Code Extension and Modification
- When extending functionality, modify existing functions directly rather
  than creating new "EnhancedXXX" functions or classes.
- Avoid creating wrapper classes or functions with names like "EnhancedXXX"
  as a way to extend existing code.
- Prefer direct modification of original implementations to maintain code
  clarity and avoid unnecessary abstraction layers.
