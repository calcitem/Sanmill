// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';

void main() {
  const List<String> expected = <String>[
    'onlineFriendGame',
    'onlineFriendGameDescription',
    'onlineServiceDisclosure',
    'onlineCreateGame',
    'onlineJoinGame',
    'onlineFriendGameSettings',
    'onlinePlayFirst',
    'onlinePlaySecond',
    'onlineRandomSide',
    'onlineCreatingGame',
    'onlineJoiningGame',
    'onlineWaitingForOpponent',
    'onlineInviteInstruction',
    'onlineInvitePrivacyNotice',
    'onlineCopyInviteLink',
    'onlineInviteLinkCopied',
    'onlineShareInviteLink',
    'onlinePasteInviteLink',
    'onlineInvalidInvite',
    'onlineInviteExpired',
    'onlineInviteAlreadyUsed',
    'onlineRoomUnavailable',
    'onlineRoomFull',
    'onlineVersionMismatch',
    'onlineServiceUnavailable',
    'onlineSynchronizing',
    'onlineReconnecting',
    'onlineReconnectFailed',
    'onlineRetryConnection',
    'onlineLeaveGame',
    'onlineOpponentJoined',
    'onlineOpponentDisconnected',
    'onlineOpponentLeft',
    'onlineActionRejected',
  ];

  test('online keys are appended to en and zh in identical order', () {
    for (final String locale in <String>['en', 'zh']) {
      final Map<String, Object?> arb = _readArb('intl_$locale.arb');
      final List<String> keys = arb.keys.toList(growable: false);
      final List<String> online = keys
          .where(
            (String key) => key.startsWith('online') && !key.startsWith('@'),
          )
          .toList(growable: false);
      expect(online, expected);
      expect(
        keys.indexOf('onlineFriendGame'),
        keys.indexOf('@remoteNotConnected') + 1,
      );
      for (final String key in expected) {
        final int valueIndex = keys.indexOf(key);
        expect(keys[valueIndex + 1], '@$key');
        final Object? metadata = arb['@$key'];
        expect(metadata, isA<Map<String, Object?>>());
        expect((metadata! as Map<String, Object?>)['description'], isNotEmpty);
      }
    }
  });

  test('no other ARB defines online keys and locales fall back to English', () {
    final Directory directory = Directory('lib/l10n');
    for (final FileSystemEntity entity in directory.listSync()) {
      if (entity is! File ||
          !entity.path.endsWith('.arb') ||
          entity.path.endsWith('intl_en.arb') ||
          entity.path.endsWith('intl_zh.arb')) {
        continue;
      }
      expect(entity.readAsStringSync(), isNot(contains('"onlineFriendGame"')));
    }
    expect(lookupS(const Locale('fr')).onlineFriendGame, 'Online friend game');
  });
}

Map<String, Object?> _readArb(String name) {
  final Object? decoded = jsonDecode(File('lib/l10n/$name').readAsStringSync());
  return decoded! as Map<String, Object?>;
}
