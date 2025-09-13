// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// mcts.cpp - Hybrid MCTS-Minimax implementation for Nine Men's Morris
// Combines the strategic planning of MCTS with the tactical precision of
// minimax
//
// HYBRID ARCHITECTURE OVERVIEW:
// =============================
//
// 1. STRATEGIC LAYER (MCTS):
//    - Provides global position understanding and long-term planning
//    - Uses PUCT selection for exploration vs exploitation balance
//    - Maintains game tree with visit counts and value estimates
//    - Handles uncertainty through Monte Carlo simulations
//
// 2. TACTICAL LAYER (Minimax):
//    - Provides precise evaluation in critical positions
//    - Used at leaf nodes for accurate position assessment
//    - Triggered in endgames, mill formations, and tactical situations
//    - Ensures no tactical oversights in important positions
//
// 3. INTEGRATION POINTS:
//    - Leaf Evaluation: Minimax search replaces simple heuristics
//    - Root Validation: Shallow minimax validates move ordering
//    - Tactical Search: Deep search in critical positions
//    - Adaptive Depth: Search depth varies by position complexity
//
// 4. PERFORMANCE OPTIMIZATIONS:
//    - Minimax result caching to avoid redundant calculations
//    - Adaptive simulation counts based on position criticality
//    - Selective application of expensive evaluations
//
// This hybrid approach achieves both the strategic understanding of MCTS
// and the tactical accuracy of traditional search, resulting in stronger
// overall play than either method alone.
//
// Original MCTS implementation inspired by KataGo and Leela Chess Zero
// optimizations

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <map>
#include <mutex>
#include <random>
#include <sstream>
#include <stack>
#include <thread>
#include <unordered_map>
#include <vector>

#include "mcts.h"
#include "movepick.h"
#include "option.h"
#include "position.h"
#include "search.h"
#include "search_engine.h"
#include "types.h"
#include "uci.h"
#include "hashmap.h"

using namespace std;

// Thread-local RNG management for efficient random number generation
// Avoids expensive random_device construction per node
class ThreadRNGManager
{
private:
    // Use thread-safe per-thread storage instead of thread_local for Android
    // ARM compatibility
    // FIXED: Use std::map instead of unordered_map to prevent reference
    // invalidation during rehash operations. std::map guarantees that
    // references remain valid during insertions, unlike unordered_map which may
    // rehash and invalidate all references.
    static std::map<std::thread::id, std::mt19937> thread_rngs_;
    static std::mutex rng_mutex_;
    static std::atomic<uint64_t> global_seed_counter_;

    // Fast splitmix64 for lightweight seed generation
    static uint64_t splitmix64(uint64_t &state)
    {
        uint64_t z = (state += 0x9e3779b97f4a7c15ULL);
        z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
        z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
        return z ^ (z >> 31);
    }

public:
    // Get thread-local RNG, creating if necessary
    static std::mt19937 &get_thread_rng()
    {
        std::thread::id tid = std::this_thread::get_id();
        std::lock_guard<std::mutex> lock(rng_mutex_);

        auto it = thread_rngs_.find(tid);
        if (it == thread_rngs_.end()) {
            // Create new RNG for this thread with lightweight seeding
            uint64_t seed = global_seed_counter_.fetch_add(
                1, std::memory_order_relaxed);
            uint64_t state = seed + std::hash<std::thread::id> {}(tid);
            uint64_t final_seed = splitmix64(state);

            thread_rngs_[tid] = std::mt19937(static_cast<uint32_t>(final_seed));
            return thread_rngs_[tid];
        }
        return it->second;
    }

    // Generate a seed for node-specific RNG from thread RNG
    static uint32_t get_node_seed() { return get_thread_rng()(); }

    // Clean up thread RNG when thread exits (optional)
    static void cleanup_thread_rng()
    {
        std::thread::id tid = std::this_thread::get_id();
        std::lock_guard<std::mutex> lock(rng_mutex_);
        thread_rngs_.erase(tid);
    }
};

// Static member definitions
std::map<std::thread::id, std::mt19937> ThreadRNGManager::thread_rngs_;
std::mutex ThreadRNGManager::rng_mutex_;
std::atomic<uint64_t> ThreadRNGManager::global_seed_counter_ {1}; // Start from
                                                                  // 1 to avoid
                                                                  // 0 seeds

static SearchEngine searchEngine;

// Configuration parameters are now defined in mcts.h for better organization

// Hash function for position transposition table using Zobrist keys
struct PositionHash
{
    size_t operator()(Key pos_key) const
    {
        // For 64-bit keys, use the key directly as hash
        // For 32-bit keys, also use directly (already well-distributed by
        // Zobrist)
        return static_cast<size_t>(pos_key);
    }
};

// RAVE (Rapid Action Value Estimation) statistics for context-aware move
// evaluation
struct RAVEStats
{
    double total_value = 0.0;
    int total_visits = 0;

    void update(double value)
    {
        total_value += value;
        total_visits++;
    }

    double get_rave_value() const
    {
        return total_visits > 0 ? total_value / total_visits : 0.0;
    }
};

// Context-aware RAVE key that distinguishes player and basic position features
struct RAVEKey
{
    Move move;
    Color side_to_move;
    uint32_t position_pattern; // Lightweight position features hash

    RAVEKey(Move m, Color side, uint32_t pattern = 0)
        : move(m)
        , side_to_move(side)
        , position_pattern(pattern)
    { }

    bool operator==(const RAVEKey &other) const
    {
        return move == other.move && side_to_move == other.side_to_move &&
               position_pattern == other.position_pattern;
    }
};

// Hash function for RAVEKey
struct RAVEKeyHash
{
    size_t operator()(const RAVEKey &key) const
    {
        // Combine move, side, and position pattern into hash
        uint64_t hash_val = static_cast<uint64_t>(key.move);
        hash_val ^= (static_cast<uint64_t>(key.side_to_move) << 16);
        hash_val ^= (static_cast<uint64_t>(key.position_pattern) << 32);
        return std::hash<uint64_t> {}(hash_val);
    }
};

// Context-aware RAVE table for move evaluation with player and position
// distinction Uses thread-local caching with periodic synchronization for
// optimal performance
class GlobalRAVETable
{
private:
    unordered_map<RAVEKey, RAVEStats, RAVEKeyHash> rave_stats_;
    mutable mutex rave_mutex_;

    // Thread-local cache structure for batched updates
    struct ThreadLocalRAVE
    {
        unordered_map<RAVEKey, pair<double, int>, RAVEKeyHash>
            pending_updates; // value_sum, count
        int update_counter = 0;
        static constexpr int SYNC_FREQUENCY = 32; // Sync every N updates

        void add_update(const RAVEKey &key, double value)
        {
            auto it = pending_updates.find(key);
            if (it == pending_updates.end()) {
                pending_updates.insert({key, {value, 1}});
            } else {
                it->second.first += value;
                it->second.second += 1;
            }
            update_counter++;
        }

        bool should_sync() const { return update_counter >= SYNC_FREQUENCY; }

        void clear()
        {
            pending_updates.clear();
            update_counter = 0;
        }
    };

    // Thread-safe cache using std::map with mutex protection
    // Replaced thread_local with per-thread storage to fix Android ARM linking
    // issues FIXED: Use std::map instead of unordered_map to prevent reference
    // invalidation during rehash operations. std::map guarantees that
    // references remain valid during insertions, unlike unordered_map which may
    // rehash and invalidate all references.
    static std::map<std::thread::id, ThreadLocalRAVE> thread_caches_;
    static std::mutex cache_mutex_;

    // Get current thread's cache (thread-safe replacement for thread_local)
    ThreadLocalRAVE &get_current_cache()
    {
        std::thread::id tid = std::this_thread::get_id();
        std::lock_guard<std::mutex> lock(cache_mutex_);
        return thread_caches_[tid]; // Creates entry if doesn't exist
    }

    // Flush current thread's cache to global table
    // OPTIMIZED: Avoid unnecessary loops by directly accumulating sums
    void flush_local_cache()
    {
        ThreadLocalRAVE &local_cache = get_current_cache();
        if (local_cache.pending_updates.empty())
            return;

        std::lock_guard<std::mutex> lock(rave_mutex_);
        for (const auto &[key, stats] : local_cache.pending_updates) {
            // OPTIMIZED: Use operator[] for automatic insertion if not exists
            auto &rave_stat = rave_stats_[key]; // Creates default RAVEStats if
                                                // not exists
            // Directly accumulate totals instead of calling update() in a loop
            rave_stat.total_value += stats.first;   // Accumulate value sum
            rave_stat.total_visits += stats.second; // Accumulate visit count
        }
        local_cache.clear();
    }

    // Generate lightweight position pattern hash for RAVE context
    // Uses key position features to distinguish different game contexts
    uint32_t generate_position_pattern(const Position *pos) const
    {
        uint32_t pattern = 0;

        // Include game phase (2 bits)
        pattern |= static_cast<uint32_t>(pos->get_phase()) & 0x3;

        // Include piece counts (8 bits each, capped at 255)
        uint32_t white_pieces = std::min(
            255u, static_cast<uint32_t>(pos->piece_on_board_count(WHITE)));
        uint32_t black_pieces = std::min(
            255u, static_cast<uint32_t>(pos->piece_on_board_count(BLACK)));
        pattern |= (white_pieces & 0xFF) << 2;
        pattern |= (black_pieces & 0xFF) << 10;

        // Include center control pattern (4 bits for key squares)
        // Check occupancy of central star positions: SQ_16, SQ_18, SQ_20, SQ_22
        uint32_t center_pattern = 0;
        if (pos->piece_on(SQ_16) != NO_PIECE)
            center_pattern |= 1;
        if (pos->piece_on(SQ_18) != NO_PIECE)
            center_pattern |= 2;
        if (pos->piece_on(SQ_20) != NO_PIECE)
            center_pattern |= 4;
        if (pos->piece_on(SQ_22) != NO_PIECE)
            center_pattern |= 8;
        pattern |= (center_pattern & 0xF) << 18;

        // Include side to move (1 bit)
        pattern |= (static_cast<uint32_t>(pos->sideToMove) & 0x1) << 22;

        return pattern;
    }

public:
    void update_rave(const RAVEKey &key, double value)
    {
        // Add to current thread's cache
        ThreadLocalRAVE &local_cache = get_current_cache();
        local_cache.add_update(key, value);

        // Periodically sync to global table
        if (local_cache.should_sync()) {
            flush_local_cache();
        }
    }

    // Convenience method for updating RAVE with position context
    void update_rave(Move move, double value, const Position *pos)
    {
        uint32_t pattern = generate_position_pattern(pos);
        RAVEKey key(move, pos->sideToMove, pattern);
        update_rave(key, value);
    }

    // Get RAVE value with position context consideration
    double get_rave_value(const RAVEKey &key) const
    {
        // First check current thread's cache
        std::thread::id tid = std::this_thread::get_id();
        double local_value = 0.0;
        int local_visits = 0;

        {
            std::lock_guard<std::mutex> lock(cache_mutex_);
            auto cache_it = thread_caches_.find(tid);
            if (cache_it != thread_caches_.end()) {
                auto local_it = cache_it->second.pending_updates.find(key);
                if (local_it != cache_it->second.pending_updates.end()) {
                    local_value = local_it->second.first;
                    local_visits = local_it->second.second;
                }
            }
        }

        // Then check global table
        std::lock_guard<std::mutex> lock(rave_mutex_);
        auto global_it = rave_stats_.find(key);

        if (global_it == rave_stats_.end() && local_visits == 0) {
            return 0.0;
        }

        // Combine local and global statistics
        double global_value = (global_it != rave_stats_.end()) ?
                                  global_it->second.get_rave_value() *
                                      global_it->second.total_visits :
                                  0.0;
        int global_visits = (global_it != rave_stats_.end()) ?
                                global_it->second.total_visits :
                                0;

        int total_visits = local_visits + global_visits;
        if (total_visits == 0)
            return 0.0;

        return (local_value + global_value) / total_visits;
    }

    // Convenience method for getting RAVE value with position context
    double get_rave_value(Move move, const Position *pos) const
    {
        uint32_t pattern = generate_position_pattern(pos);
        RAVEKey key(move, pos->sideToMove, pattern);
        return get_rave_value(key);
    }

    int get_rave_visits(const RAVEKey &key) const
    {
        // Check current thread's cache
        std::thread::id tid = std::this_thread::get_id();
        int local_visits = 0;

        {
            std::lock_guard<std::mutex> lock(cache_mutex_);
            auto cache_it = thread_caches_.find(tid);
            if (cache_it != thread_caches_.end()) {
                auto local_it = cache_it->second.pending_updates.find(key);
                if (local_it != cache_it->second.pending_updates.end()) {
                    local_visits = local_it->second.second;
                }
            }
        }

        // Check global table
        std::lock_guard<std::mutex> lock(rave_mutex_);
        auto global_it = rave_stats_.find(key);
        int global_visits = (global_it != rave_stats_.end()) ?
                                global_it->second.total_visits :
                                0;

        return local_visits + global_visits;
    }

    // Convenience method for getting RAVE visits with position context
    int get_rave_visits(Move move, const Position *pos) const
    {
        uint32_t pattern = generate_position_pattern(pos);
        RAVEKey key(move, pos->sideToMove, pattern);
        return get_rave_visits(key);
    }

    // Force synchronization of all pending updates
    void force_sync() { flush_local_cache(); }

    // Clean up current thread's cache when thread exits (prevents memory leaks)
    static void cleanup_current_cache()
    {
        std::thread::id tid = std::this_thread::get_id();
        std::lock_guard<std::mutex> lock(cache_mutex_);
        thread_caches_.erase(tid);
    }
};

// Transposition table entry for position caching
struct TranspositionEntry
{
    double value = 0.0;
    int visits = 0;
    int depth = 0;
    chrono::steady_clock::time_point timestamp;

    TranspositionEntry()
        : timestamp(chrono::steady_clock::now())
    { }
};

// OPTIMIZED: High-performance transposition table using specialized HashMap
// Uses the project's optimized HashMap with Zobrist key direct indexing
class TranspositionTable
{
private:
    // Use the optimized HashMap from hashmap.h
    // This provides better performance than std::unordered_map due to:
    // 1. Direct Zobrist key usage as hash (no additional hashing)
    // 2. Optimized memory layout and allocation
    // 3. Fine-grained locking for better concurrency
    // 4. Support for large pages and cache-friendly access patterns
    CTSL::HashMap<Key, TranspositionEntry> hashMap_;

    // Track entries manually to avoid HashMap's stat() casting issues
    mutable std::atomic<size_t> entry_count_ {0};

public:
    TranspositionTable()
        : hashMap_(MCTSConfig::TRANSPOSITION_TABLE_SIZE)
    { }

    bool lookup(Key position_key, TranspositionEntry &entry) const
    {
        return hashMap_.find(position_key, entry);
    }

    void store(Key position_key, const TranspositionEntry &entry)
    {
        // Check if this is a new entry by trying to find it first
        TranspositionEntry existing;
        bool existed = hashMap_.find(position_key, existing);

        hashMap_.insert(position_key, entry);

        // If it's a new entry, increment counter
        if (!existed) {
            entry_count_.fetch_add(1, std::memory_order_relaxed);
        }
    }

    // Optional: Clear table
    void clear()
    {
        hashMap_.clear();
        entry_count_.store(0, std::memory_order_relaxed);
    }

    // Optional: Get statistics
    size_t size() const { return entry_count_.load(std::memory_order_relaxed); }
};

// Advanced MCTS Node with KataGo and LC0 inspired optimizations
class MCTSNode
{
public:
    MCTSNode(Position *pos, Move m, MCTSNode *prt, int idx, double prior = 0.0)
        : position(pos)
        , move(m)
        , parent(prt)
        , move_index(idx)
        , prior_probability(prior)
        , position_key(pos->key()) // Use Zobrist key directly from Position
    {
        // FIXED: Use efficient thread-local RNG instead of expensive
        // random_device per node This significantly reduces node construction
        // cost
        rng.seed(ThreadRNGManager::get_node_seed());
    }

    ~MCTSNode()
    {
        if (position != nullptr) {
            delete position;
            position = nullptr;
        }

        // Note: No pending positions to clean up in current full-expansion
        // implementation

        // Don't delete children here - they will be handled by delete_mcts_tree
        // to avoid double deletion
    }

    // Get the Q-value (average reward) for this node
    double get_q_value() const
    {
        int visits = num_visits.load(std::memory_order_acquire);
        if (visits == 0)
            return 0.0;
        return value_sum.load(std::memory_order_acquire) / visits;
    }

    // Get Q-value with virtual loss (disabled impact on Q to preserve playing
    // strength) We keep this helper for potential future tuning, but do not
    // penalize Q currently.
    double get_q_value_with_virtual_loss() const { return get_q_value(); }

    // Get Q-value mixed with RAVE statistics for improved move evaluation
    // Implementation moved outside class to avoid forward declaration issues
    double get_q_value_with_rave() const;

    // Get the variance of values for this node with numerical stability
    double get_variance() const
    {
        int visits = num_visits.load(std::memory_order_acquire);
        if (visits <= 1)
            return 0.0;

        double mean = get_q_value();
        double mean_squared = mean * mean;
        double sum_squared = squared_value_sum.load(std::memory_order_acquire) /
                             visits;

        // Ensure numerical stability: variance cannot be negative due to
        // floating-point errors
        double variance = sum_squared - mean_squared;
        return std::max(0.0, variance);
    }

    // Advanced UCB calculation with PUCT (Polynomial Upper Confidence Trees)
    // Integrates RAVE statistics and virtual loss for enhanced parallel search
    double get_puct_value(double c_puct, double fpu_reduction) const
    {
        if (parent == nullptr)
            return 0.0;

        // Use RAVE-enhanced Q-value for better move evaluation
        double q_value = get_q_value_with_rave();

        // Get visit counts with virtual loss adjustment
        double vloss = virtual_loss.load(std::memory_order_acquire);
        int base_visits = num_visits.load(std::memory_order_acquire);
        double adjusted_visits = static_cast<double>(base_visits) + vloss;

        // First Play Urgency - reduce value for unvisited nodes
        if (base_visits == 0) {
            q_value = parent->get_q_value() - fpu_reduction;
        }

        // Add variance penalty for high-variance nodes with numerical stability
        double variance = get_variance(); // Already guaranteed to be
                                          // non-negative
        double variance_penalty = MCTSConfig::VARIANCE_PENALTY *
                                  std::sqrt(variance);

        // UCB exploration term with consistent virtual loss handling
        // FIXED: Apply virtual loss consistently to both numerator and
        // denominator to maintain proper exploration balance in parallel search
        double parent_base_visits = static_cast<double>(
            parent->num_visits.load(std::memory_order_acquire));
        double parent_children_vloss = parent->children_virtual_loss.load(
            std::memory_order_acquire);
        double adjusted_parent_visits = parent_base_visits +
                                        parent_children_vloss;

        double exploration = c_puct * prior_probability *
                             std::sqrt(adjusted_parent_visits + 1.0) /
                             (1.0 + adjusted_visits);

        // Optional progressive bias based on move ordering (human experience
        // heuristic) Only apply if BIAS_FACTOR > 0 and human experience is
        // enabled
        double progressive_bias = 0.0;
        if (gameOptions.getDrawOnHumanExperience() &&
            MCTSConfig::BIAS_FACTOR > 0.0) {
            progressive_bias = MCTSConfig::BIAS_FACTOR / (1.0 + move_index);
        }

        return q_value + exploration + progressive_bias - variance_penalty;
    }

    // Select best child using PUCT with natural exploration
    // Lock-free implementation using atomic flags
    MCTSNode *select_best_child(double c_puct, double fpu_reduction)
    {
        // Wait for expansion to complete using proper release-acquire
        // synchronization
        while (!is_expanded.load(std::memory_order_acquire)) {
            std::this_thread::yield(); // More efficient than sleep for short
                                       // waits
        }

        // CRITICAL: Make a local copy of children vector to avoid race
        // conditions Even though children is not supposed to be modified after
        // expansion, there might be memory reordering issues in multi-threaded
        // access
        std::vector<MCTSNode *> local_children = children;

        if (local_children.empty())
            return nullptr;

        // PUCT evaluation with random tie-breaking to prevent first child bias
        // FIXED: When parent has 0 visits, exploration term is 0 and FPU makes
        // all unvisited children have identical PUCT values. Without
        // tie-breaking, select_best_child always picks the first child in
        // traversal order, creating systematic bias toward MovePicker's first
        // move.
        MCTSNode *best_child = nullptr;
        double best_value = -numeric_limits<double>::infinity();
        int tie_count = 0;
        std::mt19937 &thread_rng = ThreadRNGManager::get_thread_rng();

        // Use small epsilon for floating-point comparison tolerance
        constexpr double EPSILON = 1e-12;

        for (MCTSNode *child : local_children) {
            double value = child->get_puct_value(c_puct, fpu_reduction);

            if (value > best_value + EPSILON) {
                // New best value found
                best_value = value;
                best_child = child;
                tie_count = 1;
            } else if (std::abs(value - best_value) <= EPSILON) {
                // Tied with current best - use reservoir sampling for random
                // selection
                tie_count++;
                if (std::uniform_int_distribution<int>(1, tie_count)(
                        thread_rng) == 1) {
                    best_child = child;
                }
            }
        }

        return best_child;
    }

    // Apply virtual loss for parallel search - lock-free with atomics
    // Virtual loss mechanism for thread coordination:
    // 1. When thread selects a path, it adds virtual loss to the SELECTED CHILD
    // (not parent)
    // 2. This makes the selected child appear worse to other threads in PUCT
    // evaluation
    // 3. Other threads are discouraged from selecting the same child node
    // 4. After evaluation, virtual loss is removed from nodes that actually had
    // it applied
    void add_virtual_loss()
    {
        // Apply virtual loss to this node
        double current = virtual_loss.load(std::memory_order_acquire);
        while (!virtual_loss.compare_exchange_weak(
            current, current + MCTSConfig::VIRTUAL_LOSS_VALUE,
            std::memory_order_acq_rel)) {
            // Retry if CAS failed - use acq_rel for cross-thread visibility
        }

        // FIXED: Also update parent's children virtual loss counter for
        // consistent PUCT calculation This ensures that parent's sqrt(N_parent
        // + total_vloss) matches children's denominators
        if (parent != nullptr) {
            double parent_current = parent->children_virtual_loss.load(
                std::memory_order_acquire);
            while (!parent->children_virtual_loss.compare_exchange_weak(
                parent_current, parent_current + MCTSConfig::VIRTUAL_LOSS_VALUE,
                std::memory_order_acq_rel)) {
                // Retry if CAS failed
            }
        }
    }

    void remove_virtual_loss()
    {
        // Remove virtual loss from this node
        double current = virtual_loss.load(std::memory_order_acquire);
        while (!virtual_loss.compare_exchange_weak(
            current, current - MCTSConfig::VIRTUAL_LOSS_VALUE,
            std::memory_order_acq_rel)) {
            // Retry if CAS failed - use acq_rel for cross-thread visibility
        }

        // FIXED: Also update parent's children virtual loss counter for
        // consistent PUCT calculation This maintains the balance between
        // numerator and denominator in PUCT formula
        if (parent != nullptr) {
            double parent_current = parent->children_virtual_loss.load(
                std::memory_order_acquire);
            while (!parent->children_virtual_loss.compare_exchange_weak(
                parent_current, parent_current - MCTSConfig::VIRTUAL_LOSS_VALUE,
                std::memory_order_acq_rel)) {
                // Retry if CAS failed
            }
        }
    }

    // Update node statistics with lock-free atomics
    void update(double value)
    {
        // Use relaxed memory ordering for statistics updates - acceptable for
        // counters Critical reads (like in PUCT evaluation) use acquire to
        // establish proper ordering
        num_visits.fetch_add(1, std::memory_order_relaxed);

        // For floating point atomics, we need compare-and-swap loop
        // Relaxed is sufficient here as these are pure statistical
        // accumulations
        double current_sum = value_sum.load(std::memory_order_relaxed);
        while (!value_sum.compare_exchange_weak(
            current_sum, current_sum + value, std::memory_order_relaxed)) {
            // Retry if CAS failed
        }

        double current_squared = squared_value_sum.load(
            std::memory_order_relaxed);
        double new_squared = value * value;
        while (!squared_value_sum.compare_exchange_weak(
            current_squared, current_squared + new_squared,
            std::memory_order_relaxed)) {
            // Retry if CAS failed
        }
    }

    // Add child node
    // Use atomic flag to prevent concurrent modifications during expansion
    void add_child(MCTSNode *child)
    {
        // Simple lock-free approach: only one thread should expand a node
        // This is guaranteed by the expansion logic in expand_node()
        children.push_back(child);

        // No need to sort here since children are added in MovePicker order
        // and prior probabilities already incorporate move ordering preferences
    }

    // Check if node is terminal
    bool is_terminal() const
    {
        return position->get_phase() == Phase::gameOver;
    }

    // Generate unique position key for transposition table using Zobrist
    // hashing
    Key generate_position_key(const Position *pos) const
    {
        // OPTIMIZED: Use Zobrist key directly - much faster than string
        // operations
        return pos->key();
    }

    // Node data members
    Position *position {nullptr};
    Move move {MOVE_NONE};
    MCTSNode *parent {nullptr};
    vector<MCTSNode *> children;

    // Visit and value statistics
    atomic<int> num_visits {0};
    atomic<double> value_sum {0.0};
    atomic<double> squared_value_sum {0.0};
    atomic<double> virtual_loss {0.0};

    // Track total virtual loss applied to all children for consistent PUCT
    // calculation FIXED: This solves the virtual loss inconsistency problem
    // where parent's sqrt(N) was not synchronized with children's denominator
    // adjustments, causing insufficient global exploration and thread
    // clustering in parallel search
    atomic<double> children_virtual_loss {0.0};

    // Node properties
    int move_index {0};
    double prior_probability {0.0};
    Key position_key; // OPTIMIZED: Use 64-bit Zobrist key instead of string

    // Thread safety - use atomic flag for expansion instead of mutex
    atomic<bool> is_expanding {false};
    atomic<bool> is_expanded {false};
    mutable mt19937 rng;

    // Note: Progressive expansion support removed for simplicity
    // Current implementation uses full expansion with natural PUCT selection
    // This approach is simpler and allows proper prior probability
    // normalization

#ifdef MCTS_ALPHA_BETA
    atomic<int> alpha_beta_depth {1};
    MCTSNode *best_alpha_beta_child {nullptr};
    atomic<double> last_bonus_given {0.0};
#endif // MCTS_ALPHA_BETA
};

// Global instances for advanced MCTS features
GlobalRAVETable global_rave_table;
TranspositionTable transposition_table;

// Minimax evaluation cache for performance optimization
class MinimaxCache
{
private:
    struct CacheEntry
    {
        double evaluation;
        Depth depth;
        chrono::steady_clock::time_point timestamp;

        CacheEntry()
            : evaluation(0.0)
            , depth(0)
            , timestamp(chrono::steady_clock::now())
        { }
        CacheEntry(double eval, Depth d)
            : evaluation(eval)
            , depth(d)
            , timestamp(chrono::steady_clock::now())
        { }
    };

    unordered_map<Key, CacheEntry> cache_;
    mutable mutex cache_mutex_;

public:
    bool lookup(Key position_key, Depth required_depth,
                double &evaluation) const
    {
        if (!MCTSConfig::USE_MINIMAX_CACHE)
            return false;

        lock_guard<mutex> lock(cache_mutex_);
        auto it = cache_.find(position_key);

        if (it != cache_.end() && it->second.depth >= required_depth) {
            evaluation = it->second.evaluation;
            return true;
        }
        return false;
    }

    void store(Key position_key, Depth depth, double evaluation)
    {
        if (!MCTSConfig::USE_MINIMAX_CACHE)
            return;

        lock_guard<mutex> lock(cache_mutex_);

        // Simple LRU eviction if cache is full
        if (cache_.size() >= MCTSConfig::MINIMAX_CACHE_SIZE) {
            auto oldest = cache_.begin();
            auto oldest_time = oldest->second.timestamp;

            for (auto it = cache_.begin(); it != cache_.end(); ++it) {
                if (it->second.timestamp < oldest_time) {
                    oldest = it;
                    oldest_time = it->second.timestamp;
                }
            }
            cache_.erase(oldest);
        }

        cache_[position_key] = CacheEntry(evaluation, depth);
    }

    void clear()
    {
        lock_guard<mutex> lock(cache_mutex_);
        cache_.clear();
    }
};

MinimaxCache minimax_cache;

// Thread-safe RAVE cache definitions (replaced thread_local for Android ARM
// compatibility)
std::map<std::thread::id, GlobalRAVETable::ThreadLocalRAVE>
    GlobalRAVETable::thread_caches_;
std::mutex GlobalRAVETable::cache_mutex_;

// Implementation of context-aware RAVE-enhanced Q-value calculation
// Uses the formula: Q' = (1-β) * Q + β * Q_RAVE, where β = b/(b+N)
// Now considers position context and player to move for more accurate RAVE data
double MCTSNode::get_q_value_with_rave() const
{
    if (move == MOVE_NONE)
        return get_q_value(); // Root node has no move

    int visits = num_visits.load(std::memory_order_acquire);
    double q_value = get_q_value();

    // Use context-aware RAVE lookup with position and player information
    double rave_value = global_rave_table.get_rave_value(move, position);
    int rave_visits = global_rave_table.get_rave_visits(move, position);

    // Apply minimum visit threshold for RAVE mixing to ensure reliability
    // This prevents premature mixing with insufficient RAVE data
    if (rave_visits < MCTSConfig::MIN_VISITS_FOR_RAVE_MIXING) {
        return q_value; // Use pure Q-value when RAVE data is insufficient
    }

    // For unvisited nodes with sufficient RAVE data, use RAVE as prior
    if (visits == 0) {
        return rave_value;
    }

    // Calculate mixing coefficient β = b/(b+N)
    // When visits is small, β is large (more RAVE influence)
    // When visits is large, β is small (more Q-value influence)
    // FIXED: Now uses reduced bias factor (75 instead of 300) for more
    // conservative mixing
    double beta = MCTSConfig::RAVE_BIAS_FACTOR /
                  (MCTSConfig::RAVE_BIAS_FACTOR + static_cast<double>(visits));

    // Mix Q and RAVE values: Q' = (1-β) * Q + β * Q_RAVE
    return (1.0 - beta) * q_value + beta * rave_value;
}

// Recursively delete MCTS tree starting from the given node
void delete_mcts_tree(MCTSNode *root)
{
    if (root == nullptr)
        return;

    // Use post-order traversal to delete children before parent
    // First delete all children
    for (MCTSNode *child : root->children) {
        if (child != nullptr) {
            delete_mcts_tree(child);
        }
    }

    // Clear children vector to avoid dangling pointers
    root->children.clear();

    // Then delete the root
    delete root;
}

// Advanced MCTS selection with PUCT and virtual loss support
// Fixed: Apply virtual loss to selected CHILD nodes, not parent nodes
MCTSNode *select_node(MCTSNode *root, double c_puct, double fpu_reduction,
                      vector<MCTSNode *> &path, vector<MCTSNode *> &vloss_nodes)
{
    MCTSNode *current = root;
    path.clear();
    vloss_nodes.clear();
    path.push_back(current);

    // Selection phase: traverse down the tree using PUCT
    while (!current->is_terminal()) {
        // Ensure node is fully expanded before accessing children
        // This provides consistent synchronization barrier for children vector
        // access
        if (!current->is_expanded.load(std::memory_order_acquire)) {
            break; // Node not yet expanded, stop selection here
        }

        if (current->children.empty()) {
            break; // No children to select from
        }

        MCTSNode *selected = current->select_best_child(c_puct, fpu_reduction);
        if (selected == nullptr)
            break;

        // FIXED: Apply virtual loss to the SELECTED CHILD, not the parent
        // This ensures the selected child appears worse to other threads in
        // PUCT evaluation
        selected->add_virtual_loss();
        vloss_nodes.push_back(selected); // Track which nodes have virtual loss
                                         // applied

        current = selected;
        path.push_back(current);

        // Depth limit check
        if (path.size() >= MCTSConfig::MAX_TREE_DEPTH)
            break;
    }

    return current;
}

// Normalize prior probabilities among sibling nodes
// Supports both softmax and simple sum normalization
void normalize_prior_probabilities(vector<double> &priors)
{
    if (priors.empty())
        return;

    if (MCTSConfig::USE_SOFTMAX_PRIOR_NORMALIZATION) {
        // Softmax normalization: p_i = exp(x_i/T) / sum(exp(x_j/T))
        double temperature = MCTSConfig::PRIOR_SOFTMAX_TEMPERATURE;
        double max_prior = *std::max_element(priors.begin(), priors.end());

        // Numerical stability: subtract max before exp to prevent overflow
        double sum_exp = 0.0;
        for (double &prior : priors) {
            prior = std::exp((prior - max_prior) / temperature);
            sum_exp += prior;
        }

        // Normalize and apply epsilon smoothing
        for (double &prior : priors) {
            prior = prior / sum_exp;
            prior = std::max(MCTSConfig::MIN_PRIOR_PROBABILITY, prior);
        }

        // Re-normalize after epsilon smoothing
        double final_sum = 0.0;
        for (double prior : priors) {
            final_sum += prior;
        }
        if (final_sum > 0.0) {
            for (double &prior : priors) {
                prior = prior / final_sum;
            }

            // Final check: ensure all values are above minimum
            for (double &prior : priors) {
                prior = std::max(MCTSConfig::MIN_PRIOR_PROBABILITY, prior);
            }
        }
    } else {
        // Simple sum normalization: p_i = x_i / sum(x_j)
        double sum = 0.0;
        for (double prior : priors) {
            sum += prior;
        }

        if (sum > 0.0) {
            // Normalize
            for (double &prior : priors) {
                prior = prior / sum;
            }

            // Apply epsilon smoothing
            for (double &prior : priors) {
                prior = std::max(MCTSConfig::MIN_PRIOR_PROBABILITY, prior);
            }

            // Re-normalize after epsilon smoothing
            double final_sum = 0.0;
            for (double prior : priors) {
                final_sum += prior;
            }
            if (final_sum > 0.0) {
                for (double &prior : priors) {
                    prior = prior / final_sum;
                }

                // Final check: ensure all values are above minimum
                for (double &prior : priors) {
                    prior = std::max(MCTSConfig::MIN_PRIOR_PROBABILITY, prior);
                }
            }
        } else {
            // Fallback: uniform distribution with epsilon smoothing
            double uniform_prior = 1.0 / priors.size();
            for (double &prior : priors) {
                prior = std::max(MCTSConfig::MIN_PRIOR_PROBABILITY,
                                 uniform_prior);
            }
        }
    }
}

// Calculate prior probabilities using move ordering system
// Supports both human experience heuristics and pure algorithmic approach
double calculate_move_prior(Position *pos, Move move, int move_index)
{
    const Square to = to_sq(move);
    const Square from = from_sq(move);

    // Base prior probability (uniform distribution)
    double base_prior = 1.0 / 24.0; // 24 possible positions on Nine Men's
                                    // Morris board

    // Apply move ordering priorities with optional human experience weighting
    double priority_bonus = 1.0;

    if (gameOptions.getDrawOnHumanExperience()) {
        // Human experience-based heuristics for Nine Men's Morris strategy

        // Phase-specific strategy: In placing phase without diagonal lines,
        // mobility and positional flexibility are more important than immediate
        // mills
        bool is_placing_no_diagonal = (pos->get_phase() == Phase::placing &&
                                       !rule.hasDiagonalLines);

        // Early placing phase (first 4 rounds): Even more emphasis on mobility
        // over mills When total pieces in hand > 10, the game is still in early
        // layout stage
        int total_pieces_in_hand = pos->piece_in_hand_count(WHITE) +
                                   pos->piece_in_hand_count(BLACK);
        bool is_early_placing = is_placing_no_diagonal &&
                                (total_pieces_in_hand > 10);

        // 1. Mill-forming and blocking moves - adjust weight based on game
        // phase
        if (type_of(move) != MOVETYPE_REMOVE) {
            int our_mills = pos->potential_mills_count(to, pos->sideToMove,
                                                       from);
            if (our_mills > 0) {
                // Adaptive mill weight: ignore mills only in early placing
                // phase without diagonals
                double mill_weight;
                if (is_early_placing) {
                    mill_weight = 0.0; // ZERO priority for mills in first 4
                                       // rounds of no-diagonal placing
                } else if (is_placing_no_diagonal) {
                    mill_weight = 1.2; // Medium priority in later placing phase
                                       // without diagonals
                } else {
                    mill_weight = 2.0; // High priority in moving/flying phases
                                       // or with diagonals
                }
                priority_bonus += mill_weight * our_mills;
            } else {
                // 2. Mill-blocking moves with adaptive weighting
                int their_mills = pos->potential_mills_count(to,
                                                             ~pos->sideToMove);
                if (their_mills > 0) {
                    double block_weight;
                    if (is_early_placing) {
                        block_weight = 0.0; // ZERO blocking priority in early
                                            // no-diagonal placing - focus on
                                            // own development
                    } else if (is_placing_no_diagonal) {
                        block_weight = 0.8; // Medium blocking priority in later
                                            // no-diagonal placing
                    } else {
                        block_weight = 1.0; // Standard blocking priority in
                                            // moving/flying or with diagonals
                    }
                    priority_bonus += block_weight * their_mills;
                }
            }
        }

        // 3. Apply positional priorities with mobility-focused weighting
        if (pos->get_phase() == Phase::placing) {
            if (!rule.hasDiagonalLines) {
                // Mobility-focused positional priorities with early no-diagonal
                // game emphasis Central star positions (SQ_16, SQ_18, SQ_20,
                // SQ_22) offer maximum flexibility
                if (to == SQ_16 || to == SQ_18 || to == SQ_20 || to == SQ_22) {
                    double mobility_bonus;
                    if (is_early_placing) {
                        mobility_bonus = 5.0; // MAXIMUM priority for central
                                              // mobility in early no-diagonal
                                              // placing
                    } else if (is_placing_no_diagonal) {
                        mobility_bonus = 2.5; // High priority in later
                                              // no-diagonal placing
                    } else {
                        mobility_bonus = 0.8; // Standard priority in other
                                              // phases
                    }
                    priority_bonus += mobility_bonus;
                }
                // Outer ring corners and inner ring - good mobility but less
                // central
                else if (to == SQ_24 || to == SQ_26 || to == SQ_28 ||
                         to == SQ_30 || to == SQ_8 || to == SQ_10 ||
                         to == SQ_12 || to == SQ_14) {
                    double mobility_bonus;
                    if (is_early_placing) {
                        mobility_bonus = 3.0; // Very high priority for
                                              // secondary mobility positions
                    } else if (is_placing_no_diagonal) {
                        mobility_bonus = 1.8;
                    } else {
                        mobility_bonus = 0.6;
                    }
                    priority_bonus += mobility_bonus;
                }
                // Middle ring corners - moderate mobility
                else if (to == SQ_17 || to == SQ_19 || to == SQ_21 ||
                         to == SQ_23) {
                    double mobility_bonus;
                    if (is_early_placing) {
                        mobility_bonus = 2.0; // Good mobility value in early
                                              // game
                    } else if (is_placing_no_diagonal) {
                        mobility_bonus = 1.2;
                    } else {
                        mobility_bonus = 0.4;
                    }
                    priority_bonus += mobility_bonus;
                }
                // Edge positions - limited mobility, even lower priority in
                // early placing
                else {
                    double mobility_bonus;
                    if (is_early_placing) {
                        mobility_bonus = 0.3; // Very low priority for edge
                                              // positions
                    } else if (is_placing_no_diagonal) {
                        mobility_bonus = 0.5;
                    } else {
                        mobility_bonus = 0.2;
                    }
                    priority_bonus += mobility_bonus;
                }
            } else {
                // With diagonal lines, priority order changes
                if (to == SQ_17 || to == SQ_19 || to == SQ_21 || to == SQ_23) {
                    priority_bonus += 0.8;
                } else if (to == SQ_25 || to == SQ_27 || to == SQ_29 ||
                           to == SQ_31 || to == SQ_9 || to == SQ_11 ||
                           to == SQ_13 || to == SQ_15) {
                    priority_bonus += 0.6;
                } else if (to == SQ_16 || to == SQ_18 || to == SQ_20 ||
                           to == SQ_22) {
                    priority_bonus += 0.4;
                } else {
                    priority_bonus += 0.2;
                }
            }
        }
    } else {
        // Pure algorithmic approach - basic mill detection without human
        // heuristics
        if (type_of(move) != MOVETYPE_REMOVE) {
            int our_mills = pos->potential_mills_count(to, pos->sideToMove,
                                                       from);
            if (our_mills > 0) {
                priority_bonus += 1.5 * our_mills; // Simple mill bonus
            } else {
                int their_mills = pos->potential_mills_count(to,
                                                             ~pos->sideToMove);
                if (their_mills > 0) {
                    priority_bonus += 1.0 * their_mills; // Simple blocking
                                                         // bonus
                }
            }
        }
    }

    // 4. Optional move ordering influence (controlled by BIAS_FACTOR)
    // Since PUCT already uses prior_probability and progressive_bias,
    // we only apply a minimal ordering influence here to avoid redundancy
    double order_influence = 1.0;
    if (MCTSConfig::BIAS_FACTOR > 0.0) {
        // Much lighter influence than before to avoid double-counting
        order_influence = 1.0 /
                          (1.0 + move_index * MCTSConfig::BIAS_FACTOR * 0.1);
    }

    // 5. Calculate the final prior
    double final_prior = base_prior * priority_bonus * order_influence;

    // Only apply minimum constraint - let normalization handle the upper bound
    // This allows priority_bonus to have full effect before normalization
    return std::max(MCTSConfig::MIN_PRIOR_PROBABILITY, final_prior);
}

// Advanced node expansion with move ordering and prior calculation
// Supports both full expansion and true progressive expansion
MCTSNode *expand_node(MCTSNode *node)
{
    // Fast lock-free check - if already expanded, return appropriate child
    if (node->is_expanded.load(std::memory_order_acquire)) {
        if (node->children.empty()) {
            return node;
        }
        // Use same logic as below to select appropriate child
        if (node->parent == nullptr) {
            // Root node: random selection
            std::mt19937 &thread_rng = ThreadRNGManager::get_thread_rng();
            std::uniform_int_distribution<size_t> dist(
                0, node->children.size() - 1);
            return node->children[dist(thread_rng)];
        } else {
            // Non-root: select child with highest prior
            MCTSNode *best_prior_child = node->children[0];
            double best_prior = best_prior_child->prior_probability;
            for (size_t i = 1; i < node->children.size(); ++i) {
                if (node->children[i]->prior_probability > best_prior) {
                    best_prior = node->children[i]->prior_probability;
                    best_prior_child = node->children[i];
                }
            }
            return best_prior_child;
        }
    }

    // Atomic compare-and-swap to claim expansion rights
    bool expected = false;
    if (!node->is_expanding.compare_exchange_strong(
            expected, true, std::memory_order_acquire)) {
        // Another thread is expanding, wait for completion using proper
        // synchronization
        while (!node->is_expanded.load(std::memory_order_acquire)) {
            std::this_thread::yield(); // More efficient than sleep for short
                                       // waits
        }
        // Use same selection logic as above
        if (node->children.empty()) {
            return node;
        }
        if (node->parent == nullptr) {
            // Root node: random selection
            std::mt19937 &thread_rng = ThreadRNGManager::get_thread_rng();
            std::uniform_int_distribution<size_t> dist(
                0, node->children.size() - 1);
            return node->children[dist(thread_rng)];
        } else {
            // Non-root: select child with highest prior
            MCTSNode *best_prior_child = node->children[0];
            double best_prior = best_prior_child->prior_probability;
            for (size_t i = 1; i < node->children.size(); ++i) {
                if (node->children[i]->prior_probability > best_prior) {
                    best_prior = node->children[i]->prior_probability;
                    best_prior_child = node->children[i];
                }
            }
            return best_prior_child;
        }
    }

    // We won the race - perform expansion
    if (node->is_terminal()) {
        node->is_expanded.store(true, std::memory_order_release);
        node->is_expanding.store(false, std::memory_order_release);
        return node;
    }

    Position *pos = node->position;
    MovePicker mp(*pos, MOVE_NONE);
    mp.next_move<LEGAL>(); // Get sorted legal moves

    const int move_count = mp.move_count();
    if (move_count == 0) {
        // No legal moves - mark as expanded and return
        node->is_expanded.store(true, std::memory_order_release);
        node->is_expanding.store(false, std::memory_order_release);
        return node;
    }

    // Check transposition table for this position
    TranspositionEntry tt_entry;
    bool tt_hit = transposition_table.lookup(node->position_key, tt_entry);

    // First pass: calculate raw prior probabilities for all moves
    vector<double> raw_priors;
    vector<Position *> child_positions;
    vector<Move> child_moves;

    for (int i = 0; i < move_count; ++i) {
        Position *child_position = new Position(*pos);
        if (child_position == nullptr) {
            // Memory allocation failed, skip this child
            continue;
        }

        const Move move = mp.moves[i].move;
        child_position->do_move(move);

        // Use hybrid approach: combine MovePicker score with our heuristics
        double prior = calculate_move_prior(pos, move, i);

        // Boost prior based on MovePicker's evaluation (human experience
        // heuristic) MovePicker scores are typically in range [0, 1000+],
        // normalize to [1.0, 3.0]
        if (gameOptions.getDrawOnHumanExperience() && mp.moves[i].value > 0) {
            double movepicker_bonus = 1.0 +
                                      std::min(2.0, mp.moves[i].value / 500.0);
            prior *= movepicker_bonus;
        }

        // Adjust prior based on transposition table hit (human experience
        // heuristic)
        if (gameOptions.getDrawOnHumanExperience() && tt_hit &&
            tt_entry.visits > 5) {
            prior *= (1.0 + tt_entry.value * 0.1); // Boost good positions
        }

        // NEW: Root-level minimax validation for enhanced move ordering
        // This provides tactical validation of promising moves at the root
        if (MCTSConfig::USE_ROOT_MINIMAX_VALIDATION &&
            node->parent == nullptr &&
            (is_critical_position(pos) || requires_tactical_search(pos))) {
            // Perform shallow minimax search to validate move quality
            Move dummy_move = MOVE_NONE;
            Sanmill::Stack<Position> validation_ss;
            validation_ss.push(*child_position);

            Value minimax_eval = Search::search(
                searchEngine, child_position, validation_ss,
                MCTSConfig::ROOT_MINIMAX_DEPTH, MCTSConfig::ROOT_MINIMAX_DEPTH,
                -VALUE_INFINITE, VALUE_INFINITE, dummy_move);

            child_position->undo_move(validation_ss);

            // Convert minimax evaluation to prior multiplier
            // Positive evaluations boost prior, negative evaluations reduce it
            double minimax_multiplier = 1.0 +
                                        tanh(static_cast<double>(minimax_eval) /
                                             300.0) *
                                            0.5;
            prior *= minimax_multiplier;
        }

        // Only clip extreme values before normalization to prevent numerical
        // issues Let priority_bonus have full effect - normalization will
        // handle the final scaling
        prior = std::max(MCTSConfig::MIN_PRIOR_PROBABILITY,
                         std::min(MCTSConfig::MAX_PRIOR_PROBABILITY, prior));

        // Critical endgame safety: suppress suicidal moves when we have only 3
        // pieces If our move allows opponent to win immediately (move+remove),
        // heavily suppress its prior
        if (pos->piece_on_board_count(pos->sideToMove) <= 3 &&
            has_immediate_win(child_position)) {
            prior = MCTSConfig::MIN_PRIOR_PROBABILITY; // Strongly suppress
                                                       // suicidal moves in
                                                       // critical endgame
        }

        raw_priors.push_back(prior);
        child_positions.push_back(child_position);
        child_moves.push_back(move);
    }

    // Normalize prior probabilities among all siblings
    normalize_prior_probabilities(raw_priors);

    // Apply Dirichlet noise to root node for better exploration
    // FIXED: This prevents first child bias by adding randomness to root priors
    if (MCTSConfig::USE_ROOT_DIRICHLET_NOISE && node->parent == nullptr &&
        !raw_priors.empty()) {
        std::mt19937 &thread_rng = ThreadRNGManager::get_thread_rng();
        std::gamma_distribution<double> gamma_dist(MCTSConfig::DIRICHLET_ALPHA,
                                                   1.0);

        // Generate Dirichlet noise
        std::vector<double> noise(raw_priors.size());
        double noise_sum = 0.0;
        for (size_t i = 0; i < noise.size(); ++i) {
            noise[i] = gamma_dist(thread_rng);
            noise_sum += noise[i];
        }

        // Normalize noise
        if (noise_sum > 0.0) {
            for (double &n : noise) {
                n /= noise_sum;
            }

            // Mix with original priors: prior' = (1-ε) * prior + ε * noise
            for (size_t i = 0; i < raw_priors.size(); ++i) {
                raw_priors[i] = (1.0 - MCTSConfig::DIRICHLET_EPSILON) *
                                    raw_priors[i] +
                                MCTSConfig::DIRICHLET_EPSILON * noise[i];
            }

            // Re-normalize after mixing
            normalize_prior_probabilities(raw_priors);
        }
    }

#ifdef MCTS_PRINT_STAT
    // Debug: verify normalization
    double sum_check = 0.0;
    for (double prior : raw_priors) {
        sum_check += prior;
    }
    if (std::abs(sum_check - 1.0) > 0.001) {
        cout << "Warning: Prior normalization failed, sum = " << sum_check
             << endl;
    }
#endif

    // Second pass: create child nodes with normalized priors
    for (size_t i = 0; i < raw_priors.size(); ++i) {
        MCTSNode *child = new MCTSNode(child_positions[i], child_moves[i], node,
                                       static_cast<int>(i), raw_priors[i]);
        if (child != nullptr) {
            node->add_child(child);
        } else {
            // Child creation failed, clean up position
            delete child_positions[i];
        }
    }

    // Mark expansion as complete
    node->is_expanded.store(true, std::memory_order_release);
    node->is_expanding.store(false, std::memory_order_release);

    // FIXED: Instead of always returning children[0], select a better child for
    // evaluation This prevents systematic bias toward the first move in
    // MovePicker order
    if (node->children.empty()) {
        return node;
    }

    // For root node, use random selection to break first child bias
    if (node->parent == nullptr) {
        std::mt19937 &thread_rng = ThreadRNGManager::get_thread_rng();
        std::uniform_int_distribution<size_t> dist(0,
                                                   node->children.size() - 1);
        return node->children[dist(thread_rng)];
    }

    // For non-root nodes, select child with highest prior probability
    // This respects the move ordering while avoiding systematic first-child
    // bias
    MCTSNode *best_prior_child = node->children[0];
    double best_prior = best_prior_child->prior_probability;

    for (size_t i = 1; i < node->children.size(); ++i) {
        if (node->children[i]->prior_probability > best_prior) {
            best_prior = node->children[i]->prior_probability;
            best_prior_child = node->children[i];
        }
    }

    return best_prior_child;
}

// Advanced heuristic evaluation without alpha-beta search (KataGo/LC0 style)
// Supports both human experience heuristics and pure algorithmic evaluation
// IMPORTANT: This function evaluates the position from pos->sideToMove's
// perspective Positive values mean good for pos->sideToMove, negative values
// mean bad The backpropagation process will flip signs as values propagate up
// the tree since each level represents alternating players
double evaluate_position_pure_mcts(MCTSNode *node)
{
    Position *pos = node->position;

    // Check for immediate terminal states
    if (pos->get_phase() == Phase::gameOver) {
        int material_diff = pos->piece_on_board_count(pos->sideToMove) -
                            pos->piece_on_board_count(~pos->sideToMove);
        if (material_diff == 0)
            return 0.0;
        return (material_diff > 0) ? 1.0 : -1.0;
    }

    // Check for immediate win only in critical endgames (opponent has 3 or
    // fewer pieces) This prevents "one-move-loss" scenarios while maintaining
    // normal play in other situations
    if (pos->piece_on_board_count(~pos->sideToMove) <= 3 &&
        has_immediate_win(pos)) {
        return 1.0; // Extremely good for current side (extremely bad for
                    // previous move maker)
    }

    // Heuristic evaluation based on position features
    double evaluation = 0.0;

    // 1. Material advantage (most important)
    int our_pieces = pos->piece_on_board_count(pos->sideToMove);
    int opp_pieces = pos->piece_on_board_count(~pos->sideToMove);
    int material_diff = our_pieces - opp_pieces;
    evaluation += material_diff * 0.4;

    // 2. Pieces in hand advantage (for placing phase)
    if (pos->get_phase() == Phase::placing) {
        int our_hand = pos->piece_in_hand_count(pos->sideToMove);
        int opp_hand = pos->piece_in_hand_count(~pos->sideToMove);
        evaluation += (our_hand - opp_hand) * 0.2;
    }

    if (gameOptions.getDrawOnHumanExperience()) {
        // Human experience-based positional evaluation

        // 3. Center control bonus with human strategic knowledge
        PieceType our_piece_type = (pos->sideToMove == WHITE) ? WHITE_PIECE :
                                                                BLACK_PIECE;
        PieceType opp_piece_type = (pos->sideToMove == WHITE) ? BLACK_PIECE :
                                                                WHITE_PIECE;

        // Center squares: SQ_16, SQ_18, SQ_20, SQ_22 (most important strategic
        // positions) Intuitive scoring: our pieces +1, opponent pieces -1 To
        // preserve identical overall search behavior (given MCTS backprop
        // negates the value at each level), we apply a negative sign when
        // adding to the evaluation below so that the net effect remains
        // unchanged.
        int star_control = 0;
        if (type_of(pos->piece_on(SQ_16)) == our_piece_type)
            star_control++;
        if (type_of(pos->piece_on(SQ_18)) == our_piece_type)
            star_control++;
        if (type_of(pos->piece_on(SQ_20)) == our_piece_type)
            star_control++;
        if (type_of(pos->piece_on(SQ_22)) == our_piece_type)
            star_control++;
        if (type_of(pos->piece_on(SQ_16)) == opp_piece_type)
            star_control--;
        if (type_of(pos->piece_on(SQ_18)) == opp_piece_type)
            star_control--;
        if (type_of(pos->piece_on(SQ_20)) == opp_piece_type)
            star_control--;
        if (type_of(pos->piece_on(SQ_22)) == opp_piece_type)
            star_control--;

        // Apply a negative sign to keep total effect identical to the previous
        // (counter-intuitive) implementation once backprop sign flips are
        // considered.
        evaluation += (-star_control) * 0.15;

        // 4. Mobility evaluation with phase-specific weighting based on human
        // experience
        MovePicker mp(*pos, MOVE_NONE);
        mp.next_move<LEGAL>();
        int mobility = mp.move_count();

        // Adaptive mobility weighting based on game phase and human strategy
        bool is_placing_no_diagonal = (pos->get_phase() == Phase::placing &&
                                       !rule.hasDiagonalLines);
        int total_pieces_in_hand = pos->piece_in_hand_count(WHITE) +
                                   pos->piece_in_hand_count(BLACK);
        bool is_early_placing = is_placing_no_diagonal &&
                                (total_pieces_in_hand > 10);

        double mobility_weight;
        if (is_early_placing) {
            mobility_weight = 0.20; // 10x weight in early no-diagonal placing -
                                    // mobility absolutely dominates
        } else if (is_placing_no_diagonal) {
            mobility_weight = 0.08; // 4x weight in later no-diagonal placing
        } else {
            mobility_weight = 0.02; // Standard weight in moving/flying phases
                                    // or with diagonals
        }
        evaluation += (mobility - 12) * mobility_weight; // 12 is roughly
                                                         // average mobility

        // 5. Phase-specific bonuses based on human knowledge
        if (pos->get_phase() == Phase::moving && our_pieces == 3) {
            // Flying phase advantage
            evaluation += 0.1;
        }
    } else {
        // Pure algorithmic evaluation without human heuristics

        // 3. Simple mobility evaluation
        MovePicker mp(*pos, MOVE_NONE);
        mp.next_move<LEGAL>();
        int mobility = mp.move_count();
        evaluation += (mobility - 12) * 0.02; // Simple mobility bonus

        // 4. Basic phase evaluation
        if (pos->get_phase() == Phase::moving && our_pieces == 3) {
            evaluation += 0.05; // Reduced flying phase bonus
        }
    }

    // 6. Immediate tactical threats (simple mill detection) - used in both
    // modes
    evaluation += detect_immediate_mills(pos) * 0.3;

    // Normalize to [-1, 1] range using tanh
    return tanh(evaluation);
}

// Fast mill threat detection with two-step process (move + remove)
// Enhanced to handle Nine Men's Morris mill formation and capture mechanics
double detect_immediate_mills(Position *pos)
{
    double mill_score = 0.0;

    MovePicker mp(*pos, MOVE_NONE);
    mp.next_move<LEGAL>();

    const int opp_before = pos->piece_on_board_count(~pos->sideToMove);

    for (int i = 0; i < mp.move_count(); ++i) {
        Position p1(*pos);
        p1.do_move(mp.moves[i].move);

        // 1) If do_move already includes capture and completes it
        // (implementation dependent)
        if (p1.piece_on_board_count(~pos->sideToMove) < opp_before) {
            mill_score += 0.5;
            continue;
        }

        // 2) Otherwise enumerate REMOVE moves after mill formation
        MovePicker mp2(p1, MOVE_NONE);
        mp2.next_move<LEGAL>();
        for (int j = 0; j < mp2.move_count(); ++j) {
            if (type_of(mp2.moves[j].move) != MOVETYPE_REMOVE)
                continue;
            Position p2(p1);
            p2.do_move(mp2.moves[j].move);
            if (p2.piece_on_board_count(~pos->sideToMove) < opp_before) {
                mill_score += 0.5;
                break; // Found a capturing sequence, no need to check other
                       // removes
            }
        }
    }
    return mill_score;
}

// Hybrid MCTS-Minimax integration helper functions
// These functions determine when and how to integrate traditional search

// Check if position requires critical analysis (endgame or tactical situations)
bool is_critical_position(const Position *pos)
{
    // Critical if either player has very few pieces
    int white_pieces = pos->piece_on_board_count(WHITE);
    int black_pieces = pos->piece_on_board_count(BLACK);

    return (white_pieces <= MCTSConfig::CRITICAL_ENDGAME_THRESHOLD ||
            black_pieces <= MCTSConfig::CRITICAL_ENDGAME_THRESHOLD);
}

// Check if position is in endgame phase
bool is_endgame_position(const Position *pos)
{
    int total_pieces = pos->piece_on_board_count(WHITE) +
                       pos->piece_on_board_count(BLACK);
    return total_pieces <= MCTSConfig::ENDGAME_PIECE_THRESHOLD;
}

// Check if position requires tactical search (mills, captures, critical moves)
bool requires_tactical_search(const Position *pos)
{
    // Always use tactical search in critical positions
    if (is_critical_position(pos)) {
        return true;
    }

    // Use tactical search when immediate mill threats exist
    if (std::abs(detect_immediate_mills(const_cast<Position *>(pos))) > 0.1) {
        return true;
    }

    // Use tactical search in endgame
    if (is_endgame_position(pos)) {
        return true;
    }

    return false;
}

// Get adaptive minimax search depth based on position characteristics
Depth get_adaptive_minimax_depth(const Position *pos)
{
    // Deeper search in critical positions
    if (is_critical_position(pos)) {
        return MCTSConfig::MINIMAX_LEAF_MAX_DEPTH;
    }

    // Medium depth in endgame
    if (is_endgame_position(pos)) {
        return static_cast<Depth>((MCTSConfig::MINIMAX_LEAF_DEPTH +
                                   MCTSConfig::MINIMAX_LEAF_MAX_DEPTH) /
                                  2);
    }

    // Standard depth otherwise
    return MCTSConfig::MINIMAX_LEAF_DEPTH;
}

// Enhanced evaluation using tactical minimax search for critical positions
double evaluate_with_tactical_search(MCTSNode *node,
                                     Sanmill::Stack<Position> &ss)
{
    Position *pos = node->position;
    Key position_key = pos->key();

    // Use deeper search for tactical positions
    Depth search_depth = requires_tactical_search(pos) ?
                             MCTSConfig::TACTICAL_SEARCH_DEPTH :
                             get_adaptive_minimax_depth(pos);

    // Check cache first
    double cached_evaluation;
    if (minimax_cache.lookup(position_key, search_depth, cached_evaluation)) {
        return cached_evaluation;
    }

    // Perform minimax search
    Move best_move = MOVE_NONE;
    Value minimax_value = Search::search(searchEngine, pos, ss, search_depth,
                                         search_depth, -VALUE_INFINITE,
                                         VALUE_INFINITE, best_move);

    // Convert minimax value to MCTS range [-1, 1]
    // Use tanh to ensure bounded output and handle extreme values gracefully
    double normalized_value = tanh(static_cast<double>(minimax_value) / 200.0);

    // Store in cache
    minimax_cache.store(position_key, search_depth, normalized_value);

    return normalized_value;
}

// Hybrid evaluation combining MCTS heuristics with minimax tactical depth
double evaluate_position_hybrid_minimax(MCTSNode *node,
                                        Sanmill::Stack<Position> &ss)
{
    Position *pos = node->position;

    // Always check for immediate terminal states first
    if (pos->get_phase() == Phase::gameOver) {
        int material_diff = pos->piece_on_board_count(pos->sideToMove) -
                            pos->piece_on_board_count(~pos->sideToMove);
        if (material_diff == 0)
            return 0.0;
        return (material_diff > 0) ? 1.0 : -1.0;
    }

    // Use tactical search for critical positions
    if (requires_tactical_search(pos)) {
        return evaluate_with_tactical_search(node, ss);
    }

    // For non-critical positions, use a blend of heuristic and light minimax
    double heuristic_value = evaluate_position_pure_mcts(node);

    // Add minimax validation for leaf nodes if enabled
    if (MCTSConfig::USE_MINIMAX_AT_LEAF_NODES) {
        double minimax_component = evaluate_with_tactical_search(node, ss);

        // Weighted combination: more weight on minimax in endgame
        double minimax_weight = is_endgame_position(pos) ? 0.7 : 0.3;
        double heuristic_weight = 1.0 - minimax_weight;

        return heuristic_weight * heuristic_value +
               minimax_weight * minimax_component;
    }

    return heuristic_value;
}

// Check if current side to move has an immediate winning move (leading to
// gameOver) This handles Nine Men's Morris two-step process: move + remove
// Critical for preventing "one-move-loss" scenarios in endgames
bool has_immediate_win(const Position *pos)
{
    // Current player to move
    const Color me = pos->sideToMove;

    // First, enumerate all possible moves for current player
    Position gen(*pos);
    MovePicker mp(gen, MOVE_NONE);
    mp.next_move<LEGAL>();

    for (int i = 0; i < mp.move_count(); ++i) {
        const Move m = mp.moves[i].move;

        // Execute this move first
        Position p1(*pos);
        p1.do_move(m);

        // Some implementations might immediately mark gameOver after direct win
        if (p1.get_phase() == Phase::gameOver)
            return true;

        // Critical: if this move forms a mill, the same turn generates
        // MOVETYPE_REMOVE
        MovePicker mp2(p1, MOVE_NONE);
        mp2.next_move<LEGAL>();

        for (int j = 0; j < mp2.move_count(); ++j) {
            const Move r = mp2.moves[j].move;
            if (type_of(r) != MOVETYPE_REMOVE)
                continue;

            Position p2(p1);
            p2.do_move(r);

            // Any REMOVE that leads to gameOver or opponent pieces <= 2 is
            // immediate win
            if (p2.get_phase() == Phase::gameOver)
                return true;

            const int opp_after = p2.piece_on_board_count(~me);
            if (opp_after <= 2)
                return true;
        }
    }
    return false;
}

// Hybrid evaluation: intelligent integration of MCTS heuristics and minimax
// search
double evaluate_position(MCTSNode *node, Sanmill::Stack<Position> &ss)
{
    // Use configuration from MCTSConfig namespace
    if (MCTSConfig::USE_PURE_MCTS_EVALUATION) {
        return evaluate_position_pure_mcts(node);
    } else {
        // New hybrid approach: adaptive integration based on position
        // characteristics
        return evaluate_position_hybrid_minimax(node, ss);
    }
}

// Advanced backpropagation with context-aware RAVE updates and virtual loss
// cleanup Fixed: Now correctly handles player distinction and position context
// in RAVE updates
void backpropagate_values(vector<MCTSNode *> &path, double leaf_value,
                          const vector<MCTSNode *> &vloss_nodes)
{
    // Collect move-position pairs for context-aware RAVE updates
    struct MoveContext
    {
        Move move;
        Position *position;
        Color side_to_move;
    };
    vector<MoveContext> moves_with_context;

    for (size_t i = 1; i < path.size(); ++i) {
        MCTSNode *node = path[i];
        // Use the position BEFORE the move was made (parent's position)
        // This gives us the correct context for when this move was chosen
        Position *move_position = (i > 0) ? path[i - 1]->position :
                                            node->position;
        moves_with_context.push_back({
            node->move, move_position,
            move_position->sideToMove // The player who made this move
        });
    }

    // Backpropagate values up the path
    double value = leaf_value;
    for (int i = static_cast<int>(path.size()) - 1; i >= 0; --i) {
        MCTSNode *node = path[i];

        // Update node statistics
        node->update(value);

        // Update transposition table
        TranspositionEntry tt_entry;
        tt_entry.value = node->get_q_value();
        tt_entry.visits = node->num_visits.load(std::memory_order_acquire);
        tt_entry.depth = static_cast<int>(path.size()) - i;
        transposition_table.store(node->position_key, tt_entry);

        // FIXED: Context-aware RAVE updates that properly distinguish players
        // and positions Update RAVE for all moves that occurred after this node
        // in the simulation The value is from the perspective of the current
        // node's player
        for (size_t j = i + 1; j < moves_with_context.size(); ++j) {
            const MoveContext &move_ctx = moves_with_context[j];

            // Calculate the value from the perspective of the player who made
            // the move We need to account for the alternating nature of the
            // game
            int levels_down = static_cast<int>(j) - i;
            double move_value = (levels_down % 2 == 1) ? value : -value;

            // Update RAVE with full context: move, player, and position
            global_rave_table.update_rave(move_ctx.move, move_value,
                                          move_ctx.position);
        }

        // FIXED: Flip value for opponent - this is necessary in MCTS
        // Each node represents a different player, so we need to negate the
        // value when propagating up the tree. The evaluation function evaluates
        // from the perspective of pos->sideToMove at each node.
        value = -value;
    }

    // FIXED: Remove virtual loss only from nodes that actually had it applied
    // This prevents negative virtual loss accumulation
    for (MCTSNode *node : vloss_nodes) {
        node->remove_virtual_loss();
    }
}

// Single MCTS simulation with advanced features
// Fixed: Properly track and manage virtual loss nodes
void run_mcts_simulation(MCTSNode *root, double c_puct, double fpu_reduction,
                         Sanmill::Stack<Position> &ss)
{
    vector<MCTSNode *> path;
    vector<MCTSNode *> vloss_nodes; // Track nodes with virtual loss applied

    // Selection: traverse tree using PUCT
    MCTSNode *leaf = select_node(root, c_puct, fpu_reduction, path,
                                 vloss_nodes);

    // Expansion: add children if not terminal and not yet expanded
    if (!leaf->is_terminal()) {
        // Use consistent synchronization barrier before accessing children
        if (!leaf->is_expanded.load(std::memory_order_acquire) ||
            leaf->children.empty()) {
            leaf = expand_node(leaf);
            if (leaf != path.back()) {
                // Apply virtual loss to newly expanded and immediately
                // evaluated node
                leaf->add_virtual_loss();
                vloss_nodes.push_back(leaf);
                path.push_back(leaf);
            }
        }
    }

    // Evaluation: get value for leaf node
    double value = evaluate_position(leaf, ss);

    // Backpropagation: update statistics up the tree and clean up virtual loss
    backpropagate_values(path, value, vloss_nodes);
}

// Advanced MCTS worker thread with parallel search optimization
// FIXED: Ensure RAVE thread-local cache is flushed before thread exit
void advanced_mcts_worker(MCTSNode *root, int max_simulations, double c_puct,
                          double fpu_reduction, atomic<bool> &should_stop)
{
    Sanmill::Stack<Position> ss;

    for (int i = 0;
         i < max_simulations && !should_stop.load(std::memory_order_acquire);
         ++i) {
        run_mcts_simulation(root, c_puct, fpu_reduction, ss);

        // More frequent stop checking to ensure responsive shutdown
        if ((i & 63) == 0 && should_stop.load(std::memory_order_acquire)) {
            break; // Early exit if stop requested
        }

        // Periodically check time constraints
        if ((i & (MCTSConfig::CHECK_TIME_FREQUENCY - 1)) == 0 &&
            gameOptions.getMoveTime() > 0) {
            // Time checking logic would be implemented here
            // For now, just continue
        }
    }

    // FIXED: Force synchronization of RAVE thread-local cache before thread
    // exit This prevents data loss when worker threads exit with unflushed
    // updates
    global_rave_table.force_sync();

    // FIXED: Clean up thread-local caches to prevent memory leaks
    GlobalRAVETable::cleanup_current_cache();
    ThreadRNGManager::cleanup_thread_rng();
}

#ifdef MCTS_PRINT_STAT
// Beautiful runtime printing of candidate move statistics
void print_beautiful_move_stats(MCTSNode *root, Move best_move,
                                Value best_value, double search_time_ms = 0.0)
{
    // Show basic info even if no children
    if (root->children.empty()) {
        cout << "\n+==========================================================="
                "===================+\n";
        cout << "|                            MCTS Analysis Report             "
                "                |\n";
        cout << "+============================================================="
                "=================+\n";
        cout << "| Total Simulations: " << setw(8)
             << root->num_visits.load(std::memory_order_acquire)
             << " | Search Time: " << setw(8) << fixed << setprecision(1)
             << search_time_ms << "ms";
        cout << " | Eval Mode: "
             << (MCTSConfig::USE_PURE_MCTS_EVALUATION ? "Pure MCTS" :
                                                        "MCTS-Minimax Hybrid")
             << " |\n";
        cout << "+============================================================="
                "=================+\n";
        cout << "| WARNING: No children expanded - search may have been too "
                "shallow or failed |\n";
        cout << "| Best Move: " << setw(8) << UCI::move(best_move)
             << " | Position Value: " << setw(8) << static_cast<int>(best_value)
             << "                     |\n";
        cout << "+============================================================="
                "=================+\n\n";
        return;
    }

    // Sort children by visit count for better presentation
    vector<MCTSNode *> sorted_children = root->children;
    sort(sorted_children.begin(), sorted_children.end(),
         [](const MCTSNode *a, const MCTSNode *b) {
             return a->num_visits.load(std::memory_order_acquire) >
                    b->num_visits.load(std::memory_order_acquire);
         });

    // Calculate statistics
    int total_visits = root->num_visits.load(std::memory_order_acquire);
    double c_puct = MCTSConfig::DEFAULT_C_PUCT;
    double fpu_reduction = MCTSConfig::FPU_REDUCTION;

    // Beautiful header
    cout << "\n+==============================================================="
            "===============+\n";
    cout << "|                            MCTS Analysis Report                 "
            "            |\n";
    cout << "+================================================================="
            "=============+\n";
    cout << "| Total Simulations: " << setw(8) << total_visits
         << " | Search Time: " << setw(8) << fixed << setprecision(1)
         << search_time_ms << "ms";
    cout << " | Eval Mode: "
         << (MCTSConfig::USE_PURE_MCTS_EVALUATION ? "Pure MCTS" :
                                                    "MCTS-Minimax Hybrid")
         << " |\n";
    cout << "+================================================================="
            "=============+\n\n";

    // Table header
    cout << "+=========+==========+=========+=========+=========+=========+===="
            "=============+\n";
    cout << "|  Move   | Win Rate | Visits  |  Share  |  PUCT   |  Prior  | "
            "Confidence Bar  |\n";
    cout << "+=========+==========+=========+=========+=========+=========+===="
            "=============+\n";

    // Print each move's statistics
    for (size_t i = 0; i < sorted_children.size(); ++i) { // Show all moves
        MCTSNode *child = sorted_children[i];
        string move_str = UCI::move(child->move);

        // Calculate statistics
        double win_rate = (child->get_q_value() + 1.0) / 2.0; // Convert [-1,1]
                                                              // to [0,1]
        int visits = child->num_visits.load(std::memory_order_acquire);
        double visit_share = static_cast<double>(visits) / total_visits * 100.0;
        double puct_value = child->get_puct_value(c_puct, fpu_reduction);
        double prior = child->prior_probability;

        // Create confidence bar (based on visit count)
        int bar_length = min(15, static_cast<int>(visit_share * 15.0 / 100.0));
        string confidence_bar = string(bar_length, '#') +
                                string(15 - bar_length, '.');

        // Color coding based on win rate
        string color_prefix = "";
        if (child->move == best_move) {
            color_prefix = "*"; // Star for best move
        } else if (win_rate > 0.7) {
            color_prefix = "+"; // Plus for very good moves
        } else if (win_rate > 0.5) {
            color_prefix = "="; // Equal for decent moves
        } else {
            color_prefix = "-"; // Minus for poor moves
        }

        cout << "|" << color_prefix << setw(7) << move_str << "|" << setw(9)
             << fixed << setprecision(1) << (win_rate * 100.0) << "%"
             << "|" << setw(8) << visits << "|" << setw(8) << fixed
             << setprecision(1) << visit_share << "%"
             << "|" << setw(8) << fixed << setprecision(3) << puct_value << "|"
             << setw(8) << fixed << setprecision(3) << prior << "| "
             << confidence_bar << " |\n";
    }

    cout << "+=========+==========+=========+=========+=========+=========+===="
            "=============+\n";

    // Summary information
    cout << "\nAnalysis Summary:\n";
    cout << "   * Best Move: " << UCI::move(best_move)
         << " (Win Rate: " << fixed << setprecision(1)
         << ((sorted_children[0]->get_q_value() + 1.0) / 2.0 * 100.0) << "%)\n";
    cout << "   * Position Value: " << static_cast<int>(best_value) << "\n";
    cout << "   * Moves Analyzed: " << sorted_children.size() << "\n";

    // Show top 3 alternatives
    if (sorted_children.size() > 1) {
        cout << "   * Top Alternatives:\n";
        for (size_t i = 1; i < min(sorted_children.size(), size_t(10));
             ++i) { // Show up to 10 alternatives
            MCTSNode *alt = sorted_children[i];
            double alt_win_rate = (alt->get_q_value() + 1.0) / 2.0 * 100.0;
            cout << "     " << (i + 1) << ". " << UCI::move(alt->move) << " ("
                 << fixed << setprecision(1) << alt_win_rate << "%, "
                 << alt->num_visits.load(std::memory_order_acquire)
                 << " visits)\n";
        }
    }

    // Performance metrics
    if (search_time_ms > 0) {
        double nps = total_visits / (search_time_ms / 1000.0); // Nodes per
                                                               // second
        cout << "   * Performance: " << fixed << setprecision(0) << nps
             << " simulations/sec\n";
    }

    cout << "\n" << string(80, '=') << "\n\n";
}
#endif // MCTS_PRINT_STAT

// Main Monte Carlo Tree Search function with advanced optimizations
Value monte_carlo_tree_search(Position *pos, Move &best_move)
{
    // Display search mode information
    cout << "Hybrid MCTS-Minimax Search Started (Skill: "
         << gameOptions.getSkillLevel() << ")" << endl;
    cout << "  Pure MCTS: "
         << (MCTSConfig::USE_PURE_MCTS_EVALUATION ? "Yes" : "No") << endl;
    cout << "  Leaf Minimax: "
         << (MCTSConfig::USE_MINIMAX_AT_LEAF_NODES ? "Yes" : "No") << endl;
    cout << "  Tactical Search: "
         << (MCTSConfig::USE_TACTICAL_SEARCH ? "Yes" : "No") << endl;
    cout << "  Root Validation: "
         << (MCTSConfig::USE_ROOT_MINIMAX_VALIDATION ? "Yes" : "No") << endl;

    // Initialize search parameters
    const double c_puct = MCTSConfig::DEFAULT_C_PUCT;
    const double fpu_reduction = MCTSConfig::FPU_REDUCTION;

    // Calculate number of simulations based on skill level and position
    // complexity
    int base_simulations = gameOptions.getSkillLevel() *
                           MCTSConfig::ITERATIONS_PER_SKILL_LEVEL;

    // Adaptive simulation count based on position characteristics
    double simulation_multiplier = 1.0;
    if (MCTSConfig::USE_ADAPTIVE_SIMULATIONS) {
        if (is_critical_position(pos)) {
            simulation_multiplier = MCTSConfig::CRITICAL_SIMULATION_MULTIPLIER;
            cout << "  Critical position detected - increasing simulations by "
                 << simulation_multiplier << "x" << endl;
        } else if (is_endgame_position(pos)) {
            simulation_multiplier = MCTSConfig::ENDGAME_SIMULATION_MULTIPLIER;
            cout << "  Endgame position detected - increasing simulations by "
                 << simulation_multiplier << "x" << endl;
        }
    }

    int max_simulations = static_cast<int>(base_simulations *
                                           simulation_multiplier);

    // FIXED: Handle edge case where skill level is 0 or very low
    if (max_simulations == 0) {
        cout << "Warning: Skill level 0 detected, using minimal search" << endl;
        max_simulations = 1; // Ensure at least one simulation to trigger root
                             // expansion
    }

    // Reduce simulations for opening moves to speed up play
    if (pos->is_board_empty()) {
        max_simulations = min(max_simulations, 1000);
    }

    // Create root node
    MCTSNode *root = new MCTSNode(new Position(*pos), MOVE_NONE, nullptr, 0,
                                  1.0);

    // Time management
    auto start_time = chrono::steady_clock::now();
    auto move_time_limit = gameOptions.getMoveTime();

    // Adaptive multi-threading setup based on hardware and workload
    int num_threads = thread::hardware_concurrency();
    if (num_threads == 0)
        num_threads = 1; // Fallback for systems that don't report cores

    // Adaptive thread count based on simulation budget and hardware
    if (max_simulations < MCTSConfig::SMALL_WORKLOAD_THRESHOLD) {
        // Small workloads: limit threads to avoid overhead
        num_threads = min(num_threads, 2);
    } else if (max_simulations < MCTSConfig::MEDIUM_WORKLOAD_THRESHOLD) {
        // Medium workloads: moderate parallelism
        num_threads = min(num_threads, 4);
    } else {
        // Large workloads: use more threads but cap at configured maximum
        num_threads = min(num_threads, MCTSConfig::MAX_THREADS);
    }

    // Ensure minimum work per thread to avoid excessive coordination overhead
    if (max_simulations / num_threads <
        MCTSConfig::MIN_SIMULATIONS_PER_THREAD) {
        num_threads = max(1, max_simulations /
                                 MCTSConfig::MIN_SIMULATIONS_PER_THREAD);
    }

    vector<thread> worker_threads;
    atomic<bool> should_stop(false);

    int simulations_per_thread = max_simulations / num_threads;

    // Debug: Show threading configuration
    cout << "Using " << num_threads << " threads (" << simulations_per_thread
         << " simulations per thread)" << endl;

    // Launch worker threads
    for (int i = 0; i < num_threads; ++i) {
        worker_threads.emplace_back(advanced_mcts_worker, root,
                                    simulations_per_thread, c_puct,
                                    fpu_reduction, ref(should_stop));
    }

    // Monitor time limit
    if (move_time_limit > 0) {
        auto time_limit = chrono::seconds(move_time_limit);
        while (chrono::steady_clock::now() - start_time < time_limit) {
            this_thread::sleep_for(chrono::milliseconds(50));
        }
        should_stop.store(true, std::memory_order_release);
    }

    // Ensure all threads stop before proceeding (redundant but safe)
    should_stop.store(true, std::memory_order_release);

    // Wait for all threads to complete with timeout protection
    for (auto &t : worker_threads) {
        if (t.joinable()) {
            t.join();
        }
    }

    // Memory barrier to ensure all thread operations are complete
    std::atomic_thread_fence(std::memory_order_acq_rel);

    // Select best move based on visit count (robust child selection)
    // FIXED: Avoid infinite spin-wait when root is never expanded (skill=0 or
    // very short time)
    MCTSNode *best_child = nullptr;
    int max_visits = -1;

    // FIXED: Instead of spin-waiting, directly expand root if needed
    // This handles cases where no simulations ran (skill=0 or early timeout)
    if (!root->is_expanded.load(std::memory_order_acquire)) {
        expand_node(root); // Thread-safe: uses internal CAS protection via
                           // is_expanding
    }

    // Critical endgame safety: prioritize "safe" children only when we have 3
    // or fewer pieces This prevents choosing moves that allow opponent to win
    // in one move in critical situations
    bool is_critical_endgame = pos->piece_on_board_count(pos->sideToMove) <= 3;

    std::vector<MCTSNode *> safe_children;
    if (is_critical_endgame) {
        for (MCTSNode *child : root->children) {
            if (!has_immediate_win(child->position)) {
                safe_children.push_back(child);
            }
        }

        // Debug output to verify fix effectiveness in critical endgame
        cout << "[MCTS] Critical endgame - Safe children: "
             << safe_children.size() << " / " << root->children.size()
             << " total children" << endl;
    }

    // Choose from safe children only in critical endgame, otherwise use all
    // children
    const std::vector<MCTSNode *> &selection_pool = (is_critical_endgame &&
                                                     !safe_children.empty()) ?
                                                        safe_children :
                                                        root->children;

    // Find best child from the selection pool based on visit count
    for (MCTSNode *child : selection_pool) {
        // FIXED: Use acquire for critical path to ensure consistency with
        // statistics updates
        int child_visits = child->num_visits.load(std::memory_order_acquire);
        if (child_visits > max_visits) {
            max_visits = child_visits;
            best_child = child;
        }
    }

    // FIXED: Improved fallback logic for cases with no expanded children
    if (best_child != nullptr) {
        best_move = best_child->move;
    } else {
        // Fallback to MovePicker when no children available (no legal moves or
        // expansion failed)
        MovePicker mp(*pos, MOVE_NONE);
        mp.next_move<LEGAL>();
        if (mp.move_count() > 0) {
            best_move = mp.moves[0].move;
        } else {
            // Ultimate fallback: if no legal moves at all, use MOVE_NONE
            best_move = MOVE_NONE;
        }
    }

    // Calculate return value based on position evaluation
    Value return_value = VALUE_DRAW;
    if (best_child != nullptr) {
        double q_value = best_child->get_q_value();
        return_value = static_cast<Value>(
            q_value * static_cast<double>(VALUE_EACH_PIECE) * 2.0);
    }

#ifdef MCTS_PRINT_STAT
    // Calculate search time for performance metrics
    auto end_time = chrono::steady_clock::now();
    auto search_duration = chrono::duration_cast<chrono::microseconds>(
        end_time - start_time);
    double search_time_ms = search_duration.count() / 1000.0;

    // Debug information before printing stats
    cout << "\n=== MCTS DEBUG INFO ===\n";
    cout << "Root visits: " << root->num_visits.load(std::memory_order_acquire)
         << "\n";
    cout << "Root children count: " << root->children.size() << "\n";
    cout << "Best move: " << UCI::move(best_move) << "\n";
    cout << "Return value: " << return_value << "\n";
    cout << "Search time: " << search_time_ms << "ms\n";
    cout << "=======================\n" << endl;

    print_beautiful_move_stats(root, best_move, return_value, search_time_ms);
#endif // MCTS_PRINT_STAT

    // Force synchronization of RAVE statistics before cleanup
    global_rave_table.force_sync();

    // Clean up
    delete_mcts_tree(root);

    // Optional: Clear minimax cache periodically to prevent memory bloat
    // This can be done less frequently in a real implementation
    static int search_count = 0;
    if (++search_count % 10 == 0) {
        minimax_cache.clear();
    }

    return return_value;
}
