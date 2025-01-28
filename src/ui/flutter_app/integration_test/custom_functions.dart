// custom_functions.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/shared/database/database.dart';

/// A map of custom function names to their corresponding implementations.
final Map<String, Future<void> Function(WidgetTester, Map<String, String>)>
    customFunctionMap =
    <String, Future<void> Function(WidgetTester p1, Map<String, String> p2)>{
  'setSkillLevelAndMovingTime':
      (WidgetTester tester, Map<String, String> stepData) async {
    DB().generalSettings = DB().generalSettings.copyWith(
          skillLevel: 5,
        );
    DB().generalSettings = DB().generalSettings.copyWith(
          moveTime: 0,
        );
    await tester.pumpAndSettle();
  },
  // Add more custom functions as needed
};
