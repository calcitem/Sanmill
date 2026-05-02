// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// Recommended search depth computation, mirroring master `Mills::get_search_depth`
// in `src/mills.cpp` (P2-E).

use crate::rules::{MillFormationActionInPlacingPhase, MillPhase, MillState, MillVariantOptions};

/// Mirror of `GameOptions` fields that affect depth selection.
pub struct EngineRuntimeOptions {
    pub skill_level: u8,
    pub draw_on_human_experience: bool,
    pub developer_mode: bool,
}

impl Default for EngineRuntimeOptions {
    fn default() -> Self {
        Self {
            skill_level: 1,
            draw_on_human_experience: true,
            developer_mode: true,
        }
    }
}

/// Compute the recommended search depth for the current position, mirroring
/// master `Mills::get_search_depth(const Position *pos)` in `src/mills.cpp`.
///
/// The depth depends on the game phase, piece count, variant options (diagonal
/// lines, fly-capture, stalemate action), and engine runtime options (skill
/// level, developer mode, draw on human experience). Returns at least 1.
pub fn recommended_search_depth(
    state: &MillState,
    options: &MillVariantOptions,
    runtime: &EngineRuntimeOptions,
) -> i32 {
    const DEPTH_ADJUST: i32 = 0; // master include/config.h: constexpr auto DEPTH_ADJUST = 0

    let level = i32::from(runtime.skill_level);
    let pw = i32::from(state.pieces_on_board()[0]);
    let pb = i32::from(state.pieces_on_board()[1]);
    let pieces = pw + pb;

    // Non-developer mode: use simpler depth tables.
    if !runtime.developer_mode {
        if state.phase() == MillPhase::Placing {
            // Lasker Morris (may_move_in_placing_phase) and
            // draw_on_human_experience=false → depth == SkillLevel.
            if !runtime.draw_on_human_experience || options.may_move_in_placing_phase {
                return level;
            }

            #[rustfmt::skip]
            const PLACING_DEPTH_TABLE_9: [i32; 25] = [
                1,  1,  1,  1,   // 0-3
                3,  3,  3, 15,   // 4-7
               15,  5, 18,  0,   // 8-11
                0,  0,  0,  0,   // 12-15
                0,  0,  0,  0,   // 16-19
                0,  0,  0,  0,   // 20-23
                0,               // 24
            ];
            #[rustfmt::skip]
            const PLACING_DEPTH_TABLE_12: [i32; 25] = [
                1,  2,  2,  4,   // 0-3
                4, 12, 12, 18,   // 4-7
               12,  0,  0,  0,   // 8-11
                0,  0,  0,  0,   // 12-15
                0,  0,  0,  0,   // 16-19
                0,  0,  0,  0,   // 20-23
                0,               // 24
            ];

            let index = (i32::from(options.piece_count) * 2
                - i32::from(state.pieces_in_hand[0])
                - i32::from(state.pieces_in_hand[1]))
            .max(0) as usize;

            let d = if options.has_diagonal_lines {
                PLACING_DEPTH_TABLE_12.get(index).copied().unwrap_or(0)
            } else {
                PLACING_DEPTH_TABLE_9.get(index).copied().unwrap_or(0)
            };

            if d == 0 {
                return level;
            }
            return if level > d { d } else { level };
        }
        if state.phase() == MillPhase::Moving {
            return level;
        }
    }

    // Developer mode: use full depth tables.
    #[rustfmt::skip]
    const PLACING_DEPTH_TABLE_12: [i32; 25] = [
         1,  2,  2,  4,   // 0-3
         4, 12, 12, 18,   // 4-7
        12, 16, 16, 16,   // 8-11
        16, 16, 16, 17,   // 12-15
        17, 16, 16, 15,   // 16-19
        15, 14, 14, 14,   // 20-23
        14,               // 24
    ];
    #[rustfmt::skip]
    const PLACING_DEPTH_TABLE_12_SPECIAL: [i32; 25] = [
         1,  2,  2,  4,   // 0-3
         4, 12, 12, 12,   // 4-7
        12, 13, 13, 13,   // 8-11
        13, 13, 13, 13,   // 12-15
        13, 13, 13, 13,   // 16-19
        13, 13, 13, 13,   // 20-23
        13,               // 24
    ];
    #[rustfmt::skip]
    const PLACING_DEPTH_TABLE_9: [i32; 20] = [
         1,  7,  7, 10,   // 0-3
        10, 12, 12, 14,   // 4-7
        14, 14, 14, 14,   // 8-11
        14, 14, 14, 14,   // 12-15
        14, 14, 14,       // 16-18
        14,               // 19
    ];
    #[rustfmt::skip]
    const MOVING_DEPTH_TABLE: [i32; 24] = [
         1,  1,  1,  1,  // 0-3
         1,  1, 11, 11,  // 4-7
        11, 11, 11, 11,  // 8-11
        11, 11, 11, 11,  // 12-15
        11, 11, 12, 12,  // 16-19
        12, 12, 13, 14,  // 20-23
    ];
    // Non-endgame-learning diff table (master's non-#ifdef path).
    const MOVING_DIFF_DEPTH_TABLE: [i32; 13] = [
        0, 0, 0, // 0-2
        11, 11, 10, 9, 8, // 3-7
        7, 6, 5, 4, 3, // 8-12
    ];
    const FLYING_DEPTH: i32 = 9;

    let mut d = 0_i32;

    if state.phase() == MillPhase::Placing {
        let index = (i32::from(options.piece_count) * 2
            - i32::from(state.pieces_in_hand[0])
            - i32::from(state.pieces_in_hand[1])) as usize;

        if options.piece_count == 9 {
            d = PLACING_DEPTH_TABLE_9.get(index).copied().unwrap_or(0);
        } else {
            // Use the "special" table unless diagonal lines or MarkAndDelay.
            let use_special = options.mill_formation_action_in_placing_phase
                != MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces
                && !options.has_diagonal_lines;
            d = if use_special {
                PLACING_DEPTH_TABLE_12_SPECIAL
                    .get(index)
                    .copied()
                    .unwrap_or(0)
            } else {
                PLACING_DEPTH_TABLE_12.get(index).copied().unwrap_or(0)
            };
        }
    }

    if state.phase() == MillPhase::Moving {
        let diff = (pb - pw).unsigned_abs() as usize;
        d = MOVING_DIFF_DEPTH_TABLE.get(diff).copied().unwrap_or(0);
        if d == 0 {
            d = MOVING_DEPTH_TABLE
                .get(pieces as usize)
                .copied()
                .unwrap_or(0);
        }

        // Flying depth adjustments.
        if options.may_fly {
            let fly_threshold = i32::from(options.fly_piece_count);
            if pb <= fly_threshold || pw <= fly_threshold {
                d = FLYING_DEPTH;
            }
            if pb <= fly_threshold && pw <= fly_threshold {
                d = FLYING_DEPTH / 2;
            }
        }
    }

    // WAR: Limit depth if stalemate doesn't immediately end the game.
    use crate::rules::StalemateAction;
    if options.stalemate_action != StalemateAction::EndWithStalemateLoss
        && options.stalemate_action != StalemateAction::EndWithStalemateDraw
        && d > 9
    {
        d = 9;
    }

    d += DEPTH_ADJUST;
    d = d.max(1);
    d
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rules::MillRules;
    use tgf_core::GameRules;

    #[test]
    fn recommended_depth_default_placing_returns_level() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let state = MillRules::decode_snapshot(rules.initial_state(&[]));
        let rt = EngineRuntimeOptions {
            skill_level: 5,
            draw_on_human_experience: false,
            developer_mode: false,
        };
        assert_eq!(recommended_search_depth(&state, &options, &rt), 5);
    }

    #[test]
    fn recommended_depth_developer_mode_placing_non_zero() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let state = MillRules::decode_snapshot(rules.initial_state(&[]));
        let rt = EngineRuntimeOptions {
            skill_level: 10,
            draw_on_human_experience: true,
            developer_mode: true,
        };
        let d = recommended_search_depth(&state, &options, &rt);
        assert!(d >= 1, "depth should be >= 1, got {d}");
    }
}
