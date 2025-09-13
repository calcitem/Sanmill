// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// sanmill_adapter.cpp - Implementation of Sanmill adapter layer

#include "sanmill_adapter.h"
#include "utils/logger.h"

// Additional Sanmill includes needed for initialization
#include "evaluate.h"
#include "movegen.h"
#include "movepick.h"
#include "engine_commands.h"

namespace fastmill {

// Static member definitions
bool SanmillAdapter::initialized_ = false;
SearchEngine SanmillAdapter::search_engine_;

bool SanmillAdapter::initialize() {
    if (initialized_) {
        return true;
    }
    
    try {
        Logger::debug("Initializing Sanmill core components...");
        
        // Initialize Position static components
        Position::init();
        
        // Initialize Mills components
        Mills::adjacent_squares_init();
        Mills::mill_table_init();
        
        // Initialize UCI options
        initializeOptions();
        
        // Initialize game tables
        initializeGameTables();
        
        // Initialize engine commands
        EngineCommands::init_start_fen();
        
        initialized_ = true;
        Logger::info("Sanmill core components initialized successfully");
        return true;
        
    } catch (const std::exception& e) {
        Logger::error("Failed to initialize Sanmill components: " + std::string(e.what()));
        return false;
    }
}

void SanmillAdapter::cleanup() {
    if (initialized_) {
        Logger::debug("Cleaning up Sanmill components");
        initialized_ = false;
    }
}

Position SanmillAdapter::createPosition() {
    Position pos;
    pos.reset();
    return pos;
}

Position SanmillAdapter::createPosition(const Rule& rule) {
    Position pos;
    pos.reset();
    // Note: Setting rule would require modifying Position class
    // For now, use default rule
    (void)rule; // Suppress unused parameter warning
    return pos;
}

std::string SanmillAdapter::moveToString(Move move, const Position& /* pos */) {
    // Use UCI move formatting
    return UCI::move(move);
}

Move SanmillAdapter::stringToMove(const std::string& move_str, Position& pos) {
    // Use UCI move parsing
    return UCI::to_move(&pos, move_str);
}

bool SanmillAdapter::isGameOver(Position& pos) {
    return pos.check_if_game_is_over();
}

Value SanmillAdapter::evaluatePosition(Position& pos) {
    return Eval::evaluate(pos);
}

std::vector<Move> SanmillAdapter::generateLegalMoves(Position& pos) {
    std::vector<Move> moves;
    
    // Use MovePicker to generate legal moves
    MovePicker mp(pos, MOVE_NONE);
    mp.next_move<LEGAL>();
    
    for (int i = 0; i < mp.move_count(); ++i) {
        moves.push_back(mp.moves[i].move);
    }
    
    return moves;
}

bool SanmillAdapter::isLegalMove(const Position& pos, Move move) {
    return pos.legal(move);
}

std::string SanmillAdapter::getGameResult(Position& pos) {
    if (!isGameOver(pos)) {
        return "*"; // Game ongoing
    }
    
    Color winner = pos.get_winner();
    if (winner == WHITE) {
        return "1-0";
    } else if (winner == BLACK) {
        return "0-1";
    } else {
        return "1/2-1/2"; // Draw
    }
}

void SanmillAdapter::initializeOptions() {
    // Initialize UCI options if not already done
    UCI::init(Options);
}

void SanmillAdapter::initializeGameTables() {
    // Initialize any additional game tables if needed
    Position::create_mill_table();
}

// SafePosition implementation
SafePosition::SafePosition() : initialized_(false) {
    if (SanmillAdapter::initialize()) {
        pos_.reset();
        initialized_ = true;
    }
}

SafePosition::SafePosition(const Rule& rule) : initialized_(false) {
    if (SanmillAdapter::initialize()) {
        pos_.reset();
        // Note: Setting rule would require Position class modification
        (void)rule; // Suppress unused parameter warning
        initialized_ = true;
    }
}

bool SafePosition::makeMove(Move move) {
    if (!initialized_ || !SanmillAdapter::isLegalMove(pos_, move)) {
        return false;
    }
    
    pos_.do_move(move);
    return true;
}

bool SafePosition::isGameOver() {
    if (!initialized_) return true;
    return SanmillAdapter::isGameOver(pos_);
}

Value SafePosition::evaluate() {
    if (!initialized_) return VALUE_ZERO;
    return SanmillAdapter::evaluatePosition(pos_);
}

std::vector<Move> SafePosition::getLegalMoves() {
    if (!initialized_) return {};
    return SanmillAdapter::generateLegalMoves(pos_);
}

std::string SafePosition::toFEN() const {
    if (!initialized_) return "";
    return pos_.fen();
}

bool SafePosition::fromFEN(const std::string& fen) {
    if (!initialized_) return false;
    
    try {
        pos_.set(fen);
        return true;
    } catch (...) {
        return false;
    }
}

Color SafePosition::sideToMove() const {
    return pos_.side_to_move();
}

int SafePosition::getPieceCount(Color color) const {
    return getPiecesOnBoard(color) + getPiecesInHand(color);
}

int SafePosition::getPiecesOnBoard(Color color) const {
    return pos_.piece_on_board_count(color);
}

int SafePosition::getPiecesInHand(Color color) const {
    return pos_.piece_in_hand_count(color);
}

} // namespace fastmill
