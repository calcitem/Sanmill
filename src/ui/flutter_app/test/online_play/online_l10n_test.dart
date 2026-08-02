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
    'onlineProxySettings',
    'onlineUseProxy',
    'onlineProxyDescription',
    'onlineProxyHost',
    'onlineProxyPort',
    'onlineProxyInvalidHost',
    'onlineProxyInvalidPort',
    'onlineProxySaved',
    'onlineSavedRoomTitle',
    'onlineSavedRoomDescription',
    'onlineContinueWaiting',
    'onlineCancelRoom',
    'onlineNotConfigured',
    'onlineConnectionFailed',
    'onlineServiceAtCapacity',
    'onlineAuthorizationFailed',
    'onlineProtocolError',
    'onlineCreateCapacityTitle',
    'onlineCreateCapacityMessage',
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
    expect(lookupS(const Locale('fr')).onlineFriendGame, 'Cloud match');
  });

  test('Simplified Chinese labels cloud-hosted play explicitly', () {
    expect(lookupS(const Locale('zh')).onlineFriendGame, '云端对战');
  });

  test('cloud failures have distinct English and Chinese guidance', () {
    final S english = lookupS(const Locale('en'));
    final S chinese = lookupS(const Locale('zh'));

    expect(
      english.onlineNotConfigured,
      'Cloud play is not supported in this version.',
    );
    expect(chinese.onlineNotConfigured, '当前版本不支持云端对战。');
    expect(
      english.onlineConnectionFailed,
      'Could not reach the cloud service. Check your network and proxy '
      'settings, then try again.',
    );
    expect(chinese.onlineConnectionFailed, '无法连接云端服务。请检查网络和代理服务器设置后重试。');
    expect(
      english.onlineServiceAtCapacity,
      'Cloud play is temporarily at capacity. Please try again later.',
    );
    expect(chinese.onlineServiceAtCapacity, '云端可用资源暂时已满，请稍后重试。');
    expect(
      english.onlineServiceUnavailable,
      'The cloud service is temporarily unavailable. Please try again later.',
    );
    expect(chinese.onlineServiceUnavailable, '云端服务暂时不可用，请稍后重试。');
    expect(
      english.onlineAuthorizationFailed,
      'Cloud game authorization failed. Reopen the invitation or create a '
      'new game.',
    );
    expect(chinese.onlineAuthorizationFailed, '云端对局授权失败。请重新打开邀请链接或创建新对局。');
    expect(
      english.onlineProtocolError,
      'The cloud service returned an incompatible response. Update the app, '
      'then try again.',
    );
    expect(chinese.onlineProtocolError, '云端服务返回了不兼容的响应。请更新软件后重试。');
  });
}

Map<String, Object?> _readArb(String name) {
  final Object? decoded = jsonDecode(File('lib/l10n/$name').readAsStringSync());
  return decoded! as Map<String, Object?>;
}
