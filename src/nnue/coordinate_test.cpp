// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// coordinate_test.cpp - Test coordinate conversion between engine and perfect DB

#include "types.h"
#include "perfect/perfect_adaptor.h"
#include <iostream>

int main() {
    std::cout << "Testing coordinate conversion between engine and perfect database:\n" << std::endl;
    
    std::cout << "Engine Square -> Perfect DB Index -> Back to Engine Square:" << std::endl;
    std::cout << "------------------------------------------------------------" << std::endl;
    
    // Test all valid engine squares
    for (Square sq = SQ_BEGIN; sq < SQ_END; ++sq) {
        int perfect_idx = to_perfect_square(sq);
        if (perfect_idx != -1) {
            Square back_to_engine = from_perfect_square(perfect_idx);
            bool conversion_ok = (back_to_engine == sq);
            
            std::cout << "SQ_" << sq << " -> " << perfect_idx << " -> SQ_" << back_to_engine;
            if (conversion_ok) {
                std::cout << " ✓" << std::endl;
            } else {
                std::cout << " ✗ ERROR!" << std::endl;
            }
        } else {
            std::cout << "SQ_" << sq << " -> invalid (not a board square)" << std::endl;
        }
    }
    
    std::cout << "\nPerfect DB Index -> Engine Square -> Back to Perfect DB:" << std::endl;
    std::cout << "--------------------------------------------------------" << std::endl;
    
    // Test all perfect database indices
    for (int perfect_idx = 0; perfect_idx < 24; ++perfect_idx) {
        Square engine_sq = from_perfect_square(perfect_idx);
        int back_to_perfect = to_perfect_square(engine_sq);
        bool conversion_ok = (back_to_perfect == perfect_idx);
        
        std::cout << perfect_idx << " -> SQ_" << engine_sq << " -> " << back_to_perfect;
        if (conversion_ok) {
            std::cout << " ✓" << std::endl;
        } else {
            std::cout << " ✗ ERROR!" << std::endl;
        }
    }
    
    std::cout << "\nCoordinate conversion test completed." << std::endl;
    return 0;
}
