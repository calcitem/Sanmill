// SPDX-License-Identifier: AGPL-3.0-or-later

use super::*;

const FEN: &str = "O*******/**@*****/****O*** b p p 2 7 1 8 0 0 -1 -1 -1 -1 7 42 3 ids:nodes";

#[test]
fn maps_match_flutter_reference_points() {
    assert_eq!(transform_opening_book_node(0, 1).unwrap(), 2);
    assert_eq!(transform_opening_book_node(22, 1).unwrap(), 16);
    assert_eq!(transform_opening_book_node(0, 4).unwrap(), 4);
    assert_eq!(transform_opening_book_node(0, 8).unwrap(), 16);
    assert_eq!(transform_opening_book_node(22, 15).unwrap(), 0);
}

#[test]
fn every_transform_round_trips_through_its_inverse() {
    for transform in 0..OPENING_BOOK_SYMMETRY_COUNT {
        let inverse = inverse_opening_book_transform(transform).unwrap();
        for node in 0..24 {
            let mapped = transform_opening_book_node(node, transform).unwrap();
            assert_eq!(
                transform_opening_book_node(mapped, inverse).unwrap(),
                node,
                "transform {transform} node {node}"
            );
        }
        let moved = transform_opening_book_notation("d6-d7xa4", transform).unwrap();
        assert_eq!(
            transform_opening_book_notation(&moved, inverse).unwrap(),
            "d6-d7xa4"
        );
    }
}

#[test]
fn fen_normalization_zeros_volatile_fields() {
    let normalized = normalize_opening_book_fen(FEN).unwrap();
    let fields = normalized.split_whitespace().collect::<Vec<_>>();
    assert_eq!(fields[14], "0");
    assert_eq!(fields[15], "0");
}

#[test]
fn canonical_transform_is_stable_across_the_full_orbit() {
    let (canonical, _) = canonical_opening_book_fen(FEN).unwrap();
    for transform in 0..OPENING_BOOK_SYMMETRY_COUNT {
        let image = transform_opening_book_fen(FEN, transform).unwrap();
        assert_eq!(canonical_opening_book_fen(&image).unwrap().0, canonical);
    }
}
