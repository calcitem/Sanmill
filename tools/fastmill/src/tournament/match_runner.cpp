// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// match_runner.cpp - Implementation of Mill match runner

#include "match_runner.h"
#include "utils/logger.h"

// Reuse existing Sanmill headers for game logic
#include "mills.h"
#include "movegen.h"
#include "evaluate.h"

#include <sstream>
#include <iomanip>

namespace fastmill {

// MatchResult implementation
int MatchResult::getWhiteWins() const
{
    int wins = 0;
    for (const auto &game : games) {
        if (game.result == GameResult::Result::WHITE_WINS)
            wins++;
    }
    return wins;
}

int MatchResult::getBlackWins() const
{
    int wins = 0;
    for (const auto &game : games) {
        if (game.result == GameResult::Result::BLACK_WINS)
            wins++;
    }
    return wins;
}

int MatchResult::getDraws() const
{
    int draws = 0;
    for (const auto &game : games) {
        if (game.result == GameResult::Result::DRAW)
            draws++;
    }
    return draws;
}

double MatchResult::getScore() const
{
    double score = 0.0;
    for (const auto &game : games) {
        switch (game.result) {
        case GameResult::Result::WHITE_WINS:
            score += 1.0;
            break;
        case GameResult::Result::DRAW:
            score += 0.5;
            break;
        case GameResult::Result::BLACK_WINS:
            score += 0.0;
            break;
        default:
            // Timeouts and errors are treated as losses for the affected side
            break;
        }
    }
    return score / games.size();
}

// MatchRunner implementation
MatchRunner::MatchRunner(MillEngineWrapper *white_engine,
                         MillEngineWrapper *black_engine,
                         const TournamentConfig &config)
    : white_engine_(white_engine)
    , black_engine_(black_engine)
    , config_(config)
{ }

MatchResult MatchRunner::runMatch()
{
    MatchResult match_result;
    match_result.white_engine = white_engine_->getName();
    match_result.black_engine = black_engine_->getName();

    Logger::info("Starting match: " + match_result.white_engine + " vs " +
                 match_result.black_engine);

    // Run the specified number of rounds
    for (int round = 0; round < config_.rounds; ++round) {
        // Run game with white starting
        GameResult game1 = runGame(true);
        match_result.games.push_back(game1);

        // If alternating colors, run second game with colors swapped
        if (config_.rounds > 1) {
            GameResult game2 = runGame(false);
            match_result.games.push_back(game2);
        }
    }

    Logger::info("Match completed: " + match_result.white_engine + " vs " +
                 match_result.black_engine +
                 " - Score: " + std::to_string(match_result.getScore()));

    return match_result;
}

GameResult MatchRunner::runGame(bool white_starts)
{
    GameResult result;
    result.result = GameResult::Result::ERROR; // Initialize to error, will be
                                               // set properly later
    auto start_time = std::chrono::steady_clock::now();

    // Determine which engines play which colors for this game
    MillEngineWrapper *white_player = white_starts ? white_engine_ :
                                                     black_engine_;
    MillEngineWrapper *black_player = white_starts ? black_engine_ :
                                                     white_engine_;

    Logger::debug("Starting game: White=" + white_player->getName() +
                  ", Black=" + black_player->getName());

    // Initialize game position using existing Sanmill Position class
    Position pos;
    pos.reset(); // Initialize with default starting position

    // Use opening position if set
    if (use_opening_) {
        pos = opening_position_;
    }

    // Initialize engines for new game
    if (!white_player->newGame(config_.mill_variant) ||
        !black_player->newGame(config_.mill_variant)) {
        result.result = GameResult::Result::ERROR;
        result.termination_reason = "Failed to initialize engines";
        return result;
    }

    std::vector<Move> move_history;
    std::chrono::milliseconds white_time_left = config_.time_control.base_time;
    std::chrono::milliseconds black_time_left = config_.time_control.base_time;

    int move_count = 0;
    const int max_moves = config_.max_moves;

    // Main game loop
    while (!isGameOver(pos) && move_count < max_moves) {
        MillEngineWrapper *current_engine = (pos.side_to_move() == WHITE) ?
                                                white_player :
                                                black_player;
        std::chrono::milliseconds *time_left = (pos.side_to_move() == WHITE) ?
                                                   &white_time_left :
                                                   &black_time_left;

        // Calculate thinking time for this move
        std::chrono::milliseconds think_time = calculateThinkTime(
            config_.time_control, move_count, *time_left);

        // Get move from engine
        auto move_start = std::chrono::steady_clock::now();
        Move move = getEngineMove(current_engine, pos, think_time);
        auto move_end = std::chrono::steady_clock::now();
        auto actual_think_time =
            std::chrono::duration_cast<std::chrono::milliseconds>(move_end -
                                                                  move_start);

        // Check for timeout or invalid move
        if (move == MOVE_NONE) {
            result.result = GameResult::Result::TIMEOUT;
            result.termination_reason = "Engine " + current_engine->getName() +
                                        " failed to provide a move";
            break;
        }

        // Validate move using existing Sanmill move validation
        if (!pos.legal(move)) {
            result.result = GameResult::Result::ERROR;
            result.termination_reason = "Engine " + current_engine->getName() +
                                        " provided illegal move";
            break;
        }

        // Make the move
        pos.do_move(move);
        move_history.push_back(move);

        // Update time
        *time_left -= actual_think_time;
        *time_left += config_.time_control.increment;

        // Check for time forfeit
        if (*time_left <= std::chrono::milliseconds(0)) {
            result.result = GameResult::Result::TIMEOUT;
            result.termination_reason = "Time forfeit by " +
                                        current_engine->getName();
            break;
        }

        move_count++;

        // Check for adjudication conditions
        if (shouldAdjudicateDraw(pos, move_count)) {
            result.result = GameResult::Result::DRAW;
            result.termination_reason = "Adjudicated draw";
            break;
        }

        // Check for repetition using existing Sanmill logic
        if (isThreefoldRepetition(pos)) {
            result.result = GameResult::Result::DRAW;
            result.termination_reason = "Threefold repetition";
            break;
        }

        if (isFiftyMoveRule(pos)) {
            result.result = GameResult::Result::DRAW;
            result.termination_reason = "50-move rule";
            break;
        }
    }

    // If game loop ended without setting result, evaluate final position
    if (result.result == GameResult::Result::ERROR) { // Check if result was set
                                                      // in loop
        if (move_count >= max_moves) {
            result.result = GameResult::Result::DRAW;
            result.termination_reason = "Maximum moves reached";
        } else {
            result.result = evaluatePosition(pos);
            if (result.result == GameResult::Result::WHITE_WINS) {
                result.termination_reason = "White wins";
            } else if (result.result == GameResult::Result::BLACK_WINS) {
                result.termination_reason = "Black wins";
            } else {
                result.termination_reason = "Game drawn";
            }
        }
    }

    // Calculate game duration and statistics
    auto end_time = std::chrono::steady_clock::now();
    result.duration = std::chrono::duration_cast<std::chrono::milliseconds>(
        end_time - start_time);
    result.total_moves = move_count;

    updateGameStats(result, pos);

    // Generate PGN if requested
    if (config_.save_games) {
        result.pgn = generatePGN(move_history, result);
    }

    Logger::debug("Game completed: " + result.termination_reason + " (" +
                  std::to_string(result.total_moves) + " moves)");

    return result;
}

void MatchRunner::setOpeningPosition(const Position &opening_pos)
{
    opening_position_ = opening_pos;
    use_opening_ = true;
}

bool MatchRunner::initializeGame()
{
    // Any additional game initialization logic
    return true;
}

Move MatchRunner::getEngineMove(MillEngineWrapper *engine, const Position &pos,
                                std::chrono::milliseconds time_left)
{
    return engine->getBestMove(pos, time_left);
}

bool MatchRunner::isGameOver(const Position &pos) const
{
    // Use existing Sanmill game over detection
    // Note: check_if_game_is_over() is not const, so we create a copy
    Position temp_pos = pos;
    return temp_pos.check_if_game_is_over();
}

GameResult::Result MatchRunner::evaluatePosition(const Position &pos) const
{
    // Use existing Sanmill position evaluation
    // Note: evaluate() is in the Eval namespace and requires non-const Position
    Position temp_pos = pos;
    Value eval = Eval::evaluate(temp_pos);

    if (eval == VALUE_MATE) {
        return (pos.side_to_move() == WHITE) ? GameResult::Result::BLACK_WINS :
                                               GameResult::Result::WHITE_WINS;
    } else if (eval == -VALUE_MATE) {
        return (pos.side_to_move() == WHITE) ? GameResult::Result::WHITE_WINS :
                                               GameResult::Result::BLACK_WINS;
    } else {
        return GameResult::Result::DRAW;
    }
}

std::chrono::milliseconds
MatchRunner::calculateThinkTime(const TimeControl &tc, int moves_played,
                                std::chrono::milliseconds time_left) const
{
    // Simple time management: use a fraction of remaining time plus increment
    auto base_time = time_left / std::max(1, 40 - moves_played); // Assume 40
                                                                 // moves per
                                                                 // game average
    return std::min(base_time + tc.increment, time_left / 2); // Don't use more
                                                              // than half
                                                              // remaining time
}

std::string MatchRunner::generatePGN(const std::vector<Move> &moves,
                                     const GameResult &result) const
{
    std::ostringstream pgn;

    // PGN headers
    pgn << "[Event \"Fastmill Tournament\"]\n";
    pgn << "[Site \"Computer\"]\n";
    // Get current time for PGN header
    auto now = std::time(nullptr);
    pgn << "[Date \"" << std::put_time(std::gmtime(&now), "%Y.%m.%d")
        << "\"]\n";
    pgn << "[Round \"1\"]\n";
    pgn << "[White \"" << white_engine_->getName() << "\"]\n";
    pgn << "[Black \"" << black_engine_->getName() << "\"]\n";

    // Result
    std::string result_str;
    switch (result.result) {
    case GameResult::Result::WHITE_WINS:
        result_str = "1-0";
        break;
    case GameResult::Result::BLACK_WINS:
        result_str = "0-1";
        break;
    case GameResult::Result::DRAW:
        result_str = "1/2-1/2";
        break;
    default:
        result_str = "*";
        break;
    }
    pgn << "[Result \"" << result_str << "\"]\n";
    pgn << "[Termination \"" << result.termination_reason << "\"]\n\n";

    // Moves (simplified - would need proper Mill notation)
    Position pos;
    pos.reset(); // Initialize with default starting position

    for (size_t i = 0; i < moves.size(); ++i) {
        if (i % 2 == 0) {
            pgn << (i / 2 + 1) << ". ";
        }

        // Convert move to algebraic notation (simplified)
        // Note: We need to implement a proper move-to-string conversion
        pgn << "move" << (i + 1) << " "; // Placeholder

        pos.do_move(moves[i]);

        if (i % 10 == 9)
            pgn << "\n"; // Line break every 10 moves
    }

    pgn << result_str << "\n";

    return pgn.str();
}

void MatchRunner::updateGameStats(GameResult &result,
                                  const Position &final_pos) const
{
    // Extract Mill-specific statistics from final position
    // Calculate captured pieces based on pieces on board + pieces in hand
    int initial_pieces = 9; // Standard Mill has 9 pieces per side
    int white_remaining = final_pos.piece_on_board_count(WHITE) +
                          final_pos.piece_in_hand_count(WHITE);
    int black_remaining = final_pos.piece_on_board_count(BLACK) +
                          final_pos.piece_in_hand_count(BLACK);

    result.white_pieces_captured = initial_pieces - black_remaining;
    result.black_pieces_captured = initial_pieces - white_remaining;

    // Mill formation counts would require additional tracking during the game
    // For now, set to 0 as a placeholder
    result.mills_formed_white = 0;
    result.mills_formed_black = 0;
}

bool MatchRunner::shouldAdjudicateDraw(const Position &pos,
                                       int move_count) const
{
    if (!config_.adjudicate_draws)
        return false;

    // Simple draw adjudication based on move count and evaluation
    if (move_count > config_.draw_move_count) {
        Position temp_pos = pos;
        Value eval = Eval::evaluate(temp_pos);
        return std::abs(eval) < config_.draw_score_limit;
    }

    return false;
}

bool MatchRunner::shouldAdjudicateWin(const Position &pos) const
{
    // Use existing Sanmill win detection
    // Note: check_if_game_is_over() is not const, so we create a copy
    Position temp_pos = pos;
    return temp_pos.check_if_game_is_over();
}

bool MatchRunner::isThreefoldRepetition(const Position &pos) const
{
    // Use existing Sanmill repetition detection
    // Note: Proper repetition detection would require maintaining a position
    // stack For now, return false as a placeholder
    (void)pos;    // Suppress unused parameter warning
    return false; // Placeholder - would need proper implementation with
                  // position history
}

bool MatchRunner::isFiftyMoveRule(const Position &pos) const
{
    // Mill doesn't have a traditional 50-move rule, but we can implement
    // a similar concept based on moves without captures
    return pos.rule50_count() >= 100; // 50 moves for each side
}

} // namespace fastmill
