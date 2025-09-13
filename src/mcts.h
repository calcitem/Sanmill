// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// mcts.h - Hybrid MCTS-Minimax interface for Nine Men's Morris
// Combines Monte Carlo Tree Search with traditional minimax for optimal play
//
// KEY FEATURES:
// - Strategic MCTS planning with tactical minimax precision
// - Adaptive evaluation based on position characteristics
// - Performance optimizations including caching and selective search
// - Configurable integration parameters for fine-tuning
//
// Original MCTS design inspired by KataGo and Leela Chess Zero optimizations
//
// Lock-free Optimization Strategy:
// 1. Use atomic operations for frequently updated statistics (num_visits,
// value_sum)
// 2. Atomic flags (is_expanding, is_expanded) replace mutexes for node
// expansion
// 3. Compare-and-swap operations for thread-safe expansion coordination
// 4. Immutable children vector after expansion eliminates need for read locks
// 5. Consistent use of is_expanded as synchronization barrier for children
// access
// 6. Relaxed memory ordering for performance, acquire/release for
// synchronization
// 7. Spin-wait with yield() for minimal latency in contended scenarios

#ifndef MCTS_H
#define MCTS_H

#include "position.h"
#include "types.h"

#define MCTS_PRINT_STAT

// Advanced MCTS configuration parameters
// Unified namespace for all MCTS-related constants
namespace MCTSConfig {
// UCB exploration parameters
// The C_PUCT parameter balances exploration vs exploitation in PUCT formula
// Higher values encourage more exploration of less-visited nodes
// Lower values focus more on promising nodes based on current evaluations
// Typical range: 0.5 - 2.0, with 1.25 being optimal for many games
constexpr double DEFAULT_C_PUCT = 1.25;

// Legacy exploration parameter for backward compatibility
// Used in traditional UCT formula before PUCT improvements
constexpr double EXPLORATION_PARAMETER = 0.5;

// Virtual loss configuration for parallel search
// Virtual loss is applied consistently to both numerator (parent visits) and
// denominator (child visits) in PUCT formula to maintain proper exploration
// balance. Lower values reduce pessimism while still providing effective thread
// deconfliction.
constexpr double VIRTUAL_LOSS_VALUE = 1.0;

// First Play Urgency (FPU) reduction
// Reduces the value assigned to unvisited nodes relative to their parent
// Prevents over-exploration of completely unknown positions
constexpr double FPU_REDUCTION = 0.25;

// Expansion strategy: Full expansion with natural PUCT selection
// All legal moves are expanded immediately, then PUCT formula naturally guides
// exploration Benefits:
// 1. Simpler implementation without complex progressive logic
// 2. Proper prior probability normalization across all siblings
// 3. Natural exploration based on PUCT values rather than artificial limits
// 4. No memory overhead from maintaining unexpanded move lists

// RAVE (Rapid Action Value Estimation) parameters
// RAVE enhances move evaluation by learning from all simulations where a move
// was played Uses thread-local caching for performance in parallel search
// FIXED: Lowered threshold to enable RAVE earlier in search
// Minimum visits before RAVE mixing becomes reliable (only for mixing, not
// updates)
constexpr int MIN_VISITS_FOR_RAVE_MIXING = 3;
// RAVE bias factor for combining RAVE and UCB values
// Formula: Q' = (1-β) * Q + β * Q_RAVE, where β = b/(b+N)
// The β factor automatically handles early vs late game mixing
// FIXED: Reduced from 300 to 75 to prevent over-influence from unrelated
// positions
constexpr double RAVE_BIAS_FACTOR = 75.0;

// Variance penalty for high-uncertainty nodes
// Penalizes nodes with high value variance to prefer stable evaluations
// Uses numerically stable variance calculation to prevent NaN from
// sqrt(negative)
constexpr double VARIANCE_PENALTY = 0.01;

// Move ordering bias factor
// Controls the strength of move ordering influence in both prior calculation
// and PUCT Set to 0.0 to disable move ordering bias completely Typical range:
// 0.0 (no bias) to 0.1 (strong bias) This factor is used in:
// 1. Prior calculation: order_influence = 1.0 / (1.0 + move_index * BIAS_FACTOR
// * 0.1)
// 2. PUCT progressive bias: progressive_bias = BIAS_FACTOR / (1.0 + move_index)
constexpr double BIAS_FACTOR = 0.05;

// Prior probability normalization parameters
// Minimum prior probability to prevent zero exploration (epsilon smoothing)
constexpr double MIN_PRIOR_PROBABILITY = 0.001;
// Maximum prior probability before normalization (for clipping extreme values)
constexpr double MAX_PRIOR_PROBABILITY = 10.0;
// Whether to use softmax normalization (true) or simple sum normalization
// (false)
constexpr bool USE_SOFTMAX_PRIOR_NORMALIZATION = false;
// Temperature parameter for softmax normalization (lower = sharper
// distribution)
constexpr double PRIOR_SOFTMAX_TEMPERATURE = 1.0;

// Search depth and memory limits
// Alpha-beta search depth for position evaluation
constexpr int ALPHA_BETA_DEPTH = 6;
// Maximum tree depth to prevent infinite recursion
constexpr int MAX_TREE_DEPTH = 100;
// Transposition table size for position caching
// Uses bucketed hash table with O(1) random eviction for high performance
constexpr int TRANSPOSITION_TABLE_SIZE = 1000000;

// Performance tuning parameters
// Check time constraints every N iterations to avoid overhead
constexpr int CHECK_TIME_FREQUENCY = 128;
// Base number of simulations per skill level
constexpr int ITERATIONS_PER_SKILL_LEVEL = 2048;

// Multi-threading configuration
// Maximum number of threads to use (will be capped by hardware_concurrency)
constexpr int MAX_THREADS = 1;
// Minimum simulations per thread to avoid excessive coordination overhead
constexpr int MIN_SIMULATIONS_PER_THREAD = 500;
// Simulation thresholds for adaptive thread scaling
constexpr int SMALL_WORKLOAD_THRESHOLD = 5000;   // Use <=2 threads
constexpr int MEDIUM_WORKLOAD_THRESHOLD = 20000; // Use <=4 threads

// Root node exploration enhancement
// Enable Dirichlet noise for root node to prevent first child bias
constexpr bool USE_ROOT_DIRICHLET_NOISE = true;
// Dirichlet noise concentration parameter (lower = more uniform, higher = more
// peaked) Typical values: 0.03 for Go, 0.3 for Chess, 0.15 for Nine Men's
// Morris
constexpr double DIRICHLET_ALPHA = 0.15;
// Weight of Dirichlet noise mixed with prior probabilities
// Formula: prior' = (1-ε) * prior + ε * noise
constexpr double DIRICHLET_EPSILON = 0.25;

// Evaluation method configuration
// Set to true for pure MCTS evaluation (KataGo/LC0 style)
// Set to false for alpha-beta enhanced evaluation (traditional hybrid)
constexpr bool USE_PURE_MCTS_EVALUATION = false;

// Hybrid MCTS-Minimax integration parameters
// Enable minimax search at leaf nodes for tactical accuracy
constexpr bool USE_MINIMAX_AT_LEAF_NODES = true;
// Minimum depth for minimax search at leaf nodes
constexpr Depth MINIMAX_LEAF_DEPTH = 4;
// Maximum depth for minimax search at leaf nodes (adaptive based on position)
constexpr Depth MINIMAX_LEAF_MAX_DEPTH = 8;

// Enable tactical search for critical positions
constexpr bool USE_TACTICAL_SEARCH = true;
// Depth for tactical search in critical positions (endgame, mill formations)
constexpr Depth TACTICAL_SEARCH_DEPTH = 6;

// Enable minimax validation at root level for move ordering
constexpr bool USE_ROOT_MINIMAX_VALIDATION = true;
// Depth for root level minimax validation
constexpr Depth ROOT_MINIMAX_DEPTH = 3;

// Thresholds for triggering different search modes
constexpr int ENDGAME_PIECE_THRESHOLD = 6;    // Total pieces on board
constexpr int CRITICAL_ENDGAME_THRESHOLD = 4; // Pieces per player

// Performance optimization parameters
// Cache minimax evaluations to avoid redundant calculations
constexpr bool USE_MINIMAX_CACHE = true;
constexpr int MINIMAX_CACHE_SIZE = 10000;

// Adaptive simulation count based on position complexity
constexpr bool USE_ADAPTIVE_SIMULATIONS = true;
constexpr double ENDGAME_SIMULATION_MULTIPLIER = 1.5;  // More simulations in
                                                       // endgame
constexpr double CRITICAL_SIMULATION_MULTIPLIER = 2.0; // Even more in critical
                                                       // positions
} // namespace MCTSConfig

// Main MCTS search interface
// Uses advanced algorithms including PUCT, virtual loss, RAVE, and
// transposition tables Returns evaluation value and sets bestMove to the
// optimal move found
Value monte_carlo_tree_search(Position *pos, Move &bestMove);

// Forward declarations for evaluation functions
class MCTSNode;
double evaluate_position_pure_mcts(MCTSNode *node);
double evaluate_position_hybrid_minimax(MCTSNode *node,
                                        Sanmill::Stack<Position> &ss);
double detect_immediate_mills(Position *pos);
bool has_immediate_win(const Position *pos);

// Hybrid MCTS-Minimax integration functions
bool is_critical_position(const Position *pos);
bool is_endgame_position(const Position *pos);
bool requires_tactical_search(const Position *pos);
Depth get_adaptive_minimax_depth(const Position *pos);
double evaluate_with_tactical_search(MCTSNode *node,
                                     Sanmill::Stack<Position> &ss);

#endif // MCTS_H
