// SPDX-License-Identifier: GPL-3.0-or-later
// Mill Zobrist hash tables.
//
// Mirrors master `src/position.cpp:25-37 namespace Zobrist`:
//
//   constexpr int KEY_MISC_BIT = 2;
//   Key psq[PIECE_TYPE_NB][SQUARE_EXT_NB];
//   Key side;
//   Key custodianTarget[COLOR_NB][SQUARE_EXT_NB];
//   Key custodianCount[COLOR_NB][5];
//   Key interventionTarget[COLOR_NB][SQUARE_EXT_NB];
//   Key interventionCount[COLOR_NB][9];
//   Key leapTarget[COLOR_NB][SQUARE_EXT_NB];
//   Key leapCount[COLOR_NB][2];
//
// Differences from master:
//   * Rust stores compact node ids `0..24`, where `node = legacy SQ - 8`.
//     This keeps TT key generation aligned with C++ `SQ_8..SQ_31` while
//     avoiding sparse runtime arrays.
//   * `Key` is u64 internally to match the rest of `tgf-core`'s API, but the
//     generated values occupy only master's low 32-bit key space.
//   * KEY_MISC_BIT semantics match: the top 2 bits of the final key hold the
//     cached value from master `update_key_misc()`.  That value is not
//     recomputed when `set_side_to_move()` flips the side bit, so it is stored
//     explicitly in the spare bits of `MillStateFlags`.

use super::{MillPhase, MillState};

/// Number of high bits reserved for the MISC counter (piece-to-remove
/// count for the side to move).  Mirrors master `Zobrist::KEY_MISC_BIT`.
pub(crate) const KEY_MISC_BIT: u32 = 2;

/// Number of board nodes in the compact master-normalized Mill encoding.
const NODE_COUNT: usize = 24;

/// Number of piece types: empty, white, black, marked.
const PIECE_TYPES: usize = 4;

/// Maximum custodian removal value tracked by the misc counter
/// (master `kMaxCustodianRemoval = 4`).
const MAX_CUSTODIAN: usize = 5;

/// Maximum intervention removal value tracked by the misc counter
/// (master `kMaxInterventionRemoval = 8`).
const MAX_INTERVENTION: usize = 9;

/// Master `Zobrist::leapCount[COLOR_NB][2]`.
const MAX_LEAP: usize = 2;

#[derive(Clone, Copy, Debug)]
pub(crate) struct MillZobrist {
    /// `psq[piece_type][square]`: 0 = empty (unused), 1 = white,
    /// 2 = black, 3 = marked.
    pub psq: [[u64; NODE_COUNT]; PIECE_TYPES],
    pub side: u64,
    pub custodian_target: [[u64; NODE_COUNT]; 2],
    pub custodian_count: [[u64; MAX_CUSTODIAN]; 2],
    pub intervention_target: [[u64; NODE_COUNT]; 2],
    pub intervention_count: [[u64; MAX_INTERVENTION]; 2],
    pub leap_target: [[u64; NODE_COUNT]; 2],
    pub leap_count: [[u64; MAX_LEAP]; 2],
}

/// Master `Position::init` seed.
const SEED: u64 = 1_070_372;

/// Generate the Zobrist table at compile time so the values live in
/// `.rodata` and stay deterministic across runs.
const fn build_zobrist() -> MillZobrist {
    let mut state = SEED;

    macro_rules! next {
        () => {{
            state = next_prng_state(state);
            key_from_prng_state(state)
        }};
    }

    let mut psq = [[0_u64; NODE_COUNT]; PIECE_TYPES];
    let mut p = 0;
    while p < PIECE_TYPES {
        let mut node = 0;
        while node < NODE_COUNT {
            psq[p][node] = next!();
            node += 1;
        }
        p += 1;
    }

    let mut custodian_target = [[0_u64; NODE_COUNT]; 2];
    let mut custodian_count = [[0_u64; MAX_CUSTODIAN]; 2];
    let mut intervention_target = [[0_u64; NODE_COUNT]; 2];
    let mut intervention_count = [[0_u64; MAX_INTERVENTION]; 2];
    let mut leap_target = [[0_u64; NODE_COUNT]; 2];
    let mut leap_count = [[0_u64; MAX_LEAP]; 2];

    let mut c = 0;
    while c < 2 {
        let mut node = 0;
        while node < NODE_COUNT {
            custodian_target[c][node] = next!();
            node += 1;
        }
        let mut i = 0;
        while i < MAX_CUSTODIAN {
            custodian_count[c][i] = next!();
            i += 1;
        }

        let mut node = 0;
        while node < NODE_COUNT {
            intervention_target[c][node] = next!();
            node += 1;
        }
        let mut i = 0;
        while i < MAX_INTERVENTION {
            intervention_count[c][i] = next!();
            i += 1;
        }

        let mut node = 0;
        while node < NODE_COUNT {
            leap_target[c][node] = next!();
            node += 1;
        }
        let mut i = 0;
        while i < MAX_LEAP {
            leap_count[c][i] = next!();
            i += 1;
        }

        c += 1;
    }

    let side = next!();

    MillZobrist {
        psq,
        side,
        custodian_target,
        custodian_count,
        intervention_target,
        intervention_count,
        leap_target,
        leap_count,
    }
}

const fn next_prng_state(state: u64) -> u64 {
    let mut x = state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    x
}

const fn key_from_prng_state(state: u64) -> u64 {
    (state.wrapping_mul(2_685_821_657_736_338_717) as u32 & 0x3fff_ffff) as u64
}

/// Static Zobrist tables consumed by `position_key` and the
/// incremental-update helpers in [`crate::rules`].
pub(crate) static MILL_ZOBRIST: MillZobrist = build_zobrist();

/// Strip the top KEY_MISC_BIT bits and OR in the supplied count.
/// Mirrors master `update_key_misc` (src/position.cpp).
#[inline]
pub(crate) fn apply_misc(mut key: u64, count: u64) -> u64 {
    let shift = u32::BITS - KEY_MISC_BIT;
    key &= (1_u64 << shift) - 1;
    key |= (count & ((1_u64 << KEY_MISC_BIT) - 1)) << shift;
    key
}

/// Compute the full Zobrist key from scratch.  Used to initialise
/// `MillState::zobrist_key` and as the slow-path fallback in tests.
pub(crate) fn full_state_key(state: &MillState) -> u64 {
    let mut key = 0_u64;

    // Piece-square contribution: 1 = white, 2 = black on each square.
    for s in 0..NODE_COUNT {
        let pt = match state.board[s] {
            1 => 1,
            2 => 2,
            _ => continue,
        };
        key ^= MILL_ZOBRIST.psq[pt][s];
    }

    // Marked-piece contribution (delayed-remove squares).
    let mut marked = state.delayed_marked_pieces;
    while marked != 0 {
        let s = marked.trailing_zeros() as usize;
        if s < NODE_COUNT {
            key ^= MILL_ZOBRIST.psq[3][s];
        }
        marked &= marked - 1;
    }

    // Side-to-move.
    if state.side_to_move == 1 {
        key ^= MILL_ZOBRIST.side;
    }

    // Capture states (custodian / intervention / leap).
    for c in 0..2 {
        let mut targets = state.custodian_targets[c];
        while targets != 0 {
            let s = targets.trailing_zeros() as usize;
            if s < NODE_COUNT {
                key ^= MILL_ZOBRIST.custodian_target[c][s];
            }
            targets &= targets - 1;
        }
        let count = (state.custodian_count[c] as usize).min(MAX_CUSTODIAN - 1);
        if count != 0 {
            key ^= MILL_ZOBRIST.custodian_count[c][count];
        }

        let mut targets = state.intervention_targets[c];
        while targets != 0 {
            let s = targets.trailing_zeros() as usize;
            if s < NODE_COUNT {
                key ^= MILL_ZOBRIST.intervention_target[c][s];
            }
            targets &= targets - 1;
        }
        let count = (state.intervention_count[c] as usize).min(MAX_INTERVENTION - 1);
        if count != 0 {
            key ^= MILL_ZOBRIST.intervention_count[c][count];
        }

        let mut targets = state.leap_targets[c];
        while targets != 0 {
            let s = targets.trailing_zeros() as usize;
            if s < NODE_COUNT {
                key ^= MILL_ZOBRIST.leap_target[c][s];
            }
            targets &= targets - 1;
        }
        let count = (state.leap_count[c] as usize).min(MAX_LEAP - 1);
        if count != 0 {
            key ^= MILL_ZOBRIST.leap_count[c][count];
        }
    }

    // Misc counter: cached master `update_key_misc()` value.  Do not derive it
    // from the current side here; master leaves these bits stale across
    // `set_side_to_move()` and search parity depends on preserving that cache.
    let count = if state.phase != MillPhase::GameOver {
        u64::from(state.flags.zobrist_misc_count())
    } else {
        0
    };
    apply_misc(key, count)
}

/// Snapshot of the `MillState` fields that contribute to the Zobrist key,
/// captured *before* `MillRules::apply_to_state` mutates the state so the
/// post-apply key can be derived incrementally via [`key_after_apply`].
#[derive(Clone, Copy)]
pub(crate) struct ZobristInputs {
    board: [i8; NODE_COUNT],
    side_to_move: i8,
    delayed_marked_pieces: u32,
    custodian_targets: [u32; 2],
    custodian_count: [u8; 2],
    intervention_targets: [u32; 2],
    intervention_count: [u8; 2],
    leap_targets: [u32; 2],
    leap_count: [u8; 2],
}

impl ZobristInputs {
    #[inline]
    pub(crate) fn capture(state: &MillState) -> Self {
        Self {
            board: state.board,
            side_to_move: state.side_to_move,
            delayed_marked_pieces: state.delayed_marked_pieces,
            custodian_targets: state.custodian_targets,
            custodian_count: state.custodian_count,
            intervention_targets: state.intervention_targets,
            intervention_count: state.intervention_count,
            leap_targets: state.leap_targets,
            leap_count: state.leap_count,
        }
    }
}

/// XOR delta of a capture-target bitmap contribution between two states.
#[inline]
fn target_delta(table: &[u64; NODE_COUNT], old_targets: u32, new_targets: u32) -> u64 {
    let mut delta = 0_u64;
    let mut diff = old_targets ^ new_targets;
    while diff != 0 {
        let s = diff.trailing_zeros() as usize;
        diff &= diff - 1;
        if s < NODE_COUNT {
            delta ^= table[s];
        }
    }
    delta
}

/// XOR delta of a capture-count table entry between two states.
#[inline]
fn count_delta(table: &[u64], old_count: u8, new_count: u8, max: usize) -> u64 {
    let oc = (old_count as usize).min(max - 1);
    let nc = (new_count as usize).min(max - 1);
    if oc == nc {
        return 0;
    }
    let mut delta = 0_u64;
    if oc != 0 {
        delta ^= table[oc];
    }
    if nc != 0 {
        delta ^= table[nc];
    }
    delta
}

/// Incrementally derive the post-apply Zobrist key.
///
/// `old_key` is `full_state_key(old_state)` (the key before the apply),
/// `old` captures the pre-apply key inputs (see [`ZobristInputs::capture`]),
/// `new_state` is the post-apply state, and `from_node` / `to_node` are the
/// applied action's squares.  The return value is bit-identical to
/// `full_state_key(new_state)` but skips the full 24-square board scan.
///
/// Correct by construction: `full_state_key` is
/// `apply_misc(board ^ marked ^ side ^ captures, misc)`, and `apply_misc`
/// depends only on the low bits of its accumulator plus the misc count, so
/// `apply_misc(old_key ^ delta, misc_new)` reproduces the new key when
/// `delta` is the XOR difference of every non-misc component.  A
/// `debug_assert` in `apply_to_state` cross-checks this against
/// `full_state_key` on every apply.
pub(crate) fn key_after_apply(
    old_key: u64,
    old: &ZobristInputs,
    new_state: &MillState,
    from_node: i16,
    to_node: i16,
) -> u64 {
    let z = &MILL_ZOBRIST;
    let mut delta = 0_u64;

    if old.delayed_marked_pieces == 0
        && new_state.delayed_marked_pieces == 0
        && capture_state_is_empty(
            old.custodian_targets,
            old.custodian_count,
            old.intervention_targets,
            old.intervention_count,
            old.leap_targets,
            old.leap_count,
        )
        && capture_state_is_empty(
            new_state.custodian_targets,
            new_state.custodian_count,
            new_state.intervention_targets,
            new_state.intervention_count,
            new_state.leap_targets,
            new_state.leap_count,
        )
    {
        if (0..NODE_COUNT as i16).contains(&from_node) {
            let s = from_node as usize;
            let o = old.board[s];
            let n = new_state.board[s];
            if o == 1 || o == 2 {
                delta ^= z.psq[o as usize][s];
            }
            if n == 1 || n == 2 {
                delta ^= z.psq[n as usize][s];
            }
        }
        if (0..NODE_COUNT as i16).contains(&to_node) {
            let s = to_node as usize;
            let o = old.board[s];
            let n = new_state.board[s];
            if o != n {
                if o == 1 || o == 2 {
                    delta ^= z.psq[o as usize][s];
                }
                if n == 1 || n == 2 {
                    delta ^= z.psq[n as usize][s];
                }
            }
        }
        if (old.side_to_move == 1) != (new_state.side_to_move == 1) {
            delta ^= z.side;
        }
        return apply_misc(old_key ^ delta, misc_count(new_state));
    }

    // Board piece-square delta.  The only board writes in `apply_to_state`
    // are the action's from/to squares and the placing-to-moving marked
    // sweep, so the candidate square set is bounded by those.
    let mut candidates = old.delayed_marked_pieces;
    if (0..NODE_COUNT as i16).contains(&from_node) {
        candidates |= 1_u32 << from_node;
    }
    if (0..NODE_COUNT as i16).contains(&to_node) {
        candidates |= 1_u32 << to_node;
    }
    let mut cb = candidates;
    while cb != 0 {
        let s = cb.trailing_zeros() as usize;
        cb &= cb - 1;
        if s >= NODE_COUNT {
            continue;
        }
        let o = old.board[s];
        let n = new_state.board[s];
        if o == n {
            continue;
        }
        if o == 1 || o == 2 {
            delta ^= z.psq[o as usize][s];
        }
        if n == 1 || n == 2 {
            delta ^= z.psq[n as usize][s];
        }
    }

    // Side-to-move delta (only the "is it Black" bit matters).
    if (old.side_to_move == 1) != (new_state.side_to_move == 1) {
        delta ^= z.side;
    }

    // Marked-piece (psq[3]) delta: symmetric difference of the marked sets.
    let mut md = old.delayed_marked_pieces ^ new_state.delayed_marked_pieces;
    while md != 0 {
        let s = md.trailing_zeros() as usize;
        md &= md - 1;
        if s < NODE_COUNT {
            delta ^= z.psq[3][s];
        }
    }

    // Capture-state deltas (custodian / intervention / leap).
    for c in 0..2 {
        delta ^= target_delta(
            &z.custodian_target[c],
            old.custodian_targets[c],
            new_state.custodian_targets[c],
        );
        delta ^= count_delta(
            &z.custodian_count[c],
            old.custodian_count[c],
            new_state.custodian_count[c],
            MAX_CUSTODIAN,
        );
        delta ^= target_delta(
            &z.intervention_target[c],
            old.intervention_targets[c],
            new_state.intervention_targets[c],
        );
        delta ^= count_delta(
            &z.intervention_count[c],
            old.intervention_count[c],
            new_state.intervention_count[c],
            MAX_INTERVENTION,
        );
        delta ^= target_delta(
            &z.leap_target[c],
            old.leap_targets[c],
            new_state.leap_targets[c],
        );
        delta ^= count_delta(
            &z.leap_count[c],
            old.leap_count[c],
            new_state.leap_count[c],
            MAX_LEAP,
        );
    }

    // Misc counter for the new side to move (master `update_key_misc`).
    apply_misc(old_key ^ delta, misc_count(new_state))
}

#[inline]
pub(crate) fn capture_state_is_empty(
    custodian_targets: [u32; 2],
    custodian_count: [u8; 2],
    intervention_targets: [u32; 2],
    intervention_count: [u8; 2],
    leap_targets: [u32; 2],
    leap_count: [u8; 2],
) -> bool {
    custodian_targets == [0, 0]
        && custodian_count == [0, 0]
        && intervention_targets == [0, 0]
        && intervention_count == [0, 0]
        && leap_targets == [0, 0]
        && leap_count == [0, 0]
}

#[inline]
pub(crate) fn key_after_apply_from_changed_squares(
    old_key: u64,
    old_side_to_move: i8,
    old_from_piece: i8,
    old_to_piece: i8,
    new_state: &MillState,
    from_node: i16,
    to_node: i16,
) -> u64 {
    let z = &MILL_ZOBRIST;
    let mut delta = 0_u64;

    if (0..NODE_COUNT as i16).contains(&from_node) {
        let s = from_node as usize;
        if old_from_piece == 1 || old_from_piece == 2 {
            delta ^= z.psq[old_from_piece as usize][s];
        }
        let new_piece = new_state.board[s];
        if new_piece == 1 || new_piece == 2 {
            delta ^= z.psq[new_piece as usize][s];
        }
    }
    if (0..NODE_COUNT as i16).contains(&to_node) {
        let s = to_node as usize;
        if from_node != to_node {
            if old_to_piece == 1 || old_to_piece == 2 {
                delta ^= z.psq[old_to_piece as usize][s];
            }
            let new_piece = new_state.board[s];
            if new_piece == 1 || new_piece == 2 {
                delta ^= z.psq[new_piece as usize][s];
            }
        }
    }
    if (old_side_to_move == 1) != (new_state.side_to_move == 1) {
        delta ^= z.side;
    }
    apply_misc(old_key ^ delta, misc_count(new_state))
}

#[inline]
fn misc_count(state: &MillState) -> u64 {
    if state.phase != MillPhase::GameOver {
        u64::from(state.flags.zobrist_misc_count())
    } else {
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every Zobrist entry must be unique with overwhelming
    /// probability; collisions would inflate TT false-positive rates.
    /// The PRNG is deterministic, so this test is a regression guard.
    #[test]
    fn zobrist_entries_are_pairwise_distinct() {
        let mut all = Vec::new();
        for p in 1..PIECE_TYPES {
            for s in 0..NODE_COUNT {
                all.push(MILL_ZOBRIST.psq[p][s]);
            }
        }
        all.push(MILL_ZOBRIST.side);
        for c in 0..2 {
            all.extend_from_slice(&MILL_ZOBRIST.custodian_target[c]);
            all.extend_from_slice(&MILL_ZOBRIST.custodian_count[c]);
            all.extend_from_slice(&MILL_ZOBRIST.intervention_target[c]);
            all.extend_from_slice(&MILL_ZOBRIST.intervention_count[c]);
            all.extend_from_slice(&MILL_ZOBRIST.leap_target[c]);
            all.extend_from_slice(&MILL_ZOBRIST.leap_count[c]);
        }
        let total = all.len();
        all.sort_unstable();
        all.dedup();
        assert_eq!(all.len(), total, "duplicate entry in Mill Zobrist table");
    }

    #[test]
    fn zobrist_seed_is_nonzero_to_avoid_xorshift_collapse() {
        assert_ne!(SEED, 0);
    }

    #[test]
    fn zobrist_opening_entries_match_legacy_engine() {
        // Master generates psq entries in legacy SQ_8..SQ_31 order. d6 is
        // legacy SQ_16 and node 8 in the master-normalized Rust topology.
        assert_eq!(MILL_ZOBRIST.psq[1][8], 411_597_989);
        assert_eq!(MILL_ZOBRIST.side, 687_726_975);
        assert_eq!(MILL_ZOBRIST.psq[1][8] ^ MILL_ZOBRIST.side, 813_014_490);
    }

    #[test]
    fn key_misc_bit_round_trips_through_apply_misc() {
        let key = 0x00FF_FFFF_FFFF_FFFF_u64;
        for count in 0..=3 {
            let with_misc = apply_misc(key, count as u64);
            let extracted = with_misc >> (u32::BITS - KEY_MISC_BIT);
            assert_eq!(extracted, count as u64);
        }
    }
}
