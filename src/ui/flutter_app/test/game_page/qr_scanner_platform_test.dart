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

  group('QR camera watchdog', () {
    test('does not restart before the first decoder callback', () {
      expect(
        qrCameraWatchdogShouldReinitialize(
          hasReceivedScanActivity: false,
          isBusy: false,
          cameraAvailable: true,
          isReinitializing: false,
          idleFor: const Duration(minutes: 1),
          threshold: const Duration(seconds: 5),
        ),
        isFalse,
      );
    });

    test('restarts an idle camera after decoder activity has started', () {
      expect(
        qrCameraWatchdogShouldReinitialize(
          hasReceivedScanActivity: true,
          isBusy: false,
          cameraAvailable: true,
          isReinitializing: false,
          idleFor: const Duration(seconds: 6),
          threshold: const Duration(seconds: 5),
        ),
        isTrue,
      );
    });

    test('does not restart while scan handling is busy', () {
      expect(
        qrCameraWatchdogShouldReinitialize(
          hasReceivedScanActivity: true,
          isBusy: true,
          cameraAvailable: true,
          isReinitializing: false,
          idleFor: const Duration(seconds: 6),
          threshold: const Duration(seconds: 5),
        ),
        isFalse,
      );
    });
  });
}
