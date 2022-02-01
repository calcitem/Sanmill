// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/models/color_settings.dart';
import 'package:sanmill/models/display_settings.dart';
import 'package:sanmill/services/database/database.dart';
import 'package:sanmill/services/language_info.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/shared/custom_drawer/custom_drawer.dart';
import 'package:sanmill/shared/settings/settings.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

part 'package:sanmill/screens/appearance_settings/animation_duration_slider.dart';
part 'package:sanmill/screens/appearance_settings/board_boarder_line_width_slider.dart';
part 'package:sanmill/screens/appearance_settings/board_inner_line_width_slider.dart';
part 'package:sanmill/screens/appearance_settings/board_top_slider.dart';
part 'package:sanmill/screens/appearance_settings/font_size_slider.dart';
part 'package:sanmill/screens/appearance_settings/language_picker.dart';
part 'package:sanmill/screens/appearance_settings/piece_width_slider.dart';
part 'package:sanmill/screens/appearance_settings/point_style_modal.dart';
part 'package:sanmill/screens/appearance_settings/point_width_slider.dart';

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({Key? key}) : super(key: key);

  void setBoardBorderLineWidth(BuildContext context) => showModalBottomSheet(
        context: context,
        builder: (_) => const _BoardBorderWidthSlider(),
      );

  void setBoardInnerLineWidth(BuildContext context) => showModalBottomSheet(
        context: context,
        builder: (_) => const _BoardInnerWidthSlider(),
      );

  void setPointStyle(BuildContext context, DisplaySettings _displaySettings) {
    void _callback(PaintingStyle? pointStyle) {
      Navigator.pop(context);
      DB().displaySettings = pointStyle == null
          ? _displaySettings.copyWith()
          : _displaySettings.copyWith(pointStyle: pointStyle);

      logger.v("[config] pointStyle: $pointStyle");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _PointStyleModal(
        pointStyle: _displaySettings.pointStyle,
        onChanged: _callback,
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

  void langCallback(
    BuildContext context,
    DisplaySettings _displaySettings, [
    Locale? locale,
  ]) {
    Navigator.pop(context);

    if (locale == null) {
      DB().displaySettings = _displaySettings.copyWith();
    } else {
      DB().displaySettings = _displaySettings.copyWith(languageCode: locale);
    }

    logger.v("[config] languageCode = $locale");
  }

  Widget _buildColorSettings(BuildContext context, Box<ColorSettings> box, _) {
    final ColorSettings _colorSettings = box.get(
      DB.colorSettingsKey,
      defaultValue: const ColorSettings(),
    )!;

    return SettingsCard(
      title: Text(S.of(context).color),
      children: <Widget>[
        SettingsListTile.color(
          titleString: S.of(context).boardColor,
          value: DB().colorSettings.boardBackgroundColor,
          onChanged: (val) => DB().colorSettings =
              _colorSettings.copyWith(boardBackgroundColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).backgroundColor,
          value: DB().colorSettings.darkBackgroundColor,
          onChanged: (val) => DB().colorSettings =
              _colorSettings.copyWith(darkBackgroundColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).lineColor,
          value: DB().colorSettings.boardLineColor,
          onChanged: (val) =>
              DB().colorSettings = _colorSettings.copyWith(boardLineColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).whitePieceColor,
          value: DB().colorSettings.whitePieceColor,
          onChanged: (val) => DB().colorSettings =
              _colorSettings.copyWith(whitePieceColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).blackPieceColor,
          value: DB().colorSettings.blackPieceColor,
          onChanged: (val) => DB().colorSettings =
              _colorSettings.copyWith(blackPieceColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).pieceHighlightColor,
          value: DB().colorSettings.pieceHighlightColor,
          onChanged: (val) => DB().colorSettings =
              _colorSettings.copyWith(pieceHighlightColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).messageColor,
          value: DB().colorSettings.messageColor,
          onChanged: (val) =>
              DB().colorSettings = _colorSettings.copyWith(messageColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).drawerColor,
          value: DB().colorSettings.drawerColor,
          onChanged: (val) =>
              DB().colorSettings = _colorSettings.copyWith(drawerColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).drawerTextColor,
          value: DB().colorSettings.drawerTextColor,
          onChanged: (val) => DB().colorSettings =
              _colorSettings.copyWith(drawerTextColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).drawerHighlightItemColor,
          value: DB().colorSettings.drawerHighlightItemColor,
          onChanged: (val) => DB().colorSettings = _colorSettings.copyWith(
            drawerHighlightItemColor: val,
          ),
        ),
        SettingsListTile.color(
          titleString: S.of(context).mainToolbarBackgroundColor,
          value: DB().colorSettings.mainToolbarBackgroundColor,
          onChanged: (val) => DB().colorSettings = _colorSettings.copyWith(
            mainToolbarBackgroundColor: val,
          ),
        ),
        SettingsListTile.color(
          titleString: S.of(context).mainToolbarIconColor,
          value: DB().colorSettings.mainToolbarIconColor,
          onChanged: (val) => DB().colorSettings =
              _colorSettings.copyWith(mainToolbarIconColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).navigationToolbarBackgroundColor,
          value: DB().colorSettings.navigationToolbarBackgroundColor,
          onChanged: (val) => DB().colorSettings = _colorSettings.copyWith(
            navigationToolbarBackgroundColor: val,
          ),
        ),
        SettingsListTile.color(
          titleString: S.of(context).navigationToolbarIconColor,
          value: DB().colorSettings.navigationToolbarIconColor,
          onChanged: (val) => DB().colorSettings = _colorSettings.copyWith(
            navigationToolbarIconColor: val,
          ),
        ),
      ],
    );
  }

  Widget _buildDisplaySettings(
    BuildContext context,
    Box<DisplaySettings> box,
    _,
  ) {
    final DisplaySettings _displaySettings = box.get(
      DB.displaySettingsKey,
      defaultValue: const DisplaySettings(),
    )!;
    return SettingsCard(
      title: Text(S.of(context).display),
      children: <Widget>[
        SettingsListTile(
          titleString: S.of(context).language,
          trailingString: DB().displaySettings.languageCode != null
              ? languageCodeToStrings[_displaySettings.languageCode]
              : null,
          onTap: () => showDialog(
            context: context,
            builder: (_) => _LanguagePicker(
              currentLocale: _displaySettings.languageCode,
              onChanged: (locale) =>
                  langCallback(context, _displaySettings, locale),
            ),
          ),
        ),
        SettingsListTile.switchTile(
          value: _displaySettings.isPieceCountInHandShown,
          onChanged: (val) => DB().displaySettings =
              _displaySettings.copyWith(isPieceCountInHandShown: val),
          titleString: S.of(context).isPieceCountInHandShown,
        ),
        SettingsListTile.switchTile(
          value: _displaySettings.isNotationsShown,
          onChanged: (val) => DB().displaySettings =
              _displaySettings.copyWith(isNotationsShown: val),
          titleString: S.of(context).isNotationsShown,
        ),
        SettingsListTile.switchTile(
          value: _displaySettings.isHistoryNavigationToolbarShown,
          onChanged: (val) => DB().displaySettings =
              _displaySettings.copyWith(isHistoryNavigationToolbarShown: val),
          titleString: S.of(context).isHistoryNavigationToolbarShown,
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
          onTap: () => setPointStyle(context, _displaySettings),
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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBackgroundColor,
      appBar: AppBar(
        leading: DrawerIcon.of(context)?.icon,
        title: Text(S.of(context).appearance),
      ),
      body: SettingsList(
        children: [
          ValueListenableBuilder(
            valueListenable: DB().listenDisplaySettings,
            builder: _buildDisplaySettings,
          ),
          ValueListenableBuilder(
            valueListenable: DB().listenColorSettings,
            builder: _buildColorSettings,
          ),
        ],
      ),
    );
  }
}
