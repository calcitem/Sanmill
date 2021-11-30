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
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/models/color.dart';
import 'package:sanmill/models/display.dart';
import 'package:sanmill/services/language_info.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/custom_drawer/custom_drawer.dart';
import 'package:sanmill/shared/custom_spacer.dart';
import 'package:sanmill/shared/settings/settings.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

part 'package:sanmill/screens/personalization_settings/animation_duration_slider.dart';
part 'package:sanmill/screens/personalization_settings/board_boarder_line_width_slider.dart';
part 'package:sanmill/screens/personalization_settings/board_inner_line_width_slider.dart';
part 'package:sanmill/screens/personalization_settings/board_top_slider.dart';
part 'package:sanmill/screens/personalization_settings/font_size_slider.dart';
part 'package:sanmill/screens/personalization_settings/language_picker.dart';
part 'package:sanmill/screens/personalization_settings/piece_width_slider.dart';
part 'package:sanmill/screens/personalization_settings/point_style_modal.dart';
part 'package:sanmill/screens/personalization_settings/point_width_slider.dart';

class PersonalizationSettingsPage extends StatelessWidget {
  const PersonalizationSettingsPage({Key? key}) : super(key: key);

  void setBoardBorderLineWidth(BuildContext context) => showModalBottomSheet(
        context: context,
        builder: (_) => const _BoardBorderWidthSlider(),
      );

  void setBoardInnerLineWidth(BuildContext context) => showModalBottomSheet(
        context: context,
        builder: (_) => const _BoardInnerWidthSlider(),
      );

  void setPointStyle(BuildContext context, Display _display) {
    void _callback(PaintingStyle? pointStyle) {
      Navigator.pop(context);

      LocalDatabaseService.display = _display.copyWith(pointStyle: pointStyle);

      logger.v("[config] pointStyle: $pointStyle");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _PointStyleModal(
        pointStyle: _display.pointStyle,
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

  void langCallback(BuildContext context, Display _display, [Locale? locale]) {
    Navigator.pop(context);

    if (locale == null) {
      LocalDatabaseService.display = _display.copyWithNull(languageCode: true);
    } else {
      LocalDatabaseService.display = _display.copyWith(languageCode: locale);
    }

    logger.v("[config] languageCode = $locale");
  }

  Widget _buildColor(BuildContext context, Box<ColorSettings> colorBox, _) {
    final ColorSettings _colorSettings = colorBox.get(
      LocalDatabaseService.colorSettingsKey,
      defaultValue: const ColorSettings(),
    )!;

    return SettingsCard(
      children: <Widget>[
        SettingsListTile.color(
          titleString: S.of(context).boardColor,
          value: LocalDatabaseService.colorSettings.boardBackgroundColor,
          onChanged: (val) => LocalDatabaseService.colorSettings =
              _colorSettings.copyWith(boardBackgroundColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).backgroundColor,
          value: LocalDatabaseService.colorSettings.darkBackgroundColor,
          onChanged: (val) => LocalDatabaseService.colorSettings =
              _colorSettings.copyWith(darkBackgroundColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).lineColor,
          value: LocalDatabaseService.colorSettings.boardLineColor,
          onChanged: (val) => LocalDatabaseService.colorSettings =
              _colorSettings.copyWith(boardLineColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).whitePieceColor,
          value: LocalDatabaseService.colorSettings.whitePieceColor,
          onChanged: (val) => LocalDatabaseService.colorSettings =
              _colorSettings.copyWith(whitePieceColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).blackPieceColor,
          value: LocalDatabaseService.colorSettings.blackPieceColor,
          onChanged: (val) => LocalDatabaseService.colorSettings =
              _colorSettings.copyWith(blackPieceColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).pieceHighlightColor,
          value: LocalDatabaseService.colorSettings.pieceHighlightColor,
          onChanged: (val) => LocalDatabaseService.colorSettings =
              _colorSettings.copyWith(pieceHighlightColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).messageColor,
          value: LocalDatabaseService.colorSettings.messageColor,
          onChanged: (val) => LocalDatabaseService.colorSettings =
              _colorSettings.copyWith(messageColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).drawerColor,
          value: LocalDatabaseService.colorSettings.drawerColor,
          onChanged: (val) => LocalDatabaseService.colorSettings =
              _colorSettings.copyWith(drawerColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).drawerTextColor,
          value: LocalDatabaseService.colorSettings.drawerTextColor,
          onChanged: (val) => LocalDatabaseService.colorSettings =
              _colorSettings.copyWith(drawerTextColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).drawerHighlightItemColor,
          value: LocalDatabaseService.colorSettings.drawerHighlightItemColor,
          onChanged: (val) =>
              LocalDatabaseService.colorSettings = _colorSettings.copyWith(
            drawerHighlightItemColor: val,
          ),
        ),
        SettingsListTile.color(
          titleString: S.of(context).mainToolbarBackgroundColor,
          value: LocalDatabaseService.colorSettings.mainToolbarBackgroundColor,
          onChanged: (val) =>
              LocalDatabaseService.colorSettings = _colorSettings.copyWith(
            mainToolbarBackgroundColor: val,
          ),
        ),
        SettingsListTile.color(
          titleString: S.of(context).mainToolbarIconColor,
          value: LocalDatabaseService.colorSettings.mainToolbarIconColor,
          onChanged: (val) => LocalDatabaseService.colorSettings =
              _colorSettings.copyWith(mainToolbarIconColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).navigationToolbarBackgroundColor,
          value: LocalDatabaseService
              .colorSettings.navigationToolbarBackgroundColor,
          onChanged: (val) =>
              LocalDatabaseService.colorSettings = _colorSettings.copyWith(
            navigationToolbarBackgroundColor: val,
          ),
        ),
        SettingsListTile.color(
          titleString: S.of(context).navigationToolbarIconColor,
          value: LocalDatabaseService.colorSettings.navigationToolbarIconColor,
          onChanged: (val) =>
              LocalDatabaseService.colorSettings = _colorSettings.copyWith(
            navigationToolbarIconColor: val,
          ),
        ),
      ],
    );
  }

  Widget _buildDisplay(BuildContext context, Box<Display> displayBox, _) {
    final Display _display = displayBox.get(
      LocalDatabaseService.colorSettingsKey,
      defaultValue: const Display(),
    )!;
    return SettingsCard(
      children: <Widget>[
        SettingsListTile(
          titleString: S.of(context).language,
          trailingString: LocalDatabaseService.display.languageCode != null
              ? languageCodeToStrings[_display.languageCode]
              : null,
          onTap: () => showDialog(
            context: context,
            builder: (_) => _LanguagePicker(
              currentLocale: _display.languageCode,
              onChanged: (locale) => langCallback(context, _display, locale),
            ),
          ),
        ),
        SettingsListTile.switchTile(
          value: _display.isPieceCountInHandShown,
          onChanged: (val) => LocalDatabaseService.display =
              _display.copyWith(isPieceCountInHandShown: val),
          titleString: S.of(context).isPieceCountInHandShown,
        ),
        SettingsListTile.switchTile(
          value: _display.isNotationsShown,
          onChanged: (val) => LocalDatabaseService.display =
              _display.copyWith(isNotationsShown: val),
          titleString: S.of(context).isNotationsShown,
        ),
        SettingsListTile.switchTile(
          value: _display.isHistoryNavigationToolbarShown,
          onChanged: (val) => LocalDatabaseService.display =
              _display.copyWith(isHistoryNavigationToolbarShown: val),
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
        SettingsListTile.switchTile(
          value: LocalDatabaseService.display.standardNotationEnabled,
          onChanged: (val) => LocalDatabaseService.display =
              _display.copyWith(standardNotationEnabled: val),
          titleString: S.of(context).standardNotation,
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
        title: Text(S.of(context).personalization),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.of(context).display, style: AppTheme.settingsHeaderStyle),
            ValueListenableBuilder(
              valueListenable: LocalDatabaseService.listenDisplay,
              builder: _buildDisplay,
            ),
            const CustomSpacer(),
            Text(S.of(context).color, style: AppTheme.settingsHeaderStyle),
            // TODO [Leptopoda]: remove the value listenable as we access the ColorSettings via Them.of(constant)
            ValueListenableBuilder(
              valueListenable: LocalDatabaseService.listenColorSettings,
              builder: _buildColor,
            ),
          ],
        ),
      ),
    );
  }
}
