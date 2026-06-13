// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Regression coverage for the board-image-recognition import path.
//
// The recognition pipeline emits a `Map<int, PieceColor>` that
// [BoardRecognitionDebugView.generateTempFenString] turns into a Mill FEN.
// The riskiest part of porting the feature onto the Rust/TGF stack is that
// this independently-built FEN must be accepted by the native kernel and,
// once loaded through [MillSetupPositionController.pasteFen], must reproduce
// the same piece counts.  These tests pin that contract.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/widgets/board_recognition_debug_view.dart';
import 'package:sanmill/games/mill/mill_setup_position_controller.dart';
import 'package:sanmill/games/mill/mill_types.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/test_native_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  late Directory appDocDir;

  setUpAll(() async {
    appDocDir = Directory.systemTemp.createTempSync('sanmill_recog_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (
          MethodCall methodCall,
        ) async {
          return appDocDir.path;
        });
    await initRustLibForTests();
    await DB.init();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    disposeRustLibForTests();
  });

  MillSetupPositionController newController(NativeMillGameSession session) {
    return MillSetupPositionController(
      session: session,
      ruleSettings: const RuleSettings(),
    )..initFromSession();
  }

  int countColor(Map<int, PieceColor> map, PieceColor color) =>
      map.values.where((PieceColor c) => c == color).length;

  group('Board recognition FEN integrates with the native setup session', () {
    test('empty recognition map yields no FEN', () {
      expect(
        BoardRecognitionDebugView.generateTempFenString(
          const <int, PieceColor>{},
        ),
        isNull,
      );
    });

    test(
      'recognized pieces produce a kernel-valid FEN with matching counts',
      () {
        // A placing-phase position: three white, two black on assorted
        // recognition indices spanning all three rings.
        final Map<int, PieceColor> recognized = <int, PieceColor>{
          0: PieceColor.white,
          8: PieceColor.white,
          16: PieceColor.white,
          5: PieceColor.black,
          13: PieceColor.black,
        };

        final String? fen = BoardRecognitionDebugView.generateTempFenString(
          recognized,
        );
        expect(fen, isNotNull);

        final NativeMillGameSession session = NativeMillGameSession();
        final MillSetupPositionController controller = newController(session);

        expect(
          controller.pasteFen(fen!),
          isTrue,
          reason: 'recognized FEN must be accepted by the Rust kernel: $fen',
        );
        expect(
          controller.countOnBoard(PieceColor.white),
          countColor(recognized, PieceColor.white),
        );
        expect(
          controller.countOnBoard(PieceColor.black),
          countColor(recognized, PieceColor.black),
        );

        session.dispose();
      },
      skip: nativeLibrarySkipReason() != null,
    );
  });
}
