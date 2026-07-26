// SPDX-License-Identifier: AGPL-3.0-or-later

use std::path::Path;

use perfect_db::database::{
    Database, DatabaseOptions, DatabaseVariant, FileDatabaseProvider, PerfectOutcome,
};
use perfect_db::{PerfectMoveOrdering, all_logical_turn_outcomes_with_database};
use tgf_mill::{MillRules, MillVariantOptions};

use super::model::{
    DatabaseEvidence, DatabaseTurnEvidence, EvidenceLevel, FindingClass, LossReport, ReplayedGame,
    ValueSwing,
};
use super::replay::finding;

pub(crate) struct PerfectOracle {
    database: Database<FileDatabaseProvider>,
}

impl PerfectOracle {
    pub fn open(path: &Path, options: &MillVariantOptions) -> Result<Self, String> {
        let variant = DatabaseVariant::match_mill_options(options)
            .map_err(|_| "only standard Nine Men's Morris is supported".to_string())?;
        if variant != DatabaseVariant::STANDARD {
            return Err("only standard Nine Men's Morris is supported".to_string());
        }
        let database = Database::open_variant_with_options(
            FileDatabaseProvider::new(path.to_path_buf()),
            variant,
            DatabaseOptions::with_sector_cache_capacity(64),
        )
        .map_err(|error| format!("failed to open Perfect DB {}: {error}", path.display()))?;
        Ok(Self { database })
    }

    pub fn annotate(
        &mut self,
        games: &mut [ReplayedGame],
        rules: &MillRules,
        options: &MillVariantOptions,
        rules_sha256: &str,
    ) {
        for game in games {
            for turn in &mut game.logical_turns {
                let result = all_logical_turn_outcomes_with_database(
                    &mut self.database,
                    rules,
                    &turn.root,
                    &turn.root_history,
                    options,
                );
                match result {
                    Ok(Some(choices)) => {
                        let best = choices
                            .iter()
                            .map(|choice| choice.outcome)
                            .max_by(|left, right| {
                                PerfectMoveOrdering::StrictSteps.compare(*left, *right)
                            })
                            .expect("a covered logical root has at least one legal turn");
                        let best_turns = choices
                            .iter()
                            .filter(|choice| {
                                PerfectMoveOrdering::StrictSteps
                                    .compare(choice.outcome, best)
                                    .is_eq()
                            })
                            .map(|choice| choice.tokens.clone())
                            .collect::<Vec<_>>();
                        let played = choices
                            .iter()
                            .find(|choice| choice.tokens == turn.tokens)
                            .map(|choice| choice.outcome);
                        let evidence = DatabaseEvidence {
                            status: if played.is_some() {
                                "covered".to_string()
                            } else {
                                "played_turn_not_enumerated".to_string()
                            },
                            best_wdl: Some(best.wdl()),
                            best_steps: Some(best.steps()),
                            played_wdl: played.map(PerfectOutcome::wdl),
                            played_steps: played.map(PerfectOutcome::steps),
                            best_turns: best_turns.clone(),
                            all_turns: choices
                                .iter()
                                .map(|choice| {
                                    DatabaseTurnEvidence::from_outcome(
                                        choice.tokens.clone(),
                                        choice.outcome,
                                    )
                                })
                                .collect(),
                            error: None,
                        };
                        if let Some(played) = played {
                            let primary_has_optimal = choices.iter().any(|choice| {
                                choice.tokens.first() == turn.tokens.first()
                                    && choice.outcome.wdl() == best.wdl()
                            });
                            match classify_database_result(best, played, primary_has_optimal) {
                                DatabaseClassification::WdlDrop {
                                    severity,
                                    removal_error,
                                } => {
                                    let code = if removal_error {
                                        "db_primary_correct_removal_error"
                                    } else {
                                        "db_wdl_drop"
                                    };
                                    let mut item = finding(
                                        &game.source,
                                        Some(turn.action_start),
                                        Some(turn.logical_ply_index),
                                        Some(turn.actor),
                                        EvidenceLevel::Exact,
                                        FindingClass::MoveError,
                                        code,
                                        &format!(
                                            "Perfect DB proves the played logical turn drops WDL from {} to {} (severity {severity})",
                                            best.wdl(),
                                            played.wdl()
                                        ),
                                        Some(&turn.before),
                                        rules_sha256,
                                        if turn.tokens.len() > 1 {
                                            "mill_with_removal"
                                        } else {
                                            "single_action"
                                        },
                                    );
                                    item.database = Some(evidence.clone());
                                    item.facts.push(format!(
                                        "best logical turns: {}",
                                        best_turns
                                            .iter()
                                            .map(|actions| actions.join(" "))
                                            .collect::<Vec<_>>()
                                            .join(" | ")
                                    ));
                                    if removal_error {
                                        item.inferences.push(
                                            "the primary action can preserve the best WDL; the selected mandatory removal cannot".to_string(),
                                        );
                                    }
                                    game.findings.push(item);
                                }
                                DatabaseClassification::StepsOnly => {
                                    let mut item = finding(
                                        &game.source,
                                        Some(turn.action_start),
                                        Some(turn.logical_ply_index),
                                        Some(turn.actor),
                                        EvidenceLevel::Advisory,
                                        FindingClass::ConversionInefficiency,
                                        "db_steps_only_difference",
                                        "the played turn preserves WDL but is worse under strict DB step ordering",
                                        Some(&turn.before),
                                        rules_sha256,
                                        "conversion_efficiency",
                                    );
                                    item.database = Some(evidence.clone());
                                    game.findings.push(item);
                                }
                                DatabaseClassification::Optimal => {}
                            }
                        } else {
                            let mut item = finding(
                                &game.source,
                                Some(turn.action_start),
                                Some(turn.logical_ply_index),
                                Some(turn.actor),
                                EvidenceLevel::Hard,
                                FindingClass::EngineAnomaly,
                                "db_played_turn_not_enumerated",
                                "strict replay accepted a logical turn the Perfect DB legal-turn enumerator did not return",
                                Some(&turn.before),
                                rules_sha256,
                                "rules_database_contract",
                            );
                            item.database = Some(evidence.clone());
                            game.findings.push(item);
                        }
                        turn.database = Some(evidence);
                    }
                    Ok(None) => {
                        let evidence = unresolved_evidence("miss", None);
                        let mut item = finding(
                            &game.source,
                            Some(turn.action_start),
                            Some(turn.logical_ply_index),
                            Some(turn.actor),
                            EvidenceLevel::Unresolved,
                            FindingClass::Unresolved,
                            "unresolved_db_coverage",
                            "Perfect DB does not cover every continuation at this logical root",
                            Some(&turn.before),
                            rules_sha256,
                            "database_coverage",
                        );
                        item.database = Some(evidence.clone());
                        item.unknowns.push(
                            "the mathematical WDL of the played and alternative turns is unknown"
                                .to_string(),
                        );
                        game.findings.push(item);
                        turn.database = Some(evidence);
                    }
                    Err(error) => {
                        let evidence = unresolved_evidence("error", Some(error.to_string()));
                        let mut item = finding(
                            &game.source,
                            Some(turn.action_start),
                            Some(turn.logical_ply_index),
                            Some(turn.actor),
                            EvidenceLevel::Unresolved,
                            FindingClass::Unresolved,
                            "unresolved_db_error",
                            "Perfect DB query failed at this logical root",
                            Some(&turn.before),
                            rules_sha256,
                            "database_error",
                        );
                        item.database = Some(evidence.clone());
                        item.unknowns.push(error.to_string());
                        game.findings.push(item);
                        turn.database = Some(evidence);
                    }
                }
            }
        }
    }
}

pub(crate) fn mark_all_database_unavailable(games: &mut [ReplayedGame], rules_sha256: &str) {
    for game in games {
        for turn in &mut game.logical_turns {
            let evidence = unresolved_evidence("not_requested", None);
            let mut item = finding(
                &game.source,
                Some(turn.action_start),
                Some(turn.logical_ply_index),
                Some(turn.actor),
                EvidenceLevel::Unresolved,
                FindingClass::Unresolved,
                "unresolved_db_not_configured",
                "no Perfect DB was supplied for this logical root",
                Some(&turn.before),
                rules_sha256,
                "database_not_configured",
            );
            item.database = Some(evidence.clone());
            item.unknowns
                .push("no exact WDL proof was attempted".to_string());
            game.findings.push(item);
            turn.database = Some(evidence);
        }
    }
}

fn unresolved_evidence(status: &str, error: Option<String>) -> DatabaseEvidence {
    DatabaseEvidence {
        status: status.to_string(),
        best_wdl: None,
        best_steps: None,
        played_wdl: None,
        played_steps: None,
        best_turns: Vec::new(),
        all_turns: Vec::new(),
        error,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum DatabaseClassification {
    Optimal,
    StepsOnly,
    WdlDrop { severity: i32, removal_error: bool },
}

fn classify_database_result(
    best: PerfectOutcome,
    played: PerfectOutcome,
    primary_has_optimal: bool,
) -> DatabaseClassification {
    let severity = best.wdl() - played.wdl();
    if severity > 0 {
        return DatabaseClassification::WdlDrop {
            severity,
            removal_error: primary_has_optimal,
        };
    }
    if PerfectMoveOrdering::StrictSteps
        .compare(played, best)
        .is_lt()
    {
        DatabaseClassification::StepsOnly
    } else {
        DatabaseClassification::Optimal
    }
}

pub(crate) fn loss_reports(games: &[ReplayedGame]) -> Vec<LossReport> {
    games
        .iter()
        .filter(|game| game.source.loser().is_some() || game.source.is_loss_for_candidate())
        .map(loss_report)
        .collect()
}

fn loss_report(game: &ReplayedGame) -> LossReport {
    let loser = game.source.loser();
    let fully_covered = !game.logical_turns.is_empty()
        && game.logical_turns.iter().all(|turn| {
            turn.database
                .as_ref()
                .is_some_and(|evidence| evidence.status == "covered")
        });
    let mut swings = Vec::new();
    for turn in &game.logical_turns {
        let Some(database) = turn.database.as_ref() else {
            continue;
        };
        let (Some(before), Some(after)) = (database.best_wdl, database.played_wdl) else {
            continue;
        };
        let before_white = if turn.actor == tgf_cli::h2h_trace::H2hActor::White {
            before
        } else {
            -before
        };
        let after_white = if turn.actor == tgf_cli::h2h_trace::H2hActor::White {
            after
        } else {
            -after
        };
        swings.push(ValueSwing {
            logical_ply_index: turn.logical_ply_index,
            action_index: turn.action_start,
            actor: turn.actor,
            before_white_wdl: before_white,
            after_white_wdl: after_white,
            escaped: false,
        });
    }

    let mut escaped_blunders = Vec::new();
    if let Some(loser) = loser {
        for index in 0..swings.len() {
            let before_loser = loser_value(loser, swings[index].before_white_wdl);
            let after_loser = loser_value(loser, swings[index].after_white_wdl);
            if after_loser < before_loser
                && swings[index + 1..].iter().any(|later| {
                    loser_value(loser, later.before_white_wdl) >= before_loser
                        || loser_value(loser, later.after_white_wdl) >= before_loser
                })
            {
                swings[index].escaped = true;
                escaped_blunders.push(swings[index].logical_ply_index);
            }
        }
    }

    let decisive_loss_turn = if fully_covered {
        loser.and_then(|loser| {
            swings
                .iter()
                .enumerate()
                .filter(|(_, swing)| {
                    loser_value(loser, swing.before_white_wdl) >= 0
                        && loser_value(loser, swing.after_white_wdl) < 0
                })
                .filter(|(index, _)| {
                    swings[index + 1..].iter().all(|later| {
                        loser_value(loser, later.before_white_wdl) < 0
                            && loser_value(loser, later.after_white_wdl) < 0
                    })
                })
                .map(|(_, swing)| swing.logical_ply_index)
                .next_back()
        })
    } else {
        None
    };
    let earliest_observed_suspect = if fully_covered {
        None
    } else {
        game.findings
            .iter()
            .filter(|finding| {
                matches!(
                    finding.classification,
                    FindingClass::MoveError
                        | FindingClass::EngineAnomaly
                        | FindingClass::Unresolved
                )
            })
            .filter_map(|finding| finding.logical_ply_index)
            .min()
    };
    let first_engine_anomaly = game
        .findings
        .iter()
        .filter(|finding| finding.classification == FindingClass::EngineAnomaly)
        .min_by_key(|finding| finding.action_index.unwrap_or(usize::MAX))
        .map(|finding| finding.finding_id.clone());
    let unresolved = !fully_covered
        || game
            .findings
            .iter()
            .any(|finding| finding.evidence == EvidenceLevel::Unresolved);
    LossReport {
        game_index: game.source.game_index,
        pair_index: game.source.pair_index,
        loser,
        db_fully_covered: fully_covered,
        decisive_loss_turn,
        earliest_observed_suspect,
        first_engine_anomaly,
        escaped_blunders,
        value_swings: swings,
        unresolved,
        case_ids: Vec::new(),
    }
}

fn loser_value(loser: tgf_cli::h2h_trace::H2hActor, white_value: i32) -> i32 {
    if loser == tgf_cli::h2h_trace::H2hActor::White {
        white_value
    } else {
        -white_value
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn database_classification_separates_wdl_steps_and_removal() {
        assert_eq!(
            classify_database_result(
                PerfectOutcome::Win { steps: 4 },
                PerfectOutcome::Draw { steps: 0 },
                false
            ),
            DatabaseClassification::WdlDrop {
                severity: 1,
                removal_error: false
            }
        );
        assert_eq!(
            classify_database_result(
                PerfectOutcome::Win { steps: 4 },
                PerfectOutcome::Loss { steps: 12 },
                true
            ),
            DatabaseClassification::WdlDrop {
                severity: 2,
                removal_error: true
            }
        );
        assert_eq!(
            classify_database_result(
                PerfectOutcome::Win { steps: 4 },
                PerfectOutcome::Win { steps: 8 },
                false
            ),
            DatabaseClassification::StepsOnly
        );
        assert_eq!(
            classify_database_result(
                PerfectOutcome::Draw { steps: 5 },
                PerfectOutcome::Draw { steps: 99 },
                false
            ),
            DatabaseClassification::Optimal
        );
    }

    #[test]
    fn db_miss_evidence_is_never_safe() {
        let evidence = unresolved_evidence("miss", None);
        assert_eq!(evidence.status, "miss");
        assert!(evidence.best_wdl.is_none());
        assert!(evidence.played_wdl.is_none());
    }
}
