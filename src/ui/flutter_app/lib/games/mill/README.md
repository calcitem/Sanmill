<!--
SPDX-License-Identifier: GPL-3.0-or-later
Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
-->

# `lib/games/mill/` — File Map

The Mill game module is intentionally flat (Dart imports stay short and
non-cyclic), so this README acts as the taxonomy for the 21 source files
under this directory.  Adding a new Mill file should fit into one of
these buckets; if it does not, the bucket list itself probably needs an
extension.

## Module entry

* `mill_game_module.dart` — implements `GameModule` for Mill, registers
  the `MillKernelExtraDecoder`, exposes `playModes` / `drawerContributions`,
  applies first-run language defaults, etc.

## Ports (`game_platform` interface implementations)

* `mill_engine_port.dart` — `EnginePort` adapter; routes the legacy
  `Engine` through the platform engine boundary.
* `mill_notation_port.dart` — `NotationPort`: encode / decode notation
  strings for Mill move lists.
* `mill_rule_settings_port.dart` — `RuleSettingsPort` glue over the
  Hive-backed settings repository.

## Native FRB session adapters

* `mill_kernel_session.dart` — wraps `TgfKernel` with the Mill-only
  search-event stream, setup-position editors, and FEN import / export.
* `native_mill_rules_port.dart` — `RulesPort` backed by the Rust-native
  `MillRules` through `MillKernelSession`.
* `native_mill_game_session.dart` — full `GameSession` over the native
  rules port; emits `MillEventTypes.*` events.
* `native_mill_ai_turn_controller.dart` — drives the AI move pump for
  the native session (replaces the legacy `Engine`-based driver).
* `native_mill_snapshot_board_view.dart` — read-only `MillBoardView`
  built from a native `GameStateSnapshot`.

## Codecs and shape mappers

* `mill_action_codec.dart` — `GameAction` ↔ `tgf.TgfAction` ↔ legacy
  `ExtMove` (move-string and node-id translations).
* `mill_marked_pieces_codec.dart` — decodes `MillState.delayed_marked_pieces`
  bitmask out of the FRB opaque payload, plus the
  `MillKernelExtraDecoder` registered with `TgfKernelExtraRegistry`.
* `mill_variant_options_mapper.dart` — Hive `RuleSettings` ↔ FRB
  `MillVariantOptions` round-trip.
* `mill_board_coordinate_maps.dart` — dense node ↔ legacy square ↔
  notation ↔ PlayOK numeric notation tables.
* `game_state_snapshot_mill_ext.dart` — `GameStateSnapshot.payload`
  accessor for the `millMarkedNodes` set, used by the board renderer.

## UI / interaction glue

* `mill_session_tap_controller.dart` — converts raw board taps into
  `GameAction`s through `MillTapActionSelector`.
* `mill_tap_action_selector.dart` — pure logic for "what `GameAction`
  does this tap correspond to?" given the current snapshot.
* `mill_session_recorder_bridge.dart` — keeps `GameRecorder` synchronised
  with `MillGameSession`'s event stream; forwards through
  `GameController.gameRecorder` so legacy widgets keep working.

## Puzzle integration

* `puzzle_mill_session.dart` — Mill-flavoured `GameSession` used by
  the Puzzle module.

## Constants / route ids / metadata

* `mill_constants.dart` — `MillActionTypes`, `MillEventTypes`,
  `MillPhases.legacy` and friends.
* `mill_route_ids.dart` — drawer / shell `GameRouteId`s for the Mill
  play modes (humanVsAi, humanVsHuman, etc.).
* `lan_session_meta.dart` — typed wrapper around the LAN session
  payload (`hostName`, `peerName`, `connectedAt`).

## Conventions

* New code should prefer the **native** rules port / game session and
  the typed `MillKernelSession` over the legacy `GameController`
  facade.  The legacy paths are still wired through for backwards
  compatibility but new game modes should not extend them.
* Only `mill_marked_pieces_codec.dart` is allowed to touch the raw
  FRB opaque payload bytes — every other consumer reads through the
  `GameStateSnapshotMillExt` getter.
* When a file gets large enough (~700 lines) consider splitting along
  the bucket lines in this README; do not invent a new top-level
  Mill directory layout, the flat structure is intentional.
