# Fastmill - Tournament Tool for Mill (Nine Men's Morris) Engines

Fastmill is a tournament management tool specifically designed for Mill (Nine Men's Morris) engines, based on the Sanmill engine framework. It allows you to run tournaments between different Mill engines with various configurations.

## Features

- **Multiple Tournament Types**: Round Robin, Gauntlet, and Swiss system tournaments
- **Engine Management**: Support for UCI-compatible Mill engines
- **Concurrent Execution**: Run multiple games simultaneously for faster tournaments
- **ELO Rating System**: Track and calculate engine ratings over time
- **Game Recording**: Save games in PGN format
- **Real-time Progress**: Monitor tournament progress with live updates
- **Mill-specific Rules**: Support for different Mill rule variants
- **Statistics**: Comprehensive tournament and game statistics

## Building

### Prerequisites

- C++17 compatible compiler (GCC 7.3+ or Clang 8.0+)
- Make utility
- Sanmill source code (this tool reuses core components)

### Compilation

```bash
cd tools/fastmill
make
```

For debug build:
```bash
make build=debug
```

For release build:
```bash
make build=release
```

## Usage

### Basic Tournament

Run a simple round-robin tournament between two engines:

```bash
./fastmill -engine cmd=sanmill name=Engine1 \
           -engine cmd=sanmill name=Engine2 \
           -each tc=60+1 \
           -rounds 10 \
           -concurrency 2
```

### Advanced Configuration

```bash
./fastmill -engine cmd=./engine1 name="Engine A" dir=/path/to/engine1 \
           -engine cmd=./engine2 name="Engine B" dir=/path/to/engine2 \
           -engine cmd=./engine3 name="Engine C" \
           -tournament roundrobin \
           -each tc=120+2 \
           -rounds 5 \
           -concurrency 4 \
           -pgnout tournament_games.pgn \
           -log tournament.log
```

### Command Line Options

- `-engine cmd=ENGINE name=NAME [dir=DIR]` - Add an engine to the tournament
- `-each tc=TIME_CONTROL` - Set time control for all engines (format: base+increment in seconds)
- `-rounds N` - Number of rounds to play
- `-concurrency N` - Number of concurrent games
- `-tournament TYPE` - Tournament type (roundrobin, gauntlet, swiss)
- `-openings FILE` - Opening book file (future feature)
- `-pgnout FILE` - Save games to PGN file
- `-log FILE` - Log file path
- `-help` - Show help message
- `-version` - Show version information

### Time Control Format

Time controls are specified in the format `base+increment` where:
- `base` is the base time in seconds
- `increment` is the increment per move in seconds

Examples:
- `60+1` - 1 minute base + 1 second increment
- `300+5` - 5 minutes base + 5 seconds increment
- `180+0` - 3 minutes base + no increment

### Tournament Types

1. **Round Robin** (`roundrobin`): Each engine plays against every other engine
2. **Gauntlet** (`gauntlet`): First engine plays against all others
3. **Swiss** (`swiss`): Swiss system pairing (future implementation)

## Architecture

Fastmill is designed to maximize code reuse from the existing Sanmill project:

### Core Components

- **Engine Wrapper** (`mill_engine_wrapper.cpp`): Manages UCI communication with Mill engines
- **Tournament Manager** (`tournament_manager.cpp`): Coordinates tournament execution
- **Match Runner** (`match_runner.cpp`): Handles individual matches between engines
- **ELO Calculator** (`elo_calculator.cpp`): Calculates and tracks engine ratings
- **CLI Parser** (`cli_parser.cpp`): Command line argument processing

### Reused Sanmill Components

- `types.h` - Core type definitions
- `position.h` - Game position representation
- `uci.h` - UCI protocol implementation
- `rule.h` - Mill rule variants
- `mills.h` - Mill-specific game logic
- `movegen.h` - Move generation
- `bitboard.h` - Bitboard operations

## Mill Rule Support

Fastmill supports different Mill rule variants through the existing Sanmill rule system. The tool can be configured to use specific rule variants for tournaments.

## Output Formats

### Console Output
- Real-time tournament progress
- Live standings with ELO ratings
- Final tournament results and statistics

### PGN Files
Games can be saved in PGN format for analysis and archival purposes.

### Log Files
Detailed logging of tournament execution, engine communication, and errors.

## Examples

### Simple Engine vs Engine Match
```bash
./fastmill -engine cmd=sanmill name=Sanmill1 \
           -engine cmd=sanmill name=Sanmill2 \
           -each tc=30+0.5 \
           -rounds 1
```

### Multi-Engine Tournament
```bash
./fastmill -engine cmd=./engine_a name="Engine A" \
           -engine cmd=./engine_b name="Engine B" \
           -engine cmd=./engine_c name="Engine C" \
           -engine cmd=./engine_d name="Engine D" \
           -tournament roundrobin \
           -each tc=60+1 \
           -rounds 2 \
           -concurrency 3 \
           -pgnout results.pgn
```

## Development

### Adding New Features

The modular design makes it easy to add new features:

1. **New Tournament Types**: Extend `TournamentManager::generateXXXPairings()`
2. **New Statistics**: Add to `elo_calculator.cpp` or create new stat modules
3. **New Output Formats**: Extend output management in `tournament_manager.cpp`

### Testing

```bash
make tests
./fastmill-tests
```

## License

This project inherits the GPL-3.0-or-later license from the Sanmill project.

## Contributing

Contributions are welcome! Please ensure that:
1. Code follows the existing style and patterns
2. New features are well-tested
3. Documentation is updated accordingly
4. Changes are beneficial for Mill engine tournaments

## Troubleshooting

### Engine Not Starting
- Verify engine path and permissions
- Check engine supports UCI protocol
- Review log files for detailed error messages

### Tournament Hangs
- Check engine responsiveness
- Verify time controls are reasonable
- Monitor system resources

### Compilation Issues
- Ensure all Sanmill dependencies are available
- Check compiler version (C++17 required)
- Verify include paths in Makefile

## Future Enhancements

- Opening book support
- Swiss system tournament implementation
- Web-based tournament monitoring
- Advanced adjudication options
- Database integration for historical results
- Cross-platform GUI interface
