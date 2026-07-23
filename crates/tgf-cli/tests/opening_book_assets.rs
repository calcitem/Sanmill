// SPDX-License-Identifier: AGPL-3.0-or-later
// Verify that every shipped opening-book recommendation is legal under the
// authoritative Rust rules for its variant.

use serde_json::Value;
use tgf_core::{ActionList, GameRules};
use tgf_mill::{MillUciCodec, rules_for_preset};

const NMM_BOOK: &str =
    include_str!("../../../src/ui/flutter_app/assets/opening_books/nmm/opening_book.json");
const EL_FILJA_BOOK: &str =
    include_str!("../../../src/ui/flutter_app/assets/opening_books/el_filja/opening_book.json");

fn assert_oracle_recommendations_are_legal(asset: &str, preset: i32, variant: &str) {
    let document: Value = serde_json::from_str(asset).expect("opening-book asset must be JSON");
    assert_eq!(
        document.get("variant").and_then(Value::as_str),
        Some(variant),
        "opening-book asset variant must match its rule preset"
    );
    let oracle = document
        .get("oracle")
        .and_then(Value::as_object)
        .expect("opening-book asset must contain an oracle object");
    assert!(!oracle.is_empty(), "opening-book oracle must not be empty");
    let rules = rules_for_preset(preset).expect("opening-book preset must exist");

    for (fen, moves) in oracle {
        let state = rules
            .set_from_fen(fen)
            .unwrap_or_else(|error| panic!("opening-book FEN must parse ({error}): {fen}"));
        let snapshot = rules.encode_state(state);
        let mut legal = ActionList::<256>::new();
        rules.legal_actions(&snapshot, &mut legal);

        let recommendations = moves
            .as_array()
            .unwrap_or_else(|| panic!("opening-book moves must be an array: {fen}"));
        assert!(
            !recommendations.is_empty(),
            "opening-book position must recommend at least one move: {fen}"
        );
        for move_value in recommendations {
            let move_text = move_value
                .as_str()
                .unwrap_or_else(|| panic!("opening-book move must be a string: {fen}"));
            let action = MillUciCodec::decode_action(&snapshot, move_text)
                .unwrap_or_else(|| panic!("opening-book move must use Mill notation: {move_text}"));
            assert!(
                legal.as_slice().contains(&action),
                "opening-book move {move_text} is illegal for {fen}"
            );
        }
    }
}

#[test]
fn nmm_opening_book_only_recommends_legal_moves() {
    assert_oracle_recommendations_are_legal(NMM_BOOK, 0, "nmm");
}

#[test]
fn el_filja_opening_book_only_recommends_legal_moves() {
    assert_oracle_recommendations_are_legal(EL_FILJA_BOOK, 9, "el_filja");
}
