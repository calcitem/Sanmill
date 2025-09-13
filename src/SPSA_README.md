# SPSA Parameter Tuning System for Sanmill

## Overview

This SPSA (Simultaneous Perturbation Stochastic Approximation) parameter tuning system provides automated optimization of Sanmill's evaluation function parameters **for traditional search algorithms only**. 

**⚠️ IMPORTANT: This system is designed ONLY for Alpha-Beta, PVS, and MTD(f) algorithms. It is NOT compatible with MCTS!**

The system uses a sophisticated algorithm to find optimal parameter values through iterative self-play testing of traditional search algorithms.

## Key Features

- **Automated Parameter Optimization**: Uses SPSA algorithm for efficient high-dimensional parameter optimization
- **Parallel Game Testing**: Multi-threaded game playing for fast evaluation
- **Convergence Detection**: Automatic stopping when optimal parameters are found
- **Checkpoint System**: Resume interrupted tuning sessions
- **Comprehensive Logging**: Detailed logs of the tuning process
- **Interactive Mode**: Real-time monitoring and control

## Algorithm Description

### SPSA (Simultaneous Perturbation Stochastic Approximation)

SPSA is a gradient-free optimization algorithm particularly well-suited for noisy objective functions like chess engine evaluation. The algorithm works by:

1. **Simultaneous Perturbation**: All parameters are perturbed simultaneously with random ±1 values
2. **Stochastic Approximation**: Gradient is estimated using only two function evaluations regardless of parameter count
3. **Parameter Update**: Parameters are updated in the direction of estimated gradient

### Key Advantages

- **Efficiency**: Only 2 evaluations per iteration regardless of parameter count
- **Robustness**: Works well with noisy evaluations from game outcomes
- **Proven**: Successfully used in many chess engines and optimization problems

## Compilation

### Using the Provided Makefile

```bash
# Compile the SPSA tuner
make -f spsa_tuner_makefile

# Create example configuration files
make -f spsa_tuner_makefile examples

# Install to bin directory
make -f spsa_tuner_makefile install
```

### Manual Compilation

```bash
g++ -std=c++17 -O3 -Wall -Wextra -pthread -I. \
    spsa_tuner.cpp spsa_main.cpp position.cpp evaluate.cpp \
    search.cpp search_engine.cpp movegen.cpp movepick.cpp \
    option.cpp bitboard.cpp mills.cpp tt.cpp misc.cpp \
    thread.cpp thread_pool.cpp rule.cpp engine_commands.cpp \
    uci.cpp ucioption.cpp -o spsa_tuner -pthread
```

## Usage

### Basic Usage

```bash
# Start tuning with default parameters
./spsa_tuner

# Tune with specific number of iterations and games
./spsa_tuner --iterations 500 --games 200

# Use custom configuration file
./spsa_tuner --config my_config.txt

# Resume from checkpoint
./spsa_tuner --resume checkpoint.txt
```

### Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `-h, --help` | Show help message | - |
| `-c, --config FILE` | Load configuration from file | - |
| `-p, --params FILE` | Load initial parameters from file | - |
| `-o, --output FILE` | Save best parameters to file | - |
| `-l, --log FILE` | Log file path | spsa_tuning.log |
| `-i, --iterations N` | Maximum iterations | 1000 |
| `-g, --games N` | Games per evaluation | 100 |
| `-t, --threads N` | Maximum threads | 8 |
| `-a, --learning-rate R` | Learning rate parameter | 0.16 |
| `-s, --perturbation R` | Perturbation parameter | 0.05 |
| `-r, --resume FILE` | Resume from checkpoint | - |
| `--alpha R` | Learning rate decay exponent | 0.602 |
| `--gamma R` | Perturbation decay exponent | 0.101 |
| `--convergence R` | Convergence threshold | 0.001 |
| `--window N` | Convergence window size | 50 |

### Interactive Mode

```bash
./spsa_tuner --interactive
```

Interactive commands:
- `start` - Start tuning process
- `stop` - Stop tuning process  
- `status` - Show current status
- `params` - Show current parameters
- `save FILE` - Save parameters to file
- `load FILE` - Load parameters from file
- `quit` - Exit program

## Configuration

### Configuration File Format

```ini
# SPSA Configuration
learning_rate=0.16
perturbation=0.05
stability=100
alpha=0.602
gamma=0.101
max_iterations=1000
games_per_evaluation=100
max_threads=8
convergence_threshold=0.001
convergence_window=50
log_file=spsa_tuning.log
checkpoint_file=spsa_checkpoint.txt
checkpoint_frequency=10
```

### Parameter File Format

```
# Format: name value min_value max_value perturbation_size is_integer
exploration_parameter 0.500000 0.100000 2.000000 0.100000 0
bias_factor 0.050000 0.000000 0.200000 0.010000 0
alpha_beta_depth 6.000000 3.000000 12.000000 1.000000 1
piece_value 5.000000 1.000000 20.000000 1.000000 1
mobility_weight 1.000000 0.000000 3.000000 0.100000 0
```

## Tunable Parameters (Traditional Search Algorithms Only)

The system can optimize the following parameters for Alpha-Beta, PVS, and MTD(f) algorithms:

### Search Algorithm Parameters
| Parameter | Description | Type | Range |
|-----------|-------------|------|-------|
| `max_search_depth` | Maximum search depth | Integer | 4 - 16 |
| `quiescence_depth` | Quiescence search depth | Integer | 8 - 32 |
| `null_move_reduction` | Null move pruning reduction | Integer | 1 - 6 |
| `late_move_reduction` | Late move reduction | Integer | 1 - 4 |
| `futility_margin` | Futility pruning margin | Integer | 50 - 300 |
| `razor_margin` | Razoring margin | Integer | 20 - 150 |

### Basic Evaluation Parameters
| Parameter | Description | Type | Range |
|-----------|-------------|------|-------|
| `piece_value` | Base piece value | Integer | 1 - 20 |
| `piece_inhand_value` | In-hand piece value | Integer | 1 - 20 |
| `piece_onboard_value` | On-board piece value | Integer | 1 - 20 |
| `piece_needremove_value` | Removable piece penalty | Integer | 1 - 20 |

### Positional Evaluation Weights
| Parameter | Description | Type | Range |
|-----------|-------------|------|-------|
| `mobility_weight` | Mobility evaluation weight | Float | 0.0 - 3.0 |
| `center_control_weight` | Center control weight | Float | 0.0 - 2.0 |
| `mill_potential_weight` | Mill formation potential weight | Float | 0.0 - 3.0 |
| `blocking_weight` | Opponent mill blocking weight | Float | 0.0 - 2.0 |

### Endgame and Tempo Parameters
| Parameter | Description | Type | Range |
|-----------|-------------|------|-------|
| `endgame_piece_threshold` | Endgame piece count threshold | Integer | 3 - 10 |
| `endgame_mobility_bonus` | Extra mobility importance in endgame | Float | 0.5 - 3.0 |
| `tempo_bonus` | Bonus for having the move | Float | 0.0 - 0.5 |

### Mill Evaluation Parameters
| Parameter | Description | Type | Range |
|-----------|-------------|------|-------|
| `mill_value` | Base value of a mill | Integer | 5 - 30 |
| `potential_mill_value` | Value of potential mill (2 pieces) | Integer | 1 - 10 |
| `broken_mill_penalty` | Penalty for broken mill | Integer | 2 - 20 |

## Algorithm Parameters

### Learning Rate (a)
- Controls step size for parameter updates
- Typical range: 0.05 - 0.5
- Higher values = faster convergence but less stable
- Lower values = more stable but slower convergence

### Perturbation Size (c)
- Controls size of parameter perturbations
- Typical range: 0.01 - 0.1
- Should be roughly 1-2 standard deviations of noise
- Automatically decays over iterations

### Stability Constant (A)
- Prevents learning rate from being too high initially
- Typical range: 50 - 200
- Higher values = more conservative early updates

### Decay Exponents
- **Alpha (α)**: Learning rate decay, recommended 0.602
- **Gamma (γ)**: Perturbation decay, recommended 0.101
- These are theoretical optimal values from SPSA literature

## Output Files

### Log File
Contains detailed iteration-by-iteration results:
```
2023-12-15 10:30:15 Iter:0 Score+:0.5234 Score-:0.4891 Grad:0.003429 Best:0.5234 Params:exploration_parameter=0.5123,bias_factor=0.0487,...
```

### Checkpoint File
Stores current state for resuming:
```
42 0.5678
0.5234
0.5156
0.5289
...
```

### Parameter Files
Best parameters found during tuning:
```
exploration_parameter 0.523400 0.100000 2.000000 0.100000 0
bias_factor 0.048700 0.000000 0.200000 0.010000 0
...
```

## Performance Considerations

### Games Per Evaluation
- More games = more accurate evaluation but slower
- Recommended: 50-200 games depending on available time
- Use fewer games for initial exploration, more for final refinement

### Thread Count
- More threads = faster game playing
- Recommended: Number of CPU cores
- Diminishing returns beyond 8-16 threads

### Convergence Detection
- Monitors standard deviation of recent scores
- Stops when improvement plateaus
- Adjust threshold and window size based on desired precision

## Best Practices

### Initial Parameter Selection
1. Start with current engine defaults
2. Use reasonable bounds (not too wide)
3. Set appropriate perturbation sizes (10-20% of parameter range)

### Tuning Process
1. Start with fewer games per evaluation for exploration
2. Increase games per evaluation as you approach optimum  
3. Use checkpoints for long tuning runs
4. Monitor logs for convergence patterns

### Validation
1. Test final parameters against baseline in separate matches
2. Verify improvements are statistically significant
3. Test on different time controls and positions

## Troubleshooting

### Common Issues

**Slow Convergence**
- Increase learning rate
- Decrease stability constant
- Check if perturbation sizes are appropriate

**Unstable Results**
- Decrease learning rate  
- Increase games per evaluation
- Check for bugs in evaluation function

**No Improvement**
- Parameters may already be near optimal
- Try different parameter bounds
- Increase perturbation sizes

**High Memory Usage**
- Reduce thread count
- Check for memory leaks in game playing code

### Debugging

Enable verbose logging and check:
- Parameter bounds are reasonable
- Games are completing properly
- Score calculations are correct
- No infinite loops in game playing

## Advanced Usage

### Custom Parameters
Add new parameters by modifying the `initialize_default_parameters()` function in `spsa_tuner.cpp`.

### Custom Evaluation
Modify the `apply_parameters()` function in the `GameEngine` class to use optimized parameters.

### Multi-Stage Tuning
1. Tune major parameters first (piece values, depth)
2. Then tune minor parameters (mobility weights, etc.)
3. Finally, fine-tune all parameters together

## References

1. Spall, J.C. (1998). "An Overview of the Simultaneous Perturbation Method for Efficient Optimization"
2. Spall, J.C. (1992). "Multivariate Stochastic Approximation Using a Simultaneous Perturbation Gradient Approximation"
3. Various chess engine tuning papers and implementations

## License

This SPSA tuning system is part of the Sanmill project and is licensed under GPL-3.0-or-later.
