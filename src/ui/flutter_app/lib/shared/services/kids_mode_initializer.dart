// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// kids_mode_initializer.dart

import 'package:flutter/material.dart';

import '../../parental_controls/services/parental_control_service.dart';
import '../../safety/services/child_safety_service.dart';
import '../database/database.dart';
import '../themes/kids_theme.dart';
import 'kids_ui_service.dart';

/// Initializer for kids mode and all related services
/// Ensures proper setup for Teacher Approved and Family programs compliance
class KidsModeInitializer {
  KidsModeInitializer._();

  static final KidsModeInitializer _instance = KidsModeInitializer._();
  static KidsModeInitializer get instance => _instance;

  bool _isInitialized = false;

  /// Initialize all kids mode services and features
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      // Initialize child safety service first (most important)
      await ChildSafetyService.instance.initialize();

      // Initialize parental controls
      await ParentalControlService.instance.initialize();

      // Initialize kids UI service
      if (DB().generalSettings.kidsMode == true) {
        await KidsUIService.instance.initializeKidsUI();
      }

      _isInitialized = true;
    } catch (e) {
      // Handle initialization error safely
      debugPrint('Error initializing kids mode: $e');
    }
  }

  /// Check if kids mode should be enabled based on device/user settings
  bool shouldEnableKidsMode() {
    // Check various factors that might indicate this should be in kids mode
    final bool kidsMode = DB().generalSettings.kidsMode ?? false;

    // Additional checks could be added here, such as:
    // - Time of day (e.g., kids are more likely to play during certain hours)
    // - Device type (e.g., tablets might be more likely to be used by kids)
    // - Previous usage patterns

    return kidsMode;
  }

  /// Get the appropriate theme based on current mode
  ThemeData getAppropriateTheme(BuildContext context) {
    if (shouldEnableKidsMode()) {
      final KidsColorTheme kidsTheme =
          DB().displaySettings.kidsTheme ?? KidsColorTheme.sunnyPlayground;
      return KidsTheme.createKidsTheme(
        colorTheme: kidsTheme,
        brightness: Theme.of(context).brightness,
      );
    }

    // Return regular app theme
    return Theme.of(context);
  }

  /// Setup kids mode when first enabled
  Future<void> setupKidsMode() async {
    await ChildSafetyService.instance.enableSafeMode();
    await KidsUIService.instance.toggleKidsMode(true);

    // Set default kids theme if none selected
    if (DB().displaySettings.kidsTheme == null) {
      await KidsUIService.instance
          .switchKidsTheme(KidsColorTheme.sunnyPlayground);
    }

    // Start safe session
    ChildSafetyService.instance.startSafeSession();
  }

  /// Teardown kids mode when disabled
  Future<void> teardownKidsMode() async {
    ParentalControlService.instance.endPlaySession();
    ChildSafetyService.instance.endSafeSession();
    await ChildSafetyService.instance.disableSafeMode();
    await KidsUIService.instance.toggleKidsMode(false);
  }

  /// Dispose all services
  void dispose() {
    ParentalControlService.instance.dispose();
    ChildSafetyService.instance.dispose();
    _isInitialized = false;
  }

  // Getters
  bool get isInitialized => _isInitialized;
}
