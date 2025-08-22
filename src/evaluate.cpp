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
#include <cstring>
#include <mutex>

namespace Eval {

// NNUE evaluation settings
bool useNNUE = false;
std::string evalFile = "";
bool nnueInitialized = false;

// Hybrid evaluation settings
int nnueMinDepth = 1;  // Minimum depth to use NNUE evaluation

// Guard concurrent or repeated NNUE initialization
static std::mutex nnueInitMutex;
static std::string loadedNnuePathNormalized;

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
        std::lock_guard<std::mutex> lock(nnueInitMutex);

        // Normalize the file path to use correct separators for the current platform
        std::string normalizedPath = normalizePath(evalFile);

        // If already initialized with the same model, skip re-initialization
        if (nnueInitialized && normalizedPath == loadedNnuePathNormalized) {
            sync_cout << "info string NNUE already initialized with the same model; skipping re-init" << sync_endl;
            return;
        }
        
        std::ifstream stream(normalizedPath, std::ios::binary);
        
        // Log both original and normalized paths for debugging
        sync_cout << "info string Original NNUE model path: " << evalFile << sync_endl;
        sync_cout << "info string Normalized NNUE model path: " << normalizedPath << sync_endl;
        sync_cout << "info string Attempting to load NNUE model from: " << normalizedPath << sync_endl;
        
        // Check if file can be opened
        if (!stream.is_open()) {
            sync_cout << "info string ERROR: Failed to open NNUE model file: " << normalizedPath << sync_endl;
            sync_cout << "info string NNUE initialization failed - model file not accessible" << sync_endl;
            nnueInitialized = false;
            return;
        }
        
        // Check file size
        stream.seekg(0, std::ios::end);
        std::streampos fileSize = stream.tellg();
        stream.seekg(0, std::ios::beg);
        sync_cout << "info string NNUE model file size: " << fileSize << " bytes" << sync_endl;
        
        if (fileSize == 0) {
            sync_cout << "info string ERROR: NNUE model file is empty" << sync_endl;
            sync_cout << "info string NNUE initialization failed - empty model file" << sync_endl;
            nnueInitialized = false;
            return;
        }
        
        // Check file header information
        sync_cout << "info string Checking NNUE file header..." << sync_endl;
        checkNNUEFileHeader(normalizedPath);
        
        // Try to load the model
        sync_cout << "info string Initializing NNUE structures..." << sync_endl;
        Stockfish::Eval::NNUE::initialize();
        
        sync_cout << "info string Reading NNUE parameters..." << sync_endl;
        // Reset stream to beginning after header check
        stream.clear();
        stream.seekg(0, std::ios::beg);
        
        bool loadResult = Stockfish::Eval::NNUE::load_eval(normalizedPath, stream);
        if (!loadResult) {
            sync_cout << "info string ERROR: Failed to load NNUE model - checking specific failure point..." << sync_endl;
            
            // Try to diagnose the specific failure
            stream.clear();
            stream.seekg(0, std::ios::beg);
            
            // Check if we can read the header again
            std::uint32_t testVersion = readLittleEndianUint32(stream);
            std::uint32_t testHashValue = readLittleEndianUint32(stream);
            std::uint32_t testDescSize = readLittleEndianUint32(stream);
            
            sync_cout << "info string Diagnostic - Version: 0x" << std::hex << testVersion 
                      << ", Hash: 0x" << testHashValue 
                      << ", DescSize: " << std::dec << testDescSize << sync_endl;
            
            if (testDescSize > 0 && testDescSize < 1000) {
                stream.seekg(testDescSize, std::ios::cur); // Skip description
            }
            
            // Check current stream position after header
            std::streampos currentPos = stream.tellg();
            sync_cout << "info string Current stream position after header: " << currentPos << sync_endl;
            
            // Check remaining bytes
            stream.seekg(0, std::ios::end);
            std::streampos endPos = stream.tellg();
            sync_cout << "info string Remaining bytes for parameters: " << (endPos - currentPos) << sync_endl;
            
            // Check if the issue is with FeatureTransformer dimensions
            sync_cout << "info string Expected FeatureTransformer input dimensions: " 
                      << Stockfish::Eval::NNUE::FeatureSet::Dimensions << sync_endl;
            sync_cout << "info string Expected TransformedFeatureDimensions: " 
                      << Stockfish::Eval::NNUE::TransformedFeatureDimensions << sync_endl;
            
            // Calculate expected parameter sizes
            const auto featureDims = Stockfish::Eval::NNUE::FeatureSet::Dimensions;
            const auto transformedDims = Stockfish::Eval::NNUE::TransformedFeatureDimensions;
            const auto psqtBuckets = Stockfish::Eval::NNUE::PSQTBuckets;
            
            sync_cout << "info string Expected parameter sizes:" << sync_endl;
            sync_cout << "info string - Biases: " << transformedDims << " elements" << sync_endl;
            sync_cout << "info string - Weights: " << (transformedDims * featureDims) << " elements" << sync_endl;
            sync_cout << "info string - PSQT Weights: " << (psqtBuckets * featureDims) << " elements" << sync_endl;
            
            // Calculate expected bytes (actual serializer writes int16 bias and int16 FT weights, int32 PSQT)
            const size_t biasBytes = transformedDims * 2;  // int16_t
            const size_t weightBytes = transformedDims * featureDims * 2;  // int16_t
            const size_t psqtBytes = psqtBuckets * featureDims * 4;  // int32_t
            const size_t totalFeatureTransformerBytes = biasBytes + weightBytes + psqtBytes;
            
            sync_cout << "info string Expected FeatureTransformer bytes:" << sync_endl;
            sync_cout << "info string - Biases: " << biasBytes << " bytes" << sync_endl;
            sync_cout << "info string - Weights: " << weightBytes << " bytes" << sync_endl;
            sync_cout << "info string - PSQT Weights: " << psqtBytes << " bytes" << sync_endl;
            sync_cout << "info string - Total FeatureTransformer: " << totalFeatureTransformerBytes << " bytes" << sync_endl;
            
            // Calculate network layer bytes (InputLayer: 1536 -> HiddenLayer1: 15 -> HiddenLayer2: 32 -> OutputLayer: 1)
            // Each layer has biases (int32_t, 4 bytes) and weights (int8_t, 1 byte)
            const size_t layer1BiasBytes = 15 * 4;  // 15 biases, int32_t
            // nnue-pytorch writes an extra (L2+1) row in L1; account for it in expected size
            const size_t layer1WeightBytes = (15 + 1) * transformedDims * 1;  // 16 * 1536
            const size_t layer2BiasBytes = 32 * 4;  // 32 biases, int32_t  
            const size_t layer2WeightBytes = 32 * 15 * 1;  // 32 * 15 weights, int8_t
            const size_t layer3BiasBytes = 1 * 4;   // 1 bias, int32_t
            const size_t layer3WeightBytes = 1 * 32 * 1;   // 1 * 32 weights, int8_t
            
            const size_t totalNetworkBytes = layer1BiasBytes + layer1WeightBytes + 
                                           layer2BiasBytes + layer2WeightBytes + 
                                           layer3BiasBytes + layer3WeightBytes;
            
            sync_cout << "info string Expected Network layer bytes:" << sync_endl;
            sync_cout << "info string - Layer1 (1536->15): " << (layer1BiasBytes + layer1WeightBytes) << " bytes" << sync_endl;
            sync_cout << "info string - Layer2 (15->32): " << (layer2BiasBytes + layer2WeightBytes) << " bytes" << sync_endl;
            sync_cout << "info string - Layer3 (32->1): " << (layer3BiasBytes + layer3WeightBytes) << " bytes" << sync_endl;
            sync_cout << "info string - Total Network: " << totalNetworkBytes << " bytes" << sync_endl;
            
            const size_t totalExpectedBytes = totalFeatureTransformerBytes + totalNetworkBytes * Stockfish::Eval::NNUE::LayerStacks;
            sync_cout << "info string Total expected bytes (with " << Stockfish::Eval::NNUE::LayerStacks << " layer stacks): " << totalExpectedBytes << " bytes" << sync_endl;
            sync_cout << "info string Available bytes: " << (endPos - currentPos) << " bytes" << sync_endl;
            
            if (featureDims != 1152) {
                sync_cout << "info string WARNING: FeatureSet dimensions (" << featureDims 
                          << ") do not match expected Nine Men's Morris dimensions (1152)" << sync_endl;
            }
            
            if (transformedDims != featureDims) {
                sync_cout << "info string ERROR: TransformedFeatureDimensions (" << transformedDims 
                          << ") does not match FeatureSet dimensions (" << featureDims << ")" << sync_endl;
            } else {
                sync_cout << "info string OK: Dimensions are consistent (" << transformedDims << ")" << sync_endl;
            }
            
            sync_cout << "info string NNUE model loading failed - parameters could not be loaded" << sync_endl;
            nnueInitialized = false;
            return;
        }
        
        sync_cout << "info string NNUE model successfully loaded from " << normalizedPath << sync_endl;
        sync_cout << "info string NNUE evaluation is now active" << sync_endl;
        nnueInitialized = true;
        loadedNnuePathNormalized = normalizedPath;
    } else {
        nnueInitialized = false;
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
    
    // If NNUE is enabled, only use NNUE evaluation
    if (useNNUE) {
        if (nnueInitialized) {
            return Stockfish::Eval::NNUE::evaluate(pos, false);
        } else {
            sync_cout << "info string ERROR: NNUE is enabled but not initialized properly" << sync_endl;
            // Return a neutral evaluation when NNUE fails to load
            return VALUE_DRAW;
        }
    }
    
    // Only use traditional evaluation if NNUE is explicitly disabled
    return Evaluation(pos).value();
}

/// Hybrid evaluation function with depth information
/// Uses traditional evaluation for shallow depths and NNUE for deeper analysis
Value Eval::evaluate(Position &pos, Depth depth)
{
    // First try perfect database if available
    if (gameOptions.getUsePerfectDatabase()) {
        Value perfectValue = PerfectAPI::getValue(pos);
        if (perfectValue != VALUE_NONE) {
            return perfectValue;
        }
    }
    
    // If NNUE is enabled, always use NNUE evaluation (no depth-based fallback)
    if (useNNUE) {
        if (nnueInitialized) {
            return Stockfish::Eval::NNUE::evaluate(pos, false);
        } else {
            sync_cout << "info string ERROR: NNUE is enabled but not initialized properly" << sync_endl;
            // Return a neutral evaluation when NNUE fails to load
            return VALUE_DRAW;
        }
    }
    
    // Only use traditional evaluation if NNUE is explicitly disabled
    return Evaluation(pos).value();
}
