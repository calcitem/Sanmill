// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/online_play/online_deep_links.dart';

void main() {
  const String roomId = 'abcdefghijklmnopqrstuv';
  const String inviteToken = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';

  test('recognizes HTTPS and app-scheme online invites', () {
    expect(
      isPotentialOnlineInviteUri(
        Uri.parse('https://example.com/invite/$roomId#$inviteToken'),
      ),
      isTrue,
    );
    expect(
      isPotentialOnlineInviteUri(
        Uri.parse('sanmill://invite/$roomId#$inviteToken'),
      ),
      isTrue,
    );
  });

  test('does not intercept ordinary shared files or malformed invites', () {
    expect(
      isPotentialOnlineInviteUri(Uri.parse('file:///sdcard/game.pgn')),
      isFalse,
    );
    expect(
      isPotentialOnlineInviteUri(
        Uri.parse('https://example.com/invite/short#$inviteToken'),
      ),
      isFalse,
    );
    expect(
      isPotentialOnlineInviteUri(
        Uri.parse(
          'https://example.com/invite/$roomId'
          '?source=share#$inviteToken',
        ),
      ),
      isFalse,
    );
  });

  test('received invite is emitted and remains pending until consumed', () {
    final OnlineDeepLinkController controller =
        OnlineDeepLinkController.instance;
    final Uri invite = Uri.parse(
      'https://example.com/invite/$roomId#$inviteToken',
    );
    addTearDown(() => controller.consume(invite));

    expectLater(controller.links, emits(invite));
    controller.receive(invite);

    expect(controller.pending, invite);
    expect(controller.takePending(), invite);
    expect(controller.pending, isNull);
  });
}
