// SPDX-License-Identifier: GPL-3.0-or-later
// Offline eval-weight tuning pipeline for the Mill engine.
//
// Three sub-commands, intended to be run in sequence:
//
//   tgf tune gen   [--positions N] [--out PATH] [--seed N] [--depth D]
//   tgf tune label [--in PATH] [--out PATH] [--db PATH] [--resume]
//   tgf tune stats [--in PATH]
//   tgf tune fit   [--in PATH] [--out PATH] [--iters N] [--k SCALE]
//                  [--checkpoint PATH] [--resume]
//
// Or via the one-shot orchestration script:
//   bash scripts/tune_mill_eval.sh [--positions N] [--db PATH] [options]
//
// Dataset format (pipe-delimited text, one position per line):
//   KEY|PHASE|IN_HAND_DIFF|ON_BOARD_DIFF|MOBILITY_DIFF|WDL|STEPS|FEN
//
// KEY      : Zobrist key as hex (u64) — used for deduplication
// PHASE    : 0 = Placing, 1 = Moving
// IN_HAND_DIFF, ON_BOARD_DIFF, MOBILITY_DIFF : i32 (White minus Black)
// WDL      : 1 = White win, 0 = draw, -1 = White loss, or "?" if unlabeled
// STEPS    : distance-to-conversion (i32), or -1 if unknown / unlabeled
// FEN      : Mill FEN string (may contain '|' only if quoted; not expected)
//
// The file is append-safe: tune-label reads the gen output and rewrites
// it with WDL/STEPS filled.  tune-fit reads labeled lines only.

mod datagen;
mod datagen_human;
mod fit;
mod label;
mod stats;

pub(crate) use datagen::run_gen;
pub(crate) use datagen_human::run_gen_human;
pub(crate) use fit::run_fit;
pub(crate) use label::run_label;
pub(crate) use stats::run_stats;

/// One sampled position, including extracted features.
#[derive(Clone, Debug)]
pub(crate) struct PositionRecord {
    pub key: u64,
    pub phase: u8, // 0 = placing, 1 = moving
    pub in_hand_diff: i32,
    pub on_board_diff: i32,
    pub mobility_diff: i32,
    /// WDL from the side-to-move perspective: 1/0/-1.
    /// None means the label has not yet been filled by tune-label.
    pub wdl: Option<i32>,
    /// Distance-to-conversion (from Perfect DB), or None / -1 if unknown.
    pub steps: Option<i32>,
    /// Full Mill FEN for diagnostics (may be empty string).
    pub fen: String,
}

impl PositionRecord {
    /// Serialize to the pipeline text format.
    pub fn to_record_line(&self) -> String {
        let wdl_str = match self.wdl {
            Some(v) => format!("{v}"),
            None => "?".to_string(),
        };
        let steps_str = match self.steps {
            Some(v) => format!("{v}"),
            None => "-1".to_string(),
        };
        format!(
            "{:#018x}|{}|{}|{}|{}|{}|{}|{}",
            self.key,
            self.phase,
            self.in_hand_diff,
            self.on_board_diff,
            self.mobility_diff,
            wdl_str,
            steps_str,
            self.fen,
        )
    }

    /// Parse from a pipeline text line.  Returns None on malformed input.
    pub fn from_record_line(line: &str) -> Option<Self> {
        let mut parts = line.splitn(8, '|');
        let key = u64::from_str_radix(parts.next()?.trim_start_matches("0x"), 16).ok()?;
        let phase = parts.next()?.parse::<u8>().ok()?;
        let in_hand_diff = parts.next()?.parse::<i32>().ok()?;
        let on_board_diff = parts.next()?.parse::<i32>().ok()?;
        let mobility_diff = parts.next()?.parse::<i32>().ok()?;
        let wdl_raw = parts.next()?;
        let wdl = if wdl_raw == "?" {
            None
        } else {
            Some(wdl_raw.parse::<i32>().ok()?)
        };
        let steps_raw = parts.next()?;
        let steps = match steps_raw.parse::<i32>() {
            Ok(v) if v < 0 => None,
            Ok(v) => Some(v),
            Err(_) => None,
        };
        let fen = parts.next().unwrap_or("").to_string();
        Some(Self {
            key,
            phase,
            in_hand_diff,
            on_board_diff,
            mobility_diff,
            wdl,
            steps,
            fen,
        })
    }
}

/// Parse a `--flag value` or `--flag=value` pair from an args slice.
pub(crate) fn parse_flag<T: std::str::FromStr>(args: &[String], flag: &str, default: T) -> T {
    let eq_prefix = format!("{flag}=");
    let mut iter = args.iter();
    while let Some(tok) = iter.next() {
        if tok == flag {
            if let Some(val) = iter.next()
                && let Ok(v) = val.parse::<T>()
            {
                return v;
            }
            return default;
        }
        if let Some(val) = tok.strip_prefix(&eq_prefix)
            && let Ok(v) = val.parse::<T>()
        {
            return v;
        }
    }
    default
}

/// Check whether `--flag` (bare boolean) is present in args.
pub(crate) fn flag_present(args: &[String], flag: &str) -> bool {
    args.iter().any(|a| a == flag)
}
