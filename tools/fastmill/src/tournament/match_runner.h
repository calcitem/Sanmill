// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// match_runner.h - Runs individual Mill matches between engines

#pragma once

#include <memory>
#include <chrono>

// Reuse existing Sanmill headers
#include "types.h"
#include "position.h"
#include "rule.h"

// Fastmill headers
#include "tournament/tournament_types.h"
#include "engine/mill_engine_wrapper.h"

namespace fastmill {

// Result of a single game
struct GameResult
{
    enum class Result { WHITE_WINS, BLACK_WINS, DRAW, TIMEOUT, ERROR } result;
    int total_moves {0};
    std::chrono::milliseconds duration {0};
    std::string termination_reason;
    std::string pgn; // Game in PGN format if requested

    // Mill-specific statistics
    int white_pieces_captured {0};
    int black_pieces_captured {0};
    int mills_formed_white {0};
    int mills_formed_black {0};
};

// Result of a match (potentially multiple games)
struct MatchResult
{
    std::string white_engine;
    std::string black_engine;
    std::vector<GameResult> games;

    int getWhiteWins() const;
    int getBlackWins() const;
    int getDraws() const;
    double getScore() const; // From white's perspective (0.5 for draw, 1.0 for
                             // win)
};

// Manages and runs a single match between two engines
class MatchRunner
{
public:
    MatchRunner(MillEngineWrapper *white_engine,
                MillEngineWrapper *black_engine,
                const TournamentConfig &config);

    // Run a complete match (potentially multiple games with color alternation)
    MatchResult runMatch();

    // Run a single game
    GameResult runGame(bool white_starts = true);

    // Set opening position (optional)
    void setOpeningPosition(const Position &opening_pos);

private:
    MillEngineWrapper *white_engine_;
    MillEngineWrapper *black_engine_;
    TournamentConfig config_;
    Position opening_position_;
    bool use_opening_ {false};

    // Game management
    bool initializeGame();
    Move getEngineMove(MillEngineWrapper *engine, const Position &pos,
                       std::chrono::milliseconds time_left);

    // Game state evaluation using existing Sanmill logic
    bool isGameOver(const Position &pos) const;
    GameResult::Result evaluatePosition(const Position &pos) const;

    // Time management
    std::chrono::milliseconds
    calculateThinkTime(const TimeControl &tc, int moves_played,
                       std::chrono::milliseconds time_left) const;

    // PGN generation
    std::string generatePGN(const std::vector<Move> &moves,
                            const GameResult &result) const;

    // Statistics collection
    void updateGameStats(GameResult &result, const Position &final_pos) const;

    // Adjudication
    bool shouldAdjudicateDraw(const Position &pos, int move_count) const;
    bool shouldAdjudicateWin(const Position &pos) const;

    // Repetition detection using existing Sanmill infrastructure
    bool isThreefoldRepetition(const Position &pos) const;
    bool isFiftyMoveRule(const Position &pos) const;
};

} // namespace fastmill
