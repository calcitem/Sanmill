/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/l10n/resources.dart';
import 'package:sanmill/models/color.dart';
import 'package:sanmill/models/display.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/constants.dart';
import 'package:sanmill/shared/settings/settings_card.dart';
import 'package:sanmill/shared/settings/settings_list_tile.dart';
import 'package:sanmill/shared/settings/settings_switch_list_tile.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

part 'package:sanmill/screens/personalization_settings/color_selector_list_tile.dart';
part 'package:sanmill/screens/personalization_settings/animation_duration_slider.dart';
part 'package:sanmill/screens/personalization_settings/board_top_slider.dart';
part 'package:sanmill/screens/personalization_settings/board_boarder_line_width_slider.dart';
part 'package:sanmill/screens/personalization_settings/board_inner_line_width_slider.dart';
part 'package:sanmill/screens/personalization_settings/font_size_slider.dart';
part 'package:sanmill/screens/personalization_settings/point_width_slider.dart';
part 'package:sanmill/screens/personalization_settings/piece_width_slider.dart';
part 'package:sanmill/screens/personalization_settings/point_style_modal.dart';

class PersonalizationSettingsPage extends StatelessWidget {
  void setBoardBorderLineWidth(BuildContext context) => showModalBottomSheet(
        context: context,
        builder: (_) => const _BoardBorderWidthSlider(),
      );

  void setBoardInnerLineWidth(BuildContext context) => showModalBottomSheet(
        context: context,
        builder: (_) => const _BoardInnerWidthSlider(),
      );

  void setPointStyle(BuildContext context, Display _display) {
    void callback(int? pointStyle) {
      Navigator.pop(context);

      LocalDatabaseService.display = _display.copyWith(pointStyle: pointStyle);

      debugPrint("[config] pointStyle: $pointStyle");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _PointStyleModal(
        pointStyle: _display.pointStyle,
        onChanged: callback,
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

  @override
  Widget build(BuildContext context) {
    void langCallback(Display _display, [Locale? locale]) {
      debugPrint("[config] languageCode = $locale");

      Navigator.pop(context);

      LocalDatabaseService.display = _display.copyWith(languageCode: locale);

      debugPrint("[config] Config.languageCode: ${_display.languageCode}");
    }

    return Scaffold(
      backgroundColor: AppTheme.lightBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        title: Text(S.of(context).personalization),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.of(context).display,
              style: AppTheme.settingsHeaderStyle,
            ),
            ValueListenableBuilder(
              valueListenable: LocalDatabaseService.listenDisplay,
              builder: (context, Box<Display> displayaBox, _) {
                final Display _display = displayaBox.get(
                  LocalDatabaseService.colorSettingsKey,
                  defaultValue: Display(),
                )!;

                return SettingsCard(
                  children: <Widget>[
                    SettingsListTile(
                      titleString: S.of(context).language,
                      trailingString:
                          LocalDatabaseService.display.languageCode !=
                                  Constants.defaultLocale
                              ? languageCodeToStrings[_display.languageCode]!
                                  .languageName
                              : "",
                      onTap: () => setLanguage(
                        context,
                        (locale) => langCallback(_display, locale),
                      ),
                    ),
                    SettingsSwitchListTile(
                      value: _display.isPieceCountInHandShown,
                      onChanged: (val) =>
                          setIsPieceCountInHandShown(_display, val),
                      titleString: S.of(context).isPieceCountInHandShown,
                    ),
                    SettingsSwitchListTile(
                      value: _display.isNotationsShown,
                      onChanged: (val) => setIsNotationsShown(_display, val),
                      titleString: S.of(context).isNotationsShown,
                    ),
                    SettingsSwitchListTile(
                      value: _display.isHistoryNavigationToolbarShown,
                      onChanged: (val) =>
                          setIsHistoryNavigationToolbarShown(_display, val),
                      titleString:
                          S.of(context).isHistoryNavigationToolbarShown,
                    ),
                    SettingsListTile(
                      titleString: S.of(context).boardBorderLineWidth,
                      onTap: () => setBoardBorderLineWidth(context),
                    ),
                    SettingsListTile(
                      titleString: S.of(context).boardInnerLineWidth,
                      onTap: () => setBoardInnerLineWidth(context),
                    ),
                    SettingsListTile(
                      titleString: S.of(context).pointStyle,
                      onTap: () => setPointStyle(context, _display),
                    ),
                    SettingsListTile(
                      titleString: S.of(context).pointWidth,
                      onTap: () => setPointWidth(context),
                    ),
                    SettingsListTile(
                      titleString: S.of(context).pieceWidth,
                      onTap: () => setPieceWidth(context),
                    ),
                    SettingsListTile(
                      titleString: S.of(context).fontSize,
                      onTap: () => setFontSize(context),
                    ),
                    SettingsListTile(
                      titleString: S.of(context).boardTop,
                      onTap: () => setBoardTop(context),
                    ),
                    SettingsListTile(
                      titleString: S.of(context).animationDuration,
                      onTap: () => setAnimationDuration(context),
                    ),
                    SettingsSwitchListTile(
                      value:
                          LocalDatabaseService.display.standardNotationEnabled,
                      onChanged: (val) =>
                          setStandardNotationEnabled(_display, val),
                      titleString: S.of(context).standardNotation,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppTheme.sizedBoxHeight),
            Text(S.of(context).color, style: AppTheme.settingsHeaderStyle),
            ValueListenableBuilder(
              valueListenable: LocalDatabaseService.listenColorSettings,
              builder: (context, Box<ColorSettings> colorBox, _) {
                final ColorSettings _colorSettings = colorBox.get(
                  LocalDatabaseService.colorSettingsKey,
                  defaultValue: ColorSettings(),
                )!;

                return SettingsCard(
                  children: <Widget>[
                    _ColorSelectorListTile(
                      title: S.of(context).boardColor,
                      value: _colorSettings.boardBackgroundColor,
                      onChanged: (val) => LocalDatabaseService.colorSettings =
                          _colorSettings.copyWith(boardBackgroundColor: val),
                    ),
                    _ColorSelectorListTile(
                      title: S.of(context).backgroundColor,
                      value: _colorSettings.darkBackgroundColor,
                      onChanged: (val) => LocalDatabaseService.colorSettings =
                          _colorSettings.copyWith(darkBackgroundColor: val),
                    ),
                    _ColorSelectorListTile(
                      title: S.of(context).lineColor,
                      value: _colorSettings.boardLineColor,
                      onChanged: (val) => LocalDatabaseService.colorSettings =
                          _colorSettings.copyWith(boardLineColor: val),
                    ),
                    _ColorSelectorListTile(
                      title: S.of(context).whitePieceColor,
                      value: _colorSettings.whitePieceColor,
                      onChanged: (val) => LocalDatabaseService.colorSettings =
                          _colorSettings.copyWith(whitePieceColor: val),
                    ),
                    _ColorSelectorListTile(
                      title: S.of(context).blackPieceColor,
                      value: _colorSettings.blackPieceColor,
                      onChanged: (val) => LocalDatabaseService.colorSettings =
                          _colorSettings.copyWith(blackPieceColor: val),
                    ),
                    _ColorSelectorListTile(
                      title: S.of(context).pieceHighlightColor,
                      value: _colorSettings.pieceHighlightColor,
                      onChanged: (val) => LocalDatabaseService.colorSettings =
                          _colorSettings.copyWith(pieceHighlightColor: val),
                    ),
                    _ColorSelectorListTile(
                      title: S.of(context).messageColor,
                      value: _colorSettings.messageColor,
                      onChanged: (val) => LocalDatabaseService.colorSettings =
                          _colorSettings.copyWith(messageColor: val),
                    ),
                    _ColorSelectorListTile(
                      title: S.of(context).drawerColor,
                      value: _colorSettings.drawerColor,
                      onChanged: (val) => LocalDatabaseService.colorSettings =
                          _colorSettings.copyWith(drawerColor: val),
                    ),
                    _ColorSelectorListTile(
                      title: S.of(context).drawerBackgroundColor,
                      value: _colorSettings.drawerBackgroundColor,
                      onChanged: (val) => LocalDatabaseService.colorSettings =
                          _colorSettings.copyWith(drawerBackgroundColor: val),
                    ),
                    _ColorSelectorListTile(
                      title: S.of(context).drawerTextColor,
                      value: _colorSettings.drawerTextColor,
                      onChanged: (val) => LocalDatabaseService.colorSettings =
                          _colorSettings.copyWith(drawerTextColor: val),
                    ),
                    _ColorSelectorListTile(
                      title: S.of(context).drawerHighlightItemColor,
                      value: _colorSettings.drawerHighlightItemColor,
                      onChanged: (val) => LocalDatabaseService.colorSettings =
                          _colorSettings.copyWith(
                        drawerHighlightItemColor: val,
                      ),
                    ),
                    _ColorSelectorListTile(
                      title: S.of(context).mainToolbarBackgroundColor,
                      value: _colorSettings.mainToolbarBackgroundColor,
                      onChanged: (val) => LocalDatabaseService.colorSettings =
                          _colorSettings.copyWith(
                        mainToolbarBackgroundColor: val,
                      ),
                    ),
                    _ColorSelectorListTile(
                      title: S.of(context).mainToolbarIconColor,
                      value: _colorSettings.mainToolbarIconColor,
                      onChanged: (val) => LocalDatabaseService.colorSettings =
                          _colorSettings.copyWith(mainToolbarIconColor: val),
                    ),
                    _ColorSelectorListTile(
                      title: S.of(context).navigationToolbarBackgroundColor,
                      value: _colorSettings.navigationToolbarBackgroundColor,
                      onChanged: (val) => LocalDatabaseService.colorSettings =
                          _colorSettings.copyWith(
                        navigationToolbarBackgroundColor: val,
                      ),
                    ),
                    _ColorSelectorListTile(
                      title: S.of(context).navigationToolbarIconColor,
                      value: _colorSettings.navigationToolbarIconColor,
                      onChanged: (val) => LocalDatabaseService.colorSettings =
                          _colorSettings.copyWith(
                        navigationToolbarIconColor: val,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void setIsPieceCountInHandShown(Display _display, bool value) {
    LocalDatabaseService.display =
        _display.copyWith(isPieceCountInHandShown: value);
  }

  void setIsNotationsShown(Display _display, bool value) {
    LocalDatabaseService.display = _display.copyWith(isNotationsShown: value);
  }

  void setIsHistoryNavigationToolbarShown(Display _display, bool value) {
    LocalDatabaseService.display =
        _display.copyWith(isHistoryNavigationToolbarShown: value);
  }

  void setStandardNotationEnabled(Display _display, bool value) {
    LocalDatabaseService.display =
        _display.copyWith(standardNotationEnabled: value);

    debugPrint("[config] standardNotationEnabled: $value");
  }
}
