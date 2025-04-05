// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// storage_permission_service.dart

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'logger.dart';

/// Service to handle storage permission requests and prepare directories for screenshots
class StoragePermissionService {
  // Factory constructor to return singleton instance
  factory StoragePermissionService() => _instance;

  // Private constructor to prevent instantiation from outside
  StoragePermissionService._();

  // Singleton instance
  static final StoragePermissionService _instance =
      StoragePermissionService._();

  /// Request storage permissions for Android
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid || kIsWeb) {
      return true; // Only Android needs explicit permissions
    }

    try {
      // Request basic storage permission
      final PermissionStatus status = await Permission.storage.request();

      // Log the result
      logger.i('Storage permission status: $status');

      if (status.isGranted) {
        await _prepareDirectories();
        return true;
      } else {
        logger.e('Storage permission denied');
        return false;
      }
    } catch (e) {
      logger.e('Error requesting storage permission: $e');
      return false;
    }
  }

  /// Get the best available directory for saving screenshots
  Future<String?> getScreenshotDirectory() async {
    if (!Platform.isAndroid || kIsWeb) {
      return null;
    }

    try {
      // Try several locations in order of preference

      // 1. External storage (most widely accessible)
      final Directory? extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final Directory picturesDir = Directory('${extDir.path}/Pictures');
        if (!picturesDir.existsSync()) {
          // Use sync version to avoid warning
          picturesDir.createSync(recursive: true);
        }
        return picturesDir.path;
      }

      // 2. Application documents directory (fallback)
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final Directory appPicturesDir = Directory('${appDocDir.path}/Pictures');
      if (!appPicturesDir.existsSync()) {
        // Use sync version to avoid warning
        appPicturesDir.createSync(recursive: true);
      }
      return appPicturesDir.path;
    } catch (e) {
      logger.e('Error getting screenshot directory: $e');
      return null;
    }
  }

  /// Prepare necessary directories for screenshots
  Future<void> _prepareDirectories() async {
    try {
      // Standard external directories to check and create if needed
      const List<String> standardDirs = <String>[
        '/sdcard/Pictures',
        '/storage/emulated/0/Pictures',
      ];

      // Try to create each directory
      for (final String path in standardDirs) {
        final Directory dir = Directory(path);
        if (!dir.existsSync()) {
          // Use sync version to avoid warning
          try {
            dir.createSync(recursive: true);
            logger.i('Created directory: $path');
          } catch (e) {
            logger.w('Could not create directory: $path - $e');
          }
        } else {
          logger.i('Directory exists: $path');
        }
      }

      // Also create app-specific directory
      final String? appDir = await getScreenshotDirectory();
      logger.i('App screenshot directory: $appDir');
    } catch (e) {
      logger.e('Error preparing directories: $e');
    }
  }

  // Static methods for backward compatibility with renamed methods to avoid conflicts

  /// Request storage permissions for Android (static version)
  static Future<bool> requestPermission() async {
    return StoragePermissionService().requestStoragePermission();
  }

  /// Get the best available directory for saving screenshots (static version)
  static Future<String?> getDirectory() async {
    return StoragePermissionService().getScreenshotDirectory();
  }
}
