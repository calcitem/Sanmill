// SPDX-License-Identifier: GPL-3.0-or-later
// Phase 1 integration smoke-test: verifies that the Rust/FRB bridge loads
// correctly and that tgfHelloWorld() returns the expected prefix.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:sanmill/src/rust/api/simple.dart';
import 'package:sanmill/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  testWidgets('tgfHelloWorld returns TGF greeting', (WidgetTester tester) async {
    final String greeting = tgfHelloWorld();
    expect(greeting, startsWith('hello from TGF'));
  });

  testWidgets('tgfVersion returns non-empty version', (WidgetTester tester) async {
    final String version = tgfVersion();
    expect(version, isNotEmpty);
  });
}
