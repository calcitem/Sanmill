// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// model_downloader.dart

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../models/voice_assistant_settings.dart';

/// Service to download and manage Whisper model files
class ModelDownloader {
  factory ModelDownloader() => _instance;

  ModelDownloader._internal();

  static final ModelDownloader _instance = ModelDownloader._internal();

  /// Download progress notifier (0.0 to 1.0, -1.0 means no download)
  final ValueNotifier<double> downloadProgress = ValueNotifier<double>(-1.0);

  /// Download status message
  final ValueNotifier<String> downloadStatus = ValueNotifier<String>('');

  /// Whether a download is currently in progress
  bool _isDownloading = false;

  /// Check if a download is in progress
  bool get isDownloading => _isDownloading;

  /// Get the models directory path
  Future<String> getModelsDirectory() async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String modelsPath = '${appDir.path}/whisper_models';
    final Directory modelsDir = Directory(modelsPath);

    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }

    return modelsPath;
  }

  /// Get the full path for a model file
  Future<String> getModelPath(
    WhisperModelType modelType,
    String language,
  ) async {
    final String modelsDir = await getModelsDirectory();
    final String fileName = modelType.fileName;
    return '$modelsDir/$language-$fileName';
  }

  /// Check if a model file exists
  Future<bool> isModelDownloaded(
    WhisperModelType modelType,
    String language,
  ) async {
    final String modelPath = await getModelPath(modelType, language);
    final File modelFile = File(modelPath);
    return modelFile.existsSync();
  }

  /// Download a Whisper model with retry support
  ///
  /// Returns the path to the downloaded model file on success, or null on failure
  /// Automatically retries up to 3 times on network failures
  Future<String?> downloadModel({
    required WhisperModelType modelType,
    required String language,
    int maxRetries = 3,
  }) async {
    if (_isDownloading) {
      logger.w('Download already in progress');
      return null;
    }

    _isDownloading = true;
    int retryCount = 0;

    try {
      while (retryCount < maxRetries) {
        try {
          final String? result = await _attemptDownload(modelType, language);
          if (result != null) {
            return result;
          }
          // If result is null but no exception, it's a server error, retry
          retryCount++;
          if (retryCount < maxRetries) {
            final int delaySeconds =
                retryCount * 2; // Exponential backoff: 2s, 4s, 6s
            downloadStatus.value =
                'Retrying in $delaySeconds seconds... (${retryCount + 1}/$maxRetries)';
            logger.w(
              'Download failed, retrying in $delaySeconds seconds (attempt ${retryCount + 1}/$maxRetries)',
            );
            await Future<void>.delayed(Duration(seconds: delaySeconds));
          }
        } catch (e, stackTrace) {
          logger.e(
            'Download attempt ${retryCount + 1} failed',
            error: e,
            stackTrace: stackTrace,
          );
          retryCount++;
          if (retryCount < maxRetries) {
            final int delaySeconds = retryCount * 2;
            downloadStatus.value =
                'Retrying in $delaySeconds seconds... (${retryCount + 1}/$maxRetries)';
            await Future<void>.delayed(Duration(seconds: delaySeconds));
          } else {
            downloadStatus.value =
                'Download failed after $maxRetries attempts: $e';
            return null;
          }
        }
      }

      downloadStatus.value = 'Download failed after $maxRetries attempts';
      return null;
    } finally {
      _isDownloading = false;
    }
  }

  /// Internal method to attempt a single download
  Future<String?> _attemptDownload(
    WhisperModelType modelType,
    String language,
  ) async {
    downloadProgress.value = 0.0;
    downloadStatus.value = 'Starting download...';
    _updateDatabaseProgress(0.0);

    final String downloadUrl = modelType.getDownloadUrl(language);
    final String modelPath = await getModelPath(modelType, language);
    final File modelFile = File(modelPath);

    logger.i('Downloading model from: $downloadUrl');
    logger.i('Saving to: $modelPath');

    final http.Client client = http.Client();
    IOSink? sink;
    bool completed = false;
    try {
      final http.Request request = http.Request('GET', Uri.parse(downloadUrl));
      final http.StreamedResponse response = await client.send(request);

      if (response.statusCode != 200) {
        logger.e('Failed to download model: HTTP ${response.statusCode}');
        return null;
      }

      final int? contentLength = response.contentLength;
      if (contentLength == null) {
        logger.w('Content-Length not provided by server');
      }

      sink = modelFile.openWrite();
      int downloadedBytes = 0;

      await for (final List<int> chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;

        if (contentLength != null) {
          final double progress = downloadedBytes / contentLength;
          downloadProgress.value = progress;
          downloadStatus.value =
              'Downloading: ${(progress * 100).toStringAsFixed(1)}%';
          _updateDatabaseProgress(progress);
          logger.i(
            'Download progress: ${(progress * 100).toStringAsFixed(1)}%',
          );
        }
      }

      downloadStatus.value = 'Writing file...';
      await sink.flush();
      await sink.close();
      sink = null;
      completed = true;

      // Reset progress to hide progress indicator
      downloadProgress.value = -1.0;
      downloadStatus.value = 'Download complete';
      _updateDatabaseProgress(-1.0); // Reset progress in database
      logger.i('Model downloaded successfully to: $modelPath');

      return modelPath;
    } finally {
      client.close();
      if (sink != null) {
        await sink.close();
      }
      if (!completed && modelFile.existsSync()) {
        modelFile.deleteSync();
      }
      // Reset progress on failure
      if (!completed) {
        _updateDatabaseProgress(-1.0);
      }
    }
  }

  /// Update download progress in database for persistence
  void _updateDatabaseProgress(double progress) {
    try {
      final VoiceAssistantSettings currentSettings =
          DB().voiceAssistantSettings;
      DB().voiceAssistantSettings = currentSettings.copyWith(
        downloadProgress: progress,
      );
    } catch (e) {
      logger.w('Failed to update download progress in database', error: e);
    }
  }

  /// Delete a downloaded model
  Future<bool> deleteModel(WhisperModelType modelType, String language) async {
    try {
      final String modelPath = await getModelPath(modelType, language);
      final File modelFile = File(modelPath);

      if (modelFile.existsSync()) {
        modelFile.deleteSync();
        logger.i('Model deleted: $modelPath');
        return true;
      }

      return false;
    } catch (e, stackTrace) {
      logger.e('Failed to delete model', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Get the size of a model file in bytes
  Future<int?> getModelSize(WhisperModelType modelType, String language) async {
    try {
      final String modelPath = await getModelPath(modelType, language);
      final File modelFile = File(modelPath);

      if (modelFile.existsSync()) {
        return modelFile.lengthSync();
      }

      return null;
    } catch (e) {
      logger.e('Failed to get model size', error: e);
      return null;
    }
  }

  /// Format bytes to human-readable format
  static String formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// Check and clean up incomplete downloads on app startup
  ///
  /// This method checks if there are incomplete downloads from previous sessions
  /// and removes them. A download is considered incomplete if:
  /// 1. downloadProgress is between 0.0 and 1.0 (indicating download was in progress)
  /// 2. The model file exists but modelDownloaded is false
  ///
  /// Returns true if incomplete downloads were found and cleaned up
  Future<bool> checkAndCleanIncompleteDownloads() async {
    try {
      final VoiceAssistantSettings currentSettings =
          DB().voiceAssistantSettings;

      // Check if there was a download in progress (progress between 0.0 and 1.0)
      final bool wasDownloading =
          currentSettings.downloadProgress >= 0.0 &&
          currentSettings.downloadProgress < 1.0;

      // Check if model is marked as not downloaded but file exists
      final String modelPath = await getModelPath(
        currentSettings.modelType,
        currentSettings.language,
      );
      final File modelFile = File(modelPath);
      final bool hasIncompleteFile =
          modelFile.existsSync() && !currentSettings.modelDownloaded;

      if (wasDownloading || hasIncompleteFile) {
        logger.i(
          'Detected incomplete download from previous session, cleaning up...',
        );

        // Delete the incomplete file if it exists
        if (modelFile.existsSync()) {
          modelFile.deleteSync();
          logger.i('Deleted incomplete model file: $modelPath');
        }

        // Reset download progress and model downloaded status in database
        DB().voiceAssistantSettings = currentSettings.copyWith(
          downloadProgress: -1.0,
          modelDownloaded: false,
          modelPath: '',
          enabled: false, // Ensure switch is off for incomplete downloads
        );

        // Reset in-memory progress notifier to hide progress indicator
        downloadProgress.value = -1.0;
        downloadStatus.value = '';

        logger.i('Incomplete download cleaned up successfully');
        return true;
      }

      // No incomplete downloads found, ensure in-memory progress is reset
      // This is important to handle cases where database was already clean
      // but in-memory value might have stale data
      downloadProgress.value = -1.0;
      downloadStatus.value = '';
      
      return false;
    } catch (e, stackTrace) {
      logger.e(
        'Failed to check/clean incomplete downloads',
        error: e,
        stackTrace: stackTrace,
      );
      // On error, ensure progress is reset to avoid showing stale progress
      downloadProgress.value = -1.0;
      downloadStatus.value = '';
      return false;
    }
  }
}
