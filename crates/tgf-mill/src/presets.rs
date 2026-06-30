// SPDX-License-Identifier: AGPL-3.0-or-later
// Canonical Mill rule presets.
//
// Each preset is a named MillVariantOptions configuration that corresponds
// to one user-selectable rule variant.  These are used:
//   * by Flutter/Dart rule settings as the stable list of named variants.
//   * by replay and oracle tests to map persisted rule_idx values to MillRules.
//
// The order and field values are persisted app-level compatibility data.

use crate::rules::{
    MillBoardFullAction, MillFormationActionInPlacingPhase, MillRules, MillVariantOptions,
    StalemateAction,
};

/// A named rule preset.
#[derive(Clone, Debug)]
pub struct MillRulePreset {
    /// Stable persisted preset index.
    pub id: i32,
    /// Human-readable English name.
    pub name: &'static str,
    /// Short description (same as C++ Rule::description).
    pub description: &'static str,
    /// The corresponding `MillVariantOptions`.
    pub options: MillVariantOptions,
}

/// Look up a preset by its integer rule index (0..=10).
/// Returns `None` when `idx` is outside `0..=10`.
pub fn preset_for(idx: i32) -> Option<MillRulePreset> {
    let d = MillVariantOptions::default();
    let (name, options) = match idx {
        0 => (
            "Nine Men's Morris",
            d, // fully default
        ),
        1 => (
            "Twelve Men's Morris",
            MillVariantOptions {
                piece_count: 12,
                has_diagonal_lines: true,
                ..d
            },
        ),
        2 => (
            "Dooz",
            MillVariantOptions {
                piece_count: 12,
                has_diagonal_lines: true,
                mill_formation_action_in_placing_phase:
                    MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenOpponentsTurn,
                ..d
            },
        ),
        3 => (
            "Morabaraba",
            MillVariantOptions {
                piece_count: 12,
                has_diagonal_lines: true,
                may_remove_multiple: true,
                ..d
            },
        ),
        4 => (
            "Russian Mill",
            MillVariantOptions {
                one_time_use_mill: true,
                ..d
            },
        ),
        5 => (
            "Lasker Morris",
            MillVariantOptions {
                piece_count: 10,
                may_move_in_placing_phase: true,
                ..d
            },
        ),
        6 => (
            "Cheng San Qi",
            MillVariantOptions {
                may_fly: false,
                ..d
            },
        ),
        7 => (
            "Da San Qi",
            MillVariantOptions {
                piece_count: 12,
                has_diagonal_lines: true,
                mill_formation_action_in_placing_phase:
                    MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces,
                is_defender_move_first: true,
                may_remove_from_mills_always: true,
                may_fly: false,
                ..d
            },
        ),
        8 => (
            "Zhi Qi",
            MillVariantOptions {
                piece_count: 12,
                has_diagonal_lines: true,
                board_full_action: MillBoardFullAction::FirstAndSecondPlayerRemovePiece,
                stalemate_action: StalemateAction::RemoveOpponentsPieceAndMakeNextMove,
                ..d
            },
        ),
        9 => (
            "El Filja",
            MillVariantOptions {
                piece_count: 12,
                mill_formation_action_in_placing_phase:
                    MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts,
                may_remove_from_mills_always: true,
                board_full_action: MillBoardFullAction::FirstAndSecondPlayerRemovePiece,
                may_fly: false,
                ..d
            },
        ),
        10 => (
            "Experimental",
            MillVariantOptions {
                piece_count: 12,
                has_diagonal_lines: true,
                is_defender_move_first: true,
                may_remove_from_mills_always: true,
                board_full_action: MillBoardFullAction::SecondAndFirstPlayerRemovePiece,
                may_fly: false,
                ..d
            },
        ),
        _ => return None,
    };
    Some(MillRulePreset {
        id: idx,
        name,
        description: name, // description = name for all presets
        options,
    })
}

/// Convenience: build `MillRules` directly from a rule index (0..=10).
/// Panics via `MillRules::new` assert if the options are invalid (should never
/// happen for canonical presets).
pub fn rules_for_preset(idx: i32) -> Option<MillRules> {
    let preset = preset_for(idx)?;
    Some(MillRules::new(preset.options))
}

/// Number of canonical presets.
pub const N_PRESETS: i32 = 11;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_11_presets_are_present() {
        for idx in 0..N_PRESETS {
            assert!(preset_for(idx).is_some(), "preset_for({idx}) returned None");
        }
    }

    #[test]
    fn out_of_range_returns_none() {
        assert!(preset_for(-1).is_none());
        assert!(preset_for(11).is_none());
    }

    #[test]
    fn all_preset_ids_match_index() {
        for idx in 0..N_PRESETS {
            let preset = preset_for(idx).unwrap();
            assert_eq!(preset.id, idx, "preset id mismatch for index {idx}");
        }
    }

    #[test]
    fn all_preset_options_pass_validation() {
        for idx in 0..N_PRESETS {
            let preset = preset_for(idx).unwrap();
            // assert_valid() will panic if out of range.
            preset.options.assert_valid();
        }
    }

    #[test]
    fn rules_for_preset_builds_without_panic() {
        for idx in 0..N_PRESETS {
            let _ = rules_for_preset(idx).expect("rules_for_preset should return Some");
        }
    }
}
