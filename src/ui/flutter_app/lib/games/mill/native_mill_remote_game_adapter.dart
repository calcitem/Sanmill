// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import '../../game_platform/game_session.dart';
import '../../general_settings/models/general_settings.dart';
import '../../remote_play/remote_match_coordinator.dart';
import '../../remote_play/remote_models.dart';
import '../../rule_settings/models/rule_settings.dart';
import 'mill_remote_session_meta.dart';
import 'native_mill_game_session.dart';

class NativeMillRemoteGameAdapter implements RemoteGameAdapter {
  NativeMillRemoteGameAdapter({
    required this.session,
    required this.transportKind,
    required this.role,
    this.generalSettings,
    this.onBeforeReset,
    this.onStateChanged,
  });

  final NativeMillGameSession session;
  final RemoteTransportKind transportKind;
  final RemoteRole role;
  final GeneralSettings? generalSettings;
  final FutureOr<void> Function()? onBeforeReset;
  final FutureOr<void> Function()? onStateChanged;

  RemoteMatchConfig? _config;

  @override
  RemoteSeat get activeSeat => switch (session.state.value.activeSeat) {
    PlayerSeat.first => RemoteSeat.first,
    PlayerSeat.second => RemoteSeat.second,
    PlayerSeat.none => RemoteSeat.first,
  };

  @override
  String get fen => session.getFen();

  @override
  Future<void> configure(RemoteMatchConfig config) async {
    _config = config;
    await onBeforeReset?.call();
    final RuleSettings rules = RuleSettings.fromJson(
      Map<String, dynamic>.from(config.ruleSettings),
    );
    session.resetGame(rules: rules, generalSettings: generalSettings);
    if (session.getFen() != config.initialFen) {
      final bool loaded = session.loadFen(config.initialFen);
      if (!loaded) {
        throw FormatException(
          'Invalid remote initial FEN: ${config.initialFen}',
        );
      }
    }
    final RemoteSeat localSeat = role == RemoteRole.host
        ? config.hostPlaysFirst
              ? RemoteSeat.first
              : RemoteSeat.second
        : config.hostPlaysFirst
        ? RemoteSeat.second
        : RemoteSeat.first;
    session.remoteMeta = MillRemoteSessionMeta.fromRemote(
      RemoteSessionMeta(
        transportKind: transportKind,
        role: role,
        localSeat: localSeat,
        hostPlaysFirst: config.hostPlaysFirst,
        sessionId: config.sessionId,
      ),
    );
    await onStateChanged?.call();
  }

  @override
  Future<bool> applyAction(String notation) async {
    final bool applied = session.applyMoveString(notation);
    if (applied) {
      await onStateChanged?.call();
    }
    return applied;
  }

  @override
  Future<void> restoreSnapshot(RemoteStateSnapshot snapshot) async {
    final RemoteMatchConfig? config = _config;
    if (config == null) {
      throw StateError('Cannot restore a snapshot before match configuration.');
    }
    await configure(config);
    if (session.getFen() != snapshot.initialFen) {
      final bool loaded = session.loadFen(snapshot.initialFen);
      if (!loaded) {
        throw FormatException(
          'Invalid remote snapshot FEN: ${snapshot.initialFen}',
        );
      }
    }
    for (final String action in snapshot.actions) {
      if (!session.applyMoveString(action)) {
        throw StateError('Snapshot contains illegal action: $action');
      }
    }
    if (session.getFen() != snapshot.resultFen) {
      throw StateError('Snapshot result does not match its action history.');
    }
    await onStateChanged?.call();
  }

  @override
  Future<void> undoActions(int steps) async {
    if (steps <= 0 || steps > session.undoDepth) {
      throw RangeError.range(steps, 1, session.undoDepth, 'steps');
    }
    for (int i = 0; i < steps; i++) {
      await session.undo();
    }
    await onStateChanged?.call();
  }

  @override
  Future<void> forceWinner(RemoteSeat winner) async {
    session.forceTerminal(
      GameOutcome.win(
        winner == RemoteSeat.first ? PlayerSeat.first : PlayerSeat.second,
      ),
      reason: 'lose-resign',
    );
    await onStateChanged?.call();
  }

  @override
  Future<void> abandon() async {
    session.forceTerminal(
      const GameOutcome.abandoned(),
      reason: 'remote-abandoned',
    );
    await onStateChanged?.call();
  }
}
