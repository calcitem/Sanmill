// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/general_settings/widgets/general_settings_page.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DB.instance = _GeneralSettingsPageTestDb();
  });

  tearDown(() {
    DB.instance = null;
  });

  testWidgets('desktop settings expose screen-reader support', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        locale: const Locale('en'),
        home: const GeneralSettingsPage(),
      ),
    );
    await tester.pump();

    await tester.drag(
      find.byKey(const Key('settings_list')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const Key('general_settings_page_settings_card_accessibility'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const Key(
          'general_settings_page_settings_card_accessibility_screen_reader_support',
        ),
      ),
      findsOneWidget,
    );
  });
}

class _GeneralSettingsPageTestDb extends MockDB {
  _GeneralSettingsPageTestDb()
    : _generalSettingsListenable = ValueNotifier<Box<GeneralSettings>>(
        _SettingsBox<GeneralSettings>(
          DB.generalSettingsKey,
          const GeneralSettings(),
        ),
      );

  final ValueNotifier<Box<GeneralSettings>> _generalSettingsListenable;

  @override
  ValueListenable<Box<GeneralSettings>> get listenGeneralSettings =>
      _generalSettingsListenable;
}

class _SettingsBox<T> extends Fake implements Box<T> {
  _SettingsBox(this.settingsKey, this.value);

  final String settingsKey;
  final T value;

  @override
  T? get(dynamic key, {T? defaultValue}) =>
      key == settingsKey ? value : defaultValue;
}
