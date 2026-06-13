// SPDX-License-Identifier: GPL-3.0-or-later
// Game-neutral helpers for the FRB-public `EngineEvent` POD.
//
// `EngineEvent` itself is defined in `crate::api::simple` because the FRB
// codegen scans the `pub struct` definition there to produce the Dart
// wire type.  Every helper that constructs or transforms events lives
// here so the `crate::api::*` modules stay thin.

pub(crate) use crate::api::simple::EngineEvent;

use crate::frb_generated::StreamSink;

/// Construct a "ready" event.  Emitted as the first item on every search
/// stream so the Dart side knows the worker has spun up.
pub(crate) fn ready() -> EngineEvent {
    new("ready")
}

/// Construct a "stopped" event.  Emitted as the last item on every
/// search stream, regardless of success / failure.
pub(crate) fn stopped() -> EngineEvent {
    new("stopped")
}

/// Construct an "error" event.  The error text is stored in `reason`.
pub(crate) fn error(reason: &str) -> EngineEvent {
    EngineEvent {
        kind: "error".to_owned(),
        depth: 0,
        score: 0,
        nodes: 0,
        to_node: -1,
        reason: reason.to_owned(),
    }
}

/// Construct an "info" event used for IDS depth progress.
pub(crate) fn info(depth: i32, score: i32, nodes: u64) -> EngineEvent {
    EngineEvent {
        kind: "info".to_owned(),
        depth,
        score,
        nodes,
        to_node: -1,
        reason: String::new(),
    }
}

/// Construct a "bestMove" event from a raw action plus a pre-formatted
/// notation string.  Concrete game adapters provide `notation` from
/// their own action codec (e.g. Mill UCI: "a4", "a1-a4", "xa4").
///
/// `root_side_to_move` flips the score to first-player perspective so
/// the Dart side never needs to know about side-relative scoring; the
/// original (mover-relative) value is preserved inside `reason` as
/// `rawScore=<score>` for callers that depend on it.
#[expect(dead_code)]
pub(crate) fn best_move_with_notation(
    action: tgf_core::Action,
    score: i32,
    root_side_to_move: i8,
    notation: &str,
) -> EngineEvent {
    best_move_with_notation_and_aimovetype(
        action,
        score,
        root_side_to_move,
        notation,
        "traditional",
    )
}

/// Like [best_move_with_notation] but annotates `reason` with an explicit
/// `aimovetype=` tag for the Flutter UI (`traditional` / `perfect` /
/// `consensus`).
pub(crate) fn best_move_with_notation_and_aimovetype(
    action: tgf_core::Action,
    score: i32,
    root_side_to_move: i8,
    notation: &str,
    aimovetype: &str,
) -> EngineEvent {
    let output_score = if root_side_to_move == 1 {
        -score
    } else {
        score
    };
    EngineEvent {
        kind: "bestMove".to_owned(),
        depth: action.from_node as i32,
        score: output_score,
        nodes: 0,
        to_node: action.to_node as i32,
        reason: format!("{notation} aimovetype={aimovetype} rawScore={score}"),
    }
}

/// Background-spawn an `error → stopped` sequence on a fresh thread so a
/// failed search request still releases the Dart-side `Stream`.
pub(crate) fn spawn_kernel_search_error(message: String, sink: StreamSink<EngineEvent>) {
    std::thread::spawn(move || {
        let _ = sink.add(error(&message));
        let _ = sink.add(stopped());
    });
}

fn new(kind: &str) -> EngineEvent {
    EngineEvent {
        kind: kind.to_owned(),
        depth: 0,
        score: 0,
        nodes: 0,
        to_node: -1,
        reason: String::new(),
    }
}
