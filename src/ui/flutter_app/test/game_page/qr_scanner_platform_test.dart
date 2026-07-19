// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/widgets/qr_scanner_page.dart';

void main() {
  group('QR scanner platform support', () {
    test('uses a live camera on Android, iOS, and macOS', () {
      for (final TargetPlatform platform in <TargetPlatform>[
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ]) {
        expect(
          qrScannerUsesLiveCamera(platform: platform, isWeb: false),
          isTrue,
        );
      }
    });

    test('keeps image-based scanning on other desktop platforms', () {
      for (final TargetPlatform platform in <TargetPlatform>[
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          qrScannerUsesLiveCamera(platform: platform, isWeb: false),
          isFalse,
        );
      }
    });

    test('does not request a live camera on web', () {
      expect(
        qrScannerUsesLiveCamera(platform: TargetPlatform.android, isWeb: true),
        isFalse,
      );
    });
  });
}
