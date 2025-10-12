/// @file position_manipulation.cpp
/// @brief Position manipulation example
///
/// Demonstrates:
/// 1. Creating and setting up positions
/// 2. Making and undoing moves
/// 3. Querying position state
/// 4. Mill detection
/// 5. FEN import/export

#include "position.h"
#include "movegen.h"
#include "uci.h"
#include <iostream>
#include <cassert>

void printPosition(const Position &pos) {
    std::cout << "FEN: " << pos.fen() << std::endl;
    std::cout << "Side to move: " << (pos.side_to_move() == WHITE ? "White" : "Black") << std::endl;
    std::cout << "Phase: ";
    switch (pos.get_phase()) {
        case Phase::ready: std::cout << "Ready"; break;
        case Phase::placing: std::cout << "Placing"; break;
        case Phase::moving: std::cout << "Moving"; break;
        case Phase::gameOver: std::cout << "Game Over"; break;
        default: std::cout << "Unknown"; break;
    }
    std::cout << std::endl;
    std::cout << "Ply: " << pos.game_ply() << std::endl;
    std::cout << std::endl;
}

int main() {
    std::cout << "=== Position Manipulation Example ===" << std::endl << std::endl;
    
    // 1. Create initial position
    std::cout << "1. Creating initial position..." << std::endl;
    Position pos;
    pos.set("********/********/********_w_0_0");
    pos.start();
    printPosition(pos);
    
    // 2. Generate legal moves
    std::cout << "2. Generating legal moves..." << std::endl;
    // Note: In real code, use proper move generation
    // For simplicity, we'll manually create a move
    
    // 3. Make a move (place piece at a1)
    std::cout << "3. Making move: place at a1" << std::endl;
    // Create move manually (in real code, use move generation)
    Move move = /* create move to a1 */;
    
    Sanmill::Stack<Position> history;
    history.push(pos);  // Save position for undo
    
    // Verify move is legal
    if (pos.legal(move)) {
        pos.do_move(move);
        std::cout << "Move applied successfully" << std::endl;
        printPosition(pos);
    } else {
        std::cout << "Move is illegal!" << std::endl;
    }
    
    // 4. Undo move
    std::cout << "4. Undoing move..." << std::endl;
    pos.undo_move(history);
    std::cout << "Position restored" << std::endl;
    printPosition(pos);
    
    // 5. Set up custom position
    std::cout << "5. Setting up custom position..." << std::endl;
    pos.set("***OO***/********/O*******_b_0_5");
    std::cout << "Custom position set" << std::endl;
    printPosition(pos);
    
    // 6. Query position properties
    std::cout << "6. Querying position properties..." << std::endl;
    std::cout << "White pieces on board: " << pos.count<ON_BOARD>(WHITE) << std::endl;
    std::cout << "Black pieces on board: " << pos.count<ON_BOARD>(BLACK) << std::endl;
    std::cout << "White pieces in hand: " << pos.count<IN_HAND>(WHITE) << std::endl;
    std::cout << "Black pieces in hand: " << pos.count<IN_HAND>(BLACK) << std::endl;
    std::cout << std::endl;
    
    // 7. Check specific squares
    std::cout << "7. Checking specific squares..." << std::endl;
    std::cout << "Square a1: " << (pos.empty(SQ_A1) ? "Empty" : "Occupied") << std::endl;
    if (!pos.empty(SQ_A1)) {
        std::cout << "  Color: " << (pos.color_on(SQ_A1) == WHITE ? "White" : "Black") << std::endl;
    }
    std::cout << std::endl;
    
    // 8. Mill detection
    std::cout << "8. Mill detection..." << std::endl;
    // Set up position with a mill
    pos.set("***O****/********/O*******_w_0_5");
    for (Square sq = SQ_A1; sq < SQ_NB; ++sq) {
        int mills = pos.mills_count(sq);
        if (mills > 0) {
            std::cout << "Square " << UCI::square(sq) << " is in " << mills << " mill(s)" << std::endl;
        }
    }
    std::cout << std::endl;
    
    // 9. Check if all pieces in mills
    std::cout << "9. Checking mill protection..." << std::endl;
    std::cout << "All white pieces in mills: " << (pos.is_all_in_mills(WHITE) ? "Yes" : "No") << std::endl;
    std::cout << "All black pieces in mills: " << (pos.is_all_in_mills(BLACK) ? "Yes" : "No") << std::endl;
    std::cout << std::endl;
    
    // 10. Hash key
    std::cout << "10. Position hash key..." << std::endl;
    std::cout << "Hash: 0x" << std::hex << pos.key() << std::dec << std::endl;
    std::cout << std::endl;
    
    std::cout << "=== Example Complete ===" << std::endl;
    
    return 0;
}

// Compile: g++ -o position_manipulation position_manipulation.cpp position.o bitboard.o rule.o mills.o movegen.o uci.o misc.o -I../..
// Run: ./position_manipulation

