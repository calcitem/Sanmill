#include <iostream>

void test_game_allocation(int totalGames) {
    std::cout << "\n=== Testing totalGames = " << totalGames << " ===\n";
    
    const bool globalInfiniteMode = (totalGames == 0);
    const int gamesForWhite = globalInfiniteMode ? 0 : (totalGames + 1) / 2;  // Ceiling division
    const int gamesForBlack = globalInfiniteMode ? 0 : totalGames / 2;        // Floor division
    
    std::cout << "Global infinite mode: " << (globalInfiniteMode ? "YES" : "NO") << std::endl;
    std::cout << "Games for White (Thread A): " << gamesForWhite << std::endl;
    std::cout << "Games for Black (Thread B): " << gamesForBlack << std::endl;
    std::cout << "Sum: " << (gamesForWhite + gamesForBlack) << std::endl;
    
    // Test thread behavior
    for (int threadGames : {gamesForWhite, gamesForBlack}) {
        const bool threadInfiniteMode = globalInfiniteMode && (threadGames == 0);
        const bool shouldExitImmediately = (threadGames == 0) && !globalInfiniteMode;
        
        std::cout << "  Thread with " << threadGames << " games: ";
        if (shouldExitImmediately) {
            std::cout << "EXIT IMMEDIATELY (0 games in finite mode)" << std::endl;
        } else if (threadInfiniteMode) {
            std::cout << "INFINITE MODE (global infinite + 0 allocation)" << std::endl;
        } else {
            std::cout << "FINITE MODE (" << threadGames << " games)" << std::endl;
        }
    }
}

int main() {
    std::cout << "Testing game allocation and thread behavior logic:\n";
    test_game_allocation(0);   // Global infinite mode
    test_game_allocation(1);   // Odd - White gets 1, Black gets 0
    test_game_allocation(2);   // Even - Both get 1
    test_game_allocation(3);   // Odd - White gets 2, Black gets 1
    test_game_allocation(4);   // Even - Both get 2
    test_game_allocation(5);   // Odd - White gets 3, Black gets 2
    return 0;
}
