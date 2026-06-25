// SPDX-License-Identifier: GPL-3.0-or-later
// Mill `setoption` lookup table — parses every UCI rule / search /
// engine option supported by the Mill CLI and applies the parsed value
// to the matching slot in `MillVariantOptions` or `EngineConfig`.

use tgf_mill::MillVariantOptions;

use super::EngineConfig;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum SetoptionResult {
    Variant,
    Threads,
    ClearHash,
    /// A non-variant search/engine parameter changed (e.g. SkillLevel).
    SearchConfig,
    /// Option is valid and stored but has no side-effect on game rules.
    Acknowledged,
    Unknown,
}

pub(super) fn apply_setoption(
    line: &str,
    options: &mut MillVariantOptions,
    threads: &mut usize,
    qsearch_max_depth: &mut i32,
    engine_cfg: &mut EngineConfig,
) -> SetoptionResult {
    let tokens = line.split_whitespace().collect::<Vec<_>>();
    let Some(name_pos) = tokens.iter().position(|t| *t == "name") else {
        return SetoptionResult::Unknown;
    };
    let value_pos = tokens.iter().position(|t| *t == "value");
    let name_end = value_pos.unwrap_or(tokens.len());
    if name_end <= name_pos + 1 {
        return SetoptionResult::Unknown;
    }
    let name = tokens[name_pos + 1..name_end]
        .join(" ")
        .to_ascii_lowercase();
    let value = match value_pos.and_then(|idx| tokens.get(idx + 1).copied()) {
        Some(value) => value,
        None if matches!(name.as_str(), "clear hash" | "clearhash") => "",
        None => return SetoptionResult::Unknown,
    };

    match name.as_str() {
        "threads" => {
            if let Some(n) = value.parse::<usize>().ok().filter(|n| (1..=64).contains(n)) {
                *threads = n;
                SetoptionResult::Threads
            } else {
                SetoptionResult::Unknown
            }
        }
        "maxquiescencedepth" | "max quiescence depth" => value
            .parse::<i32>()
            .ok()
            .filter(|v| (0..=4).contains(v))
            .map(|v| {
                *qsearch_max_depth = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),

        // --- Search / difficulty options (P1-A) ---
        "skilllevel" | "skill level" => value
            .parse::<u8>()
            .ok()
            .filter(|v| (0..=30).contains(v))
            .map(|v| {
                engine_cfg.skill_level = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        // Legacy seconds-based option; kept for compatibility with master
        // C++ engines and existing UCI GUIs. Value 0..=60 accepted;
        // stored internally as milliseconds.
        "movetime" | "move time" => value
            .parse::<u32>()
            .ok()
            .filter(|v| (0..=60).contains(v))
            .map(|v| {
                engine_cfg.move_time_ms = v.saturating_mul(1000);
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        // Millisecond-precision option; Sanmill-only (master C++ ignores it).
        // Enables sub-second thinking times for faster H2H matches and
        // eval-tuning verification runs. Range 0..=60000.
        "movetimems" | "move time ms" => value
            .parse::<u32>()
            .ok()
            .filter(|v| (0..=60_000).contains(v))
            .map(|v| {
                engine_cfg.move_time_ms = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "aiislazy" | "ai is lazy" => parse_bool(value)
            .map(|v| {
                engine_cfg.ai_is_lazy = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "idsenabled" | "ids enabled" => parse_bool(value)
            .map(|v| {
                engine_cfg.ids_enabled = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "depthextension" | "depth extension" => parse_bool(value)
            .map(|v| {
                engine_cfg.depth_extension = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "algorithm" => value
            .parse::<u8>()
            .ok()
            .filter(|v| (0..=4).contains(v))
            .map(|v| {
                engine_cfg.algorithm = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "shuffling" => parse_bool(value)
            .map(|v| {
                engine_cfg.shuffling = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "uselazysmp" | "use lazy smp" => parse_bool(value)
            .map(|v| {
                engine_cfg.use_lazy_smp = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "drawonhumanexperience" | "draw on human experience" => parse_bool(value)
            .map(|v| {
                engine_cfg.draw_on_human_experience = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "useperfectdatabase" | "use perfect database" => parse_bool(value)
            .map(|v| {
                engine_cfg.use_perfect_database = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "perfectdatabasepath" | "perfect database path" => {
            // A filesystem path may contain spaces, so take the entire
            // remainder of the line after `value` rather than a single token.
            let path = value_pos
                .map(|idx| tokens[idx + 1..].join(" "))
                .filter(|s| !s.is_empty());
            match path {
                Some(path) => {
                    engine_cfg.perfect_db_path = Some(path);
                    SetoptionResult::SearchConfig
                }
                None => SetoptionResult::Unknown,
            }
        }
        "perfectdatabasecachesectors" | "perfect database cache sectors" => value
            .parse::<usize>()
            .ok()
            .filter(|v| *v <= 1_048_576)
            .map(|v| {
                engine_cfg.perfect_db_cache_sectors = (v > 0).then_some(v);
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "developermode" | "developer mode" => parse_bool(value)
            .map(|v| {
                engine_cfg.developer_mode = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "considermobility" | "consider mobility" => parse_bool(value)
            .map(|v| {
                options.consider_mobility = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "focusonblockingpaths" | "focus on blocking paths" => parse_bool(value)
            .map(|v| {
                options.focus_on_blocking_paths = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "hash" => value
            .parse::<u32>()
            .ok()
            .filter(|v| (1..=33_554_432).contains(v))
            .map(|v| {
                engine_cfg.hash_mb = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "clear hash" | "clearhash" => SetoptionResult::ClearHash,
        "ponder" => parse_bool(value)
            .map(|v| {
                engine_cfg.ponder = v;
                SetoptionResult::Acknowledged
            })
            .unwrap_or(SetoptionResult::Unknown),
        "multipv" | "multi pv" => {
            let _ = value.parse::<u32>();
            SetoptionResult::Acknowledged
        }
        "move overhead" | "moveoverhead" => {
            let _ = value.parse::<u32>();
            SetoptionResult::Acknowledged
        }
        "slow mover" | "slowmover" => {
            let _ = value.parse::<u32>();
            SetoptionResult::Acknowledged
        }
        "nodestime" | "nodes time" => {
            let _ = value.parse::<u32>();
            SetoptionResult::Acknowledged
        }

        // --- Mill variant rule options ---
        "piecescount" | "pieces count" | "piececount" | "piece count" => value
            .parse::<u8>()
            .ok()
            .filter(|v| (9..=12).contains(v))
            .map(|v| {
                options.piece_count = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "flypiececount" | "fly piece count" => value
            .parse::<u8>()
            .ok()
            .filter(|v| (3..=4).contains(v))
            .map(|v| {
                options.fly_piece_count = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "piecesatleastcount" | "pieces at least count" => value
            .parse::<u8>()
            .ok()
            .filter(|v| (3..=5).contains(v))
            .map(|v| {
                options.pieces_at_least_count = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "mayfly" | "may fly" => parse_bool(value)
            .map(|v| {
                options.may_fly = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "hasdiagonallines" | "has diagonal lines" => parse_bool(value)
            .map(|v| {
                options.has_diagonal_lines = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "millformationactioninplacingphase" | "mill formation action in placing phase" => value
            .parse::<i16>()
            .ok()
            .filter(|v| (0..=5).contains(v))
            .and_then(|v| {
                use tgf_mill::MillFormationActionInPlacingPhase::*;
                let action = match v {
                    0 => RemoveOpponentsPieceFromBoard,
                    1 => RemoveOpponentsPieceFromHandThenOpponentsTurn,
                    2 => RemoveOpponentsPieceFromHandThenYourTurn,
                    3 => OpponentRemovesOwnPiece,
                    4 => MarkAndDelayRemovingPieces,
                    5 => RemovalBasedOnMillCounts,
                    _ => return None,
                };
                options.mill_formation_action_in_placing_phase = action;
                Some(SetoptionResult::Variant)
            })
            .unwrap_or(SetoptionResult::Unknown),
        "mayremovefrommillsalways" | "may remove from mills always" => parse_bool(value)
            .map(|v| {
                options.may_remove_from_mills_always = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "mayremovemultiple" | "may remove multiple" => parse_bool(value)
            .map(|v| {
                options.may_remove_multiple = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "nmoverule" | "n move rule" => value
            .parse::<u32>()
            .ok()
            .filter(|v| (10..=200).contains(v))
            .map(|v| {
                options.n_move_rule = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "endgamenmoverule" | "endgame n move rule" => value
            .parse::<u32>()
            .ok()
            .filter(|v| (5..=200).contains(v))
            .map(|v| {
                options.endgame_n_move_rule = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "maymoveinplacingphase" | "may move in placing phase" => parse_bool(value)
            .map(|v| {
                options.may_move_in_placing_phase = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "isdefendermovefirst" | "is defender move first" => parse_bool(value)
            .map(|v| {
                options.is_defender_move_first = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "restrictrepeatedmillsformation" | "restrict repeated mills formation" => parse_bool(value)
            .map(|v| {
                options.restrict_repeated_mills_formation = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "onetimeusemill" | "one time use mill" => parse_bool(value)
            .map(|v| {
                options.one_time_use_mill = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "stopplacingwhentwoEmptysquares"
        | "stopplacingwhentwoemptysquares"
        | "stop placing when two empty squares" => parse_bool(value)
            .map(|v| {
                options.stop_placing_when_two_empty_squares = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "boardfullaction" | "board full action" => value
            .parse::<u8>()
            .ok()
            .filter(|v| (0..=4).contains(v))
            .and_then(|v| {
                use tgf_mill::MillBoardFullAction::*;
                let action = match v {
                    0 => FirstPlayerLose,
                    1 => FirstAndSecondPlayerRemovePiece,
                    2 => SecondAndFirstPlayerRemovePiece,
                    3 => SideToMoveRemovePiece,
                    4 => AgreeToDraw,
                    _ => return None,
                };
                options.board_full_action = action;
                Some(SetoptionResult::Variant)
            })
            .unwrap_or(SetoptionResult::Unknown),
        "stalemateaction" | "stalemate action" => value
            .parse::<u8>()
            .ok()
            .filter(|v| (0..=5).contains(v))
            .and_then(|v| {
                use tgf_mill::StalemateAction::*;
                let action = match v {
                    0 => EndWithStalemateLoss,
                    1 => ChangeSideToMove,
                    2 => RemoveOpponentsPieceAndMakeNextMove,
                    3 => RemoveOpponentsPieceAndChangeSideToMove,
                    4 => EndWithStalemateDraw,
                    5 => BothPlayersRemoveOpponentsPiece,
                    _ => return None,
                };
                options.stalemate_action = action;
                Some(SetoptionResult::Variant)
            })
            .unwrap_or(SetoptionResult::Unknown),
        "threefoldrepetitionrule" | "threefold repetition rule" => parse_bool(value)
            .map(|v| {
                options.threefold_repetition_rule = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),

        // --- Custodian capture sub-options ---
        "custodiancaptureenabled" | "custodian capture enabled" => parse_bool(value)
            .map(|v| {
                options.custodian_capture.enabled = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "custodiancaptureonsquareedges" | "custodian capture on square edges" => parse_bool(value)
            .map(|v| {
                options.custodian_capture.on_square_edges = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "custodiancaptureoncrosslines" | "custodian capture on cross lines" => parse_bool(value)
            .map(|v| {
                options.custodian_capture.on_cross_lines = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "custodiancaptureondiagonallines" | "custodian capture on diagonal lines" => {
            parse_bool(value)
                .map(|v| {
                    options.custodian_capture.on_diagonal_lines = v;
                    SetoptionResult::Variant
                })
                .unwrap_or(SetoptionResult::Unknown)
        }
        "custodiancaptureinplacingphase" | "custodian capture in placing phase" => {
            parse_bool(value)
                .map(|v| {
                    options.custodian_capture.in_placing_phase = v;
                    SetoptionResult::Variant
                })
                .unwrap_or(SetoptionResult::Unknown)
        }
        "custodiancaptureinmovingphase" | "custodian capture in moving phase" => parse_bool(value)
            .map(|v| {
                options.custodian_capture.in_moving_phase = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "custodiancaptureonlywhenownpiecesleq3"
        | "custodian capture only when own pieces leq 3" => parse_bool(value)
            .map(|v| {
                options
                    .custodian_capture
                    .only_available_when_own_pieces_leq3 = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),

        // --- Intervention capture sub-options ---
        "interventioncaptureenabled" | "intervention capture enabled" => parse_bool(value)
            .map(|v| {
                options.intervention_capture.enabled = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "interventioncaptureonsquareedges" | "intervention capture on square edges" => {
            parse_bool(value)
                .map(|v| {
                    options.intervention_capture.on_square_edges = v;
                    SetoptionResult::Variant
                })
                .unwrap_or(SetoptionResult::Unknown)
        }
        "interventioncaptureoncrosslines" | "intervention capture on cross lines" => {
            parse_bool(value)
                .map(|v| {
                    options.intervention_capture.on_cross_lines = v;
                    SetoptionResult::Variant
                })
                .unwrap_or(SetoptionResult::Unknown)
        }
        "interventioncaptureondiagonallines" | "intervention capture on diagonal lines" => {
            parse_bool(value)
                .map(|v| {
                    options.intervention_capture.on_diagonal_lines = v;
                    SetoptionResult::Variant
                })
                .unwrap_or(SetoptionResult::Unknown)
        }
        "interventioncaptureinplacingphase" | "intervention capture in placing phase" => {
            parse_bool(value)
                .map(|v| {
                    options.intervention_capture.in_placing_phase = v;
                    SetoptionResult::Variant
                })
                .unwrap_or(SetoptionResult::Unknown)
        }
        "interventioncaptureinmovingphase" | "intervention capture in moving phase" => {
            parse_bool(value)
                .map(|v| {
                    options.intervention_capture.in_moving_phase = v;
                    SetoptionResult::Variant
                })
                .unwrap_or(SetoptionResult::Unknown)
        }
        "interventioncaptureonlywhenownpiecesleq3"
        | "intervention capture only when own pieces leq 3" => parse_bool(value)
            .map(|v| {
                options
                    .intervention_capture
                    .only_available_when_own_pieces_leq3 = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),

        // --- Leap capture sub-options ---
        "leapcaptureenabled" | "leap capture enabled" => parse_bool(value)
            .map(|v| {
                options.leap_capture.enabled = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "leapcaptureonsquareedges" | "leap capture on square edges" => parse_bool(value)
            .map(|v| {
                options.leap_capture.on_square_edges = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "leapcaptureoncrosslines" | "leap capture on cross lines" => parse_bool(value)
            .map(|v| {
                options.leap_capture.on_cross_lines = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "leapcaptureondiagonallines" | "leap capture on diagonal lines" => parse_bool(value)
            .map(|v| {
                options.leap_capture.on_diagonal_lines = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "leapcaptureinplacingphase" | "leap capture in placing phase" => parse_bool(value)
            .map(|v| {
                options.leap_capture.in_placing_phase = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "leapcaptureinmovingphase" | "leap capture in moving phase" => parse_bool(value)
            .map(|v| {
                options.leap_capture.in_moving_phase = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "leapcaptureonlywhenownpiecesleq3" | "leap capture only when own pieces leq 3" => {
            parse_bool(value)
                .map(|v| {
                    options.leap_capture.only_available_when_own_pieces_leq3 = v;
                    SetoptionResult::Variant
                })
                .unwrap_or(SetoptionResult::Unknown)
        }
        _ => SetoptionResult::Unknown,
    }
}

pub(super) fn parse_bool(value: &str) -> Option<bool> {
    match value.to_ascii_lowercase().as_str() {
        "true" | "1" | "yes" | "on" => Some(true),
        "false" | "0" | "no" | "off" => Some(false),
        _ => None,
    }
}
