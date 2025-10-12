// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// types.h

#ifndef TYPES_H_INCLUDED
#define TYPES_H_INCLUDED

#include "config.h"

/// When compiling with provided Makefile (e.g. for Linux and OSX),
/// configuration is done automatically. To get started type 'make help'.
///
/// When Makefile is not used (e.g. with Microsoft Visual Studio) some switches
/// need to be set manually:
///
/// -DNDEBUG      | Disable debugging mode. Always use this for release.
///
/// -DNO_PREFETCH | Disable use of prefetch asm-instruction. You may need this
/// to
///               | run on some very old machines.
///
/// -DUSE_POPCNT  | Add runtime support for use of popcnt asm-instruction. Works
///               | only in 64-bit mode and requires hardware with popcnt
///               support.
///
/// -DUSE_PEXT    | Add runtime support for use of pext asm-instruction. Works
///               | only in 64-bit mode and requires hardware with pext support.

#include <algorithm>
#include <cassert>
#include <cctype>
#include <climits>
#include <cstdint>
#include <cstdlib>

#if defined(_MSC_VER)
// Disable some silly and noisy warning from MSVC compiler
#pragma warning(disable : 4127) // Conditional expression is constant
#pragma warning(disable : 4146) // Unary minus operator applied to unsigned type
#pragma warning(disable : 4800) // Forcing value to bool 'true' or 'false'
#endif

/// Predefined macros hell:
///
/// __GNUC__           Compiler is gcc, Clang or Intel on Linux
/// __INTEL_COMPILER   Compiler is Intel
/// _MSC_VER           Compiler is MSVC or Intel on Windows
/// _WIN32             Building on Windows (any)
/// _WIN64             Building on Windows 64 bit

#if defined(__GNUC__) && \
    (__GNUC__ < 9 || (__GNUC__ == 9 && __GNUC_MINOR__ <= 2)) && \
    defined(_WIN32) && !defined(__clang__)
#define ALIGNAS_ON_STACK_VARIABLES_BROKEN
#endif

#define ASSERT_ALIGNED(ptr, alignment) \
    assert(reinterpret_cast<uintptr_t>(ptr) % (alignment) == 0)

#if defined(_WIN64) && defined(_MSC_VER) // No Makefile used
#include <intrin.h> // Microsoft header for _BitScanForward64()
#define IS_64BIT
#endif

#if defined(USE_POPCNT) && \
    (defined(__INTEL_COMPILER) || \
     (defined(_MSC_VER) && !defined(_M_ARM) && !defined(_M_ARM64)))
#include <nmmintrin.h> // Intel and Microsoft header for _mm_popcnt_u64()
#endif

#if !defined(NO_PREFETCH) && \
    (defined(__INTEL_COMPILER) || \
     (defined(_MSC_VER) && !defined(_M_ARM) && !defined(_M_ARM64)))
#include <xmmintrin.h> // Intel and Microsoft header for _mm_prefetch()
#endif

#if defined(USE_PEXT)
#include <immintrin.h> // Header for _pext_u64() intrinsic
#define pext(b, m) _pext_u64(b, m)
#else
#define pext(b, m) 0
#endif

#ifdef USE_POPCNT
constexpr bool HasPopCnt = true;
#else
constexpr bool HasPopCnt = false;
#endif

#ifdef USE_PEXT
constexpr bool HasPext = true;
#else
constexpr bool HasPext = false;
#endif

#ifdef IS_64BIT
constexpr bool Is64Bit = true;
#else
constexpr bool Is64Bit = false;
#endif

/// Hash key type for position identification
///
/// Zobrist hash key used for transposition table lookups and repetition
/// detection. Can be 32-bit or 64-bit depending on compilation flags.
///
/// @note 32-bit keys have collision risk but are faster on 32-bit systems
/// @note 64-bit keys virtually collision-free but use more memory
#ifdef TRANSPOSITION_TABLE_64BIT_KEY
typedef uint64_t Key;
#else
using Key = uint32_t;
#endif /* TRANSPOSITION_TABLE_64BIT_KEY */

/// Bitboard representation of board squares
///
/// Uses 32 bits to represent the 24-square Mill board plus metadata.
/// Each bit represents one square's occupancy or property.
///
/// Bit Layout:
///   Bits 0-23: Square occupancy (24 squares)
///   Bits 24-31: Reserved for flags and metadata
///
/// @note 32-bit chosen for fast operations on both 32 and 64-bit CPUs
/// @note Allows atomic operations on most platforms
/// @note Efficient bitwise operations (AND, OR, XOR, popcount)
using Bitboard = uint32_t;

/// Maximum number of legal moves in any position
///
/// Calculation: (24 squares - 4 corners - 3 reserved) × 4 directions = 68
/// Rounded up to 72 for safety margin.
///
/// @note Used for stack-allocated move arrays
/// @note Conservative estimate (actual max is lower)
constexpr int MAX_MOVES = 72; // (24 - 4 - 3) * 4 = 68

/// Maximum search depth in plies (half-moves)
///
/// @note Practical limit due to stack size and time constraints
/// @note Typical search depth: 6-12 plies
constexpr int MAX_PLY = 48;

/// Move representation (encoded as integer)
///
/// Move encoding:
///   Positive: from_square (bits 8-15) | to_square (bits 0-7)
///   Negative: -(remove_square)
///   MOVE_NONE: No move / invalid move
///   MOVE_NULL: Null move (for search purposes)
///
/// @note Different move types distinguished by value sign and bits
/// @see from_sq(), to_sq(), type_of() for decoding
enum Move : int32_t { MOVE_NONE, MOVE_NULL = 65 };

/// Move type classification
///
/// Used to distinguish different kinds of moves in the game.
enum MoveType { 
    MOVETYPE_PLACE,   ///< Place piece from hand to board (placing phase)
    MOVETYPE_MOVE,    ///< Move piece on board (moving/flying phase)
    MOVETYPE_REMOVE   ///< Remove opponent piece (after mill formation)
};

/// AI move source classification
///
/// Indicates where the best move came from, useful for debugging
/// and user feedback.
enum class AiMoveType { 
    unknown,      ///< Move source not determined
    traditional,  ///< From search algorithm (Alpha-Beta, MTD(f), MCTS)
    perfect,      ///< From perfect play database (endgame tablebase)
    consensus     ///< Search and perfect database agree (high confidence)
};

/// Color enumeration
///
/// Represents piece colors and game outcomes. Uses specific values
/// for efficient array indexing and bitboard operations.
///
/// @note NOBODY (0) allows using Color as zero-based array index
/// @note WHITE (1) and BLACK (2) used in bitboard shift calculations
/// @note COLOR_NB (3) represents number of actual colors (for array sizing)
/// @note DRAW (4) used for game results, not a real player color
/// @note Toggle color: ~WHITE = BLACK, ~BLACK = WHITE (XOR with 3)
enum Color : uint8_t {
    NOBODY = 0,    ///< Empty square or no player (also neutral)
    WHITE = 1,     ///< White player (first player, typically human)
    BLACK = 2,     ///< Black player (second player, typically AI)
    COLOR_NB = 3,  ///< Number of actual colors (used for array bounds)
    DRAW = 4,      ///< Game result: draw (not a player color)
};

/// Game phase enumeration
///
/// Mill game progresses through distinct phases with different rules:
///
/// Flow: none → ready → placing → moving → gameOver
///                                    ↓
///                                 flying (special case of moving)
///
/// @note Phase determines which moves are legal
/// @note Flying activated when player has ≤ flyPieceCount pieces
enum class Phase : uint16_t { 
    none,      ///< Uninitialized state
    ready,     ///< Game set up but not started
    placing,   ///< Placing phase: players place pieces from hand
    moving,    ///< Moving phase: all pieces placed, normal movement
    gameOver   ///< Game ended: winner determined
    // Note: Flying is a variant of moving (not separate phase)
};

// enum class that represents an action that one player can take when it's
// his turn at the board. The can be on of the following:
//   - Select a piece on the board;
//   - Place a piece on the board;
//   - Move a piece on the board:
//       - Slide a piece between two adjacent locations;
//       - 'Jump' a piece to any empty location if the player has less than
//         three or four pieces and mayFly is |true|;
//   - Remove an opponent's piece after successfully closing a mill.
enum class Action : uint16_t { none, select, place, remove };

enum class GameOverReason {
    None,

    // A player wins by reducing the opponent to two pieces
    // (where they could no longer form mills and thus be unable to win)
    loseFewerThanThree,

    // A player wins by leaving them without a legal move.
    loseNoLegalMoves,
    loseFullBoard,

    loseResign,
    loseTimeout,
    drawThreefoldRepetition,
    drawFiftyMove,
    drawEndgameFiftyMove,
    drawFullBoard,
    drawStalemateCondition,
};

/// Alpha-Beta search bound types
///
/// Used in transposition table to indicate the type of value stored.
/// Critical for correct Alpha-Beta pruning with TT integration.
///
/// @note BOUND_EXACT means exact minimax value
/// @note BOUND_UPPER means value ≤ stored value (failed low)
/// @note BOUND_LOWER means value ≥ stored value (failed high)
enum Bound : uint8_t {
    BOUND_NONE,   ///< No bound information
    BOUND_UPPER,  ///< Upper bound (alpha didn't improve, fail-low)
    BOUND_LOWER,  ///< Lower bound (beta cutoff, fail-high)
    BOUND_EXACT = BOUND_UPPER | BOUND_LOWER  ///< Exact value (PV node)
};

/// Evaluation value type (centipawn scale)
///
/// All evaluations use this type. Positive values favor side to move.
///
/// Value Scale:
///   +100 = approximately one piece advantage
///   +50  = significant positional advantage
///   +10  = small advantage
///   0    = equal position
///   -X   = disadvantage
///
/// Special Values:
///   VALUE_INFINITE: Certain win (mate or forced win)
///   VALUE_MATE: Mate score base
///   VALUE_ZERO/DRAW: Equal or drawn position
///   VALUE_UNKNOWN: Uninitialized or error state
///
/// @note int8_t range: -128 to +127
/// @note Allows fast arithmetic and comparison
enum Value : int8_t {
    VALUE_ZERO = 0,    ///< Equal position
    VALUE_DRAW = 0,    ///< Draw score (same as zero)

#ifdef ENDGAME_LEARNING
    VALUE_KNOWN_WIN = 25,  ///< Known winning position (endgame DB)
#endif

    VALUE_MATE = 80,        ///< Base mate score
    VALUE_UNIQUE = 100,     ///< Unique/forced move bonus
    VALUE_INFINITE = 125,   ///< Certain win (>= mate)
    VALUE_UNKNOWN = INT8_MIN,  ///< -128, uninitialized value
    VALUE_NONE = VALUE_UNKNOWN,

    // Tablebase win/loss scores (within MAX_PLY distance)
    VALUE_TB_WIN_IN_MAX_PLY = VALUE_MATE - 2 * MAX_PLY,
    VALUE_TB_LOSS_IN_MAX_PLY = -VALUE_TB_WIN_IN_MAX_PLY,
    VALUE_MATE_IN_MAX_PLY = VALUE_MATE - MAX_PLY,
    VALUE_MATED_IN_MAX_PLY = -VALUE_MATE_IN_MAX_PLY,

    // Piece values (centipawns per piece)
    PieceValue = 5,                        ///< Base piece value (500 cp = 1 piece at 100 scale)
    VALUE_EACH_PIECE = PieceValue,         ///< Value of one piece
    VALUE_EACH_PIECE_INHAND = VALUE_EACH_PIECE,     ///< Piece in hand
    VALUE_EACH_PIECE_ONBOARD = VALUE_EACH_PIECE,    ///< Piece on board
    VALUE_EACH_PIECE_NEEDREMOVE = VALUE_EACH_PIECE, ///< Opponent piece to remove

    // Search window sizes
    VALUE_MTDF_WINDOW = 1,     ///< MTD(f) null window size
    VALUE_PVS_WINDOW = 1,      ///< PVS null window size

    // Aspiration window sizes for different phases
    VALUE_PLACING_WINDOW = VALUE_EACH_PIECE_NEEDREMOVE +
                           (VALUE_EACH_PIECE_ONBOARD -
                            VALUE_EACH_PIECE_INHAND) +
                           1,
    VALUE_MOVING_WINDOW = VALUE_EACH_PIECE_NEEDREMOVE + 1,
};

enum Rating : int8_t {
    RATING_ZERO = 0,

    RATING_BLOCK_ONE_MILL = 10,
    RATING_ONE_MILL = 11,

    RATING_STAR_SQUARE = 11,

    RATING_BLOCK_TWO_MILLS = RATING_BLOCK_ONE_MILL * 2,
    RATING_TWO_MILLS = RATING_ONE_MILL * 2,

    RATING_BLOCK_THREE_MILLS = RATING_BLOCK_ONE_MILL * 3,
    RATING_THREE_MILLS = RATING_ONE_MILL * 3,

    RATING_REMOVE_ONE_MILL = RATING_ONE_MILL,
    RATING_REMOVE_TWO_MILLS = RATING_TWO_MILLS,
    RATING_REMOVE_THREE_MILLS = RATING_THREE_MILLS,

    RATING_REMOVE_THEIR_ONE_MILL = -RATING_REMOVE_ONE_MILL,
    RATING_REMOVE_THEIR_TWO_MILLS = -RATING_REMOVE_TWO_MILLS,
    RATING_REMOVE_THEIR_THREE_MILLS = -RATING_REMOVE_THREE_MILLS,

    RATING_TT = 100,
    RATING_MAX = INT8_MAX,
};

/// Piece type enumeration
///
/// Classifies pieces by color and location. Uses bit encoding for
/// efficient type checking and filtering.
///
/// @note Lower bits: piece color/type
/// @note Upper bits: piece location (IN_HAND, ON_BOARD)
/// @note Can combine: WHITE_PIECE | IN_HAND = white piece in hand
enum PieceType : uint16_t {
    NO_PIECE_TYPE = 0,  ///< No piece or empty square
    WHITE_PIECE = 1,    ///< White piece (any location)
    BLACK_PIECE = 2,    ///< Black piece (any location)
    MARKED = 3,         ///< Marked piece (special rules)
    ALL_PIECES = 0,     ///< All pieces regardless of type
    PIECE_TYPE_NB = 4,  ///< Number of piece types

    IN_HAND = 0x10,     ///< Location flag: piece in hand (not placed yet)
    ON_BOARD = 0x20,    ///< Location flag: piece on board (placed)
};

/// Piece representation with identity
///
/// Each piece has unique ID to track individual pieces through the game.
/// Uses hex encoding: 0xCN where C=color (1=white, 2=black), N=piece number.
///
/// Encoding:
///   0x00: No piece (empty square)
///   0x0F: Marked piece (special state)
///   0x1N: White piece N (N = 0-12, for 12 Men's Morris)
///   0x2N: Black piece N (N = 0-12)
///
/// @note Upper nibble: color (1=white, 2=black)
/// @note Lower nibble: piece number (0-C = 12 pieces max)
/// @note Allows identifying which specific piece moved (for animation)
enum Piece : uint8_t {
    NO_PIECE = 0x00,      ///< Empty square
    MARKED_PIECE = 0x0F,  ///< Marked for removal or special state

    W_PIECE = 0x10,     ///< Generic white piece (when ID doesn't matter)
    W_PIECE_1 = 0x11,   ///< White piece #1
    W_PIECE_2 = 0x12,   ///< White piece #2
    W_PIECE_3 = 0x13,
    W_PIECE_4 = 0x14,
    W_PIECE_5 = 0x15,
    W_PIECE_6 = 0x16,
    W_PIECE_7 = 0x17,
    W_PIECE_8 = 0x18,
    W_PIECE_9 = 0x19,
    W_PIECE_10 = 0x1A,
    W_PIECE_11 = 0x1B,
    W_PIECE_12 = 0x1C,

    B_PIECE = 0x20,
    B_PIECE_1 = 0x21,
    B_PIECE_2 = 0x22,
    B_PIECE_3 = 0x23,
    B_PIECE_4 = 0x24,
    B_PIECE_5 = 0x25,
    B_PIECE_6 = 0x26,
    B_PIECE_7 = 0x27,
    B_PIECE_8 = 0x28,
    B_PIECE_9 = 0x29,
    B_PIECE_10 = 0x2A,
    B_PIECE_11 = 0x2B,
    B_PIECE_12 = 0x2C,

    // Fix overflow
    PIECE_NB = 64,
};

/// Search depth type (in plies / half-moves)
///
/// Represents search depth as signed 8-bit integer.
/// Negative depths can represent quiescence search extensions.
///
/// @note Range: -128 to +127
/// @note Typical values: 1-16
/// @note Each ply is one move by one player
using Depth = int8_t;

/// Depth constants
enum : int { 
    DEPTH_NONE = 0,         ///< No depth / uninitialized
    DEPTH_OFFSET = DEPTH_NONE  ///< Base offset for depth calculations
};

/// Board square enumeration
///
/// Mill board has 24 squares arranged in 3 concentric squares.
/// Squares numbered 0-31 for efficient bit operations, but only
/// 24 squares (8-31) are valid game squares.
///
/// Board Layout (algebraic notation):
///   a3 ----- d3 ----- g3
///   |  a2 -- d2 -- g2  |
///   |  |  a1-d1-g1  |  |
///   b3-b2-b1   c1-c2-c3
///
/// Internal numbering: SQ_8 to SQ_31 (24 squares)
/// Algebraic mapping: a1=SQ_8, d2=SQ_19, g3=SQ_31
///
/// @note Squares 0-7 are invalid (reserved/padding)
/// @note Squares 8-31 are valid game squares
/// @note Allows efficient bitboard operations
enum Square : int {
    // Numeric indices (0-7 reserved, 8-31 valid)
    SQ_0 = 0,   ///< Reserved
    SQ_1 = 1,   ///< Reserved
    SQ_2 = 2,   ///< Reserved
    SQ_3 = 3,   ///< Reserved
    SQ_4 = 4,   ///< Reserved
    SQ_5 = 5,   ///< Reserved
    SQ_6 = 6,   ///< Reserved
    SQ_7 = 7,   ///< Reserved
    SQ_8 = 8,   ///< Valid square (a1)
    SQ_9 = 9,
    SQ_10 = 10,
    SQ_11 = 11,
    SQ_12 = 12,
    SQ_13 = 13,
    SQ_14 = 14,
    SQ_15 = 15,
    SQ_16 = 16,
    SQ_17 = 17,
    SQ_18 = 18,
    SQ_19 = 19,
    SQ_20 = 20,
    SQ_21 = 21,
    SQ_22 = 22,
    SQ_23 = 23,
    SQ_24 = 24,
    SQ_25 = 25,
    SQ_26 = 26,
    SQ_27 = 27,
    SQ_28 = 28,
    SQ_29 = 29,
    SQ_30 = 30,
    SQ_31 = 31,

    // Algebraic notation mapping
    SQ_A1 = 8,   ///< a1 square
    SQ_A2 = 9,
    SQ_A3 = 10,
    SQ_A4 = 11,
    SQ_A5 = 12,
    SQ_A6 = 13,
    SQ_A7 = 14,
    SQ_A8 = 15,
    SQ_B1 = 16,  ///< b1 square
    SQ_B2 = 17,
    SQ_B3 = 18,
    SQ_B4 = 19,
    SQ_B5 = 20,
    SQ_B6 = 21,
    SQ_B7 = 22,
    SQ_B8 = 23,
    SQ_C1 = 24,  ///< c1 square
    SQ_C2 = 25,
    SQ_C3 = 26,
    SQ_C4 = 27,
    SQ_C5 = 28,
    SQ_C6 = 29,
    SQ_C7 = 30,
    SQ_C8 = 31,

    // Extended range (for some algorithms)
    SQ_32 = 32,
    SQ_33 = 33,
    SQ_34 = 34,
    SQ_35 = 35,
    SQ_36 = 36,
    SQ_37 = 37,
    SQ_38 = 38,
    SQ_39 = 39,

    // Special values
    SQ_NONE = 0,  ///< Invalid/no square

    // Constants
    SQUARE_NB = 24,      ///< Number of valid squares on Mill board
    SQUARE_ZERO = 0,     ///< Zero-based start
    SQUARE_EXT_NB = 40,  ///< Extended square count (for some variants)

    // Valid range
    SQ_BEGIN = SQ_8,   ///< First valid square (a1)
    SQ_END = SQ_32     ///< One past last valid square (exclusive)
};

enum MoveDirection : int {
    MD_CLOCKWISE = 0,
    MD_BEGIN = MD_CLOCKWISE,
    MD_ANTICLOCKWISE = 1,
    MD_INWARD = 2,
    MD_OUTWARD = 3,
    MD_NB = 4
};

enum LineDirection : int {
    LD_HORIZONTAL = 0,
    LD_VERTICAL = 1,
    LD_SLASH = 2,
    LD_NB = 3
};

enum File : int {
    FILE_A = 1,
    FILE_B = 2,
    FILE_C = 3,
    FILE_NB = 3,
    FILE_MAX = FILE_C
};

enum Rank : int {
    RANK_1 = 1,
    RANK_2 = 2,
    RANK_3 = 3,
    RANK_4 = 4,
    RANK_5 = 5,
    RANK_6 = 6,
    RANK_7 = 7,
    RANK_8 = 8,
    RANK_NB = 8,
    RANK_MAX = RANK_8
};

#define ENABLE_BASE_OPERATORS_ON(T) \
    constexpr T operator+(T d1, int d2) \
    { \
        return T(int(d1) + d2); \
    } \
    constexpr T operator-(T d1, int d2) \
    { \
        return T(int(d1) - d2); \
    } \
    constexpr T operator-(T d) \
    { \
        return T(-int(d)); \
    } \
    inline T &operator+=(T &d1, int d2) \
    { \
        return d1 = d1 + d2; \
    } \
    inline T &operator-=(T &d1, int d2) \
    { \
        return d1 = d1 - d2; \
    }

#define ENABLE_INCR_OPERATORS_ON(T) \
    inline T &operator++(T &d) \
    { \
        return d = T(int(d) + 1); \
    } \
    inline T &operator--(T &d) \
    { \
        return d = T(int(d) - 1); \
    }

#define ENABLE_FULL_OPERATORS_ON(T) \
    ENABLE_BASE_OPERATORS_ON(T) \
    constexpr T operator*(int i, T d) noexcept \
    { \
        return T(i * int(d)); \
    } \
    constexpr T operator*(T d, int i) noexcept \
    { \
        return T(int(d) * i); \
    } \
    constexpr T operator/(T d, int i) noexcept \
    { \
        return T(int(d) / i); \
    } \
    constexpr int operator/(T d1, T d2) noexcept \
    { \
        return int(d1) / int(d2); \
    } \
    inline T &operator*=(T &d, int i) noexcept \
    { \
        return d = T(int(d) * i); \
    } \
    inline T &operator/=(T &d, int i) noexcept \
    { \
        return d = T(int(d) / i); \
    }

ENABLE_FULL_OPERATORS_ON(Value)

ENABLE_INCR_OPERATORS_ON(Piece)
ENABLE_INCR_OPERATORS_ON(PieceType)
ENABLE_INCR_OPERATORS_ON(Square)
ENABLE_INCR_OPERATORS_ON(File)
ENABLE_INCR_OPERATORS_ON(Rank)
ENABLE_INCR_OPERATORS_ON(MoveDirection)

#undef ENABLE_FULL_OPERATORS_ON
#undef ENABLE_INCR_OPERATORS_ON
#undef ENABLE_BASE_OPERATORS_ON

/// Toggle color (WHITE ↔ BLACK)
///
/// Efficiently switches between WHITE and BLACK using XOR.
///
/// @param c  Color to toggle
/// @return   Opposite color (WHITE→BLACK, BLACK→WHITE)
/// @note ~WHITE = BLACK, ~BLACK = WHITE
/// @note ~NOBODY = 3 (invalid), ~DRAW = 1 (invalid)
constexpr Color operator~(Color c)
{
    return static_cast<Color>(c ^ 3); // Toggle color
}

/// Create square from file and rank
///
/// @param f  File (A, B, C)
/// @param r  Rank (1-8)
/// @return   Square at file and rank intersection
constexpr Square make_square(File f, Rank r)
{
    return static_cast<Square>((f << 3) + r - 1);
}

/// Create piece from color
///
/// Creates generic piece (without specific ID) for given color.
///
/// @param c  Piece color
/// @return   Generic piece (W_PIECE or B_PIECE)
constexpr Piece make_piece(Color c)
{
    return static_cast<Piece>(c << 4);
}

/// Create piece from color and type
///
/// @param c   Piece color
/// @param pt  Piece type
/// @return    Constructed piece
constexpr Piece make_piece(Color c, PieceType pt)
{
    if (pt == WHITE_PIECE || pt == BLACK_PIECE) {
        return make_piece(c);
    }

    if (pt == MARKED) {
        return MARKED_PIECE;
    }

    return NO_PIECE;
}

/// Extract color from piece
///
/// @param pc  Piece value
/// @return    Color of piece (WHITE, BLACK, or NOBODY)
/// @note Uses upper nibble (>> 4)
constexpr Color color_of(Piece pc)
{
    return static_cast<Color>(pc >> 4);
}

/// Extract piece type from piece
///
/// @param pc  Piece value
/// @return    Piece type (WHITE_PIECE, BLACK_PIECE, MARKED, or NO_PIECE_TYPE)
constexpr PieceType type_of(Piece pc)
{
    if (pc == MARKED_PIECE) {
        return MARKED;
    }

    if (color_of(pc) == WHITE) {
        return WHITE_PIECE;
    }

    if (color_of(pc) == BLACK) {
        return BLACK_PIECE;
    }

    return NO_PIECE_TYPE;
}

/// Validate square is in valid range
///
/// @param s  Square to validate
/// @return   true if square is valid (SQ_NONE or SQ_BEGIN..SQ_END)
constexpr bool is_ok(Square s)
{
    return s == SQ_NONE || (s >= SQ_BEGIN && s < SQ_END);
}

/// Get file of square
///
/// @param s  Square
/// @return   File (A, B, or C)
constexpr File file_of(Square s)
{
    return static_cast<File>(s >> 3);
}

/// Get rank of square
///
/// @param s  Square
/// @return   Rank (1-8)
constexpr Rank rank_of(Square s)
{
    return static_cast<Rank>((s & 0x07) + 1);
}

/// Extract source square from move
///
/// Decodes the from-square from move encoding.
///
/// @param m  Move (encoded)
/// @return   Source square (SQ_NONE for placing moves)
/// @note For remove moves (negative), takes absolute value first
constexpr Square from_sq(Move m)
{
    if (m < 0)
        m = static_cast<Move>(-m);

    return static_cast<Square>(m >> 8);
}

/// Extract destination square from move
///
/// Decodes the to-square from move encoding.
///
/// @param m  Move (encoded)
/// @return   Destination square
/// @note For remove moves (negative), takes absolute value first
constexpr Square to_sq(Move m)
{
    if (m < 0)
        m = static_cast<Move>(-m);

    return static_cast<Square>(m & 0x00FF);
}

/// Get move type from encoded move
///
/// @param m  Move (encoded)
/// @return   MOVETYPE_REMOVE (negative), MOVETYPE_MOVE (has from), or MOVETYPE_PLACE
constexpr MoveType type_of(Move m)
{
    if (m < 0) {
        return MOVETYPE_REMOVE;
    }
    if (m & 0x1f00) {
        return MOVETYPE_MOVE;
    }

    return MOVETYPE_PLACE; // m & 0x00ff
}

/// Construct move from source and destination
///
/// Creates encoded move representation.
///
/// @param from  Source square (or SQ_NONE for placing)
/// @param to    Destination square
/// @return      Encoded move
/// @note Result is positive (PLACE or MOVE type)
constexpr Move make_move(Square from, Square to)
{
    return static_cast<Move>((from << 8) + to);
}

/// Reverse a move (swap from and to)
///
/// @param m  Move to reverse
/// @return   Reversed move (to→from becomes from→to)
/// @note Useful for symmetry and analysis
constexpr Move reverse_move(Move m)
{
    return make_move(to_sq(m), from_sq(m));
}

/// Validate move encoding
///
/// @param m  Move to validate
/// @return   true if move is valid (from != to)
/// @note Catches MOVE_NULL and MOVE_NONE
constexpr bool is_ok(Move m)
{
    return from_sq(m) != to_sq(m); // Catch MOVE_NULL and MOVE_NONE
}

/// Generate hash key from seed
///
/// Creates Zobrist hash key using congruential pseudo-random number generator.
///
/// @param seed  Initial seed value
/// @return      Hash key for zobrist table initialization
/// @note Based on standard LCG formula
constexpr Key make_key(uint64_t seed)
{
    return static_cast<Key>(seed * 6364136223846793005ULL +
                            1442695040888963407ULL);
}

#endif // #ifndef TYPES_H_INCLUDED
