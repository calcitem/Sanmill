// SPDX-License-Identifier: GPL-3.0-or-later
// tune fit: Texel-style logistic regression over labeled Mill positions.
//
// Usage:
//   tgf tune fit [--in PATH] [--out PATH] [--iters N] [--k SCALE]
//               [--holdout FRAC] [--min-delta EPS] [--checkpoint PATH]
//               [--checkpoint-every K] [--resume]
//
// Minimizes:  loss = (1/|S|) Σ (sigmoid(k * eval(w, x)) - result(x))^2
//   where eval(w, x) = piece_value * material_diff(x, phase)
//                    + mobility * mobility_diff(x)
//                    + mill_count * mill_count_diff(x, phase)
//   result(x) = WDL-to-scalar mapping:  1 → 1.0, 0 → 0.5, -1 → 0.0
//                                       (all from side-to-move perspective)
//
// Fitting: coordinate descent (cycles through all weights + k).
// Outputs:  final weights and scaling K printed in `TGF_EVAL_WEIGHTS=...` form.

use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Write};

use tgf_mill::MillEvalWeights;

use super::{PositionRecord, flag_present, parse_flag};

/// One labeled feature vector ready for regression.
#[derive(Clone)]
struct Sample {
    /// Material difference = in_hand_diff + on_board_diff, phase-adjusted.
    /// For placing phase: material = in_hand_diff + on_board_diff
    /// For moving phase:  material = on_board_diff
    material_diff: f64,
    mobility_diff: f64,
    mill_count_diff: f64, // always 0 unless RemovalBasedOnMillCounts variant
    result: f64,          // 1.0 = White win, 0.5 = draw, 0.0 = White loss
}

/// Checkpoint saved/loaded during coordinate descent.
struct Checkpoint {
    iteration: usize,
    piece_value: f64,
    mobility: f64,
    mill_count: f64,
    k: f64,
    best_piece_value: f64,
    best_mobility: f64,
    best_mill_count: f64,
    best_k: f64,
    best_holdout_loss: f64,
    train_loss: f64,
}

fn sigmoid(x: f64) -> f64 {
    1.0 / (1.0 + (-x).exp())
}

fn compute_loss(samples: &[Sample], pv: f64, mob: f64, mc: f64, k: f64) -> f64 {
    if samples.is_empty() {
        return 0.0;
    }
    let sum: f64 = samples
        .iter()
        .map(|s| {
            let eval = pv * s.material_diff + mob * s.mobility_diff + mc * s.mill_count_diff;
            let predicted = sigmoid(k * eval);
            let err = predicted - s.result;
            err * err
        })
        .sum();
    sum / samples.len() as f64
}

/// Current working weights (all four tunable parameters).
struct Params {
    pv: f64,
    mob: f64,
    mc: f64,
    k: f64,
}

impl Params {
    fn loss(&self, samples: &[Sample]) -> f64 {
        compute_loss(samples, self.pv, self.mob, self.mc, self.k)
    }

    /// Tune parameter `idx` (0=pv 1=mob 2=mc 3=k) by `step`; keep best direction.
    fn tune_one(&mut self, samples: &[Sample], idx: usize, step: f64, cur: f64) -> f64 {
        let orig = self.get(idx);
        self.set(idx, orig + step);
        let lp = self.loss(samples);
        self.set(idx, orig - step);
        let lm = self.loss(samples);
        if lp <= lm && lp < cur {
            self.set(idx, orig + step);
            lp
        } else if lm < lp && lm < cur {
            lm
        } else {
            self.set(idx, orig);
            cur
        }
    }

    fn get(&self, idx: usize) -> f64 {
        match idx {
            0 => self.pv,
            1 => self.mob,
            2 => self.mc,
            _ => self.k,
        }
    }

    fn set(&mut self, idx: usize, v: f64) {
        match idx {
            0 => self.pv = v,
            1 => self.mob = v,
            2 => self.mc = v,
            _ => self.k = v,
        }
    }
}

fn save_checkpoint(path: &str, cp: &Checkpoint) {
    let tmp = format!("{path}.tmp");
    let mut f = File::create(&tmp).expect("cannot create checkpoint tmp");
    writeln!(f, "iteration={}", cp.iteration).ok();
    writeln!(f, "piece_value={}", cp.piece_value).ok();
    writeln!(f, "mobility={}", cp.mobility).ok();
    writeln!(f, "mill_count={}", cp.mill_count).ok();
    writeln!(f, "k={}", cp.k).ok();
    writeln!(f, "best_piece_value={}", cp.best_piece_value).ok();
    writeln!(f, "best_mobility={}", cp.best_mobility).ok();
    writeln!(f, "best_mill_count={}", cp.best_mill_count).ok();
    writeln!(f, "best_k={}", cp.best_k).ok();
    writeln!(f, "best_holdout_loss={}", cp.best_holdout_loss).ok();
    writeln!(f, "train_loss={}", cp.train_loss).ok();
    f.flush().ok();
    drop(f);
    fs::rename(&tmp, path).expect("checkpoint rename failed");
}

fn load_checkpoint(path: &str) -> Option<Checkpoint> {
    let f = File::open(path).ok()?;
    let mut kv: HashMap<String, String> = HashMap::new();
    for line in BufReader::new(f).lines().map_while(Result::ok) {
        if let Some((k, v)) = line.split_once('=') {
            kv.insert(k.to_string(), v.to_string());
        }
    }
    let get_f64 = |key: &str| -> Option<f64> { kv.get(key)?.parse::<f64>().ok() };
    let get_usize = |key: &str| -> Option<usize> { kv.get(key)?.parse::<usize>().ok() };
    Some(Checkpoint {
        iteration: get_usize("iteration")?,
        piece_value: get_f64("piece_value")?,
        mobility: get_f64("mobility")?,
        mill_count: get_f64("mill_count")?,
        k: get_f64("k")?,
        best_piece_value: get_f64("best_piece_value")?,
        best_mobility: get_f64("best_mobility")?,
        best_mill_count: get_f64("best_mill_count")?,
        best_k: get_f64("best_k")?,
        best_holdout_loss: get_f64("best_holdout_loss")?,
        train_loss: get_f64("train_loss")?,
    })
}

pub(crate) fn run_fit(args: &[String]) {
    let in_path: String = parse_flag(args, "--in", "tune_labeled.dat".to_string());
    let out_path: String = parse_flag(args, "--out", "tune_weights.txt".to_string());
    let max_iters: usize = parse_flag(args, "--iters", 1000usize);
    let k_init: f64 = parse_flag(args, "--k", 0.1_f64);
    let holdout_frac: f64 = parse_flag(args, "--holdout", 0.2_f64);
    let min_delta: f64 = parse_flag(args, "--min-delta", 1e-7_f64);
    let checkpoint_path: String =
        parse_flag(args, "--checkpoint", "tune_fit.checkpoint".to_string());
    let checkpoint_every: usize = parse_flag(args, "--checkpoint-every", 10usize);
    let resume = flag_present(args, "--resume");
    let dtm_weight: f64 = parse_flag(args, "--dtm-weight", 0.0_f64);

    eprintln!(
        "[tune fit] in={in_path} out={out_path} iters={max_iters} k={k_init} \
         holdout={holdout_frac:.2} min_delta={min_delta:.2e} resume={resume}"
    );

    // Load samples.
    let f =
        File::open(&in_path).unwrap_or_else(|e| panic!("[tune fit] cannot open {in_path}: {e}"));
    let mut all_samples: Vec<Sample> = Vec::new();
    let mut skipped_unlabeled = 0usize;
    let mut win_count = 0usize;
    let mut draw_count = 0usize;
    let mut loss_count = 0usize;

    for line in BufReader::new(f).lines().map_while(Result::ok) {
        if line.trim().is_empty() || line.starts_with('#') {
            continue;
        }
        let Some(rec) = PositionRecord::from_record_line(&line) else {
            continue;
        };
        let Some(wdl) = rec.wdl else {
            skipped_unlabeled += 1;
            continue;
        };
        // Map WDL (side-to-move perspective) to result target in [0,1].
        // When dtm_weight > 0, fine-grade win/loss using steps.
        let base_result = match wdl {
            1 => 1.0_f64,
            0 => 0.5_f64,
            -1 => 0.0_f64,
            _ => continue,
        };
        let result = if dtm_weight > 0.0 {
            if let Some(steps) = rec.steps.filter(|&s| s > 0) {
                // Grade: closer win -> closer to 1.0 / 0.0; far win ~ 0.75 / 0.25.
                let t = 1.0 - (steps as f64 / 100.0_f64).min(1.0);
                if wdl == 1 {
                    0.5 + t * 0.5 * dtm_weight + (1.0 - dtm_weight) * 0.5
                } else if wdl == -1 {
                    0.5 - t * 0.5 * dtm_weight - (1.0 - dtm_weight) * 0.5
                } else {
                    base_result
                }
            } else {
                base_result
            }
        } else {
            base_result
        };

        match wdl {
            1 => win_count += 1,
            0 => draw_count += 1,
            -1 => loss_count += 1,
            _ => {}
        }

        let material_diff = if rec.phase == 0 {
            (rec.in_hand_diff + rec.on_board_diff) as f64
        } else {
            rec.on_board_diff as f64
        };
        all_samples.push(Sample {
            material_diff,
            mobility_diff: rec.mobility_diff as f64,
            mill_count_diff: 0.0, // standard Nine Men's Morris doesn't use this
            result,
        });
    }

    let total_labeled = all_samples.len();
    let label_rate =
        total_labeled as f64 * 100.0 / (total_labeled + skipped_unlabeled).max(1) as f64;
    eprintln!(
        "[tune fit] loaded {total_labeled} labeled ({label_rate:.1}%),  \
         {skipped_unlabeled} skipped-unlabeled"
    );
    eprintln!("[tune fit] label distribution: W={win_count} D={draw_count} L={loss_count}");
    if total_labeled < 100 {
        eprintln!(
            "[tune fit] WARNING: only {total_labeled} labeled samples — \
             results may be unreliable"
        );
    }

    // Split train / holdout deterministically (first 1-frac = train, rest = holdout).
    let n_holdout = ((total_labeled as f64 * holdout_frac) as usize).max(1);
    let n_train = total_labeled - n_holdout;
    let train = &all_samples[..n_train];
    let holdout = &all_samples[n_train..];
    eprintln!(
        "[tune fit] train={n_train} holdout={n_holdout} ({:.0}%)",
        holdout_frac * 100.0
    );

    // Starting weights.
    let legacy = MillEvalWeights::LEGACY;
    let mut w = Params {
        pv: legacy.piece_value as f64,
        mob: legacy.mobility as f64,
        mc: legacy.mill_count as f64,
        k: k_init,
    };
    let mut iter_start = 0usize;
    let mut best = Params {
        pv: w.pv,
        mob: w.mob,
        mc: w.mc,
        k: w.k,
    };
    let mut best_holdout_loss = f64::MAX;

    // Resume from checkpoint if requested.
    if resume && let Some(cp) = load_checkpoint(&checkpoint_path) {
        {
            w.pv = cp.piece_value;
            w.mob = cp.mobility;
            w.mc = cp.mill_count;
            w.k = cp.k;
            iter_start = cp.iteration;
            best.pv = cp.best_piece_value;
            best.mob = cp.best_mobility;
            best.mc = cp.best_mill_count;
            best.k = cp.best_k;
            best_holdout_loss = cp.best_holdout_loss;
            eprintln!(
                "[tune fit] resumed from iter {iter_start}: \
                 pv={:.4} mob={:.4} mc={:.4} k={:.6} best_holdout={best_holdout_loss:.6}",
                w.pv, w.mob, w.mc, w.k
            );
        }
    }

    let initial_train_loss = w.loss(train);
    let initial_holdout_loss = w.loss(holdout);
    eprintln!(
        "[tune fit] initial losses: train={initial_train_loss:.6} holdout={initial_holdout_loss:.6}"
    );
    if best_holdout_loss == f64::MAX {
        best_holdout_loss = initial_holdout_loss;
    }

    let step_sizes = [0.5_f64, 0.1, 0.01, 0.001];
    let k_steps = [0.05_f64, 0.01, 0.001, 0.0001];

    for iter in iter_start..max_iters {
        let mut changed = false;
        for (step_idx, &step) in step_sizes.iter().enumerate() {
            for param in 0..3usize {
                let prev = w.loss(train);
                let next = w.tune_one(train, param, step, prev);
                if (prev - next).abs() > min_delta * 0.01 {
                    changed = true;
                }
            }
            // Tune k separately.
            let prev = w.loss(train);
            let k_step = k_steps[step_idx.min(k_steps.len() - 1)];
            let next = w.tune_one(train, 3, k_step, prev);
            if (prev - next).abs() > min_delta * 0.01 {
                changed = true;
            }
        }

        let train_loss = w.loss(train);
        let holdout_loss = w.loss(holdout);

        // Track best by holdout loss.
        if holdout_loss < best_holdout_loss {
            best_holdout_loss = holdout_loss;
            best.pv = w.pv;
            best.mob = w.mob;
            best.mc = w.mc;
            best.k = w.k;
        }

        if (iter + 1).is_multiple_of(checkpoint_every) || !changed {
            eprintln!(
                "[tune fit] iter {:>4}/{max_iters}: \
                 pv={:+.4} mob={:+.4} mc={:+.4} k={:.5}  \
                 train={train_loss:.6} holdout={holdout_loss:.6}  \
                 best_holdout={best_holdout_loss:.6}",
                iter + 1,
                w.pv,
                w.mob,
                w.mc,
                w.k
            );
            save_checkpoint(
                &checkpoint_path,
                &Checkpoint {
                    iteration: iter + 1,
                    piece_value: w.pv,
                    mobility: w.mob,
                    mill_count: w.mc,
                    k: w.k,
                    best_piece_value: best.pv,
                    best_mobility: best.mob,
                    best_mill_count: best.mc,
                    best_k: best.k,
                    best_holdout_loss,
                    train_loss,
                },
            );
        }

        if !changed || train_loss < min_delta {
            eprintln!(
                "[tune fit] converged after {} iterations (delta < {min_delta})",
                iter + 1
            );
            break;
        }
    }

    // Use best.* throughout the remainder.
    let best_pv = best.pv;
    let best_mob = best.mob;
    let best_mc = best.mc;
    let best_k = best.k;
    let final_train = compute_loss(train, best_pv, best_mob, best_mc, best_k);
    let final_holdout = compute_loss(holdout, best_pv, best_mob, best_mc, best_k);

    // Quantize to i32 (round to nearest, clamp within mate gap).
    //
    // MILL_TERMINAL_WIN_SCORE = 80.  In the worst case, placing-phase eval
    // applies piece_value to (in_hand_diff + on_board_diff) which can reach
    // ±9 (one side has 9 pieces, the other 0).  To keep non-mate eval within
    // the mate boundary: piece_value * 9 < 80  =>  piece_value <= 8.
    // We leave a further margin and cap at 7 to stay well below the boundary
    // even when mobility (max ~24) or remove terms add to the total.
    const MAX_PIECE_VALUE: i32 = 7;
    let q_pv = (best_pv.round() as i32).clamp(1, MAX_PIECE_VALUE);
    let q_mob = best_mob.round() as i32;
    let q_mc = best_mc.round() as i32;

    eprintln!("[tune fit] BEST weights (holdout={final_holdout:.6} train={final_train:.6}):");
    eprintln!(
        "  float: piece_value={best_pv:.4} mobility={best_mob:.4} mill_count={best_mc:.4} k={best_k:.6}"
    );
    eprintln!("  i32:   piece_value={q_pv} mobility={q_mob} mill_count={q_mc}");
    eprintln!();
    eprintln!("  Inject:  TGF_EVAL_WEIGHTS={q_pv},{q_mob},{q_mc}");
    eprintln!("  Verify:  TGF_EVAL_WEIGHTS={q_pv},{q_mob},{q_mc} SKILL=30 MOVETIME_MS=200 \\");
    eprintln!("    GAMES=10000 JOBS=20 bash scripts/run_h2h_head_vs_parent.sh");

    // Write weights artifact.
    let mut out = File::create(&out_path)
        .unwrap_or_else(|e| panic!("[tune fit] cannot create output {out_path}: {e}"));
    writeln!(out, "# Mill eval weights — generated by tgf tune fit").ok();
    writeln!(out, "# Final best by holdout loss").ok();
    writeln!(
        out,
        "# Float: piece_value={best_pv:.4} mobility={best_mob:.4} mill_count={best_mc:.4} k={best_k:.6}"
    )
    .ok();
    writeln!(
        out,
        "# Quantized: piece_value={q_pv} mobility={q_mob} mill_count={q_mc}"
    )
    .ok();
    writeln!(
        out,
        "# Losses: train={final_train:.8} holdout={final_holdout:.8}"
    )
    .ok();
    writeln!(out, "# Samples: train={n_train} holdout={n_holdout}").ok();
    writeln!(out).ok();
    writeln!(out, "TGF_EVAL_WEIGHTS={q_pv},{q_mob},{q_mc}").ok();
    out.flush().ok();

    eprintln!("[tune fit] weights written to {out_path}");

    // Feature contribution analysis.
    let total = (all_samples.len() as f64).max(1.0);
    let avg_mat: f64 = all_samples
        .iter()
        .map(|s| s.material_diff.abs())
        .sum::<f64>()
        / total;
    let avg_mob: f64 = all_samples
        .iter()
        .map(|s| s.mobility_diff.abs())
        .sum::<f64>()
        / total;
    let contrib_mat = best_pv.abs() * avg_mat;
    let contrib_mob = best_mob.abs() * avg_mob;
    let total_contrib = contrib_mat + contrib_mob + 1e-9;
    eprintln!("[tune fit] feature contribution (avg |weight×feature|):");
    eprintln!(
        "  material  : {:.2}% (pv={best_pv:.3} × avg_mat={avg_mat:.2})",
        contrib_mat / total_contrib * 100.0
    );
    eprintln!(
        "  mobility  : {:.2}% (mob={best_mob:.3} × avg_mob={avg_mob:.2})",
        contrib_mob / total_contrib * 100.0
    );
}
