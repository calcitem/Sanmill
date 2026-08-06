// SPDX-License-Identifier: AGPL-3.0-or-later

use std::collections::{BTreeMap, HashMap};

use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};

use super::model::{Diagnostic, Result};

type NodePair = (Option<[u8; 32]>, Option<[u8; 32]>);

pub(super) fn digest_bytes(bytes: &[u8]) -> String {
    format!("sha256:{}", hex(&Sha256::digest(bytes)))
}

pub(super) fn digest_json(value: &Value) -> String {
    digest_bytes(&jcs_bytes(value))
}

pub(super) fn jcs_bytes(value: &Value) -> Vec<u8> {
    serde_json_canonicalizer::to_vec(value).expect("validated MIF values are RFC 8785 serializable")
}

pub(super) fn manifest_identities(manifest: &Value) -> Result<(String, String)> {
    let object = manifest.as_object().ok_or_else(|| {
        Diagnostic::new("syntax", "manifest-invalid", "manifest must be an object")
    })?;
    if object.get("format").and_then(Value::as_str) != Some("MRS/1.0")
        || object.get("semanticsProfile").and_then(Value::as_str) != Some("mif-finite-rules-v3")
        || object.get("topology").and_then(Value::as_str) != Some("mill24-orthogonal-v1")
    {
        return Err(Diagnostic::new(
            "unsupported",
            "manifest-profile-unsupported",
            "adapter supports MRS/1.0 mif-finite-rules-v3 on mill24-orthogonal-v1",
        ));
    }
    let semantic = semantic_projection(object)?;
    Ok((digest_json(&semantic), digest_json(manifest)))
}

fn semantic_projection(manifest: &Map<String, Value>) -> Result<Value> {
    let required = [
        "semanticsProfile",
        "topology",
        "pieces",
        "turn",
        "flying",
        "placing",
        "mills",
        "captures",
        "boardFull",
        "stalemate",
        "draw",
        "semanticState",
    ];
    let mut projection = Map::new();
    projection.insert("profile".into(), json!("mrs-semantic-v1"));
    for name in required {
        projection.insert(
            name.into(),
            manifest.get(name).cloned().ok_or_else(|| {
                Diagnostic::new(
                    "syntax",
                    "manifest-member-missing",
                    format!("manifest member `{name}` is required"),
                )
            })?,
        );
    }

    if projection["flying"].get("enabled").and_then(Value::as_bool) == Some(false) {
        projection.insert("flying".into(), json!({ "enabled": false }));
    }

    if let Some(placing) = projection.get_mut("placing").and_then(Value::as_object_mut)
        && placing
            .get("earlyStop")
            .and_then(|value| value.get("emptyPoints"))
            .and_then(Value::as_u64)
            == Some(0)
    {
        placing.insert("earlyStop".into(), json!({ "emptyPoints": 0 }));
    }

    if let Some(captures) = projection
        .get_mut("captures")
        .and_then(Value::as_object_mut)
    {
        for name in ["custodian", "intervention", "leap"] {
            if captures
                .get(name)
                .and_then(|value| value.get("enabled"))
                .and_then(Value::as_bool)
                == Some(false)
            {
                captures.insert(name.into(), json!({ "enabled": false }));
            }
        }
    }

    if let Some(draw) = projection.get_mut("draw").and_then(Value::as_object_mut) {
        if let Some(no_progress) = draw.get("noProgress")
            && no_progress.get("normalLimit").and_then(Value::as_u64) == Some(0)
            && no_progress.get("endgameLimit").and_then(Value::as_u64) == Some(0)
        {
            draw.insert("noProgress".into(), json!({ "enabled": false }));
        }
        if draw
            .get("repetition")
            .and_then(|value| value.get("count"))
            .and_then(Value::as_u64)
            == Some(0)
        {
            draw.insert("repetition".into(), json!({ "count": 0 }));
        }
    }

    if let Some(extensions) = manifest.get("extensions").and_then(Value::as_array)
        && !extensions.is_empty()
    {
        return Err(Diagnostic::new(
            "unsupported",
            "semantic-extension-unsupported",
            "semantic MRS extensions are not implemented by this adapter",
        ));
    }
    Ok(Value::Object(projection))
}

pub(super) fn repetition_root(history: &[Value], threshold: u64) -> Result<String> {
    let empty = empty_hashes();
    let mut counts: BTreeMap<[u8; 32], u64> = BTreeMap::new();
    let mut observations: BTreeMap<[u8; 32], Vec<u8>> = BTreeMap::new();
    for entry in history {
        let key = entry.get("key").ok_or_else(|| {
            Diagnostic::new(
                "syntax",
                "repetition-key-missing",
                "repetition history entry requires key",
            )
        })?;
        let bytes = jcs_bytes(key);
        let digest: [u8; 32] = Sha256::digest(&bytes).into();
        if let Some(prior) = observations.insert(digest, bytes.clone())
            && prior != bytes
        {
            return Err(Diagnostic::new(
                "integrity",
                "observation-digest-collision",
                "different repetition observations share one digest",
            ));
        }
        *counts.entry(digest).or_default() += 1;
    }

    let mut nodes: BTreeMap<[u8; 32], [u8; 32]> = BTreeMap::new();
    for (path, count) in counts {
        let mut input = Vec::with_capacity(41);
        input.push(0x01);
        input.extend_from_slice(&path);
        input.extend_from_slice(&count.min(threshold).to_be_bytes());
        nodes.insert(path, Sha256::digest(&input).into());
    }

    for (height, empty_at_height) in empty.iter().take(256).enumerate() {
        let bit_index = 255 - height;
        let mut parents: HashMap<[u8; 32], NodePair> = HashMap::new();
        for (path, hash) in nodes {
            let byte = bit_index / 8;
            let mask = 1 << (7 - (bit_index % 8));
            let right = path[byte] & mask != 0;
            let mut parent = path;
            parent[byte] &= !mask;
            let pair = parents.entry(parent).or_default();
            if right {
                pair.1 = Some(hash);
            } else {
                pair.0 = Some(hash);
            }
        }
        nodes = parents
            .into_iter()
            .map(|(path, (left, right))| {
                let left = left.unwrap_or(*empty_at_height);
                let right = right.unwrap_or(*empty_at_height);
                let mut input = Vec::with_capacity(65);
                input.push(0x02);
                input.extend_from_slice(&left);
                input.extend_from_slice(&right);
                (path, Sha256::digest(&input).into())
            })
            .collect();
    }
    let root = nodes.values().next().copied().unwrap_or(empty[256]);
    Ok(format!("sha256:{}", hex(&root)))
}

fn empty_hashes() -> Vec<[u8; 32]> {
    let mut values: Vec<[u8; 32]> = Vec::with_capacity(257);
    values.push(Sha256::digest([0_u8]).into());
    for height in 0..256 {
        let mut input = Vec::with_capacity(65);
        input.push(0x02);
        input.extend_from_slice(&values[height]);
        input.extend_from_slice(&values[height]);
        values.push(Sha256::digest(&input).into());
    }
    values
}

#[cfg(test)]
pub(super) fn empty_repetition_root() -> String {
    format!("sha256:{}", hex(&empty_hashes()[256]))
}

fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        output.push(DIGITS[(byte >> 4) as usize] as char);
        output.push(DIGITS[(byte & 0x0f) as usize] as char);
    }
    output
}
