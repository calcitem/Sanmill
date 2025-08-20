/*
  NNUE feature set for Nine Men's Morris

  This feature set mirrors ml/nnue-pytorch/features_mill.py (NineMillFeatures):
  - Board has 24 valid points (indices SQ_8..SQ_31 -> 0..23 here)
  - Two piece types (white/black stones)
  - Anchored representation: for each anchor (24), encode all piece placements
    in planes of size (2 piece types x 24 positions) -> 24 x (2 x 24) = 1152
    input features per perspective
*/

#ifndef NNUE_FEATURES_NINE_MILL_H_INCLUDED
#define NNUE_FEATURES_NINE_MILL_H_INCLUDED

#include "../nnue_common.h"

// Forward declarations to avoid circular includes. Full definitions are in position.h
class Position;
struct StateInfo;

namespace Stockfish::Eval::NNUE::Features {

  class NineMill {
   public:
    // Feature set name and hash must match the serializer used by nnue-pytorch
    static constexpr const char* Name = "NineMill";
    static constexpr std::uint32_t HashValue = 0x9A111001u; // keep in sync with Py serializer

    // Board constants for Nine Men's Morris
    static constexpr IndexType NumSquares = 24;      // 0..23 mapped from SQ_8..SQ_31
    static constexpr IndexType NumPieceTypes = 2;    // white, black
    static constexpr IndexType NumPlanes = NumSquares * NumPieceTypes; // 48

    // Total feature dimensions per perspective
    static constexpr IndexType Dimensions = NumSquares * NumPlanes;     // 24 * 48 = 1152

    // We activate one feature per (anchor, piece) -> at most 24 anchors x 24 pieces = 576
    static constexpr IndexType MaxActiveDimensions = 24 * 24;           // 576

    static IndexType get_dimensions() { return Dimensions; }

    // Build list of active feature indices for current position and perspective
    static void append_active_indices(
      const Position& pos,
      Color perspective,
      ValueListInserter<IndexType> active);

    // For simplicity we force full refreshes. No incremental update list.
    static void append_changed_indices(
      Square ksq,
      StateInfo* st,
      Color perspective,
      ValueListInserter<IndexType> removed,
      ValueListInserter<IndexType> added,
      const Position& pos);

    static int update_cost(StateInfo* st);
    static int refresh_cost(const Position& pos);

    // Always refresh for Nine Men's Morris; we do not track dirty pieces here.
    static bool requires_refresh(StateInfo* st, Color perspective, const Position& pos);
  };

} // namespace Stockfish::Eval::NNUE::Features

#endif // NNUE_FEATURES_NINE_MILL_H_INCLUDED


