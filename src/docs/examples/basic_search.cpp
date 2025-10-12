/// @file basic_search.cpp
/// @brief Basic search example demonstrating engine usage
///
/// This example shows how to:
/// 1. Initialize a position
/// 2. Set up a search engine
/// 3. Execute a search
/// 4. Retrieve and use the best move

#include "position.h"
#include "search_engine.h"
#include "search.h"
#include "option.h"
#include "uci.h"
#include <iostream>

int main() {
    // Initialize search module (one-time setup)
    Search::init();
    
    // Create and initialize position
    Position pos;
    pos.set("********/********/********_w_0_0");  // Initial position FEN
    pos.start();  // Start the game
    
    std::cout << "Initial position set" << std::endl;
    std::cout << "FEN: " << pos.fen() << std::endl;
    
    // Create search engine
    SearchEngine engine;
    engine.setRootPosition(&pos);
    
    // Configure search
    gameOptions.setAlgorithm(1);  // Alpha-Beta
    gameOptions.setDepth(6);      // Search 6 plies deep
    gameOptions.setSkillLevel(5); // Medium skill
    
    std::cout << "\nSearching (depth 6)..." << std::endl;
    
    // Execute search
    engine.runSearch();
    
    // Get results
    Move bestMove = engine.getBestMove();
    Value evaluation = engine.getBestValue();
    
    // Display results
    std::cout << "Search complete!" << std::endl;
    std::cout << "Best move: " << UCI::move(bestMove) << std::endl;
    std::cout << "Evaluation: " << evaluation << " centipawns" << std::endl;
    
    // Apply the move
    if (bestMove != MOVE_NONE && pos.legal(bestMove)) {
        pos.do_move(bestMove);
        std::cout << "\nMove applied. New position:" << std::endl;
        std::cout << "FEN: " << pos.fen() << std::endl;
    } else {
        std::cerr << "Error: Invalid move!" << std::endl;
        return 1;
    }
    
    return 0;
}

// Compile: g++ -o basic_search basic_search.cpp position.o search_engine.o search.o option.o uci.o bitboard.o evaluate.o tt.o movegen.o rule.o mills.o misc.o -I../..
// Run: ./basic_search

