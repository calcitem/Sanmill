// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/general_settings/widgets/general_settings_page.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SoundManager previousSoundManager;
  late _PreviewTrackingAudios previewTrackingAudios;

  setUp(() {
    DB.instance = _GeneralSettingsPageTestDb();
    previousSoundManager = SoundManager.instance;
    previewTrackingAudios = _PreviewTrackingAudios();
    SoundManager.instance = previewTrackingAudios;
  });

  tearDown(() {
    SoundManager.instance = previousSoundManager;
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

  testWidgets('sound themes provide previews without changing selection', (
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

    final Finder soundTheme = find.byKey(
      const Key('general_settings_page_settings_card_play_sounds_sound_theme'),
    );
    await tester.scrollUntilVisible(
      soundTheme,
      300,
      scrollable: find.descendant(
        of: find.byKey(const Key('settings_list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(soundTheme);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Preview sound'), findsNWidgets(3));
    expect(
      find.byKey(const Key('sound_theme_modal_preview_event')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sound_theme_modal_preview_ball')), findsOne);
    expect(find.byKey(const Key('sound_theme_modal_preview_liquid')), findsOne);
    expect(find.byKey(const Key('sound_theme_modal_preview_wood')), findsOne);

    await tester.tap(find.byKey(const Key('sound_theme_modal_preview_event')));
    await tester.pumpAndSettle();
    for (final String event in <String>[
      'place',
      'select',
      'mill',
      'remove',
      'illegal',
    ]) {
      expect(
        find.byKey(Key('sound_theme_modal_preview_event_$event')),
        findsWidgets,
      );
    }
    final Finder millEvent = find.ancestor(
      of: find.byKey(const Key('sound_theme_modal_preview_event_mill')),
      matching: find.byType(InkWell),
    );
    expect(millEvent, findsWidgets);
    await tester.tap(millEvent.last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sound_theme_modal_preview_liquid')));
    await tester.pump();

    expect(previewTrackingAudios.previewedTheme, SoundTheme.liquid);
    expect(previewTrackingAudios.previewedSound, Sound.mill);
    expect(DB().generalSettings.soundTheme, SoundTheme.ball);
  });
}

class _PreviewTrackingAudios extends MockAudios {
  SoundTheme? previewedTheme;
  Sound? previewedSound;

  @override
  Future<void> playSoundThemePreview(
    SoundTheme theme, {
    Sound sound = Sound.place,
  }) async {
    previewedTheme = theme;
    previewedSound = sound;
  }
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
