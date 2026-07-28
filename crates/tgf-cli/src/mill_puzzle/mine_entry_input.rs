// SPDX-License-Identifier: AGPL-3.0-or-later
// Persistent, bounded-memory input adapter from `tgf mill mine` JSONL
// records to the exact puzzle-certification pipeline.

use std::cmp::{Ordering, Reverse};
use std::collections::{BTreeMap, BinaryHeap, HashSet};
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};

use perfect_db::database::PerfectQuery;
use perfect_db::query_from_state;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use tgf_core::{GameRules, OutcomeKind};
use tgf_mill::{MillPhase, MillRules, MillVariantOptions};

use super::analysis::canonical_symmetry_key;
use super::candidate_input::{
    CandidateDiscovery, EngineBlunderEvidence, LoadedCandidate, LoadedCandidateSet,
};
use super::motifs::PuzzleMotif;
use super::sampler::SampleSpec;

#[derive(Clone, Copy, Debug)]
pub(super) struct MineEntryLoadConfig<'a> {
    pub paths: &'a str,
    pub candidate_limit: usize,
    pub per_shape_limit: usize,
    pub min_severity: i8,
    pub min_mass: f64,
    pub min_depth_used: i32,
    /// Minimum number of primary placement actions already played. This is
    /// exact in the placing phase because each placement decrements one hand;
    /// movement roots naturally report the full two-side piece budget.
    pub min_placements: u8,
    pub seed: u64,
    pub spec: SampleSpec,
}

#[derive(Debug, Deserialize)]
struct MineEntryRow {
    severity: i8,
    trap_score: u8,
    mass: f64,
    fen: String,
    depth_used: i32,
}

/// Piece-count shape normalised to the solver/defender frame. Grouping
/// accepted candidates by this key keeps consecutive Perfect DB probes in
/// the same sector while still balancing the input pool across phases and
/// material configurations.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
struct ShapeKey {
    phase: u8,
    solver_on_board: u8,
    defender_on_board: u8,
    solver_in_hand: u8,
    defender_in_hand: u8,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
struct RankKey {
    depth_used: i32,
    severity: i8,
    trap_score: u8,
    /// Every accepted mass is finite and non-negative, for which positive
    /// IEEE-754 bit order is the same as numerical order.
    mass_bits: u64,
    tie_break: u64,
}

#[derive(Clone, Debug)]
struct RankedCandidate {
    rank: RankKey,
    canonical_root: u64,
    query: PerfectQuery,
    evidence: EngineBlunderEvidence,
}

impl PartialEq for RankedCandidate {
    fn eq(&self, other: &Self) -> bool {
        self.rank == other.rank && self.canonical_root == other.canonical_root
    }
}

impl Eq for RankedCandidate {}

impl PartialOrd for RankedCandidate {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for RankedCandidate {
    fn cmp(&self, other: &Self) -> Ordering {
        self.rank
            .cmp(&other.rank)
            .then_with(|| self.canonical_root.cmp(&other.canonical_root))
    }
}

#[derive(Default)]
struct LoadStats {
    inspected_rows: usize,
    eligible_rows: usize,
    phase_filtered: usize,
    material_filtered: usize,
    opening_filtered: usize,
    pending_removal_filtered: usize,
    terminal_filtered: usize,
}

pub(super) fn load_mine_entry_candidates(
    config: MineEntryLoadConfig<'_>,
    rules: &MillRules,
    options: &MillVariantOptions,
) -> LoadedCandidateSet {
    assert!(
        config.candidate_limit > 0,
        "mine candidate limit must be positive"
    );
    assert!(
        config.per_shape_limit > 0,
        "mine per-shape limit must be positive"
    );
    assert!(
        (1..=2).contains(&config.min_severity),
        "mine minimum severity must be 1 or 2"
    );
    assert!(
        config.min_mass.is_finite() && config.min_mass >= 0.0,
        "mine minimum mass must be finite and non-negative"
    );
    assert!(
        config.min_placements <= options.piece_count.saturating_mul(2),
        "mine minimum placements exceeds the variant's two-side piece budget"
    );

    let paths = canonical_input_paths(config.paths);
    let mut heaps = BTreeMap::<ShapeKey, BinaryHeap<Reverse<RankedCandidate>>>::new();
    let mut stats = LoadStats::default();
    let mut source_digests = Vec::with_capacity(paths.len());

    for path in &paths {
        source_digests.push(scan_file(
            path, config, rules, options, &mut heaps, &mut stats,
        ));
    }

    let manifest_sha256 = source_manifest_sha256(&mut source_digests);
    let buckets = heaps
        .into_iter()
        .map(|(shape, heap)| {
            let mut candidates = heap
                .into_iter()
                .map(|candidate| candidate.0)
                .collect::<Vec<_>>();
            candidates.sort_by(|left, right| right.cmp(left));
            (shape, candidates)
        })
        .collect::<Vec<_>>();

    // Take one candidate per material shape at a time before taking a
    // second, third, and so on. This prevents the large moving/endgame
    // inputs from drowning out placement and asymmetric-material studies.
    let mut selected = Vec::<(ShapeKey, RankedCandidate)>::new();
    let mut seen_roots = HashSet::new();
    let maximum_bucket_len = buckets
        .iter()
        .map(|(_, candidates)| candidates.len())
        .max()
        .unwrap_or(0);
    'balanced: for rank_index in 0..maximum_bucket_len {
        for (shape, candidates) in &buckets {
            let Some(candidate) = candidates.get(rank_index) else {
                continue;
            };
            if seen_roots.insert(candidate.canonical_root) {
                selected.push((*shape, candidate.clone()));
                if selected.len() >= config.candidate_limit {
                    break 'balanced;
                }
            }
        }
    }

    // Re-establish useful sector locality without undoing the material
    // balance above. A small block amortises one sector load, then moves on
    // to another shape before an early `--count` stop can fill the pack with
    // near-identical material configurations.
    const SHAPE_BLOCK_LEN: usize = 16;
    let mut selected_by_shape = BTreeMap::<ShapeKey, Vec<RankedCandidate>>::new();
    for (shape, candidate) in selected {
        selected_by_shape.entry(shape).or_default().push(candidate);
    }
    for candidates in selected_by_shape.values_mut() {
        candidates.sort_by(|left, right| right.cmp(left));
    }
    let maximum_selected_bucket_len = selected_by_shape.values().map(Vec::len).max().unwrap_or(0);
    let mut scheduled = Vec::with_capacity(config.candidate_limit);
    for block_start in (0..maximum_selected_bucket_len).step_by(SHAPE_BLOCK_LEN) {
        for candidates in selected_by_shape.values() {
            let block_end = (block_start + SHAPE_BLOCK_LEN).min(candidates.len());
            if block_start < block_end {
                scheduled.extend(candidates[block_start..block_end].iter().cloned());
            }
        }
    }
    let candidates = scheduled
        .into_iter()
        .map(|candidate| LoadedCandidate {
            query: candidate.query,
            replay: None,
            engine_blunder: Some(candidate.evidence),
        })
        .collect::<Vec<_>>();
    if candidates.is_empty() {
        panic!("[puzzle-gen] no mine-entry candidates survived the source filters");
    }

    eprintln!(
        "[puzzle-gen] mine input: files={} manifest={} rows={} eligible={} selected={} \
         phase-filtered={} material-filtered={} opening-filtered={} pending-removal={} terminal={}",
        paths.len(),
        &manifest_sha256[..12],
        stats.inspected_rows,
        stats.eligible_rows,
        candidates.len(),
        stats.phase_filtered,
        stats.material_filtered,
        stats.opening_filtered,
        stats.pending_removal_filtered,
        stats.terminal_filtered,
    );

    LoadedCandidateSet {
        motif: PuzzleMotif::Any,
        discovery: CandidateDiscovery::EngineBlunderCorpus {
            manifest_sha256,
            source_file_count: paths.len(),
            inspected_rows: stats.inspected_rows,
            eligible_rows: stats.eligible_rows,
        },
        candidates,
    }
}

fn canonical_input_paths(raw_paths: &str) -> Vec<PathBuf> {
    let mut paths = raw_paths
        .split(',')
        .map(str::trim)
        .filter(|path| !path.is_empty())
        .map(|path| {
            std::fs::canonicalize(path).unwrap_or_else(|error| {
                panic!("[puzzle-gen] cannot open mine input {path}: {error}")
            })
        })
        .collect::<Vec<_>>();
    paths.sort();
    paths.dedup();
    if paths.is_empty() {
        panic!("[puzzle-gen] --mine-entry-file did not name an input file");
    }
    paths
}

fn scan_file(
    path: &Path,
    config: MineEntryLoadConfig<'_>,
    rules: &MillRules,
    options: &MillVariantOptions,
    heaps: &mut BTreeMap<ShapeKey, BinaryHeap<Reverse<RankedCandidate>>>,
    stats: &mut LoadStats,
) -> [u8; 32] {
    let file = File::open(path)
        .unwrap_or_else(|error| panic!("[puzzle-gen] cannot read {}: {error}", path.display()));
    let mut reader = BufReader::with_capacity(1024 * 1024, file);
    let mut hasher = Sha256::new();
    let mut raw_line = Vec::new();
    let mut line_number = 0usize;
    loop {
        raw_line.clear();
        let bytes_read = reader
            .read_until(b'\n', &mut raw_line)
            .unwrap_or_else(|error| {
                panic!(
                    "[puzzle-gen] cannot read {} at line {}: {error}",
                    path.display(),
                    line_number + 1
                )
            });
        if bytes_read == 0 {
            break;
        }
        hasher.update(&raw_line);
        line_number += 1;
        let text = std::str::from_utf8(&raw_line)
            .unwrap_or_else(|error| {
                panic!(
                    "[puzzle-gen] mine input {}:{} is not UTF-8: {error}",
                    path.display(),
                    line_number
                )
            })
            .trim();
        if text.is_empty() {
            continue;
        }
        stats.inspected_rows += 1;
        let row: MineEntryRow = serde_json::from_str(text).unwrap_or_else(|error| {
            panic!(
                "[puzzle-gen] invalid mine entry at {}:{}: {error}",
                path.display(),
                line_number
            )
        });
        consider_row(row, config, rules, options, heaps, stats);
    }
    hasher.finalize().into()
}

fn consider_row(
    row: MineEntryRow,
    config: MineEntryLoadConfig<'_>,
    rules: &MillRules,
    options: &MillVariantOptions,
    heaps: &mut BTreeMap<ShapeKey, BinaryHeap<Reverse<RankedCandidate>>>,
    stats: &mut LoadStats,
) {
    if !(0..=2).contains(&row.severity) {
        panic!(
            "[puzzle-gen] mine entry severity {} is outside the supported 0..=2 range",
            row.severity
        );
    }
    if !row.mass.is_finite() || row.mass < 0.0 {
        panic!(
            "[puzzle-gen] mine entry mass must be finite and non-negative, got {}",
            row.mass
        );
    }
    if row.severity < config.min_severity
        || row.mass < config.min_mass
        || row.depth_used < config.min_depth_used
    {
        return;
    }

    let mut state = rules.set_from_fen(&row.fen).unwrap_or_else(|error| {
        panic!("[puzzle-gen] invalid mine-entry FEN ({error}): {}", row.fen)
    });
    state.reset_ply_since_capture();
    let side = state.side_to_move();
    if state.pending_removals()[side as usize] > 0 {
        stats.pending_removal_filtered += 1;
        return;
    }
    let snapshot = rules.encode_state(state.clone());
    if rules.outcome(&snapshot).kind != OutcomeKind::Ongoing {
        stats.terminal_filtered += 1;
        return;
    }
    let is_moving = state.phase() == MillPhase::Moving;
    if !config.spec.phase.accepts(is_moving) || !config.spec.side.accepts(side as u8) {
        stats.phase_filtered += 1;
        return;
    }
    let query = query_from_state(&state, options, side).unwrap_or_else(|| {
        panic!(
            "[puzzle-gen] mine-entry FEN is outside the selected Perfect DB variant: {}",
            row.fen
        )
    });
    let placements = options
        .piece_count
        .saturating_mul(2)
        .saturating_sub(query.white_in_hand)
        .saturating_sub(query.black_in_hand);
    if placements < config.min_placements {
        stats.opening_filtered += 1;
        return;
    }
    let (solver_on_board, defender_on_board, solver_in_hand, defender_in_hand) =
        solver_material(&query);
    if !(config.spec.min_solver_pieces..=config.spec.max_solver_pieces).contains(&solver_on_board)
        || !(config.spec.min_defender_pieces..=config.spec.max_defender_pieces)
            .contains(&defender_on_board)
    {
        stats.material_filtered += 1;
        return;
    }

    stats.eligible_rows += 1;
    let canonical_root = canonical_symmetry_key(&query);
    let evidence = EngineBlunderEvidence {
        severity: row.severity,
        trap_score: row.trap_score,
        mass: row.mass,
        depth_used: row.depth_used,
    };
    let candidate = RankedCandidate {
        rank: RankKey {
            depth_used: row.depth_used,
            severity: row.severity,
            trap_score: row.trap_score,
            mass_bits: row.mass.to_bits(),
            tie_break: splitmix64(canonical_root ^ config.seed),
        },
        canonical_root,
        query,
        evidence,
    };
    let shape = ShapeKey {
        phase: u8::from(is_moving),
        solver_on_board,
        defender_on_board,
        solver_in_hand,
        defender_in_hand,
    };
    let heap = heaps.entry(shape).or_default();
    if heap.len() < config.per_shape_limit {
        heap.push(Reverse(candidate));
        return;
    }
    let weakest = &heap
        .peek()
        .expect("a full per-shape heap must have a weakest candidate")
        .0;
    if candidate > *weakest {
        heap.pop();
        heap.push(Reverse(candidate));
    }
}

fn solver_material(query: &PerfectQuery) -> (u8, u8, u8, u8) {
    let white_on_board = query.white_bits.count_ones() as u8;
    let black_on_board = query.black_bits.count_ones() as u8;
    if query.side_to_move == 0 {
        (
            white_on_board,
            black_on_board,
            query.white_in_hand,
            query.black_in_hand,
        )
    } else {
        (
            black_on_board,
            white_on_board,
            query.black_in_hand,
            query.white_in_hand,
        )
    }
}

fn source_manifest_sha256(digests: &mut [[u8; 32]]) -> String {
    digests.sort();
    let mut manifest = Sha256::new();
    manifest.update(b"sanmill.mill-mine-puzzle-source.v1\0");
    for digest in digests {
        manifest.update((digest.len() as u64).to_le_bytes());
        manifest.update(digest);
    }
    hex_lower(&manifest.finalize())
}

fn hex_lower(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(bytes.len() * 2);
    for &byte in bytes {
        output.push(HEX[(byte >> 4) as usize] as char);
        output.push(HEX[(byte & 0x0f) as usize] as char);
    }
    output
}

fn splitmix64(mut value: u64) -> u64 {
    value = value.wrapping_add(0x9e37_79b9_7f4a_7c15);
    value = (value ^ (value >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    value = (value ^ (value >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    value ^ (value >> 31)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tgf_mill::MillVariantOptions;

    #[test]
    fn mine_input_prefers_deeper_evidence_within_one_shape() {
        let path = std::env::temp_dir().join(format!(
            "sanmill_mine_puzzle_input_{}.jsonl",
            std::process::id()
        ));
        std::fs::write(
            &path,
            concat!(
                "{\"severity\":1,\"trap_score\":200,\"mass\":50.0,",
                "\"fen\":\"*O*@****/********/******** w p p 1 8 1 8 0 0 ",
                "-1 -1 -1 -1 0 0 2 ids:nodes\",\"depth_used\":4}\n",
                "{\"severity\":1,\"trap_score\":180,\"mass\":40.0,",
                "\"fen\":\"*O*****@/********/******** w p p 1 8 1 8 0 0 ",
                "-1 -1 -1 -1 0 0 2 ids:nodes\",\"depth_used\":8}\n",
            ),
        )
        .expect("fixture write must succeed");
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let loaded = load_mine_entry_candidates(
            MineEntryLoadConfig {
                paths: path.to_str().expect("temporary path must be UTF-8"),
                candidate_limit: 1,
                per_shape_limit: 4,
                min_severity: 1,
                min_mass: 0.0,
                min_depth_used: 0,
                min_placements: 0,
                seed: 7,
                spec: SampleSpec {
                    phase: super::super::sampler::PhaseChoice::Placing,
                    side: super::super::sampler::SideChoice::White,
                    min_solver_pieces: 0,
                    max_solver_pieces: 9,
                    min_defender_pieces: 0,
                    max_defender_pieces: 9,
                },
            },
            &rules,
            &options,
        );
        let _ = std::fs::remove_file(path);

        assert_eq!(loaded.candidates.len(), 1);
        assert_eq!(
            loaded.candidates[0]
                .engine_blunder
                .as_ref()
                .expect("mine evidence must survive loading")
                .depth_used,
            8
        );
    }

    #[test]
    fn mine_input_can_skip_the_first_six_placement_rounds() {
        let path = std::env::temp_dir().join(format!(
            "sanmill_mine_puzzle_opening_filter_{}.jsonl",
            std::process::id()
        ));
        std::fs::write(
            &path,
            concat!(
                "{\"severity\":2,\"trap_score\":220,\"mass\":10.0,",
                "\"fen\":\"*O*@****/********/******** w p p 1 8 1 8 0 0 ",
                "-1 -1 -1 -1 0 0 2 ids:nodes\",\"depth_used\":12}\n",
                "{\"severity\":1,\"trap_score\":100,\"mass\":1.0,",
                "\"fen\":\"O@O@O@**/O@O@O@**/******** w p p 6 3 6 3 0 0 ",
                "-1 -1 -1 -1 0 0 2 ids:nodes\",\"depth_used\":8}\n",
            ),
        )
        .expect("fixture write must succeed");
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let loaded = load_mine_entry_candidates(
            MineEntryLoadConfig {
                paths: path.to_str().expect("temporary path must be UTF-8"),
                candidate_limit: 4,
                per_shape_limit: 4,
                min_severity: 1,
                min_mass: 0.0,
                min_depth_used: 0,
                min_placements: 12,
                seed: 11,
                spec: SampleSpec {
                    phase: super::super::sampler::PhaseChoice::Placing,
                    side: super::super::sampler::SideChoice::White,
                    min_solver_pieces: 0,
                    max_solver_pieces: 9,
                    min_defender_pieces: 0,
                    max_defender_pieces: 9,
                },
            },
            &rules,
            &options,
        );
        let _ = std::fs::remove_file(path);

        assert_eq!(loaded.candidates.len(), 1);
        assert_eq!(loaded.candidates[0].query.white_in_hand, 3);
        assert_eq!(loaded.candidates[0].query.black_in_hand, 3);
    }
}
