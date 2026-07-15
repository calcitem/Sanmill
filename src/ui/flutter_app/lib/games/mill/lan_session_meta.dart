// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:meta/meta.dart';

import '../../game_platform/game_session.dart';
import '../../remote_play/remote_models.dart';
import 'mill_remote_session_meta.dart';

/// LAN-specific ownership metadata for a native Mill session.
///
/// The Rust session only knows whose turn it is.  LAN UI code also needs to
/// know which seat belongs to this device so it can block opponent taps and
/// compute the local/remote turn state without consulting legacy `Position`.
@immutable
class LanSessionMeta extends MillRemoteSessionMeta {
  const LanSessionMeta({
    required super.localSeat,
    required super.hostPlaysWhite,
  }) : super(
         transportKind: RemoteTransportKind.lan,
         role: hostPlaysWhite
             ? localSeat == PlayerSeat.first
                   ? RemoteRole.host
                   : RemoteRole.join
             : localSeat == PlayerSeat.second
             ? RemoteRole.host
             : RemoteRole.join,
         sessionId: '',
       );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LanSessionMeta &&
          other.localSeat == localSeat &&
          other.hostPlaysWhite == hostPlaysWhite;

  @override
  int get hashCode => Object.hash(localSeat, hostPlaysWhite);

  /// Legacy `GameController.getLocalColor()` bridge while LAN still shares
  /// header and painter helpers with the pre-session code path.
  ///
  /// Returns the existing `PieceColor` enum without importing the legacy
  /// service library here; callers can compare the stable string token.
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
