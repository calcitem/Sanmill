// SPDX-License-Identifier: GPL-3.0-or-later
// `MillState` setup, encode/decode, recompute, and the small
// `sync_action_state` helper that re-derives `MillState::action` from
// the rest of the snapshot after a transition.

use tgf_core::{GameStateSnapshot, OPAQUE_PAYLOAD_LEN};

use super::{MillActionState, MillOutcomeReason, MillPhase, MillState, MillVariantOptions};

impl MillState {
    pub(super) fn sync_action_after_transition(&mut self) {
        self.action = if self.phase == MillPhase::GameOver {
            MillActionState::GameOver
        } else if self.side_to_move >= 0 && self.pending_removals[self.side_to_move as usize] > 0 {
            MillActionState::Remove
        } else {
            match self.phase {
                MillPhase::Placing | MillPhase::Ready => MillActionState::Place,
                MillPhase::Moving => MillActionState::Select,
                MillPhase::GameOver => MillActionState::GameOver,
            }
        };
    }

    pub(super) fn action_for_legal_generation(&self) -> MillActionState {
        if self.action == MillActionState::Place
            && (self.phase != MillPhase::Placing
                || (self.side_to_move >= 0
                    && self.pending_removals[self.side_to_move as usize] > 0))
        {
            let mut normalized = self.clone();
            normalized.sync_action_after_transition();
            normalized.action
        } else {
            self.action
        }
    }
}

pub(super) fn sync_action_state(state: &mut MillState) {
    state.sync_action_after_transition();
}

impl MillState {
    pub(super) fn encode(self) -> [u8; OPAQUE_PAYLOAD_LEN] {
        let mut payload = [0_u8; OPAQUE_PAYLOAD_LEN];
        for (i, piece) in self.board.iter().enumerate() {
            payload[i] = *piece as u8;
        }
        payload[24] = self.pieces_in_hand[0];
        payload[25] = self.pieces_in_hand[1];
        payload[26] = self.pieces_on_board[0];
        payload[27] = self.pieces_on_board[1];
        payload[28] = self.pending_removals[0];
        payload[29] = self.pending_removals[1];
        payload[30] = self.winner as u8;
        payload[279] = self.action as u8;
        payload[31] = (self.ply_since_capture & 0xff) as u8;
        payload[32] = (self.ply_since_capture >> 8) as u8;
        payload[33] = self.last_mill_from[0] as u8;
        payload[34] = self.last_mill_to[0] as u8;
        payload[35..39].copy_from_slice(&self.used_mill_lines.to_le_bytes());
        payload[39..43].copy_from_slice(&self.delayed_marked_pieces.to_le_bytes());
        payload[43] = self.outcome_reason as u8;
        // 44..=235: serialized key_history window (24 × 8 bytes,
        // little-endian). Runtime history is a Vec capped at 256 to mirror
        // master; snapshots persist the most recent 24 keys for compatibility.
        let start = self.key_history.len().saturating_sub(24);
        let history_window = &self.key_history[start..];
        for (slot_idx, key) in history_window.iter().enumerate() {
            let base = 44 + slot_idx * 8;
            payload[base..base + 8].copy_from_slice(&key.to_le_bytes());
        }
        // 236: serialized key_history_len (clamped to the payload window).
        payload[236] = history_window.len().min(24) as u8;
        payload[237..241].copy_from_slice(&self.custodian_targets[0].to_le_bytes());
        payload[241..245].copy_from_slice(&self.intervention_targets[0].to_le_bytes());
        payload[245..249].copy_from_slice(&self.leap_targets[0].to_le_bytes());
        payload[249] = self.custodian_count[0];
        payload[250] = self.intervention_count[0];
        payload[251] = self.leap_count[0];
        // Pack loose bool flags into a single byte (bits 0-5).
        let flags: u8 = u8::from(self.mill_available_at_removal)
            | (u8::from(self.stalemate_removing) << 1)
            | (u8::from(self.both_stalemate_removing) << 2)
            | (u8::from(self.remove_own_piece[0]) << 3)
            | (u8::from(self.remove_own_piece[1]) << 4)
            | (u8::from(self.board_full_removing) << 5);
        payload[252] = flags;
        payload[253] = self.last_mill_from[1] as u8;
        payload[254] = self.last_mill_to[1] as u8;
        payload[255] = self.preferred_remove_target as u8;
        // 256..263: per-side `formed_mills_bb` (matches legacy
        // Position::formedMillsBB[c]).  Each side stores a 24-bit
        // little-endian square bitmap.  Aligned so byte 256/260 starts
        // a fresh 4-byte slot in the extended 320-byte payload.
        payload[256..260].copy_from_slice(&self.formed_mills_bb[0].to_le_bytes());
        payload[260..264].copy_from_slice(&self.formed_mills_bb[1].to_le_bytes());
        payload[264..268].copy_from_slice(&self.custodian_targets[1].to_le_bytes());
        payload[268..272].copy_from_slice(&self.intervention_targets[1].to_le_bytes());
        payload[272..276].copy_from_slice(&self.leap_targets[1].to_le_bytes());
        payload[276] = self.custodian_count[1];
        payload[277] = self.intervention_count[1];
        payload[278] = self.leap_count[1];
        payload
    }

    pub(super) fn decode(snapshot: &GameStateSnapshot) -> Self {
        let payload = snapshot.opaque_payload;
        let mut board = [0_i8; 24];
        for (i, slot) in board.iter_mut().enumerate() {
            *slot = payload[i] as i8;
        }
        let history_len = usize::from(payload[236].min(24));
        let mut key_history = Vec::with_capacity(history_len);
        for slot_idx in 0..history_len {
            let base = 44 + slot_idx * 8;
            let mut bytes = [0_u8; 8];
            bytes.copy_from_slice(&payload[base..base + 8]);
            key_history.push(u64::from_le_bytes(bytes));
        }
        let read_u32 = |offset: usize| {
            let mut bytes = [0_u8; 4];
            bytes.copy_from_slice(&payload[offset..offset + 4]);
            u32::from_le_bytes(bytes)
        };
        Self {
            board,
            side_to_move: snapshot.side_to_move,
            phase: match snapshot.phase_tag {
                x if x == MillPhase::Ready as i16 => MillPhase::Ready,
                x if x == MillPhase::Moving as i16 => MillPhase::Moving,
                x if x == MillPhase::GameOver as i16 => MillPhase::GameOver,
                _ => MillPhase::Placing,
            },
            move_number: snapshot.move_number,
            pieces_in_hand: [payload[24], payload[25]],
            pieces_on_board: [payload[26], payload[27]],
            pending_removals: [payload[28], payload[29]],
            winner: payload[30] as i8,
            action: MillActionState::from_payload(payload[279]),
            ply_since_capture: u16::from(payload[31]) | (u16::from(payload[32]) << 8),
            last_mill_from: [payload[33] as i8, payload[253] as i8],
            last_mill_to: [payload[34] as i8, payload[254] as i8],
            used_mill_lines: read_u32(35),
            delayed_marked_pieces: read_u32(39),
            outcome_reason: match payload[43] {
                x if x == MillOutcomeReason::LoseFewerThanThree as u8 => {
                    MillOutcomeReason::LoseFewerThanThree
                }
                x if x == MillOutcomeReason::DrawNMoveRule as u8 => {
                    MillOutcomeReason::DrawNMoveRule
                }
                x if x == MillOutcomeReason::DrawFullBoard as u8 => {
                    MillOutcomeReason::DrawFullBoard
                }
                x if x == MillOutcomeReason::LoseFullBoard as u8 => {
                    MillOutcomeReason::LoseFullBoard
                }
                x if x == MillOutcomeReason::DrawThreefold as u8 => {
                    MillOutcomeReason::DrawThreefold
                }
                x if x == MillOutcomeReason::LoseNoLegalMoves as u8 => {
                    MillOutcomeReason::LoseNoLegalMoves
                }
                x if x == MillOutcomeReason::DrawStalemate as u8 => {
                    MillOutcomeReason::DrawStalemate
                }
                x if x == MillOutcomeReason::DrawFiftyMove as u8 => {
                    MillOutcomeReason::DrawFiftyMove
                }
                x if x == MillOutcomeReason::DrawEndgameFiftyMove as u8 => {
                    MillOutcomeReason::DrawEndgameFiftyMove
                }
                _ => MillOutcomeReason::Ongoing,
            },
            key_history,
            key_history_len: history_len,
            custodian_targets: [read_u32(237), read_u32(264)],
            intervention_targets: [read_u32(241), read_u32(268)],
            leap_targets: [read_u32(245), read_u32(272)],
            custodian_count: [payload[249], payload[276]],
            intervention_count: [payload[250], payload[277]],
            leap_count: [payload[251], payload[278]],
            mill_available_at_removal: (payload[252] & 0x01) != 0,
            stalemate_removing: (payload[252] & 0x02) != 0,
            both_stalemate_removing: (payload[252] & 0x04) != 0,
            remove_own_piece: [(payload[252] & 0x08) != 0, (payload[252] & 0x10) != 0],
            board_full_removing: (payload[252] & 0x20) != 0,
            preferred_remove_target: payload[255] as i8,
            formed_mills_bb: [read_u32(256), read_u32(260)],
        }
    }
}

// ---------------------------------------------------------------------------
// Setup-position editing API
// ---------------------------------------------------------------------------

impl MillState {
    /// Build an empty board ready for setup-position editing.
    ///
    /// `pieces_in_hand` is initialised from `options.piece_count` (matching
    /// the freshly-constructed placing-phase state), so `recompute_aux` is
    /// not needed after `empty()` alone — only after piece edits.
    pub fn empty(options: &MillVariantOptions) -> Self {
        Self {
            pieces_in_hand: [options.piece_count, options.piece_count],
            ..Self::default()
        }
    }

    /// Place or clear one piece at `node`.
    ///
    /// `owner`: `1` = first player (White), `2` = second player (Black),
    /// anything else = clear.  Callers must follow up with `recompute_aux`
    /// before encoding the snapshot.
    pub fn set_piece(&mut self, node: u16, owner: i8) {
        if let Some(slot) = self.board.get_mut(node as usize) {
            *slot = if owner == 1 || owner == 2 { owner } else { 0 };
        }
    }

    pub fn set_side_to_move(&mut self, side: i8) {
        self.side_to_move = if side == 0 || side == 1 { side } else { 0 };
    }

    pub fn set_phase(&mut self, phase: MillPhase) {
        self.phase = phase;
    }

    pub fn phase(&self) -> MillPhase {
        self.phase
    }

    pub fn pieces_on_board(&self) -> [u8; 2] {
        self.pieces_on_board
    }

    /// Per-side pieces still in hand, indexed by side (0 = white, 1 = black).
    /// Mirrors `Position::pieceInHandCount[c]` in the legacy C++ engine.
    pub fn pieces_in_hand(&self) -> [u8; 2] {
        self.pieces_in_hand
    }

    /// Set the winner field directly.  Used by setup-position tools that
    /// need to mark an immediate-GameOver position (e.g. fewer than
    /// pieces_at_least_count pieces after `setup_finish`).
    pub fn set_winner(&mut self, winner: i8) {
        self.winner = winner;
        self.side_to_move = -1;
    }

    /// Mark the position as lost due to too few pieces (mirrors C++
    /// `GameOverReason::loseFewerThanThree`).  Only valid to call after
    /// `set_phase(GameOver)`.
    pub fn set_outcome_reason_fewer_than_threshold(&mut self) {
        self.outcome_reason = MillOutcomeReason::LoseFewerThanThree;
    }

    /// Check whether either side has fewer than `options.pieces_at_least_count`
    /// pieces on board (only meaningful after both hands are empty).  Returns
    /// `Some(winner)` where winner is the side that still has enough pieces,
    /// or `None` if neither side is below the threshold.  When BOTH sides are
    /// short the side with more pieces on board wins; in a tie, black (1) wins.
    /// Used by `setup_finish` to detect immediate-GameOver positions.
    pub fn check_pieces_at_least(&self, options: &MillVariantOptions) -> Option<i8> {
        let min = options.pieces_at_least_count;
        let w_short = self.pieces_on_board[0] < min;
        let b_short = self.pieces_on_board[1] < min;
        if !w_short && !b_short {
            return None;
        }
        // The side with more pieces wins; if equal, black (1) wins by convention.
        let winner = if self.pieces_on_board[0] >= self.pieces_on_board[1] {
            0_i8 // white wins
        } else {
            1_i8 // black wins
        };
        Some(winner)
    }

    pub fn set_pending_removal(&mut self, side_idx: usize, count: u8) {
        if side_idx < 2 {
            self.pending_removals[side_idx] = count;
        }
    }

    /// Recompute auxiliary fields from the board array so the snapshot is
    /// self-consistent after a series of `set_piece` calls.
    ///
    /// Updates: `pieces_on_board`, `pieces_in_hand` (clamped to piece_count),
    /// `winner` (reset to -1), `outcome_reason`, `key_history`, and clears
    /// all capture-target bitmasks.
    pub fn recompute_aux(&mut self, options: &MillVariantOptions) {
        let mut on_board = [0u8; 2];
        for &piece in &self.board {
            if piece == 1 {
                on_board[0] += 1;
            } else if piece == 2 {
                on_board[1] += 1;
            }
        }
        self.pieces_on_board = on_board;
        self.pieces_in_hand = [
            options.piece_count.saturating_sub(on_board[0]),
            options.piece_count.saturating_sub(on_board[1]),
        ];
        self.winner = -1;
        self.outcome_reason = MillOutcomeReason::Ongoing;
        self.ply_since_capture = 0;
        self.last_mill_from = [-1, -1];
        self.last_mill_to = [-1, -1];
        self.used_mill_lines = 0;
        self.delayed_marked_pieces = 0;
        self.formed_mills_bb = [0, 0];
        self.custodian_targets = [0, 0];
        self.intervention_targets = [0, 0];
        self.leap_targets = [0, 0];
        self.custodian_count = [0, 0];
        self.intervention_count = [0, 0];
        self.leap_count = [0, 0];
        self.preferred_remove_target = -1;
        self.mill_available_at_removal = false;
        self.stalemate_removing = false;
        self.both_stalemate_removing = false;
        self.remove_own_piece = [false, false];
        self.key_history.clear();
        self.key_history_len = 0;
    }
}
