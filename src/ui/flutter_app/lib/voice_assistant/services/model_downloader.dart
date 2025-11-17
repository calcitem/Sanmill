// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// model_downloader.dart

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../shared/services/logger.dart';
import '../models/voice_assistant_settings.dart';

/// Service to download and manage Whisper model files
class ModelDownloader {
  factory ModelDownloader() => _instance;

  ModelDownloader._internal();

  static final ModelDownloader _instance = ModelDownloader._internal();

  /// Download progress notifier (0.0 to 1.0)
  final ValueNotifier<double> downloadProgress = ValueNotifier<double>(0.0);

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

    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    return modelsPath;
  }

  /// Get the full path for a model file
  Future<String> getModelPath(WhisperModelType modelType, String language) async {
    final String modelsDir = await getModelsDirectory();
    final String fileName = modelType.fileName;
    return '$modelsDir/$language-$fileName';
  }

  /// Check if a model file exists
  Future<bool> isModelDownloaded(WhisperModelType modelType, String language) async {
    final String modelPath = await getModelPath(modelType, language);
    final File modelFile = File(modelPath);
    return modelFile.exists();
  }

  /// Download a Whisper model
  ///
  /// Returns the path to the downloaded model file on success, or null on failure
  Future<String?> downloadModel({
    required WhisperModelType modelType,
    required String language,
  }) async {
    if (_isDownloading) {
      logger.w('Download already in progress');
      return null;
    }

    _isDownloading = true;
    downloadProgress.value = 0.0;
    downloadStatus.value = 'Starting download...';

    try {
      final String downloadUrl = modelType.getDownloadUrl(language);
      final String modelPath = await getModelPath(modelType, language);
      final File modelFile = File(modelPath);

      logger.i('Downloading model from: $downloadUrl');
      logger.i('Saving to: $modelPath');

      final http.Client client = http.Client();
      final http.Request request = http.Request('GET', Uri.parse(downloadUrl));
      final http.StreamedResponse response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Failed to download model: HTTP ${response.statusCode}');
      }

      final int? contentLength = response.contentLength;
      if (contentLength == null) {
        logger.w('Content-Length not provided by server');
      }

      final List<int> bytes = <int>[];
      int downloadedBytes = 0;

      await for (final List<int> chunk in response.stream) {
        bytes.addAll(chunk);
        downloadedBytes += chunk.length;

        if (contentLength != null) {
          final double progress = downloadedBytes / contentLength;
          downloadProgress.value = progress;
          downloadStatus.value = 'Downloading: ${(progress * 100).toStringAsFixed(1)}%';
          logger.i('Download progress: ${(progress * 100).toStringAsFixed(1)}%');
        }
      }

      downloadStatus.value = 'Writing file...';
      await modelFile.writeAsBytes(bytes);

      downloadProgress.value = 1.0;
      downloadStatus.value = 'Download complete';
      logger.i('Model downloaded successfully to: $modelPath');

      return modelPath;
    } catch (e, stackTrace) {
      logger.e('Failed to download model', error: e, stackTrace: stackTrace);
      downloadStatus.value = 'Download failed: $e';
      return null;
    } finally {
      _isDownloading = false;
    }
  }

  /// Delete a downloaded model
  Future<bool> deleteModel(WhisperModelType modelType, String language) async {
    try {
      final String modelPath = await getModelPath(modelType, language);
      final File modelFile = File(modelPath);

      if (await modelFile.exists()) {
        await modelFile.delete();
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

      if (await modelFile.exists()) {
        return await modelFile.length();
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
}
