// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;

import '../../../../shared/widgets/settings/settings.dart';
import '../../custom_drawer/custom_drawer.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/config/constants.dart';
import '../../shared/database/database.dart';
import '../../shared/services/language_locale_mapping.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../models/color_settings.dart';
import '../models/display_settings.dart';

part 'package:sanmill/appearance_settings/widgets/modals/point_painting_style_modal.dart';
part 'package:sanmill/appearance_settings/widgets/pickers/language_picker.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/ai_response_delay_time_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/animation_duration_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/board_boarder_line_width_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/board_inner_line_width_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/board_top_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/font_size_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/piece_width_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/point_width_slider.dart';
part 'package:sanmill/shared/themes/theme_modal.dart';

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  void setBoardBorderLineWidth(BuildContext context) => showModalBottomSheet(
    context: context,
    builder: (_) => const _BoardBorderLineWidthSlider(),
  );

  void setBoardInnerLineWidth(BuildContext context) => showModalBottomSheet(
    context: context,
    builder: (_) => const _BoardInnerLineWidthSlider(),
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

  void setAiResponseDelayTime(BuildContext context) => showModalBottomSheet(
    context: context,
    builder: (_) => const _AiResponseDelayTimeSlider(),
  );

  void langCallback(
      BuildContext context,
      DisplaySettings displaySettings, [
        Locale? locale,
      ]) {
    DB().displaySettings = displaySettings.copyWith(locale: locale);

    logger.v("[config] locale = $locale");
  }

  void _setTheme(BuildContext context, ColorSettings colorSettings) {
    void callback(ColorTheme? theme) {
      Navigator.pop(context);

      if (theme == ColorTheme.current) {
        return;
      }

      DB().colorSettings = colorSettings.copyWith(
        boardLineColor: AppTheme.colorThemes[theme]!.boardLineColor,
        darkBackgroundColor: AppTheme.colorThemes[theme]!.darkBackgroundColor,
        boardBackgroundColor: AppTheme.colorThemes[theme]!.boardBackgroundColor,
        whitePieceColor: AppTheme.colorThemes[theme]!.whitePieceColor,
        blackPieceColor: AppTheme.colorThemes[theme]!.blackPieceColor,
        pieceHighlightColor: AppTheme.colorThemes[theme]!.pieceHighlightColor,
        messageColor: AppTheme.colorThemes[theme]!.messageColor,
        drawerColor: AppTheme.colorThemes[theme]!.drawerColor,
        drawerTextColor: AppTheme.colorThemes[theme]!.drawerTextColor,
        drawerHighlightItemColor:
        AppTheme.colorThemes[theme]!.drawerHighlightItemColor,
        mainToolbarBackgroundColor:
        AppTheme.colorThemes[theme]!.mainToolbarBackgroundColor,
        mainToolbarIconColor: AppTheme.colorThemes[theme]!.mainToolbarIconColor,
        navigationToolbarBackgroundColor:
        AppTheme.colorThemes[theme]!.navigationToolbarBackgroundColor,
        navigationToolbarIconColor:
        AppTheme.colorThemes[theme]!.navigationToolbarIconColor,
      );
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _ThemeModal(
        theme: ColorTheme.current,
        onChanged: callback,
      ),
    );
  }

  Widget _buildColorSettings(BuildContext context, Box<ColorSettings> box, _) {
    final ColorSettings colorSettings = box.get(
      DB.colorSettingsKey,
      defaultValue: const ColorSettings(),
    )!;

    return SettingsCard(
      title: Text(S.of(context).color),
      children: <Widget>[
        SettingsListTile(
          titleString: S.of(context).theme,
          onTap: () => _setTheme(context, colorSettings),
        ),
        SettingsListTile.color(
          titleString: S.of(context).boardColor,
          value: DB().colorSettings.boardBackgroundColor,
          onChanged: (Color val) => DB().colorSettings =
              colorSettings.copyWith(boardBackgroundColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).backgroundColor,
          value: DB().colorSettings.darkBackgroundColor,
          onChanged: (Color val) => DB().colorSettings =
              colorSettings.copyWith(darkBackgroundColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).lineColor,
          value: DB().colorSettings.boardLineColor,
          onChanged: (Color val) =>
          DB().colorSettings = colorSettings.copyWith(boardLineColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).whitePieceColor,
          value: DB().colorSettings.whitePieceColor,
          onChanged: (Color val) =>
          DB().colorSettings = colorSettings.copyWith(whitePieceColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).blackPieceColor,
          value: DB().colorSettings.blackPieceColor,
          onChanged: (Color val) =>
          DB().colorSettings = colorSettings.copyWith(blackPieceColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).pieceHighlightColor,
          value: DB().colorSettings.pieceHighlightColor,
          onChanged: (Color val) => DB().colorSettings =
              colorSettings.copyWith(pieceHighlightColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).messageColor,
          value: DB().colorSettings.messageColor,
          onChanged: (Color val) =>
          DB().colorSettings = colorSettings.copyWith(messageColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).drawerColor,
          value: DB().colorSettings.drawerColor,
          onChanged: (Color val) =>
          DB().colorSettings = colorSettings.copyWith(drawerColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).drawerTextColor,
          value: DB().colorSettings.drawerTextColor,
          onChanged: (Color val) =>
          DB().colorSettings = colorSettings.copyWith(drawerTextColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).drawerHighlightItemColor,
          value: DB().colorSettings.drawerHighlightItemColor,
          onChanged: (Color val) => DB().colorSettings = colorSettings.copyWith(
            drawerHighlightItemColor: val,
          ),
        ),
        SettingsListTile.color(
          titleString: S.of(context).mainToolbarBackgroundColor,
          value: DB().colorSettings.mainToolbarBackgroundColor,
          onChanged: (Color val) => DB().colorSettings = colorSettings.copyWith(
            mainToolbarBackgroundColor: val,
          ),
        ),
        SettingsListTile.color(
          titleString: S.of(context).mainToolbarIconColor,
          value: DB().colorSettings.mainToolbarIconColor,
          onChanged: (Color val) => DB().colorSettings =
              colorSettings.copyWith(mainToolbarIconColor: val),
        ),
        SettingsListTile.color(
          titleString: S.of(context).navigationToolbarBackgroundColor,
          value: DB().colorSettings.navigationToolbarBackgroundColor,
          onChanged: (Color val) => DB().colorSettings = colorSettings.copyWith(
            navigationToolbarBackgroundColor: val,
          ),
        ),
        SettingsListTile.color(
          titleString: S.of(context).navigationToolbarIconColor,
          value: DB().colorSettings.navigationToolbarIconColor,
          onChanged: (Color val) => DB().colorSettings = colorSettings.copyWith(
            navigationToolbarIconColor: val,
          ),
        ),
      ],
    );
  }

  void _selectLanguage(BuildContext context, DisplaySettings displaySettings) {
    showDialog<Locale?>(
      context: context,
      builder: (BuildContext context) => _LanguagePicker(
        currentLanguageLocale: displaySettings.locale,
      ),
    ).then((Locale? newLocale) {
      if (displaySettings.locale != newLocale) {
        langCallback(context, displaySettings, newLocale);
      }
    });
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
          onTap: () => _selectLanguage(context, displaySettings),
        ),

        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
          SettingsListTile.switchTile(
            value: displaySettings.isFullScreen,
            onChanged: (bool val) {
              DB().displaySettings =
                  displaySettings.copyWith(isFullScreen: val);
              rootScaffoldMessengerKey.currentState!
                  .showSnackBarClear(S.of(context).reopenToTakeEffect);
            },
            titleString: S.of(context).fullScreen,
          ),
        SettingsListTile.switchTile(
          value: displaySettings.isPieceCountInHandShown,
          onChanged: (bool val) => DB().displaySettings =
              displaySettings.copyWith(isPieceCountInHandShown: val),
          titleString: S.of(context).isPieceCountInHandShown,
        ),
        if (!(Constants.isSmallScreen(context) == true &&
            DB().ruleSettings.piecesCount > 9))
          SettingsListTile.switchTile(
            value: displaySettings.isUnplacedAndRemovedPiecesShown,
            onChanged: (bool val) => DB().displaySettings =
                displaySettings.copyWith(isUnplacedAndRemovedPiecesShown: val),
            titleString: S.of(context).isUnplacedAndRemovedPiecesShown,
          ),
        SettingsListTile.switchTile(
          value: displaySettings.isNotationsShown,
          onChanged: (bool val) => DB().displaySettings =
              displaySettings.copyWith(isNotationsShown: val),
          titleString: S.of(context).isNotationsShown,
        ),
        SettingsListTile.switchTile(
          value: displaySettings.isHistoryNavigationToolbarShown,
          onChanged: (bool val) => DB().displaySettings =
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
        SettingsListTile(
          titleString: S.of(context).aiResponseDelayTime,
          onTap: () => setAiResponseDelayTime(context),
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
          leading: CustomDrawerIcon.of(context)?.drawerIcon,
          title: Text(S.of(context).appearance),
        ),
        body: SettingsList(
          children: <Widget>[
            ValueListenableBuilder<Box<DisplaySettings>>(
              valueListenable: DB().listenDisplaySettings,
              builder: _buildDisplaySettings,
            ),
            if (Constants.isSmallScreen(context) == false)
              ValueListenableBuilder<Box<ColorSettings>>(
                valueListenable: DB().listenColorSettings,
                builder: _buildColorSettings,
              ),
          ],
        ),
      ),
    );
  }
}
