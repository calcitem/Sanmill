// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../shared/widgets/settings/settings.dart';
import '../../custom_drawer/custom_drawer.dart';
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

part 'package:sanmill/appearance_settings/widgets/modals/point_painting_style_modal.dart';
part 'package:sanmill/appearance_settings/widgets/pickers/background_image_picker.dart';
part 'package:sanmill/appearance_settings/widgets/pickers/board_image_picker.dart';
part 'package:sanmill/appearance_settings/widgets/pickers/image_crop_page.dart';
part 'package:sanmill/appearance_settings/widgets/pickers/language_picker.dart';
part 'package:sanmill/appearance_settings/widgets/pickers/piece_image_picker.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/animation_duration_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/board_corner_radius_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/board_boarder_line_width_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/board_inner_line_width_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/board_top_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/font_size_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/piece_width_slider.dart';
part 'package:sanmill/appearance_settings/widgets/sliders/point_width_slider.dart';
part 'package:sanmill/shared/themes/theme_modal.dart';

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

  void setPointPaintingStyle(
      BuildContext context, DisplaySettings displaySettings) {
    dynamic callback(PointPaintingStyle? pointPaintingStyle) {
      Navigator.pop(context);
      DB().displaySettings =
          displaySettings.copyWith(pointPaintingStyle: pointPaintingStyle);

      logger.t("[config] pointPaintingStyle: $pointPaintingStyle");
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

      logger
          .t("[config] Selected PlaceEffectAnimation: ${selectedEffect.name}");
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

      logger
          .t("[config] Selected RemoveEffectAnimation: ${selectedEffect.name}");
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

  void setPieceImage(BuildContext context) => showModalBottomSheet(
        context: context,
        builder: (_) => const _PieceImagePicker(),
      );

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
        child: Text(
          strClose,
          style: TextStyle(
            fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
          ),
        ),
        onPressed: () => Navigator.pop(context),
      );

      final AlertDialog alert = AlertDialog(
        title: Text(
          strImport,
          style: TextStyle(
            fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
          ),
        ),
        // Show content if it's valid JSON
        content: Text(
          clipboardText,
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
      child: Text(
        S.of(context).copy,
        style: TextStyle(
          fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
        ),
      ),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: content));
        rootScaffoldMessengerKey.currentState!
            .showSnackBarClear(S.of(context).copiedToClipboard);
        Navigator.pop(context);
      },
    );

    final Widget closeButton = TextButton(
      child: Text(
        S.of(context).close,
        style: TextStyle(
          fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
        ),
      ),
      onPressed: () => Navigator.pop(context),
    );

    final AlertDialog alert = AlertDialog(
      title: Text(
        S.of(context).export,
        style: TextStyle(
          fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
        ),
      ),
      content: Text(
        content,
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
        analysisToolbarBackgroundColor:
            AppTheme.colorThemes[theme]!.analysisToolbarBackgroundColor,
        analysisToolbarIconColor:
            AppTheme.colorThemes[theme]!.analysisToolbarIconColor,
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
        if (kDebugMode)
          SettingsListTile.color(
            titleString: S.of(context).analysisToolbarBackgroundColor,
            value: DB().colorSettings.analysisToolbarBackgroundColor,
            onChanged: (Color val) =>
                DB().colorSettings = colorSettings.copyWith(
              analysisToolbarBackgroundColor: val,
            ),
          ),
        if (kDebugMode)
          SettingsListTile.color(
            titleString: S.of(context).analysisToolbarIconColor,
            value: DB().colorSettings.analysisToolbarIconColor,
            onChanged: (Color val) =>
                DB().colorSettings = colorSettings.copyWith(
              analysisToolbarIconColor: val,
            ),
          ),
        SettingsListTile(
          titleString: S.of(context).importColorSettings,
          onTap: () => importColorSettings(context),
        ),
        SettingsListTile(
          titleString: S.of(context).exportColorSettings,
          onTap: () => exportColorSettings(context),
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
      if (!context.mounted) {
        return;
      }
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
        if (kDebugMode)
          SettingsListTile.switchTile(
            value: displaySettings.isAnalysisToolbarShown,
            onChanged: (bool val) => DB().displaySettings =
                displaySettings.copyWith(isAnalysisToolbarShown: val),
            titleString: S.of(context).isAnalysisToolbarShown,
          ),
        SettingsListTile.switchTile(
          value: displaySettings.isToolbarAtBottom,
          onChanged: (bool val) => DB().displaySettings =
              displaySettings.copyWith(isToolbarAtBottom: val),
          titleString: S.of(context).isToolbarAtBottom,
        ),
        SettingsListTile.switchTile(
          value: displaySettings.isPositionalAdvantageIndicatorShown,
          onChanged: (bool val) => DB().displaySettings = displaySettings
              .copyWith(isPositionalAdvantageIndicatorShown: val),
          titleString: S.of(context).showPositionalAdvantageIndicator,
        ),
        SettingsListTile.switchTile(
          value: displaySettings.isAdvantageGraphShown,
          onChanged: (bool val) {
            DB().displaySettings =
                displaySettings.copyWith(isAdvantageGraphShown: val);
            if (val) {
              rootScaffoldMessengerKey.currentState!
                  .showSnackBarClear(S.of(context).advantageGraphHint);
            }
          },
          titleString: S.of(context).showAdvantageGraph,
        ),
        SettingsListTile(
          titleString: S.of(context).boardCornerRadius,
          onTap: () => setBoardCornerRadius(context),
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
          titleString: S.of(context).boardTop,
          onTap: () => setBoardTop(context),
        ),
        SettingsListTile.switchTile(
          value: displaySettings.isNumbersOnPiecesShown,
          onChanged: (bool val) => DB().displaySettings =
              displaySettings.copyWith(isNumbersOnPiecesShown: val),
          titleString: S.of(context).showNumbersOnPieces,
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
          titleString: S.of(context).animationDuration,
          onTap: () => setAnimationDuration(context),
        ),
        SettingsListTile(
          titleString: S.of(context).placeEffectAnimation,
          onTap: () => setPlaceEffectAnimation(context),
        ),
        SettingsListTile(
          titleString: S.of(context).removeEffectAnimation,
          onTap: () => setRemoveEffectAnimation(context),
        ),
        SettingsListTile.switchTile(
          value: displaySettings.vignetteEffectEnabled,
          onChanged: (bool val) => DB().displaySettings =
              displaySettings.copyWith(vignetteEffectEnabled: val),
          titleString: S.of(context).vignetteEffect,
        ),
        SettingsListTile(
          titleString: S.of(context).backgroundImage,
          onTap: () => setBackgroundImage(context),
        ),
        SettingsListTile(
          titleString: S.of(context).boardImage,
          onTap: () => setBoardImage(context),
        ),
        SettingsListTile(
          titleString: S.of(context).pieceImage,
          onTap: () => setPieceImage(context),
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
          title: Text(
            S.of(context).appearance,
            style: AppTheme.appBarTheme.titleTextStyle,
          ),
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
