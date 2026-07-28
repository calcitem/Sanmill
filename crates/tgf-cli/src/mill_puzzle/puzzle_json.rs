// SPDX-License-Identifier: AGPL-3.0-or-later
// JSON data model mirroring Sanmill's Flutter `PuzzleInfo` / `PuzzleSolution`
// / `PuzzleMove` schema.
//
// Field names and the top-level export envelope shape are kept in exact
// sync with `docs/PUZZLE_FORMAT.md`, `PuzzleExportService`, and
// `PuzzleInfo.toJson()` / `PuzzleSolution.toJson()` / `PuzzleMove.toJson()`
// (see `src/ui/flutter_app/lib/puzzle/models/`) so the Flutter app can
// import a `.sanmill_puzzles` file produced by this tool with no format
// translation step.

use serde::Serialize;

use super::candidate_input::{EngineBlunderEvidence, HumanReplayEvidence};
use super::motifs::PuzzleMotif;
use super::solver::BuiltSolution;

#[derive(Debug, Clone, Serialize)]
pub(crate) struct PuzzlePackageJson {
    #[serde(rename = "formatVersion")]
    pub format_version: &'static str,
    #[serde(rename = "exportedBy")]
    pub exported_by: ExportedByJson,
    #[serde(rename = "exportDate")]
    pub export_date: String,
    #[serde(rename = "puzzleCount")]
    pub puzzle_count: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub metadata: Option<PuzzlePackMetadataJson>,
    pub puzzles: Vec<PuzzleInfoJson>,
}

#[derive(Debug, Clone, Serialize)]
pub(crate) struct ExportedByJson {
    #[serde(rename = "appName")]
    pub app_name: &'static str,
    pub platform: &'static str,
}

/// Optional puzzle-pack metadata block, matching the `metadata` object in
/// `docs/PUZZLE_FORMAT.md`. Emitted when the caller passes `--pack-id`, so
/// the committed built-in asset can be regenerated entirely from the CLI.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PuzzlePackMetadataJson {
    pub id: String,
    pub name: String,
    pub description: String,
    pub author: String,
    pub version: &'static str,
    pub tags: Vec<String>,
    pub is_official: bool,
    pub rule_variant_id: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PuzzleInfoJson {
    pub id: String,
    pub title: String,
    pub description: String,
    pub category: &'static str,
    pub difficulty: &'static str,
    pub initial_position: String,
    pub solutions: Vec<PuzzleSolutionJson>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hint: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub completion_message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provenance: Option<PuzzleProvenanceJson>,
    pub tags: Vec<String>,
    pub is_custom: bool,
    pub author: String,
    pub created_date: String,
    pub version: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rating: Option<i32>,
    pub rule_variant_id: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PuzzleProvenanceJson {
    pub kind: &'static str,
    pub corpus: String,
    pub database_sha256: String,
    pub source_game_sha256: String,
    pub source_logical_ply: usize,
    pub replay_history: Vec<String>,
    pub recorded_turn: String,
    pub presentation_transform: u8,
    pub transform_model: String,
    pub position_games: u64,
    pub recorded_turn_games: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PuzzleSolutionJson {
    pub moves: Vec<PuzzleMoveJson>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub is_optimal: bool,
}

#[derive(Debug, Clone, Serialize)]
pub(crate) struct PuzzleMoveJson {
    pub notation: String,
    pub side: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub comment: Option<String>,
}

fn side_label(side: i8) -> &'static str {
    match side {
        0 => "white",
        1 => "black",
        other => unreachable!("Mill side must be 0 (white) or 1 (black), got {other}"),
    }
}

/// FNV-1a, used only to shorten a FEN into a stable-looking id suffix. Not
/// security-sensitive; collisions merely produce a duplicate `id` that a
/// human curator would notice.
fn short_hash(text: &str) -> String {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in text.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    format!("{:08x}", hash & 0xFFFF_FFFF)
}

/// The tactical fingerprint of one generated puzzle, aggregated from the
/// root-move classification and every constructed solution line. This is
/// what difficulty rating, tags, and all human-facing prose key off.
#[derive(Debug, Clone, Copy)]
pub(crate) struct PuzzleTraits {
    /// Constraint-directed motif independently confirmed on every shortest
    /// Perfect DB-certified first turn.
    pub motif: PuzzleMotif,
    /// Complete first turns tied for the shortest forced win.
    pub shortest_winning_count: usize,
    /// Number of complete legal first turns that fail to achieve the
    /// shortest forced win, including slower wins and non-wins.
    pub non_shortest_count: usize,
    /// Complete first turns that still force a win but take longer.
    pub slower_winning_count: usize,
    /// Complete first turns that lead only to a draw or loss.
    pub non_winning_count: usize,
    /// A mill-closing (capturing) first move exists that loses or draws:
    /// the most tempting move on the board is the trap.
    pub tempting_mill_mistake: bool,
    /// No winning first move closes a mill; the solution starts quietly.
    pub quiet_first_move: bool,
    /// Shallowest heuristic-search depth (from
    /// [`super::analysis::PROBE_DEPTHS`]) whose principal move keeps the
    /// win; `None` when every probe failed, i.e. only database-grade
    /// precision solves the puzzle.
    pub solve_depth: Option<i32>,
}

/// Heuristic difficulty/rating derived from how the puzzle resisted the
/// simulated human solver and how sharp its lines are. The dominant term is
/// `solve_depth` -- the search depth a player effectively needs to find the
/// first move -- because that tracks perceived difficulty far better than
/// the raw length of the win.
fn derive_difficulty_and_rating(
    target_moves: i32,
    shortest_first_turn_count: usize,
    traits: &PuzzleTraits,
    line: &LineTraits,
    is_moving_phase: bool,
) -> (&'static str, i32) {
    let mut rating = 600 + target_moves * 60;
    rating += match traits.solve_depth {
        Some(2) => 0,
        Some(4) => 180,
        Some(6) => 360,
        Some(8) => 540,
        Some(other) => unreachable!("unexpected probe depth {other}"),
        None => 700,
    };
    if shortest_first_turn_count <= 1 {
        rating += 80;
    }
    rating += (line.only_move_count * 50).min(200);
    if line.sacrifice {
        rating += 120;
    }
    if traits.tempting_mill_mistake {
        rating += 60;
    }
    if traits.quiet_first_move {
        rating += 60;
    }
    if line.vs_flying {
        rating += 40;
    }
    if line.immobilization_win {
        rating += 80;
    }
    if is_moving_phase {
        rating += 30;
    }
    let rating = rating.clamp(400, 2400);

    let difficulty = match rating {
        // Thresholds are shifted up by one bucket so the same rating maps to an
        // easier label (e.g. old "medium" 1000–1299 becomes "easy").
        r if r < 1000 => "beginner",
        r if r < 1300 => "easy",
        r if r < 1600 => "medium",
        r if r < 1900 => "hard",
        _ => "expert",
    };
    (difficulty, rating)
}

/// Line-level traits aggregated over every constructed solution.
#[derive(Debug, Clone, Copy, Default)]
struct LineTraits {
    sacrifice: bool,
    double_mill: bool,
    vs_flying: bool,
    immobilization_win: bool,
    only_move_count: i32,
    decision_point_count: i32,
}

fn aggregate_line_traits(solutions: &[BuiltSolution]) -> LineTraits {
    let mut traits = LineTraits::default();
    for built in solutions {
        traits.sacrifice |= built.sacrifice;
        traits.double_mill |= built.double_mill;
        traits.vs_flying |= built.vs_flying;
        traits.immobilization_win |= built.immobilization_win;
        traits.only_move_count = traits.only_move_count.max(built.only_move_count);
        traits.decision_point_count = traits.decision_point_count.max(built.decision_point_count);
    }
    traits
}

/// Everything needed to render one [`PuzzleInfoJson`] from a solved root
/// position plus its constructed solution lines.
pub(crate) struct PuzzleBuildInput<'a> {
    pub fen: &'a str,
    pub solver_side: i8,
    pub is_moving_phase: bool,
    pub solutions: &'a [BuiltSolution],
    pub traits: PuzzleTraits,
    pub author: &'a str,
    pub rule_variant_id: &'a str,
    pub generated_at: &'a str,
    /// Optional discovery provenance, distinct from proof authority.
    pub discovery_tag: Option<&'a str>,
    /// Present only when Rust/TGF replayed a complete source-game prefix.
    pub replay_provenance: Option<&'a HumanReplayEvidence>,
    /// Optional source-ranking evidence from the engine-error mining corpus.
    /// It is audit metadata, never proof of the published solution.
    pub engine_blunder: Option<&'a EngineBlunderEvidence>,
}

/// Human-facing prose for one theme: headline fragment, hint, and
/// completion-message lead. Kept non-spoiling: the hint points at the idea
/// without naming a square.
struct ThemeProse {
    tag: &'static str,
    headline: &'static str,
    hint: &'static str,
    completion: &'static str,
}

/// Pick the puzzle's headline theme by fixed precedence: the trap at the
/// first decision defines the puzzle's face; execution motifs (swing mill,
/// immobilization, sacrifice, flying defense) come next; a plain forced win
/// is the fallback.
fn select_theme(
    traits: &PuzzleTraits,
    line: &LineTraits,
    conceal_first_move_trap: bool,
) -> ThemeProse {
    match traits.motif {
        PuzzleMotif::DualThreat => {
            return ThemeProse {
                tag: "dual-threat",
                headline: "create two threats at once",
                hint: "Look for a quiet move that leaves two different mills ready to close.",
                completion: "One quiet move created two mill threats; the defence could answer \
                             only one.",
            };
        }
        PuzzleMotif::MillBlock => {
            return ThemeProse {
                tag: "mill-block",
                headline: "block before attacking",
                hint: "The opponent already has an accessible open mill. Stop it while keeping \
                       your own winning plan alive.",
                completion: "The defensive block took away the immediate mill and preserved the \
                             winning initiative.",
            };
        }
        PuzzleMotif::MillAbandonment => {
            return ThemeProse {
                tag: "mill-abandonment",
                headline: "abandon a mill to win",
                hint: "A formed mill is not always worth keeping closed. Consider which piece \
                       can leave it to create the decisive continuation.",
                completion: "Opening the existing mill released the piece needed for the forced \
                             win.",
            };
        }
        PuzzleMotif::CaptureChoice => {
            return ThemeProse {
                tag: "capture-choice",
                headline: "remove the right piece",
                hint: "The mill is only half the decision. Compare every legal removal before \
                       choosing the target.",
                completion: "The correct removal preserved the shortest forced win; another \
                             legal target would not.",
            };
        }
        PuzzleMotif::Zugzwang => {
            return ThemeProse {
                tag: "zugzwang",
                headline: "leave only a losing move",
                hint: "Do not rush to remove material. Find the quiet move that leaves the \
                       opponent exactly one legal reply.",
                completion: "The opponent was left with one compulsory move, and making it \
                             conceded the winning route.",
            };
        }
        PuzzleMotif::AllowMill => {
            return ThemeProse {
                tag: "allow-mill",
                headline: "look beyond the immediate mill",
                hint: "The obvious threat need not be stopped. Compare what the opponent must \
                       concede after carrying it out.",
                completion: "Allowing the mill preserved the larger plan and left the defence \
                             unable to meet the follow-up.",
            };
        }
        PuzzleMotif::MobilitySqueeze => {
            return ThemeProse {
                tag: "mobility-squeeze",
                headline: "compress the defence",
                hint: "Count useful replies as well as material. One quiet move sharply reduces \
                       the opponent's freedom.",
                completion: "The quiet move compressed the defender's mobility and made the \
                             remaining route forcing.",
            };
        }
        PuzzleMotif::JunctionRelease => {
            return ThemeProse {
                tag: "junction-release",
                headline: "release the key junction",
                hint: "A valuable intersection need not be occupied forever. Consider what \
                       moving away forces elsewhere.",
                completion: "Giving up the junction reduced the opponent's freedom and took the \
                             initiative.",
            };
        }
        PuzzleMotif::MillRecovery => {
            return ThemeProse {
                tag: "mill-recovery",
                headline: "prepare the mill's recovery",
                hint: "Improve the support around the formed mill so that losing one member will \
                       not end the structure.",
                completion: "The supporting move made the mill recoverable and preserved the \
                             winning mechanism.",
            };
        }
        PuzzleMotif::RightAngleThreat => {
            return ThemeProse {
                tag: "right-angle-threat",
                headline: "turn the corner with two threats",
                hint: "Find the quiet landing point which supports an open mill in each \
                       direction.",
                completion: "The landing piece joined two perpendicular open mills, leaving \
                             the defence unable to cover both.",
            };
        }
        PuzzleMotif::RingTransfer => {
            return ThemeProse {
                tag: "ring-transfer",
                headline: "transfer the attack across the rings",
                hint: "Look along the connectors between rings. A quiet transfer can create a \
                       new mill threat on arrival.",
                completion: "Crossing to the neighbouring ring created a new open mill and \
                             carried the attack forward.",
            };
        }
        PuzzleMotif::Any => {}
    }
    if !conceal_first_move_trap && traits.tempting_mill_mistake && traits.quiet_first_move {
        return ThemeProse {
            tag: "trap:greedy-mill",
            headline: "resist the tempting mill",
            hint: "The obvious mill is a trap. Look for the move that sets up an \
                   unstoppable threat instead.",
            completion: "The tempting mill would have thrown the win away — the quiet move \
                         was the only path.",
        };
    }
    if !conceal_first_move_trap && traits.tempting_mill_mistake {
        return ThemeProse {
            tag: "trap:wrong-mill",
            headline: "choose the right removal",
            hint: "Several removals look promising, but only one preserves the win. \
                   Compare the resulting positions.",
            completion: "Only one of the tempting removals preserved the forced win; the \
                         others handed the game back.",
        };
    }
    if conceal_first_move_trap && traits.tempting_mill_mistake {
        return ThemeProse {
            tag: "forced-win",
            headline: "find the forced win",
            hint: "Compare the complete result of every legal first turn. Find the route that \
                   keeps the shortest win.",
            completion: "The attractive immediate continuation was the trap; the less obvious \
                         route preserved the shortest forced win.",
        };
    }
    if line.double_mill {
        return ThemeProse {
            tag: "double-mill",
            headline: "set up the swing mill",
            hint: "Arrange your pieces so one of them can close a mill on every move.",
            completion: "The swing mill ground the defense down: every solver move closed a \
                         mill and removed a piece.",
        };
    }
    if line.immobilization_win {
        return ThemeProse {
            tag: "immobilization",
            headline: "immobilize the opponent",
            hint: "You do not need to remove every piece. Herd the opponent's pieces until \
                   none of them can move.",
            completion: "The win came by immobilization: the opponent still had material but \
                         no legal move left.",
        };
    }
    if line.sacrifice {
        return ThemeProse {
            tag: "sacrifice",
            headline: "give up a piece to win",
            hint: "Letting the opponent remove a piece is part of the plan. Count the \
                   resulting threats, not the material.",
            completion: "The sacrifice bought a decisive attack — material handed over, game \
                         taken back.",
        };
    }
    if traits.quiet_first_move {
        return ThemeProse {
            tag: "quiet-move",
            headline: "a quiet move wins",
            hint: "Do not look for an immediate removal. Improve a piece, and the threats \
                   will follow.",
            completion: "The winning idea started with a quiet move — the kind that is \
                         easiest to overlook over the board.",
        };
    }
    if line.vs_flying {
        return ThemeProse {
            tag: "vs-flying",
            headline: "ground the flying defense",
            hint: "The opponent will start flying anywhere on the board. Your net has to \
                   close faster than they can escape.",
            completion: "Even the flying defense could not escape: the winning net closed \
                         first.",
        };
    }
    ThemeProse {
        tag: "forced-win",
        headline: "find the forced win",
        hint: "Every reply has been accounted for. Find the move that keeps all the doors \
               closed.",
        completion: "A clean forced win, carried through against the defence that delays defeat.",
    }
}

pub(crate) fn build_puzzle_info(input: &PuzzleBuildInput<'_>) -> PuzzleInfoJson {
    assert!(
        !input.solutions.is_empty(),
        "a puzzle must have at least one constructed solution line"
    );

    // The headline "win in N" always refers to the fastest constructed
    // line, matching how `PuzzleSolution.isOptimal` is documented ("shortest
    // move count") and how puzzle notation conventionally names the mate/
    // win distance. Slower alternative lines are still included as
    // additional, non-optimal `PuzzleSolution` entries.
    let target_moves = input
        .solutions
        .iter()
        .map(|s| s.solver_move_count)
        .min()
        .expect("solutions is non-empty");
    let shortest_first_turn_count = input.traits.shortest_winning_count;
    assert!(
        shortest_first_turn_count > 0,
        "a puzzle must expose at least one shortest winning first turn"
    );
    let optimal_solutions = input
        .solutions
        .iter()
        .filter(|solution| solution.solver_move_count == target_moves)
        .cloned()
        .collect::<Vec<_>>();
    let line = aggregate_line_traits(&optimal_solutions);
    let theme = select_theme(&input.traits, &line, input.engine_blunder.is_some());

    let (difficulty, rating) = derive_difficulty_and_rating(
        target_moves,
        shortest_first_turn_count,
        &input.traits,
        &line,
        input.is_moving_phase,
    );
    // Movement-phase puzzles are plain "win the game" tactics; placement-
    // phase ones double as opening-theory study material, which the app
    // already tracks under a dedicated category.
    let category = if input.is_moving_phase {
        "winGame"
    } else {
        "opening"
    };

    let phase_word = if input.is_moving_phase {
        "movement"
    } else {
        "placement"
    };
    let side_word = side_label(input.solver_side);
    let title = format!(
        "Win in {target_moves}: {headline}",
        headline = theme.headline
    );

    let total_first_turns = shortest_first_turn_count + input.traits.non_shortest_count;
    let move_noun = if target_moves == 1 { "move" } else { "moves" };
    let mut description = format!(
        "{side} to move and win in {target_moves} {move_noun} against the defence that delays \
         defeat.",
        side = capitalize(side_word),
    );
    if input.traits.non_shortest_count > 0 {
        description.push_str(&format!(
            " Only {shortest_first_turn_count} of the {total_first_turns} complete legal first \
             turns achieve the shortest win.",
        ));
    }
    if input.traits.slower_winning_count > 0 {
        description.push_str(&format!(
            " {} other winning first turn{} take{} longer.",
            input.traits.slower_winning_count,
            if input.traits.slower_winning_count == 1 {
                ""
            } else {
                "s"
            },
            if input.traits.slower_winning_count == 1 {
                "s"
            } else {
                ""
            },
        ));
    }
    if line.sacrifice {
        description.push_str(" Requires accepting a material sacrifice along the way.");
    }
    if input.discovery_tag == Some("discovery:smt-z3") {
        description.push_str(
            " Its geometry was synthesised with Z3 and independently rechecked by Rust/TGF.",
        );
    }
    if input.replay_provenance.is_some() {
        description.push_str(
            " Replay-backed position: Rust/TGF accepted the anonymised source-game history, and \
             the recorded human turn missed this Perfect DB-certified win. Displayed solutions \
             are deterministic principal variations against a defence that delays defeat; \
             equally fast later continuations may exist.",
        );
    } else {
        description.push_str(
            " Composed position: rule-consistent and Perfect DB-certified; no legal replay \
             witness is claimed.",
        );
    }

    let mut completion = String::from(theme.completion);
    if line.only_move_count > 0 && line.decision_point_count > 0 {
        if line.decision_point_count == 1 {
            completion
                .push_str(" At the later decision point, only one turn achieved the shortest win.");
        } else {
            completion.push_str(&format!(
                " At {only} of the {total} later decision points, only one turn achieved the \
                 shortest win.",
                only = line.only_move_count,
                total = line.decision_point_count,
            ));
        }
    }

    let mut tags = vec![
        "generated".to_string(),
        "malom-db".to_string(),
        format!("win-in-{target_moves}"),
        format!(
            "distance-band:{}",
            if target_moves <= 7 {
                "short"
            } else if target_moves <= 15 {
                "medium"
            } else {
                "long"
            }
        ),
        format!("phase:{phase_word}"),
        format!("side:{side_word}"),
        format!("shortest-first-turns:{shortest_first_turn_count}"),
        format!(
            "slower-winning-first-turns:{}",
            input.traits.slower_winning_count
        ),
        format!("non-winning-first-turns:{}", input.traits.non_winning_count),
        theme.tag.to_string(),
    ];
    if let Some(replay) = input.replay_provenance {
        tags.push("source:replay-backed".to_string());
        tags.push("human-missed-win".to_string());
        tags.push("solution-display:principal-variation".to_string());
        tags.push(format!(
            "evidence:human-replay:{}",
            &replay.source_game_sha256[..12]
        ));
        tags.push(format!(
            "presentation-transform:{}",
            replay.presentation_transform
        ));
    } else {
        tags.push("source:composed".to_string());
    }
    if let Some(discovery_tag) = input.discovery_tag {
        tags.push(discovery_tag.to_string());
    }
    if let Some(evidence) = input.engine_blunder {
        tags.push("source:engine-blunder-corpus".to_string());
        tags.push(format!("source-severity:{}", evidence.severity));
        tags.push(format!("source-search-depth:{}", evidence.depth_used));
        tags.push(format!(
            "source-trap-score-band:{}",
            match evidence.trap_score {
                0..=63 => "low",
                64..=127 => "medium",
                128..=191 => "high",
                _ => "very-high",
            }
        ));
        tags.push(format!(
            "source-mass-band:{}",
            if evidence.mass >= 100_000.0 {
                "very-high"
            } else if evidence.mass >= 1_000.0 {
                "high"
            } else if evidence.mass >= 10.0 {
                "medium"
            } else {
                "low"
            }
        ));
    }
    if input.traits.tempting_mill_mistake && input.traits.quiet_first_move {
        if theme.tag != "trap:greedy-mill" {
            tags.push("trap:greedy-mill".to_string());
        }
    } else if input.traits.tempting_mill_mistake && theme.tag != "trap:wrong-mill" {
        tags.push("trap:wrong-mill".to_string());
    }
    if line.sacrifice && theme.tag != "sacrifice" {
        tags.push("sacrifice".to_string());
    }
    if line.double_mill && theme.tag != "double-mill" {
        tags.push("double-mill".to_string());
    }
    if line.immobilization_win && theme.tag != "immobilization" {
        tags.push("immobilization".to_string());
    }
    if line.vs_flying && theme.tag != "vs-flying" {
        tags.push("vs-flying".to_string());
    }
    if traits_only_moves_throughout(&line) {
        tags.push("precision".to_string());
    }
    match input.traits.solve_depth {
        Some(depth) => tags.push(format!("solve-depth:{depth}")),
        None => tags.push("solve-depth:deep".to_string()),
    }

    let id = format!(
        "malom_{phase_word}_{side_word}_{target_moves}_{}",
        short_hash(input.fen)
    );

    let solutions = input
        .solutions
        .iter()
        .enumerate()
        .map(|(index, built)| PuzzleSolutionJson {
            moves: built
                .plies
                .iter()
                .map(|ply| PuzzleMoveJson {
                    notation: ply.notation.clone(),
                    side: side_label(ply.side),
                    comment: None,
                })
                .collect(),
            description: Some(if index == 0 {
                "Main shortest solution".to_string()
            } else if built.solver_move_count == target_moves {
                format!("Alternative shortest solution {}", index + 1)
            } else {
                format!("Slower winning solution {}", index + 1)
            }),
            // The shortest solver-move-count line(s) are marked optimal so
            // the in-app hint system and star rating key off the sharpest
            // line; `target_moves` is that minimum by construction above.
            is_optimal: built.solver_move_count == target_moves,
        })
        .collect();

    let provenance = input.replay_provenance.map(|replay| PuzzleProvenanceJson {
        kind: "human-game-replay",
        corpus: replay.corpus.clone(),
        database_sha256: replay.database_sha256.clone(),
        source_game_sha256: replay.source_game_sha256.clone(),
        source_logical_ply: replay.source_logical_ply,
        replay_history: replay.history.clone(),
        recorded_turn: replay.recorded_turn.clone(),
        presentation_transform: replay.presentation_transform,
        transform_model: replay.transform_model.clone(),
        position_games: replay.position_games,
        recorded_turn_games: replay.recorded_turn_games,
    });

    PuzzleInfoJson {
        id,
        title,
        description,
        category,
        difficulty,
        initial_position: input.fen.to_string(),
        solutions,
        hint: Some(theme.hint.to_string()),
        completion_message: Some(completion),
        provenance,
        tags,
        is_custom: false,
        author: input.author.to_string(),
        created_date: input.generated_at.to_string(),
        version: 1,
        rating: Some(rating),
        rule_variant_id: input.rule_variant_id.to_string(),
    }
}

/// True when every solver decision after the first move had exactly one
/// winning choice -- the line demands perfect precision throughout.
fn traits_only_moves_throughout(line: &LineTraits) -> bool {
    line.decision_point_count > 0 && line.only_move_count == line.decision_point_count
}

fn capitalize(word: &str) -> String {
    let mut chars = word.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
        None => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mill_puzzle::solver::SolutionPly;

    fn built(solver_move_count: i32, sacrifice: bool) -> BuiltSolution {
        BuiltSolution {
            plies: vec![
                SolutionPly {
                    notation: "a1".to_string(),
                    side: 0,
                },
                SolutionPly {
                    notation: "d1".to_string(),
                    side: 1,
                },
            ],
            solver_move_count,
            sacrifice,
            only_move_count: 0,
            decision_point_count: 0,
            double_mill: false,
            vs_flying: false,
            immobilization_win: false,
        }
    }

    fn plain_traits() -> PuzzleTraits {
        PuzzleTraits {
            motif: PuzzleMotif::Any,
            shortest_winning_count: 1,
            non_shortest_count: 0,
            slower_winning_count: 0,
            non_winning_count: 0,
            tempting_mill_mistake: false,
            quiet_first_move: false,
            solve_depth: Some(2),
        }
    }

    #[test]
    fn harder_puzzles_rate_higher_than_easier_ones() {
        let easy_line = LineTraits::default();
        let hard_line = LineTraits {
            sacrifice: true,
            only_move_count: 3,
            decision_point_count: 3,
            ..LineTraits::default()
        };
        let hard_traits = PuzzleTraits {
            motif: PuzzleMotif::Any,
            shortest_winning_count: 1,
            non_shortest_count: 10,
            slower_winning_count: 2,
            non_winning_count: 8,
            tempting_mill_mistake: true,
            quiet_first_move: true,
            solve_depth: None,
        };
        let (easy_diff, easy_rating) =
            derive_difficulty_and_rating(2, 3, &plain_traits(), &easy_line, false);
        let (hard_diff, hard_rating) =
            derive_difficulty_and_rating(7, 1, &hard_traits, &hard_line, true);
        assert!(hard_rating > easy_rating);
        assert_ne!(easy_diff, hard_diff);
    }

    #[test]
    fn deeper_solve_depth_always_raises_the_rating() {
        let line = LineTraits::default();
        let rating_for = |solve_depth: Option<i32>| {
            let traits = PuzzleTraits {
                solve_depth,
                ..plain_traits()
            };
            derive_difficulty_and_rating(4, 1, &traits, &line, true).1
        };
        assert!(rating_for(Some(4)) > rating_for(Some(2)));
        assert!(rating_for(Some(6)) > rating_for(Some(4)));
        assert!(rating_for(Some(8)) > rating_for(Some(6)));
        assert!(rating_for(None) > rating_for(Some(8)));
    }

    #[test]
    fn rating_is_always_clamped_to_the_documented_range() {
        let line = LineTraits::default();
        let (_, low) = derive_difficulty_and_rating(0, 99, &plain_traits(), &line, false);
        let max_line = LineTraits {
            sacrifice: true,
            double_mill: true,
            vs_flying: true,
            immobilization_win: true,
            only_move_count: 99,
            decision_point_count: 99,
        };
        let max_traits = PuzzleTraits {
            motif: PuzzleMotif::Any,
            shortest_winning_count: 1,
            non_shortest_count: 30,
            slower_winning_count: 5,
            non_winning_count: 25,
            tempting_mill_mistake: true,
            quiet_first_move: true,
            solve_depth: None,
        };
        let (_, high) = derive_difficulty_and_rating(999, 1, &max_traits, &max_line, true);
        assert!((400..=2400).contains(&low));
        assert!((400..=2400).contains(&high));
    }

    #[test]
    fn build_puzzle_info_uses_the_shortest_line_as_the_headline_and_optimal() {
        let solutions = vec![built(4, false), built(2, true)];
        let input = PuzzleBuildInput {
            fen: "test-fen",
            solver_side: 0,
            is_moving_phase: true,
            solutions: &solutions,
            traits: PuzzleTraits {
                motif: PuzzleMotif::Any,
                shortest_winning_count: 1,
                non_shortest_count: 5,
                slower_winning_count: 2,
                non_winning_count: 3,
                tempting_mill_mistake: false,
                quiet_first_move: false,
                solve_depth: Some(4),
            },
            author: "Test Author",
            rule_variant_id: "standard_9mm",
            generated_at: "2026-01-01T00:00:00.000Z",
            discovery_tag: None,
            replay_provenance: None,
            engine_blunder: None,
        };
        let info = build_puzzle_info(&input);

        assert!(info.title.starts_with("Win in 2:"));
        assert!(info.tags.contains(&"win-in-2".to_string()));
        assert!(info.tags.contains(&"sacrifice".to_string()));
        assert!(info.tags.contains(&"solve-depth:4".to_string()));
        assert!(info.hint.is_some());
        assert!(info.completion_message.is_some());
        assert_eq!(info.solutions.len(), 2);
        assert!(
            info.solutions[1].is_optimal,
            "the 2-move line must be optimal"
        );
        assert!(
            !info.solutions[0].is_optimal,
            "the 4-move line must not be optimal"
        );
        assert_eq!(info.category, "winGame");
        assert_eq!(info.rule_variant_id, "standard_9mm");
        assert_eq!(info.version, 1);
        assert!(!info.is_custom);
    }

    #[test]
    fn trap_theme_takes_precedence_and_prose_stays_consistent() {
        let solutions = vec![built(3, false)];
        let input = PuzzleBuildInput {
            fen: "trap-fen",
            solver_side: 1,
            is_moving_phase: false,
            solutions: &solutions,
            traits: PuzzleTraits {
                motif: PuzzleMotif::Any,
                shortest_winning_count: 1,
                non_shortest_count: 8,
                slower_winning_count: 0,
                non_winning_count: 8,
                tempting_mill_mistake: true,
                quiet_first_move: true,
                solve_depth: None,
            },
            author: "Test Author",
            rule_variant_id: "standard_9mm",
            generated_at: "2026-01-01T00:00:00.000Z",
            discovery_tag: None,
            replay_provenance: None,
            engine_blunder: None,
        };
        let info = build_puzzle_info(&input);

        assert_eq!(info.title, "Win in 3: resist the tempting mill");
        assert!(info.tags.contains(&"trap:greedy-mill".to_string()));
        assert!(info.tags.contains(&"solve-depth:deep".to_string()));
        assert!(
            info.description
                .contains("Only 1 of the 9 complete legal first turns")
        );
        assert!(
            info.completion_message
                .as_deref()
                .expect("generated puzzles include completion prose")
                .contains(" — ")
        );
        assert_eq!(info.category, "opening");
    }

    #[test]
    fn engine_blunder_source_keeps_the_trap_out_of_the_headline() {
        let solutions = vec![built(4, false)];
        let evidence = EngineBlunderEvidence {
            severity: 2,
            trap_score: 220,
            mass: 2_000.0,
            depth_used: 9,
        };
        let input = PuzzleBuildInput {
            fen: "hidden-trap-fen",
            solver_side: 0,
            is_moving_phase: true,
            solutions: &solutions,
            traits: PuzzleTraits {
                motif: PuzzleMotif::Any,
                shortest_winning_count: 1,
                non_shortest_count: 8,
                slower_winning_count: 0,
                non_winning_count: 8,
                tempting_mill_mistake: true,
                quiet_first_move: true,
                solve_depth: None,
            },
            author: "Test Author",
            rule_variant_id: "standard_9mm",
            generated_at: "2026-01-01T00:00:00.000Z",
            discovery_tag: Some("discovery:engine-blunder-corpus"),
            replay_provenance: None,
            engine_blunder: Some(&evidence),
        };
        let info = build_puzzle_info(&input);

        assert_eq!(info.title, "Win in 4: find the forced win");
        assert!(info.tags.contains(&"trap:greedy-mill".to_string()));
        assert!(
            info.tags
                .contains(&"source:engine-blunder-corpus".to_string())
        );
        assert!(!info.hint.as_deref().unwrap().contains("trap"));
        assert!(!info.hint.as_deref().unwrap().contains("quiet"));
    }

    #[test]
    fn description_pluralizes_the_move_count() {
        let build_description = |solver_move_count: i32| {
            let solutions = vec![built(solver_move_count, false)];
            let input = PuzzleBuildInput {
                fen: "test-fen",
                solver_side: 0,
                is_moving_phase: true,
                solutions: &solutions,
                traits: plain_traits(),
                author: "Test Author",
                rule_variant_id: "standard_9mm",
                generated_at: "2026-01-01T00:00:00.000Z",
                discovery_tag: None,
                replay_provenance: None,
                engine_blunder: None,
            };
            build_puzzle_info(&input).description
        };

        assert!(build_description(1).contains("win in 1 move against"));
        assert!(build_description(2).contains("win in 2 moves against"));
    }

    #[test]
    fn completion_pluralizes_follow_up_decisions() {
        let build_completion = |decision_point_count: i32| {
            let mut solution = built(3, false);
            solution.only_move_count = 1;
            solution.decision_point_count = decision_point_count;
            let solutions = vec![solution];
            let input = PuzzleBuildInput {
                fen: "test-fen",
                solver_side: 0,
                is_moving_phase: true,
                solutions: &solutions,
                traits: plain_traits(),
                author: "Test Author",
                rule_variant_id: "standard_9mm",
                generated_at: "2026-01-01T00:00:00.000Z",
                discovery_tag: None,
                replay_provenance: None,
                engine_blunder: None,
            };
            build_puzzle_info(&input)
                .completion_message
                .expect("generated puzzles include completion prose")
        };

        assert!(
            build_completion(1)
                .contains("At the later decision point, only one turn achieved the shortest win.")
        );
        assert!(build_completion(2).contains(
            "At 1 of the 2 later decision points, only one turn achieved the shortest win."
        ));
    }

    #[test]
    fn flying_theme_uses_mill_specific_winning_language() {
        let theme = select_theme(
            &plain_traits(),
            &LineTraits {
                vs_flying: true,
                ..LineTraits::default()
            },
            false,
        );

        assert_eq!(theme.headline, "ground the flying defense");
        assert_eq!(
            theme.completion,
            "Even the flying defense could not escape: the winning net closed first."
        );
    }

    #[test]
    fn immobilization_theme_uses_standard_mill_language() {
        let theme = select_theme(
            &plain_traits(),
            &LineTraits {
                immobilization_win: true,
                ..LineTraits::default()
            },
            false,
        );

        assert_eq!(theme.headline, "immobilize the opponent");
        assert_eq!(theme.tag, "immobilization");
        assert!(theme.completion.contains("immobilization"));
    }

    #[test]
    fn generated_theme_copy_uses_removal_terminology() {
        let wrong_mill = select_theme(
            &PuzzleTraits {
                tempting_mill_mistake: true,
                ..plain_traits()
            },
            &LineTraits::default(),
            false,
        );
        let quiet_move = select_theme(
            &PuzzleTraits {
                quiet_first_move: true,
                ..plain_traits()
            },
            &LineTraits::default(),
            false,
        );

        for theme in [wrong_mill, quiet_move] {
            assert!(!theme.headline.contains("capture"));
            assert!(!theme.hint.contains("capture"));
            assert!(!theme.completion.contains("capture"));
        }
    }

    #[test]
    fn side_label_rejects_invalid_side_values() {
        assert_eq!(side_label(0), "white");
        assert_eq!(side_label(1), "black");
    }

    #[test]
    fn capitalize_handles_ascii_words_and_empty_input() {
        assert_eq!(capitalize("white"), "White");
        assert_eq!(capitalize(""), "");
    }
}
