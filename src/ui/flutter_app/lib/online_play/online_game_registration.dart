// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/widgets.dart';

import '../game_page/services/mill.dart' show GameController, GameMode;
import '../game_page/widgets/game_page.dart';
import '../games/mill/mill_variant_localization.dart';
import '../generated/intl/l10n.dart';
import '../remote_play/remote_match_controller.dart';
import '../shared/database/database.dart';
import 'cloud_match_coordinator.dart';
import 'online_models.dart';
import 'online_room_api.dart';
import 'online_session_store.dart';
import 'online_socket_client.dart';

/// One game's contribution to the shared online friend-match feature.
///
/// Adding another game does not change room, invitation, WebSocket, reconnect,
/// or page code. It contributes wire identifiers, rule serialization, a short
/// variant label, and the factory that installs its [RemoteGameAdapter].
abstract interface class OnlineGameRegistration {
  OnlineGameDefinition get definition;

  Map<String, Object?> createRuleOptions();

  String variantLabel(BuildContext context, Map<String, Object?> ruleOptions);

  Widget buildBoard(BuildContext context);

  Future<CloudMatchCoordinator> installCoordinator({
    required OnlineRoomSession session,
    required OnlineRoomApi roomApi,
    required OnlineSocketClient socket,
    required OnlineSessionStore sessionStore,
  });

  Future<void> disposeCoordinator();
}

class MillOnlineGameRegistration implements OnlineGameRegistration {
  const MillOnlineGameRegistration();

  @override
  OnlineGameDefinition get definition => onlineMillGameDefinition;

  @override
  Map<String, Object?> createRuleOptions() =>
      onlineOptionsFromRuleSettings(DB().ruleSettings);

  @override
  String variantLabel(BuildContext context, Map<String, Object?> ruleOptions) =>
      localizedMillVariantName(
        S.of(context),
        ruleSettingsFromOnlineOptions(ruleOptions),
      );

  @override
  Widget buildBoard(BuildContext context) =>
      const GamePage(GameMode.humanVsCloud);

  @override
  Future<CloudMatchCoordinator> installCoordinator({
    required OnlineRoomSession session,
    required OnlineRoomApi roomApi,
    required OnlineSocketClient socket,
    required OnlineSessionStore sessionStore,
  }) {
    return GameController().createCloudRemoteController<CloudMatchCoordinator>(
      (RemoteGameAdapter game) => CloudMatchCoordinator(
        definition: definition,
        session: session,
        roomApi: roomApi,
        socket: socket,
        game: game,
        sessionStore: sessionStore,
      ),
      role: session.role,
    );
  }

  @override
  Future<void> disposeCoordinator() => GameController().disposeRemoteMatch();
}
