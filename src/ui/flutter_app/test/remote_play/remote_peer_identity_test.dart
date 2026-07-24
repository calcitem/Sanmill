// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/remote_play/remote_peer_identity.dart';

void main() {
  group('RemotePeerIdentity terminal label', () {
    test('combines an Android consumer brand with its model', () {
      expect(
        RemotePeerIdentity.labelFromDeviceData(<String, dynamic>{
          'brand': 'xiaomi',
          'manufacturer': 'Xiaomi',
          'model': '2206122SC',
        }, platform: TargetPlatform.android),
        'Xiaomi 2206122SC',
      );
      expect(
        RemotePeerIdentity.labelFromDeviceData(<String, dynamic>{
          'brand': 'google',
          'model': 'Pixel 7',
        }, platform: TargetPlatform.android),
        'Google Pixel 7',
      );
    });

    test('does not repeat a brand already included in the model', () {
      expect(
        RemotePeerIdentity.labelFromDeviceData(<String, dynamic>{
          'brand': 'Xiaomi',
          'model': 'Xiaomi 14',
        }, platform: TargetPlatform.android),
        'Xiaomi 14',
      );
    });

    test('uses Apple commercial model names without custom device names', () {
      expect(
        RemotePeerIdentity.labelFromDeviceData(<String, dynamic>{
          'name': "Alice's iPhone",
          'model': 'iPhone',
          'modelName': 'iPhone 16 Pro',
        }, platform: TargetPlatform.iOS),
        'Apple iPhone 16 Pro',
      );
      expect(
        RemotePeerIdentity.labelFromDeviceData(<String, dynamic>{
          'computerName': "Alice's MacBook",
          'model': 'Mac15,6',
          'modelName': 'MacBook Pro',
        }, platform: TargetPlatform.macOS),
        'Apple MacBook Pro',
      );
    });

    test('uses stable platform labels for desktop terminals', () {
      expect(
        RemotePeerIdentity.labelFromDeviceData(<String, dynamic>{
          'computerName': 'ALICE-PC',
          'productName': 'Windows 11 Pro',
        }, platform: TargetPlatform.windows),
        'Windows 11 Pro',
      );
      expect(
        RemotePeerIdentity.labelFromDeviceData(<String, dynamic>{
          'prettyName': 'Ubuntu 24.04 LTS',
        }, platform: TargetPlatform.linux),
        'Linux Ubuntu 24.04 LTS',
      );
    });

    test('uses a browser brand on web', () {
      expect(
        RemotePeerIdentity.labelFromDeviceData(
          <String, dynamic>{'browserName': 'BrowserName.chrome'},
          platform: TargetPlatform.android,
          isWeb: true,
        ),
        'Web Chrome',
      );
    });
  });
}
