// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// evaluate.cpp

#include "evaluate.h"
#include "bitboard.h"
#include "option.h"
#include "thread.h"
#include "position.h"
#include "perfect_api.h"
#include "nnue/evaluate_nnue.h"
#include "nnue/nnue_common.h"
#include <iostream>
#include <fstream>
#include <algorithm>
#include <iomanip>

namespace Eval {

// NNUE evaluation settings
bool useNNUE = false;
std::string evalFile = "";

// Normalize file path separators for the current platform
std::string normalizePath(const std::string& path)
{
    std::string normalized = path;
    
#ifdef _WIN32
    // On Windows, replace forward slashes with backslashes
    std::replace(normalized.begin(), normalized.end(), '/', '\\');
#else
    // On Unix-like systems, replace backslashes with forward slashes
    std::replace(normalized.begin(), normalized.end(), '\\', '/');
#endif
    
    return normalized;
}

// Utility function to read little-endian uint32 from stream
std::uint32_t readLittleEndianUint32(std::istream& stream)
{
    std::uint32_t value = 0;
    char bytes[4];
    stream.read(bytes, 4);
    if (stream.gcount() == 4) {
        value = static_cast<std::uint32_t>(static_cast<unsigned char>(bytes[0])) |
                (static_cast<std::uint32_t>(static_cast<unsigned char>(bytes[1])) << 8) |
                (static_cast<std::uint32_t>(static_cast<unsigned char>(bytes[2])) << 16) |
                (static_cast<std::uint32_t>(static_cast<unsigned char>(bytes[3])) << 24);
    }
    return value;
}

// Check NNUE file header information
bool checkNNUEFileHeader(const std::string& filePath)
{
    std::ifstream stream(filePath, std::ios::binary);
    if (!stream.is_open()) {
        sync_cout << "info string ERROR: Cannot open file for header check: " << filePath << sync_endl;
        return false;
    }
    
    // Read version
    std::uint32_t fileVersion = readLittleEndianUint32(stream);
    sync_cout << "info string NNUE file version: 0x" << std::hex << fileVersion << std::dec << sync_endl;
    
    // Expected version from nnue_common.h
    const std::uint32_t expectedVersion = 0x7AF32F20u;
    sync_cout << "info string Expected version: 0x" << std::hex << expectedVersion << std::dec << sync_endl;
    
    if (fileVersion != expectedVersion) {
        sync_cout << "info string WARNING: Version mismatch! File version: 0x" << std::hex << fileVersion 
                  << ", Expected: 0x" << expectedVersion << std::dec << sync_endl;
    }
    
    // Read hash value
    std::uint32_t hashValue = readLittleEndianUint32(stream);
    sync_cout << "info string NNUE file hash value: 0x" << std::hex << hashValue << std::dec << sync_endl;
    
    // Read description size
    std::uint32_t descSize = readLittleEndianUint32(stream);
    sync_cout << "info string NNUE description size: " << descSize << " bytes" << sync_endl;
    
    if (descSize > 0 && descSize < 1000) { // Reasonable size check
        std::string description(descSize, '\0');
        stream.read(&description[0], descSize);
        if (stream.gcount() == static_cast<std::streamsize>(descSize)) {
            sync_cout << "info string NNUE description: " << description << sync_endl;
        }
    }
    
    return stream.good();
}

void init_nnue()
{
    if (!evalFile.empty()) {
        // Normalize the file path to use correct separators for the current platform
        std::string normalizedPath = normalizePath(evalFile);
        
        std::ifstream stream(normalizedPath, std::ios::binary);
        
        // Log both original and normalized paths for debugging
        sync_cout << "info string Original NNUE model path: " << evalFile << sync_endl;
        sync_cout << "info string Normalized NNUE model path: " << normalizedPath << sync_endl;
        sync_cout << "info string Attempting to load NNUE model from: " << normalizedPath << sync_endl;
        
        // Check if file can be opened
        if (!stream.is_open()) {
            sync_cout << "info string ERROR: Failed to open NNUE model file: " << normalizedPath << sync_endl;
            assert(false && "Failed to open NNUE model file");
            return;
        }
        
        // Check file size
        stream.seekg(0, std::ios::end);
        std::streampos fileSize = stream.tellg();
        stream.seekg(0, std::ios::beg);
        sync_cout << "info string NNUE model file size: " << fileSize << " bytes" << sync_endl;
        
        if (fileSize == 0) {
            sync_cout << "info string ERROR: NNUE model file is empty" << sync_endl;
            assert(false && "NNUE model file is empty");
            return;
        }
        
        // Check file header information
        sync_cout << "info string Checking NNUE file header..." << sync_endl;
        checkNNUEFileHeader(normalizedPath);
        
        // Try to load the model
        bool loadResult = Stockfish::Eval::NNUE::load_eval(normalizedPath, stream);
        if (!loadResult) {
            sync_cout << "info string ERROR: Failed to load NNUE model - invalid format or corrupted file" << sync_endl;
            assert(false && "Failed to load NNUE model");
            return;
        }
        
        sync_cout << "info string NNUE model successfully loaded from " << normalizedPath << sync_endl;
    }
}

} // namespace Eval

namespace {

class Evaluation
{
public:
    Evaluation() = delete;

    explicit Evaluation(Position &p) noexcept
        : pos(p)
    { }

    Evaluation &operator=(const Evaluation &) = delete;
    Value value() const;

private:
    Position &pos;
};

// Evaluation::value() is the main function of the class. It computes the
// various parts of the evaluation and returns the value of the position from
// the point of view of the side to move.

Value Evaluation::value() const
{
    Value value = VALUE_ZERO;

    int pieceInHandDiffCount;
    int pieceOnBoardDiffCount;
    const int pieceToRemoveDiffCount = pos.piece_to_remove_count(WHITE) -
                                       pos.piece_to_remove_count(BLACK);

    switch (pos.get_phase()) {
    case Phase::none:
    case Phase::ready:
        break;

    case Phase::placing:
        if (rule.millFormationActionInPlacingPhase ==
            MillFormationActionInPlacingPhase::removalBasedOnMillCounts) {
            if (pos.get_action() == Action::remove) {
                value += VALUE_EACH_PIECE_NEEDREMOVE * pieceToRemoveDiffCount;
            } else {
                value += pos.mills_pieces_count_difference();
            }
            break;
        }
        [[fallthrough]];
    case Phase::moving:
        if (pos.shouldConsiderMobility()) {
            value += pos.get_mobility_diff();
        }

        if (!pos.shouldFocusOnBlockingPaths()) {
            pieceInHandDiffCount = pos.piece_in_hand_count(WHITE) -
                                   pos.piece_in_hand_count(BLACK);
            value += VALUE_EACH_PIECE_INHAND * pieceInHandDiffCount;

            pieceOnBoardDiffCount = pos.piece_on_board_count(WHITE) -
                                    pos.piece_on_board_count(BLACK);
            value += VALUE_EACH_PIECE_ONBOARD * pieceOnBoardDiffCount;

            if (pos.get_action() == Action::remove) {
                value += VALUE_EACH_PIECE_NEEDREMOVE * pieceToRemoveDiffCount;
            }
        }

        break;

    case Phase::gameOver:
        if (rule.pieceCount == 12 && (pos.piece_on_board_count(WHITE) +
                                          pos.piece_on_board_count(BLACK) >=
                                      SQUARE_NB)) {
            if (rule.boardFullAction == BoardFullAction::firstPlayerLose) {
                value -= VALUE_MATE;
            } else if (rule.boardFullAction == BoardFullAction::agreeToDraw) {
                value = VALUE_DRAW;
            } else {
                assert(0);
            }
        } else if (pos.get_action() == Action::select &&
                   pos.is_all_surrounded(pos.side_to_move()) &&
                   rule.stalemateAction ==
                       StalemateAction::endWithStalemateLoss) {
            const Value delta = pos.side_to_move() == WHITE ? -VALUE_MATE :
                                                              VALUE_MATE;
            value += delta;
        } else if (pos.piece_on_board_count(WHITE) < rule.piecesAtLeastCount) {
            value -= VALUE_MATE;
        } else if (pos.piece_on_board_count(BLACK) < rule.piecesAtLeastCount) {
            value += VALUE_MATE;
        }

        break;
    }

    if (pos.side_to_move() == BLACK) {
        value = -value;
    }

#ifdef EVAL_DRAW_WHEN_NOT_KNOWN_WIN_IF_MAY_FLY
    if (pos.get_phase() == Phase::moving && rule.mayFly &&
        !rule.hasDiagonalLines) {
        int piece_on_board_count_future_white = pos.piece_on_board_count(WHITE);
        int piece_on_board_count_future_black = pos.piece_on_board_count(BLACK);

        if (pos.side_to_move() == WHITE) {
            piece_on_board_count_future_black -= pos.piece_to_remove_count(
                                                     WHITE) -
                                                 pos.piece_to_remove_count(
                                                     BLACK);
        }

        if (pos.side_to_move() == BLACK) {
            piece_on_board_count_future_white -= pos.piece_to_remove_count(
                                                     BLACK) -
                                                 pos.piece_to_remove_count(
                                                     WHITE);
            ;
        }

        // TODO(calcitem): flyPieceCount?
        if (piece_on_board_count_future_black == 3 ||
            piece_on_board_count_future_white == 3) {
            if (abs(value) < VALUE_KNOWN_WIN) {
                value = VALUE_DRAW;
            }
        }
    }
#endif

    return value;
}

} // namespace

/// evaluate() is the evaluator for the outer world. It returns a static
/// evaluation of the position from the point of view of the side to move.

Value Eval::evaluate(Position &pos)
{
    // First try perfect database if available
    if (gameOptions.getUsePerfectDatabase()) {
        Value perfectValue = PerfectAPI::getValue(pos);
        if (perfectValue != VALUE_NONE) {
            return perfectValue;
        }
    }
    
    // Then try NNUE evaluation if enabled
    if (useNNUE && !evalFile.empty()) {
        // Ensure NNUE is initialized
        static bool nnueInitialized = false;
        if (!nnueInitialized) {
            // Normalize the file path to use correct separators for the current platform
            std::string normalizedPath = normalizePath(evalFile);
            
            std::ifstream stream(normalizedPath, std::ios::binary);
            
            // Log both original and normalized paths for debugging
            sync_cout << "info string Original NNUE model path: " << evalFile << sync_endl;
            sync_cout << "info string Normalized NNUE model path: " << normalizedPath << sync_endl;
            sync_cout << "info string Attempting to load NNUE model from: " << normalizedPath << sync_endl;
            
            // Check if file can be opened
            if (!stream.is_open()) {
                sync_cout << "info string ERROR: Failed to open NNUE model file: " << normalizedPath << sync_endl;
                assert(false && "Failed to open NNUE model file");
                return VALUE_NONE;
            }
            
            // Check file size
            stream.seekg(0, std::ios::end);
            std::streampos fileSize = stream.tellg();
            stream.seekg(0, std::ios::beg);
            sync_cout << "info string NNUE model file size: " << fileSize << " bytes" << sync_endl;
            
            if (fileSize == 0) {
                sync_cout << "info string ERROR: NNUE model file is empty" << sync_endl;
                assert(false && "NNUE model file is empty");
                return VALUE_NONE;
            }
            
            // Try to load the model
            bool loadResult = Stockfish::Eval::NNUE::load_eval(normalizedPath, stream);
            if (!loadResult) {
                sync_cout << "info string ERROR: Failed to load NNUE model - invalid format or corrupted file" << sync_endl;
                assert(false && "Failed to load NNUE model");
                return VALUE_NONE;
            }
            
            sync_cout << "info string NNUE model successfully loaded from " << normalizedPath << sync_endl;
            nnueInitialized = true;
        }
        
        return Stockfish::Eval::NNUE::evaluate(pos, false);
    }
    
    // Fall back to traditional evaluation only if NNUE is disabled
    return Evaluation(pos).value();
}
