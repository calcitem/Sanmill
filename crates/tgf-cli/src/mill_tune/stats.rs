// SPDX-License-Identifier: GPL-3.0-or-later
// tune stats: inspect labeled Mill tuning datasets by phase.

use std::fs::File;
use std::io::{BufRead, BufReader};

use super::{PositionRecord, parse_flag};

#[derive(Clone, Copy, Default)]
struct PhaseStats {
    total: usize,
    labeled: usize,
    win: usize,
    draw: usize,
    loss: usize,
    unlabeled: usize,
}

impl PhaseStats {
    fn add(&mut self, rec: &PositionRecord) {
        self.total += 1;
        match rec.wdl {
            Some(1) => {
                self.labeled += 1;
                self.win += 1;
            }
            Some(0) => {
                self.labeled += 1;
                self.draw += 1;
            }
            Some(-1) => {
                self.labeled += 1;
                self.loss += 1;
            }
            Some(_) | None => {
                self.unlabeled += 1;
            }
        }
    }
}

pub(crate) fn run_stats(args: &[String]) {
    let in_path: String = parse_flag(args, "--in", "tune_labeled.dat".to_string());
    eprintln!("[tune stats] in={in_path}");

    let f =
        File::open(&in_path).unwrap_or_else(|e| panic!("[tune stats] cannot open {in_path}: {e}"));
    let mut phases = [PhaseStats::default(); 2];
    let mut other = PhaseStats::default();

    for line in BufReader::new(f).lines().map_while(Result::ok) {
        if line.trim().is_empty() || line.starts_with('#') {
            continue;
        }
        let Some(rec) = PositionRecord::from_record_line(&line) else {
            continue;
        };
        match rec.phase {
            0 => phases[0].add(&rec),
            1 => phases[1].add(&rec),
            _ => other.add(&rec),
        }
    }

    let all = PhaseStats {
        total: phases[0].total + phases[1].total + other.total,
        labeled: phases[0].labeled + phases[1].labeled + other.labeled,
        win: phases[0].win + phases[1].win + other.win,
        draw: phases[0].draw + phases[1].draw + other.draw,
        loss: phases[0].loss + phases[1].loss + other.loss,
        unlabeled: phases[0].unlabeled + phases[1].unlabeled + other.unlabeled,
    };

    eprintln!("+----------+--------+---------+------+------+------+--------+--------+");
    eprintln!("| Phase    |  Total | Labeled |  Win | Draw | Loss |  Draw% | Unlab% |");
    eprintln!("+----------+--------+---------+------+------+------+--------+--------+");
    print_phase("placing", phases[0]);
    print_phase("moving", phases[1]);
    if other.total > 0 {
        print_phase("other", other);
    }
    print_phase("TOTAL", all);
    eprintln!("+----------+--------+---------+------+------+------+--------+--------+");
}

fn print_phase(name: &str, stats: PhaseStats) {
    let draw_pct = pct(stats.draw, stats.labeled);
    let unlabeled_pct = pct(stats.unlabeled, stats.total);
    eprintln!(
        "| {name:<8} | {total:>6} | {labeled:>7} | {win:>4} | {draw:>4} | \
         {loss:>4} | {draw_pct:>6.1}% | {unlabeled_pct:>6.1}% |",
        total = stats.total,
        labeled = stats.labeled,
        win = stats.win,
        draw = stats.draw,
        loss = stats.loss,
    );
}

fn pct(part: usize, total: usize) -> f64 {
    if total == 0 {
        0.0
    } else {
        part as f64 * 100.0 / total as f64
    }
}
