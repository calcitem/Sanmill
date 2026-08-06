// SPDX-License-Identifier: AGPL-3.0-or-later

use std::io::Cursor;

use serde_json::{Value, json};

use super::{
    InputRecord, MAX_EVENTS, MAX_INTEROP_REQUEST_BYTES, capabilities, dispatch, handle_line,
    identity, model, read_record, transform,
};

fn example_manifest() -> Value {
    json!({
        "boardFull": { "action": "disabled" },
        "captures": {
            "custodian": {
                "enabled": false,
                "lines": { "cross": false, "diagonal": false, "squareEdges": false },
                "maximumOwnLivePieces": null,
                "phases": ["moving"]
            },
            "intervention": {
                "enabled": false,
                "lines": { "cross": false, "diagonal": false, "squareEdges": false },
                "maximumOwnLivePieces": null,
                "phases": ["moving"]
            },
            "leap": {
                "enabled": false,
                "lines": { "cross": false, "diagonal": false, "squareEdges": false },
                "maximumOwnLivePieces": null,
                "phases": ["moving"]
            },
            "resolution": "target-commits-v1"
        },
        "draw": {
            "claimRights": { "profile": "stable-claim-rights-v1" },
            "noProgress": {
                "countedPrimaryActions": ["move"],
                "endgameLimit": 0,
                "endgamePredicate": "none",
                "evaluationBoundary": "stable-after-primary-sequence-v1",
                "mode": "automatic",
                "normalLimit": 0,
                "resetEvents": ["board-remove"]
            },
            "offers": { "expiry": "explicit-only" },
            "repetition": {
                "count": 3,
                "mode": "claim",
                "observation": "stable-primary-decision-v1",
                "projection": "repetition-observation-v1",
                "resetEvents": ["board-remove"],
                "summary": "reset-count-smt-v1"
            }
        },
        "flying": { "enabled": true, "maximumLive": 3 },
        "format": "MRS/1.0",
        "id": "example-morris",
        "mills": {
            "delayedClearBoundary": "on-enter-moving-v1",
            "lineReuse": "unlimited",
            "movingEffect": "remove-opponent-board",
            "placingEffect": "remove-opponent-board",
            "removalMultiplicity": "one-per-primary",
            "reverseReformation": "allowed",
            "targetProtection": "outside-mill-first"
        },
        "pieces": { "black": 9, "minimumLive": 3, "white": 9 },
        "placing": {
            "earlyStop": { "boundary": "after-unobligated-place-v1", "emptyPoints": 0 },
            "movementAllowed": false,
            "noLegalPrimaryAction": "loss"
        },
        "semanticState": [],
        "semanticsProfile": "mif-finite-rules-v3",
        "stalemate": { "action": "loss", "boardRemovalTargets": "adjacent-opponent" },
        "status": "fixture",
        "title": "Example Morris",
        "topology": "mill24-orthogonal-v1",
        "turn": { "initial": "b", "placingEndActivePlayer": "retain" },
        "version": 1
    })
}

fn diagnostic(result: model::Result<Value>) -> Value {
    result.expect_err("request must be rejected").into_value()
}

#[test]
fn capabilities_bind_candidate_4_m4_baseline() {
    let capability = capabilities();
    assert_eq!(
        capability["testedCorpora"],
        json!([{
            "digest": "sha256:d11317a090300f8a47f77afed647bdbd236dcdb1996c0147a81c874fa39dfd82",
            "classes": ["identity", "position", "replay", "ruleset", "transform"]
        }])
    );
    assert_eq!(
        capability["annotations"],
        json!({
            "mifCommit": "7e45d5a3fa970a535ed6a8a8ff5981aba4b9c978",
            "mifM4Commit": "40718e80d36ec9c060fc17997568d637a74e6d9f",
            "mifM4Launch": "sha256:560ef369fde248bd96d3468a4336442db1d970ede04f488821509e69925fd48e",
            "mifM4ReferenceBaseline": "sha256:29d198dbcf8221fa0235af6a72db9d6a82646b45fc653c584071821a9a4bb61b",
            "mifEnglishSpec": "sha256:330e65145ceb26fe582e58b89405d87bd73e8be200b476aef82c0ee27731d995",
            "mifChineseSpec": "sha256:9cc06abb57425e2bc2e26432b6da53abe503e9b5415ea0b4f854f19f68722cc1",
            "mifIndex": "sha256:5acbb714bed77e24eaac72fa5f24d2e54d1e17aaf568a8b60718c840281a6541",
            "mifExecutableCorpus": "sha256:350b7ff02772e820a57431e11c4e2f15a874d0779fb6e7afb01e9b16f6992741",
            "mifAdapterProtocol": "sha256:253c1d201ea1db625e0c534da445ca4ecaa0b07597dfc7dbf59fbd6adf89874f",
            "mifSmokeCorpus": "sha256:a6d292f4d19381172fbc19f89d3ee42145a6d5533d6d81fd719394e25342bb53",
            "mifDeterministicCorpus": "sha256:d11317a090300f8a47f77afed647bdbd236dcdb1996c0147a81c874fa39dfd82"
        })
    );
}

#[test]
fn candidate_manifest_and_empty_tree_identities_match() {
    let (semantic, document) = identity::manifest_identities(&example_manifest()).unwrap();
    assert_eq!(
        semantic,
        "sha256:224f7e368e322a4cc8c1225a025fb548d5b41eb096d34b7ae0543182d1aa9393"
    );
    assert_eq!(
        document,
        "sha256:62479b6f40efb8ab478bab3d2b725647213604fcd3cc9cd4c1f69357535ae257"
    );
    assert_eq!(
        identity::empty_repetition_root(),
        "sha256:e9fbf966ccdff764594a5e199e6aea0cc36034b46c8057cc3df88a088c20101a"
    );
}

#[test]
fn initial_execution_matches_frozen_candidate_vector() {
    let result = dispatch(
        "execute",
        &json!({
            "manifest": example_manifest(),
            "origin": "MFEN/1.0 mill24-state-v1 ......../......../........ b p p 9,9 - 0 0 -",
            "events": [],
            "repetitionSeed": [],
            "preOriginClaims": []
        }),
    )
    .unwrap();
    assert_eq!(
        result["final"]["decisionDigest"],
        "sha256:3e178ce2bd4583f8a24b28b648b88f2ab1575d210e6fb295faca13e8cca47b46"
    );
    assert_eq!(result["trace"].as_array().unwrap().len(), 1);
}

#[test]
fn unsupported_gameplay_profile_fails_closed() {
    let mut manifest = example_manifest();
    manifest["captures"]["leap"]["enabled"] = json!(true);
    let error = model::execute_request(&json!({
        "manifest": manifest,
        "origin": "MFEN/1.0 mill24-state-v1 ......../......../........ b p p 9,9 - 0 0 -",
        "events": [],
        "repetitionSeed": [],
        "preOriginClaims": []
    }))
    .unwrap_err();
    assert_eq!(error.into_value()["code"], "manifest-profile-unsupported");
}

#[test]
fn parser_rejects_duplicate_members_after_unescaping() {
    let response = handle_line(
        r#"{"protocol":"MIF-INTEROP/1","kind":"request","requestId":"one","requestId":"two","operation":"capabilities","payload":{}}"#,
    );
    assert_eq!(response["status"], "error");
    assert_eq!(response["diagnostics"]["errors"][0]["code"], "invalid-json");
}

#[test]
fn execute_payload_rejects_unknown_members() {
    let error = dispatch(
        "execute",
        &json!({
            "manifest": example_manifest(),
            "origin": "MFEN/1.0 mill24-state-v1 ......../......../........ b p p 9,9 - 0 0 -",
            "events": [],
            "repetitionSeed": [],
            "preOriginClaims": [],
            "unexpected": true
        }),
    )
    .unwrap_err();
    assert_eq!(error.into_value()["code"], "closed-object-mismatch");
}

#[test]
fn reference_ruleset_may_omit_document_digest() {
    let manifest = example_manifest();
    let (semantic_digest, _) = identity::manifest_identities(&manifest).unwrap();
    let origin = "MFEN/1.0 mill24-state-v1 ......../......../........ b p p 9,9 - 0 0 -";
    let execution = dispatch(
        "execute",
        &json!({
            "manifest": manifest.clone(),
            "origin": origin,
            "events": [],
            "repetitionSeed": [],
            "preOriginClaims": []
        }),
    )
    .unwrap();
    let final_snapshot = &execution["final"];
    let replay = dispatch(
        "replay",
        &json!({
            "manifest": manifest.clone(),
            "mstate": {
                "format": "MSTATE/1.0",
                "positionFormat": "MFEN/1.0",
                "stateProfile": "mill24-state-v1",
                "ruleset": {
                    "mode": "reference",
                    "id": "example-morris",
                    "version": 1,
                    "semanticDigest": semantic_digest
                },
                "origin": origin,
                "events": [],
                "current": final_snapshot["current"],
                "repetitionHistory": final_snapshot["repetitionHistory"],
                "preOriginClaims": [],
                "claims": []
            }
        }),
    )
    .unwrap();
    assert_eq!(replay["current"], origin);
}

#[test]
fn ruleset_mode_is_validated_before_caller_manifest_is_used() {
    let manifest = example_manifest();
    let (semantic_digest, _) = identity::manifest_identities(&manifest).unwrap();
    let missing_portable_manifest = json!({
        "ruleset": {
            "mode": "portable",
            "id": "example-morris",
            "version": 1,
            "semanticDigest": semantic_digest
        }
    });
    let error = model::resolve_manifest(Some(&manifest), &missing_portable_manifest).unwrap_err();
    assert_eq!(error.into_value()["code"], "manifest-missing");

    let embedded_reference_manifest = json!({
        "ruleset": {
            "mode": "reference",
            "id": "example-morris",
            "version": 1,
            "semanticDigest": semantic_digest,
            "manifest": manifest.clone()
        }
    });
    let error = model::resolve_manifest(Some(&manifest), &embedded_reference_manifest).unwrap_err();
    assert_eq!(error.into_value()["code"], "closed-object-mismatch");
}

#[test]
fn jcs_uses_utf16_member_order_and_ecmascript_numbers() {
    let utf16_order = json!({
        "\u{e000}": 2,
        "\u{10000}": 1
    });
    let expected = format!("{{\"{}\":1,\"{}\":2}}", '\u{10000}', '\u{e000}');
    assert_eq!(
        String::from_utf8(identity::jcs_bytes(&utf16_order)).unwrap(),
        expected
    );

    let numbers: Value = serde_json::from_str(
        "[333333333.33333329,1E30,4.50,2e-3,0.000000000000000000000000001,1e-6,1e-7,-0.0]",
    )
    .unwrap();
    assert_eq!(
        String::from_utf8(identity::jcs_bytes(&numbers)).unwrap(),
        "[333333333.3333333,1e+30,4.5,0.002,1e-27,0.000001,1e-7,0]"
    );
}

#[test]
fn portable_manifest_accepts_non_bmp_annotation_identity() {
    let mut manifest = example_manifest();
    manifest["annotations"] = json!({
        "\u{e000}": "bmp-private-use",
        "\u{10000}": "non-bmp"
    });
    let (semantic_digest, document_digest) = identity::manifest_identities(&manifest).unwrap();
    assert_eq!(
        document_digest,
        "sha256:bfe3b3a3fe2ddca524670130f1f79e99990d413acfb39f5e44be51ef6ac994a5"
    );
    let origin = "MFEN/1.0 mill24-state-v1 ......../......../........ b p p 9,9 - 0 0 -";
    let execution = dispatch(
        "execute",
        &json!({
            "manifest": manifest.clone(),
            "origin": origin,
            "events": [],
            "repetitionSeed": [],
            "preOriginClaims": []
        }),
    )
    .unwrap();
    let final_snapshot = &execution["final"];
    let replay = dispatch(
        "replay",
        &json!({
            "mstate": {
                "format": "MSTATE/1.0",
                "positionFormat": "MFEN/1.0",
                "stateProfile": "mill24-state-v1",
                "ruleset": {
                    "mode": "portable",
                    "id": "example-morris",
                    "version": 1,
                    "semanticDigest": semantic_digest,
                    "documentDigest": document_digest,
                    "manifest": manifest
                },
                "origin": origin,
                "events": [],
                "current": final_snapshot["current"],
                "repetitionHistory": final_snapshot["repetitionHistory"],
                "preOriginClaims": [],
                "claims": []
            }
        }),
    )
    .unwrap();
    assert_eq!(replay["current"], origin);
}

#[test]
fn process_reader_requires_lf_only_framing() {
    let mut valid = Cursor::new(b"{}\n");
    assert!(matches!(
        read_record(&mut valid).unwrap(),
        Some(InputRecord::Request(bytes)) if bytes == b"{}"
    ));

    let mut crlf = Cursor::new(b"{}\r\n");
    assert_eq!(
        read_record(&mut crlf).unwrap_err().kind(),
        std::io::ErrorKind::InvalidData
    );

    let mut missing_lf = Cursor::new(b"{}");
    assert_eq!(
        read_record(&mut missing_lf).unwrap_err().kind(),
        std::io::ErrorKind::InvalidData
    );
}

#[test]
fn request_and_semantic_resource_limits_are_enforced() {
    assert_eq!(
        capabilities()["resourceLimits"],
        json!([
            { "name": "events", "limit": 100_000 },
            { "name": "interop-request-bytes", "limit": 16_777_216 },
            { "name": "repetition-entries", "limit": 100_000 }
        ])
    );

    let mut oversized = vec![b' '; MAX_INTEROP_REQUEST_BYTES + 1];
    oversized.push(b'\n');
    assert!(matches!(
        read_record(&mut Cursor::new(oversized)).unwrap(),
        Some(InputRecord::ResourceLimit { actual }) if actual == MAX_INTEROP_REQUEST_BYTES + 1
    ));

    let error = dispatch(
        "execute",
        &json!({
            "manifest": null,
            "origin": "",
            "events": vec![Value::Null; MAX_EVENTS + 1],
            "repetitionSeed": [],
            "preOriginClaims": []
        }),
    )
    .unwrap_err()
    .into_value();
    assert_eq!(error["code"], "resource-limit");
    assert_eq!(error["resourceLimit"]["name"], "events");
}

#[test]
fn r90ccw_maps_a7_to_a1_and_round_trips() {
    let source = "MFEN/1.0 mill24-state-v1 W......./......../........ b p p 8,9 - 0 1 -";
    let rotated = transform::transform_mfen(source, "r90ccw").unwrap();
    assert!(rotated.contains("......W./......../........"));
    let restored = transform::transform_mfen(&rotated, "r90cw").unwrap();
    assert_eq!(restored, source);
}

#[test]
fn structural_d4_mpk_is_orientation_independent() {
    let prefix = concat!(
        "MPK/1.0 mill24-state-v1 example-morris@1 ",
        "sha256:224f7e368e322a4cc8c1225a025fb548d5b41eb096d34b7ae0543182d1aa9393 ",
        "structural-d4-v1 "
    );
    let first = dispatch(
        "canonicalize",
        &json!({
            "format": "MPK/1.0",
            "manifest": example_manifest(),
            "value": format!("{prefix}W....................... b p 8,9")
        }),
    )
    .unwrap();
    let rotated = dispatch(
        "canonicalize",
        &json!({
            "format": "MPK/1.0",
            "manifest": example_manifest(),
            "value": format!("{prefix}......W................. b p 8,9")
        }),
    )
    .unwrap();
    assert_eq!(first, rotated);
}

#[test]
fn mpk_binding_diagnostics_follow_candidate_3_categories() {
    let cases = [
        (
            concat!(
                "MPK/1.0 mill24-state-v1 example-morris@1 structural-d4-v1 ",
                "........................ b p 9,9"
            ),
            "integrity",
            "mpk-semantic-digest-missing",
        ),
        (
            concat!(
                "MPK/1.0 mill24-state-v1 example-morris@1 ",
                "sha256:224F7E368E322A4CC8C1225A025FB548D5B41EB096D34B7AE0543182D1AA9393 ",
                "structural-d4-v1 ........................ b p 9,9"
            ),
            "canonical",
            "non-canonical-digest",
        ),
        (
            concat!(
                "MPK/1.0 mill24-state-v1 other-morris@1 ",
                "sha256:224f7e368e322a4cc8c1225a025fb548d5b41eb096d34b7ae0543182d1aa9393 ",
                "structural-d4-v1 ........................ b p 9,9"
            ),
            "integrity",
            "manifest-conflict",
        ),
    ];
    for (value, category, code) in cases {
        let error = diagnostic(dispatch(
            "canonicalize",
            &json!({
                "format": "MPK/1.0",
                "manifest": example_manifest(),
                "value": value,
            }),
        ));
        assert_eq!(error["category"], category);
        assert_eq!(error["code"], code);
    }
}

#[test]
fn stable_moving_repetition_ignores_placing_boundaries() {
    let mut manifest = example_manifest();
    manifest["placing"]["movementAllowed"] = json!(true);
    manifest["draw"]["repetition"]["observation"] = json!("stable-moving-v1");
    let execution = model::execute_request(&json!({
        "manifest": manifest,
        "origin": "MFEN/1.0 mill24-state-v1 W......./B......./........ w p p 8,8 - 0 0 -",
        "events": [
            { "actor": "w", "from": "a7", "seq": 1, "to": "a4", "type": "move" },
            { "actor": "b", "from": "b6", "seq": 2, "to": "b4", "type": "move" },
            { "actor": "w", "from": "a4", "seq": 3, "to": "a7", "type": "move" },
            { "actor": "b", "from": "b4", "seq": 4, "to": "b6", "type": "move" }
        ],
        "repetitionSeed": [],
        "preOriginClaims": []
    }))
    .unwrap();
    assert!(
        execution["trace"]
            .as_array()
            .unwrap()
            .iter()
            .all(|snapshot| {
                snapshot["repetitionHistory"]
                    .as_array()
                    .is_some_and(Vec::is_empty)
            })
    );
    assert_eq!(
        execution["final"]["decisionState"]["repetitionSummary"]["root"],
        "sha256:e9fbf966ccdff764594a5e199e6aea0cc36034b46c8057cc3df88a088c20101a"
    );
}

#[test]
fn claim_during_obligation_is_inconsistent() {
    let error = diagnostic(model::execute_request(&json!({
        "manifest": example_manifest(),
        "origin": "MFEN/1.0 mill24-state-v1 BB....../......../W....... b p p 8,7 - 0 3 -",
        "events": [
            { "actor": "b", "at": "g7", "seq": 1, "type": "place" },
            { "actor": "b", "reason": "repetition", "seq": 2, "type": "claim-draw" }
        ],
        "repetitionSeed": [],
        "preOriginClaims": []
    })));
    assert_eq!(error["category"], "inconsistent");
    assert_eq!(error["code"], "claim-during-obligation");
    assert_eq!(error["eventSeq"], 2);
}

#[test]
fn remove_without_obligation_is_inconsistent() {
    let error = diagnostic(dispatch(
        "execute",
        &json!({
            "manifest": example_manifest(),
            "origin": "MFEN/1.0 mill24-state-v1 ......../......../........ b p p 9,9 - 0 0 -",
            "events": [{
                "actor": "b",
                "seq": 1,
                "target": { "zone": "board", "at": "a7" },
                "type": "remove"
            }],
            "repetitionSeed": [],
            "preOriginClaims": []
        }),
    ));
    assert_eq!(error["category"], "inconsistent");
    assert_eq!(error["code"], "remove-without-obligation");
    assert_eq!(error["eventSeq"], 1);
}

#[test]
fn legal_action_projection_orders_place_move_and_flying_templates() {
    let initial = dispatch(
        "project-legal-actions",
        &json!({
            "manifest": example_manifest(),
            "current": "MFEN/1.0 mill24-state-v1 ......../......../........ b p p 9,9 - 0 0 -"
        }),
    )
    .unwrap();
    let actions = initial["document"]["actions"].as_array().unwrap();
    assert_eq!(actions.len(), 24);
    assert_eq!(
        actions.first().unwrap(),
        &json!({ "actor": "b", "at": "a7", "type": "place" })
    );
    assert_eq!(
        actions.last().unwrap(),
        &json!({ "actor": "b", "at": "c4", "type": "place" })
    );

    let mut placing_manifest = example_manifest();
    placing_manifest["placing"]["movementAllowed"] = json!(true);
    let placing = dispatch(
        "project-legal-actions",
        &json!({
            "manifest": placing_manifest,
            "current": "MFEN/1.0 mill24-state-v1 W......./B......./........ w p p 8,8 - 0 0 -"
        }),
    )
    .unwrap();
    let actions = placing["document"]["actions"].as_array().unwrap();
    assert_eq!(actions.len(), 24);
    assert_eq!(
        actions[21],
        json!({ "actor": "w", "at": "c4", "type": "place" })
    );
    assert_eq!(
        actions[22],
        json!({ "actor": "w", "from": "a7", "to": "d7", "type": "move" })
    );
    assert_eq!(
        actions[23],
        json!({ "actor": "w", "from": "a7", "to": "a4", "type": "move" })
    );

    let flying = dispatch(
        "project-legal-actions",
        &json!({
            "manifest": example_manifest(),
            "current": "MFEN/1.0 mill24-state-v1 WWW...../BBB...../........ w m m 0,0 - 0 18 -"
        }),
    )
    .unwrap();
    let actions = flying["document"]["actions"].as_array().unwrap();
    assert_eq!(actions.len(), 54);
    assert_eq!(
        actions.first().unwrap(),
        &json!({ "actor": "w", "from": "a7", "to": "g4", "type": "move" })
    );
    assert_eq!(
        actions.last().unwrap(),
        &json!({ "actor": "w", "from": "g7", "to": "c4", "type": "move" })
    );
}

#[test]
fn legal_action_projection_handles_obligation_terminal_and_unstable_states() {
    let removal = dispatch(
        "project-legal-actions",
        &json!({
            "manifest": example_manifest(),
            "current": "MFEN/1.0 mill24-state-v1 BBB...../......../W....... b p r 8,6 b:mill:b:w:1:010000:w 0 4 -"
        }),
    )
    .unwrap();
    assert_eq!(
        removal["document"]["actions"],
        json!([{
            "actor": "b", "type": "remove",
            "target": { "zone": "board", "at": "c5" }
        }])
    );

    let mut full_board_manifest = example_manifest();
    full_board_manifest["pieces"] = json!({ "black": 13, "minimumLive": 3, "white": 13 });
    let terminal = dispatch(
        "project-legal-actions",
        &json!({
            "manifest": full_board_manifest.clone(),
            "current": "MFEN/1.0 mill24-state-v1 WBWBWBWB/BWBWBWBW/WBWBWBWB - o o 1,1 - 0 0 b:no-legal-primary-action"
        }),
    )
    .unwrap();
    assert_eq!(terminal["document"]["actions"], json!([]));

    let error = diagnostic(dispatch(
        "project-legal-actions",
        &json!({
            "manifest": full_board_manifest,
            "current": "MFEN/1.0 mill24-state-v1 WBWBWBWB/BWBWBWBW/WBWBWBWB w p p 1,1 - 0 0 -"
        }),
    ));
    assert_eq!(error["category"], "inconsistent");
    assert_eq!(error["code"], "unstabilized-boundary");
}

#[test]
fn origin_stabilization_projects_one_fragment() {
    let mut manifest = example_manifest();
    manifest["boardFull"]["action"] = json!("white-then-black-remove");
    manifest["pieces"] = json!({ "black": 12, "minimumLive": 3, "white": 12 });
    manifest["id"] = json!("x-origin-stabilization");
    manifest["title"] = json!("Origin stabilization executable fixture");
    let (semantic, document) = identity::manifest_identities(&manifest).unwrap();
    let origin = "MFEN/1.0 mill24-state-v1 WBWBWBWB/BWBWBWBW/WBWBWBWB w m m 0,0 - 0 24 -";
    let events = json!([
        { "actor": "w", "seq": 1, "target": { "at": "d7", "zone": "board" }, "type": "remove" },
        { "actor": "b", "seq": 2, "target": { "at": "a7", "zone": "board" }, "type": "remove" }
    ]);
    let execution = model::execute_request(&json!({
        "manifest": manifest,
        "origin": origin,
        "events": events,
        "repetitionSeed": [],
        "preOriginClaims": []
    }))
    .unwrap();
    let final_snapshot = &execution["final"];
    let mstate = json!({
        "format": "MSTATE/1.0",
        "positionFormat": "MFEN/1.0",
        "stateProfile": "mill24-state-v1",
        "ruleset": {
            "mode": "reference", "id": "x-origin-stabilization", "version": 1,
            "semanticDigest": semantic, "documentDigest": document
        },
        "origin": origin,
        "events": events,
        "current": final_snapshot["current"],
        "repetitionHistory": final_snapshot["repetitionHistory"],
        "preOriginClaims": [],
        "claims": []
    });
    let projected = model::project_logical_turns(&json!({
        "manifest": manifest,
        "mstate": mstate
    }))
    .unwrap();
    assert_eq!(
        projected["document"]["fragments"],
        json!([{
            "kind": "origin-stabilization",
            "removeEventSeqs": [1, 2],
            "status": "complete"
        }])
    );
    assert_eq!(
        projected["document"]["sourceResumptionDigest"],
        "sha256:846a5d9523b1a959b86f8c29fb2b53536c54b9babdffcbee2046899d21c6acc8"
    );
}
