// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// hive_repair_utils.dart

import 'package:hive_flutter/hive_flutter.dart';

import '../../rule_settings/models/rule_settings.dart';
import '../services/logger.dart';

/// Utility class to repair corrupted Hive database data
class HiveRepairUtils {
  static const String _logTag = "[Hive Repair]";

  /// Repairs corrupted RuleSettings box by clearing it and using default values
  static Future<void> repairRuleSettingsBox() async {
    try {
      logger.w("$_logTag Attempting to repair corrupted rulesettings box");

      // Close the box if it's already open
      if (Hive.isBoxOpen('rulesettings')) {
        await Hive.box('rulesettings').close();
      }

      // Delete the corrupted box
      await Hive.deleteBoxFromDisk('rulesettings');
      logger.i("$_logTag Deleted corrupted rulesettings box");

      // Re-register adapters (in case they weren't registered)
      if (!Hive.isAdapterRegistered(4)) {
        Hive.registerAdapter<BoardFullAction>(BoardFullActionAdapter());
      }
      if (!Hive.isAdapterRegistered(10)) {
        Hive.registerAdapter<MillFormationActionInPlacingPhase>(
            MillFormationActionInPlacingPhaseAdapter());
      }
      if (!Hive.isAdapterRegistered(8)) {
        Hive.registerAdapter<StalemateAction>(StalemateActionAdapter());
      }
      if (!Hive.isAdapterRegistered(3)) {
        Hive.registerAdapter<RuleSettings>(RuleSettingsAdapter());
      }

      // Reopen the box with fresh data
      final Box<RuleSettings> newBox =
          await Hive.openBox<RuleSettings>('rulesettings');

      // Initialize with default settings
      const RuleSettings defaultSettings = RuleSettings();
      await newBox.put('settings', defaultSettings);

      logger.i(
          "$_logTag Successfully repaired rulesettings box with default values");
    } catch (e) {
      logger.e("$_logTag Failed to repair rulesettings box: $e");
      rethrow;
    }
  }

  /// Safely opens a box with error handling and auto-repair functionality
  static Future<Box<T>> safeOpenBox<T>(
    String boxName, {
    List<int>? encryptionKey,
  }) async {
    try {
      return await Hive.openBox<T>(boxName, encryptionKey: encryptionKey);
    } on HiveError catch (e) {
      logger.e("$_logTag Error opening box '$boxName': $e");

      // If it's a type casting error, try to repair
      if (e.message.contains('type cast') ||
          e.message.contains('subtype') ||
          e.message.contains('cast')) {
        logger.w("$_logTag Detected type casting error, attempting repair...");

        if (boxName == 'rulesettings') {
          await repairRuleSettingsBox();
          return Hive.openBox<T>(boxName, encryptionKey: encryptionKey);
        }

        // For other boxes, delete and recreate
        await Hive.deleteBoxFromDisk(boxName);
        logger.i("$_logTag Deleted corrupted box '$boxName', creating new one");
        return Hive.openBox<T>(boxName, encryptionKey: encryptionKey);
      }

      rethrow;
    }
  }

  /// Validates box data integrity
  static Future<bool> validateBoxIntegrity<T>(Box<T> box) async {
    try {
      // Try to read all values to detect corruption
      for (final dynamic key in box.keys) {
        final T? value = box.get(key);
        if (value == null && box.containsKey(key)) {
          logger.w("$_logTag Found null value for existing key: $key");
          return false;
        }
      }
      return true;
    } catch (e) {
      logger.e("$_logTag Box integrity check failed: $e");
      return false;
    }
  }
}
