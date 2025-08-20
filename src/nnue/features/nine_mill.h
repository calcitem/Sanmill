/*
  NNUE feature set for Nine Men's Morris

  This feature set mirrors ml/nnue-pytorch/features_mill.py (NineMillFeatures):
  - Board has 24 valid points (indices SQ_8..SQ_31 → 0..23 here)
  - Two piece types (white/black stones)
  - Anchored representation: for each anchor (24), encode all piece placements
    in planes of size (2 piece types × 24 positions) → 24 × (2 × 24) = 1152
    input features per perspective
*/

#ifndef NNUE_FEATURES_NINE_MILL_H_INCLUDED
#define NNUE_FEATURES_NINE_MILL_H_INCLUDED

#include "../nnue_common.h"

#include "../../position.h"

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

    // We activate one feature per (anchor, piece) → at most 24 anchors × 24 pieces = 576
    static constexpr IndexType MaxActiveDimensions = 24 * 24;           // 576

    static IndexType get_dimensions() { return Dimensions; }

    // Build list of active feature indices for current position and perspective
    static void append_active_indices(
      const Position& pos,
      Color perspective,
      ValueListInserter<IndexType> active)
    {
      (void)perspective; // Perspective does not change indices for symmetric stones

      // Iterate all board anchors (SQ_8..SQ_31 → 0..23)
      for (Square anchorSq = SQ_BEGIN; anchorSq < SQ_END; ++anchorSq) {
        const IndexType anchor = static_cast<IndexType>(anchorSq - SQ_BEGIN);

        // Enumerate stones on board once and emit per-anchor indices
        for (Square s = SQ_BEGIN; s < SQ_END; ++s) {
          const Piece pc = pos.piece_on(s);
          if (pc == NO_PIECE || pc == MARKED_PIECE) continue;

          const Color c = color_of(pc);
          const IndexType pieceType = (c == WHITE ? 0 : 1); // 0=white,1=black
          const IndexType piecePos = static_cast<IndexType>(s - SQ_BEGIN); // 0..23

          const IndexType idx = anchor * NumPlanes
                               + pieceType * NumSquares
                               + piecePos;
          active.push_back(idx);
        }
      }
    }

    // For simplicity we force full refreshes. No incremental update list.
    static void append_changed_indices(
      Square /*ksq*/,
      StateInfo* /*st*/,
      Color /*perspective*/,
      ValueListInserter<IndexType> /*removed*/,
      ValueListInserter<IndexType> /*added*/,
      const Position& /*pos*/)
    {
      // Intentionally left empty. We will always refresh the accumulator.
    }

    static int update_cost(StateInfo* /*st*/) { return 0; }
    static int refresh_cost(const Position& /*pos*/) { return static_cast<int>(MaxActiveDimensions); }

    // Always refresh for Nine Men's Morris; we do not track dirty pieces here.
    static bool requires_refresh(StateInfo* /*st*/, Color /*perspective*/, const Position& /*pos*/) {
      return true;
    }
  };

} // namespace Stockfish::Eval::NNUE::Features

#endif // NNUE_FEATURES_NINE_MILL_H_INCLUDED


