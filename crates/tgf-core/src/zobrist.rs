// SPDX-License-Identifier: GPL-3.0-or-later
// Generic Zobrist hash table generator + incremental-update helpers.
//
// Most board games maintain a 64-bit position key for transposition-
// table lookups and three-fold-repetition detection.  The classical
// recipe — described in Zobrist (1969) — is:
//
//     1. At init: seed a deterministic PRNG and fill an
//        N×K table of u64s, one entry per (square, piece-kind) pair,
//        plus auxiliary entries for side-to-move, castling rights,
//        en-passant file, …
//     2. After every change: XOR the relevant entries into the
//        running key.  A do/undo pair restores the key exactly because
//        XOR is its own inverse.
//
// `ZobristTable<MAX_SQUARES, PIECE_TYPES>` encapsulates the table
// generation step using a deterministic linear-congruential PRNG so
// the result is `const`-constructable (lives in `.rodata` with zero
// initialiser).  The xor helpers are `#[inline]` so the search hot
// path inlines them away.
//
// Mill keeps its full-state `position_key` for now; new games that
// follow the chess-style approach should reach for this helper.

/// Compile-time deterministic PRNG (xorshift64*) used to populate
/// Zobrist tables.  Keeping the keystream `const`-evaluable lets the
/// resulting `ZobristTable<…>` live in static storage with no runtime
/// initialiser, eliminating both startup cost and any chance that
/// concurrent kernels see different tables.
const fn next_xorshift64(state: u64) -> u64 {
    let mut x = state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    // Multiply step from xorshift64* (Marsaglia, 2003).
    x.wrapping_mul(0x2545_F491_4F6C_DD1D)
}

/// Pre-generated Zobrist table sized at compile time for the supplied
/// game.  `MAX_SQUARES` is the maximum board node id (typically the
/// `BoardTopology::node_count`); `PIECE_TYPES` is the count of
/// distinct (owner × kind) pairs the game tracks.
///
/// Auxiliary entries cover the most common needs without forcing the
/// caller to roll their own:
///   * `side_to_move`  — XOR after every move.
///   * `castling`      — 16 entries indexed by a 4-bit rights mask.
///   * `en_passant_file` — 8 entries indexed by file 0..=7
///     (chess-specific; ignore for other games).
#[derive(Clone, Copy, Debug)]
pub struct ZobristTable<const MAX_SQUARES: usize, const PIECE_TYPES: usize> {
    pub piece_square: [[u64; PIECE_TYPES]; MAX_SQUARES],
    pub side_to_move: u64,
    pub castling: [u64; 16],
    pub en_passant_file: [u64; 8],
}

impl<const MAX_SQUARES: usize, const PIECE_TYPES: usize> ZobristTable<MAX_SQUARES, PIECE_TYPES> {
    /// Generate a Zobrist table from the supplied seed.  The seed must
    /// be non-zero because xorshift PRNGs degenerate on a zero state;
    /// `0` is asserted away at compile time.
    pub const fn new(seed: u64) -> Self {
        assert!(seed != 0, "Zobrist seed must be non-zero");
        let mut state = seed;
        let mut piece_square = [[0_u64; PIECE_TYPES]; MAX_SQUARES];
        let mut sq = 0;
        while sq < MAX_SQUARES {
            let mut k = 0;
            while k < PIECE_TYPES {
                state = next_xorshift64(state);
                piece_square[sq][k] = state;
                k += 1;
            }
            sq += 1;
        }
        state = next_xorshift64(state);
        let side_to_move = state;
        let mut castling = [0_u64; 16];
        let mut i = 0;
        while i < 16 {
            state = next_xorshift64(state);
            castling[i] = state;
            i += 1;
        }
        let mut en_passant_file = [0_u64; 8];
        let mut i = 0;
        while i < 8 {
            state = next_xorshift64(state);
            en_passant_file[i] = state;
            i += 1;
        }
        Self {
            piece_square,
            side_to_move,
            castling,
            en_passant_file,
        }
    }

    /// XOR a piece-square entry into `key`.  `square` and `piece` must
    /// be in range; bounds are checked via `debug_assert!` so release
    /// builds stay branch-free.
    #[inline]
    pub fn xor_piece(&self, key: &mut u64, square: usize, piece: usize) {
        debug_assert!(square < MAX_SQUARES);
        debug_assert!(piece < PIECE_TYPES);
        *key ^= self.piece_square[square][piece];
    }

    /// XOR the side-to-move marker into `key`.
    #[inline]
    pub fn flip_side(&self, key: &mut u64) {
        *key ^= self.side_to_move;
    }

    /// XOR the castling-rights entry for `rights_mask` (low 4 bits)
    /// into `key`.
    #[inline]
    pub fn xor_castling(&self, key: &mut u64, rights_mask: u8) {
        debug_assert!(rights_mask < 16);
        *key ^= self.castling[rights_mask as usize];
    }

    /// XOR the en-passant-file entry for `file` (0..=7) into `key`.
    /// `None` is a no-op so callers can pass through `Option<u8>`
    /// directly.
    #[inline]
    pub fn xor_en_passant(&self, key: &mut u64, file: Option<u8>) {
        if let Some(f) = file {
            debug_assert!((f as usize) < 8);
            *key ^= self.en_passant_file[f as usize];
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    type ToyTable = ZobristTable<24, 4>;

    const TOY: ToyTable = ToyTable::new(0xdead_beef_cafe_babe);

    #[test]
    fn table_is_deterministic_for_same_seed() {
        let a: ToyTable = ToyTable::new(0xfeed_face_dead_d00d);
        let b: ToyTable = ToyTable::new(0xfeed_face_dead_d00d);
        for sq in 0..24 {
            for k in 0..4 {
                assert_eq!(a.piece_square[sq][k], b.piece_square[sq][k]);
            }
        }
        assert_eq!(a.side_to_move, b.side_to_move);
        assert_eq!(a.castling, b.castling);
        assert_eq!(a.en_passant_file, b.en_passant_file);
    }

    #[test]
    fn entries_are_distinct_with_overwhelming_probability() {
        // The PRNG must produce >99 % unique 64-bit values across the
        // small table, otherwise the seed has degenerated.
        let mut all = Vec::new();
        for sq in 0..24 {
            for k in 0..4 {
                all.push(TOY.piece_square[sq][k]);
            }
        }
        all.push(TOY.side_to_move);
        all.extend_from_slice(&TOY.castling);
        all.extend_from_slice(&TOY.en_passant_file);
        let total = all.len();
        all.sort_unstable();
        all.dedup();
        assert_eq!(all.len(), total, "PRNG produced duplicate entries");
    }

    #[test]
    fn xor_piece_round_trip_is_identity() {
        let mut key = 0_u64;
        TOY.xor_piece(&mut key, 5, 2);
        TOY.xor_piece(&mut key, 5, 2);
        assert_eq!(key, 0);
    }

    #[test]
    fn flip_side_is_self_inverse() {
        let mut key = 0xdead_u64;
        TOY.flip_side(&mut key);
        TOY.flip_side(&mut key);
        assert_eq!(key, 0xdead);
    }

    #[test]
    fn castling_xor_distinct_per_mask() {
        let baseline = 0_u64;
        let mut a = baseline;
        let mut b = baseline;
        TOY.xor_castling(&mut a, 0b0001);
        TOY.xor_castling(&mut b, 0b0010);
        assert_ne!(a, b);
    }

    #[test]
    fn en_passant_none_is_noop() {
        let mut key = 0xfade_u64;
        TOY.xor_en_passant(&mut key, None);
        assert_eq!(key, 0xfade);
    }

    #[test]
    fn en_passant_round_trip_is_identity() {
        let mut key = 0xfade_u64;
        TOY.xor_en_passant(&mut key, Some(3));
        TOY.xor_en_passant(&mut key, Some(3));
        assert_eq!(key, 0xfade);
    }
}
