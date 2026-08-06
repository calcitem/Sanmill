// SPDX-License-Identifier: AGPL-3.0-or-later
//! Independent MIF-INTEROP/1 adapter.
//!
//! This module is intentionally implemented from the published MIF 1.0 wire
//! contract. It does not link to, invoke, or copy gameplay code from the MIF
//! Python reference runner.

mod identity;
mod legal_actions;
mod model;
mod transform;

use std::io::{self, BufRead, Write};

use serde::de::{Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};
use serde_json::{Value, json};

const PROTOCOL: &str = "MIF-INTEROP/1";
const MAX_EXACT_INTEGER: u64 = 9_007_199_254_740_991;
const MAX_INTEROP_REQUEST_BYTES: usize = 16_777_216;
const MAX_EVENTS: usize = 100_000;
const MAX_REPETITION_ENTRIES: usize = 100_000;

pub(crate) fn run() {
    let stdin = io::stdin();
    let stdout = io::stdout();
    if let Err(error) = run_loop(stdin.lock(), stdout.lock()) {
        eprintln!("mif-interop: {error}");
        std::process::exit(2);
    }
}

#[derive(Debug)]
enum InputRecord {
    Request(Vec<u8>),
    ResourceLimit { actual: usize },
}

fn run_loop<R: BufRead, W: Write>(mut input: R, mut output: W) -> io::Result<()> {
    while let Some(record) = read_record(&mut input)? {
        let response = match record {
            InputRecord::Request(bytes) => match std::str::from_utf8(&bytes) {
                Ok(line) => handle_line(line),
                Err(error) => error_response(
                    "invalid-request",
                    "capabilities",
                    model::Diagnostic::new("syntax", "invalid-json", error.to_string()),
                ),
            },
            InputRecord::ResourceLimit { actual } => error_response(
                "invalid-request",
                "capabilities",
                model::Diagnostic::new(
                    "resource",
                    "resource-limit",
                    "interop-request-bytes resource limit exceeded",
                )
                .with_resource_limit(
                    "interop-request-bytes",
                    MAX_INTEROP_REQUEST_BYTES,
                    actual,
                ),
            ),
        };
        serde_json::to_writer(&mut output, &response)?;
        output.write_all(b"\n")?;
        output.flush()?;
    }
    Ok(())
}

fn read_record<R: BufRead>(input: &mut R) -> io::Result<Option<InputRecord>> {
    let mut record = Vec::new();
    let mut actual = 0_usize;
    loop {
        let (consumed, found_lf) = {
            let available = input.fill_buf()?;
            if available.is_empty() {
                if actual == 0 {
                    return Ok(None);
                }
                if actual > MAX_INTEROP_REQUEST_BYTES {
                    return Ok(Some(InputRecord::ResourceLimit { actual }));
                }
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "input must be LF-only terminated",
                ));
            }
            let lf = available.iter().position(|byte| *byte == b'\n');
            let content_len = lf.unwrap_or(available.len());
            actual = actual.saturating_add(content_len);
            if actual <= MAX_INTEROP_REQUEST_BYTES {
                record.extend_from_slice(&available[..content_len]);
            }
            (content_len + usize::from(lf.is_some()), lf.is_some())
        };
        input.consume(consumed);

        if !found_lf {
            continue;
        }
        if actual > MAX_INTEROP_REQUEST_BYTES {
            return Ok(Some(InputRecord::ResourceLimit { actual }));
        }
        if record.contains(&b'\r') {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "input must be LF-only terminated",
            ));
        }
        if record.starts_with(&[0xef, 0xbb, 0xbf]) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "input must be UTF-8 without BOM",
            ));
        }
        return Ok(Some(InputRecord::Request(record)));
    }
}

fn handle_line(line: &str) -> Value {
    let request = match serde_json::from_str::<StrictValue>(line) {
        Ok(value) => value.0,
        Err(error) => {
            return error_response(
                "invalid-request",
                "unknown",
                model::Diagnostic::new("syntax", "invalid-json", error.to_string()),
            );
        }
    };
    let request_id = request
        .get("requestId")
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    let operation = request
        .get("operation")
        .and_then(Value::as_str)
        .unwrap_or("capabilities");
    let exact_members = request.as_object().is_some_and(|object| {
        object.len() == 5
            && ["protocol", "kind", "requestId", "operation", "payload"]
                .iter()
                .all(|member| object.contains_key(*member))
    });
    if !exact_members
        || request.get("protocol").and_then(Value::as_str) != Some(PROTOCOL)
        || request.get("kind").and_then(Value::as_str) != Some("request")
        || !request.get("payload").is_some_and(Value::is_object)
    {
        return error_response(
            request_id,
            operation,
            model::Diagnostic::new(
                "syntax",
                "invalid-envelope",
                "request envelope does not conform to MIF-INTEROP/1",
            ),
        );
    }
    let payload = request.get("payload").cloned().unwrap_or_else(|| json!({}));
    match dispatch(operation, &payload) {
        Ok(result) => json!({
            "protocol": PROTOCOL,
            "kind": "response",
            "requestId": request_id,
            "operation": operation,
            "status": "ok",
            "result": result,
        }),
        Err(error) => error_response(request_id, operation, error),
    }
}

struct StrictValue(Value);

impl<'de> Deserialize<'de> for StrictValue {
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        deserializer.deserialize_any(StrictVisitor)
    }
}

struct StrictVisitor;

impl<'de> Visitor<'de> for StrictVisitor {
    type Value = StrictValue;

    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("an I-JSON value without duplicate object members")
    }

    fn visit_bool<E>(self, value: bool) -> std::result::Result<Self::Value, E> {
        Ok(StrictValue(Value::Bool(value)))
    }

    fn visit_i64<E>(self, value: i64) -> std::result::Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        if value.unsigned_abs() > MAX_EXACT_INTEGER {
            return Err(serde::de::Error::custom(
                "integer exceeds the I-JSON exact range",
            ));
        }
        Ok(StrictValue(Value::Number(value.into())))
    }

    fn visit_u64<E>(self, value: u64) -> std::result::Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        if value > MAX_EXACT_INTEGER {
            return Err(E::custom("integer exceeds the I-JSON exact range"));
        }
        Ok(StrictValue(Value::Number(value.into())))
    }

    fn visit_f64<E>(self, value: f64) -> std::result::Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        serde_json::Number::from_f64(value)
            .map(Value::Number)
            .map(StrictValue)
            .ok_or_else(|| E::custom("non-finite JSON number"))
    }

    fn visit_str<E>(self, value: &str) -> std::result::Result<Self::Value, E> {
        Ok(StrictValue(Value::String(value.into())))
    }

    fn visit_string<E>(self, value: String) -> std::result::Result<Self::Value, E> {
        Ok(StrictValue(Value::String(value)))
    }

    fn visit_none<E>(self) -> std::result::Result<Self::Value, E> {
        Ok(StrictValue(Value::Null))
    }

    fn visit_unit<E>(self) -> std::result::Result<Self::Value, E> {
        Ok(StrictValue(Value::Null))
    }

    fn visit_seq<A>(self, mut sequence: A) -> std::result::Result<Self::Value, A::Error>
    where
        A: SeqAccess<'de>,
    {
        let mut values = Vec::new();
        while let Some(value) = sequence.next_element::<StrictValue>()? {
            values.push(value.0);
        }
        Ok(StrictValue(Value::Array(values)))
    }

    fn visit_map<A>(self, mut object: A) -> std::result::Result<Self::Value, A::Error>
    where
        A: MapAccess<'de>,
    {
        let mut values = serde_json::Map::new();
        while let Some(key) = object.next_key::<String>()? {
            if values.contains_key(&key) {
                return Err(serde::de::Error::custom(format!(
                    "duplicate JSON member `{key}` after unescaping"
                )));
            }
            values.insert(key, object.next_value::<StrictValue>()?.0);
        }
        Ok(StrictValue(Value::Object(values)))
    }
}

fn dispatch(operation: &str, payload: &Value) -> model::Result<Value> {
    validate_payload_members(operation, payload)?;
    validate_payload_resources(operation, payload)?;
    match operation {
        "capabilities" => Ok(json!({ "capabilities": capabilities() })),
        "canonicalize" => model::canonicalize(payload),
        "execute" => model::execute_request(payload),
        "project-legal-actions" => legal_actions::project(payload),
        "replay" => model::replay_request(payload),
        "transform" => transform::transform_request(payload),
        "project-logical-turns" => model::project_logical_turns(payload),
        _ => Err(model::Diagnostic::new(
            "unsupported",
            "operation-unsupported",
            format!("unsupported interop operation `{operation}`"),
        )),
    }
}

fn validate_payload_members(operation: &str, payload: &Value) -> model::Result<()> {
    let Some(object) = payload.as_object() else {
        return Err(model::Diagnostic::new(
            "syntax",
            "closed-object-mismatch",
            format!("{operation} payload must be an object"),
        ));
    };
    let (required, optional): (&[&str], &[&str]) = match operation {
        "capabilities" => (&[], &[]),
        "canonicalize" => (&["format", "value"], &["manifest"]),
        "execute" => (
            &[
                "manifest",
                "origin",
                "events",
                "repetitionSeed",
                "preOriginClaims",
            ],
            &[],
        ),
        "replay" | "project-logical-turns" => (&["mstate"], &["manifest"]),
        "project-legal-actions" => (&["manifest", "current"], &[]),
        "transform" => (
            &[
                "kind",
                "document",
                "transform",
                "verifyReplay",
                "requireEquivalence",
            ],
            &["manifest", "repetitionHistory", "invariance"],
        ),
        _ => return Ok(()),
    };
    if let Some(member) = object
        .keys()
        .find(|member| !required.contains(&member.as_str()) && !optional.contains(&member.as_str()))
    {
        return Err(model::Diagnostic::new(
            "syntax",
            "closed-object-mismatch",
            format!("{operation} payload contains unknown member `{member}`"),
        ));
    }
    if let Some(member) = required
        .iter()
        .find(|member| !object.contains_key(**member))
    {
        return Err(model::Diagnostic::new(
            "syntax",
            "closed-object-mismatch",
            format!("{operation} payload lacks required member `{member}`"),
        ));
    }
    Ok(())
}

fn validate_payload_resources(operation: &str, payload: &Value) -> model::Result<()> {
    match operation {
        "execute" => {
            enforce_array_limit(payload.get("events"), "events", MAX_EVENTS)?;
            enforce_array_limit(
                payload.get("repetitionSeed"),
                "repetition-entries",
                MAX_REPETITION_ENTRIES,
            )?;
        }
        "replay" | "project-logical-turns" => {
            enforce_mstate_limits(payload.get("mstate"))?;
        }
        "transform" => {
            if payload.get("kind").and_then(Value::as_str) == Some("mstate") {
                enforce_mstate_limits(payload.get("document"))?;
            }
            enforce_array_limit(
                payload.get("repetitionHistory"),
                "repetition-entries",
                MAX_REPETITION_ENTRIES,
            )?;
        }
        _ => {}
    }
    Ok(())
}

fn enforce_mstate_limits(value: Option<&Value>) -> model::Result<()> {
    let Some(document) = value else {
        return Ok(());
    };
    enforce_array_limit(document.get("events"), "events", MAX_EVENTS)?;
    enforce_array_limit(
        document.get("repetitionHistory"),
        "repetition-entries",
        MAX_REPETITION_ENTRIES,
    )
}

fn enforce_array_limit(
    value: Option<&Value>,
    name: &'static str,
    limit: usize,
) -> model::Result<()> {
    if let Some(actual) = value.and_then(Value::as_array).map(Vec::len) {
        model::enforce_resource_limit(name, actual, limit)?;
    }
    Ok(())
}

fn error_response(request_id: &str, operation: &str, error: model::Diagnostic) -> Value {
    json!({
        "protocol": PROTOCOL,
        "kind": "response",
        "requestId": request_id,
        "operation": operation,
        "status": "error",
        "diagnostics": {
            "format": "MIFDIAG/1.0",
            "errors": [error.into_value()],
        },
    })
}

fn capabilities() -> Value {
    json!({
        "format": "MIFCAP/1.0",
        "implementation": { "name": "sanmill-rust-mif-adapter", "version": env!("CARGO_PKG_VERSION") },
        "suites": [],
        "classes": [
            { "id": "conversion", "level": "none" },
            { "id": "identity", "level": "implemented" },
            { "id": "key", "level": "implemented" },
            { "id": "position", "level": "implemented" },
            { "id": "replay", "level": "implemented" },
            { "id": "ruleset", "level": "implemented" },
            { "id": "transform", "level": "implemented" }
        ],
        "formats": [
            { "id": "MFEN/1.0", "read": "implemented", "write": "implemented" },
            { "id": "MIFCAP/1.0", "read": "none", "write": "implemented" },
            { "id": "MIFCONV/1.0", "read": "none", "write": "none" },
            { "id": "MIFDIAG/1.0", "read": "none", "write": "implemented" },
            { "id": "MIFINV/1.0", "read": "implemented", "write": "none" },
            { "id": "MIFPOS/1.0", "read": "implemented", "write": "implemented" },
            { "id": "MIFSUITE/1.0", "read": "none", "write": "none" },
            { "id": "MIFTURN/1.0", "read": "none", "write": "implemented" },
            { "id": "MPK/1.0", "read": "implemented", "write": "implemented" },
            { "id": "MRS/1.0", "read": "implemented", "write": "none" },
            { "id": "MSTATE/1.0", "read": "implemented", "write": "implemented" }
        ],
        "profiles": {
            "semantics": ["mif-finite-rules-v3"],
            "semanticProjection": ["mrs-semantic-v1"],
            "state": ["mill24-state-v1"],
            "key": ["structural-d4-v1"],
            "repetitionProjection": ["repetition-observation-v1"],
            "observation": ["stable-moving-v1", "stable-primary-decision-v1"],
            "repetitionSummary": ["reset-count-smt-v1"],
            "resumption": ["resumption-state-v1"],
            "decision": ["decision-state-v1"],
            "claimLifecycle": ["stable-claim-rights-v1"],
            "mpkBinding": ["inline-semantic-digest-v1"],
            "transform": ["mill24-full-state-v1"],
            "logicalTurn": ["logical-turn-v1"],
            "placingLiveness": ["apply-board-full", "draw", "loss"]
        },
        "rulesets": [
            {
                "id": "example-morris", "version": 1,
                "semanticDigest": "sha256:224f7e368e322a4cc8c1225a025fb548d5b41eb096d34b7ae0543182d1aa9393",
                "documentDigest": "sha256:62479b6f40efb8ab478bab3d2b725647213604fcd3cc9cd4c1f69357535ae257",
                "level": "implemented"
            },
            {
                "id": "x-origin-stabilization", "version": 1,
                "semanticDigest": "sha256:173caf8189defd1ab7d4a3e8b9e26688a07fd77976bf09d56bff5fe0c273e1a1",
                "documentDigest": "sha256:9e8a7aa8f71fe2d8cc4d0d3bc5571f2c09e21f98b12b336b691f1cdbe5bb2833",
                "level": "implemented"
            }
        ],
        "invarianceDeclarations": [],
        "conversions": [],
        "resourceLimits": [
            { "name": "events", "limit": MAX_EVENTS },
            { "name": "interop-request-bytes", "limit": MAX_INTEROP_REQUEST_BYTES },
            { "name": "repetition-entries", "limit": MAX_REPETITION_ENTRIES }
        ],
        "testedCorpora": [
            {
                "digest": "sha256:d11317a090300f8a47f77afed647bdbd236dcdb1996c0147a81c874fa39dfd82",
                "classes": ["identity", "position", "replay", "ruleset", "transform"]
            }
        ],
        "annotations": {
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
        }
    })
}

#[cfg(test)]
mod tests;
