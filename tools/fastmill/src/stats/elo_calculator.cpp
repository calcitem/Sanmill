// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// elo_calculator.cpp - Implementation of ELO rating calculator

#include "elo_calculator.h"
#include <algorithm>
#include <cmath>
#include <numeric>

namespace fastmill {

EloCalculator::EloCalculator(double k_factor)
    : k_factor_(k_factor)
{ }

void EloCalculator::addEngine(const std::string &name, double initial_rating)
{
    if (ratings_.find(name) == ratings_.end()) {
        EngineRating rating;
        rating.name = name;
        rating.rating = initial_rating;
        ratings_[name] = rating;
    }
}

void EloCalculator::updateRatings(const std::string &white_engine,
                                  const std::string &black_engine,
                                  double white_score)
{
    // Ensure both engines exist
    addEngine(white_engine);
    addEngine(black_engine);

    EngineRating &white_rating = ratings_[white_engine];
    EngineRating &black_rating = ratings_[black_engine];

    // Calculate expected scores
    double white_expected = calculateExpectedScore(white_rating.rating,
                                                   black_rating.rating);
    double black_expected = calculateExpectedScore(black_rating.rating,
                                                   white_rating.rating);

    // Update ratings
    double old_white_rating = white_rating.rating;
    double old_black_rating = black_rating.rating;

    white_rating.rating = calculateNewRating(old_white_rating, white_expected,
                                             white_score);
    black_rating.rating = calculateNewRating(old_black_rating, black_expected,
                                             1.0 - white_score);

    // Update game statistics
    white_rating.games_played++;
    black_rating.games_played++;

    if (white_score == 1.0) {
        white_rating.wins++;
        black_rating.losses++;
    } else if (white_score == 0.0) {
        white_rating.losses++;
        black_rating.wins++;
    } else {
        white_rating.draws++;
        black_rating.draws++;
    }
}

EngineRating EloCalculator::getRating(const std::string &engine_name) const
{
    auto it = ratings_.find(engine_name);
    if (it != ratings_.end()) {
        return it->second;
    }

    // Return default rating if engine not found
    EngineRating default_rating;
    default_rating.name = engine_name;
    return default_rating;
}

std::vector<EngineRating> EloCalculator::getAllRatings() const
{
    std::vector<EngineRating> all_ratings;
    all_ratings.reserve(ratings_.size());

    for (const auto &pair : ratings_) {
        all_ratings.push_back(pair.second);
    }

    return all_ratings;
}

std::vector<EngineRating> EloCalculator::getRankings() const
{
    auto rankings = getAllRatings();

    // Sort by rating (descending)
    std::sort(rankings.begin(), rankings.end(),
              [](const EngineRating &a, const EngineRating &b) {
                  if (std::abs(a.rating - b.rating) < 0.01) {
                      // If ratings are very close, sort by games played, then
                      // by score
                      if (a.games_played == b.games_played) {
                          return a.getScore() > b.getScore();
                      }
                      return a.games_played > b.games_played;
                  }
                  return a.rating > b.rating;
              });

    return rankings;
}

double EloCalculator::getAverageRating() const
{
    if (ratings_.empty())
        return 1500.0;

    double sum = std::accumulate(ratings_.begin(), ratings_.end(), 0.0,
                                 [](double sum, const auto &pair) {
                                     return sum + pair.second.rating;
                                 });

    return sum / ratings_.size();
}

double EloCalculator::getRatingSpread() const
{
    if (ratings_.empty())
        return 0.0;

    auto minmax = std::minmax_element(
        ratings_.begin(), ratings_.end(), [](const auto &a, const auto &b) {
            return a.second.rating < b.second.rating;
        });

    return minmax.second->second.rating - minmax.first->second.rating;
}

void EloCalculator::reset()
{
    for (auto &pair : ratings_) {
        EngineRating &rating = pair.second;
        rating.rating = 1500.0;
        rating.games_played = 0;
        rating.wins = 0;
        rating.losses = 0;
        rating.draws = 0;
    }
}

double EloCalculator::calculateExpectedScore(double rating_a,
                                             double rating_b) const
{
    return 1.0 / (1.0 + std::pow(10.0, (rating_b - rating_a) / 400.0));
}

double EloCalculator::calculateNewRating(double old_rating,
                                         double expected_score,
                                         double actual_score) const
{
    return old_rating + k_factor_ * (actual_score - expected_score);
}

} // namespace fastmill
