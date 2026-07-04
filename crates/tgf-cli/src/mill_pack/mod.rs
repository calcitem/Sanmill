// SPDX-License-Identifier: AGPL-3.0-or-later
// tgf mill patch-pack: turn one or more `mill mine` JSONL outputs into the
// compact binary patch format assets can bundle.
//
// Usage:
//   tgf mill patch-pack --in PATH[,PATH...] --db PATH --out PATH [options]
//
// Required:
//   --in PATHS       Comma-separated `mill mine` JSONL output file(s).
//   --db PATH        Perfect DB root directory (needs at least the
//                     variant's `.secval` file, embedded verbatim in the
//                     patch header as a lightweight DB-identity check).
//   --out PATH       Output patch file path.
//
// Budget / selection:
//   --budget-bytes N   Truncate the pool-ranked entry list (severity-0
//                      steering entries are dropped first, then the
//                      lowest-mass blunders) until the compressed patch
//                      fits N bytes (0 = unbounded, default 0). Reaching
//                      into the blunder pool is an error unless
//                      --allow-trim-blunders is passed. Best effort, not
//                      a hard cap: mid-removal records (see
//                      `build_patch_file`) are never truncated, so if
//                      those alone exceed N the written file still will.
//   --allow-trim-blunders  Explicitly allow the budget to drop severity>0
//                      corrections (default off; the trim count and mass
//                      are reported when it happens).
//   --zstd-level N     zstd compression level (default 19; this is an
//                      offline, one-shot build so favor ratio over speed).
//
// Experimental steering risk gate (default fully inert):
//   --steering-risk-gate MODE  none (default) | absolute | sibling-delta
//                      | net.
//                      absolute / sibling-delta are MASK-ONLY (stored
//                      nibbles stay the raw trap gain): absolute keeps a
//                      positive candidate iff own_risk <= lambda *
//                      trap_density; sibling-delta keeps it iff its
//                      own-risk excess over the safest resolved sibling
//                      is covered by lambda times its trap-density excess
//                      over the least-trappy resolved sibling.
//                      net REWRITES the stored value to the net score
//                      (gain_nibble - lambda * own_risk on the nibble
//                      scale, dropped from the mask when it reaches 0):
//                      the runtime's strictly-greater tie-break then
//                      compares baseline-relative nets pairwise, with no
//                      engine change. own_risk is the corrected own-TURN
//                      risk (see recompute::RiskMemo): the blunder
//                      density our side faces after the opponent's value
//                      -preserving reply -- walking through their single
//                      pending-removal layer when the reply forms a mill.
//                      With ANY active gate the severity-0 min-gap check
//                      runs on the POST-gate effective vector (see
//                      derive_child_proof), so uninformative records are
//                      judged by what they can actually steer.
//   --steering-risk-lambda F   Risk budget multiplier (default 1.0).
//   --steering-min-placing-ply-proxy N  Parents with fewer than N pieces
//                      already placed carry no steering mask (proxy, not
//                      real ply: placements only; moving-phase positions
//                      saturate at 2*piece_count and always pass).
//                      Activates the gate even with mode none.
//
// HumanDB behavior weighting (v4 trap nibbles):
//   --human-db PATH    NMM_LLM human_db.sqlite to weight trap scores by
//                      observed human replies (or SANMILL_HUMAN_DB env).
//                      A configured but unusable database is a hard error,
//                      never a silent fallback to uniform density.
//   --disable-human-weighting  Kill switch: fully bypasses opening the
//                      database (uniform geometric density only).
//   --human-min-samples N    Minimum scored reply weight per position
//                      before behavior data replaces uniform density
//                      (default 10).
//   --human-min-coverage F   Minimum scored/raw weight share (default 0.8).
//   --human-shrinkage-k F    Shrinkage pseudo-samples toward uniform
//                      density (default 30).
//   --allow-human-db-lossy   Proceed past the parser-invalid hard limit
//                      (default: hard error above 5% invalid weight).
//
// Engine fingerprint (must match what `mill mine` used; defaults mirror
// `mill mine`'s own defaults):
//   --skill-level, --depth, --near-optimal-margin, --top-k, --epsilon
//
// Variant (currently informational only -- see below):
//   --variant std      Must be "std" (the default) if passed at all.
//                      patch-pack only ever builds "std" (Standard / Nine
//                      Men's Morris) patches today: `--in` entries carry
//                      no variant tag of their own, `PatchFile.variant_byte`
//                      is hardcoded to std, and only `std.secval` is read
//                      from `--db`. Passing `lask`/`mora` is rejected
//                      outright rather than silently mislabeling
//                      Lasker/Morabaraba entries as std (see
//                      `assert_entries_fit_std_budget`); wiring up real
//                      multi-variant support needs `mill mine`'s JSONL
//                      format to carry the variant it was mined under.
//
// Audit:
//   --audit-sample N   After packing, independently re-verify N sampled
//                      records against the live database (default 200;
//                      0 disables).
//   --audit-seed HEX   Deterministic sample seed (default fixed constant).
//
// Maintenance:
//   --recompute-from-fen  Accepted for compatibility but now always on:
//                      the v3 patch format's per-record optimal-set proof
//                      (see `perfect_db::patch::PackedRecord::optimal_mask`)
//                      can only be derived against the live DB, and the
//                      same pass re-derives every entry's canonical `key`
//                      and `best_child` from its stored FEN while it is
//                      at it. Cheap relative to mining (no tier-3 engine
//                      search). Entries whose FEN no longer re-derives
//                      (parse failure, DB coverage gap) are dropped with a
//                      count, since a proof-less record could never
//                      legitimately fire at runtime.
//                      (`--recompute-best-child` is accepted as a legacy
//                      alias.)

mod audit;
mod human_weight;
mod recompute;

use std::collections::HashMap;
use std::io::Write;

use perfect_db::database::FileDatabaseProvider;
use perfect_db::patch::{
    EngineFingerprint, MID_REMOVAL_RECORD_SIZE, MidRemovalRecord, PackAlgorithm, PackedRecord,
    PatchFile, RECORD_SIZE, SectorGroup,
};
use perfect_db::wdl_plane::unpack_canonical_key;
use tgf_mill::MillVariantOptions;

use crate::cli_args::{flag_present, parse_flag, parse_flag_strict};
use crate::mill_mine::entry::MineEntry;
use recompute::ChildProof;

pub(crate) fn default_fingerprint() -> EngineFingerprint {
    EngineFingerprint {
        algorithm: PackAlgorithm::Mtdf,
        skill_level: 30,
        depth_override: 0,
        near_optimal_margin: 0,
        consider_mobility: true,
        focus_on_blocking_paths: false,
        draw_on_human_experience: true,
        ai_is_lazy: false,
        top_k: 3,
        epsilon: 0.15,
    }
}

fn variant_byte_for(name: &str) -> u8 {
    match name {
        "lask" | "lasker" => 1,
        "mora" | "morabaraba" => 2,
        _ => 0,
    }
}

/// `patch-pack` only supports building "std" (Standard / Nine Men's
/// Morris, 9 pieces per side) patches today -- see this module's doc
/// comment. Feeding it JSONL mined under a different `--variant` (e.g.
/// `mill mine --variant lask`) would otherwise be silently packed with
/// `variant_byte_for("std")` and `std.secval` regardless, producing a
/// patch that *claims* to be std but decodes keys from a different
/// variant's sector space.
///
/// Catches the common case cheaply: every settled (non-mid-removal)
/// entry's key decodes to a sector whose piece counts must fit the
/// variant it was mined under, so a sector that needs more than std's
/// 9-piece budget can only have come from Lasker (10) or Morabaraba (12).
/// Mid-removal entries are skipped: their key space is hash-addressed,
/// not sector-addressed, so it carries no piece-count signal to check.
fn assert_entries_fit_std_budget(entries: &[MineEntry]) {
    const MID_REMOVAL_TAG: u64 = 1 << 63;
    const STD_PIECE_COUNT: u8 = 9;
    for entry in entries {
        if entry.key & MID_REMOVAL_TAG != 0 {
            continue;
        }
        let (sector, _slot) = unpack_canonical_key(entry.key);
        let key = entry.key;
        let fen = &entry.fen;
        assert!(
            sector.white_on_board + sector.white_in_hand <= STD_PIECE_COUNT
                && sector.black_on_board + sector.black_in_hand <= STD_PIECE_COUNT,
            "[patch-pack] entry key {key:#x} (fen {fen}) needs more than the \
             std variant's {STD_PIECE_COUNT}-piece budget (sector {sector:?}) \
             -- was --in populated from a `mill mine --variant lask|mora` \
             run by mistake? patch-pack only supports std today."
        );
    }
}

/// Parse the experimental risk-gate flags into a [`recompute::RiskGateConfig`].
///
/// Strict by design: missing flags fall back to the inert defaults
/// (`none` / `1.0` / `0`), but a flag that is PRESENT with a missing,
/// malformed, or out-of-range value is an `Err` (the caller exits
/// nonzero). The gate configures long paired-H2H experiment matrices --
/// a silently defaulted parameter would run a configuration that was
/// never asked for and poison the comparison.
fn parse_risk_gate(args: &[String]) -> Result<recompute::RiskGateConfig, String> {
    let mode_name: String = parse_flag_strict(args, "--steering-risk-gate", "none".to_string())?;
    let mode = match mode_name.as_str() {
        "none" => recompute::RiskGateMode::None,
        "absolute" => recompute::RiskGateMode::Absolute,
        "sibling-delta" => recompute::RiskGateMode::SiblingDelta,
        "net" => recompute::RiskGateMode::Net,
        other => {
            return Err(format!(
                "--steering-risk-gate {other} is not a known mode \
                 (expected none | absolute | sibling-delta | net)"
            ));
        }
    };
    let lambda: f64 = parse_flag_strict(args, "--steering-risk-lambda", 1.0_f64)?;
    if !lambda.is_finite() || lambda < 0.0 {
        return Err(format!(
            "--steering-risk-lambda must be finite and >= 0, got {lambda}"
        ));
    }
    Ok(recompute::RiskGateConfig {
        mode,
        lambda,
        min_placing_ply_proxy: parse_flag_strict(args, "--steering-min-placing-ply-proxy", 0_u32)?,
    })
}

/// What the budget truncation actually dropped -- returned alongside the
/// file so trimming real corrections is never a silent event.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub(crate) struct BuildTrimStats {
    /// Kept prefix of the budget-ranked pool (settled entries plus
    /// mid-removal steering entries; mid-removal blunders sit outside the
    /// pool and are always kept).
    pub kept_ranked: usize,
    pub trimmed_steering: usize,
    pub trimmed_blunders: usize,
    pub trimmed_blunder_mass: f64,
}

/// Build a [`PatchFile`] from **already deduplicated** mined entries (see
/// `recompute::dedup_entries`, the single authoritative same-key rule):
/// rank blunders (severity desc, mass desc) ahead of severity-0 steering
/// entries, optionally truncate to `budget_bytes`, then group into
/// sector-sorted, slot-sorted records.
///
/// Truncation drops steering entries first (settled and mid-removal
/// steering share one budget pool, so Phase 2's steering mining cannot
/// bloat the asset through the mid-removal side door); reaching into the
/// blunder pool is an `Err` unless `allow_trim_blunders` (an explicit CLI
/// opt-in, default off) is set, and even then the trim is reported through
/// [`BuildTrimStats`] and the caller's log.
///
/// `budget_bytes` is best-effort, not a hard cap: mid-removal *blunder*
/// records are always kept in full regardless of budget (see the comment
/// below), so if those alone compress past `budget_bytes` the returned
/// `PatchFile` still will, even with zero pooled entries (that state also
/// requires `allow_trim_blunders`, since it means blunders were dropped or
/// the floor itself overflows the budget).
pub(crate) fn build_patch_file(
    entries: &[MineEntry],
    proofs: &HashMap<u64, ChildProof>,
    budget_bytes: usize,
    allow_trim_blunders: bool,
    fingerprint: EngineFingerprint,
    db_path: &std::path::Path,
    variant_name: &str,
) -> Result<(PatchFile, BuildTrimStats), String> {
    // Deduplication policy lives in exactly one place
    // (`recompute::dedup_entries`); this builder only asserts the caller
    // honored it rather than silently applying a second, different rule.
    // A duplicate here is a pipeline bug, not a data condition.
    {
        let mut seen = std::collections::HashSet::with_capacity(entries.len());
        for entry in entries {
            assert!(
                seen.insert(entry.key),
                "[patch-pack] duplicate key {:#x} reached build_patch_file -- entries must go \
                 through recompute::dedup_entries first",
                entry.key
            );
        }
    }
    // Mid-removal-parented entries (see `perfect_db::mid_removal_key`) use a
    // key space the sector groups cannot represent (there is no meaningful
    // database sector for a pending-removal position); `PatchFile`'s
    // separate `mid_removal_records` list carries them instead (see that
    // module's docs).
    //
    // Mid-removal *blunders* (severity > 0) are always included in full
    // regardless of `budget_bytes`: they are typically a small slice of the
    // total, and unlike a settled position (reachable again after a
    // different earlier move), a missed removal-choice correction has no
    // substitute. Mid-removal *steering* entries (severity 0) get no such
    // privilege -- they join the ranked pool below and are trimmed together
    // with settled steering, so `budget_bytes` genuinely bounds the
    // steering share of the asset.
    const MID_REMOVAL_TAG: u64 = 1 << 63;
    let is_mid_removal = |e: &MineEntry| e.key & MID_REMOVAL_TAG != 0;
    let mid_blunders: Vec<&MineEntry> = entries
        .iter()
        .filter(|e| is_mid_removal(e) && e.severity > 0)
        .collect();
    let pooled: Vec<&MineEntry> = entries
        .iter()
        .filter(|e| !is_mid_removal(e) || e.severity == 0)
        .collect();
    let proof_for = |entry: &MineEntry| -> ChildProof {
        *proofs.get(&entry.key).unwrap_or_else(|| {
            panic!(
                "[patch-pack] entry key {:#x} has no optimal-set proof -- \
                 proof-less entries must be dropped before packing",
                entry.key
            )
        })
    };
    let mid_record_for = |entry: &MineEntry| -> MidRemovalRecord {
        let proof = proof_for(entry);
        MidRemovalRecord {
            key: entry.key,
            best_child: entry.best_child,
            severity: entry.severity as u8,
            trap_score: entry.trap_score,
            child_count: proof.child_count,
            optimal_mask: proof.optimal_mask,
            trap_score_mask: proof.trap_score_mask,
            optimal_trap_nibbles: proof.optimal_trap_nibbles,
        }
    };
    let mid_blunder_records: Vec<MidRemovalRecord> =
        mid_blunders.iter().map(|e| mid_record_for(e)).collect();

    // Pool-aware ranking: blunder corrections (severity > 0) sort ahead of
    // severity-0 steering entries, so budget truncation always drops
    // steering first and only ever reaches into the blunder pool with the
    // caller's explicit consent.
    let mut ranked: Vec<&MineEntry> = pooled;
    ranked.sort_by(|a, b| {
        ((b.severity > 0) as u8, b.severity, b.mass)
            .partial_cmp(&((a.severity > 0) as u8, a.severity, a.mass))
            .expect("mass must be finite")
    });
    let pooled_blunders = ranked.iter().filter(|e| e.severity > 0).count();

    let variant_byte = variant_byte_for(variant_name);
    let secval_bytes = std::fs::read(db_path.join(format!("{variant_name}.secval")))
        .unwrap_or_else(|e| {
            panic!("[patch-pack] cannot read {variant_name}.secval from {db_path:?}: {e}")
        });

    let assemble = |kept: &[&MineEntry]| -> PatchFile {
        let mut sectors: HashMap<(u8, u8, u8, u8), Vec<PackedRecord>> = HashMap::new();
        let mut mid_records = mid_blunder_records.clone();
        for entry in kept {
            if is_mid_removal(entry) {
                mid_records.push(mid_record_for(entry));
                continue;
            }
            let (sector_id, slot) = unpack_canonical_key(entry.key);
            let proof = proof_for(entry);
            sectors
                .entry((
                    sector_id.white_on_board,
                    sector_id.black_on_board,
                    sector_id.white_in_hand,
                    sector_id.black_in_hand,
                ))
                .or_default()
                .push(PackedRecord {
                    slot: slot as u32,
                    best_child: entry.best_child,
                    severity: entry.severity as u8,
                    trap_score: entry.trap_score,
                    child_count: proof.child_count,
                    optimal_mask: proof.optimal_mask,
                    trap_score_mask: proof.trap_score_mask,
                    optimal_trap_nibbles: proof.optimal_trap_nibbles,
                });
        }
        mid_records.sort_by_key(|r| r.key);
        let mut groups: Vec<SectorGroup> = sectors
            .into_iter()
            .map(|((w, b, wf, bf), mut records)| {
                records.sort_by_key(|r| r.slot);
                SectorGroup {
                    white_on_board: w,
                    black_on_board: b,
                    white_in_hand: wf,
                    black_in_hand: bf,
                    records,
                }
            })
            .collect();
        groups.sort_by_key(|s| {
            (
                s.white_on_board,
                s.black_on_board,
                s.white_in_hand,
                s.black_in_hand,
            )
        });
        PatchFile {
            variant_byte,
            fingerprint,
            secval_bytes: secval_bytes.clone(),
            sectors: groups,
            mid_removal_records: mid_records,
        }
    };

    if budget_bytes == 0 {
        let stats = BuildTrimStats {
            kept_ranked: ranked.len(),
            ..BuildTrimStats::default()
        };
        return Ok((assemble(&ranked), stats));
    }

    // Binary search the largest pool-ranked prefix whose compressed size
    // fits the budget. Monotonic in prefix length (more entries never
    // shrinks the payload), so binary search is valid; compressing a
    // truncated candidate on every probe is cheap relative to the mining
    // cost that produced these entries.
    let compressed_len = |count: usize| -> usize {
        let patch = assemble(&ranked[..count]);
        let mut buf = Vec::new();
        patch
            .write_to(&mut buf, 3)
            .expect("probe compression must succeed");
        buf.len()
    };

    let mut low = 0_usize;
    let mut high = ranked.len();
    while low < high {
        let mid = low + (high - low).div_ceil(2);
        if compressed_len(mid) <= budget_bytes {
            low = mid;
        } else {
            high = mid - 1;
        }
    }
    // Trimming into the blunder pool (severity > 0 pooled entries, or the
    // always-kept mid-removal blunders not fitting at all) is a
    // configuration error by default: the budget was sized too small for
    // the data. Fail fast unless the caller explicitly allowed it.
    if low < pooled_blunders && !allow_trim_blunders {
        return Err(format!(
            "budget {budget_bytes} bytes only fits {low} of {pooled_blunders} blunder \
             corrections (plus {} always-kept mid-removal blunder records); refusing to trim \
             real corrections -- raise --budget-bytes or pass --allow-trim-blunders",
            mid_blunder_records.len()
        ));
    }
    if low == 0 && compressed_len(0) > budget_bytes && !allow_trim_blunders {
        return Err(format!(
            "budget {budget_bytes} bytes cannot even hold the {} mid-removal blunder records; \
             raise --budget-bytes or pass --allow-trim-blunders",
            mid_blunder_records.len()
        ));
    }
    let trimmed_blunder_slice = &ranked[low..pooled_blunders.max(low).min(ranked.len())];
    let stats = BuildTrimStats {
        kept_ranked: low,
        trimmed_steering: ranked.len().saturating_sub(low.max(pooled_blunders)),
        trimmed_blunders: trimmed_blunder_slice.len(),
        trimmed_blunder_mass: trimmed_blunder_slice.iter().map(|e| e.mass).sum(),
    };
    eprintln!(
        "[patch-pack] budget {budget_bytes} bytes kept {low}/{} pool-ranked entries \
         ({pooled_blunders} blunders ranked first; {} mid-removal blunders always kept)",
        ranked.len(),
        mid_blunder_records.len()
    );
    if stats.trimmed_blunders > 0 {
        eprintln!(
            "[patch-pack] WARNING: --allow-trim-blunders dropped {} blunder corrections \
             (total mass {:.3}) to meet the budget",
            stats.trimmed_blunders, stats.trimmed_blunder_mass
        );
    }
    Ok((assemble(&ranked[..low]), stats))
}

/// Full-scan invariant: every packed record's proof fields must equal the
/// recompute pipeline's derivation, key by key. This is not a sampled
/// diagnostic -- a single divergence means two nibble implementations
/// drifted apart and the file must not ship.
fn verify_packed_fields_match_proofs(
    patch: &PatchFile,
    proofs: &HashMap<u64, recompute::ChildProof>,
) {
    let check = |key: u64,
                 child_count: u8,
                 optimal_mask: u64,
                 trap_score_mask: u64,
                 optimal_trap_nibbles: u64| {
        let proof = proofs
            .get(&key)
            .unwrap_or_else(|| panic!("packed record {key:#x} has no proof"));
        assert!(
            proof.child_count == child_count
                && proof.optimal_mask == optimal_mask
                && proof.trap_score_mask == trap_score_mask
                && proof.optimal_trap_nibbles == optimal_trap_nibbles,
            "packed record {key:#x} diverged from its derived proof"
        );
    };
    for sector in &patch.sectors {
        let id = perfect_db::file_format::SectorId::new(
            sector.white_on_board,
            sector.black_on_board,
            sector.white_in_hand,
            sector.black_in_hand,
        );
        for record in &sector.records {
            let key = perfect_db::wdl_plane::pack_canonical_key(id, record.slot as usize);
            check(
                key,
                record.child_count,
                record.optimal_mask,
                record.trap_score_mask,
                record.optimal_trap_nibbles,
            );
        }
    }
    for record in &patch.mid_removal_records {
        check(
            record.key,
            record.child_count,
            record.optimal_mask,
            record.trap_score_mask,
            record.optimal_trap_nibbles,
        );
    }
    eprintln!("[patch-pack] packed-field verification: all records match their derived proofs");
}

pub(crate) fn run_patch_pack(args: &[String]) {
    let in_paths: String = parse_flag(args, "--in", String::new());
    let db_path: String = parse_flag(args, "--db", String::new());
    let out_path: String = parse_flag(args, "--out", String::new());
    if in_paths.is_empty() || db_path.is_empty() || out_path.is_empty() {
        eprintln!("[patch-pack] ERROR: --in, --db, and --out are all required");
        eprintln!(
            "  Example: tgf mill patch-pack --in mine_entries.jsonl --db D:/user/Documents/strong --out std.mill_patch"
        );
        std::process::exit(1);
    }
    let variant_name: String = parse_flag(args, "--variant", "std".to_string());
    if !matches!(variant_name.as_str(), "std" | "standard") {
        eprintln!(
            "[patch-pack] ERROR: --variant {variant_name} is not supported yet -- \
             patch-pack only builds \"std\" (Standard / Nine Men's Morris) \
             patches today; see this module's doc comment"
        );
        std::process::exit(1);
    }
    let budget_bytes: usize = parse_flag(args, "--budget-bytes", 0usize);
    let zstd_level: i32 = parse_flag(args, "--zstd-level", 19i32);
    let audit_sample: usize = parse_flag(args, "--audit-sample", 200usize);
    let audit_seed: u64 = {
        let hex: String = parse_flag(args, "--audit-seed", "9E3779B97F4A7C15".to_string());
        u64::from_str_radix(hex.trim_start_matches("0x"), 16).unwrap_or(0x9E37_79B9_7F4A_7C15)
    };

    let fingerprint = EngineFingerprint {
        skill_level: parse_flag(args, "--skill-level", default_fingerprint().skill_level),
        depth_override: parse_flag(args, "--depth", default_fingerprint().depth_override),
        near_optimal_margin: parse_flag(
            args,
            "--near-optimal-margin",
            default_fingerprint().near_optimal_margin,
        ),
        top_k: parse_flag(args, "--top-k", default_fingerprint().top_k),
        epsilon: parse_flag(args, "--epsilon", default_fingerprint().epsilon),
        ..default_fingerprint()
    };

    // Always-on since patch format v3 (the optimal-set proof requires the
    // same live-DB pass); accepted so existing invocations keep working.
    let _legacy_recompute_flag =
        flag_present(args, "--recompute-from-fen") || flag_present(args, "--recompute-best-child");

    // HumanDB behavior weighting: `--human-db PATH` (or SANMILL_HUMAN_DB)
    // enables it; `--disable-human-weighting` is the kill switch and fully
    // bypasses even opening the file (so a broken database can be routed
    // around and A/B packs stay honest).
    let human_db_flag: String = parse_flag(args, "--human-db", String::new());
    let human_db_env = std::env::var("SANMILL_HUMAN_DB").unwrap_or_default();
    let disable_human = flag_present(args, "--disable-human-weighting");
    let human_db_path = if disable_human {
        None
    } else if !human_db_flag.trim().is_empty() {
        Some(std::path::PathBuf::from(human_db_flag.trim()))
    } else if !human_db_env.trim().is_empty() {
        Some(std::path::PathBuf::from(human_db_env.trim()))
    } else {
        None
    };
    let human_config = human_weight::HumanWeightConfig {
        min_samples: parse_flag(args, "--human-min-samples", 10_u64),
        min_coverage: parse_flag(args, "--human-min-coverage", 0.8_f64),
        shrinkage_k: parse_flag(args, "--human-shrinkage-k", 30.0_f64),
        allow_lossy: flag_present(args, "--allow-human-db-lossy"),
    };

    let mut entries: Vec<MineEntry> = Vec::new();
    for path in in_paths.split(',') {
        let path = path.trim();
        if path.is_empty() {
            continue;
        }
        let text = std::fs::read_to_string(path)
            .unwrap_or_else(|e| panic!("[patch-pack] cannot read {path}: {e}"));
        let mut count = 0_usize;
        for line in text.lines() {
            if line.trim().is_empty() {
                continue;
            }
            let entry: MineEntry = serde_json::from_str(line)
                .unwrap_or_else(|e| panic!("[patch-pack] malformed entry in {path}: {e}"));
            entries.push(entry);
            count += 1;
        }
        eprintln!("[patch-pack] loaded {count} entries from {path}");
    }
    if entries.is_empty() {
        eprintln!("[patch-pack] ERROR: no entries loaded from --in {in_paths}");
        std::process::exit(1);
    }
    assert_entries_fit_std_budget(&entries);

    let options = MillVariantOptions::default();
    let steering_min_gap: u8 = parse_flag(args, "--steering-min-gap", 3_u8);
    let risk_gate = parse_risk_gate(args).unwrap_or_else(|message| {
        eprintln!("[patch-pack] ERROR: {message}");
        std::process::exit(1);
    });
    let outcome = match recompute::recompute_entries(
        entries,
        std::path::Path::new(&db_path),
        &options,
        human_db_path.as_deref(),
        human_config,
        steering_min_gap,
        risk_gate,
    ) {
        Ok(outcome) => outcome,
        Err(message) => {
            eprintln!("[patch-pack] ERROR: {message}");
            std::process::exit(1);
        }
    };
    let entries = outcome.entries;
    let proofs = outcome.proofs;
    let outcome_trap_scores = outcome.trap_score_by_key;
    let outcome_human = outcome.human;
    if entries.is_empty() {
        eprintln!("[patch-pack] ERROR: no entries survived proof derivation");
        std::process::exit(1);
    }
    {
        // Pack-level steering coverage: how many records actually carry a
        // positive trap signal (the make-traps feature's reach).
        let with_signal = proofs
            .values()
            .filter(|proof| proof.trap_score_mask != 0)
            .count();
        eprintln!(
            "[patch-pack] steering coverage: {with_signal}/{} records carry trap scores \
             (empty-mask records: {})",
            proofs.len(),
            outcome.stats.empty_trap_mask_records
        );
    }

    let allow_trim_blunders = flag_present(args, "--allow-trim-blunders");
    let (patch, trim_stats) = match build_patch_file(
        &entries,
        &proofs,
        budget_bytes,
        allow_trim_blunders,
        fingerprint,
        std::path::Path::new(&db_path),
        &variant_name,
    ) {
        Ok(built) => built,
        Err(message) => {
            eprintln!("[patch-pack] ERROR: {message}");
            std::process::exit(1);
        }
    };
    eprintln!(
        "[patch-pack] retention: kept {} pool-ranked entries, trimmed {} steering / {} blunders \
         (trimmed blunder mass {:.3})",
        trim_stats.kept_ranked,
        trim_stats.trimmed_steering,
        trim_stats.trimmed_blunders,
        trim_stats.trimmed_blunder_mass
    );
    {
        // Pool composition of the shipped file (steering pool must be
        // non-empty whenever steering entries were fed and survived).
        let packed_steering = patch
            .sectors
            .iter()
            .flat_map(|s| s.records.iter().map(|r| r.severity))
            .chain(patch.mid_removal_records.iter().map(|r| r.severity))
            .filter(|&severity| severity == 0)
            .count();
        let packed_blunders = patch.entry_count() - packed_steering;
        eprintln!(
            "[patch-pack] pools in file: blunders={packed_blunders} steering={packed_steering} \
             (steering trimmed by budget: {})",
            trim_stats.trimmed_steering
        );
    }
    verify_packed_fields_match_proofs(&patch, &proofs);
    let entry_count = patch.entry_count();
    let sector_count = patch.sectors.len();
    let mid_removal_count = patch.mid_removal_records.len();

    let mut buf = Vec::new();
    patch
        .write_to(&mut buf, zstd_level)
        .unwrap_or_else(|e| panic!("[patch-pack] failed to serialize patch: {e}"));
    std::fs::File::create(&out_path)
        .and_then(|mut f| f.write_all(&buf))
        .unwrap_or_else(|e| panic!("[patch-pack] cannot write {out_path}: {e}"));

    let uncompressed_estimate: usize = 4
        + sector_count * 8
        + (entry_count - mid_removal_count) * RECORD_SIZE
        + mid_removal_count * MID_REMOVAL_RECORD_SIZE;
    eprintln!(
        "[patch-pack] wrote {out_path}: {entry_count} entries ({mid_removal_count} \
         mid-removal) across {sector_count} sectors, {} bytes on disk ({:.1}x smaller than \
         the ~{uncompressed_estimate}-byte raw payload)",
        buf.len(),
        uncompressed_estimate as f64 / buf.len().max(1) as f64
    );

    // Reopen the shipped bytes through the runtime loader: this exercises
    // the full read path (decompression, v4 record validation, secval
    // bootstrap) on the exact artifact and pins its entry count to the
    // pack log above.
    {
        let shipped = std::fs::read(&out_path)
            .unwrap_or_else(|e| panic!("[patch-pack] cannot re-read {out_path}: {e}"));
        let reopened = perfect_db::patch::PatchLookup::open(&shipped)
            .unwrap_or_else(|e| panic!("[patch-pack] runtime reopen of {out_path} failed: {e}"));
        assert_eq!(
            reopened.entry_count(),
            entry_count,
            "[patch-pack] runtime loader sees a different entry count than the pack wrote"
        );
        eprintln!(
            "[patch-pack] runtime reopen OK: PatchLookup::open({out_path}) -> {} entries",
            reopened.entry_count()
        );
    }

    if audit_sample > 0 {
        // Audit the final retained set only: entries the budget dropped
        // never reached the file, so sampling them would validate nothing.
        // The audit also re-derives each sampled entry's proof in the same
        // HumanDB context (see `audit_entries`); combined with the
        // full-scan packed-field verification above, a passing sample
        // validates the shipped bytes end to end.
        let refs: Vec<&MineEntry> = entries
            .iter()
            .filter(|entry| {
                const MID_REMOVAL_TAG: u64 = 1 << 63;
                if entry.key & MID_REMOVAL_TAG != 0 {
                    // Tagged hash keys carry no sector fields; unpacking
                    // one would tear random bits into an (asserting)
                    // SectorId.
                    patch.lookup_mid_removal(entry.key).is_some()
                } else {
                    let (sector_id, slot) = unpack_canonical_key(entry.key);
                    patch
                        .lookup(
                            sector_id.white_on_board,
                            sector_id.black_on_board,
                            sector_id.white_in_hand,
                            sector_id.black_in_hand,
                            slot as u32,
                        )
                        .is_some()
                }
            })
            .collect();
        eprintln!(
            "[patch-pack] auditing over the {} retained entries (of {} deduplicated)",
            refs.len(),
            entries.len()
        );
        let outcome = audit::audit_entries(
            &refs,
            FileDatabaseProvider::new(&db_path),
            &options,
            audit_sample,
            audit_seed,
            &proofs,
            &outcome_trap_scores,
            outcome_human.as_ref(),
            risk_gate,
        );
        if outcome.failures.is_empty() {
            eprintln!(
                "[patch-pack] audit: {}/{} sampled entries verified OK",
                outcome.checked, outcome.checked
            );
        } else {
            eprintln!(
                "[patch-pack] audit: {} FAILURES out of {} sampled entries:",
                outcome.failures.len(),
                outcome.checked
            );
            for failure in &outcome.failures {
                eprintln!("  - {failure}");
            }
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use recompute::dedup_entries;

    fn entry(key: u64, best_child: u64, mass: f64) -> MineEntry {
        entry_with_severity(key, best_child, mass, 1)
    }

    fn entry_with_severity(key: u64, best_child: u64, mass: f64, severity: i8) -> MineEntry {
        MineEntry {
            key,
            best_child,
            severity,
            trap_score: 100,
            mass,
            fen: String::new(),
            depth_used: 5,
        }
    }

    /// Synthetic optimal-set proofs for offline tests that bypass the live
    /// DB pass (`recompute_entries`) and call `build_patch_file` directly.
    fn proofs_for(entries: &[MineEntry]) -> HashMap<u64, ChildProof> {
        entries
            .iter()
            .map(|entry| {
                (
                    entry.key,
                    ChildProof {
                        child_count: 2,
                        optimal_mask: 0b01,
                        trap_score_mask: 0,
                        optimal_trap_nibbles: 0,
                    },
                )
            })
            .collect()
    }

    fn argv(tokens: &[&str]) -> Vec<String> {
        tokens.iter().map(|token| token.to_string()).collect()
    }

    #[test]
    fn parse_risk_gate_defaults_are_inert_when_flags_are_absent() {
        let gate = parse_risk_gate(&argv(&[])).expect("absent flags fall back to defaults");
        assert_eq!(gate, recompute::RiskGateConfig::default());
        assert!(!gate.active());
    }

    #[test]
    fn parse_risk_gate_accepts_valid_configurations_in_both_flag_forms() {
        let gate = parse_risk_gate(&argv(&[
            "--steering-risk-gate",
            "sibling-delta",
            "--steering-risk-lambda",
            "0.75",
            "--steering-min-placing-ply-proxy",
            "6",
        ]))
        .expect("a valid configuration");
        assert_eq!(gate.mode, recompute::RiskGateMode::SiblingDelta);
        assert_eq!(gate.lambda, 0.75);
        assert_eq!(gate.min_placing_ply_proxy, 6);

        let gate = parse_risk_gate(&argv(&["--steering-risk-gate=absolute"]))
            .expect("the equals form parses too");
        assert_eq!(gate.mode, recompute::RiskGateMode::Absolute);
        assert_eq!(gate.lambda, 1.0, "unset lambda keeps its default");
    }

    #[test]
    fn parse_risk_gate_rejects_present_but_broken_values() {
        // A present flag must never silently fall back to its default:
        // that would run a gate configuration nobody asked for and
        // poison a paired-H2H matrix.
        let broken: &[&[&str]] = &[
            &["--steering-risk-gate", "bogus"],
            &["--steering-risk-gate"], // present without a value
            &["--steering-risk-lambda", "abc"],
            &["--steering-risk-lambda"], // present without a value
            &["--steering-risk-lambda", "-0.5"],
            &["--steering-risk-lambda", "NaN"],
            &["--steering-risk-lambda", "inf"],
            &["--steering-min-placing-ply-proxy", "-1"],
            &["--steering-min-placing-ply-proxy", "4.5"],
            &["--steering-min-placing-ply-proxy="], // empty equals form
        ];
        for tokens in broken {
            assert!(
                parse_risk_gate(&argv(tokens)).is_err(),
                "{tokens:?} must be rejected, not defaulted"
            );
        }
    }

    #[test]
    #[should_panic(expected = "needs more than the std variant's 9-piece budget")]
    fn assert_entries_fit_std_budget_rejects_a_lasker_shaped_key() {
        // 0 on board + 10 in hand per side is a valid Lasker (10-piece)
        // sector but already exceeds std's 9-piece cap.
        let key = perfect_db::wdl_plane::pack_canonical_key(
            perfect_db::file_format::SectorId::new(0, 0, 10, 10),
            0,
        );
        assert_entries_fit_std_budget(&[entry(key, 0, 1.0)]);
    }

    #[test]
    fn assert_entries_fit_std_budget_accepts_std_shaped_and_mid_removal_entries() {
        let std_key = perfect_db::wdl_plane::pack_canonical_key(
            perfect_db::file_format::SectorId::new(3, 3, 3, 3),
            0,
        );
        const MID_REMOVAL_TAG: u64 = 1 << 63;
        let mid_removal_key = MID_REMOVAL_TAG | 99;
        // Must not panic.
        assert_entries_fit_std_budget(&[entry(std_key, 0, 1.0), entry(mid_removal_key, 0, 1.0)]);
    }

    #[test]
    fn dedup_prefers_blunders_then_severity_then_mass() {
        // Same key: a high-mass severity-0 steering entry must NOT displace
        // a low-mass real blunder; within blunders, severity beats mass;
        // equal severity falls back to mass.
        let deduped = dedup_entries(vec![
            entry_with_severity(1, 100, 999.0, 0),
            entry_with_severity(1, 200, 1.0, 1),
            entry_with_severity(2, 300, 1.0, 1),
            entry_with_severity(2, 400, 999.0, 2),
            entry_with_severity(3, 500, 5.0, 1),
            entry_with_severity(3, 600, 50.0, 1),
        ]);
        let by_key: HashMap<u64, &MineEntry> = deduped.iter().map(|e| (e.key, e)).collect();
        assert_eq!(deduped.len(), 3);
        assert_eq!(
            by_key[&1].best_child, 200,
            "severity>0 must beat a higher-mass steering entry"
        );
        assert_eq!(
            by_key[&2].best_child, 400,
            "higher severity wins regardless of mass ordering"
        );
        assert_eq!(
            by_key[&3].best_child, 600,
            "equal severity falls back to the higher-mass copy"
        );
    }

    #[test]
    #[should_panic(expected = "duplicate key")]
    fn build_patch_file_asserts_on_duplicate_keys() {
        let entries = vec![entry(1, 100, 5.0), entry(1, 200, 50.0)];
        let db_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../src/ui/flutter_app/assets/databases");
        let _ = build_patch_file(
            &entries,
            &proofs_for(&entries),
            0,
            false,
            default_fingerprint(),
            &db_root,
            "std",
        );
    }

    #[test]
    fn mid_removal_entries_land_in_their_own_group() {
        const MID_REMOVAL_TAG: u64 = 1 << 63;
        let mid_removal_key = MID_REMOVAL_TAG | 42;
        let entries = dedup_entries(vec![
            entry(mid_removal_key, 100, 5.0),
            entry(mid_removal_key, 200, 50.0),
            entry(1, 300, 1.0), // an ordinary settled entry, for contrast
        ]);
        let db_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../src/ui/flutter_app/assets/databases");
        let (patch, _) = build_patch_file(
            &entries,
            &proofs_for(&entries),
            0,
            false,
            default_fingerprint(),
            &db_root,
            "std",
        )
        .expect("no budget, must build");

        assert_eq!(patch.mid_removal_records.len(), 1);
        assert_eq!(patch.entry_count(), 2, "one settled + one mid-removal");
        let record = patch.lookup_mid_removal(mid_removal_key).unwrap();
        assert_eq!(
            record.best_child, 200,
            "the higher-mass mid-removal duplicate must win, same as settled dedup"
        );
    }

    #[test]
    fn budget_truncates_to_the_highest_mass_entries_when_trimming_is_allowed() {
        // Enough entries that the (fixed-size, ~7KB for the bundled std
        // asset) header + zstd frame overhead is a small fraction of the
        // total, so the budget genuinely exercises entry truncation instead
        // of being dominated by fixed costs no truncation can shrink.
        let mut entries = Vec::new();
        for i in 0..20_000_u64 {
            entries.push(entry(i, i + 1_000_000, (20_000 - i) as f64));
        }
        let db_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../src/ui/flutter_app/assets/databases");
        let proofs = proofs_for(&entries);
        let (full, _) = build_patch_file(
            &entries,
            &proofs,
            0,
            false,
            default_fingerprint(),
            &db_root,
            "std",
        )
        .expect("no budget, must build");
        let mut full_buf = Vec::new();
        full.write_to(&mut full_buf, 3).unwrap();

        let budget = full_buf.len() / 2;
        // Every entry is a severity-1 blunder, so trimming into the pool
        // needs the explicit override...
        let (truncated, trim_stats) = build_patch_file(
            &entries,
            &proofs,
            budget,
            true,
            default_fingerprint(),
            &db_root,
            "std",
        )
        .expect("--allow-trim-blunders permits trimming");
        assert_eq!(
            trim_stats.trimmed_blunders,
            entries.len() - trim_stats.kept_ranked,
            "every dropped entry here is a blunder"
        );
        assert!(
            trim_stats.trimmed_blunder_mass > 0.0,
            "the trim must report the sacrificed mass"
        );
        let mut truncated_buf = Vec::new();
        truncated.write_to(&mut truncated_buf, 3).unwrap();

        assert!(truncated_buf.len() <= budget);
        assert!(truncated.entry_count() < full.entry_count());
        // The highest-mass entry (key 0) must survive truncation.
        let (sector, slot) = unpack_canonical_key(0);
        assert!(
            truncated
                .lookup(
                    sector.white_on_board,
                    sector.black_on_board,
                    sector.white_in_hand,
                    sector.black_in_hand,
                    slot as u32
                )
                .is_some()
        );
    }

    #[test]
    fn budget_that_cuts_into_blunders_fails_fast_by_default() {
        let mut entries = Vec::new();
        for i in 0..20_000_u64 {
            entries.push(entry(i, i + 1_000_000, (20_000 - i) as f64));
        }
        let db_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../src/ui/flutter_app/assets/databases");
        let proofs = proofs_for(&entries);
        let (full, _) = build_patch_file(
            &entries,
            &proofs,
            0,
            false,
            default_fingerprint(),
            &db_root,
            "std",
        )
        .expect("no budget, must build");
        let mut full_buf = Vec::new();
        full.write_to(&mut full_buf, 3).unwrap();

        let err = match build_patch_file(
            &entries,
            &proofs,
            full_buf.len() / 2,
            false,
            default_fingerprint(),
            &db_root,
            "std",
        ) {
            Err(message) => message,
            Ok(_) => panic!("a budget that trims real corrections must be rejected by default"),
        };
        assert!(
            err.contains("refusing to trim real corrections"),
            "unexpected error: {err}"
        );
    }

    #[test]
    fn budget_trims_steering_entries_before_touching_blunders() {
        // Half the settled entries are severity-0 steering with HIGHER mass
        // than the blunders; the pool ranking must still sacrifice them
        // first and keep every blunder without needing the override.
        let mut entries = Vec::new();
        for i in 0..4_000_u64 {
            entries.push(entry_with_severity(i, i + 1_000_000, 1000.0 + i as f64, 0));
        }
        for i in 4_000..8_000_u64 {
            entries.push(entry_with_severity(i, i + 1_000_000, (8_000 - i) as f64, 1));
        }
        let db_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../src/ui/flutter_app/assets/databases");
        let proofs = proofs_for(&entries);
        let (full, _) = build_patch_file(
            &entries,
            &proofs,
            0,
            false,
            default_fingerprint(),
            &db_root,
            "std",
        )
        .expect("no budget, must build");
        let mut full_buf = Vec::new();
        full.write_to(&mut full_buf, 3).unwrap();

        // A budget that fits the blunders plus a bit must keep ALL blunders
        // and drop only steering entries -- no override needed.
        let blunders_only: Vec<MineEntry> =
            entries.iter().filter(|e| e.severity > 0).cloned().collect();
        let (blunders_patch, _) = build_patch_file(
            &blunders_only,
            &proofs,
            0,
            false,
            default_fingerprint(),
            &db_root,
            "std",
        )
        .expect("no budget, must build");
        let mut blunders_buf = Vec::new();
        blunders_patch.write_to(&mut blunders_buf, 3).unwrap();
        let budget = blunders_buf.len() + (full_buf.len() - blunders_buf.len()) / 4;

        let (truncated, trim_stats) = build_patch_file(
            &entries,
            &proofs,
            budget,
            false,
            default_fingerprint(),
            &db_root,
            "std",
        )
        .expect("steering-only trimming needs no override");
        assert_eq!(trim_stats.trimmed_blunders, 0);
        assert!(trim_stats.trimmed_steering > 0);
        let kept_blunders = truncated
            .sectors
            .iter()
            .flat_map(|s| s.records.iter())
            .filter(|r| r.severity > 0)
            .count();
        assert_eq!(
            kept_blunders, 4_000,
            "every blunder must survive while steering absorbs the budget"
        );
        assert!(
            truncated.entry_count() < full.entry_count(),
            "some steering entries must actually have been dropped"
        );
    }

    #[test]
    fn budget_trims_mid_removal_steering_but_never_mid_removal_blunders() {
        const MID_REMOVAL_TAG: u64 = 1 << 63;
        let mut entries = Vec::new();
        // A settled blunder population to give the file real bulk...
        for i in 0..4_000_u64 {
            entries.push(entry_with_severity(i, i + 1_000_000, (4_000 - i) as f64, 1));
        }
        // ...a large mid-removal STEERING population that must be poolable
        // (higher mass than the blunders, so a naive always-keep or a
        // mass-only ranking would both get this wrong)...
        for i in 0..4_000_u64 {
            entries.push(entry_with_severity(
                MID_REMOVAL_TAG | i,
                i + 2_000_000,
                5_000.0 + i as f64,
                0,
            ));
        }
        // ...and one low-mass mid-removal BLUNDER that must survive any
        // budget regardless.
        entries.push(entry_with_severity(MID_REMOVAL_TAG | 9_999, 999, 0.001, 1));

        let db_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../src/ui/flutter_app/assets/databases");
        let proofs = proofs_for(&entries);
        let (full, _) = build_patch_file(
            &entries,
            &proofs,
            0,
            false,
            default_fingerprint(),
            &db_root,
            "std",
        )
        .expect("no budget, must build");
        let mut full_buf = Vec::new();
        full.write_to(&mut full_buf, 3).unwrap();
        assert_eq!(full.mid_removal_records.len(), 4_001);

        // A budget below the full size must shed mid-removal steering
        // records (they are the lowest pool tier together with settled
        // steering) without touching any blunder and without the override.
        let (truncated, trim_stats) = build_patch_file(
            &entries,
            &proofs,
            full_buf.len() * 3 / 4,
            false,
            default_fingerprint(),
            &db_root,
            "std",
        )
        .expect("steering-only trimming needs no override");
        assert_eq!(trim_stats.trimmed_blunders, 0);
        assert!(trim_stats.trimmed_steering > 0);
        assert!(
            truncated.mid_removal_records.len() < full.mid_removal_records.len(),
            "mid-removal steering must participate in budget truncation"
        );
        let kept_mid_blunders = truncated
            .mid_removal_records
            .iter()
            .filter(|r| r.severity > 0)
            .count();
        assert_eq!(
            kept_mid_blunders, 1,
            "the mid-removal blunder must survive every budget"
        );
        let kept_settled_blunders: usize = truncated
            .sectors
            .iter()
            .flat_map(|s| s.records.iter())
            .filter(|r| r.severity > 0)
            .count();
        assert_eq!(
            kept_settled_blunders, 4_000,
            "settled blunders must all survive a steering-level trim"
        );
    }

    #[test]
    fn verify_packed_fields_match_proofs_accepts_a_faithful_pack() {
        let entries = dedup_entries(vec![entry(1, 100, 5.0), entry(2, 300, 1.0)]);
        let db_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../src/ui/flutter_app/assets/databases");
        let proofs = proofs_for(&entries);
        let (patch, _) = build_patch_file(
            &entries,
            &proofs,
            0,
            false,
            default_fingerprint(),
            &db_root,
            "std",
        )
        .expect("no budget, must build");
        verify_packed_fields_match_proofs(&patch, &proofs);
    }

    #[test]
    #[should_panic(expected = "diverged from its derived proof")]
    fn verify_packed_fields_match_proofs_rejects_a_diverging_record() {
        let entries = dedup_entries(vec![entry(1, 100, 5.0)]);
        let db_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../src/ui/flutter_app/assets/databases");
        let proofs = proofs_for(&entries);
        let (patch, _) = build_patch_file(
            &entries,
            &proofs,
            0,
            false,
            default_fingerprint(),
            &db_root,
            "std",
        )
        .expect("no budget, must build");
        let mut tampered = proofs.clone();
        tampered.get_mut(&1).unwrap().optimal_mask = 0b11;
        verify_packed_fields_match_proofs(&patch, &tampered);
    }
}
