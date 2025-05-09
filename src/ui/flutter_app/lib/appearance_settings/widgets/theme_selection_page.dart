// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// theme_selection_page.dart

import 'dart:convert';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/services/environment_config.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
import '../models/color_settings.dart';

/// A page that displays all available themes as mini boards,
/// allowing users to visually preview and select a theme.
class ThemeSelectionPage extends StatefulWidget {
  const ThemeSelectionPage({
    super.key,
    required this.currentTheme,
  });

  final ColorTheme currentTheme;

  @override
  State<ThemeSelectionPage> createState() => _ThemeSelectionPageState();
}

class _ThemeSelectionPageState extends State<ThemeSelectionPage> {
  // List to store custom themes
  late List<ColorSettings> _customThemes;

  @override
  void initState() {
    super.initState();
    // Load custom themes from database
    _customThemes = DB().customThemes;
  }

  // Add this function to share theme JSON
  void _shareThemeJson(ColorSettings colorSettings) {
    // Convert the color settings to JSON string
    final String json = jsonEncode(colorSettings.toJson());

    if (EnvironmentConfig.test) {
      // Print the JSON string in test mode
      logger.i(json);
      return;
    }

    // Share the JSON string
    SharePlus.instance.share(
      ShareParams(
        text: json,
        subject: 'Custom Theme Settings',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get all theme keys except the "custom" theme
    final List<ColorTheme> builtInThemes = AppTheme.colorThemes.keys
        .where((ColorTheme theme) => theme != ColorTheme.custom)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          S.of(context).theme,
          style: const TextStyle(fontSize: AppTheme.largeFontSize),
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, // Two themes per row
          childAspectRatio: 0.8, // Aspect ratio for the grid items
          crossAxisSpacing: 16.0,
          mainAxisSpacing: 16.0,
        ),
        // Update the item count to use builtInThemes instead of all themes
        itemCount: builtInThemes.length +
            1 +
            _customThemes.length, // Add 1 for Current theme + custom themes
        itemBuilder: (BuildContext context, int index) {
          // Add Current theme as the first item
          if (index == 0) {
            // Get current theme settings directly from the database
            final ColorSettings currentColors = DB().colorSettings;

            return ThemePreviewItem(
              theme: ColorTheme.current,
              colors: currentColors,
              isSelected: widget.currentTheme == ColorTheme.current,
              onTap: () {
                // Just exit without returning a value
                Navigator.pop(context);
              },
              hasActionButton: true,
              actionIcon: FluentIcons.save_20_regular,
              actionTooltip: 'Save as custom theme',
              onActionPressed: () {
                // Save current theme as custom
                setState(() {
                  _customThemes.add(currentColors);
                  // Save to database for persistence
                  DB().customThemes = _customThemes;
                });
              },
              // Add share button to current theme
              hasShareButton: true,
              shareIcon: FluentIcons.share_20_regular,
              shareTooltip: 'Share current theme',
              onSharePressed: () => _shareThemeJson(currentColors),
            );
          }

          // Check if this is a custom theme
          if (index > 0 && index <= _customThemes.length) {
            final int customIndex = index - 1;
            final ColorSettings customColors = _customThemes[customIndex];

            return ThemePreviewItem(
              theme: ColorTheme.custom,
              colors: customColors,
              isSelected:
                  widget.currentTheme == ColorTheme.custom && customIndex == 0,
              // Only first custom can be selected
              onTap: () {
                // Update the custom theme in AppTheme.colorThemes so the system can access it
                AppTheme.updateCustomTheme(customColors);

                // Save to database
                DB().colorSettings = customColors;

                // Return the custom theme enum to caller
                Navigator.pop(context, ColorTheme.custom);
              },
              hasActionButton: true,
              actionIcon: FluentIcons.delete_20_regular,
              actionTooltip: 'Delete custom theme',
              onActionPressed: () {
                // Delete this custom theme
                setState(() {
                  _customThemes.removeAt(customIndex);
                  // Update database
                  DB().customThemes = _customThemes;
                });
              },
              hasShareButton: true,
              shareIcon: FluentIcons.share_20_regular,
              shareTooltip: 'Share custom theme',
              onSharePressed: () => _shareThemeJson(customColors),
            );
          }

          // Adjust index for the built-in themes and use builtInThemes list
          final int themeIndex = index - 1 - _customThemes.length;
          final ColorTheme theme = builtInThemes[themeIndex];
          final ColorSettings colors = AppTheme.colorThemes[theme]!;

          return ThemePreviewItem(
            theme: theme,
            colors: colors,
            isSelected: theme == widget.currentTheme,
            onTap: () {
              Navigator.pop(context, theme);
            },
          );
        },
      ),
    );
  }
}

/// A widget that displays a preview of a theme with a mini board
/// and the theme name.
class ThemePreviewItem extends StatelessWidget {
  const ThemePreviewItem({
    super.key,
    required this.theme,
    required this.colors,
    required this.isSelected,
    required this.onTap,
    this.hasActionButton = false,
    this.actionIcon,
    this.actionTooltip,
    this.onActionPressed,
    this.hasShareButton = false,
    this.shareIcon,
    this.shareTooltip,
    this.onSharePressed,
  });

  final ColorTheme theme;
  final ColorSettings colors;
  final bool isSelected;
  final VoidCallback onTap;
  final bool hasActionButton;
  final IconData? actionIcon;
  final String? actionTooltip;
  final VoidCallback? onActionPressed;
  final bool hasShareButton;
  final IconData? shareIcon;
  final String? shareTooltip;
  final VoidCallback? onSharePressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Card(
        elevation: isSelected ? 4.0 : 1.0,
        color: colors.darkBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
          side: isSelected
              ? const BorderSide(color: Colors.green, width: 2.0)
              : BorderSide.none,
        ),
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ThemePreviewBoard(colors: colors),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    _getThemeName(context, theme),
                    style: TextStyle(
                      fontSize: 14.0,
                      color: colors.messageColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            // Action button (Save or Delete)
            if (hasActionButton && actionIcon != null)
              Positioned(
                right: 4.0,
                bottom: 4.0,
                child: IconButton(
                  icon: Icon(
                    actionIcon,
                    color: colors.messageColor,
                    size: 20.0,
                  ),
                  tooltip: actionTooltip,
                  onPressed: onActionPressed,
                ),
              ),
            // Share button in bottom-left
            if (hasShareButton && shareIcon != null)
              Positioned(
                left: 4.0,
                bottom: 4.0,
                child: IconButton(
                  icon: Icon(
                    shareIcon,
                    color: colors.messageColor,
                    size: 20.0,
                  ),
                  tooltip: shareTooltip,
                  onPressed: onSharePressed,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Convert theme enum to readable name
  String _getThemeName(BuildContext context, ColorTheme theme) {
    switch (theme) {
      case ColorTheme.light:
        return S.of(context).light;
      case ColorTheme.dark:
        return S.of(context).dark;
      case ColorTheme.monochrome:
        return S.of(context).monochrome;
      case ColorTheme.transparentCanvas:
        return S.of(context).transparentCanvas;
      case ColorTheme.autumnLeaves:
        return S.of(context).autumnLeaves;
      case ColorTheme.legendaryLand:
        return S.of(context).legendaryLand;
      case ColorTheme.goldenJade:
        return S.of(context).goldenJade;
      case ColorTheme.forestWood:
        return S.of(context).forestWood;
      case ColorTheme.greenMeadow:
        return S.of(context).greenMeadow;
      case ColorTheme.stonyPath:
        return S.of(context).stonyPath;
      case ColorTheme.midnightBlue:
        return S.of(context).midnightBlue;
      case ColorTheme.greenForest:
        return S.of(context).greenForest;
      case ColorTheme.pastelPink:
        return S.of(context).pastelPink;
      case ColorTheme.turquoiseSea:
        return S.of(context).turquoiseSea;
      case ColorTheme.violetDream:
        return S.of(context).violetDream;
      case ColorTheme.mintChocolate:
        return S.of(context).mintChocolate;
      case ColorTheme.skyBlue:
        return S.of(context).skyBlue;
      case ColorTheme.playfulGarden:
        return S.of(context).playfulGarden;
      case ColorTheme.darkMystery:
        return S.of(context).darkMystery;
      case ColorTheme.ancientEgypt:
        return S.of(context).ancientEgypt;
      case ColorTheme.gothicIce:
        return S.of(context).gothicIce;
      case ColorTheme.riceField:
        return S.of(context).riceField;
      case ColorTheme.chinesePorcelain:
        return S.of(context).chinesePorcelain;
      case ColorTheme.desertDusk:
        return S.of(context).desertDusk;
      case ColorTheme.precisionCraft:
        return S.of(context).precisionCraft;
      case ColorTheme.folkEmbroidery:
        return S.of(context).folkEmbroidery;
      case ColorTheme.carpathianHeritage:
        return S.of(context).carpathianHeritage;
      case ColorTheme.imperialGrandeur:
        return S.of(context).imperialGrandeur;
      case ColorTheme.bohemianCrystal:
        return S.of(context).bohemianCrystal;
      case ColorTheme.savannaSunrise:
        return S.of(context).savannaSunrise;
      case ColorTheme.harmonyBalance:
        return S.of(context).harmonyBalance;
      case ColorTheme.cinnamonSpice:
        return S.of(context).cinnamonSpice;
      case ColorTheme.anatolianMosaic:
        return S.of(context).anatolianMosaic;
      case ColorTheme.carnivalSpirit:
        return S.of(context).carnivalSpirit;
      case ColorTheme.spiceMarket:
        return S.of(context).spiceMarket;
      case ColorTheme.current:
        return S.of(context).currentTheme;
      case ColorTheme.custom:
        return S.of(context).custom;
    }
  }
}

/// A widget that displays a preview of the board with the theme colors.
class ThemePreviewBoard extends StatelessWidget {
  const ThemePreviewBoard({
    super.key,
    required this.colors,
  });

  final ColorSettings colors;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8.0),
      child: Container(
        color: colors.boardBackgroundColor,
        child: CustomPaint(
          painter: ThemePreviewPainter(colors: colors),
          child: Container(),
        ),
      ),
    );
  }
}

/// A custom painter that draws a simplified Mill board with theme colors.
class ThemePreviewPainter extends CustomPainter {
  ThemePreviewPainter({required this.colors});

  final ColorSettings colors;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double minSide = math.min(w, h);

    // Center the board
    final double offsetX = (w - minSide) / 2;
    final double offsetY = (h - minSide) / 2;

    // Parameters for the board layout
    const double outerMarginFactor = 0.1;
    const double ringSpacingFactor = 0.2;
    const double pieceRadiusFactor = 0.08;

    final double outerMargin = minSide * outerMarginFactor;
    final double ringSpacing = minSide * ringSpacingFactor;
    final double pieceRadius = minSide * pieceRadiusFactor;

    // Calculate dimensions for the rings
    final double outerSize = minSide - 2 * outerMargin;
    final double middleSize = outerSize - 2 * ringSpacing;
    final double innerSize = middleSize - 2 * ringSpacing;

    // Board lines paint
    final Paint boardPaint = Paint()
      ..color = colors.boardLineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, minSide * 0.01);

    // Draw outer square
    final Rect outerRect = Rect.fromLTWH(
        offsetX + outerMargin, offsetY + outerMargin, outerSize, outerSize);
    canvas.drawRect(outerRect, boardPaint);

    // Draw middle square
    final Rect middleRect = Rect.fromLTWH(offsetX + outerMargin + ringSpacing,
        offsetY + outerMargin + ringSpacing, middleSize, middleSize);
    canvas.drawRect(middleRect, boardPaint);

    // Draw inner square
    final Rect innerRect = Rect.fromLTWH(
        offsetX + outerMargin + 2 * ringSpacing,
        offsetY + outerMargin + 2 * ringSpacing,
        innerSize,
        innerSize);
    canvas.drawRect(innerRect, boardPaint);

    // Draw connecting lines
    // Top middle
    canvas.drawLine(
        Offset(offsetX + minSide / 2, offsetY + outerMargin),
        Offset(offsetX + minSide / 2, offsetY + outerMargin + 2 * ringSpacing),
        boardPaint);

    // Bottom middle
    canvas.drawLine(
        Offset(offsetX + minSide / 2, offsetY + minSide - outerMargin),
        Offset(offsetX + minSide / 2,
            offsetY + minSide - outerMargin - 2 * ringSpacing),
        boardPaint);

    // Left middle
    canvas.drawLine(
        Offset(offsetX + outerMargin, offsetY + minSide / 2),
        Offset(offsetX + outerMargin + 2 * ringSpacing, offsetY + minSide / 2),
        boardPaint);

    // Right middle
    canvas.drawLine(
        Offset(offsetX + minSide - outerMargin, offsetY + minSide / 2),
        Offset(offsetX + minSide - outerMargin - 2 * ringSpacing,
            offsetY + minSide / 2),
        boardPaint);

    // Draw piece samples
    // White piece in top-left
    final Paint whitePaint = Paint()
      ..color = colors.whitePieceColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(offsetX + outerMargin, offsetY + outerMargin),
        pieceRadius, whitePaint);

    // Black piece in bottom-right
    final Paint blackPaint = Paint()
      ..color = colors.blackPieceColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
        Offset(
            offsetX + minSide - outerMargin, offsetY + minSide - outerMargin),
        pieceRadius,
        blackPaint);

    // Highlighted piece in top-right
    final Paint highlightPaint = Paint()
      ..color = colors.pieceHighlightColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(
        Offset(offsetX + minSide - outerMargin, offsetY + outerMargin),
        pieceRadius,
        whitePaint);

    canvas.drawCircle(
        Offset(offsetX + minSide - outerMargin, offsetY + outerMargin),
        pieceRadius + 2,
        highlightPaint);
  }

  @override
  bool shouldRepaint(covariant ThemePreviewPainter oldDelegate) {
    return oldDelegate.colors != colors;
  }
}
