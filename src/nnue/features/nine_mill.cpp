// SPDX-License-Identifier: GPL-3.0-or-later
// nine_mill.cpp - Implementation of NineMill feature helpers

#include "nine_mill.h"

#include "../../position.h"
#include <algorithm>

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
      ValueListInserter<IndexType> removed,
      ValueListInserter<IndexType> added,
      const Position& pos) {
    // Delegate to local implementation that inspects the last move.
    // If the move is unsupported for incremental update, the inserters
    // remain empty and the caller will fall back to refresh.
    auto index_for = [](IndexType anchor, IndexType pieceType /*0=white,1=black*/, IndexType piecePos) -> IndexType {
      return anchor * NineMill::NumPlanes + pieceType * NineMill::NumSquares + piecePos;
    };

    const Move m = pos.move;
    if (m == MOVE_NONE)
      return;

    const MoveType mt = type_of(m);
    if (mt == MOVETYPE_REMOVE)
      return; // Force refresh for removals

    if (mt == MOVETYPE_MOVE) {
      const Square from = from_sq(m);
      const Square to   = to_sq(m);

      const Piece pcTo = pos.piece_on(to);
      if (pcTo == NO_PIECE || pcTo == MARKED_PIECE)
        return;

      const IndexType pieceType = (color_of(pcTo) == WHITE ? 0 : 1);
      const IndexType fromIdx   = static_cast<IndexType>(from - SQ_BEGIN);
      const IndexType toIdx     = static_cast<IndexType>(to   - SQ_BEGIN);

      for (IndexType anchor = 0; anchor < NineMill::NumSquares; ++anchor) {
        removed.push_back(index_for(anchor, pieceType, fromIdx));
        added.push_back(index_for(anchor, pieceType, toIdx));
      }
    } else if (mt == MOVETYPE_PLACE) {
      const Square to = to_sq(m);
      const Piece pc  = pos.piece_on(to);
      if (pc == NO_PIECE || pc == MARKED_PIECE)
        return;

      const IndexType pieceType = (color_of(pc) == WHITE ? 0 : 1);
      const IndexType toIdx     = static_cast<IndexType>(to - SQ_BEGIN);

      for (IndexType anchor = 0; anchor < NineMill::NumSquares; ++anchor)
        added.push_back(index_for(anchor, pieceType, toIdx));
    }
  }

  int NineMill::update_cost(StateInfo* /*st*/) {
    // Heuristic: a typical non-capture move toggles two feature columns
    // across all anchors (remove-from and add-to), i.e. ~2 * NumSquares.
    // Returning a small constant encourages incremental updates over refresh.
    return static_cast<int>(2 * NumSquares);
  }

  int NineMill::refresh_cost(const Position& pos) {
    // Estimate active features as (#stones on board) * (#anchors).
    const int totalPieces = pos.piece_on_board_count(WHITE) + pos.piece_on_board_count(BLACK);
    const int estimate = totalPieces * static_cast<int>(NumSquares);
    return std::min(estimate, static_cast<int>(MaxActiveDimensions));
  }

  bool NineMill::requires_refresh(StateInfo* /*st*/, Color /*perspective*/, const Position& /*pos*/) {
    // Always require refresh due to Sanmill's Position architecture being
    // incompatible with Stockfish's StateInfo chain mechanism.
    // This is still much faster than the original implementation because
    // we use dynamic refresh_cost() and proper update_cost() estimates.
    return true;
  }

  // Incremental update helper used by FeatureTransformer.
  // Compute changed feature indices for the last applied move in pos.
  // (helper removed; logic inlined into append_changed_indices above)

} // namespace Stockfish::Eval::NNUE::Features


