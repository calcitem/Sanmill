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
//   --budget-bytes N   Truncate the mass-sorted entry list (dropping the
//                      lowest-mass entries first) until the compressed
//                      patch fits N bytes (0 = unbounded, default 0). Best
//                      effort, not a hard cap: mid-removal records (see
//                      `build_patch_file`) are never truncated, so if
//                      those alone exceed N the written file still will.
//   --zstd-level N     zstd compression level (default 19; this is an
//                      offline, one-shot build so favor ratio over speed).
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
//   --recompute-from-fen  Re-derive every entry's canonical `key` and
//                      `best_child` from its stored FEN against the live
//                      DB, instead of trusting the values the (possibly
//                      older) `mill mine` run stored. Cheap relative to
//                      mining (no tier-3 engine search): use this to pick
//                      up a canonicalization fix or a tuned recommendation
//                      policy across already-mined JSONL without
//                      re-running the whole pipeline.
//                      (`--recompute-best-child` is accepted as a legacy
//                      alias.)

mod audit;
mod recompute;

use std::collections::HashMap;
use std::io::Write;

use perfect_db::database::FileDatabaseProvider;
use perfect_db::patch::{
    EngineFingerprint, MidRemovalRecord, PackAlgorithm, PackedRecord, PatchFile, SectorGroup,
};
use perfect_db::wdl_plane::unpack_canonical_key;
use tgf_mill::MillVariantOptions;

use crate::cli_args::{flag_present, parse_flag};
use crate::mill_mine::entry::MineEntry;

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

/// Build a [`PatchFile`] from mined entries: dedup by canonical key (keeping
/// the higher-mass copy when the same position was mined more than once),
/// sort by mass descending, optionally truncate to `budget_bytes`, then
/// group into sector-sorted, slot-sorted records.
///
/// `budget_bytes` is best-effort, not a hard cap: mid-removal records are
/// always kept in full regardless of budget (see the comment below), so if
/// those alone compress past `budget_bytes` the returned `PatchFile` still
/// will, even with zero settled entries. In practice this is a non-issue --
/// mid-removal entries are a small slice of any real mining run -- but a
/// caller relying on the output literally fitting under `budget_bytes`
/// should be aware truncation cannot go any lower than that floor.
pub(crate) fn build_patch_file(
    entries: &[MineEntry],
    budget_bytes: usize,
    fingerprint: EngineFingerprint,
    db_path: &std::path::Path,
    variant_name: &str,
) -> PatchFile {
    let mut by_key: HashMap<u64, &MineEntry> = HashMap::new();
    for entry in entries {
        by_key
            .entry(entry.key)
            .and_modify(|incumbent| {
                if entry.mass > incumbent.mass {
                    *incumbent = entry;
                }
            })
            .or_insert(entry);
    }
    // Mid-removal-parented entries (see `perfect_db::mid_removal_key`) use a
    // key space the sector groups cannot represent (there is no meaningful
    // database sector for a pending-removal position); `PatchFile`'s
    // separate `mid_removal_records` list carries them instead (see that
    // module's docs). Always included in full below regardless of
    // `budget_bytes`: they are typically a small slice of the total, and
    // unlike a settled position (reachable again after a different earlier
    // move), a missed removal-choice correction has no substitute --
    // dropping the *lowest-mass* settled entries first is a much smaller
    // loss than dropping any of these. Consequence: `budget_bytes` is a
    // best-effort target, not a hard cap -- see the binary search below and
    // this function's doc comment.
    const MID_REMOVAL_TAG: u64 = 1 << 63;
    let (mid_removal, settled): (Vec<&MineEntry>, Vec<&MineEntry>) = by_key
        .into_values()
        .partition(|e| e.key & MID_REMOVAL_TAG != 0);
    let mid_removal_records = {
        let mut records: Vec<MidRemovalRecord> = mid_removal
            .into_iter()
            .map(|entry| MidRemovalRecord {
                key: entry.key,
                best_child: entry.best_child,
                severity: entry.severity as u8,
                trap_score: entry.trap_score,
            })
            .collect();
        records.sort_by_key(|r| r.key);
        records
    };

    let mut ranked: Vec<&MineEntry> = settled;
    ranked.sort_by(|a, b| b.mass.partial_cmp(&a.mass).expect("mass must be finite"));

    let variant_byte = variant_byte_for(variant_name);
    let secval_bytes = std::fs::read(db_path.join(format!("{variant_name}.secval")))
        .unwrap_or_else(|e| {
            panic!("[patch-pack] cannot read {variant_name}.secval from {db_path:?}: {e}")
        });

    let assemble = |entries: &[&MineEntry]| -> PatchFile {
        let mut sectors: HashMap<(u8, u8, u8, u8), Vec<PackedRecord>> = HashMap::new();
        for entry in entries {
            let (sector_id, slot) = unpack_canonical_key(entry.key);
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
                });
        }
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
            mid_removal_records: mid_removal_records.clone(),
        }
    };

    if budget_bytes == 0 {
        return assemble(&ranked);
    }

    // Binary search the largest mass-sorted prefix whose compressed size
    // fits the budget. Monotonic in prefix length (more entries never
    // shrinks the payload), so binary search is valid; compressing a
    // truncated candidate on every probe is cheap relative to the mining
    // cost that produced these entries. Note this only ever truncates
    // `ranked` (settled entries): if `compressed_len(0)` -- the
    // mid-removal records plus zero settled entries -- already exceeds
    // `budget_bytes`, the loop still converges (to `low == 0`), it just
    // cannot shrink the output any further; see this function's doc
    // comment.
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
    eprintln!(
        "[patch-pack] budget {budget_bytes} bytes kept {low}/{} mass-ranked entries",
        ranked.len()
    );
    assemble(&ranked[..low])
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

    let recompute_from_fen =
        flag_present(args, "--recompute-from-fen") || flag_present(args, "--recompute-best-child");

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

    if recompute_from_fen {
        let options = MillVariantOptions::default();
        recompute::recompute_entries(&mut entries, std::path::Path::new(&db_path), &options);
    }

    let patch = build_patch_file(
        &entries,
        budget_bytes,
        fingerprint,
        std::path::Path::new(&db_path),
        &variant_name,
    );
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

    let uncompressed_estimate: usize =
        4 + sector_count * 8 + (entry_count - mid_removal_count) * 14 + mid_removal_count * 18;
    eprintln!(
        "[patch-pack] wrote {out_path}: {entry_count} entries ({mid_removal_count} \
         mid-removal) across {sector_count} sectors, {} bytes on disk ({:.1}x smaller than \
         the ~{uncompressed_estimate}-byte raw payload)",
        buf.len(),
        uncompressed_estimate as f64 / buf.len().max(1) as f64
    );

    if audit_sample > 0 {
        let options = MillVariantOptions::default();
        let refs: Vec<&MineEntry> = entries.iter().collect();
        let outcome = audit::audit_entries(
            &refs,
            FileDatabaseProvider::new(&db_path),
            &options,
            audit_sample,
            audit_seed,
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

    fn entry(key: u64, best_child: u64, mass: f64) -> MineEntry {
        MineEntry {
            key,
            best_child,
            severity: 1,
            trap_score: 100,
            mass,
            fen: String::new(),
            depth_used: 5,
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
    fn dedup_keeps_the_higher_mass_copy() {
        let entries = vec![entry(1, 100, 5.0), entry(1, 200, 50.0), entry(2, 300, 1.0)];
        let db_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../src/ui/flutter_app/assets/databases");
        let patch = build_patch_file(&entries, 0, default_fingerprint(), &db_root, "std");
        assert_eq!(patch.entry_count(), 2);
        let (sector, slot) = unpack_canonical_key(1);
        let record = patch
            .lookup(
                sector.white_on_board,
                sector.black_on_board,
                sector.white_in_hand,
                sector.black_in_hand,
                slot as u32,
            )
            .unwrap();
        assert_eq!(record.best_child, 200, "the higher-mass duplicate must win");
    }

    #[test]
    fn mid_removal_entries_land_in_their_own_group_deduped_by_mass() {
        const MID_REMOVAL_TAG: u64 = 1 << 63;
        let mid_removal_key = MID_REMOVAL_TAG | 42;
        let entries = vec![
            entry(mid_removal_key, 100, 5.0),
            entry(mid_removal_key, 200, 50.0),
            entry(1, 300, 1.0), // an ordinary settled entry, for contrast
        ];
        let db_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../src/ui/flutter_app/assets/databases");
        let patch = build_patch_file(&entries, 0, default_fingerprint(), &db_root, "std");

        assert_eq!(patch.mid_removal_records.len(), 1);
        assert_eq!(patch.entry_count(), 2, "one settled + one mid-removal");
        let record = patch.lookup_mid_removal(mid_removal_key).unwrap();
        assert_eq!(
            record.best_child, 200,
            "the higher-mass mid-removal duplicate must win, same as settled dedup"
        );
    }

    #[test]
    fn budget_truncates_to_the_highest_mass_entries() {
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
        let full = build_patch_file(&entries, 0, default_fingerprint(), &db_root, "std");
        let mut full_buf = Vec::new();
        full.write_to(&mut full_buf, 3).unwrap();

        let budget = full_buf.len() / 2;
        let truncated = build_patch_file(&entries, budget, default_fingerprint(), &db_root, "std");
        let mut truncated_buf = Vec::new();
        truncated.write_to(&mut truncated_buf, 3).unwrap();

        assert!(truncated_buf.len() <= budget);
        assert!(truncated.entry_count() < full.entry_count());
        // The highest-mass entry (key 0, mass 200) must survive truncation.
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
    fn budget_truncation_never_drops_mid_removal_entries() {
        const MID_REMOVAL_TAG: u64 = 1 << 63;
        let mut entries = Vec::new();
        // A large settled population (so there is genuinely something to
        // truncate) plus one low-mass mid-removal entry that a naive
        // mass-only truncation would drop first.
        for i in 0..20_000_u64 {
            entries.push(entry(i, i + 1_000_000, (20_000 - i) as f64));
        }
        entries.push(entry(MID_REMOVAL_TAG | 7, 999_999, 0.001));

        let db_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../src/ui/flutter_app/assets/databases");
        let full = build_patch_file(&entries, 0, default_fingerprint(), &db_root, "std");
        let mut full_buf = Vec::new();
        full.write_to(&mut full_buf, 3).unwrap();

        let truncated = build_patch_file(
            &entries,
            full_buf.len() / 2,
            default_fingerprint(),
            &db_root,
            "std",
        );
        assert!(
            truncated.entry_count() < full.entry_count(),
            "budget must still truncate settled entries"
        );
        assert_eq!(
            truncated.mid_removal_records.len(),
            1,
            "the sole mid-removal entry must survive despite its negligible mass"
        );
    }
}
