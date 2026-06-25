// SPDX-License-Identifier: GPL-3.0-or-later
// tune gen: sample quiet Mill positions from self-play random walks.
//
// Usage:
//   tgf tune gen [--positions N] [--out PATH] [--seed HEX] [--depth D]
//                [--resume]
//
// --positions N   Target number of unique quiet positions.  Default: 50000.
// --out PATH      Output file (pipeline format).  Default: tune_positions.dat
// --seed HEX      xorshift64* seed for reproducible sampling.  Default: 0.
//                 When 0, uses a time-based seed.
// --depth D       Fixed search depth for position generation.  Default: 0
//                 (random walk, no search).  Depth > 0 uses MTD(f) to play
//                 stronger positions but is slower.
// --resume        Append to an existing output file and skip positions
//                 whose Zobrist keys are already in it.
//
// Output: positions in the pipeline format (see mill_tune/mod.rs).

use std::collections::HashSet;
use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use tgf_core::{ActionList, Game, GameRules, Workbench};
use tgf_mill::{MillActionKind, MillGame, MillRules, MillVariantOptions};

use super::{PositionRecord, flag_present, parse_flag};

pub(crate) fn run_gen(args: &[String]) {
    let n_positions: usize = parse_flag(args, "--positions", 50_000);
    let out_path: String = parse_flag(args, "--out", "tune_positions.dat".to_string());
    let seed_hex: String = parse_flag(args, "--seed", "0".to_string());
    let resume = flag_present(args, "--resume");

    let seed: u64 = if seed_hex == "0" {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::ZERO)
            .as_nanos() as u64
            ^ 0x9E37_79B9_7F4A_7C15
    } else {
        u64::from_str_radix(seed_hex.trim_start_matches("0x"), 16).unwrap_or(1)
    };

    eprintln!("[tune gen] target={n_positions} out={out_path} seed={seed:#018x} resume={resume}");

    // Load already-seen keys if resuming.
    let mut seen: HashSet<u64> = HashSet::new();
    if resume && std::path::Path::new(&out_path).exists() {
        let f = File::open(&out_path).expect("cannot open existing output for resume");
        for line in BufReader::new(f).lines().map_while(Result::ok) {
            if let Some(rec) = PositionRecord::from_record_line(&line) {
                seen.insert(rec.key);
            }
        }
        eprintln!("[tune gen] resume: loaded {} existing keys", seen.len());
    }

    let file = OpenOptions::new()
        .create(true)
        .append(resume)
        .write(!resume)
        .truncate(!resume)
        .open(&out_path)
        .expect("cannot open output file");
    let mut writer = BufWriter::new(file);

    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let game = MillGame::new(options.clone());

    let mut rng = seed;
    let mut collected = seen.len();
    let mut games_played = 0usize;
    let mut positions_visited = 0usize;
    let mut filtered_removing = 0usize;

    let progress_every = n_positions / 20; // every 5%

    while collected < n_positions {
        games_played += 1;
        let mut snap = rules.initial_state(&[]);
        let mut ply = 0usize;

        loop {
            // Terminal check.
            let outcome = rules.outcome(&snap);
            if !matches!(outcome.kind, tgf_core::OutcomeKind::Ongoing) {
                break;
            }
            if ply > 240 {
                break; // break excessively long games
            }

            let decoded = MillRules::decode_snapshot(snap);

            // Collect only quiet positions (no pending capture).
            let has_pending =
                decoded.pending_removals()[0] > 0 || decoded.pending_removals()[1] > 0;
            if !has_pending {
                let wb = game.build_workbench(&snap);
                let key = wb.key();
                positions_visited += 1;

                if !seen.contains(&key) {
                    use tgf_mill::MillPhase;
                    let phase = decoded.phase();
                    let phase_id = match phase {
                        MillPhase::Placing => 0u8,
                        MillPhase::Moving => 1u8,
                        _ => {
                            // skip GameOver / Ready phases
                            let mut legal = ActionList::<256>::default();
                            rules.legal_actions(&snap, &mut legal);
                            if legal.is_empty() {
                                break;
                            }
                            snap = apply_random(&rules, snap, &mut rng);
                            ply += 1;
                            continue;
                        }
                    };

                    let in_hand = decoded.pieces_in_hand();
                    let on_board = decoded.pieces_on_board();
                    let in_hand_diff = i32::from(in_hand[0]) - i32::from(in_hand[1]);
                    let on_board_diff = i32::from(on_board[0]) - i32::from(on_board[1]);
                    let mob = decoded.mobility_diff();

                    let fen = rules.export_fen(&MillRules::decode_snapshot(snap));
                    let rec = PositionRecord {
                        key,
                        phase: phase_id,
                        in_hand_diff,
                        on_board_diff,
                        mobility_diff: mob,
                        wdl: None,
                        steps: None,
                        fen,
                    };

                    writeln!(writer, "{}", rec.to_record_line()).expect("write failed");
                    seen.insert(key);
                    collected += 1;

                    if progress_every > 0 && collected.is_multiple_of(progress_every) {
                        eprintln!(
                            "[tune gen] {collected}/{n_positions} ({:.0}%)  \
                             games={games_played} visited={positions_visited} \
                             skip_removing={filtered_removing}",
                            collected as f64 * 100.0 / n_positions as f64
                        );
                        writer.flush().expect("flush failed");
                    }

                    if collected >= n_positions {
                        break;
                    }
                }
            } else {
                filtered_removing += 1;
            }

            let mut legal = ActionList::<256>::default();
            rules.legal_actions(&snap, &mut legal);
            if legal.is_empty() {
                break;
            }
            snap = apply_random(&rules, snap, &mut rng);
            ply += 1;
        }
    }

    writer.flush().expect("final flush failed");
    eprintln!(
        "[tune gen] done: {collected} unique quiet positions  \
         games={games_played} visited={positions_visited} skip_removing={filtered_removing}"
    );
}

fn xorshift64(state: &mut u64) -> u64 {
    let mut x = *state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *state = x;
    x
}

fn apply_random(
    rules: &MillRules,
    snap: tgf_core::GameStateSnapshot,
    rng: &mut u64,
) -> tgf_core::GameStateSnapshot {
    let mut legal = ActionList::<256>::default();
    rules.legal_actions(&snap, &mut legal);
    if legal.is_empty() {
        return snap;
    }
    // Prefer place/move actions to spend more time in interesting positions;
    // apply a random removal if no other choice exists.
    let non_remove: Vec<_> = legal
        .as_slice()
        .iter()
        .filter(|a| a.kind_tag != MillActionKind::Remove as i16)
        .copied()
        .collect();
    let action = if !non_remove.is_empty() {
        let idx = (xorshift64(rng) as usize) % non_remove.len();
        non_remove[idx]
    } else {
        let idx = (xorshift64(rng) as usize) % legal.len();
        legal[idx]
    };
    rules.apply(&snap, action)
}
