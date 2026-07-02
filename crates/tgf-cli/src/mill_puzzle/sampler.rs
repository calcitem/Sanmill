// SPDX-License-Identifier: AGPL-3.0-or-later
// Random position sampling for puzzle generation.
//
// Mirrors the "random piece counts, random depth" sampling strategy
// described for the reference NMM_LLM puzzle generators
// (`tools/malom_puzzle_generator.py`, `tools/placement_puzzle_generator.py`):
// draw a random legal-shaped bitboard within the requested
// phase/piece-count/side constraints, then let the caller reject it via a
// Perfect DB lookup. Positions are not checked for game-tree reachability --
// the same simplification those reference tools use -- only for internal
// consistency (disjoint bitboards, hand+board within the variant's piece
// budget).

use perfect_db::database::PerfectQuery;
use tgf_mill::MillVariantOptions;

/// Which phase a sampled root position should be drawn from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum PhaseChoice {
    Placing,
    Moving,
    Random,
}

impl PhaseChoice {
    pub(crate) fn parse(value: &str) -> Self {
        match value {
            "placing" | "place" | "placement" => Self::Placing,
            "moving" | "move" | "movement" => Self::Moving,
            _ => Self::Random,
        }
    }
}

/// Which side to move a sampled root position should have.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SideChoice {
    White,
    Black,
    Random,
}

impl SideChoice {
    pub(crate) fn parse(value: &str) -> Self {
        match value {
            "w" | "white" => Self::White,
            "b" | "black" => Self::Black,
            _ => Self::Random,
        }
    }

    fn resolve(self, rng: &mut u64) -> u8 {
        match self {
            Self::White => 0,
            Self::Black => 1,
            Self::Random => (next_u64(rng) & 1) as u8,
        }
    }
}

/// Sampling parameters for one candidate root position.
#[derive(Debug, Clone, Copy)]
pub(crate) struct SampleSpec {
    pub phase: PhaseChoice,
    pub side: SideChoice,
    pub min_pieces: u8,
    pub max_pieces: u8,
}

/// xorshift64* step; matches the PRNG idiom used by `mill_tune::datagen`.
pub(crate) fn next_u64(state: &mut u64) -> u64 {
    let mut x = *state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *state = x;
    x
}

/// Uniform integer in `[lo, hi]` (inclusive on both ends).
fn next_range(rng: &mut u64, lo: u8, hi: u8) -> u8 {
    assert!(lo <= hi, "sampling range must be non-empty (lo <= hi)");
    let span = u64::from(hi - lo) + 1;
    lo + (next_u64(rng) % span) as u8
}

/// Draw `count` distinct perfect-database bit indices (0..24) from `pool`,
/// removing the chosen indices so a later call for the other color cannot
/// collide with them.
fn draw_distinct(rng: &mut u64, pool: &mut Vec<u8>, count: u8) -> u32 {
    let mut bits = 0u32;
    for _ in 0..count {
        assert!(
            !pool.is_empty(),
            "sampling pool exhausted before drawing enough squares"
        );
        let idx = (next_u64(rng) % pool.len() as u64) as usize;
        let square = pool.swap_remove(idx);
        bits |= 1u32 << square;
    }
    bits
}

/// A sampled Perfect DB sector shape: on-board and in-hand counts per side,
/// plus the side to move. This is exactly the information a `SectorId`
/// carries (see `perfect_db::database::SectorId`), which is also exactly
/// the granularity at which `.sec2` files are loaded and LRU-cached.
///
/// Splitting sampling into "pick a shape" (this struct) and "pick bits
/// within that shape" ([`sample_bits_for_shape`]) lets callers deliberately
/// reuse one shape across many attempts, so repeated attempts hit the same
/// cached sector instead of forcing a fresh multi-megabyte `.sec2` read on
/// every single try.
#[derive(Debug, Clone, Copy)]
pub(crate) struct SectorShape {
    pub side_to_move: u8,
    pub white_on_board: u8,
    pub black_on_board: u8,
    pub white_in_hand: u8,
    pub black_in_hand: u8,
}

/// Sample one random sector shape consistent with `spec` and the variant's
/// piece budget. See [`SectorShape`] for why this is a separate step from
/// choosing the actual bitboard.
pub(crate) fn sample_sector_shape(
    rng: &mut u64,
    spec: &SampleSpec,
    options: &MillVariantOptions,
) -> SectorShape {
    let phase = match spec.phase {
        PhaseChoice::Random => {
            if next_u64(rng) & 1 == 0 {
                PhaseChoice::Placing
            } else {
                PhaseChoice::Moving
            }
        }
        other => other,
    };
    // Side must be resolved before the hand counts: Mill strictly
    // alternates one placement per ply (White moves first), so which side
    // is "ahead" on pieces already placed is fully determined by whose turn
    // it is -- see `sample_placing_hands` for the exact invariant. Sampling
    // hands without this constraint can name a `SectorId` the Perfect DB
    // has no base value for (an unreachable shape), which surfaces as a
    // hard database error rather than an ordinary "no data" miss.
    let side_to_move = spec.side.resolve(rng);

    let lo = spec.min_pieces.max(options.pieces_at_least_count);
    let hi = spec.max_pieces.min(options.piece_count).max(lo);
    let white_on_board = next_range(rng, lo, hi);
    let black_on_board = next_range(rng, lo, hi);
    let white_room = options.piece_count - white_on_board;
    let black_room = options.piece_count - black_on_board;

    let (white_in_hand, black_in_hand) = match phase {
        PhaseChoice::Moving => (0, 0),
        PhaseChoice::Placing => {
            sample_placing_hands(rng, side_to_move, white_room, black_room, true)
        }
        PhaseChoice::Random => {
            sample_placing_hands(rng, side_to_move, white_room, black_room, false)
        }
    };

    SectorShape {
        side_to_move,
        white_on_board,
        black_on_board,
        white_in_hand,
        black_in_hand,
    }
}

/// Sample a random disjoint bitboard placement within a fixed
/// [`SectorShape`] and build the resulting query.
pub(crate) fn sample_bits_for_shape(rng: &mut u64, shape: &SectorShape) -> PerfectQuery {
    let mut pool: Vec<u8> = (0..24u8).collect();
    let white_bits = draw_distinct(rng, &mut pool, shape.white_on_board);
    let black_bits = draw_distinct(rng, &mut pool, shape.black_on_board);

    PerfectQuery::new(
        white_bits,
        black_bits,
        shape.white_in_hand,
        shape.black_in_hand,
        shape.side_to_move,
        false,
    )
}

/// Sample one random root query consistent with `spec` and the variant's
/// piece budget.
///
/// The result is not filtered for legality beyond disjoint placement and
/// the hand/board piece budget; callers reject unsuitable candidates via a
/// Perfect DB lookup, exactly like the reference Python generators this
/// mirrors.
///
/// Convenience wrapper around [`sample_sector_shape`] +
/// [`sample_bits_for_shape`] for one-off callers. Production code always
/// goes through the two-stage API directly for cache-friendly sector
/// batching (see `mill_puzzle::run_puzzle_gen`), so this currently only
/// exists for tests that do not care about batching.
#[cfg(test)]
pub(crate) fn sample_root_query(
    rng: &mut u64,
    spec: &SampleSpec,
    options: &MillVariantOptions,
) -> PerfectQuery {
    let shape = sample_sector_shape(rng, spec, options);
    sample_bits_for_shape(rng, &shape)
}

/// Sample `(white_in_hand, black_in_hand)` consistent with strict placement
/// alternation (White places first): at any point in the placing phase, the
/// two sides' "pieces placed so far" (`piece_count - hand`) differ by at
/// most one, and the side that is one placement ahead must be the side
/// whose turn it now is *not*. Concretely:
///
///   * `side_to_move == White` implies `white_in_hand == black_in_hand`.
///   * `side_to_move == Black` implies `black_in_hand == white_in_hand + 1`.
///
/// When `require_nonempty` is true, at least one hand must stay above zero
/// (a genuine "still placing" position); when the room budget cannot
/// support that for the requested `side_to_move`, this falls back to
/// `(0, 0)` -- a rare edge case that simply yields a moving-phase-shaped
/// sample instead of resampling the whole position.
fn sample_placing_hands(
    rng: &mut u64,
    side_to_move: u8,
    white_room: u8,
    black_room: u8,
    require_nonempty: bool,
) -> (u8, u8) {
    if side_to_move == 0 {
        let max_h = white_room.min(black_room);
        let min_h = u8::from(require_nonempty);
        if min_h > max_h {
            return (0, 0);
        }
        let h = next_range(rng, min_h, max_h);
        (h, h)
    } else {
        if black_room == 0 {
            return (0, 0);
        }
        let max_h = white_room.min(black_room - 1);
        let h = next_range(rng, 0, max_h);
        (h, h + 1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sampled_queries_never_overlap_and_respect_piece_budget() {
        let options = MillVariantOptions::default();
        let spec = SampleSpec {
            phase: PhaseChoice::Random,
            side: SideChoice::Random,
            min_pieces: 3,
            max_pieces: 7,
        };
        let mut rng = 0xDEAD_BEEF_u64;
        for _ in 0..2000 {
            let query = sample_root_query(&mut rng, &spec, &options);
            assert_eq!(
                query.white_bits & query.black_bits,
                0,
                "white/black bitboards must never overlap"
            );
            let white_on_board = query.white_bits.count_ones() as u8;
            let black_on_board = query.black_bits.count_ones() as u8;
            assert!((3..=7).contains(&white_on_board));
            assert!((3..=7).contains(&black_on_board));
            assert!(white_on_board + query.white_in_hand <= options.piece_count);
            assert!(black_on_board + query.black_in_hand <= options.piece_count);
            assert!(query.side_to_move == 0 || query.side_to_move == 1);
        }
    }

    #[test]
    fn moving_phase_requests_always_have_empty_hands() {
        let options = MillVariantOptions::default();
        let spec = SampleSpec {
            phase: PhaseChoice::Moving,
            side: SideChoice::White,
            min_pieces: 3,
            max_pieces: 6,
        };
        let mut rng = 1_u64;
        for _ in 0..200 {
            let query = sample_root_query(&mut rng, &spec, &options);
            assert_eq!(query.white_in_hand, 0);
            assert_eq!(query.black_in_hand, 0);
            assert_eq!(query.side_to_move, 0);
        }
    }

    #[test]
    fn hand_counts_always_respect_strict_placement_alternation() {
        // Regression test: a real game strictly alternates one placement
        // per ply (White first), so the two sides' "pieces placed so far"
        // can differ by at most one, and only in White's favor while it is
        // Black's turn. Sampling outside this invariant used to name a
        // `SectorId` the Perfect DB has no base value for at all (crashing
        // as a hard database error instead of an ordinary cache miss).
        let options = MillVariantOptions::default();
        for phase in [PhaseChoice::Placing, PhaseChoice::Random] {
            let spec = SampleSpec {
                phase,
                side: SideChoice::Random,
                min_pieces: 1,
                max_pieces: 9,
            };
            let mut rng = 0x1234_5678_u64;
            for _ in 0..5000 {
                let query = sample_root_query(&mut rng, &spec, &options);
                let placed_white = options.piece_count - query.white_in_hand;
                let placed_black = options.piece_count - query.black_in_hand;
                if query.side_to_move == 0 {
                    assert_eq!(
                        placed_white, placed_black,
                        "White to move must have placed exactly as many pieces as Black"
                    );
                } else {
                    assert!(
                        placed_white == placed_black || placed_white == placed_black + 1,
                        "Black to move must have placed the same as, or one fewer than, White"
                    );
                }
            }
        }
    }

    #[test]
    fn placing_phase_requests_always_leave_a_hand_nonempty() {
        let options = MillVariantOptions::default();
        let spec = SampleSpec {
            phase: PhaseChoice::Placing,
            side: SideChoice::Random,
            min_pieces: 3,
            max_pieces: 7,
        };
        let mut rng = 42_u64;
        for _ in 0..200 {
            let query = sample_root_query(&mut rng, &spec, &options);
            assert!(query.white_in_hand > 0 || query.black_in_hand > 0);
        }
    }

    #[test]
    fn phase_and_side_parse_recognized_aliases() {
        assert_eq!(PhaseChoice::parse("placing"), PhaseChoice::Placing);
        assert_eq!(PhaseChoice::parse("placement"), PhaseChoice::Placing);
        assert_eq!(PhaseChoice::parse("moving"), PhaseChoice::Moving);
        assert_eq!(PhaseChoice::parse("random"), PhaseChoice::Random);
        assert_eq!(PhaseChoice::parse("anything-else"), PhaseChoice::Random);

        assert_eq!(SideChoice::parse("w"), SideChoice::White);
        assert_eq!(SideChoice::parse("white"), SideChoice::White);
        assert_eq!(SideChoice::parse("b"), SideChoice::Black);
        assert_eq!(SideChoice::parse("random"), SideChoice::Random);
    }
}
