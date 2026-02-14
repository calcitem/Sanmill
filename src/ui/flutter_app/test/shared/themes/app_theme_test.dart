// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// app_theme_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/appearance_settings/models/color_settings.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/themes/app_theme.dart';

import '../../helpers/mocks/mock_database.dart';

void main() {
  setUp(() {
    DB.instance = MockDB();
  });

  // ---------------------------------------------------------------------------
  // shouldUseDarkSettingsUi
  // ---------------------------------------------------------------------------
  group('shouldUseDarkSettingsUi', () {
    test('should return true for built-in Dark theme', () {
      const ColorSettings darkTheme = ColorSettings(
        boardLineColor: Color(0xFF878D91),
        darkBackgroundColor: Colors.black,
        boardBackgroundColor: Colors.black,
        drawerColor: Colors.black,
      );

      expect(AppTheme.shouldUseDarkSettingsUi(darkTheme), isTrue);
    });

    test('should return true for built-in Midnight Blue theme', () {
      const ColorSettings midnightBlue = ColorSettings(
        boardBackgroundColor: Color(0xFF162447),
        darkBackgroundColor: Color(0xFF1f4068),
        drawerColor: Color(0xFF1f4068),
      );

      expect(AppTheme.shouldUseDarkSettingsUi(midnightBlue), isTrue);
    });

    test('should return true for Dark Mystery theme', () {
      const ColorSettings darkMystery = ColorSettings(
        darkBackgroundColor: Color(0xFF0F0F0F),
        drawerColor: Color(0xFF0F0F0F),
      );

      expect(AppTheme.shouldUseDarkSettingsUi(darkMystery), isTrue);
    });

    test('should return false for default light theme', () {
      const ColorSettings lightTheme = ColorSettings(); // Defaults

      expect(AppTheme.shouldUseDarkSettingsUi(lightTheme), isFalse);
    });

    test('should return false for pastel theme', () {
      const ColorSettings pastel = ColorSettings(
        boardBackgroundColor: Color(0xFFf7bacf),
        darkBackgroundColor: Color(0xFFefc3e6),
        drawerColor: Color(0xFFa95c5c),
      );

      expect(AppTheme.shouldUseDarkSettingsUi(pastel), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // colorThemes map
  // ---------------------------------------------------------------------------
  group('colorThemes', () {
    test('should contain entries for all ColorTheme values', () {
      for (final ColorTheme theme in ColorTheme.values) {
        if (theme == ColorTheme.current) {
          continue; // 'current' is not in the map
        }
        expect(
          AppTheme.colorThemes.containsKey(theme),
          isTrue,
          reason: 'Missing colorThemes entry for $theme',
        );
      }
    });

    test('light theme should have default values', () {
      final ColorSettings? light = AppTheme.colorThemes[ColorTheme.light];
      expect(light, isNotNull);
      expect(light, const ColorSettings());
    });

    test('dark theme should have black background', () {
      final ColorSettings? dark = AppTheme.colorThemes[ColorTheme.dark];
      expect(dark, isNotNull);
      expect(dark!.darkBackgroundColor, Colors.black);
      expect(dark.boardBackgroundColor, Colors.black);
    });

    test('monochrome theme should use only black and white', () {
      final ColorSettings? mono = AppTheme.colorThemes[ColorTheme.monochrome];
      expect(mono, isNotNull);
      expect(mono!.whitePieceColor, Colors.white);
      expect(mono.blackPieceColor, Colors.black);
      expect(mono.boardLineColor, Colors.black);
      expect(mono.boardBackgroundColor, Colors.white);
    });
  });

  // ---------------------------------------------------------------------------
  // updateCustomTheme
  // ---------------------------------------------------------------------------
  group('updateCustomTheme', () {
    test('should update the custom theme in the map', () {
      const ColorSettings custom = ColorSettings(
        boardLineColor: Colors.purple,
        darkBackgroundColor: Colors.indigo,
      );

      AppTheme.updateCustomTheme(custom);

      expect(
        AppTheme.colorThemes[ColorTheme.custom]?.boardLineColor,
        Colors.purple,
      );
      expect(
        AppTheme.colorThemes[ColorTheme.custom]?.darkBackgroundColor,
        Colors.indigo,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Static theme data
  // ---------------------------------------------------------------------------
  group('Theme data', () {
    test('lightThemeData should be Brightness.light', () {
      expect(AppTheme.lightThemeData.brightness, Brightness.light);
    });

    test('darkThemeData should be Brightness.dark', () {
      expect(AppTheme.darkThemeData.brightness, Brightness.dark);
    });

    test('lightThemeData should use Material 3', () {
      expect(AppTheme.lightThemeData.useMaterial3, isTrue);
    });

    test('darkThemeData should use Material 3', () {
      expect(AppTheme.darkThemeData.useMaterial3, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // buildAccessibleSettingsDarkTheme
  // ---------------------------------------------------------------------------
  group('buildAccessibleSettingsDarkTheme', () {
    test('should return a dark theme for dark color settings', () {
      const ColorSettings darkColors = ColorSettings(
        darkBackgroundColor: Colors.black,
        boardBackgroundColor: Colors.black,
        drawerColor: Colors.black,
      );

      final ThemeData theme = AppTheme.buildAccessibleSettingsDarkTheme(
        darkColors,
      );

      expect(theme.brightness, Brightness.dark);
      expect(theme.useMaterial3, isTrue);
    });

    test('should return a dark theme for midnight blue settings', () {
      const ColorSettings midnightBlue = ColorSettings(
        boardBackgroundColor: Color(0xFF162447),
        darkBackgroundColor: Color(0xFF1f4068),
        drawerColor: Color(0xFF1f4068),
      );

      final ThemeData theme = AppTheme.buildAccessibleSettingsDarkTheme(
        midnightBlue,
      );

      expect(theme.brightness, Brightness.dark);
    });
  });

  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------
  group('AppTheme constants', () {
    test('border colors should be defined', () {
      expect(AppTheme.whitePieceBorderColor, isNotNull);
      expect(AppTheme.blackPieceBorderColor, isNotNull);
    });

    test('font sizes should be positive', () {
      expect(AppTheme.smallFontSize, greaterThan(0));
      expect(AppTheme.defaultFontSize, greaterThan(0));
      expect(AppTheme.largeFontSize, greaterThan(0));
      expect(AppTheme.extraLargeFontSize, greaterThan(0));
      expect(AppTheme.hugeFontSize, greaterThan(0));
      expect(AppTheme.giantFontSize, greaterThan(0));
    });

    test('font sizes should increase in order', () {
      expect(AppTheme.smallFontSize, lessThan(AppTheme.defaultFontSize));
      expect(AppTheme.defaultFontSize, lessThan(AppTheme.largeFontSize));
      expect(AppTheme.largeFontSize, lessThan(AppTheme.extraLargeFontSize));
      expect(AppTheme.extraLargeFontSize, lessThan(AppTheme.hugeFontSize));
      expect(AppTheme.hugeFontSize, lessThan(AppTheme.giantFontSize));
    });

    test('board margin should be positive', () {
      expect(AppTheme.boardMargin, greaterThan(0));
    });
  });
}
