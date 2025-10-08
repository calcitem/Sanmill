import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // This is a workaround to ensure the app is fully closed between tests.
    GameController.instance.engine.shutdown();
  });

  testWidgets('Setup Position FEN Import Test', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle();

    final GameController controller = GameController.instance;

    // 1. Define a FEN with intervention state
    const String fenWithIntervention =
        '**@*O*@**/********/******** w p r 3 6 3 6 0 2 0 0 0 0 0 0 1 i:w-0-|b-2-10.14';

    // 2. Simulate pasting the FEN by calling setFen()
    final bool success = controller.position.setFen(fenWithIntervention);
    print('FEN import success: $success');

    // 3. Verify the state was imported correctly
    expect(success, isTrue);
    expect(controller.position.pieceToRemoveCount[PieceColor.black], 2);

    final String? exportedFen = controller.position.fen;
    print('FEN after import: $exportedFen');
    expect(exportedFen, contains('i:w-0-|b-2-10.14'));
  });
}
