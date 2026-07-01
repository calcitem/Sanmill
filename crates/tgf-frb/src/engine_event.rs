// SPDX-License-Identifier: AGPL-3.0-or-later
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

pub(crate) struct PrincipalVariationEvent<'a> {
    pub rank: usize,
    pub action: tgf_core::Action,
    pub score: i32,
    pub root_side_to_move: i8,
    pub notation: &'a str,
    pub pv_notation: &'a str,
    pub nodes: u64,
    pub nodes_per_second: u64,
    pub depth: i32,
    pub cutoff: bool,
}

/// Construct a "pv" event for one root candidate line.
///
/// `event.rank` follows UCI MultiPV semantics: lower ranks are better for the
/// side to move at the root.  `event.pv_notation` is a comma-separated line
/// reconstructed from opt-in TT move hints when available.
pub(crate) fn principal_variation(event: PrincipalVariationEvent<'_>) -> EngineEvent {
    let output_score = if event.root_side_to_move == 1 {
        -event.score
    } else {
        event.score
    };
    EngineEvent {
        kind: "pv".to_owned(),
        depth: event.depth,
        score: output_score,
        nodes: event.nodes,
        to_node: event.action.to_node as i32,
        reason: format!(
            "{} rank={} rawScore={} cutoff={} nps={} pv={}",
            event.notation,
            event.rank,
            event.score,
            event.cutoff,
            event.nodes_per_second,
            event.pv_notation
        ),
    }
}

/// Background-spawn an `error → stopped` sequence on a fresh thread so a
/// failed search request still releases the Dart-side `Stream`.
pub(crate) fn spawn_kernel_search_error(message: String, sink: StreamSink<EngineEvent>) {
    #[cfg(not(target_arch = "wasm32"))]
    std::thread::spawn(move || {
        let _ = sink.add(error(&message));
        let _ = sink.add(stopped());
    });

    #[cfg(target_arch = "wasm32")]
    {
        let _ = sink.add(error(&message));
        let _ = sink.add(stopped());
    }
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

#[cfg(test)]
mod tests {
    use tgf_core::Action;

    use super::{
        PrincipalVariationEvent, best_move_with_notation_and_aimovetype, principal_variation,
    };

    const ACTION: Action = Action {
        kind_tag: 0,
        from_node: -1,
        to_node: 3,
        aux: -1,
        payload_bits: 0,
    };

    #[test]
    fn best_move_score_is_reported_from_first_player_perspective() {
        let first_player =
            best_move_with_notation_and_aimovetype(ACTION, 42, 0, "d6", "traditional");
        let second_player =
            best_move_with_notation_and_aimovetype(ACTION, 42, 1, "d6", "traditional");

        assert_eq!(first_player.score, 42);
        assert_eq!(second_player.score, -42);
        assert!(second_player.reason.contains("rawScore=42"));
    }

    #[test]
    fn principal_variation_score_is_reported_from_first_player_perspective() {
        let first_player = principal_variation(PrincipalVariationEvent {
            rank: 1,
            action: ACTION,
            score: -27,
            root_side_to_move: 0,
            notation: "d6",
            pv_notation: "d6,f4",
            nodes: 128,
            nodes_per_second: 4096,
            depth: 3,
            cutoff: false,
        });
        let second_player = principal_variation(PrincipalVariationEvent {
            rank: 1,
            action: ACTION,
            score: -27,
            root_side_to_move: 1,
            notation: "d6",
            pv_notation: "d6,f4",
            nodes: 128,
            nodes_per_second: 4096,
            depth: 3,
            cutoff: false,
        });

        assert_eq!(first_player.score, -27);
        assert_eq!(second_player.score, 27);
        assert!(second_player.reason.contains("rawScore=-27"));
        assert!(second_player.reason.contains("rank=1"));
        assert!(second_player.reason.contains("nps=4096"));
        assert!(second_player.reason.contains("pv=d6,f4"));
    }
}
