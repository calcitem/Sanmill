// SPDX-License-Identifier: GPL-3.0-or-later
// nine_mill.cpp - Implementation of NineMill feature helpers

#include "nine_mill.h"

#include "../../position.h"

namespace Stockfish::Eval::NNUE::Features {

  void NineMill::append_active_indices(
      const Position& pos,
      Color perspective,
      ValueListInserter<IndexType> active) {
    (void)perspective; // Perspective does not change indices for symmetric stones

    // Iterate all board anchors (SQ_8..SQ_31 -> 0..23)
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

  void NineMill::append_changed_indices(
      Square /*ksq*/, StateInfo* /*st*/, Color /*perspective*/,
      ValueListInserter<IndexType> /*removed*/,
      ValueListInserter<IndexType> /*added*/,
      const Position& /*pos*/) {
    // We always perform a full refresh for Nine Men's Morris features.
  }

  int NineMill::update_cost(StateInfo* /*st*/) { return 0; }

  int NineMill::refresh_cost(const Position& /*pos*/) {
    return static_cast<int>(MaxActiveDimensions);
  }

  bool NineMill::requires_refresh(StateInfo* /*st*/, Color /*perspective*/, const Position& /*pos*/) {
    // Always refresh for simplicity.
    return true;
  }

} // namespace Stockfish::Eval::NNUE::Features


