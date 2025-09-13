// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// sanmill_adapter.h - Adapter layer to bridge Fastmill with Sanmill core

#pragma once

// Include necessary Sanmill headers
#include "types.h"
#include "position.h"
#include "uci.h"
#include "rule.h"
#include "mills.h"
#include "option.h"
#include "search_engine.h"

namespace fastmill {

// Adapter class to provide necessary Sanmill functionality for Fastmill
class SanmillAdapter {
public:
    // Initialize Sanmill core components
    static bool initialize();
    
    // Cleanup Sanmill resources
    static void cleanup();
    
    // Create a properly initialized Position
    static Position createPosition();
    
    // Create a properly initialized Position with specific rule
    static Position createPosition(const Rule& rule);
    
    // Convert move to UCI string format
    static std::string moveToString(Move move, const Position& pos);
    
    // Convert UCI string to move
    static Move stringToMove(const std::string& move_str, Position& pos);
    
    // Check if position represents game over
    static bool isGameOver(Position& pos);
    
    // Get position evaluation
    static Value evaluatePosition(Position& pos);
    
    // Generate legal moves for position
    static std::vector<Move> generateLegalMoves(Position& pos);
    
    // Validate if a move is legal
    static bool isLegalMove(const Position& pos, Move move);
    
    // Get game result from position
    static std::string getGameResult(Position& pos);
    
private:
    static bool initialized_;
    static SearchEngine search_engine_;
    
    // Initialize UCI options if needed
    static void initializeOptions();
    
    // Initialize game rules and tables
    static void initializeGameTables();
};

// Helper class to manage Position lifecycle safely
class SafePosition {
public:
    SafePosition();
    explicit SafePosition(const Rule& rule);
    ~SafePosition() = default;
    
    // Get the underlying Position object
    Position& get() { return pos_; }
    const Position& get() const { return pos_; }
    
    // Position operations
    bool makeMove(Move move);
    bool isGameOver();
    Value evaluate();
    std::vector<Move> getLegalMoves();
    std::string toFEN() const;
    bool fromFEN(const std::string& fen);
    
    // Game state queries
    Color sideToMove() const;
    int getPieceCount(Color color) const;
    int getPiecesOnBoard(Color color) const;
    int getPiecesInHand(Color color) const;
    
private:
    Position pos_;
    bool initialized_;
};

} // namespace fastmill
