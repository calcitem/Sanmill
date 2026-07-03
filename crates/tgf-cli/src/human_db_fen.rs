// SPDX-License-Identifier: AGPL-3.0-or-later
// Shared conversion from an NMM_LLM `human_db.sqlite` `state_key` /
// canonical board string to a Mill FEN the Rust engine can load.
//
// Used by both `mill_tune::datagen_human` (eval-tuning sample extraction)
// and `mill_mine::human_seed` (mining frontier seeding), so the
// canonical-board-string <-> engine-node mapping lives in exactly one place.

/// NMM_LLM's canonical 24-character board string order (outer ring, middle
/// ring, inner ring) mapped to this engine's node ids. Mirrors the layout
/// documented in `docs/HUMAN_DATABASE.md`.
const NMM_POSITION_ORDER_NODES: [usize; 24] = [
    23, 16, 17, 18, 19, 20, 21, 22, // outer ring
    15, 8, 9, 10, 11, 12, 13, 14, // middle ring
    7, 0, 1, 2, 3, 4, 5, 6, // inner ring
];

/// Build a Mill FEN from a `human_db.sqlite` `positions.state_key` /
/// `moves.state_key` value
/// (`{canon}|{turn}|{phase}|{placed_w}|{placed_b}|{on_w}|{on_b}`, see
/// `docs/HUMAN_DATABASE.md`). Returns `None` for malformed keys; the human
/// database is external, user-supplied data, so callers should skip rather
/// than panic on a bad row.
pub(crate) fn fen_from_state_key(state_key: &str) -> Option<String> {
    let fields = state_key.split('|').collect::<Vec<_>>();
    if fields.len() < 7 {
        return None;
    }
    let canonical = fields[0];
    if canonical.len() != 24 {
        return None;
    }
    let side = match fields[1] {
        "W" => "w",
        "B" => "b",
        _ => return None,
    };
    let phase = match fields[2] {
        "place" => "p",
        "move" | "fly" => "m",
        _ => return None,
    };
    let action = if phase == "p" { "p" } else { "s" };
    let placed_w = fields[3].parse::<u8>().ok()?;
    let placed_b = fields[4].parse::<u8>().ok()?;
    let on_w = fields[5].parse::<u8>().ok()?;
    let on_b = fields[6].parse::<u8>().ok()?;
    let hand_w = 9_u8.checked_sub(placed_w)?;
    let hand_b = 9_u8.checked_sub(placed_b)?;

    let mut board = ['*'; 24];
    for (nmm_idx, ch) in canonical.chars().enumerate() {
        let node = NMM_POSITION_ORDER_NODES[nmm_idx];
        board[node] = match ch {
            'W' => 'O',
            'B' => '@',
            '.' => '*',
            _ => return None,
        };
    }
    let inner: String = board[0..8].iter().collect();
    let middle: String = board[8..16].iter().collect();
    let outer: String = board[16..24].iter().collect();
    Some(format!(
        "{inner}/{middle}/{outer} {side} {phase} {action} \
         {on_w} {hand_w} {on_b} {hand_b} 0 0 -1 -1 -1 -1 0 0 1 ids:nodes"
    ))
}

/// Deterministic FNV-1a-style hash, used to deduplicate `state_key` strings
/// without keeping the (potentially large) strings themselves around.
pub(crate) fn stable_hash(value: &str) -> u64 {
    let mut hash = 0xcbf2_9ce4_8422_2325_u64;
    for byte in value.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fen_from_state_key_decodes_empty_board() {
        let key = "........................|W|place|0|0|0|0";
        let fen = fen_from_state_key(key).unwrap();
        assert!(fen.starts_with("********/********/********"));
        assert!(fen.contains(" w p p "));
    }

    #[test]
    fn fen_from_state_key_rejects_malformed_keys() {
        assert!(fen_from_state_key("too|few|fields").is_none());
        assert!(fen_from_state_key("short|W|place|0|0|0|0").is_none());
    }

    #[test]
    fn stable_hash_is_deterministic_and_sensitive_to_input() {
        let a = stable_hash("abc");
        let b = stable_hash("abc");
        let c = stable_hash("abd");
        assert_eq!(a, b);
        assert_ne!(a, c);
    }
}
