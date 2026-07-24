// SPDX-License-Identifier: AGPL-3.0-or-later

use tgf_core::{ActionList, GameRules};

use super::*;
use crate::{MillUciCodec, MillVariantOptions};

fn apply_token(
    rules: &MillRules,
    snapshot: &mut GameStateSnapshot,
    history: &mut Vec<GameStateSnapshot>,
    counts: &mut MillPlyCount,
    token: &str,
) {
    let action = MillUciCodec::decode_action(snapshot, token).expect("token must decode");
    let mut legal = ActionList::<256>::new();
    rules.legal_actions(snapshot, &mut legal);
    assert!(legal.as_slice().contains(&action), "{token} must be legal");
    let before = *snapshot;
    let after = rules.apply_with_history(&before, action, history);
    history.push(before);
    counts.record(rules, &before, &after).unwrap();
    *snapshot = after;
}

#[test]
fn mill_and_removal_count_as_one_logical_ply() {
    let rules = MillRules::new(MillVariantOptions::default());
    let mut snapshot = rules.initial_state(&[]);
    let mut history = Vec::new();
    let mut setup_counts = MillPlyCount::default();
    for token in ["d7", "a1", "g7", "d1"] {
        apply_token(
            &rules,
            &mut snapshot,
            &mut history,
            &mut setup_counts,
            token,
        );
    }
    let mut counts = MillPlyCount::default();

    apply_token(&rules, &mut snapshot, &mut history, &mut counts, "a7");
    assert_eq!(counts.action_tokens, 1);
    assert_eq!(counts.logical_plies, 0);
    assert_eq!(snapshot.side_to_move, 0);

    let remove = {
        let mut legal = ActionList::<256>::new();
        rules.legal_actions(&snapshot, &mut legal);
        MillUciCodec::encode_action(legal.as_slice()[0])
    };
    apply_token(&rules, &mut snapshot, &mut history, &mut counts, &remove);
    assert_eq!(counts.action_tokens, 2);
    assert_eq!(counts.logical_plies, 1);
    assert_eq!(counts.logical_plies_by_side, [1, 0]);
}

#[test]
fn logical_turn_enumeration_expands_removal_continuations() {
    let rules = MillRules::new(MillVariantOptions::default());
    let mut snapshot = rules.initial_state(&[]);
    let mut history = Vec::new();
    let mut counts = MillPlyCount::default();
    for token in ["d7", "a1", "g7", "d1"] {
        apply_token(&rules, &mut snapshot, &mut history, &mut counts, token);
    }
    let turns = legal_logical_turns(&rules, &snapshot, &history).unwrap();
    let mill_turns = turns
        .iter()
        .filter(|turn| MillUciCodec::encode_action(turn.actions[0]) == "a7")
        .collect::<Vec<_>>();

    assert!(!mill_turns.is_empty());
    assert!(mill_turns.iter().all(|turn| turn.actions.len() == 2));
    assert!(
        mill_turns
            .iter()
            .all(|turn| turn.final_snapshot.side_to_move == 1)
    );
}
