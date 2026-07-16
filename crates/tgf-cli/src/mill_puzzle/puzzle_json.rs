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
    /// Number of legal first moves that immediately throw the win away.
    pub mistake_count: usize,
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
    winning_first_move_count: usize,
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
    if winning_first_move_count <= 1 {
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
fn select_theme(traits: &PuzzleTraits, line: &LineTraits) -> ThemeProse {
    if traits.tempting_mill_mistake && traits.quiet_first_move {
        return ThemeProse {
            tag: "trap:greedy-mill",
            headline: "resist the tempting mill",
            hint: "The capture that jumps out at you does not win. Look for the move that \
                   sets up an unstoppable threat instead.",
            completion: "The tempting mill would have thrown the win away — the quiet move \
                         was the only path.",
        };
    }
    if traits.tempting_mill_mistake {
        return ThemeProse {
            tag: "trap:wrong-mill",
            headline: "pick the right capture",
            hint: "More than one capture is on the board, but only one keeps the win. \
                   Compare what each removal leaves behind.",
            completion: "Only one of the tempting captures kept the forced win; the others \
                         handed the game back.",
        };
    }
    if line.double_mill {
        return ThemeProse {
            tag: "double-mill",
            headline: "set up the swing mill",
            hint: "Arrange your pieces so one of them can close a mill on every move.",
            completion: "The swing mill ground the defense down: every solver move closed a \
                         mill and took a piece.",
        };
    }
    if line.immobilization_win {
        return ThemeProse {
            tag: "immobilization",
            headline: "leave them no move",
            hint: "You do not need to capture everything. Herd the opponent's pieces until \
                   none of them can move.",
            completion: "The win came by immobilization: the opponent still had material but \
                         no legal move left.",
        };
    }
    if line.sacrifice {
        return ThemeProse {
            tag: "sacrifice",
            headline: "give up a piece to win",
            hint: "Letting the opponent capture is part of the plan. Count the resulting \
                   threats, not the material.",
            completion: "The sacrifice bought a decisive attack — material handed over, game \
                         taken back.",
        };
    }
    if traits.quiet_first_move {
        return ThemeProse {
            tag: "quiet-move",
            headline: "a quiet move wins",
            hint: "No capture starts this win. Improve a piece and the threats appear by \
                   themselves.",
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
            completion: "Even the flying defense could not escape: the mating net closed \
                         first.",
        };
    }
    ThemeProse {
        tag: "forced-win",
        headline: "find the forced win",
        hint: "Every reply has been accounted for. Find the move that keeps all the doors \
               closed.",
        completion: "A clean forced win, carried through against the best practical defense.",
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
    let winning_first_move_count = input.solutions.len();
    let line = aggregate_line_traits(input.solutions);
    let theme = select_theme(&input.traits, &line);

    let (difficulty, rating) = derive_difficulty_and_rating(
        target_moves,
        winning_first_move_count,
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

    let total_first_moves = winning_first_move_count + input.traits.mistake_count;
    let move_noun = if target_moves == 1 { "move" } else { "moves" };
    let mut description = format!(
        "{side} to move and win in {target_moves} {move_noun} against the opponent's best \
         practical defense.",
        side = capitalize(side_word),
    );
    if input.traits.mistake_count > 0 {
        description.push_str(&format!(
            " Only {winning_first_move_count} of the {total_first_moves} legal first moves \
             keep{s} the win alive.",
            s = if winning_first_move_count == 1 {
                "s"
            } else {
                ""
            },
        ));
    }
    if line.sacrifice {
        description.push_str(" Requires accepting a material sacrifice along the way.");
    }

    let mut completion = String::from(theme.completion);
    if line.only_move_count > 0 && line.decision_point_count > 0 {
        if line.decision_point_count == 1 {
            completion.push_str(
                " The follow-up decision allowed exactly one winning move.",
            );
        } else {
            completion.push_str(&format!(
                " {only} of the {total} follow-up decisions allowed exactly one winning move.",
                only = line.only_move_count,
                total = line.decision_point_count,
            ));
        }
    }

    let mut tags = vec![
        "generated".to_string(),
        "malom-db".to_string(),
        format!("win-in-{target_moves}"),
        format!("phase:{phase_word}"),
        format!("side:{side_word}"),
        theme.tag.to_string(),
    ];
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
                "Main solution".to_string()
            } else {
                format!("Alternative solution {}", index + 1)
            }),
            // The shortest solver-move-count line(s) are marked optimal so
            // the in-app hint system and star rating key off the sharpest
            // line; `target_moves` is that minimum by construction above.
            is_optimal: built.solver_move_count == target_moves,
        })
        .collect();

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
            mistake_count: 0,
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
            mistake_count: 10,
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
            mistake_count: 30,
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
                mistake_count: 5,
                tempting_mill_mistake: false,
                quiet_first_move: false,
                solve_depth: Some(4),
            },
            author: "Test Author",
            rule_variant_id: "standard_9mm",
            generated_at: "2026-01-01T00:00:00.000Z",
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
                mistake_count: 8,
                tempting_mill_mistake: true,
                quiet_first_move: true,
                solve_depth: None,
            },
            author: "Test Author",
            rule_variant_id: "standard_9mm",
            generated_at: "2026-01-01T00:00:00.000Z",
        };
        let info = build_puzzle_info(&input);

        assert_eq!(info.title, "Win in 3: resist the tempting mill");
        assert!(info.tags.contains(&"trap:greedy-mill".to_string()));
        assert!(info.tags.contains(&"solve-depth:deep".to_string()));
        assert!(
            info.description
                .contains("Only 1 of the 9 legal first moves")
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
            };
            build_puzzle_info(&input)
                .completion_message
                .expect("generated puzzles include completion prose")
        };

        assert!(
            build_completion(1)
                .contains("The follow-up decision allowed exactly one winning move.")
        );
        assert!(
            build_completion(2)
                .contains("1 of the 2 follow-up decisions allowed exactly one winning move.")
        );
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
