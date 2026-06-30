// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// appearance_settings_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../shared/widgets/settings/settings.dart';
import '../../game_page/services/mill.dart';
import '../../generated/assets/assets.gen.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/config/constants.dart';
import '../../shared/database/database.dart';
import '../../shared/services/language_locale_mapping.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../models/color_settings.dart';
import '../models/display_settings.dart';
import './../../game_page/services/painters/painters.dart';
import 'piece_effect_selection_page.dart';
import 'theme_selection_page.dart';

part 'package:sanmill/appearance_settings/widgets/modals/point_painting_style_modal.dart';
part 'package:sanmill/appearance_settings/widgets/pickers/background_image_picker.dart';
part 'package:sanmill/appearance_settings/widgets/pickers/board_image_picker.dart';
part 'package:sanmill/appearance_settings/widgets/pickers/image_crop_page.dart';
part 'package:sanmill/appearance_settings/widgets/pickers/language_picker.dart';
part 'package:sanmill/appearance_settings/widgets/pickers/piece_image_picker.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/animation_duration_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/board_boarder_line_width_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/board_corner_radius_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/board_inner_ring_size_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/board_inner_line_width_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/board_top_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/font_size_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/piece_width_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/point_width_slider.dart';

class _BoardStylePreview extends StatelessWidget {
  const _BoardStylePreview({required this.colors});

  final ColorSettings colors;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ThemePreviewBoard(colors: colors),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  void setBoardCornerRadius(BuildContext context) => showModalBottomSheet(
    context: context,
    builder: (_) => const _BoardCornerRadiusSlider(),
  );

  void setBoardBorderLineWidth(BuildContext context) => showModalBottomSheet(
    context: context,
    builder: (_) => const _BoardBorderLineWidthSlider(),
  );

  void setBoardInnerLineWidth(BuildContext context) => showModalBottomSheet(
    context: context,
    builder: (_) => const _BoardInnerLineWidthSlider(),
  );

  void setBoardInnerRingSize(BuildContext context) => showModalBottomSheet(
    context: context,
    builder: (_) => const _BoardInnerRingSizeSlider(),
  );

  void setPointPaintingStyle(
    BuildContext context,
    DisplaySettings displaySettings,
  ) {
    dynamic callback(PointPaintingStyle? pointPaintingStyle) {
      Navigator.pop(context);
      DB().displaySettings = displaySettings.copyWith(
        pointPaintingStyle: pointPaintingStyle ?? PointPaintingStyle.none,
      );

      logger.t(
        "[config] pointPaintingStyle: ${pointPaintingStyle ?? PointPaintingStyle.none}",
      );
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _PointPaintingStyleModal(
        pointPaintingStyle: displaySettings.pointPaintingStyle,
        onPointPaintingStyleChanged: callback,
      ),
    );
  }

  void setPointWidth(BuildContext context) => showModalBottomSheet(
    context: context,
    builder: (_) => const _PointWidthSlider(),
  );

  void setPieceWidth(BuildContext context) => showModalBottomSheet(
    context: context,
    builder: (_) => const _PieceWidthSlider(),
  );

  void setFontSize(BuildContext context) => showModalBottomSheet(
    context: context,
    builder: (_) => const _FontSizeSlider(),
  );

  void setBoardTop(BuildContext context) => showModalBottomSheet(
    context: context,
    builder: (_) => const _BoardTopSlider(),
  );

  void setAnimationDuration(BuildContext context) => showModalBottomSheet(
    context: context,
    builder: (_) => const _AnimationDurationSlider(),
  );

  Future<void> setPlaceEffectAnimation(BuildContext context) async {
    final EffectItem? selectedEffect = await Navigator.push<EffectItem>(
      context,
      MaterialPageRoute<EffectItem>(
        builder: (BuildContext context) =>
            const PieceEffectSelectionPage(moveType: MoveType.place),
      ),
    );

    if (selectedEffect != null) {
      DB().displaySettings = DB().displaySettings.copyWith(
        placeEffectAnimation: selectedEffect.name,
      );

      logger.t(
        "[config] Selected PlaceEffectAnimation: ${selectedEffect.name}",
      );
    }
  }

  Future<void> setRemoveEffectAnimation(BuildContext context) async {
    final EffectItem? selectedEffect = await Navigator.push<EffectItem>(
      context,
      MaterialPageRoute<EffectItem>(
        builder: (BuildContext context) =>
            const PieceEffectSelectionPage(moveType: MoveType.move),
      ),
    );

    if (selectedEffect != null) {
      DB().displaySettings = DB().displaySettings.copyWith(
        removeEffectAnimation: selectedEffect.name,
      );

      logger.t(
        "[config] Selected RemoveEffectAnimation: ${selectedEffect.name}",
      );
    }
  }

  void setBackgroundImage(BuildContext context) => showModalBottomSheet(
    context: context,
    builder: (_) => const _BackgroundImagePicker(),
  );

  void setBoardImage(BuildContext context) => showModalBottomSheet(
    context: context,
    builder: (_) => const _BoardImagePicker(),
  );

  void setPieceImage(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const _PieceImageSelectionPage(),
      ),
    );
  }

  Future<void> importColorSettings(BuildContext context) async {
    final String strImport = S.of(context).import;
    final String strClose = S.of(context).close;
    final String strImported = S.of(context).imported;
    final String strInvalidFormat = S.of(context).pleaseCopyJsonToClipboard;

    // Get clipboard data
    final ClipboardData? data = await Clipboard.getData('text/plain');
    if (data == null || data.text == null) {
      rootScaffoldMessengerKey.currentState!.showSnackBar(
        SnackBar(
          key: const Key('import_color_settings_invalid_format_snackbar'),
          content: Text(strInvalidFormat),
        ),
      );
      return;
    }

    // Check if clipboard content contains only ASCII characters
    final String clipboardText = data.text!;
    if (!isAscii(clipboardText)) {
      // If content is not ASCII, show a SnackBar with the invalid format message
      rootScaffoldMessengerKey.currentState!.showSnackBar(
        SnackBar(
          key: const Key(
            'import_color_settings_invalid_format_snackbar_non_ascii',
          ),
          content: Text(strInvalidFormat),
        ),
      );
      return;
    }

    try {
      // Try to parse the clipboard content as JSON
      final Map<String, dynamic> json =
          jsonDecode(clipboardText) as Map<String, dynamic>;
      final Widget importButton = TextButton(
        key: const Key('import_color_settings_import_button'),
        child: Text(
          strImport,
          style: TextStyle(
            fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
          ),
        ),
        onPressed: () async {
          final ColorSettings colorSettings = ColorSettings.fromJson(json);
          DB().colorSettings = colorSettings;

          rootScaffoldMessengerKey.currentState!.showSnackBarClear(strImported);

          if (!context.mounted) {
            return;
          }
          Navigator.pop(context);
        },
      );

      final Widget closeButton = TextButton(
        key: const Key('import_color_settings_close_button'),
        child: Text(
          strClose,
          style: TextStyle(
            fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
          ),
        ),
        onPressed: () => Navigator.pop(context),
      );

      final AlertDialog alert = AlertDialog(
        key: const Key('import_color_settings_alert_dialog'),
        title: Text(
          strImport,
          key: const Key('import_color_settings_alert_dialog_title'),
          style: TextStyle(
            fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
          ),
        ),
        // Show content if it's valid JSON
        content: Text(
          clipboardText,
          key: const Key('import_color_settings_alert_dialog_content'),
          textDirection: TextDirection.ltr,
        ),
        actions: <Widget>[importButton, closeButton],
        scrollable: true,
      );

      if (!context.mounted) {
        return;
      }

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return alert;
        },
      );
    } catch (e) {
      // If parsing fails (not valid JSON), show a SnackBar with the invalid format message
      rootScaffoldMessengerKey.currentState!.showSnackBar(
        SnackBar(
          key: const Key(
            'import_color_settings_invalid_format_snackbar_parse_error',
          ),
          content: Text(strInvalidFormat),
        ),
      );
    }
  }

  // Function to check if a string contains only ASCII characters
  bool isAscii(String text) {
    return text.codeUnits.every((int unit) => unit <= 127);
  }

  void exportColorSettings(BuildContext context) {
    final String json = jsonEncode(DB().colorSettings.toJson());
    final String content = json;
    final Widget copyButton = TextButton(
      key: const Key('export_color_settings_copy_button'),
      child: Text(
        S.of(context).copy,
        style: TextStyle(
          fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
        ),
      ),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: content));
        rootScaffoldMessengerKey.currentState!.showSnackBarClear(
          S.of(context).copiedToClipboard,
        );
        Navigator.pop(context);
      },
    );

    final Widget closeButton = TextButton(
      key: const Key('export_color_settings_close_button'),
      child: Text(
        S.of(context).close,
        style: TextStyle(
          fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
        ),
      ),
      onPressed: () => Navigator.pop(context),
    );

    final AlertDialog alert = AlertDialog(
      key: const Key('export_color_settings_alert_dialog'),
      title: Text(
        S.of(context).export,
        key: const Key('export_color_settings_alert_dialog_title'),
        style: TextStyle(
          fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
        ),
      ),
      content: Text(
        content,
        key: const Key('export_color_settings_alert_dialog_content'),
        textDirection: TextDirection.ltr,
      ),
      actions: <Widget>[copyButton, closeButton],
      scrollable: true,
    );

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  void langCallback(
    BuildContext context,
    DisplaySettings displaySettings, [
    Locale? locale,
  ]) {
    DB().displaySettings = displaySettings.copyWith(locale: locale);

    logger.t("[config] locale = $locale");
  }

  Future<void> _setTheme(
    BuildContext context,
    ColorSettings colorSettings,
  ) async {
    // Navigate to the theme selection page instead of showing modal
    final ColorTheme? selectedTheme = await Navigator.push<ColorTheme>(
      context,
      MaterialPageRoute<ColorTheme>(
        builder: (BuildContext context) =>
            const ThemeSelectionPage(currentTheme: ColorTheme.current),
      ),
    );

    if (selectedTheme == null || selectedTheme == ColorTheme.current) {
      return; // No theme selected or current theme selected
    }

    // Update the color settings with the selected theme
    DB().colorSettings = colorSettings.copyWith(
      boardLineColor: AppTheme.colorThemes[selectedTheme]!.boardLineColor,
      darkBackgroundColor:
          AppTheme.colorThemes[selectedTheme]!.darkBackgroundColor,
      boardBackgroundColor:
          AppTheme.colorThemes[selectedTheme]!.boardBackgroundColor,
      whitePieceColor: AppTheme.colorThemes[selectedTheme]!.whitePieceColor,
      blackPieceColor: AppTheme.colorThemes[selectedTheme]!.blackPieceColor,
      pieceHighlightColor:
          AppTheme.colorThemes[selectedTheme]!.pieceHighlightColor,
      capturablePieceHighlightColor:
          AppTheme.colorThemes[selectedTheme]!.capturablePieceHighlightColor,
      messageColor: AppTheme.colorThemes[selectedTheme]!.messageColor,
      mainToolbarBackgroundColor:
          AppTheme.colorThemes[selectedTheme]!.mainToolbarBackgroundColor,
      mainToolbarIconColor:
          AppTheme.colorThemes[selectedTheme]!.mainToolbarIconColor,
      navigationToolbarBackgroundColor:
          AppTheme.colorThemes[selectedTheme]!.navigationToolbarBackgroundColor,
      navigationToolbarIconColor:
          AppTheme.colorThemes[selectedTheme]!.navigationToolbarIconColor,
      analysisToolbarBackgroundColor:
          AppTheme.colorThemes[selectedTheme]!.analysisToolbarBackgroundColor,
      analysisToolbarIconColor:
          AppTheme.colorThemes[selectedTheme]!.analysisToolbarIconColor,
      annotationToolbarBackgroundColor:
          AppTheme.colorThemes[selectedTheme]!.annotationToolbarBackgroundColor,
      annotationToolbarIconColor:
          AppTheme.colorThemes[selectedTheme]!.annotationToolbarIconColor,
    );
  }

  Widget _buildBoardStyleSettings(
    BuildContext context,
    Box<ColorSettings> box,
    _,
  ) {
    final ColorSettings colorSettings = box.get(
      DB.colorSettingsKey,
      defaultValue: const ColorSettings(),
    )!;

    return Column(
      key: const Key('appearance_settings_page_style_settings_column'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _BoardStylePreview(colors: colorSettings),
        SettingsCard(
          key: const Key('appearance_settings_page_theme_settings_card'),
          title: Text(
            S.of(context).board,
            key: const Key('theme_settings_card_title'),
          ),
          children: <Widget>[
            SettingsListTile(
              key: const Key('color_settings_card_theme_settings_list_tile'),
              leading: const Icon(Icons.dashboard_outlined),
              titleString: S.of(context).board,
              trailingString: _activeBoardThemeLabel(context, colorSettings),
              onTap: () => _setTheme(context, colorSettings),
            ),
            SettingsListTile(
              key: const Key(
                'display_settings_card_piece_image_settings_list_tile',
              ),
              leading: const Icon(Icons.radio_button_unchecked),
              titleString: S.of(context).pieceSet,
              onTap: () => setPieceImage(context),
            ),
            ValueListenableBuilder<Box<DisplaySettings>>(
              key: const Key(
                'display_settings_card_notations_shown_value_listenable_builder',
              ),
              valueListenable: DB().listenDisplaySettings,
              builder:
                  (
                    BuildContext context,
                    Box<DisplaySettings> box,
                    Widget? child,
                  ) {
                    final DisplaySettings displaySettings = box.get(
                      DB.displaySettingsKey,
                      defaultValue: const DisplaySettings(),
                    )!;
                    return SettingsListTile.switchTile(
                      key: const Key(
                        'display_settings_card_notations_shown_switch_tile',
                      ),
                      leading: const Icon(Icons.location_on_outlined),
                      value: displaySettings.isNotationsShown,
                      onChanged: (bool val) => DB().displaySettings =
                          displaySettings.copyWith(isNotationsShown: val),
                      titleString: S.of(context).isNotationsShown,
                    );
                  },
            ),
            ValueListenableBuilder<Box<DisplaySettings>>(
              key: const Key(
                'display_settings_card_piece_animation_value_listenable_builder',
              ),
              valueListenable: DB().listenDisplaySettings,
              builder:
                  (
                    BuildContext context,
                    Box<DisplaySettings> box,
                    Widget? child,
                  ) {
                    final DisplaySettings displaySettings = box.get(
                      DB.displaySettingsKey,
                      defaultValue: const DisplaySettings(),
                    )!;
                    return SettingsListTile.switchTile(
                      key: const Key(
                        'display_settings_card_piece_pick_up_animation_enabled_switch_tile',
                      ),
                      leading: const Icon(Icons.animation_outlined),
                      value: displaySettings.isPiecePickUpAnimationEnabled,
                      onChanged: (bool val) =>
                          DB().displaySettings = displaySettings.copyWith(
                            isPiecePickUpAnimationEnabled: val,
                          ),
                      titleString: S.of(context).enablePiecePickUpAnimation,
                    );
                  },
            ),
            SettingsListTile(
              key: const Key(
                'display_settings_card_board_image_settings_list_tile',
              ),
              leading: const Icon(Icons.image_outlined),
              titleString: S.of(context).boardImage,
              onTap: () => setBoardImage(context),
            ),
            SettingsListTile(
              key: const Key(
                'display_settings_card_background_image_settings_list_tile',
              ),
              leading: const Icon(Icons.wallpaper_outlined),
              titleString: S.of(context).backgroundImage,
              onTap: () => setBackgroundImage(context),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildColorTuningSettings(
    BuildContext context,
    Box<ColorSettings> box,
    _,
  ) {
    final ColorSettings colorSettings = box.get(
      DB.colorSettingsKey,
      defaultValue: const ColorSettings(),
    )!;

    return Column(
      key: const Key('appearance_settings_page_color_tuning_column'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsCard(
          key: const Key('appearance_settings_page_board_color_settings_card'),
          title: Text(
            S.of(context).board,
            key: const Key('board_color_settings_card_title'),
          ),
          children: <Widget>[
            SettingsListTile.color(
              key: const Key(
                'color_settings_card_board_color_settings_list_tile',
              ),
              titleString: S.of(context).boardColor,
              value: DB().colorSettings.boardBackgroundColor,
              onChanged: (Color val) => DB().colorSettings = colorSettings
                  .copyWith(boardBackgroundColor: val),
            ),
            SettingsListTile.color(
              key: const Key(
                'color_settings_card_background_color_settings_list_tile',
              ),
              titleString: S.of(context).backgroundColor,
              value: DB().colorSettings.darkBackgroundColor,
              onChanged: (Color val) => DB().colorSettings = colorSettings
                  .copyWith(darkBackgroundColor: val),
            ),
            SettingsListTile.color(
              key: const Key(
                'color_settings_card_line_color_settings_list_tile',
              ),
              titleString: S.of(context).lineColor,
              value: DB().colorSettings.boardLineColor,
              onChanged: (Color val) => DB().colorSettings = colorSettings
                  .copyWith(boardLineColor: val),
            ),
          ],
        ),
        SettingsCard(
          key: const Key('appearance_settings_page_piece_settings_card'),
          title: Text(
            S.of(context).pieces,
            key: const Key('piece_settings_card_title'),
          ),
          children: <Widget>[
            SettingsListTile.color(
              key: const Key(
                'color_settings_card_white_piece_color_settings_list_tile',
              ),
              titleString: S.of(context).whitePieceColor,
              value: DB().colorSettings.whitePieceColor,
              onChanged: (Color val) => DB().colorSettings = colorSettings
                  .copyWith(whitePieceColor: val),
            ),
            SettingsListTile.color(
              key: const Key(
                'color_settings_card_black_piece_color_settings_list_tile',
              ),
              titleString: S.of(context).blackPieceColor,
              value: DB().colorSettings.blackPieceColor,
              onChanged: (Color val) => DB().colorSettings = colorSettings
                  .copyWith(blackPieceColor: val),
            ),
            SettingsListTile.color(
              key: const Key(
                'color_settings_card_piece_highlight_color_settings_list_tile',
              ),
              titleString: S.of(context).pieceHighlightColor,
              value: DB().colorSettings.pieceHighlightColor,
              onChanged: (Color val) => DB().colorSettings = colorSettings
                  .copyWith(pieceHighlightColor: val),
            ),
            SettingsListTile.color(
              key: const Key(
                'color_settings_card_capturable_piece_highlight_color_settings_list_tile',
              ),
              titleString: S.of(context).capturablePieceHighlightColor,
              value: DB().colorSettings.capturablePieceHighlightColor,
              onChanged: (Color val) => DB().colorSettings = colorSettings
                  .copyWith(capturablePieceHighlightColor: val),
            ),
          ],
        ),
        SettingsCard(
          key: const Key(
            'appearance_settings_page_advanced_color_settings_card',
          ),
          title: Text(
            S.of(context).advanced,
            key: const Key('advanced_color_settings_card_title'),
          ),
          children: <Widget>[
            SettingsListTile.color(
              key: const Key(
                'color_settings_card_message_color_settings_list_tile',
              ),
              titleString: S.of(context).messageColor,
              value: DB().colorSettings.messageColor,
              onChanged: (Color val) => DB().colorSettings = colorSettings
                  .copyWith(messageColor: val),
            ),
            SettingsListTile.color(
              key: const Key(
                'color_settings_card_main_toolbar_background_color_settings_list_tile',
              ),
              titleString: S.of(context).mainToolbarBackgroundColor,
              value: DB().colorSettings.mainToolbarBackgroundColor,
              onChanged: (Color val) => DB().colorSettings = colorSettings
                  .copyWith(mainToolbarBackgroundColor: val),
            ),
            SettingsListTile.color(
              key: const Key(
                'color_settings_card_main_toolbar_icon_color_settings_list_tile',
              ),
              titleString: S.of(context).mainToolbarIconColor,
              value: DB().colorSettings.mainToolbarIconColor,
              onChanged: (Color val) => DB().colorSettings = colorSettings
                  .copyWith(mainToolbarIconColor: val),
            ),
            SettingsListTile.color(
              key: const Key(
                'color_settings_card_navigation_toolbar_background_color_settings_list_tile',
              ),
              titleString: S.of(context).navigationToolbarBackgroundColor,
              value: DB().colorSettings.navigationToolbarBackgroundColor,
              onChanged: (Color val) => DB().colorSettings = colorSettings
                  .copyWith(navigationToolbarBackgroundColor: val),
            ),
            SettingsListTile.color(
              key: const Key(
                'color_settings_card_navigation_toolbar_icon_color_settings_list_tile',
              ),
              titleString: S.of(context).navigationToolbarIconColor,
              value: DB().colorSettings.navigationToolbarIconColor,
              onChanged: (Color val) => DB().colorSettings = colorSettings
                  .copyWith(navigationToolbarIconColor: val),
            ),
            SettingsListTile.color(
              key: const Key(
                'color_settings_card_annotation_toolbar_background_color_settings_list_tile',
              ),
              titleString: S.of(context).annotationToolbarBackgroundColor,
              value: DB().colorSettings.annotationToolbarBackgroundColor,
              onChanged: (Color val) => DB().colorSettings = colorSettings
                  .copyWith(annotationToolbarBackgroundColor: val),
            ),
            SettingsListTile.color(
              key: const Key(
                'color_settings_card_annotation_toolbar_icon_color_settings_list_tile',
              ),
              titleString: S.of(context).annotationToolbarIconColor,
              value: DB().colorSettings.annotationToolbarIconColor,
              onChanged: (Color val) => DB().colorSettings = colorSettings
                  .copyWith(annotationToolbarIconColor: val),
            ),
            SettingsListTile(
              key: const Key(
                'color_settings_card_import_color_settings_list_tile',
              ),
              titleString: S.of(context).importColorSettings,
              onTap: () => importColorSettings(context),
            ),
            SettingsListTile(
              key: const Key(
                'color_settings_card_export_color_settings_list_tile',
              ),
              titleString: S.of(context).exportColorSettings,
              onTap: () => exportColorSettings(context),
            ),
          ],
        ),
      ],
    );
  }

  void _selectLanguage(BuildContext context, DisplaySettings displaySettings) {
    showDialog<Locale?>(
      context: context,
      builder: (BuildContext context) =>
          _LanguagePicker(currentLanguageLocale: displaySettings.locale),
    ).then((Locale? newLocale) {
      if (!context.mounted) {
        return;
      }
      if (displaySettings.locale != newLocale) {
        langCallback(context, displaySettings, newLocale);
      }
    });
  }

  String _themeModeLabel(BuildContext context, AppThemeMode themeMode) {
    final S strings = S.of(context);
    return switch (themeMode) {
      AppThemeMode.system => strings.system,
      AppThemeMode.light => strings.light,
      AppThemeMode.dark => strings.dark,
    };
  }

  void _setThemeMode(BuildContext context, DisplaySettings displaySettings) {
    showModalBottomSheet<AppThemeMode>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: RadioGroup<AppThemeMode>(
            groupValue: displaySettings.themeMode,
            onChanged: (AppThemeMode? value) {
              assert(value != null, 'Theme mode cannot be null.');
              Navigator.pop(context, value);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final AppThemeMode themeMode in AppThemeMode.values)
                  RadioListTile<AppThemeMode>(
                    key: Key('theme_mode_${themeMode.name}_radio_tile'),
                    title: Text(_themeModeLabel(context, themeMode)),
                    value: themeMode,
                  ),
              ],
            ),
          ),
        );
      },
    ).then((AppThemeMode? themeMode) {
      if (themeMode == null || themeMode == displaySettings.themeMode) {
        return;
      }
      DB().displaySettings = displaySettings.copyWith(themeMode: themeMode);
    });
  }

  String _activeBoardThemeLabel(
    BuildContext context,
    ColorSettings colorSettings,
  ) {
    final Map<String, dynamic> activeColors = colorSettings.toJson();
    for (final MapEntry<ColorTheme, ColorSettings> entry
        in AppTheme.colorThemes.entries) {
      if (entry.key == ColorTheme.current) {
        continue;
      }
      if (mapEquals(entry.value.toJson(), activeColors)) {
        return colorThemeLabel(context, entry.key);
      }
    }
    return S.of(context).custom;
  }

  Widget _buildDisplaySettings(
    BuildContext context,
    Box<DisplaySettings> box,
    _,
  ) {
    final DisplaySettings displaySettings = box.get(
      DB.displaySettingsKey,
      defaultValue: const DisplaySettings(),
    )!;
    final S strings = S.of(context);

    return Column(
      key: const Key('appearance_settings_page_display_settings_column'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsCard(
          key: const Key('appearance_settings_page_display_settings_card'),
          title: Text(
            strings.general,
            key: const Key('display_settings_card_title'),
          ),
          children: <Widget>[
            SettingsListTile(
              key: const Key(
                'display_settings_card_language_settings_list_tile',
              ),
              titleString: strings.language,
              trailingString: DB().displaySettings.locale != null
                  ? localeToLanguageName[displaySettings.locale]
                  : null,
              onTap: () => _selectLanguage(context, displaySettings),
            ),
            SettingsListTile(
              key: const Key(
                'display_settings_card_theme_mode_settings_list_tile',
              ),
              titleString: strings.themeMode,
              trailingString: _themeModeLabel(
                context,
                displaySettings.themeMode,
              ),
              onTap: () => _setThemeMode(context, displaySettings),
            ),
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
              SettingsListTile.switchTile(
                key: const Key('display_settings_card_full_screen_switch_tile'),
                value: displaySettings.isFullScreen,
                onChanged: (bool val) {
                  DB().displaySettings = displaySettings.copyWith(
                    isFullScreen: val,
                  );
                  rootScaffoldMessengerKey.currentState!.showSnackBarClear(
                    strings.reopenToTakeEffect,
                  );
                },
                titleString: strings.fullScreen,
              ),
          ],
        ),
        SettingsCard(
          key: const Key('appearance_settings_page_board_display_card'),
          title: Text(strings.board),
          children: <Widget>[
            SettingsListTile.switchTile(
              key: const Key(
                'display_settings_card_piece_count_in_hand_shown_switch_tile',
              ),
              value: displaySettings.isPieceCountInHandShown,
              onChanged: (bool val) => DB().displaySettings = displaySettings
                  .copyWith(isPieceCountInHandShown: val),
              titleString: strings.isPieceCountInHandShown,
            ),
            if (!(Constants.isSmallScreen(context) == true &&
                DB().ruleSettings.piecesCount > 9))
              SettingsListTile.switchTile(
                key: const Key(
                  'display_settings_card_unplaced_removed_pieces_shown_switch_tile',
                ),
                value: displaySettings.isUnplacedAndRemovedPiecesShown,
                onChanged: (bool val) => DB().displaySettings = displaySettings
                    .copyWith(isUnplacedAndRemovedPiecesShown: val),
                titleString: strings.isUnplacedAndRemovedPiecesShown,
              ),
            SettingsListTile(
              key: const Key(
                'display_settings_card_board_corner_radius_settings_list_tile',
              ),
              titleString: strings.boardCornerRadius,
              onTap: () => setBoardCornerRadius(context),
            ),
            SettingsListTile(
              key: const Key(
                'display_settings_card_board_border_line_width_settings_list_tile',
              ),
              titleString: strings.boardBorderLineWidth,
              onTap: () => setBoardBorderLineWidth(context),
            ),
            SettingsListTile(
              key: const Key(
                'display_settings_card_board_inner_line_width_settings_list_tile',
              ),
              titleString: strings.boardInnerLineWidth,
              onTap: () => setBoardInnerLineWidth(context),
            ),
            SettingsListTile(
              key: const Key(
                'display_settings_card_board_inner_ring_size_settings_list_tile',
              ),
              titleString: strings.boardInnerRingSize,
              onTap: () => setBoardInnerRingSize(context),
            ),
            SettingsListTile.switchTile(
              key: const Key('display_settings_card_board_shadow_switch_tile'),
              value: displaySettings.boardShadowEnabled,
              onChanged: (bool val) => DB().displaySettings = displaySettings
                  .copyWith(boardShadowEnabled: val),
              titleString: strings.boardShadowEnabled,
            ),
            SettingsListTile(
              key: const Key(
                'display_settings_card_point_style_settings_list_tile',
              ),
              titleString: strings.pointStyle,
              onTap: () => setPointPaintingStyle(context, displaySettings),
            ),
            SettingsListTile(
              key: const Key(
                'display_settings_card_point_width_settings_list_tile',
              ),
              titleString: strings.pointWidth,
              onTap: () => setPointWidth(context),
            ),
            SettingsListTile(
              key: const Key(
                'display_settings_card_board_top_settings_list_tile',
              ),
              titleString: strings.boardTop,
              onTap: () => setBoardTop(context),
            ),
          ],
        ),
        SettingsCard(
          key: const Key('appearance_settings_page_piece_display_card'),
          title: Text(strings.pieces),
          children: <Widget>[
            SettingsListTile.switchTile(
              key: const Key(
                'display_settings_card_numbers_on_pieces_shown_switch_tile',
              ),
              value: displaySettings.isNumbersOnPiecesShown,
              onChanged: (bool val) => DB().displaySettings = displaySettings
                  .copyWith(isNumbersOnPiecesShown: val),
              titleString: strings.showNumbersOnPieces,
            ),
            SettingsListTile.switchTile(
              key: const Key(
                'display_settings_card_capturable_pieces_highlight_shown_switch_tile',
              ),
              value: displaySettings.isCapturablePiecesHighlightShown,
              onChanged: (bool val) => DB().displaySettings = displaySettings
                  .copyWith(isCapturablePiecesHighlightShown: val),
              titleString: strings.highlightCapturablePieces,
            ),
            SettingsListTile(
              key: const Key(
                'display_settings_card_piece_width_settings_list_tile',
              ),
              titleString: strings.pieceWidth,
              onTap: () => setPieceWidth(context),
            ),
            SettingsListTile(
              key: const Key(
                'display_settings_card_animation_duration_settings_list_tile',
              ),
              titleString: strings.animationDuration,
              onTap: () => setAnimationDuration(context),
            ),
            if (!displaySettings.isPiecePickUpAnimationEnabled)
              SettingsListTile(
                key: const Key(
                  'display_settings_card_place_effect_animation_settings_list_tile',
                ),
                titleString: strings.placeEffectAnimation,
                onTap: () => setPlaceEffectAnimation(context),
              ),
            if (!displaySettings.isPiecePickUpAnimationEnabled)
              SettingsListTile(
                key: const Key(
                  'display_settings_card_remove_effect_animation_settings_list_tile',
                ),
                titleString: strings.removeEffectAnimation,
                onTap: () => setRemoveEffectAnimation(context),
              ),
          ],
        ),
        SettingsCard(
          key: const Key('appearance_settings_page_advanced_display_card'),
          title: Text(strings.advanced),
          children: <Widget>[
            SettingsListTile.switchTile(
              key: const Key(
                'display_settings_card_history_navigation_toolbar_shown_switch_tile',
              ),
              value: displaySettings.isHistoryNavigationToolbarShown,
              onChanged: (bool val) => DB().displaySettings = displaySettings
                  .copyWith(isHistoryNavigationToolbarShown: val),
              titleString: strings.isHistoryNavigationToolbarShown,
            ),
            SettingsListTile.switchTile(
              key: const Key(
                'display_settings_card_annotation_toolbar_shown_switch_tile',
              ),
              value: displaySettings.isAnnotationToolbarShown,
              onChanged: (bool val) => DB().displaySettings = displaySettings
                  .copyWith(isAnnotationToolbarShown: val),
              titleString: strings.isAnnotationToolbarShown,
            ),
            SettingsListTile.switchTile(
              key: const Key(
                'display_settings_card_positional_advantage_indicator_shown_switch_tile',
              ),
              value: displaySettings.isPositionalAdvantageIndicatorShown,
              onChanged: (bool val) => DB().displaySettings = displaySettings
                  .copyWith(isPositionalAdvantageIndicatorShown: val),
              titleString: strings.showPositionalAdvantageIndicator,
            ),
            SettingsListTile.switchTile(
              key: const Key(
                'display_settings_card_advantage_graph_shown_switch_tile',
              ),
              value: displaySettings.isAdvantageGraphShown,
              onChanged: (bool val) {
                DB().displaySettings = displaySettings.copyWith(
                  isAdvantageGraphShown: val,
                );
                if (val) {
                  rootScaffoldMessengerKey.currentState!.showSnackBarClear(
                    strings.advantageGraphHint,
                  );
                }
              },
              titleString: strings.showAdvantageGraph,
            ),
            SettingsListTile(
              key: const Key(
                'display_settings_card_font_size_settings_list_tile',
              ),
              titleString: strings.fontSize,
              onTap: () => setFontSize(context),
            ),
            SettingsListTile.switchTile(
              key: const Key(
                'display_settings_card_vignette_effect_switch_tile',
              ),
              value: displaySettings.vignetteEffectEnabled,
              onChanged: (bool val) => DB().displaySettings = displaySettings
                  .copyWith(vignetteEffectEnabled: val),
              titleString: strings.vignetteEffect,
            ),
            SettingsListTile.switchTile(
              key: const Key(
                'display_settings_card_screenshot_game_info_shown_switch_tile',
              ),
              value: displaySettings.isScreenshotGameInfoShown,
              onChanged: (bool val) => DB().displaySettings = displaySettings
                  .copyWith(isScreenshotGameInfoShown: val),
              titleString: strings.showGameInfoOnScreenshots,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return BlockSemantics(
      key: const Key('appearance_settings_page_block_semantics'),
      child: Scaffold(
        key: const Key('appearance_settings_page_scaffold'),
        resizeToAvoidBottomInset: false,
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          key: const Key('appearance_settings_page_appbar'),
          title: Text(
            S.of(context).board,
            key: const Key('appearance_settings_page_appbar_title'),
          ),
        ),
        body: SettingsList(
          key: const Key('appearance_settings_page_settings_list'),
          children: <Widget>[
            // Board display settings come first to match the Lichess Board
            // settings flow: board theme, piece set, and coordinates are the
            // primary choices for this page.
            ValueListenableBuilder<Box<ColorSettings>>(
              key: const Key(
                'appearance_settings_page_color_settings_value_listenable_builder',
              ),
              valueListenable: DB().listenColorSettings,
              builder: _buildBoardStyleSettings,
            ),
            ValueListenableBuilder<Box<DisplaySettings>>(
              key: const Key(
                'appearance_settings_page_display_settings_value_listenable_builder',
              ),
              valueListenable: DB().listenDisplaySettings,
              builder: _buildDisplaySettings,
            ),
            ValueListenableBuilder<Box<ColorSettings>>(
              key: const Key(
                'appearance_settings_page_color_tuning_value_listenable_builder',
              ),
              valueListenable: DB().listenColorSettings,
              builder: _buildColorTuningSettings,
            ),
          ],
        ),
      ),
    );
  }
}
