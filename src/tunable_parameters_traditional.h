// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tunable_parameters_traditional.h - Tunable parameters for traditional search
// algorithms This system is designed for Alpha-Beta, PVS, MTD(f) algorithms,
// NOT for MCTS

#ifndef TUNABLE_PARAMETERS_TRADITIONAL_H_INCLUDED
#define TUNABLE_PARAMETERS_TRADITIONAL_H_INCLUDED

#include "types.h"
#include <atomic>
#include <mutex>

namespace TunableParams {

// Thread-safe parameter container for traditional search algorithms
class TraditionalParameterManager
{
public:
    static TraditionalParameterManager &instance()
    {
        static TraditionalParameterManager instance_;
        return instance_;
    }

    // ========== Search Algorithm Parameters ==========
    // These parameters control the search behavior of Alpha-Beta, PVS, MTD(f)

    std::atomic<int> max_search_depth {8};    // Maximum search depth
    std::atomic<int> quiescence_depth {16};   // Quiescence search depth
    std::atomic<int> null_move_reduction {3}; // Null move pruning reduction
    std::atomic<int> late_move_reduction {2}; // Late move reduction
    std::atomic<int> futility_margin {100};   // Futility pruning margin
    std::atomic<int> razor_margin {50};       // Razoring margin

    // ========== Evaluation Function Parameters ==========
    // These control the position evaluation scoring

    // Basic piece values
    std::atomic<int> piece_value {5};
    std::atomic<int> piece_inhand_value {5};
    std::atomic<int> piece_onboard_value {5};
    std::atomic<int> piece_needremove_value {5};

    // Positional evaluation weights
    std::atomic<double> mobility_weight {1.0}; // Weight for mobility evaluation
    std::atomic<double> center_control_weight {0.8}; // Weight for center
                                                     // control
    std::atomic<double> mill_potential_weight {1.2}; // Weight for mill
                                                     // formation potential
    std::atomic<double> blocking_weight {0.9}; // Weight for blocking opponent
                                               // mills

    // Phase-specific parameters
    std::atomic<int> endgame_piece_threshold {6}; // When to switch to endgame
                                                  // evaluation
    std::atomic<double> endgame_mobility_bonus {1.5}; // Extra mobility
                                                      // importance in endgame
    std::atomic<double> tempo_bonus {0.1}; // Bonus for having the move

    // Mill evaluation parameters
    std::atomic<int> mill_value {15};          // Base value of a mill
    std::atomic<int> potential_mill_value {3}; // Value of potential mill (2
                                               // pieces in line)
    std::atomic<int> broken_mill_penalty {8};  // Penalty for broken mill

    // ========== Thread-safe parameter updates ==========

    // Search parameters
    void update_max_search_depth(int value)
    {
        max_search_depth.store(std::max(1, std::min(20, value)),
                               std::memory_order_relaxed);
    }

    void update_quiescence_depth(int value)
    {
        quiescence_depth.store(std::max(0, std::min(32, value)),
                               std::memory_order_relaxed);
    }

    void update_null_move_reduction(int value)
    {
        null_move_reduction.store(std::max(1, std::min(8, value)),
                                  std::memory_order_relaxed);
    }

    void update_late_move_reduction(int value)
    {
        late_move_reduction.store(std::max(1, std::min(6, value)),
                                  std::memory_order_relaxed);
    }

    void update_futility_margin(int value)
    {
        futility_margin.store(std::max(10, std::min(500, value)),
                              std::memory_order_relaxed);
    }

    void update_razor_margin(int value)
    {
        razor_margin.store(std::max(10, std::min(200, value)),
                           std::memory_order_relaxed);
    }

    // Evaluation parameters
    void update_piece_value(int value)
    {
        int clamped_value = std::max(1, std::min(50, value));
        piece_value.store(clamped_value, std::memory_order_relaxed);
    }

    void update_piece_inhand_value(int value)
    {
        piece_inhand_value.store(std::max(1, std::min(50, value)),
                                 std::memory_order_relaxed);
    }

    void update_piece_onboard_value(int value)
    {
        piece_onboard_value.store(std::max(1, std::min(50, value)),
                                  std::memory_order_relaxed);
    }

    void update_piece_needremove_value(int value)
    {
        piece_needremove_value.store(std::max(1, std::min(50, value)),
                                     std::memory_order_relaxed);
    }

    void update_mobility_weight(double value)
    {
        mobility_weight.store(std::max(0.0, std::min(5.0, value)),
                              std::memory_order_relaxed);
    }

    void update_center_control_weight(double value)
    {
        center_control_weight.store(std::max(0.0, std::min(3.0, value)),
                                    std::memory_order_relaxed);
    }

    void update_mill_potential_weight(double value)
    {
        mill_potential_weight.store(std::max(0.0, std::min(3.0, value)),
                                    std::memory_order_relaxed);
    }

    void update_blocking_weight(double value)
    {
        blocking_weight.store(std::max(0.0, std::min(3.0, value)),
                              std::memory_order_relaxed);
    }

    void update_endgame_piece_threshold(int value)
    {
        endgame_piece_threshold.store(std::max(3, std::min(12, value)),
                                      std::memory_order_relaxed);
    }

    void update_endgame_mobility_bonus(double value)
    {
        endgame_mobility_bonus.store(std::max(0.5, std::min(3.0, value)),
                                     std::memory_order_relaxed);
    }

    void update_tempo_bonus(double value)
    {
        tempo_bonus.store(std::max(0.0, std::min(1.0, value)),
                          std::memory_order_relaxed);
    }

    void update_mill_value(int value)
    {
        mill_value.store(std::max(5, std::min(50, value)),
                         std::memory_order_relaxed);
    }

    void update_potential_mill_value(int value)
    {
        potential_mill_value.store(std::max(1, std::min(20, value)),
                                   std::memory_order_relaxed);
    }

    void update_broken_mill_penalty(int value)
    {
        broken_mill_penalty.store(std::max(1, std::min(30, value)),
                                  std::memory_order_relaxed);
    }

    // ========== Thread-safe parameter getters ==========

    // Search parameters
    int get_max_search_depth() const
    {
        return max_search_depth.load(std::memory_order_relaxed);
    }

    int get_quiescence_depth() const
    {
        return quiescence_depth.load(std::memory_order_relaxed);
    }

    int get_null_move_reduction() const
    {
        return null_move_reduction.load(std::memory_order_relaxed);
    }

    int get_late_move_reduction() const
    {
        return late_move_reduction.load(std::memory_order_relaxed);
    }

    int get_futility_margin() const
    {
        return futility_margin.load(std::memory_order_relaxed);
    }

    int get_razor_margin() const
    {
        return razor_margin.load(std::memory_order_relaxed);
    }

    // Evaluation parameters
    int get_piece_value() const
    {
        return piece_value.load(std::memory_order_relaxed);
    }

    int get_piece_inhand_value() const
    {
        return piece_inhand_value.load(std::memory_order_relaxed);
    }

    int get_piece_onboard_value() const
    {
        return piece_onboard_value.load(std::memory_order_relaxed);
    }

    int get_piece_needremove_value() const
    {
        return piece_needremove_value.load(std::memory_order_relaxed);
    }

    double get_mobility_weight() const
    {
        return mobility_weight.load(std::memory_order_relaxed);
    }

    double get_center_control_weight() const
    {
        return center_control_weight.load(std::memory_order_relaxed);
    }

    double get_mill_potential_weight() const
    {
        return mill_potential_weight.load(std::memory_order_relaxed);
    }

    double get_blocking_weight() const
    {
        return blocking_weight.load(std::memory_order_relaxed);
    }

    int get_endgame_piece_threshold() const
    {
        return endgame_piece_threshold.load(std::memory_order_relaxed);
    }

    double get_endgame_mobility_bonus() const
    {
        return endgame_mobility_bonus.load(std::memory_order_relaxed);
    }

    double get_tempo_bonus() const
    {
        return tempo_bonus.load(std::memory_order_relaxed);
    }

    int get_mill_value() const
    {
        return mill_value.load(std::memory_order_relaxed);
    }

    int get_potential_mill_value() const
    {
        return potential_mill_value.load(std::memory_order_relaxed);
    }

    int get_broken_mill_penalty() const
    {
        return broken_mill_penalty.load(std::memory_order_relaxed);
    }

    // Reset to default values
    void reset_to_defaults()
    {
        // Search parameters
        max_search_depth.store(8, std::memory_order_relaxed);
        quiescence_depth.store(16, std::memory_order_relaxed);
        null_move_reduction.store(3, std::memory_order_relaxed);
        late_move_reduction.store(2, std::memory_order_relaxed);
        futility_margin.store(100, std::memory_order_relaxed);
        razor_margin.store(50, std::memory_order_relaxed);

        // Evaluation parameters
        piece_value.store(5, std::memory_order_relaxed);
        piece_inhand_value.store(5, std::memory_order_relaxed);
        piece_onboard_value.store(5, std::memory_order_relaxed);
        piece_needremove_value.store(5, std::memory_order_relaxed);
        mobility_weight.store(1.0, std::memory_order_relaxed);
        center_control_weight.store(0.8, std::memory_order_relaxed);
        mill_potential_weight.store(1.2, std::memory_order_relaxed);
        blocking_weight.store(0.9, std::memory_order_relaxed);
        endgame_piece_threshold.store(6, std::memory_order_relaxed);
        endgame_mobility_bonus.store(1.5, std::memory_order_relaxed);
        tempo_bonus.store(0.1, std::memory_order_relaxed);
        mill_value.store(15, std::memory_order_relaxed);
        potential_mill_value.store(3, std::memory_order_relaxed);
        broken_mill_penalty.store(8, std::memory_order_relaxed);
    }

    // Check if MCTS is currently selected (SPSA should not run with MCTS)
    bool is_traditional_algorithm_selected() const;

private:
    TraditionalParameterManager() = default;
    ~TraditionalParameterManager() = default;
    TraditionalParameterManager(const TraditionalParameterManager &) = delete;
    TraditionalParameterManager &
    operator=(const TraditionalParameterManager &) = delete;
};

// Convenience macros for accessing parameters in traditional search algorithms
#define TUNABLE_MAX_SEARCH_DEPTH \
    (TunableParams::TraditionalParameterManager::instance() \
         .get_max_search_depth())
#define TUNABLE_QUIESCENCE_DEPTH \
    (TunableParams::TraditionalParameterManager::instance() \
         .get_quiescence_depth())
#define TUNABLE_NULL_MOVE_REDUCTION \
    (TunableParams::TraditionalParameterManager::instance() \
         .get_null_move_reduction())
#define TUNABLE_LATE_MOVE_REDUCTION \
    (TunableParams::TraditionalParameterManager::instance() \
         .get_late_move_reduction())
#define TUNABLE_FUTILITY_MARGIN \
    (TunableParams::TraditionalParameterManager::instance() \
         .get_futility_margin())
#define TUNABLE_RAZOR_MARGIN \
    (TunableParams::TraditionalParameterManager::instance().get_razor_margin())

#define TUNABLE_PIECE_VALUE \
    (TunableParams::TraditionalParameterManager::instance().get_piece_value())
#define TUNABLE_PIECE_INHAND_VALUE \
    (TunableParams::TraditionalParameterManager::instance() \
         .get_piece_inhand_value())
#define TUNABLE_PIECE_ONBOARD_VALUE \
    (TunableParams::TraditionalParameterManager::instance() \
         .get_piece_onboard_value())
#define TUNABLE_PIECE_NEEDREMOVE_VALUE \
    (TunableParams::TraditionalParameterManager::instance() \
         .get_piece_needremove_value())

#define TUNABLE_MOBILITY_WEIGHT \
    (TunableParams::TraditionalParameterManager::instance() \
         .get_mobility_weight())
#define TUNABLE_CENTER_CONTROL_WEIGHT \
    (TunableParams::TraditionalParameterManager::instance() \
         .get_center_control_weight())
#define TUNABLE_MILL_POTENTIAL_WEIGHT \
    (TunableParams::TraditionalParameterManager::instance() \
         .get_mill_potential_weight())
#define TUNABLE_BLOCKING_WEIGHT \
    (TunableParams::TraditionalParameterManager::instance() \
         .get_blocking_weight())

#define TUNABLE_ENDGAME_PIECE_THRESHOLD \
    (TunableParams::TraditionalParameterManager::instance() \
         .get_endgame_piece_threshold())
#define TUNABLE_ENDGAME_MOBILITY_BONUS \
    (TunableParams::TraditionalParameterManager::instance() \
         .get_endgame_mobility_bonus())
#define TUNABLE_TEMPO_BONUS \
    (TunableParams::TraditionalParameterManager::instance().get_tempo_bonus())

#define TUNABLE_MILL_VALUE \
    (TunableParams::TraditionalParameterManager::instance().get_mill_value())
#define TUNABLE_POTENTIAL_MILL_VALUE \
    (TunableParams::TraditionalParameterManager::instance() \
         .get_potential_mill_value())
#define TUNABLE_BROKEN_MILL_PENALTY \
    (TunableParams::TraditionalParameterManager::instance() \
         .get_broken_mill_penalty())

} // namespace TunableParams

#endif // TUNABLE_PARAMETERS_TRADITIONAL_H_INCLUDED
