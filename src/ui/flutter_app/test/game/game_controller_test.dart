import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';
import '../helpers/test_mills.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Define the MethodChannel to be mocked
  const MethodChannel engineChannel =
      MethodChannel("com.calcitem.sanmill/engine");

  setUp(() {
    // Use the new API to set up mock handlers for MethodChannel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'send':
          // Handle the 'send' method
          return null; // Return a success response
        case 'shutdown':
          // Handle the 'shutdown' method
          return null; // Return a success response
        case 'startup':
          // Handle the 'startup' method
          return null; // Return a success response
        case 'read':
          // Simulate a response for the 'read' method
          return 'bestmove d2';
        case 'isThinking':
          // Simulate the 'isThinking' method response
          return false;
        default:
          // For unhandled methods, return null
          return null;
      }
    });
  });

  tearDown(() {
    // Use the new API to remove the mock handler
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  group("GameController", () {
    test("New game should have the same GameMode", () async {
      const GameMode gameMode = GameMode.humanVsAi;

      // Initialize the test
      DB.instance = MockDB();
      final GameController controller = GameController();

      controller.gameInstance.gameMode = gameMode;

      // Reset the game
      controller.reset();

      expect(controller.gameInstance.gameMode, gameMode);
    });

    test("Import should clear the focus", () async {
      // Initialize the test
      DB.instance = MockDB();
      SoundManager.instance = MockAudios();
      final GameController controller = GameController();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;

      // Import a game
      ImportService.import(const WinLessThanThreeGame().moveList);

      expect(GameController().gameInstance.focusIndex, isNull);
    });
  });
}
