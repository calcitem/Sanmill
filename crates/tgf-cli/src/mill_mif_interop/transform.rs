// SPDX-License-Identifier: AGPL-3.0-or-later

use serde_json::{Value, json};

use super::identity;
use super::model::{
    COORDS, Diagnostic, Manifest, Result, State, coord_index, replay_document, resolve_manifest,
    verify_ruleset_envelope,
};

const TRANSFORMS: [&str; 8] = [
    "i",
    "r90ccw",
    "r180",
    "r90cw",
    "mirror-v",
    "mirror-h",
    "mirror-main",
    "mirror-anti",
];

pub(super) fn transform_request(payload: &Value) -> Result<Value> {
    let kind = text(payload, "kind")?;
    let transform = text(payload, "transform")?;
    if !TRANSFORMS.contains(&transform) {
        return Err(Diagnostic::new(
            "unsupported",
            "transform-unsupported",
            format!("transform `{transform}` is unsupported"),
        ));
    }
    if payload
        .get("requireEquivalence")
        .and_then(Value::as_bool)
        .unwrap_or(false)
        && payload.get("invariance").is_none()
    {
        return Err(Diagnostic::new(
            "ineligible",
            "transform-invariance-undeclared",
            "coordinate conversion has no exact invariance declaration",
        ));
    }
    let document = payload.get("document").ok_or_else(|| {
        Diagnostic::new("syntax", "document-missing", "transform requires document")
    })?;
    match kind {
        "mstate" => transform_mstate(payload, document, transform),
        "mifpos" => transform_mifpos(payload, document, transform),
        "decision-state" => transform_decision(payload, document, transform),
        _ => Err(Diagnostic::new(
            "unsupported",
            "transform-kind-unsupported",
            format!("transform kind `{kind}` is unsupported"),
        )),
    }
}

fn transform_mstate(payload: &Value, document: &Value, transform: &str) -> Result<Value> {
    let manifest_value = resolve_manifest(payload.get("manifest"), document)?;
    let manifest = Manifest::new(manifest_value.clone())?;
    verify_ruleset_envelope(document, &manifest)?;
    verify_equivalence(payload, &manifest, transform)?;
    let mut transformed = document.clone();
    transformed["origin"] = json!(transform_mfen(text(document, "origin")?, transform)?);
    transformed["current"] = json!(transform_mfen(text(document, "current")?, transform)?);
    transformed["events"] = Value::Array(
        array(document, "events")?
            .iter()
            .map(|event| transform_event(event, transform))
            .collect::<Result<_>>()?,
    );
    transformed["repetitionHistory"] = Value::Array(
        array(document, "repetitionHistory")?
            .iter()
            .map(|entry| transform_history_entry(entry, transform))
            .collect::<Result<_>>()?,
    );
    let replay = replay_document(&transformed, manifest_value)?;
    Ok(json!({
        "document": transformed,
        "decisionState": replay["decisionState"],
        "decisionDigest": replay["decisionDigest"],
        "resumptionState": replay["resumptionState"],
        "resumptionDigest": replay["resumptionDigest"],
    }))
}

fn transform_mifpos(payload: &Value, document: &Value, transform: &str) -> Result<Value> {
    let manifest_value = resolve_manifest(payload.get("manifest"), document)?;
    let manifest = Manifest::new(manifest_value)?;
    verify_ruleset_envelope(document, &manifest)?;
    verify_equivalence(payload, &manifest, transform)?;
    let mut transformed = document.clone();
    transformed["position"] = json!(transform_mfen(text(document, "position")?, transform)?);
    Ok(json!({ "document": transformed }))
}

fn transform_decision(payload: &Value, document: &Value, transform: &str) -> Result<Value> {
    let manifest_value = payload.get("manifest").cloned().ok_or_else(|| {
        Diagnostic::new(
            "integrity",
            "manifest-missing",
            "decision transform requires caller ruleset context",
        )
    })?;
    let manifest = Manifest::new(manifest_value)?;
    verify_equivalence(payload, &manifest, transform)?;
    if document
        .pointer("/repetitionSummary/root")
        .and_then(Value::as_str)
        .is_some()
        && payload.get("repetitionHistory").is_none()
    {
        return Err(Diagnostic::new(
            "ineligible",
            "insufficient-transform-history",
            "decision repetition root requires its materialized active history",
        ));
    }
    if document.get("semanticDigest").and_then(Value::as_str) != Some(&manifest.semantic_digest) {
        return Err(Diagnostic::new(
            "integrity",
            "semantic-digest-mismatch",
            "decision semantic digest does not match manifest",
        ));
    }
    let mut transformed = document.clone();
    transformed["board"] = json!(transform_board(text(document, "board")?, transform)?);
    transformed["obligations"] = json!(transform_obligations(
        text(document, "obligations")?,
        transform
    )?);
    transform_semantic(&mut transformed["semantic"], transform)?;
    if document
        .get("repetitionSummary")
        .is_some_and(|value| !value.is_null())
    {
        let source_history = array(payload, "repetitionHistory")?;
        let threshold = manifest
            .value
            .pointer("/draw/repetition/count")
            .and_then(Value::as_u64)
            .unwrap_or(0);
        let supplied_root = document
            .pointer("/repetitionSummary/root")
            .and_then(Value::as_str)
            .unwrap_or("");
        if identity::repetition_root(source_history, threshold)? != supplied_root {
            return Err(Diagnostic::new(
                "integrity",
                "repetition-summary-mismatch",
                "decision repetition root does not match materialized history",
            ));
        }
        let history = source_history
            .iter()
            .map(|entry| transform_history_entry(entry, transform))
            .collect::<Result<Vec<_>>>()?;
        transformed["repetitionSummary"] = json!({
            "profile": "reset-count-smt-v1",
            "root": identity::repetition_root(&history, threshold)?,
        });
    }
    Ok(json!({ "document": transformed }))
}

fn verify_equivalence(payload: &Value, manifest: &Manifest, transform: &str) -> Result<()> {
    if !payload
        .get("requireEquivalence")
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        return Ok(());
    }
    let declaration = payload
        .get("invariance")
        .and_then(Value::as_object)
        .ok_or_else(|| {
            Diagnostic::new(
                "ineligible",
                "transform-invariance-undeclared",
                "coordinate conversion has no exact invariance declaration",
            )
        })?;
    let declared = declaration.get("format").and_then(Value::as_str) == Some("MIFINV/1.0")
        && declaration.get("profile").and_then(Value::as_str) == Some("transform-invariance-v1")
        && declaration.get("semanticDigest").and_then(Value::as_str)
            == Some(&manifest.semantic_digest)
        && declaration.get("stateProfile").and_then(Value::as_str) == Some("mill24-state-v1")
        && declaration.get("transformProfile").and_then(Value::as_str)
            == Some("mill24-full-state-v1")
        && declaration
            .get("transforms")
            .and_then(Value::as_array)
            .is_some_and(|transforms| {
                transforms
                    .iter()
                    .any(|candidate| candidate.as_str() == Some(transform))
            });
    if !declared {
        return Err(Diagnostic::new(
            "ineligible",
            "transform-invariance-undeclared",
            "invariance declaration does not authorize this semantic transform",
        ));
    }
    if declaration
        .get("extensionTreatments")
        .and_then(Value::as_array)
        .is_none_or(|treatments| !treatments.is_empty())
    {
        return Err(Diagnostic::new(
            "unsupported",
            "transform-extension-unsupported",
            "invariance extension treatments are not implemented",
        ));
    }
    let expected = declaration
        .get("documentDigest")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            Diagnostic::new(
                "integrity",
                "document-digest-missing",
                "invariance declaration requires documentDigest",
            )
        })?;
    let mut digest_input = declaration.clone();
    digest_input.remove("documentDigest");
    if identity::digest_json(&Value::Object(digest_input)) != expected {
        return Err(Diagnostic::new(
            "integrity",
            "document-digest-mismatch",
            "invariance declaration digest does not match its content",
        ));
    }
    Ok(())
}

pub(super) fn transform_mfen(value: &str, transform: &str) -> Result<String> {
    let mut state = State::parse(value)?;
    let source = state.board;
    let mut board = ['.'; 24];
    for (index, piece) in source.into_iter().enumerate() {
        board[transform_index(index, transform)?] = piece;
    }
    state.board = board;
    state.obligations = transform_obligations(&state.obligations, transform)?;
    state.extensions = state
        .extensions
        .iter()
        .map(|extension| transform_extension(extension, transform))
        .collect::<Result<_>>()?;
    Ok(state.canonical())
}

fn transform_board(value: &str, transform: &str) -> Result<String> {
    let compact = value.replace('/', "");
    if compact.len() != 24 {
        return Err(Diagnostic::new(
            "syntax",
            "board-invalid",
            "board field does not contain 24 points",
        ));
    }
    let mut output = ['.'; 24];
    for (index, piece) in compact.chars().enumerate() {
        output[transform_index(index, transform)?] = piece;
    }
    let text: String = output.iter().collect();
    Ok(format!(
        "{}/{}/{}",
        &text[0..8],
        &text[8..16],
        &text[16..24]
    ))
}

pub(super) fn transform_mpk_board(value: &str, transform: &str) -> Result<String> {
    let transformed = transform_board(value, transform)?;
    Ok(transformed.replace('/', ""))
}

fn transform_event(event: &Value, transform: &str) -> Result<Value> {
    let mut transformed = event.clone();
    for name in ["at", "from", "to"] {
        if let Some(coord) = event.get(name).and_then(Value::as_str) {
            transformed[name] = json!(transform_coord(coord, transform)?);
        }
    }
    if let Some(coord) = event.pointer("/target/at").and_then(Value::as_str) {
        transformed["target"]["at"] = json!(transform_coord(coord, transform)?);
    }
    if let Some(line) = event.get("interventionLine").and_then(Value::as_u64) {
        transformed["interventionLine"] = json!(transform_line(line as usize, transform)?);
    }
    Ok(transformed)
}

fn transform_history_entry(entry: &Value, transform: &str) -> Result<Value> {
    let mut transformed = entry.clone();
    let board = entry
        .pointer("/key/board")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            Diagnostic::new(
                "syntax",
                "repetition-key-invalid",
                "repetition entry requires key.board",
            )
        })?;
    transformed["key"]["board"] = json!(transform_board(board, transform)?);
    transform_semantic(&mut transformed["key"]["semantic"], transform)?;
    Ok(transformed)
}

fn transform_semantic(semantic: &mut Value, transform: &str) -> Result<()> {
    let Some(object) = semantic.as_object_mut() else {
        return Err(Diagnostic::new(
            "syntax",
            "semantic-state-invalid",
            "semantic state must be an object",
        ));
    };
    if let Some(value) = object.get_mut("lm")
        && let Some(text) = value.as_str()
    {
        *value = json!(transform_lm(text, transform)?);
    }
    if object.contains_key("ul") {
        let value = object["ul"]
            .as_str()
            .ok_or_else(|| Diagnostic::new("syntax", "used-lines-invalid", "ul must be text"))?;
        object.insert("ul".into(), json!(transform_ul(value, transform)?));
    }
    Ok(())
}

fn transform_extension(extension: &str, transform: &str) -> Result<String> {
    let Some((key, value)) = extension.split_once('=') else {
        return Err(Diagnostic::new(
            "syntax",
            "extension-invalid",
            "MFEN extension requires key=value",
        ));
    };
    match key {
        "lm" => Ok(format!("lm={}", transform_lm(value, transform)?)),
        "ul" => Ok(format!("ul={}", transform_ul(value, transform)?)),
        "pc" => Ok(extension.into()),
        _ => Err(Diagnostic::new(
            "unsupported",
            "transform-extension-unsupported",
            format!("coordinate treatment for extension `{key}` is unknown"),
        )),
    }
}

fn transform_lm(value: &str, transform: &str) -> Result<String> {
    value
        .split(';')
        .map(|player| {
            player
                .split(',')
                .map(|coord| {
                    if coord == "-" {
                        Ok("-".into())
                    } else {
                        transform_coord(coord, transform)
                    }
                })
                .collect::<Result<Vec<_>>>()
                .map(|coords| coords.join(","))
        })
        .collect::<Result<Vec<_>>>()
        .map(|players| players.join(";"))
}

fn transform_ul(value: &str, transform: &str) -> Result<String> {
    value
        .split(',')
        .map(|bits| {
            let mask = u32::from_str_radix(bits, 16).map_err(|_| {
                Diagnostic::new("syntax", "used-lines-invalid", "invalid ul bit set")
            })?;
            let mut transformed = 0_u32;
            for line in 0..16 {
                if mask & (1 << line) != 0 {
                    transformed |= 1 << transform_line(line, transform)?;
                }
            }
            Ok(format!("{:04x}", transformed))
        })
        .collect::<Result<Vec<_>>>()
        .map(|players| players.join(","))
}

fn transform_obligations(value: &str, transform: &str) -> Result<String> {
    if value == "-" {
        return Ok(value.into());
    }
    value
        .split('|')
        .map(|branch| {
            branch
                .split(';')
                .map(|obligation| {
                    let mut fields: Vec<_> = obligation.split(':').map(str::to_string).collect();
                    if fields.len() != 7 {
                        return Err(Diagnostic::new(
                            "syntax",
                            "obligation-invalid",
                            "obligation requires seven fields",
                        ));
                    }
                    if fields[2] == "b" && fields[5] != "~" {
                        let mask = u32::from_str_radix(&fields[5], 16).map_err(|_| {
                            Diagnostic::new(
                                "syntax",
                                "obligation-invalid",
                                "invalid obligation target bit set",
                            )
                        })?;
                        fields[5] = format!("{:06x}", transform_mask(mask, transform)?);
                    }
                    Ok(fields.join(":"))
                })
                .collect::<Result<Vec<_>>>()
                .map(|items| items.join(";"))
        })
        .collect::<Result<Vec<_>>>()
        .map(|branches| branches.join("|"))
}

fn transform_mask(mask: u32, transform: &str) -> Result<u32> {
    let mut output = 0;
    for index in 0..24 {
        if mask & (1 << index) != 0 {
            output |= 1 << transform_index(index, transform)?;
        }
    }
    Ok(output)
}

fn transform_coord(coord: &str, transform: &str) -> Result<String> {
    let index = coord_index(coord).ok_or_else(|| {
        Diagnostic::new(
            "syntax",
            "coordinate-invalid",
            format!("coordinate `{coord}` is invalid"),
        )
    })?;
    Ok(COORDS[transform_index(index, transform)?].into())
}

fn transform_index(index: usize, transform: &str) -> Result<usize> {
    let coord = COORDS[index].as_bytes();
    let x = coord[0] as i8 - b'd' as i8;
    let y = coord[1] as i8 - b'4' as i8;
    let (x, y) = match transform {
        "i" => (x, y),
        "r90ccw" => (-y, x),
        "r180" => (-x, -y),
        "r90cw" => (y, -x),
        "mirror-v" => (-x, y),
        "mirror-h" => (x, -y),
        "mirror-main" => (y, x),
        "mirror-anti" => (-y, -x),
        _ => {
            return Err(Diagnostic::new(
                "unsupported",
                "transform-unsupported",
                "unknown D4 transform",
            ));
        }
    };
    let transformed = format!(
        "{}{}",
        (b'd' as i8 + x) as u8 as char,
        (b'4' as i8 + y) as u8 as char
    );
    coord_index(&transformed).ok_or_else(|| {
        Diagnostic::new(
            "inconsistent",
            "transform-coordinate-invalid",
            "D4 transform left the mill24 topology",
        )
    })
}

fn transform_line(line: usize, transform: &str) -> Result<usize> {
    const LINES: [[usize; 3]; 16] = [
        [0, 1, 2],
        [2, 3, 4],
        [4, 5, 6],
        [6, 7, 0],
        [8, 9, 10],
        [10, 11, 12],
        [12, 13, 14],
        [14, 15, 8],
        [16, 17, 18],
        [18, 19, 20],
        [20, 21, 22],
        [22, 23, 16],
        [1, 9, 17],
        [3, 11, 19],
        [5, 13, 21],
        [7, 15, 23],
    ];
    let source = LINES
        .get(line)
        .ok_or_else(|| Diagnostic::new("syntax", "line-id-invalid", "line ID is outside 0..15"))?;
    let mut points = source
        .iter()
        .map(|index| transform_index(*index, transform))
        .collect::<Result<Vec<_>>>()?;
    points.sort_unstable();
    LINES
        .iter()
        .position(|candidate| {
            let mut candidate = candidate.to_vec();
            candidate.sort_unstable();
            candidate == points
        })
        .ok_or_else(|| {
            Diagnostic::new(
                "inconsistent",
                "line-transform-invalid",
                "D4 transform did not map a line to a line",
            )
        })
}

fn text<'a>(value: &'a Value, member: &str) -> Result<&'a str> {
    value.get(member).and_then(Value::as_str).ok_or_else(|| {
        Diagnostic::new(
            "syntax",
            "text-member-missing",
            format!("member `{member}` must be text"),
        )
    })
}

fn array<'a>(value: &'a Value, member: &str) -> Result<&'a [Value]> {
    value
        .get(member)
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .ok_or_else(|| {
            Diagnostic::new(
                "syntax",
                "array-member-missing",
                format!("member `{member}` must be an array"),
            )
        })
}
