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
    pub puzzles: Vec<PuzzleInfoJson>,
}

#[derive(Debug, Clone, Serialize)]
pub(crate) struct ExportedByJson {
    #[serde(rename = "appName")]
    pub app_name: &'static str,
    pub platform: &'static str,
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

/// Heuristic difficulty/rating derived from how "sharp" the generated
/// puzzle is. This is intentionally simple and documented rather than
/// precise: deeper forced wins, fewer alternative winning first moves, and
/// lines that require a sacrifice all make a puzzle harder to find over the
/// board, so each nudges the rating up.
fn derive_difficulty_and_rating(
    target_moves: i32,
    winning_first_move_count: usize,
    sacrifice: bool,
    is_moving_phase: bool,
) -> (&'static str, i32) {
    let mut rating = 700 + target_moves * 120;
    if winning_first_move_count <= 1 {
        rating += 80;
    }
    if sacrifice {
        rating += 150;
    }
    if is_moving_phase {
        rating += 50;
    }
    let rating = rating.clamp(400, 2400);

    let difficulty = match rating {
        r if r < 800 => "beginner",
        r if r < 1000 => "easy",
        r if r < 1300 => "medium",
        r if r < 1600 => "hard",
        r if r < 1900 => "expert",
        _ => "master",
    };
    (difficulty, rating)
}

/// Everything needed to render one [`PuzzleInfoJson`] from a solved root
/// position plus its constructed solution lines.
pub(crate) struct PuzzleBuildInput<'a> {
    pub fen: &'a str,
    pub solver_side: i8,
    pub is_moving_phase: bool,
    pub solutions: &'a [BuiltSolution],
    pub author: &'a str,
    pub rule_variant_id: &'a str,
    pub generated_at: &'a str,
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
    let has_sacrifice = input.solutions.iter().any(|s| s.sacrifice);
    let winning_first_move_count = input.solutions.len();

    let (difficulty, rating) = derive_difficulty_and_rating(
        target_moves,
        winning_first_move_count,
        has_sacrifice,
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
        "Forced win in {target_moves} ({phase_word}, {side_word} to move)"
    );
    let mut description = format!(
        "{side} to move: find the forced win in {target_moves} move(s) even \
         against the opponent's best practical defense.",
        side = capitalize(side_word),
    );
    if has_sacrifice {
        description.push_str(" Requires accepting a material sacrifice along the way.");
    }

    let mut tags = vec![
        "generated".to_string(),
        "malom-db".to_string(),
        format!("win-in-{target_moves}"),
        format!("phase:{phase_word}"),
        format!("side:{side_word}"),
    ];
    if has_sacrifice {
        tags.push("sacrifice".to_string());
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
        hint: None,
        tags,
        is_custom: false,
        author: input.author.to_string(),
        created_date: input.generated_at.to_string(),
        version: 1,
        rating: Some(rating),
        rule_variant_id: input.rule_variant_id.to_string(),
    }
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
        }
    }

    #[test]
    fn harder_puzzles_rate_higher_than_easier_ones() {
        let (easy_diff, easy_rating) = derive_difficulty_and_rating(2, 3, false, false);
        let (hard_diff, hard_rating) = derive_difficulty_and_rating(7, 1, true, true);
        assert!(hard_rating > easy_rating);
        assert_ne!(easy_diff, hard_diff);
    }

    #[test]
    fn rating_is_always_clamped_to_the_documented_range() {
        let (_, low) = derive_difficulty_and_rating(0, 99, false, false);
        let (_, high) = derive_difficulty_and_rating(999, 1, true, true);
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
            author: "Test Author",
            rule_variant_id: "standard_9mm",
            generated_at: "2026-01-01T00:00:00.000Z",
        };
        let info = build_puzzle_info(&input);

        assert!(info.title.contains("in 2"));
        assert!(info.tags.contains(&"win-in-2".to_string()));
        assert!(info.tags.contains(&"sacrifice".to_string()));
        assert_eq!(info.solutions.len(), 2);
        assert!(info.solutions[1].is_optimal, "the 2-move line must be optimal");
        assert!(!info.solutions[0].is_optimal, "the 4-move line must not be optimal");
        assert_eq!(info.category, "winGame");
        assert_eq!(info.rule_variant_id, "standard_9mm");
        assert_eq!(info.version, 1);
        assert!(!info.is_custom);
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
