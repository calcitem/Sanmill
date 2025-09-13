// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tunable_parameters.h - Global tunable parameters for SPSA optimization

#ifndef TUNABLE_PARAMETERS_H_INCLUDED
#define TUNABLE_PARAMETERS_H_INCLUDED

#include "types.h"
#include <atomic>
#include <mutex>

namespace TunableParams {

// Thread-safe parameter container
class ParameterManager
{
public:
    static ParameterManager &instance()
    {
        static ParameterManager instance_;
        return instance_;
    }

    // Search Algorithm Parameters (for Alpha-Beta, PVS, MTD(f))
    std::atomic<int> search_depth {6};
    std::atomic<int> quiescence_depth {8};
    std::atomic<int> null_move_reduction {2};

    // Evaluation Parameters
    std::atomic<int> piece_value {5};
    std::atomic<int> piece_inhand_value {5};
    std::atomic<int> piece_onboard_value {5};
    std::atomic<int> piece_needremove_value {5};

    // Additional Evaluation Parameters
    std::atomic<double> mobility_weight {1.0};
    std::atomic<double> positional_weight {1.0};
    std::atomic<int> endgame_piece_threshold {6};
    std::atomic<double> tempo_bonus {0.1};

    // Thread-safe parameter updates
    void update_exploration_parameter(double value)
    {
        exploration_parameter.store(value, std::memory_order_relaxed);
    }

    void update_bias_factor(double value)
    {
        bias_factor.store(value, std::memory_order_relaxed);
    }

    void update_alpha_beta_depth(int value)
    {
        alpha_beta_depth.store(value, std::memory_order_relaxed);
    }

    void update_piece_value(int value)
    {
        piece_value.store(value, std::memory_order_relaxed);
        // Update derived values
        piece_inhand_value.store(value, std::memory_order_relaxed);
        piece_onboard_value.store(value, std::memory_order_relaxed);
        piece_needremove_value.store(value, std::memory_order_relaxed);
    }

    void update_piece_inhand_value(int value)
    {
        piece_inhand_value.store(value, std::memory_order_relaxed);
    }

    void update_piece_onboard_value(int value)
    {
        piece_onboard_value.store(value, std::memory_order_relaxed);
    }

    void update_piece_needremove_value(int value)
    {
        piece_needremove_value.store(value, std::memory_order_relaxed);
    }

    void update_mobility_weight(double value)
    {
        mobility_weight.store(value, std::memory_order_relaxed);
    }

    // Get current values (thread-safe)
    double get_exploration_parameter() const
    {
        return exploration_parameter.load(std::memory_order_relaxed);
    }

    double get_bias_factor() const
    {
        return bias_factor.load(std::memory_order_relaxed);
    }

    int get_alpha_beta_depth() const
    {
        return alpha_beta_depth.load(std::memory_order_relaxed);
    }

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

    int get_iterations_per_skill_level() const
    {
        return iterations_per_skill_level.load(std::memory_order_relaxed);
    }

    int get_check_time_frequency() const
    {
        return check_time_frequency.load(std::memory_order_relaxed);
    }

    // Reset to default values
    void reset_to_defaults()
    {
        exploration_parameter.store(0.5, std::memory_order_relaxed);
        bias_factor.store(0.05, std::memory_order_relaxed);
        alpha_beta_depth.store(6, std::memory_order_relaxed);
        piece_value.store(5, std::memory_order_relaxed);
        piece_inhand_value.store(5, std::memory_order_relaxed);
        piece_onboard_value.store(5, std::memory_order_relaxed);
        piece_needremove_value.store(5, std::memory_order_relaxed);
        mobility_weight.store(1.0, std::memory_order_relaxed);
        iterations_per_skill_level.store(2048, std::memory_order_relaxed);
        check_time_frequency.store(128, std::memory_order_relaxed);
    }

private:
    ParameterManager() = default;
    ~ParameterManager() = default;
    ParameterManager(const ParameterManager &) = delete;
    ParameterManager &operator=(const ParameterManager &) = delete;
};

// Convenience macros for accessing parameters
#define TUNABLE_EXPLORATION_PARAMETER \
    (TunableParams::ParameterManager::instance().get_exploration_parameter())
#define TUNABLE_BIAS_FACTOR \
    (TunableParams::ParameterManager::instance().get_bias_factor())
#define TUNABLE_ALPHA_BETA_DEPTH \
    (TunableParams::ParameterManager::instance().get_alpha_beta_depth())
#define TUNABLE_PIECE_VALUE \
    (TunableParams::ParameterManager::instance().get_piece_value())
#define TUNABLE_PIECE_INHAND_VALUE \
    (TunableParams::ParameterManager::instance().get_piece_inhand_value())
#define TUNABLE_PIECE_ONBOARD_VALUE \
    (TunableParams::ParameterManager::instance().get_piece_onboard_value())
#define TUNABLE_PIECE_NEEDREMOVE_VALUE \
    (TunableParams::ParameterManager::instance().get_piece_needremove_value())
#define TUNABLE_MOBILITY_WEIGHT \
    (TunableParams::ParameterManager::instance().get_mobility_weight())
#define TUNABLE_ITERATIONS_PER_SKILL_LEVEL \
    (TunableParams::ParameterManager::instance() \
         .get_iterations_per_skill_level())
#define TUNABLE_CHECK_TIME_FREQUENCY \
    (TunableParams::ParameterManager::instance().get_check_time_frequency())

} // namespace TunableParams

#endif // TUNABLE_PARAMETERS_H_INCLUDED
