// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// theme_selection_page.dart

import 'dart:convert';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/services/environment_config.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_styles.dart';
import '../../shared/themes/app_theme.dart';
import '../models/color_settings.dart';

String colorThemeLabel(BuildContext context, ColorTheme theme) {
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

/// A page that displays all available themes as mini boards,
/// allowing users to visually preview and select a theme.
class ThemeSelectionPage extends StatefulWidget {
  const ThemeSelectionPage({super.key, required this.currentTheme});

  final ColorTheme currentTheme;

  @override
  State<ThemeSelectionPage> createState() => _ThemeSelectionPageState();
}

class _ThemeSelectionPageState extends State<ThemeSelectionPage> {
  // List to store custom themes
  late List<ColorSettings> _customThemes;
  late final Map<String, dynamic> _appliedColorsSnapshot;

  @override
  void initState() {
    super.initState();
    // Load custom themes from database
    _customThemes = DB().customThemes;
    _appliedColorsSnapshot = DB().colorSettings.toJson();
  }

  /// Check if the given color settings match the currently applied colors
  bool _matchesCurrentColors(ColorSettings colors) {
    final Map<String, dynamic> candidate = colors.toJson();
    return mapEquals(candidate, _appliedColorsSnapshot);
  }

  /// Determine if current theme item should be selected
  /// Always show as selected, but especially when no other theme matches
  bool _shouldSelectCurrentTheme() {
    return true; // Current theme is always conceptually selected
  }

  /// Determine if a built-in theme should be selected
  bool _shouldSelectBuiltInTheme(ColorTheme theme) {
    // Show as selected if this theme matches current colors
    final ColorSettings themeColors = AppTheme.colorThemes[theme]!;
    return _matchesCurrentColors(themeColors);
  }

  /// Determine if a custom theme should be selected
  bool _shouldSelectCustomTheme(ColorSettings customColors) {
    // Show as selected if this custom theme matches current colors
    return _matchesCurrentColors(customColors);
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
      ShareParams(text: json, subject: 'Custom Theme Settings'),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get all theme keys except the "custom" theme
    final List<ColorTheme> builtInThemes = AppTheme.colorThemes.keys
        .where((ColorTheme theme) => theme != ColorTheme.custom)
        .toList();
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(S.of(context).theme, style: AppStyles.pageTitle),
      ),
      body: SafeArea(
        child: ListView.separated(
          key: const Key('theme_selection_list'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: builtInThemes.length + 1 + _customThemes.length,
          separatorBuilder: (BuildContext context, int index) {
            if (Theme.of(context).platform == TargetPlatform.iOS) {
              return const Divider(height: 0, indent: AppStyles.bodyPadding);
            }
            return const SizedBox.shrink();
          },
          itemBuilder: (BuildContext context, int index) {
            if (index == 0) {
              final ColorSettings currentColors = DB().colorSettings;

              return ThemePreviewItem(
                key: const Key('theme_preview_current'),
                theme: ColorTheme.current,
                colors: currentColors,
                isSelected: _shouldSelectCurrentTheme(),
                onTap: () {
                  Navigator.pop(context);
                },
                actionIcon: FluentIcons.save_20_regular,
                actionTooltip: S.of(context).saveTheme,
                onActionPressed: () {
                  setState(() {
                    _customThemes.add(currentColors);
                    DB().customThemes = _customThemes;
                  });
                },
                shareIcon: FluentIcons.share_20_regular,
                shareTooltip: S.of(context).shareQrCode,
                onSharePressed: () => _shareThemeJson(currentColors),
              );
            }

            if (index > 0 && index <= _customThemes.length) {
              final int customIndex = index - 1;
              final ColorSettings customColors = _customThemes[customIndex];

              return ThemePreviewItem(
                key: Key('theme_preview_custom_$customIndex'),
                theme: ColorTheme.custom,
                colors: customColors,
                isSelected: _shouldSelectCustomTheme(customColors),
                onTap: () {
                  AppTheme.updateCustomTheme(customColors);
                  DB().colorSettings = customColors;
                  Navigator.pop(context, ColorTheme.custom);
                },
                actionIcon: FluentIcons.delete_20_regular,
                actionTooltip: S.of(context).delete,
                onActionPressed: () {
                  setState(() {
                    _customThemes.removeAt(customIndex);
                    DB().customThemes = _customThemes;
                  });
                },
                shareIcon: FluentIcons.share_20_regular,
                shareTooltip: S.of(context).shareQrCode,
                onSharePressed: () => _shareThemeJson(customColors),
              );
            }

            final int themeIndex = index - 1 - _customThemes.length;
            final ColorTheme colorTheme = builtInThemes[themeIndex];
            final ColorSettings colors = AppTheme.colorThemes[colorTheme]!;

            return ThemePreviewItem(
              key: Key('theme_preview_${colorTheme.name}'),
              theme: colorTheme,
              colors: colors,
              isSelected: _shouldSelectBuiltInTheme(colorTheme),
              onTap: () {
                Navigator.pop(context, colorTheme);
              },
            );
          },
        ),
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
    this.actionIcon,
    this.actionTooltip,
    this.onActionPressed,
    this.shareIcon,
    this.shareTooltip,
    this.onSharePressed,
  });

  final ColorTheme theme;
  final ColorSettings colors;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? actionIcon;
  final String? actionTooltip;
  final VoidCallback? onActionPressed;
  final IconData? shareIcon;
  final String? shareTooltip;
  final VoidCallback? onSharePressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextStyle titleStyle = AppStyles.tileTitle.copyWith(
      color: isSelected ? colorScheme.primary : colorScheme.onSurface,
      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
    );

    return Material(
      color: isSelected
          ? colorScheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppStyles.bodyPadding,
            vertical: 12,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      colorThemeLabel(context, this.theme),
                      style: titleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SizedBox(
                        width: 136,
                        height: 96,
                        child: ThemePreviewBoard(colors: colors),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (shareIcon != null)
                    IconButton(
                      icon: Icon(shareIcon),
                      tooltip: shareTooltip,
                      visualDensity: VisualDensity.compact,
                      color: colorScheme.onSurfaceVariant,
                      onPressed: onSharePressed,
                    ),
                  if (actionIcon != null)
                    IconButton(
                      icon: Icon(actionIcon),
                      tooltip: actionTooltip,
                      visualDensity: VisualDensity.compact,
                      color: colorScheme.onSurfaceVariant,
                      onPressed: onActionPressed,
                    ),
                  SizedBox(
                    width: 32,
                    child: isSelected
                        ? Icon(Icons.check_rounded, color: colorScheme.primary)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A widget that displays a preview of the board with the theme colors.
class ThemePreviewBoard extends StatelessWidget {
  const ThemePreviewBoard({super.key, required this.colors});

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
      offsetX + outerMargin,
      offsetY + outerMargin,
      outerSize,
      outerSize,
    );
    canvas.drawRect(outerRect, boardPaint);

    // Draw middle square
    final Rect middleRect = Rect.fromLTWH(
      offsetX + outerMargin + ringSpacing,
      offsetY + outerMargin + ringSpacing,
      middleSize,
      middleSize,
    );
    canvas.drawRect(middleRect, boardPaint);

    // Draw inner square
    final Rect innerRect = Rect.fromLTWH(
      offsetX + outerMargin + 2 * ringSpacing,
      offsetY + outerMargin + 2 * ringSpacing,
      innerSize,
      innerSize,
    );
    canvas.drawRect(innerRect, boardPaint);

    // Draw connecting lines
    // Top middle
    canvas.drawLine(
      Offset(offsetX + minSide / 2, offsetY + outerMargin),
      Offset(offsetX + minSide / 2, offsetY + outerMargin + 2 * ringSpacing),
      boardPaint,
    );

    // Bottom middle
    canvas.drawLine(
      Offset(offsetX + minSide / 2, offsetY + minSide - outerMargin),
      Offset(
        offsetX + minSide / 2,
        offsetY + minSide - outerMargin - 2 * ringSpacing,
      ),
      boardPaint,
    );

    // Left middle
    canvas.drawLine(
      Offset(offsetX + outerMargin, offsetY + minSide / 2),
      Offset(offsetX + outerMargin + 2 * ringSpacing, offsetY + minSide / 2),
      boardPaint,
    );

    // Right middle
    canvas.drawLine(
      Offset(offsetX + minSide - outerMargin, offsetY + minSide / 2),
      Offset(
        offsetX + minSide - outerMargin - 2 * ringSpacing,
        offsetY + minSide / 2,
      ),
      boardPaint,
    );

    // Draw piece samples
    // White piece in top-left
    final Paint whitePaint = Paint()
      ..color = colors.whitePieceColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(offsetX + outerMargin, offsetY + outerMargin),
      pieceRadius,
      whitePaint,
    );

    // Black piece in bottom-right
    final Paint blackPaint = Paint()
      ..color = colors.blackPieceColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(offsetX + minSide - outerMargin, offsetY + minSide - outerMargin),
      pieceRadius,
      blackPaint,
    );

    // Highlighted piece in top-right
    final Paint highlightPaint = Paint()
      ..color = colors.pieceHighlightColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(
      Offset(offsetX + minSide - outerMargin, offsetY + outerMargin),
      pieceRadius,
      whitePaint,
    );

    canvas.drawCircle(
      Offset(offsetX + minSide - outerMargin, offsetY + outerMargin),
      pieceRadius + 2,
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant ThemePreviewPainter oldDelegate) {
    return oldDelegate.colors != colors;
  }
}
