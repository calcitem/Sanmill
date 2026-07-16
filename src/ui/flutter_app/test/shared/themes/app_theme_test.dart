// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// app_theme_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/appearance_settings/models/color_settings.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/themes/app_theme.dart';
import 'package:sanmill/shared/utils/helpers/color_helpers/color_helper.dart';

import '../../helpers/mocks/mock_database.dart';

void main() {
  setUp(() {
    DB.instance = MockDB();
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

    test('app bar titles should be left aligned', () {
      expect(AppTheme.lightThemeData.appBarTheme.centerTitle, isFalse);
      expect(AppTheme.darkThemeData.appBarTheme.centerTitle, isFalse);
    });

    test('light primary remains readable on every light surface container', () {
      final ColorScheme colors = AppTheme.lightThemeData.colorScheme;
      for (final Color background in <Color>[
        colors.surfaceContainerLowest,
        colors.surface,
        colors.surfaceContainerLow,
        colors.surfaceContainer,
        colors.surfaceContainerHigh,
        colors.surfaceContainerHighest,
      ]) {
        expect(
          colorContrastRatio(colors.primary, background),
          greaterThanOrEqualTo(normalTextMinimumContrastRatio),
          reason: 'Primary text must remain readable on $background.',
        );
      }
    });

    test(
      'light tertiary remains readable on every light surface container',
      () {
        final ColorScheme colors = AppTheme.lightThemeData.colorScheme;
        for (final Color background in <Color>[
          colors.surfaceContainerLowest,
          colors.surface,
          colors.surfaceContainerLow,
          colors.surfaceContainer,
          colors.surfaceContainerHigh,
          colors.surfaceContainerHighest,
        ]) {
          expect(
            colorContrastRatio(colors.tertiary, background),
            greaterThanOrEqualTo(normalTextMinimumContrastRatio),
            reason: 'Tertiary text must remain readable on $background.',
          );
        }
      },
    );

    test('good status color follows the readable theme primary', () {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.lightThemeData,
        AppTheme.darkThemeData,
      ]) {
        final AppCustomColors customColors = theme
            .extension<AppCustomColors>()!;
        expect(customColors.good, theme.colorScheme.primary);
        expect(
          colorContrastRatio(
            customColors.good,
            theme.colorScheme.surfaceContainerLow,
          ),
          greaterThanOrEqualTo(normalTextMinimumContrastRatio),
        );
      }
    });

    test('legacy light rule subtitles remain readable on cards', () {
      expect(
        colorContrastRatio(
          AppTheme.listTileSubtitleStyle.color!,
          AppTheme.cardColor,
        ),
        greaterThanOrEqualTo(normalTextMinimumContrastRatio),
      );
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
