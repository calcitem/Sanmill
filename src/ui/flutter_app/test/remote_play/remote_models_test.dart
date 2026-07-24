// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/remote_play/remote_models.dart';

void main() {
  test('peer Elo round-trips while remaining optional for older peers', () {
    const RemotePeerInfo peer = RemotePeerInfo(
      peerId: 'peer-id',
      label: 'Test phone',
      platform: 'android',
      appVersion: '1.0.0',
      appBuild: '1',
      eloRating: 1630,
    );

    expect(RemotePeerInfo.fromJson(peer.toJson()).eloRating, 1630);
    expect(
      RemotePeerInfo.fromJson(const <String, Object?>{
        'peerId': 'legacy-peer',
        'label': 'Legacy phone',
        'platform': 'android',
        'appVersion': '1.0.0',
        'appBuild': '1',
      }).eloRating,
      isNull,
    );
    expect(
      () => RemotePeerInfo.fromJson(<String, Object?>{
        ...peer.toJson(),
        'eloRating': 99,
      }),
      throwsFormatException,
    );
  });

  test('snapshot preserves takeback eligibility across synchronization', () {
    const RemoteStateSnapshot snapshot = RemoteStateSnapshot(
      revision: 3,
      initialFen: 'start',
      actions: <String>['a1'],
      resultFen: 'start|a1',
      hadTakeBack: true,
    );

    expect(RemoteStateSnapshot.fromJson(snapshot.toJson()).hadTakeBack, isTrue);
    expect(
      RemoteStateSnapshot.fromJson(const <String, Object?>{
        'revision': 0,
        'initialFen': 'start',
        'actions': <String>[],
        'resultFen': 'start',
      }).hadTakeBack,
      isFalse,
    );
  });
}
