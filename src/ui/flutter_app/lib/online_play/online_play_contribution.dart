// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/material.dart';

import '../game_page/services/mill.dart' show GameController;
import '../game_platform/game_id.dart';
import '../game_platform/game_menu.dart';
import '../game_platform/game_session.dart';
import '../game_platform/play_mode_contribution.dart';
import '../game_shell/game_session_scope.dart';
import '../games/mill/mill_route_ids.dart';
import '../generated/intl/l10n.dart';
import '../shared/config/constants.dart';
import 'online_deep_links.dart';
import 'online_friend_game_page.dart';
import 'online_game_registration.dart';

class OnlinePlayContribution implements PlayModeContribution {
  const OnlinePlayContribution();

  // App-lifetime subscription installed once by the official entry point.
  // ignore: cancel_subscriptions
  static StreamSubscription<Uri>? _autoOpenSubscription;
  static bool _routeOpen = false;

  static void initializeDeepLinks() {
    final OnlineDeepLinkController controller =
        OnlineDeepLinkController.instance;
    controller.start();
    _autoOpenSubscription ??= controller.links.listen((Uri uri) {
      unawaited(_openInviteRoute(uri));
    });
  }

  static Future<void> _openInviteRoute(Uri uri, [int attempt = 0]) async {
    await Future<void>.delayed(Duration.zero);
    final OnlineDeepLinkController links = OnlineDeepLinkController.instance;
    if (links.pending != uri || _routeOpen) {
      return;
    }
    final NavigatorState? navigator = currentNavigatorKey.currentState;
    final session = GameController().activeNativeMillSession;
    if (navigator == null || session == null) {
      if (attempt < 100) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await _openInviteRoute(uri, attempt + 1);
      }
      return;
    }
    links.consume(uri);
    _routeOpen = true;
    try {
      await navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => GameSessionScope(
            session: session,
            child: OnlineFriendGamePage(
              registration: const MillOnlineGameRegistration(),
              initialInviteUri: uri,
            ),
          ),
        ),
      );
    } finally {
      _routeOpen = false;
    }
  }

  @override
  GameId get gameId => GameId.mill;

  @override
  GameModeEntry buildEntry(BuildContext context) {
    final S s = S.of(context);
    return GameModeEntry(
      id: MillRouteIds.humanVsCloud,
      label: s.onlineFriendGame,
      launchTarget: GameModeLaunchTarget.online,
      availability: GameModeAvailability.experimental,
      capabilities: const <GameModeCapability>{
        GameModeCapability.remoteMultiplayer,
        GameModeCapability.reviewable,
      },
      subtitle: s.onlineFriendGameDescription,
      icon: Icons.cloud_outlined,
      menuKey: const Key('drawer_item_human_vs_cloud'),
      contentKey: const Key('human_cloud'),
      builder: (BuildContext context, {Key? key, GameSession? session}) =>
          OnlineFriendGamePage(
            key: key,
            registration: const MillOnlineGameRegistration(),
            initialInviteUri: OnlineDeepLinkController.instance.takePending(),
          ),
    );
  }
}
