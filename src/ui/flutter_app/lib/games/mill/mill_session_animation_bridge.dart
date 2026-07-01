// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:typed_data';

import '../../appearance_settings/models/display_settings.dart';
import '../../game_page/services/mill.dart' as mill;
import '../../game_platform/game_session.dart';
import '../../shared/database/database.dart';
import 'mill_board_coordinate_maps.dart';
import 'mill_constants.dart';
import 'mill_types.dart';

/// Drives board piece animations and their sound effects from native Mill
/// session events.
///
/// Mirrors [MillSessionRecorderBridge]: it subscribes once at session creation
/// time so that place / move / remove animations and the matching landing,
/// mill, and capture sounds are produced from the authoritative
/// [GameSessionEvent] stream instead of being scattered through the tap and AI
/// call sites.
///
/// The legacy driver for these effects lived in the Dart `Position` rule
/// machine (`position.dart`) and was removed together with it.  This bridge
/// reconnects the same behaviour to the Rust-native session path without
/// reintroducing any rule logic on the Dart side: it reads only the
/// already-applied snapshot to choose the correct sound, and forwards
/// rendering hints (focus / blur / remove indices) to the shared
/// [mill.Game] + animation manager.
class MillSessionAnimationBridge {
  MillSessionAnimationBridge({required GameSession session})
    : _session = session {
    _subscription = session.events.listen(_onEvent);
  }

  final GameSession _session;
  late final StreamSubscription<GameSessionEvent> _subscription;

  Future<void> dispose() => _subscription.cancel();

  mill.Game get _game => mill.GameController().gameInstance;

  void _onEvent(GameSessionEvent event) {
    if (event.type == MillEventTypes.moveApplied) {
      _onMoveApplied(event);
    } else if (event.type == MillEventTypes.undoApplied ||
        event.type == MillEventTypes.redoApplied) {
      // History navigation undoes / replays moves with animations disabled and
      // sound muted (see HistoryNavigation).  Clear stale highlight indices so
      // the board does not keep a focus ring on a square whose move was just
      // taken back; the navigation layer plays its own landing sound for the
      // resulting position.
      _clearIndices();
    }
  }

  void _onMoveApplied(GameSessionEvent event) {
    final String type = event.payload['type'] as String? ?? '';
    switch (type) {
      case MillActionTypes.place:
        _animatePlace(event);
      case MillActionTypes.move:
        _animateMove(event);
      case MillActionTypes.remove:
        _animateRemove(event);
    }
  }

  void _animatePlace(GameSessionEvent event) {
    _game
      ..removeIndex = null
      ..blurIndex = null
      ..focusIndex = gridIndexForNode(_toNode(event));
    _prepareLandingSound(event, isMove: false);
    if (mill.GameController().hasAnimationManager) {
      mill.GameController().animationManager.animatePlace();
    }
  }

  void _animateMove(GameSessionEvent event) {
    _game
      ..removeIndex = null
      ..blurIndex = gridIndexForNode(_fromNode(event))
      ..focusIndex = gridIndexForNode(_toNode(event));
    _prepareLandingSound(event, isMove: true);
    if (mill.GameController().hasAnimationManager) {
      mill.GameController().animationManager.animateMove();
    }
  }

  void _animateRemove(GameSessionEvent event) {
    final PieceColor? capturer = _moverColor(event);
    _game
      ..removeByColor = capturer
      ..removePieceColor = capturer == null ? null : _opponentOf(capturer)
      ..removeIndex = gridIndexForNode(_toNode(event))
      ..blurIndex = null
      ..focusIndex = null;
    // The remove sound always plays immediately at capture time, matching the
    // legacy behaviour; the fly-out animation runs in parallel.
    mill.SoundManager().playTone(mill.Sound.remove);
    if (mill.GameController().hasAnimationManager) {
      mill.GameController().animationManager.animateRemove();
    }
  }

  /// Decide how the landing sound for a place / move is produced.
  ///
  /// This mirrors the legacy `position.dart` logic:
  ///   * If the action formed a mill, play the mill sound.  When pick-up
  ///     animations are enabled the sound is deferred to the put-down landing
  ///     (so audio and animation stay in sync) via [mill.Game]'s one-shot
  ///     flags, which the animation manager consumes; otherwise it plays
  ///     immediately.
  ///   * Otherwise the place sound is normally played by the put-down
  ///     animation status listener.  That listener fires for every move, but
  ///     for a place only when pick-up animations are enabled, so when they
  ///     are disabled (or animations are suppressed) we play it immediately.
  void _prepareLandingSound(GameSessionEvent event, {required bool isMove}) {
    final DisplaySettings display = DB().displaySettings;
    final bool pickUpEnabled = display.isPiecePickUpAnimationEnabled;
    // No GameBoard means no put-down listener will ever fire to consume a
    // deferred landing sound, so treat animations as not-allowed and play
    // sounds immediately below (matches the no-animation branch).
    final bool animationsAllowed =
        mill.GameController().hasAnimationManager &&
        mill.GameController().animationManager.allowAnimations;

    if (_moveFormedMill(event)) {
      final bool canDeferToLanding =
          pickUpEnabled && display.animationDuration > 0 && animationsAllowed;

      // Defensively complete a leftover barrier so a previous mill that never
      // landed cannot block a follow-up capture indefinitely.
      final Completer<void>? previous = _game.pendingMillSoundCompleter;
      if (previous != null && !previous.isCompleted) {
        previous.complete();
      }

      if (canDeferToLanding) {
        _game
          ..playMillSoundOnLanding = true
          ..pendingMillSoundCompleter = Completer<void>();
      } else {
        final Completer<void> barrier = Completer<void>();
        _game
          ..playMillSoundOnLanding = false
          ..pendingMillSoundCompleter = barrier;
        mill.SoundManager().playToneAndWait(mill.Sound.mill).whenComplete(() {
          if (!barrier.isCompleted) {
            barrier.complete();
          }
          if (_game.pendingMillSoundCompleter == barrier) {
            _game.pendingMillSoundCompleter = null;
          }
        });
      }
      return;
    }

    // Custodian / intervention captures during placing also schedule a remove
    // but are not mills (see master 2aa1bc50d: gate the immediate place sound
    // on non-capture placements when pick-up animation is disabled).
    if (!isMove && _placementTriggeredCaptureRemoval(event)) {
      _game.playMillSoundOnLanding = false;
      return;
    }

    // No mill: the put-down listener plays the place sound for every move, and
    // for a place only when pick-up animations are enabled.  When the listener
    // will not fire, play the sound now instead.
    _game.playMillSoundOnLanding = false;
    final bool putDownWillPlaySound =
        animationsAllowed && (isMove || pickUpEnabled);
    if (!putDownWillPlaySound) {
      mill.SoundManager().playTone(mill.Sound.place);
    }
  }

  /// True when a just-applied placement left the mover with pending removals
  /// (custodian / intervention capture).  Exposed for tests.
  static bool placementTriggeredCaptureRemoval({
    required Uint8List payload,
    required PieceColor mover,
  }) {
    if (payload.length < 30) {
      return false;
    }
    final int side = mover == PieceColor.white ? 0 : 1;
    return payload[28 + side] > 0;
  }

  bool _placementTriggeredCaptureRemoval(GameSessionEvent event) {
    final PieceColor? mover = _moverColor(event);
    if (mover == null) {
      return false;
    }
    final Object? raw = _session.state.value.payload['tgfPayload'];
    if (raw is! Uint8List) {
      return false;
    }
    return placementTriggeredCaptureRemoval(payload: raw, mover: mover);
  }

  /// Returns true when the just-applied place / move completed a mill that
  /// includes the destination node.
  ///
  /// Detection is purely positional (three of the mover's pieces on a mill
  /// line through the destination), so it reports `true` only for genuine
  /// mills and not for custodian / intervention captures that also create a
  /// pending removal.  This matches the legacy mill-vs-place sound split.
  bool _moveFormedMill(GameSessionEvent event) {
    final int? to = _toNode(event);
    if (to == null) {
      return false;
    }
    final PieceColor? mover = _moverColor(event);
    final int moverByte = _colorByte(mover);
    if (moverByte == 0) {
      return false;
    }
    final Uint8List? occupancy = _nodeOccupancy();
    if (occupancy == null) {
      return false;
    }
    return formedMillAt(
      occupancy: occupancy,
      toNode: to,
      moverByte: moverByte,
      hasDiagonalLines: DB().ruleSettings.hasDiagonalLines,
    );
  }

  /// Pure mill-line check: does [toNode] (occupied by [moverByte]) belong to a
  /// completed mill line of that colour in [occupancy]?
  ///
  /// Exposed for testing; `occupancy` is the 0..23 node array (`0` empty,
  /// `1` white, `2` black).
  static bool formedMillAt({
    required Uint8List occupancy,
    required int toNode,
    required int moverByte,
    required bool hasDiagonalLines,
  }) {
    if (toNode < 0 ||
        toNode >= _nodeCount ||
        occupancy.length < _nodeCount ||
        occupancy[toNode] != moverByte) {
      return false;
    }
    final List<List<int>> lines = hasDiagonalLines
        ? MillBoardCoordinateMaps.diagonalMillNodeLines
        : MillBoardCoordinateMaps.standardMillNodeLines;
    for (final List<int> line in lines) {
      if (!line.contains(toNode)) {
        continue;
      }
      if (line.every((int node) => occupancy[node] == moverByte)) {
        return true;
      }
    }
    return false;
  }

  /// Node occupancy bytes (`0` empty, `1` white, `2` black) of the current
  /// post-move snapshot, or null when unavailable.
  Uint8List? _nodeOccupancy() {
    final Object? raw = _session.state.value.payload['tgfPayload'];
    if (raw is! Uint8List || raw.length < _nodeCount) {
      return null;
    }
    return raw;
  }

  void _clearIndices() {
    _game
      ..focusIndex = null
      ..blurIndex = null
      ..removeIndex = null;
  }

  PieceColor? _moverColor(GameSessionEvent event) {
    return switch (event.payload['mover'] as String?) {
      'first' => PieceColor.white,
      'second' => PieceColor.black,
      _ => null,
    };
  }

  PieceColor _opponentOf(PieceColor color) {
    return color == PieceColor.white ? PieceColor.black : PieceColor.white;
  }

  static int _colorByte(PieceColor? color) {
    return switch (color) {
      PieceColor.white => 1,
      PieceColor.black => 2,
      _ => 0,
    };
  }

  int? _toNode(GameSessionEvent event) => _asNode(event.payload['toNode']);

  int? _fromNode(GameSessionEvent event) => _asNode(event.payload['fromNode']);

  int? _asNode(Object? raw) => (raw is int && raw >= 0) ? raw : null;

  /// Convert a 0..23 board node to the legacy 7x7 grid index the painter
  /// indexes by, or null when the node is missing / out of range.
  ///
  /// Exposed for testing.
  static int? gridIndexForNode(int? node) {
    if (node == null || node < 0 || node >= _nodeCount) {
      return null;
    }
    final int? square = MillBoardCoordinateMaps.nodeToLegacySquare[node];
    if (square == null) {
      return null;
    }
    return MillBoardCoordinateMaps.squareToGridIndex[square];
  }

  static const int _nodeCount = 24;
}
