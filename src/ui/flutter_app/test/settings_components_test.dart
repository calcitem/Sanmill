// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/widgets/settings/settings.dart';

void main() {
  testWidgets(
    'SettingsCard uses the Lichess list section structure on Material',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettingsCard(
              title: Text('Display'),
              children: <Widget>[
                ListTile(
                  key: Key('settings_card_first_tile'),
                  title: Text('A'),
                ),
                ListTile(
                  key: Key('settings_card_second_tile'),
                  title: Text('B'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('settings_card_title')), findsOneWidget);
      expect(find.byKey(const Key('settings_card_card')), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const Key('settings_card_title')),
          matching: find.byType(Card),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byKey(const Key('settings_card_first_tile')),
          matching: find.byType(Card),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('settings_card_card')),
          matching: find.byType(Divider),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'SettingsListTile matches Lichess trailing behavior on Material',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(400, 800)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const String value = 'A deliberately long value for layout testing';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                SettingsListTile(titleString: 'Navigation', onTap: () {}),
                SettingsListTile(
                  titleString: 'Theme',
                  trailingString: value,
                  onTap: () {},
                ),
                SettingsListTile.switchTile(
                  titleString: 'Sound',
                  value: true,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byType(Switch), findsOneWidget);

      final Text trailingText = tester.widget<Text>(find.text(value));
      expect(trailingText.maxLines, kSettingsTileTitleMaxLines);
      expect(trailingText.textAlign, TextAlign.end);

      final Finder trailingBoxFinder = find.ancestor(
        of: find.text(value),
        matching: find.byType(ConstrainedBox),
      );
      final ConstrainedBox trailingBox = tester.widget<ConstrainedBox>(
        trailingBoxFinder,
      );
      expect(trailingBox.constraints.maxWidth, 100);
    },
  );
}
