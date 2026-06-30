// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:meta/meta.dart';

import '../../game_platform/game_session.dart';

/// LAN-specific ownership metadata for a native Mill session.
///
/// The Rust session only knows whose turn it is.  LAN UI code also needs to
/// know which seat belongs to this device so it can block opponent taps and
/// compute the local/remote turn state without consulting legacy `Position`.
@immutable
class LanSessionMeta {
  const LanSessionMeta({required this.localSeat, required this.hostPlaysWhite});

  final PlayerSeat localSeat;
  final bool hostPlaysWhite;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LanSessionMeta &&
          other.localSeat == localSeat &&
          other.hostPlaysWhite == hostPlaysWhite;

  @override
  int get hashCode => Object.hash(localSeat, hostPlaysWhite);

  bool get localIsHost => hostPlaysWhite
      ? localSeat == PlayerSeat.first
      : localSeat == PlayerSeat.second;

  bool isOpponentTurn(PlayerSeat activeSeat) {
    return activeSeat != PlayerSeat.none && activeSeat != localSeat;
  }

  /// Legacy `GameController.getLocalColor()` bridge while LAN still shares
  /// header and painter helpers with the pre-session code path.
  ///
  /// Returns the existing `PieceColor` enum without importing the legacy
  /// service library here; callers can compare the stable string token.
  String get localPieceColorName {
    return switch (localSeat) {
      PlayerSeat.first => 'white',
      PlayerSeat.second => 'black',
      PlayerSeat.none => 'none',
    };
  }

  static LanSessionMeta fromHost({
    required bool isHost,
    required bool hostPlaysWhite,
  }) {
    final PlayerSeat hostSeat = hostPlaysWhite
        ? PlayerSeat.first
        : PlayerSeat.second;
    final PlayerSeat clientSeat = hostPlaysWhite
        ? PlayerSeat.second
        : PlayerSeat.first;
    return LanSessionMeta(
      localSeat: isHost ? hostSeat : clientSeat,
      hostPlaysWhite: hostPlaysWhite,
    );
  }
}
