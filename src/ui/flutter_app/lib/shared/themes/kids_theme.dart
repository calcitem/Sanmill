// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// kids_theme.dart

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../appearance_settings/models/color_settings.dart';
import '../database/database.dart';

/// Kids-friendly theme for Teacher Approved and Family programs
/// Designed to meet Google Play for Education guidelines
@immutable
class KidsTheme {
  const KidsTheme._();

  // Kids-specific color themes optimized for children
  static final Map<KidsColorTheme, ColorSettings> kidsColorThemes = {
    // Bright and cheerful theme with high contrast for easy reading
    KidsColorTheme.sunnyPlayground: const ColorSettings(
      boardBackgroundColor: Color(0xFFF7E7B4), // Warm sunny yellow
      darkBackgroundColor: Color(0xFF4A90E2), // Friendly blue
      boardLineColor: Color(0xFF2E5984), // Strong contrast lines
      whitePieceColor: Color(0xFFFFFFFF), // Pure white for clarity
      blackPieceColor: Color(0xFF1A237E), // Deep blue instead of scary black
      pieceHighlightColor: Color(0xFFFF6B35), // Bright orange highlight
      messageColor: Color(0xFF2E5984), // Dark blue for readability
      drawerColor: Color(0xFF4A90E2), // Match dark background
      drawerTextColor: Color(0xFFFFFFFF), // White text for contrast
      drawerHighlightItemColor: Color(0x33FF6B35), // Semi-transparent orange
      mainToolbarBackgroundColor: Color(0xFF4A90E2),
      mainToolbarIconColor: Color(0xFFFFFFFF),
      navigationToolbarBackgroundColor: Color(0xFF4A90E2),
      navigationToolbarIconColor: Color(0xFFFFFFFF),
      analysisToolbarBackgroundColor: Color(0xFF4A90E2),
      analysisToolbarIconColor: Color(0xFFFFFFFF),
      annotationToolbarBackgroundColor: Color(0xFF4A90E2),
      annotationToolbarIconColor: Color(0xFFFFFFFF),
    ),

    // Nature-inspired green theme
    KidsColorTheme.friendlyForest: const ColorSettings(
      boardBackgroundColor: Color(0xFFB8E6B8), // Light green
      darkBackgroundColor: Color(0xFF2E7D32), // Forest green
      boardLineColor: Color(0xFF1B5E20), // Dark green lines
      whitePieceColor: Color(0xFFFFFDE7), // Cream white
      blackPieceColor: Color(0xFF4527A0), // Purple instead of black
      pieceHighlightColor: Color(0xFFFF9800), // Orange highlight
      messageColor: Color(0xFF1B5E20), // Dark green text
      drawerColor: Color(0xFF2E7D32),
      drawerTextColor: Color(0xFFFFFFFF),
      drawerHighlightItemColor: Color(0x33FF9800),
      mainToolbarBackgroundColor: Color(0xFF2E7D32),
      mainToolbarIconColor: Color(0xFFFFFFFF),
      navigationToolbarBackgroundColor: Color(0xFF2E7D32),
      navigationToolbarIconColor: Color(0xFFFFFFFF),
      analysisToolbarBackgroundColor: Color(0xFF2E7D32),
      analysisToolbarIconColor: Color(0xFFFFFFFF),
      annotationToolbarBackgroundColor: Color(0xFF2E7D32),
      annotationToolbarIconColor: Color(0xFFFFFFFF),
    ),

    // Ocean adventure theme
    KidsColorTheme.oceanAdventure: const ColorSettings(
      boardBackgroundColor: Color(0xFFB3E5FC), // Light ocean blue
      darkBackgroundColor: Color(0xFF0277BD), // Deep ocean blue
      boardLineColor: Color(0xFF01579B), // Navy blue lines
      whitePieceColor: Color(0xFFFFFFFF), // White like sea foam
      blackPieceColor: Color(0xFF6A1B9A), // Purple like sea urchin
      pieceHighlightColor: Color(0xFFFF5722), // Coral orange
      messageColor: Color(0xFF01579B), // Navy text
      drawerColor: Color(0xFF0277BD),
      drawerTextColor: Color(0xFFFFFFFF),
      drawerHighlightItemColor: Color(0x33FF5722),
      mainToolbarBackgroundColor: Color(0xFF0277BD),
      mainToolbarIconColor: Color(0xFFFFFFFF),
      navigationToolbarBackgroundColor: Color(0xFF0277BD),
      navigationToolbarIconColor: Color(0xFFFFFFFF),
      analysisToolbarBackgroundColor: Color(0xFF0277BD),
      analysisToolbarIconColor: Color(0xFFFFFFFF),
      annotationToolbarBackgroundColor: Color(0xFF0277BD),
      annotationToolbarIconColor: Color(0xFFFFFFFF),
    ),

    // Sweet candy theme
    KidsColorTheme.sweetCandy: const ColorSettings(
      boardBackgroundColor: Color(0xFFF8BBD9), // Cotton candy pink
      darkBackgroundColor: Color(0xFFAD1457), // Deep pink
      boardLineColor: Color(0xFF880E4F), // Darker pink lines
      whitePieceColor: Color(0xFFFFF3E0), // Cream
      blackPieceColor: Color(0xFF4527A0), // Purple
      pieceHighlightColor: Color(0xFF00BCD4), // Turquoise highlight
      messageColor: Color(0xFF880E4F), // Dark pink text
      drawerColor: Color(0xFFAD1457),
      drawerTextColor: Color(0xFFFFFFFF),
      drawerHighlightItemColor: Color(0x3300BCD4),
      mainToolbarBackgroundColor: Color(0xFFAD1457),
      mainToolbarIconColor: Color(0xFFFFFFFF),
      navigationToolbarBackgroundColor: Color(0xFFAD1457),
      navigationToolbarIconColor: Color(0xFFFFFFFF),
      analysisToolbarBackgroundColor: Color(0xFFAD1457),
      analysisToolbarIconColor: Color(0xFFFFFFFF),
      annotationToolbarBackgroundColor: Color(0xFFAD1457),
      annotationToolbarIconColor: Color(0xFFFFFFFF),
    ),
  };

  // Kids-specific font sizes (larger than adult versions)
  static const double kidsSmallFontSize = 18.0; // Increased from 14.0
  static const double kidsDefaultFontSize = 22.0; // Increased from 16.0
  static const double kidsLargeFontSize = 26.0; // Increased from 20.0
  static const double kidsExtraLargeFontSize = 30.0; // Increased from 24.0
  static const double kidsHugeFontSize = 34.0; // Increased from 28.0
  static const double kidsGiantFontSize = 38.0; // Increased from 32.0

  // Kids-specific UI dimensions (larger touch targets)
  static const double kidsButtonHeight =
      56.0; // Minimum 48dp per Material Design
  static const double kidsButtonWidth = 120.0;
  static const double kidsIconSize = 32.0; // Larger icons
  static const double kidsBoardMargin = 16.0; // More generous margins
  static const double kidsDrawerItemHeight = 64.0; // Larger drawer items
  static const double kidsDrawerItemPadding = 16.0;

  // Kids-specific text styles with better readability
  static TextTheme get kidsTextTheme => const TextTheme(
        headlineLarge: TextStyle(
          fontSize: kidsGiantFontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          height: 1.2, // Better line spacing for readability
        ),
        headlineMedium: TextStyle(
          fontSize: kidsHugeFontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
          height: 1.2,
        ),
        titleLarge: TextStyle(
          fontSize: kidsExtraLargeFontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          height: 1.3,
        ),
        titleMedium: TextStyle(
          fontSize: kidsLargeFontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          height: 1.3,
        ),
        bodyLarge: TextStyle(
          fontSize: kidsDefaultFontSize,
          fontWeight: FontWeight.w500, // Slightly bolder for better readability
          letterSpacing: 0.3,
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          fontSize: kidsDefaultFontSize,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.3,
          height: 1.4,
        ),
        labelLarge: TextStyle(
          fontSize: kidsDefaultFontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          height: 1.2,
        ),
      );

  // Kids-friendly button theme with larger touch targets
  static ElevatedButtonThemeData get kidsElevatedButtonTheme =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(kidsButtonWidth, kidsButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          textStyle: const TextStyle(
            fontSize: kidsDefaultFontSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(16.0), // More rounded for friendly look
          ),
          elevation: 4.0, // Slight elevation for tactile feel
        ),
      );

  // Kids-friendly card theme
  static CardTheme get kidsCardTheme => CardTheme(
        margin: const EdgeInsets.all(12.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0), // Very rounded corners
        ),
        elevation: 6.0, // More elevation for depth perception
      );

  /// Creates a complete kids-friendly theme data
  static ThemeData createKidsTheme({
    required KidsColorTheme colorTheme,
    required Brightness brightness,
  }) {
    final colorSettings = kidsColorThemes[colorTheme]!;

    final ColorScheme colorScheme = ColorScheme(
      brightness: brightness,
      primary: colorSettings.darkBackgroundColor,
      onPrimary: Colors.white,
      primaryContainer: colorSettings.boardBackgroundColor,
      onPrimaryContainer: colorSettings.boardLineColor,
      secondary: colorSettings.pieceHighlightColor,
      onSecondary: Colors.white,
      secondaryContainer: colorSettings.pieceHighlightColor.withOpacity(0.3),
      onSecondaryContainer: colorSettings.boardLineColor,
      surface: colorSettings.boardBackgroundColor,
      onSurface: colorSettings.boardLineColor,
      error: Colors.red,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: kidsTextTheme,
      elevatedButtonTheme: kidsElevatedButtonTheme,
      cardTheme: kidsCardTheme,
      // Ensure all interactive elements have sufficient size
      materialTapTargetSize: MaterialTapTargetSize.padded,
      dialogTheme: DialogTheme(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
        ),
        titleTextStyle: TextStyle(
          fontSize: kidsLargeFontSize,
          fontWeight: FontWeight.w600,
          color: colorSettings.boardLineColor,
        ),
        contentTextStyle: TextStyle(
          fontSize: kidsDefaultFontSize,
          color: colorSettings.boardLineColor,
          height: 1.4,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorSettings.darkBackgroundColor,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          fontSize: kidsLargeFontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        toolbarHeight: 72.0, // Taller app bar for kids
      ),
    );
  }

  /// Get current kids theme setting
  static KidsColorTheme getCurrentKidsTheme() {
    // Default to sunny playground theme
    return DB().displaySettings.kidsTheme ?? KidsColorTheme.sunnyPlayground;
  }

  /// Check if kids mode is currently enabled
  static bool get isKidsModeEnabled {
    return DB().generalSettings.kidsMode ?? false;
  }
}

/// Available kids color themes
@HiveType(typeId: 20)
enum KidsColorTheme {
  @HiveField(0)
  sunnyPlayground,
  @HiveField(1)
  friendlyForest,
  @HiveField(2)
  oceanAdventure,
  @HiveField(3)
  sweetCandy,
}

// Extension to add kids theme names for UI display
extension KidsColorThemeName on KidsColorTheme {
  String get displayName {
    switch (this) {
      case KidsColorTheme.sunnyPlayground:
        return 'Sunny Playground'; // Bright and cheerful
      case KidsColorTheme.friendlyForest:
        return 'Friendly Forest'; // Nature-inspired
      case KidsColorTheme.oceanAdventure:
        return 'Ocean Adventure'; // Blue ocean theme
      case KidsColorTheme.sweetCandy:
        return 'Sweet Candy'; // Pink candy theme
    }
  }

  String get description {
    switch (this) {
      case KidsColorTheme.sunnyPlayground:
        return 'Bright and sunny colors perfect for happy learning';
      case KidsColorTheme.friendlyForest:
        return 'Calming green theme inspired by nature';
      case KidsColorTheme.oceanAdventure:
        return 'Cool blue ocean colors for underwater adventures';
      case KidsColorTheme.sweetCandy:
        return 'Sweet pink colors like cotton candy';
    }
  }
}
