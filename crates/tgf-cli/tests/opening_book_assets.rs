// SPDX-License-Identifier: AGPL-3.0-or-later
// Verify that every shipped opening-book recommendation is legal under the
// authoritative Rust rules for its variant.

use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use tgf_core::{ActionList, GameRules};
use tgf_mill::{MillUciCodec, rules_for_preset};

const NMM_BOOK: &str =
    include_str!("../../../src/ui/flutter_app/assets/opening_books/nmm/opening_book.json");
const EL_FILJA_BOOK: &str =
    include_str!("../../../src/ui/flutter_app/assets/opening_books/el_filja/opening_book.json");
const OCCUPIED_C3_FEN: &str =
    "****OO*O/O@O*@OO@/@@**@*O* b p p 8 1 6 2 0 0 -1 -1 -1 -1 0 0 8 ids:nodes";
const DUPLICATE_C5_FEN: &str =
    "********/**@O@*@O/O******* w p p 3 6 3 6 0 0 -1 -1 -1 -1 0 0 4 ids:nodes";

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
        let mut seen = HashSet::new();
        for move_value in recommendations {
            let move_text = move_value
                .as_str()
                .unwrap_or_else(|| panic!("opening-book move must be a string: {fen}"));
            assert!(
                seen.insert(move_text),
                "opening-book move {move_text} is duplicated for {fen}"
            );
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

#[test]
fn nmm_opening_book_matches_the_repaired_asset_identity() {
    let document: Value = serde_json::from_str(NMM_BOOK).expect("NMM opening book must be JSON");
    let oracle = document["oracle"]
        .as_object()
        .expect("NMM opening book must contain an oracle object");
    let record_count: usize = oracle
        .values()
        .map(|moves| {
            moves
                .as_array()
                .expect("candidate list must be an array")
                .len()
        })
        .sum();
    let digest = Sha256::digest(NMM_BOOK.as_bytes());
    let digest_hex = digest
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();

    assert_eq!(oracle.len(), 109);
    assert_eq!(record_count, 437);
    assert_eq!(
        digest_hex,
        "cdc4768bc461c22177634985a4cc1d92452774e2992515b937fed8812eb076f5"
    );
}

#[test]
fn repaired_nmm_records_do_not_regress() {
    let document: Value = serde_json::from_str(NMM_BOOK).expect("NMM opening book must be JSON");
    let oracle = document["oracle"]
        .as_object()
        .expect("NMM opening book must contain an oracle object");

    assert!(
        !oracle.contains_key(OCCUPIED_C3_FEN),
        "the Oracle row that recommended occupied c3 must remain deleted"
    );
    let c5_count = oracle[DUPLICATE_C5_FEN]
        .as_array()
        .expect("candidate list must be an array")
        .iter()
        .filter(|candidate| candidate.as_str() == Some("c5"))
        .count();
    assert_eq!(
        c5_count, 1,
        "c5 must not receive accidental duplicate weight"
    );
}
