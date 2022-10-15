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
import 'package:hive_flutter/adapters.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/models/color_settings.dart';
import 'package:sanmill/models/display_settings.dart';
import 'package:sanmill/services/database/database.dart';
import 'package:sanmill/services/language_info.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/shared/constants.dart';
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

  void setPointPaintingStyle(
      BuildContext context, DisplaySettings displaySettings) {
    dynamic callback(PointPaintingStyle? pointPaintingStyle) {
      Navigator.pop(context);
      DB().displaySettings =
          displaySettings.copyWith(pointPaintingStyle: pointPaintingStyle);

      logger.v("[config] pointPaintingStyle: $pointPaintingStyle");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _PointPaintingStyleModal(
        pointPaintingStyle: displaySettings.pointPaintingStyle,
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

  void langCallback(
    BuildContext context,
    DisplaySettings displaySettings, [
    Locale? locale,
  ]) {
    Navigator.of(context, rootNavigator: true).pop();

    DB().displaySettings = displaySettings.copyWith(locale: locale);

    logger.v("[config] locale = $locale");
  }

  Widget _buildColorSettings(BuildContext context, Box<ColorSettings> box, _) {
    final ColorSettings colorSettings = box.get(
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
              colorSettings.copyWith(boardBackgroundColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).backgroundColor,
          value: DB().colorSettings.darkBackgroundColor,
          onChanged: (val) => DB().colorSettings =
              colorSettings.copyWith(darkBackgroundColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).lineColor,
          value: DB().colorSettings.boardLineColor,
          onChanged: (val) =>
              DB().colorSettings = colorSettings.copyWith(boardLineColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).whitePieceColor,
          value: DB().colorSettings.whitePieceColor,
          onChanged: (val) =>
              DB().colorSettings = colorSettings.copyWith(whitePieceColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).blackPieceColor,
          value: DB().colorSettings.blackPieceColor,
          onChanged: (val) =>
              DB().colorSettings = colorSettings.copyWith(blackPieceColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).pieceHighlightColor,
          value: DB().colorSettings.pieceHighlightColor,
          onChanged: (val) => DB().colorSettings =
              colorSettings.copyWith(pieceHighlightColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).messageColor,
          value: DB().colorSettings.messageColor,
          onChanged: (val) =>
              DB().colorSettings = colorSettings.copyWith(messageColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).drawerColor,
          value: DB().colorSettings.drawerColor,
          onChanged: (val) =>
              DB().colorSettings = colorSettings.copyWith(drawerColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).drawerTextColor,
          value: DB().colorSettings.drawerTextColor,
          onChanged: (val) =>
              DB().colorSettings = colorSettings.copyWith(drawerTextColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).drawerHighlightItemColor,
          value: DB().colorSettings.drawerHighlightItemColor,
          onChanged: (val) => DB().colorSettings = colorSettings.copyWith(
            drawerHighlightItemColor: val,
          ),
        ),
        SettingsListTile.color(
          titleString: S.of(context).mainToolbarBackgroundColor,
          value: DB().colorSettings.mainToolbarBackgroundColor,
          onChanged: (val) => DB().colorSettings = colorSettings.copyWith(
            mainToolbarBackgroundColor: val,
          ),
        ),
        SettingsListTile.color(
          titleString: S.of(context).mainToolbarIconColor,
          value: DB().colorSettings.mainToolbarIconColor,
          onChanged: (val) => DB().colorSettings =
              colorSettings.copyWith(mainToolbarIconColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).navigationToolbarBackgroundColor,
          value: DB().colorSettings.navigationToolbarBackgroundColor,
          onChanged: (val) => DB().colorSettings = colorSettings.copyWith(
            navigationToolbarBackgroundColor: val,
          ),
        ),
        SettingsListTile.color(
          titleString: S.of(context).navigationToolbarIconColor,
          value: DB().colorSettings.navigationToolbarIconColor,
          onChanged: (val) => DB().colorSettings = colorSettings.copyWith(
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
    final DisplaySettings displaySettings = box.get(
      DB.displaySettingsKey,
      defaultValue: const DisplaySettings(),
    )!;
    return SettingsCard(
      title: Text(S.of(context).display),
      children: <Widget>[
        SettingsListTile(
          titleString: S.of(context).language,
          trailingString: DB().displaySettings.locale != null
              ? localeToLanguageName[displaySettings.locale]
              : null,
          onTap: () => showDialog(
            context: context,
            builder: (_) => _LanguagePicker(
              currentLocale: displaySettings.locale,
              onChanged: (locale) =>
                  langCallback(context, displaySettings, locale),
            ),
          ),
        ),
        SettingsListTile.switchTile(
          value: displaySettings.isPieceCountInHandShown,
          onChanged: (val) => DB().displaySettings =
              displaySettings.copyWith(isPieceCountInHandShown: val),
          titleString: S.of(context).isPieceCountInHandShown,
        ),
        if (!(Constants.isSmallScreen == true &&
            DB().ruleSettings.piecesCount > 9))
          SettingsListTile.switchTile(
            value: displaySettings.isUnplacedAndRemovedPiecesShown,
            onChanged: (val) => DB().displaySettings =
                displaySettings.copyWith(isUnplacedAndRemovedPiecesShown: val),
            titleString: S.of(context).isUnplacedAndRemovedPiecesShown,
          ),
        SettingsListTile.switchTile(
          value: displaySettings.isNotationsShown,
          onChanged: (val) => DB().displaySettings =
              displaySettings.copyWith(isNotationsShown: val),
          titleString: S.of(context).isNotationsShown,
        ),
        SettingsListTile.switchTile(
          value: displaySettings.isHistoryNavigationToolbarShown,
          onChanged: (val) => DB().displaySettings =
              displaySettings.copyWith(isHistoryNavigationToolbarShown: val),
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
          onTap: () => setPointPaintingStyle(context, displaySettings),
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
    return BlockSemantics(
      child: Scaffold(
        resizeToAvoidBottomInset: false,
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
            if (Constants.isSmallScreen == false)
              ValueListenableBuilder(
                valueListenable: DB().listenColorSettings,
                builder: _buildColorSettings,
              ),
          ],
        ),
      ),
    );
  }
}
