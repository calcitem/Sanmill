# Fastmill Build Instructions

## Prerequisites

- C++17 compatible compiler (GCC 7.3+ or Clang 8.0+)
- Make utility
- Access to Sanmill source code (this tool reuses core components)

## Building on Different Platforms

### Linux / macOS / WSL

```bash
cd tools/fastmill
make clean
make
```

### Windows (Cygwin/MSYS2)

```bash
cd tools/fastmill
make clean
make
```

### Windows (Visual Studio)

For Visual Studio, you would need to create a project file or use CMake. The current Makefile is designed for Unix-like environments.

## Compilation Issues and Solutions

### Common Issues

1. **Missing config.h**: Ensure `../../include` is in include path
2. **Missing Sanmill headers**: Ensure `../../src` is in include path  
3. **C++17 support**: Use GCC 7.3+ or Clang 8.0+

### Testing Individual Components

Use the compilation test script:

```bash
chmod +x compile_test.sh
./compile_test.sh
```

This will test individual file compilation to isolate issues.

### Debug Build

```bash
make build=debug
```

### Release Build

```bash
make build=release
```

## Architecture Overview

Fastmill is designed to maximize code reuse from the existing Sanmill project:

### Core Components (New)
- `main.cpp` - Entry point
- `cli/cli_parser.*` - Command line parsing
- `utils/logger.*` - Logging system
- `stats/elo_calculator.*` - ELO rating calculation
- `tournament/tournament_manager.*` - Tournament coordination
- `tournament/match_runner.*` - Individual match execution
- `engine/mill_engine_wrapper.*` - UCI engine communication

### Reused Sanmill Components
- `types.h` - Core type definitions
- `position.h` - Game position representation
- `uci.h` - UCI protocol implementation
- `rule.h` - Mill rule variants
- `mills.h` - Mill-specific game logic
- `movegen.h` - Move generation
- `evaluate.h` - Position evaluation
- `bitboard.h` - Bitboard operations

## Troubleshooting

### Compilation Errors

1. **String concatenation errors**: Make sure to use `std::string` for concatenation
2. **Const qualifier errors**: Some Position methods are not const
3. **Missing includes**: Add necessary headers from Sanmill

### Runtime Issues

1. **Engine not found**: Check engine paths and permissions
2. **UCI communication**: Verify engines support UCI protocol
3. **Tournament hangs**: Check engine responsiveness and time controls

## Testing

After successful compilation:

```bash
# Test help
./fastmill -help

# Test version
./fastmill -version

# Test with actual engines (requires UCI-compatible Mill engines)
./fastmill -engine cmd=sanmill name=Engine1 \
           -engine cmd=sanmill name=Engine2 \
           -each tc=10+0.1 \
           -rounds 1
```

## Contributing

When adding new features:

1. Maintain code reuse principles
2. Use English comments
3. Follow existing code style
4. Test compilation on multiple platforms
5. Update documentation

## Platform-Specific Notes

### Windows
- Use MSYS2, Cygwin, or WSL for best compatibility
- Visual Studio support would require additional project files

### macOS
- May need to adjust compiler flags
- Ensure Xcode command line tools are installed

### Linux
- Should work out of the box with GCC/Clang
- Ensure development packages are installed
