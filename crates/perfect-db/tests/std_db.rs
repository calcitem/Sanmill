// SPDX-License-Identifier: GPL-3.0-or-later

use perfect_db::{best_move_token, deinit, evaluate, init};

#[test]
fn std_perfect_db_init_evaluate_and_best_move() {
    let db_path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../src/ui/flutter_app/assets/databases"
    );
    assert!(
        init(db_path),
        "pd_init_std must succeed with bundled assets"
    );

    // Empty board, placing phase, white to move, 9 pieces each in hand.
    let eval = evaluate(0, 0, 9, 9, 0, false);
    assert!(
        eval.is_some(),
        "empty start position must be in the database"
    );
    let (wdl, _steps) = eval.unwrap();
    assert_eq!(wdl, 0, "standard Nine Men's Morris is a drawn game");

    let token = best_move_token(0, 0, 9, 9, 0, false);
    assert!(token.is_some(), "perfect db must return an opening move");
    assert!(!token.unwrap().is_empty());

    deinit();
}
