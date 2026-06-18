// SPDX-License-Identifier: GPL-3.0-or-later
// `MillRules` setup-position editing API plus FEN import/export.
// These methods drive the FRB kernel's setup flow and the legacy
// position-FEN round-trip.

use tgf_core::GameStateSnapshot;

use super::fen::{append_capture_field, parse_capture_field};
use super::legacy_squares::{
    legacy_square_bb_to_node_bb, legacy_square_to_node_signed, node_bb_to_legacy_square_bb,
    node_to_legacy_square,
};
use super::transitions::is_marked;
use super::{MillActionState, MillPhase, MillRules, MillState, node_bit, recompute_mobility_diff};

// MillRules setup-position helpers (used by the FRB kernel API)
// ---------------------------------------------------------------------------

impl MillRules {
    /// Return a fresh setup-editing state backed by this rule set's options.
    pub fn setup_empty(&self) -> MillState {
        MillState::empty(&self.options)
    }

    /// Encode an externally-edited `MillState` into a `GameStateSnapshot`
    /// suitable for `GameKernel::replace_state`.
    pub fn encode_state(&self, state: MillState) -> GameStateSnapshot {
        self.encode(state)
    }

    /// Parse a Mill FEN string (compatible with the legacy Dart/C++ engine)
    /// and return the resulting `MillState`.
    ///
    /// FEN format (17+ whitespace-separated fields):
    /// `<board> <side> <phase> <act> <w_on> <w_hand> <b_on> <b_hand>
    ///  <w_remove> <b_remove> <w_from> <w_to> <b_from> <b_to>
    ///  <mills_mask> <rule50> <fullmove>`
    ///
    /// `board` = `inner8/middle8/outer8`; pieces: `O`=white, `@`=black, `*`=empty.
    ///
    /// Mills-bitmask and last-mill-from/to fields are parsed but ignored; the
    /// returned state has those auxiliary fields at their defaults so that
    /// `encode_state` + `decode_snapshot` round-trips cleanly.
    pub fn set_from_fen(&self, fen: &str) -> Result<MillState, String> {
        let trimmed = fen.trim();
        // Split FEN into the 17 mandatory whitespace-separated fields plus
        // an optional trailing extension block that holds c:/i:/l:/p:/s:
        // tokens introduced for custodian/intervention/leap captures and
        // the preferred-remove / stalemate flags.
        let mut all_fields: Vec<&str> = trimmed.split_whitespace().collect();
        if all_fields.len() < 17 {
            return Err(format!("FEN needs >= 17 fields, got {}", all_fields.len()));
        }
        let extension_tokens: Vec<&str> = all_fields.split_off(17);
        let fields = all_fields;

        // FEN board position index -> Rust board node index.
        // FEN position i corresponds to legacy square (i + 8), then uses
        // the same fixed legacySquareToNode permutation as Flutter's
        // MillBoardCoordinateMaps.  This is not a simple reversed range.
        const FEN_TO_NODE: [usize; 24] = [
            17, 18, 19, 20, 21, 22, 23, 16, 9, 10, 11, 12, 13, 14, 15, 8, 1, 2, 3, 4, 5, 6, 7, 0,
        ];

        let board_str = fields[0];
        let ranks: Vec<&str> = board_str.split('/').collect();
        if ranks.len() != 3 || ranks.iter().any(|r| r.len() != 8) {
            return Err("FEN board must be three 8-character ranks separated by '/'".to_owned());
        }
        let all_chars: String = ranks.join("");
        let mut board = [0_i8; 24];
        let mut delayed_marked_pieces = 0_u32;
        for (i, c) in all_chars.chars().enumerate() {
            let node = FEN_TO_NODE[i];
            board[node] = if c == 'O' {
                1
            } else if c == '@' {
                2
            } else if c == '*' {
                0
            } else if c == 'X' {
                // MARKED_PIECE in the legacy engine: keep it on the board
                // visually but flag the square so live_piece treats it as
                // empty (matches Position::set_fen handling).
                delayed_marked_pieces |= node_bit(node);
                0
            } else {
                return Err(format!("unexpected piece character '{c}' in FEN"));
            };
        }

        let side_to_move: i8 = match fields[1] {
            "w" => 0,
            "b" => 1,
            s => return Err(format!("invalid side '{s}' in FEN")),
        };

        // Accept every phase token Position::fen emits.  Both 'r' (ready)
        // and 'n' (none) share the placing-phase semantics in Rust because
        // MillPhase has no separate Ready/None variants.
        let phase = match fields[2] {
            "r" | "p" | "n" => MillPhase::Placing,
            "m" => MillPhase::Moving,
            "o" => MillPhase::GameOver,
            s => return Err(format!("invalid phase '{s}' in FEN")),
        };
        // Mirror master src/position.cpp:set FEN action parsing: phase and
        // action are independent tokens in legacy FEN.
        if fields[3].len() != 1 {
            return Err(format!("invalid action token '{}' in FEN", fields[3]));
        }
        let fen_action = MillActionState::from_fen_token(fields[3]);
        let action_is_remove = fen_action == MillActionState::Remove;

        let parse_u8 = |s: &str| -> Result<u8, String> {
            s.parse::<u8>()
                .map_err(|_| format!("cannot parse '{s}' as u8"))
        };
        let parse_i8 = |s: &str| -> Result<i8, String> {
            s.parse::<i8>()
                .map_err(|_| format!("cannot parse '{s}' as i8"))
        };
        let parse_u16 = |s: &str| -> Result<u16, String> {
            s.parse::<u16>()
                .map_err(|_| format!("cannot parse '{s}' as u16"))
        };

        let on_board_w = parse_u8(fields[4])?;
        let in_hand_w = parse_u8(fields[5])?;
        let on_board_b = parse_u8(fields[6])?;
        let in_hand_b = parse_u8(fields[7])?;
        // pieceToRemoveCount[c] is signed in the legacy engine: a negative
        // value flags "remove your own piece" (RemovalBasedOnMillCounts
        // double-zero branch).  Rust models the sign via remove_own_piece
        // and stores the absolute count.
        let signed_remove_w = parse_i8(fields[8])?;
        let signed_remove_b = parse_i8(fields[9])?;
        let remove_w = signed_remove_w.unsigned_abs();
        let remove_b = signed_remove_b.unsigned_abs();
        let remove_own = [signed_remove_w < 0, signed_remove_b < 0];

        // Fields 10..14: last-mill from/to per side.  Master stores them as
        // legacy Square ids; 0 means "none".
        let last_w_from_sq = parse_u8(fields[10])?;
        let last_w_to_sq = parse_u8(fields[11])?;
        let last_b_from_sq = parse_u8(fields[12])?;
        let last_b_to_sq = parse_u8(fields[13])?;
        let last_mill_from = [
            legacy_square_to_node_signed(last_w_from_sq),
            legacy_square_to_node_signed(last_b_from_sq),
        ];
        let last_mill_to = [
            legacy_square_to_node_signed(last_w_to_sq),
            legacy_square_to_node_signed(last_b_to_sq),
        ];

        // Field 14: 64-bit formedMillsBB with per-side per-square mill
        // bitmaps.  Layout matches Position::fen():
        //   ((white_bb_24bits) << 32) | black_bb_24bits
        // The legacy engine uses 32-bit Bitboard slots even though only
        // bits 8..32 are populated (legacy Square ids).  Translate each
        // side's square bitmap from legacy ids into Rust dense node ids
        // before storing.
        let formed_mills_bb_raw = fields[14].parse::<u64>().unwrap_or(0);
        let formed_white_legacy_bb = ((formed_mills_bb_raw >> 32) & 0xFFFF_FFFF) as u32;
        let formed_black_legacy_bb = (formed_mills_bb_raw & 0xFFFF_FFFF) as u32;
        let formed_mills_bb = [
            legacy_square_bb_to_node_bb(formed_white_legacy_bb),
            legacy_square_bb_to_node_bb(formed_black_legacy_bb),
        ];

        let rule50 = parse_u16(fields[15])?;
        let full_move: i32 = fields[16].parse::<i32>().unwrap_or(1).max(1);

        // Reconstruct game ply (move_number) from full-move counter, matching
        // the Dart Position.setFen formula:
        //   gamePly = max(2*(fullMove-1), 0) + (side==black ? 1 : 0)
        let side_is_black = i16::from(side_to_move == 1);
        let move_number = (2_i32 * (full_move - 1)).max(0) as i16 + side_is_black;

        // Trailing extension tokens: c:/i:/l:/p:/s:.
        let mut custodian_targets = [0_u32; 2];
        let mut custodian_count = [0_u8; 2];
        let mut intervention_targets = [0_u32; 2];
        let mut intervention_count = [0_u8; 2];
        let mut leap_targets = [0_u32; 2];
        let mut leap_count = [0_u8; 2];
        let mut stalemate_removing = false;
        let mut both_stalemate_removing = false;
        let mut preferred_remove_target: i8 = -1;
        for token in &extension_tokens {
            if token.len() < 2 || token.as_bytes()[1] != b':' {
                continue;
            }
            let value = &token[2..];
            match token.as_bytes()[0] {
                b'c' => parse_capture_field(value, &mut custodian_targets, &mut custodian_count),
                b'i' => {
                    parse_capture_field(value, &mut intervention_targets, &mut intervention_count)
                }
                b'l' => parse_capture_field(value, &mut leap_targets, &mut leap_count),
                b'p' => {
                    // Mirror Position::set_fen: parse `p:NN` (legacy
                    // Square id) into preferred_remove_target as a Rust
                    // dense node id (or -1 for SQ_NONE / out of range).
                    if let Ok(legacy_sq) = value.parse::<i32>()
                        && (8..32).contains(&legacy_sq)
                    {
                        preferred_remove_target = legacy_square_to_node_signed(legacy_sq as u8);
                    }
                }
                b's' => {
                    if let Ok(flag) = value.parse::<i32>() {
                        stalemate_removing = flag == 1;
                        both_stalemate_removing = flag == 2;
                    }
                }
                _ => {}
            }
        }

        // P0-E.1: If the action token is 'r' (remove) but the piece-to-remove
        // count for the active side is 0, infer a single pending removal.  This
        // handles FENs where the action token is the authoritative source for
        // the next expected action (matching master's Action::remove semantics).
        let side_usize = side_to_move as usize;
        let (final_remove_w, final_remove_b) = if action_is_remove
            && remove_w == 0
            && remove_b == 0
            && custodian_count[side_usize] == 0
            && intervention_count[side_usize] == 0
            && leap_count[side_usize] == 0
        {
            if side_usize == 0 {
                (1_u8, 0_u8)
            } else {
                (0_u8, 1_u8)
            }
        } else {
            (remove_w, remove_b)
        };

        let mut state = MillState {
            board,
            side_to_move,
            phase,
            move_number,
            pieces_on_board: [on_board_w, on_board_b],
            pieces_in_hand: [in_hand_w, in_hand_b],
            pending_removals: [final_remove_w, final_remove_b],
            remove_own_piece: remove_own,
            ply_since_capture: rule50,
            last_mill_from,
            last_mill_to,
            delayed_marked_pieces,
            custodian_targets,
            custodian_count,
            intervention_targets,
            intervention_count,
            leap_targets,
            leap_count,
            stalemate_removing,
            both_stalemate_removing,
            action: fen_action,
            mill_available_at_removal: (final_remove_w > 0 || final_remove_b > 0)
                && !(custodian_count[side_usize] > 0
                    || intervention_count[side_usize] > 0
                    || leap_count[side_usize] > 0),
            formed_mills_bb,
            preferred_remove_target,
            winner: -1,
            ..MillState::default()
        };
        recompute_mobility_diff(&mut state, &self.options);
        // Mirror master src/position.cpp:2069 Position::check_if_game_is_over:
        // importing a FEN immediately runs the same terminal checks as a
        // freshly reached position.  Game-over FENs keep their encoded phase
        // untouched because the FEN format does not carry a winner token.
        if state.phase != MillPhase::GameOver {
            self.check_if_game_is_over(&mut state);
        }
        Ok(state)
    }

    /// Serialize a `MillState` into a Mill FEN string compatible with the
    /// legacy Dart/C++ engine.
    ///
    /// Output covers every parsed field: board layout (with 'X' for
    /// marked pieces), side-to-move, phase ('r/p/m/o'), action token
    /// (`p`/`s`/`r`/`?` matching `Position::fen`), piece-on-board /
    /// piece-in-hand / piece-to-remove counts (negative when
    /// `remove_own_piece` is set), per-side last-mill from/to, the
    /// mills bitmask placeholder (always `0` because Rust tracks
    /// per-line use rather than per-square), rule50, full-move number,
    /// and the trailing `c:/i:/l:/p:/s:` extension block when active.
    pub fn export_fen(&self, state: &MillState) -> String {
        // Rust board node index → FEN board position index (inverse of FEN_TO_NODE).
        const NODE_TO_FEN_POS: [usize; 24] = [
            23, 16, 17, 18, 19, 20, 21, 22, 15, 8, 9, 10, 11, 12, 13, 14, 7, 0, 1, 2, 3, 4, 5, 6,
        ];

        let mut fenchars = [b'*'; 26];
        fenchars[8] = b'/';
        fenchars[17] = b'/';
        for (node, &pos) in NODE_TO_FEN_POS.iter().enumerate() {
            let slot = if pos < 8 {
                pos
            } else if pos < 16 {
                pos + 1
            } else {
                pos + 2
            };
            fenchars[slot] = if is_marked(state, node) {
                b'X'
            } else {
                match state.board[node] {
                    1 => b'O',
                    2 => b'@',
                    _ => b'*',
                }
            };
        }
        let board_str = std::str::from_utf8(&fenchars).unwrap_or("????????/????????/????????");

        let side = if state.side_to_move == 1 { 'b' } else { 'w' };
        let phase = match state.phase {
            MillPhase::Placing => 'p',
            MillPhase::Moving => 'm',
            MillPhase::GameOver => 'o',
            MillPhase::Ready => 'r',
        };
        let side_is_black = i32::from(state.side_to_move == 1);
        let full_move = (1 + (i32::from(state.move_number) - side_is_black) / 2).max(1);

        let action_token = state.action.to_fen_token();

        // Encode signed pieceToRemoveCount mirroring legacy semantics.
        let signed_remove = |idx: usize| -> i32 {
            let abs = i32::from(state.pending_removals[idx]);
            if state.remove_own_piece[idx] {
                -abs
            } else {
                abs
            }
        };

        // Field 14: legacy formedMillsBB packed as
        //   ((white_legacy_bb_24bit) << 32) | black_legacy_bb_24bit
        // Translate per-side dense node bitmaps back to legacy square
        // bitmaps so master-style Position::set_fen can re-load them.
        let formed_white_legacy = u64::from(node_bb_to_legacy_square_bb(state.formed_mills_bb[0]));
        let formed_black_legacy = u64::from(node_bb_to_legacy_square_bb(state.formed_mills_bb[1]));
        let formed_mills_field = (formed_white_legacy << 32) | formed_black_legacy;

        let mut out = format!(
            "{} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {}",
            board_str,
            side,
            phase,
            action_token,
            state.pieces_on_board[0],
            state.pieces_in_hand[0],
            state.pieces_on_board[1],
            state.pieces_in_hand[1],
            signed_remove(0),
            signed_remove(1),
            node_to_legacy_square(state.last_mill_from[0]),
            node_to_legacy_square(state.last_mill_to[0]),
            node_to_legacy_square(state.last_mill_from[1]),
            node_to_legacy_square(state.last_mill_to[1]),
            formed_mills_field,
            state.ply_since_capture,
            full_move,
        );

        // Trailing extension fields.  Rust keeps single (active-side)
        // capture-state bitmaps because the legacy engine only ever
        // populates the side currently owing the removal; attribute the
        // payload to whichever colour is to move.
        append_capture_field(
            &mut out,
            'c',
            state.custodian_targets,
            state.custodian_count,
        );
        append_capture_field(
            &mut out,
            'i',
            state.intervention_targets,
            state.intervention_count,
        );
        append_capture_field(&mut out, 'l', state.leap_targets, state.leap_count);
        if state.preferred_remove_target >= 0 {
            out.push_str(&format!(
                " p:{}",
                node_to_legacy_square(state.preferred_remove_target)
            ));
        }
        if state.stalemate_removing {
            out.push_str(" s:1");
        } else if state.both_stalemate_removing {
            out.push_str(" s:2");
        }
        out
    }
}
