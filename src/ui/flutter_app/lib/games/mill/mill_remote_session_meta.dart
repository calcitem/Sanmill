// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:meta/meta.dart';

import '../../game_platform/game_session.dart';
import '../../remote_play/remote_models.dart';

@immutable
class MillRemoteSessionMeta {
  const MillRemoteSessionMeta({
    required this.localSeat,
    required this.hostPlaysWhite,
    required this.transportKind,
    required this.role,
    required this.sessionId,
  });

  factory MillRemoteSessionMeta.fromRemote(RemoteSessionMeta meta) {
    return MillRemoteSessionMeta(
      localSeat: switch (meta.localSeat) {
        RemoteSeat.first => PlayerSeat.first,
        RemoteSeat.second => PlayerSeat.second,
      },
      hostPlaysWhite: meta.hostPlaysFirst,
      transportKind: meta.transportKind,
      role: meta.role,
      sessionId: meta.sessionId,
    );
  }

  final PlayerSeat localSeat;
  final bool hostPlaysWhite;
  final RemoteTransportKind transportKind;
  final RemoteRole role;
  final String sessionId;

  bool get localIsHost => role == RemoteRole.host;

  bool isOpponentTurn(PlayerSeat activeSeat) {
    return activeSeat != PlayerSeat.none && activeSeat != localSeat;
  }

  String get localPieceColorName {
    return switch (localSeat) {
      PlayerSeat.first => 'white',
      PlayerSeat.second => 'black',
      PlayerSeat.none => 'none',
    };
  }
}
