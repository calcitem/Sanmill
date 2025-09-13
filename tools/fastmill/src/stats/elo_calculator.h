// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// elo_calculator.h - ELO rating calculation for Mill tournaments

#pragma once

#include <map>
#include <string>
#include <vector>

namespace fastmill {

struct EngineRating
{
    std::string name;
    double rating {1500.0};
    int games_played {0};
    int wins {0};
    int losses {0};
    int draws {0};

    double getScore() const
    {
        return games_played > 0 ? (wins + 0.5 * draws) / games_played : 0.0;
    }

    double getWinRate() const
    {
        return games_played > 0 ? static_cast<double>(wins) / games_played :
                                  0.0;
    }
};

class EloCalculator
{
public:
    explicit EloCalculator(double k_factor = 32.0);

    // Initialize engines with starting ratings
    void addEngine(const std::string &name, double initial_rating = 1500.0);

    // Update ratings based on game result
    void updateRatings(const std::string &white_engine,
                       const std::string &black_engine,
                       double white_score); // 1.0 = white wins, 0.5 = draw, 0.0
                                            // = black wins

    // Get current ratings
    EngineRating getRating(const std::string &engine_name) const;
    std::vector<EngineRating> getAllRatings() const;
    std::vector<EngineRating> getRankings() const; // Sorted by rating

    // Statistics
    double getAverageRating() const;
    double getRatingSpread() const; // Difference between highest and lowest

    // Reset all ratings
    void reset();

private:
    double k_factor_;
    std::map<std::string, EngineRating> ratings_;

    // ELO calculation helpers
    double calculateExpectedScore(double rating_a, double rating_b) const;
    double calculateNewRating(double old_rating, double expected_score,
                              double actual_score) const;
};

} // namespace fastmill
