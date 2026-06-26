// SPDX-License-Identifier: GPL-3.0-or-later
// tune fit: phase-aware Texel-style regression over labeled Mill positions.

use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Write};
use std::time::Instant;

use tgf_mill::{
    MillEvalFeatureSet, MillEvalWeights, MillPhase, MillPhaseEvalWeights, MillRules,
    MillVariantOptions,
};

use super::{PositionRecord, flag_present, parse_flag};

const PHASE_COUNT: usize = 4;
const FEATURE_COUNT: usize = 6;
const PARAM_COUNT: usize = PHASE_COUNT * FEATURE_COUNT;
const PHASE_NAMES: [&str; PHASE_COUNT] = ["placing", "moving", "pre_fly", "flying"];
const FEATURE_NAMES: [&str; FEATURE_COUNT] = [
    "piece_value",
    "mobility",
    "mill_count",
    "position_value",
    "cardinal_mill",
    "near_fly_bonus",
];
const MAX_NON_MATE_EVAL: f64 = 70.0;

/// L2 regularization prior per feature: the LEGACY weights `{5,1,1}` plus zero
/// for the new structural features.  Pulling toward this prior makes an
/// unsupported phase or a sparse feature (e.g. `cardinal_mill`, non-zero in
/// very few positions) fall back to baseline behaviour instead of fitting
/// extreme, sign-flipped noise.
const PRIOR: [f64; FEATURE_COUNT] = [5.0, 1.0, 1.0, 0.0, 0.0, 0.0];

#[derive(Clone)]
struct Sample {
    phase: usize,
    features: [f64; FEATURE_COUNT],
    result: f64,
    weight: f64,
}

#[derive(Clone, Copy)]
struct Params {
    weights: [[f64; FEATURE_COUNT]; PHASE_COUNT],
    k: f64,
}

impl Params {
    fn from_eval_weights(weights: MillEvalWeights, k: f64) -> Self {
        Self {
            weights: [
                phase_to_array(weights.placing),
                phase_to_array(weights.moving_open),
                phase_to_array(weights.pre_fly),
                phase_to_array(weights.flying),
            ],
            k,
        }
    }

    /// Pure weighted mean-squared error (no regularization).  Used for the
    /// holdout split and best-so-far selection so validation reflects real
    /// predictive error rather than the training penalty.
    fn data_loss(&self, samples: &[Sample]) -> f64 {
        if samples.is_empty() {
            return 0.0;
        }
        let mut weighted_sum = 0.0;
        let mut weight_sum = 0.0;
        for sample in samples {
            let eval = dot(self.weights[sample.phase], sample.features);
            let predicted = sigmoid(self.k * eval);
            let err = predicted - sample.result;
            weighted_sum += sample.weight * err * err;
            weight_sum += sample.weight;
        }
        weighted_sum / weight_sum.max(1e-9)
    }

    /// L2 penalty pulling every phase weight toward `PRIOR` (k is exempt).
    fn l2_penalty(&self) -> f64 {
        let mut penalty = 0.0;
        for phase in &self.weights {
            for (feature, &w) in phase.iter().enumerate() {
                let delta = w - PRIOR[feature];
                penalty += delta * delta;
            }
        }
        penalty
    }

    /// Training objective minimised by coordinate descent: data loss plus the
    /// L2 penalty.  Holdout/best selection use `data_loss` instead.
    fn objective(&self, samples: &[Sample], lambda: f64) -> f64 {
        self.data_loss(samples) + lambda * self.l2_penalty()
    }

    fn tune_one(
        &mut self,
        samples: &[Sample],
        idx: usize,
        step: f64,
        cur: f64,
        lambda: f64,
    ) -> f64 {
        let orig = self.get(idx);
        self.set(idx, orig + step);
        let lp = self.objective(samples, lambda);
        self.set(idx, orig - step);
        let lm = self.objective(samples, lambda);
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
        if idx == PARAM_COUNT {
            self.k
        } else {
            self.weights[idx / FEATURE_COUNT][idx % FEATURE_COUNT]
        }
    }

    fn set(&mut self, idx: usize, value: f64) {
        if idx == PARAM_COUNT {
            self.k = value;
        } else {
            self.weights[idx / FEATURE_COUNT][idx % FEATURE_COUNT] = value;
        }
    }
}

struct Checkpoint {
    iteration: usize,
    current: Params,
    best: Params,
    best_holdout_loss: f64,
    train_loss: f64,
}

#[derive(Clone, Copy, Default)]
struct PhaseCounts {
    samples: usize,
    win: usize,
    draw: usize,
    loss: usize,
}

impl PhaseCounts {
    fn add(&mut self, wdl: i32) {
        self.samples += 1;
        match wdl {
            1 => self.win += 1,
            0 => self.draw += 1,
            -1 => self.loss += 1,
            _ => {}
        }
    }
}

fn sigmoid(x: f64) -> f64 {
    1.0 / (1.0 + (-x).exp())
}

/// Deterministic Fisher-Yates shuffle (xorshift64* RNG) so the train/holdout
/// split is representative even when the input file is ordered by phase or
/// game frequency.  A fixed seed keeps the result reproducible.
fn shuffle_samples(samples: &mut [Sample], seed: u64) {
    let mut state = seed | 1; // avoid the xorshift all-zero fixed point
    for i in (1..samples.len()).rev() {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        let j = (state % (i as u64 + 1)) as usize;
        samples.swap(i, j);
    }
}

fn dot(weights: [f64; FEATURE_COUNT], features: [f64; FEATURE_COUNT]) -> f64 {
    weights
        .iter()
        .zip(features.iter())
        .map(|(w, x)| w * x)
        .sum()
}

fn phase_to_array(phase: MillPhaseEvalWeights) -> [f64; FEATURE_COUNT] {
    [
        phase.piece_value as f64,
        phase.mobility as f64,
        phase.mill_count as f64,
        phase.position_value as f64,
        phase.cardinal_mill as f64,
        phase.near_fly_bonus as f64,
    ]
}

fn feature_array(features: MillEvalFeatureSet) -> [f64; FEATURE_COUNT] {
    [
        features.material_diff as f64,
        features.mobility_diff as f64,
        features.mill_count_diff as f64,
        features.position_value_diff as f64,
        features.cardinal_mill_diff as f64,
        features.near_fly_diff as f64,
    ]
}

fn save_checkpoint(path: &str, cp: &Checkpoint) {
    let tmp = format!("{path}.tmp");
    let mut f = File::create(&tmp).expect("cannot create checkpoint tmp");
    writeln!(f, "iteration={}", cp.iteration).ok();
    writeln!(f, "k={}", cp.current.k).ok();
    writeln!(f, "best_k={}", cp.best.k).ok();
    writeln!(f, "best_holdout_loss={}", cp.best_holdout_loss).ok();
    writeln!(f, "train_loss={}", cp.train_loss).ok();
    for phase in 0..PHASE_COUNT {
        for feature in 0..FEATURE_COUNT {
            writeln!(
                f,
                "w_{phase}_{feature}={}",
                cp.current.weights[phase][feature]
            )
            .ok();
            writeln!(
                f,
                "best_w_{phase}_{feature}={}",
                cp.best.weights[phase][feature]
            )
            .ok();
        }
    }
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
    let mut current = Params::from_eval_weights(MillEvalWeights::LEGACY, get_f64("k")?);
    let mut best = Params::from_eval_weights(MillEvalWeights::LEGACY, get_f64("best_k")?);
    for phase in 0..PHASE_COUNT {
        for feature in 0..FEATURE_COUNT {
            current.weights[phase][feature] = get_f64(&format!("w_{phase}_{feature}"))?;
            best.weights[phase][feature] = get_f64(&format!("best_w_{phase}_{feature}"))?;
        }
    }
    Some(Checkpoint {
        iteration: get_usize("iteration")?,
        current,
        best,
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
    // Deterministic shuffle seed for the train/holdout split.  The dataset
    // arrives in a content-correlated order (tune-gen-human sorts by game
    // frequency, so placing dominates the head and flying the tail); a plain
    // prefix/suffix split would put unlike phases in train vs holdout and make
    // the holdout loss meaningless.  Shuffle first so both halves share the
    // same phase mix.  Fixed default keeps runs reproducible.
    let shuffle_seed: u64 = parse_flag(args, "--shuffle-seed", 0x9E37_79B9_7F4A_7C15_u64);
    // L2 regularization strength toward PRIOR.  Suppresses overfitting on
    // sparse features and small phase buckets; 0 disables it.
    let l2_lambda: f64 = parse_flag(args, "--l2-lambda", 0.001_f64);
    // Phases with fewer labeled samples than this are folded into moving_open
    // instead of being fit independently (avoids 21-sample phases fitting six
    // weights).  0 disables folding.
    let min_phase_samples: usize = parse_flag(args, "--min-phase-samples", 500usize);
    let dtm_weight: f64 = parse_flag(args, "--dtm-weight", 0.0_f64);
    let placing_weight: f64 = parse_flag(args, "--placing-weight", 0.2_f64);
    let moving_weight: f64 = parse_flag(args, "--moving-weight", 1.0_f64);
    let pre_fly_weight: f64 = parse_flag(args, "--pre-fly-weight", 1.0_f64);
    let flying_weight: f64 = parse_flag(args, "--flying-weight", 1.0_f64);
    let phase_weights = [placing_weight, moving_weight, pre_fly_weight, flying_weight];

    eprintln!(
        "[tune fit] in={in_path} out={out_path} iters={max_iters} k={k_init} \
         holdout={holdout_frac:.2} min_delta={min_delta:.2e} resume={resume}"
    );
    eprintln!(
        "[tune fit] phase sample weights: placing={placing_weight:.2} \
         moving={moving_weight:.2} pre_fly={pre_fly_weight:.2} flying={flying_weight:.2}"
    );
    eprintln!(
        "[tune fit] l2_lambda={l2_lambda} min_phase_samples={min_phase_samples} \
         shuffle_seed={shuffle_seed:#018x}"
    );

    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let f =
        File::open(&in_path).unwrap_or_else(|e| panic!("[tune fit] cannot open {in_path}: {e}"));
    let mut all_samples: Vec<Sample> = Vec::new();
    let mut skipped_unlabeled = 0usize;
    let mut skipped_zero_weight = 0usize;
    let mut phase_counts = [PhaseCounts::default(); PHASE_COUNT];

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
        let base_result = match wdl {
            1 => 1.0_f64,
            0 => 0.5_f64,
            -1 => 0.0_f64,
            _ => continue,
        };
        let result = dtm_adjusted_result(base_result, wdl, rec.steps, dtm_weight);

        let (phase, features) = features_for_record(&rules, &options, &rec);
        let weight = phase_weights[phase];
        phase_counts[phase].add(wdl);
        if weight <= 0.0 {
            skipped_zero_weight += 1;
            continue;
        }
        all_samples.push(Sample {
            phase,
            features,
            result,
            weight,
        });
    }

    let total_labeled = all_samples.len();
    let label_rate =
        total_labeled as f64 * 100.0 / (total_labeled + skipped_unlabeled).max(1) as f64;
    eprintln!(
        "[tune fit] loaded {total_labeled} weighted labeled ({label_rate:.1}%), \
         {skipped_unlabeled} skipped-unlabeled, {skipped_zero_weight} skipped-zero-weight"
    );
    print_phase_distribution(phase_counts);
    if total_labeled < 100 {
        eprintln!("[tune fit] WARNING: only {total_labeled} samples; results may be unreliable");
    }

    // Fold phases with too few samples into moving_open before fitting so a
    // 21-sample bucket cannot fit six independent weights.  moving_open itself
    // is never folded.
    let active_phase: [bool; PHASE_COUNT] =
        std::array::from_fn(|p| p == 1 || phase_counts[p].samples >= min_phase_samples);
    let mut folded = 0usize;
    for sample in all_samples.iter_mut() {
        if !active_phase[sample.phase] {
            sample.phase = 1;
            folded += 1;
        }
    }
    for (p, name) in PHASE_NAMES.iter().enumerate() {
        if !active_phase[p] {
            eprintln!(
                "[tune fit] phase '{name}' has {} samples (< {min_phase_samples}); \
                 folded into moving_open",
                phase_counts[p].samples
            );
        }
    }
    if folded > 0 {
        eprintln!("[tune fit] folded {folded} samples into moving_open");
    }

    // Shuffle before splitting so train and holdout share the same phase mix
    // regardless of the input file's ordering (see shuffle_seed comment above).
    shuffle_samples(&mut all_samples, shuffle_seed);
    eprintln!("[tune fit] shuffled samples with seed {shuffle_seed:#018x} before split");

    let n_holdout = ((total_labeled as f64 * holdout_frac) as usize).max(1);
    let n_train = total_labeled.saturating_sub(n_holdout);
    assert!(
        n_train > 0,
        "tune-fit requires at least one training sample after holdout split"
    );
    let train = &all_samples[..n_train];
    let holdout = &all_samples[n_train..];
    eprintln!(
        "[tune fit] train={n_train} holdout={n_holdout} ({:.0}%)",
        holdout_frac * 100.0
    );

    let mut w = Params::from_eval_weights(MillEvalWeights::LEGACY, k_init);
    let mut iter_start = 0usize;
    let mut best = w;
    let mut best_holdout_loss = f64::MAX;

    if resume && let Some(cp) = load_checkpoint(&checkpoint_path) {
        w = cp.current;
        best = cp.best;
        iter_start = cp.iteration;
        best_holdout_loss = cp.best_holdout_loss;
        eprintln!(
            "[tune fit] resumed from iter {iter_start}: k={:.6} best_holdout={best_holdout_loss:.6}",
            w.k
        );
    }

    let initial_train_loss = w.data_loss(train);
    let initial_holdout_loss = w.data_loss(holdout);
    eprintln!(
        "[tune fit] initial losses: train={initial_train_loss:.6} holdout={initial_holdout_loss:.6}"
    );
    if best_holdout_loss == f64::MAX {
        best_holdout_loss = initial_holdout_loss;
    }

    let step_sizes = [0.5_f64, 0.1, 0.01, 0.001];
    let k_steps = [0.05_f64, 0.01, 0.001, 0.0001];
    let fit_start = Instant::now();

    for iter in iter_start..max_iters {
        let mut changed = false;
        for (step_idx, &step) in step_sizes.iter().enumerate() {
            for param in 0..PARAM_COUNT {
                let prev = w.objective(train, l2_lambda);
                let next = w.tune_one(train, param, step, prev, l2_lambda);
                if (prev - next).abs() > min_delta * 0.01 {
                    changed = true;
                }
            }
            let prev = w.objective(train, l2_lambda);
            let next = w.tune_one(train, PARAM_COUNT, k_steps[step_idx], prev, l2_lambda);
            if (prev - next).abs() > min_delta * 0.01 {
                changed = true;
            }
        }

        let train_loss = w.data_loss(train);
        let holdout_loss = w.data_loss(holdout);
        if holdout_loss < best_holdout_loss {
            best_holdout_loss = holdout_loss;
            best = w;
        }

        if (iter + 1).is_multiple_of(checkpoint_every) || !changed {
            let elapsed = fit_start.elapsed().as_secs_f64();
            let iters_done = (iter + 1).saturating_sub(iter_start).max(1);
            let eta_str = if elapsed > 0.1 && iters_done < max_iters - iter_start {
                let secs_per_iter = elapsed / iters_done as f64;
                let remaining = secs_per_iter * (max_iters - iter - 1) as f64;
                format!("  ETA {}", fmt_secs(remaining))
            } else {
                String::new()
            };
            eprintln!(
                "[tune fit] iter {:>4}/{max_iters}: k={:.5} train={train_loss:.6} \
                 holdout={holdout_loss:.6} best_holdout={best_holdout_loss:.6} \
                 elapsed={}{eta_str}",
                iter + 1,
                w.k,
                fmt_secs(elapsed),
            );
            save_checkpoint(
                &checkpoint_path,
                &Checkpoint {
                    iteration: iter + 1,
                    current: w,
                    best,
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

    let final_train = best.data_loss(train);
    let final_holdout = best.data_loss(holdout);
    // Folded phases carried no samples of their own, so emit moving_open's
    // fitted weights for them rather than the untouched LEGACY prior.
    for (p, &is_active) in active_phase.iter().enumerate() {
        if !is_active {
            best.weights[p] = best.weights[1];
        }
    }
    // Data-driven mate guard: bound the quantized eval using the feature
    // ranges actually observed per phase, not theoretical maxima.  This stops
    // a dead feature (mill_count is always 0 in standard play) from inflating
    // the bound and wrongly shrinking piece_value.
    let mut phase_max_abs = [[0.0_f64; FEATURE_COUNT]; PHASE_COUNT];
    for sample in &all_samples {
        for (f, &value) in sample.features.iter().enumerate() {
            let abs = value.abs();
            if abs > phase_max_abs[sample.phase][f] {
                phase_max_abs[sample.phase][f] = abs;
            }
        }
    }
    for (p, &is_active) in active_phase.iter().enumerate() {
        if !is_active {
            phase_max_abs[p] = phase_max_abs[1];
        }
    }
    let quantized = quantize_all(best.weights, &phase_max_abs);
    let flat = flatten_quantized(quantized);
    let weights_env = flat
        .iter()
        .map(i32::to_string)
        .collect::<Vec<_>>()
        .join(",");

    eprintln!("[tune fit] BEST weights (holdout={final_holdout:.6} train={final_train:.6}):");
    print_float_weights(best);
    print_quantized_weights(quantized);
    eprintln!();
    eprintln!("  Inject:  TGF_EVAL_WEIGHTS={weights_env}");
    eprintln!("  Verify:  TGF_EVAL_WEIGHTS={weights_env} SKILL=30 MOVETIME_MS=200 \\");
    eprintln!("    GAMES=10000 JOBS=20 bash scripts/run_h2h_head_vs_parent.sh");

    let mut out = File::create(&out_path)
        .unwrap_or_else(|e| panic!("[tune fit] cannot create output {out_path}: {e}"));
    writeln!(out, "# Mill eval weights generated by tgf tune fit").ok();
    writeln!(out, "# Phase order: placing,moving_open,pre_fly,flying").ok();
    writeln!(
        out,
        "# Feature order per phase: {}",
        FEATURE_NAMES.join(",")
    )
    .ok();
    writeln!(
        out,
        "# Losses: train={final_train:.8} holdout={final_holdout:.8}"
    )
    .ok();
    writeln!(out, "# Samples: train={n_train} holdout={n_holdout}").ok();
    writeln!(
        out,
        "# Phase sample weights: placing={placing_weight:.3} moving={moving_weight:.3} \
         pre_fly={pre_fly_weight:.3} flying={flying_weight:.3}"
    )
    .ok();
    writeln!(out).ok();
    writeln!(out, "TGF_EVAL_WEIGHTS={weights_env}").ok();
    out.flush().ok();
    eprintln!(
        "[tune fit] weights written to {out_path}  (total fit time: {})",
        fmt_secs(fit_start.elapsed().as_secs_f64())
    );

    print_feature_contributions(&all_samples, best);
}

fn dtm_adjusted_result(base: f64, wdl: i32, steps: Option<i32>, dtm_weight: f64) -> f64 {
    if dtm_weight <= 0.0 {
        return base;
    }
    let Some(steps) = steps.filter(|&s| s > 0) else {
        return base;
    };
    let t = 1.0 - (steps as f64 / 100.0_f64).min(1.0);
    match wdl {
        1 => 0.5 + t * 0.5 * dtm_weight + (1.0 - dtm_weight) * 0.5,
        -1 => 0.5 - t * 0.5 * dtm_weight - (1.0 - dtm_weight) * 0.5,
        _ => base,
    }
}

fn features_for_record(
    rules: &MillRules,
    options: &MillVariantOptions,
    rec: &PositionRecord,
) -> (usize, [f64; FEATURE_COUNT]) {
    if !rec.fen.is_empty()
        && let Ok(state) = rules.set_from_fen(&rec.fen)
    {
        return (
            phase_index(state.phase(), state.pieces_on_board(), options),
            feature_array(rules.eval_features(&state)),
        );
    }
    let material_diff = if rec.phase == 0 {
        rec.in_hand_diff + rec.on_board_diff
    } else {
        rec.on_board_diff
    };
    let phase = if rec.phase == 0 { 0 } else { 1 };
    (
        phase,
        [
            material_diff as f64,
            rec.mobility_diff as f64,
            0.0,
            0.0,
            0.0,
            0.0,
        ],
    )
}

fn phase_index(phase: MillPhase, pieces_on_board: [u8; 2], options: &MillVariantOptions) -> usize {
    match phase {
        MillPhase::Placing => 0,
        MillPhase::Moving if flying_phase_active(pieces_on_board, options) => 3,
        MillPhase::Moving if pre_fly_phase_active(pieces_on_board, options) => 2,
        MillPhase::Moving => 1,
        _ => 1,
    }
}

fn flying_phase_active(pieces_on_board: [u8; 2], options: &MillVariantOptions) -> bool {
    options.may_fly
        && (pieces_on_board[0] <= options.fly_piece_count
            || pieces_on_board[1] <= options.fly_piece_count)
}

fn pre_fly_phase_active(pieces_on_board: [u8; 2], options: &MillVariantOptions) -> bool {
    if !options.may_fly {
        return false;
    }
    let pre_fly = options.fly_piece_count.saturating_add(1);
    pieces_on_board[0] == pre_fly || pieces_on_board[1] == pre_fly
}

fn print_phase_distribution(counts: [PhaseCounts; PHASE_COUNT]) {
    eprintln!("+----------+---------+------+------+------+--------+");
    eprintln!("| Phase    | Samples |  Win | Draw | Loss |  Draw% |");
    eprintln!("+----------+---------+------+------+------+--------+");
    for (phase, stats) in counts.iter().enumerate() {
        let draw_pct = if stats.samples == 0 {
            0.0
        } else {
            stats.draw as f64 * 100.0 / stats.samples as f64
        };
        eprintln!(
            "| {:<8} | {:>7} | {:>4} | {:>4} | {:>4} | {:>6.1}% |",
            PHASE_NAMES[phase], stats.samples, stats.win, stats.draw, stats.loss, draw_pct
        );
    }
    eprintln!("+----------+---------+------+------+------+--------+");
}

fn quantize_all(
    weights: [[f64; FEATURE_COUNT]; PHASE_COUNT],
    phase_max_abs: &[[f64; FEATURE_COUNT]; PHASE_COUNT],
) -> [[i32; FEATURE_COUNT]; PHASE_COUNT] {
    let mut out = [[0_i32; FEATURE_COUNT]; PHASE_COUNT];
    for phase in 0..PHASE_COUNT {
        out[phase] = quantize_phase(weights[phase], &phase_max_abs[phase]);
    }
    out
}

fn quantize_phase(
    weights: [f64; FEATURE_COUNT],
    max_abs: &[f64; FEATURE_COUNT],
) -> [i32; FEATURE_COUNT] {
    let mut q = [0_i32; FEATURE_COUNT];
    q[0] = (weights[0].round() as i32).clamp(1, 7);
    for idx in 1..FEATURE_COUNT {
        q[idx] = (weights[idx].round() as i32).clamp(-7, 7);
    }
    while observed_max_eval(&q, max_abs) > MAX_NON_MATE_EVAL {
        let Some(idx) = largest_reducible_contribution(&q, max_abs) else {
            break;
        };
        q[idx] -= q[idx].signum();
        if idx == 0 && q[idx] < 1 {
            q[idx] = 1;
            break;
        }
    }
    q
}

/// Worst-case |eval| using each feature's observed per-phase range.
fn observed_max_eval(weights: &[i32; FEATURE_COUNT], max_abs: &[f64; FEATURE_COUNT]) -> f64 {
    weights
        .iter()
        .zip(max_abs.iter())
        .map(|(w, max_feature)| f64::from(w.abs()) * max_feature)
        .sum()
}

fn largest_reducible_contribution(
    weights: &[i32; FEATURE_COUNT],
    max_abs: &[f64; FEATURE_COUNT],
) -> Option<usize> {
    (0..FEATURE_COUNT)
        .filter(|&idx| weights[idx] != 0 && !(idx == 0 && weights[idx] <= 1))
        .max_by(|&a, &b| {
            let ca = f64::from(weights[a].abs()) * max_abs[a];
            let cb = f64::from(weights[b].abs()) * max_abs[b];
            ca.partial_cmp(&cb).unwrap_or(std::cmp::Ordering::Equal)
        })
}

fn flatten_quantized(weights: [[i32; FEATURE_COUNT]; PHASE_COUNT]) -> Vec<i32> {
    let mut out = Vec::with_capacity(PARAM_COUNT);
    for phase_weights in weights {
        out.extend_from_slice(&phase_weights);
    }
    out
}

fn print_float_weights(params: Params) {
    for (phase, phase_name) in PHASE_NAMES.iter().enumerate() {
        eprintln!("  [{phase_name}]");
        for (feature, feature_name) in FEATURE_NAMES.iter().enumerate() {
            eprintln!(
                "    {:<15} {:+.4}",
                feature_name, params.weights[phase][feature]
            );
        }
    }
    eprintln!("  k={:.6}", params.k);
}

fn print_quantized_weights(weights: [[i32; FEATURE_COUNT]; PHASE_COUNT]) {
    eprintln!("  quantized:");
    for (phase_name, phase_weights) in PHASE_NAMES.iter().zip(weights.iter()) {
        eprintln!("    {phase_name:<8}: {phase_weights:?}");
    }
}

fn fmt_secs(secs: f64) -> String {
    let secs = secs.max(0.0) as u64;
    let h = secs / 3600;
    let m = (secs % 3600) / 60;
    let s = secs % 60;
    if h > 0 {
        format!("{h}h{m:02}m{s:02}s")
    } else if m > 0 {
        format!("{m}m{s:02}s")
    } else {
        format!("{s}s")
    }
}

fn print_feature_contributions(samples: &[Sample], params: Params) {
    let mut totals = [[0.0_f64; FEATURE_COUNT]; PHASE_COUNT];
    let mut counts = [0_usize; PHASE_COUNT];
    for sample in samples {
        counts[sample.phase] += 1;
        for (feature, total) in totals[sample.phase].iter_mut().enumerate() {
            *total += (params.weights[sample.phase][feature] * sample.features[feature]).abs();
        }
    }
    eprintln!("[tune fit] feature contribution (avg |weight x feature|):");
    for (phase, phase_name) in PHASE_NAMES.iter().enumerate() {
        if counts[phase] == 0 {
            continue;
        }
        eprintln!("  [{phase_name}]");
        for (feature, feature_name) in FEATURE_NAMES.iter().enumerate() {
            eprintln!(
                "    {:<15} {:.4}",
                feature_name,
                totals[phase][feature] / counts[phase] as f64
            );
        }
    }
}
