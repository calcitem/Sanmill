// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// theme_selection_page.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/themes/app_theme.dart';
import '../models/color_settings.dart';

/// A page that displays all available themes as mini boards,
/// allowing users to visually preview and select a theme.
class ThemeSelectionPage extends StatelessWidget {
  const ThemeSelectionPage({
    super.key,
    required this.currentTheme,
  });

  final ColorTheme currentTheme;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).theme),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, // Two themes per row
          childAspectRatio: 0.8, // Aspect ratio for the grid items
          crossAxisSpacing: 16.0,
          mainAxisSpacing: 16.0,
        ),
        itemCount: AppTheme.colorThemes.length,
        itemBuilder: (BuildContext context, int index) {
          final ColorTheme theme = AppTheme.colorThemes.keys.elementAt(index);
          final ColorSettings colors = AppTheme.colorThemes[theme]!;

          return ThemePreviewItem(
            theme: theme,
            colors: colors,
            isSelected: theme == currentTheme,
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
  });

  final ColorTheme theme;
  final ColorSettings colors;
  final bool isSelected;
  final VoidCallback onTap;

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
        child: Column(
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
      case ColorTheme.current:
        return S.of(context).currentTheme;
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
