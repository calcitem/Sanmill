// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// kids_ui_service.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../appearance_settings/models/color_settings.dart';
import '../database/database.dart';
import '../themes/kids_theme.dart';
import 'logger.dart';

/// Service for managing kids-friendly UI elements and interactions
/// Designed to meet Google Play for Education and Teacher Approved guidelines
class KidsUIService {
  KidsUIService._();

  static final KidsUIService _instance = KidsUIService._();
  static KidsUIService get instance => _instance;

  /// Check if kids mode is currently enabled
  bool get isKidsModeEnabled => DB().generalSettings.kidsMode ?? false;

  /// Get current kids theme
  KidsColorTheme get currentKidsTheme =>
      DB().displaySettings.kidsTheme ?? KidsColorTheme.sunnyPlayground;

  /// Initialize kids-friendly system UI
  Future<void> initializeKidsUI() async {
    if (!isKidsModeEnabled) {
      return;
    }

    // Set system UI for kids mode with softer colors
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness:
            Brightness.dark, // Dark icons for better visibility
        systemNavigationBarColor: KidsTheme
            .kidsColorThemes[currentKidsTheme]!.darkBackgroundColor
            .withOpacity(0.8),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // Ensure safe area padding for kids' fingers
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: <SystemUiOverlay>[SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
  }

  /// Get kids-friendly text style with improved readability
  TextStyle getKidsTextStyle(
    BuildContext? context, {
    double? baseFontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
  }) {
    final double baseSize = baseFontSize ?? KidsTheme.kidsDefaultFontSize;

    // Use default color if context is null or Theme.of fails
    Color? textColor = color;
    if (textColor == null && context != null) {
      try {
        textColor = Theme.of(context).textTheme.bodyLarge?.color;
      } catch (e) {
        // If Theme.of fails, use default color
        textColor = const Color(0xFF333333); // Default dark gray
      }
    } else {
      textColor ??= const Color(0xFF333333);
    }

    return TextStyle(
      fontSize: baseSize,
      fontWeight:
          fontWeight ?? FontWeight.w500, // Slightly bolder for readability
      color: textColor,
      letterSpacing: letterSpacing ?? 0.3, // Better letter spacing for kids
      height: 1.4, // Better line height for readability
    );
  }

  /// Create kids-friendly button with large touch target
  Widget createKidsButton({
    required String text,
    required VoidCallback onPressed,
    IconData? icon,
    Color? backgroundColor,
    Color? textColor,
    double? width,
    double? height,
    bool isPrimary = true,
  }) {
    return Builder(builder: (BuildContext context) {
      final ColorSettings colorSettings =
          KidsTheme.kidsColorThemes[currentKidsTheme]!;

      return Container(
        width: width ?? KidsTheme.kidsButtonWidth,
        height: height ?? KidsTheme.kidsButtonHeight,
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: ElevatedButton(
          onPressed: () {
            // Provide haptic feedback for better user experience
            HapticFeedback.lightImpact();
            onPressed();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor ??
                (isPrimary
                    ? colorSettings.darkBackgroundColor
                    : colorSettings.boardBackgroundColor),
            foregroundColor: textColor ?? Colors.white,
            padding: const EdgeInsets.all(16.0),
            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(20.0), // Very rounded for kids
            ),
            elevation: 6.0, // More elevation for depth perception
            shadowColor: Colors.black26,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: KidsTheme.kidsIconSize),
                const SizedBox(width: 8.0),
              ],
              Flexible(
                child: Text(
                  text,
                  style: getKidsTextStyle(
                    context,
                    baseFontSize: KidsTheme.kidsDefaultFontSize,
                    fontWeight: FontWeight.w600,
                    color: textColor ?? Colors.white,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// Create kids-friendly card with rounded corners and large padding
  Widget createKidsCard({
    required Widget child,
    EdgeInsets? padding,
    Color? backgroundColor,
    double? elevation,
  }) {
    return Builder(builder: (BuildContext context) {
      final ColorSettings colorSettings =
          KidsTheme.kidsColorThemes[currentKidsTheme]!;

      return Card(
        color: backgroundColor ?? colorSettings.boardBackgroundColor,
        elevation: elevation ?? 8.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.0), // Very rounded for kids
        ),
        margin: const EdgeInsets.all(12.0),
        child: Padding(
          padding:
              padding ?? const EdgeInsets.all(20.0), // Large padding for kids
          child: child,
        ),
      );
    });
  }

  /// Create kids-friendly dialog with large text and buttons
  Widget createKidsDialog({
    required String title,
    required String content,
    required List<Widget> actions,
    Widget? icon,
  }) {
    return Builder(builder: (BuildContext context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28.0), // Very rounded
        ),
        title: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              icon,
              const SizedBox(width: 12.0),
            ],
            Expanded(
              child: Text(
                title,
                style: getKidsTextStyle(
                  context,
                  baseFontSize: KidsTheme.kidsLargeFontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          content,
          style: getKidsTextStyle(
            context,
            baseFontSize: KidsTheme.kidsDefaultFontSize,
          ),
        ),
        actions: actions,
        actionsPadding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0),
        contentPadding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 24.0),
        titlePadding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 0.0),
      );
    });
  }

  /// Create educational hint bubble for teaching game rules
  Widget createEducationalHint({
    required String message,
    required VoidCallback onDismiss,
    IconData? icon,
  }) {
    return Builder(builder: (BuildContext context) {
      final ColorSettings colorSettings =
          KidsTheme.kidsColorThemes[currentKidsTheme]!;

      return Container(
        margin: const EdgeInsets.all(16.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: colorSettings.pieceHighlightColor.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20.0),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8.0,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                size: KidsTheme.kidsIconSize,
                color: Colors.white,
              ),
              const SizedBox(width: 12.0),
            ],
            Expanded(
              child: Text(
                message,
                style: getKidsTextStyle(
                  context,
                  baseFontSize: KidsTheme.kidsDefaultFontSize,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
            IconButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                onDismiss();
              },
              icon: const Icon(
                Icons.close,
                color: Colors.white,
                size: 24.0,
              ),
              padding: const EdgeInsets.all(8.0),
            ),
          ],
        ),
      );
    });
  }

  /// Create progress indicator for kids with fun animations
  Widget createKidsProgressIndicator({
    double? value,
    String? label,
    Color? color,
  }) {
    return Builder(builder: (BuildContext context) {
      final ColorSettings colorSettings =
          KidsTheme.kidsColorThemes[currentKidsTheme]!;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (label != null) ...<Widget>[
            Text(
              label,
              style: getKidsTextStyle(
                context,
                baseFontSize: KidsTheme.kidsDefaultFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12.0),
          ],
          SizedBox(
            width: 100.0,
            height: 100.0,
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 8.0,
              backgroundColor: colorSettings.boardBackgroundColor,
              valueColor: AlwaysStoppedAnimation<Color>(
                color ?? colorSettings.pieceHighlightColor,
              ),
            ),
          ),
        ],
      );
    });
  }

  /// Show educational celebration animation when kids complete a task
  void showCelebration(BuildContext context, {String? message}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => createKidsDialog(
        title: '🎉 Great Job! 🎉',
        content: message ?? 'You did amazing! Keep playing and learning!',
        icon: const Icon(
          Icons.star,
          color: Colors.yellow,
          size: 32.0,
        ),
        actions: <Widget>[
          createKidsButton(
            text: 'Continue',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icons.arrow_forward,
          ),
        ],
      ),
    );

    // Add haptic celebration feedback
    HapticFeedback.heavyImpact();

    // Auto-dismiss after 3 seconds for better UX
    Future.delayed(const Duration(seconds: 3), () {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  /// Create accessibility-friendly widget with proper semantics
  Widget createAccessibleWidget({
    required Widget child,
    required String semanticLabel,
    String? semanticHint,
    bool excludeSemantics = false,
  }) {
    return Semantics(
      label: semanticLabel,
      hint: semanticHint,
      excludeSemantics: excludeSemantics,
      child: child,
    );
  }

  /// Toggle kids mode and apply appropriate theme
  Future<void> toggleKidsMode(bool enabled) async {
    // TODO: Update kids mode setting - temporarily disabled until copyWith is available
    // DB().generalSettings = DB().generalSettings.copyWith(kidsMode: enabled);

    if (enabled) {
      // TODO: Set default kids theme - temporarily disabled until copyWith is available
      // final currentDisplay = DB().displaySettings;
      // if (currentDisplay.kidsTheme == null) {
      //   DB().displaySettings = DB().displaySettings.copyWith(
      //     kidsTheme: KidsColorTheme.sunnyPlayground,
      //   );
      // }
      await initializeKidsUI();
    }

    logger.i(
        'Kids mode ${enabled ? 'enabled' : 'disabled'} (temporary implementation)');
  }

  /// Switch to a different kids theme
  Future<void> switchKidsTheme(KidsColorTheme theme) async {
    // TODO: Update kids theme - temporarily disabled until copyWith is available
    // DB().displaySettings = DB().displaySettings.copyWith(kidsTheme: theme);

    if (isKidsModeEnabled) {
      await initializeKidsUI();
    }

    logger.i('Kids theme switched to: $theme (temporary implementation)');
  }

  /// Get safe color for kids (avoid scary colors like pure black)
  Color getSafeColor(Color originalColor) {
    // Replace pure black with dark blue for less intimidating appearance
    if (originalColor == Colors.black) {
      return const Color(0xFF1A237E); // Dark blue
    }

    // Replace very dark colors with slightly lighter versions
    final HSLColor hsl = HSLColor.fromColor(originalColor);
    if (hsl.lightness < 0.1) {
      return hsl.withLightness(0.2).toColor();
    }

    return originalColor;
  }
}
