// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// speech_recognition_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../../shared/services/logger.dart';

/// Service to handle speech recognition using Whisper
class SpeechRecognitionService {
  factory SpeechRecognitionService() => _instance;

  SpeechRecognitionService._internal();

  static final SpeechRecognitionService _instance =
      SpeechRecognitionService._internal();

  WhisperController? _whisper;
  bool _isInitialized = false;
  bool _isListening = false;
  String _language = 'en';
  WhisperModel _model = WhisperModel.base;

  /// Whether the service is initialized
  bool get isInitialized => _isInitialized;

  /// Whether actively listening
  bool get isListening => _isListening;

  /// Recognition result notifier
  final ValueNotifier<String?> recognitionResult = ValueNotifier<String?>(null);

  /// Recognition status notifier
  final ValueNotifier<String> recognitionStatus = ValueNotifier<String>(
    'Ready',
  );

  /// Initialize the Whisper model
  ///
  /// [modelPath] - Path to the downloaded model file (not used with WhisperController)
  /// [language] - Language code (e.g., 'en', 'zh')
  Future<bool> initialize(String modelPath, String language) async {
    if (_isInitialized) {
      logger.i('Speech recognition already initialized');
      return true;
    }

    try {
      recognitionStatus.value = 'Initializing...';

      // Initialize WhisperController
      _whisper = WhisperController();
      _language = language;

      // Determine model type from path (e.g., "base", "small", "medium", "large")
      if (modelPath.contains('tiny')) {
        _model = WhisperModel.tiny;
      } else if (modelPath.contains('small')) {
        _model = WhisperModel.small;
      } else if (modelPath.contains('medium')) {
        _model = WhisperModel.medium;
      } else if (modelPath.contains('large')) {
        _model = WhisperModel.large;
      } else {
        _model = WhisperModel.base;
      }

      _isInitialized = true;
      recognitionStatus.value = 'Ready';
      logger.i('Speech recognition initialized successfully');
      return true;
    } catch (e, stackTrace) {
      logger.e(
        'Failed to initialize speech recognition',
        error: e,
        stackTrace: stackTrace,
      );
      recognitionStatus.value = 'Initialization failed';
      _isInitialized = false;
      return false;
    }
  }

  /// Request microphone permission
  Future<bool> requestMicrophonePermission() async {
    try {
      final PermissionStatus status = await Permission.microphone.request();
      final bool granted = status.isGranted;

      if (!granted) {
        logger.w('Microphone permission denied');
        recognitionStatus.value = 'Microphone permission denied';
      }

      return granted;
    } catch (e, stackTrace) {
      logger.e(
        'Failed to request microphone permission',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Check if microphone permission is granted
  Future<bool> hasMicrophonePermission() async {
    final PermissionStatus status = await Permission.microphone.status;
    return status.isGranted;
  }

  /// Start listening for voice input
  ///
  /// Returns the recognized text or null on failure
  /// Note: whisper_ggml doesn't support direct microphone input, so this method
  /// would require recording audio to a temporary file first
  Future<String?> startListening({
    Duration maxDuration = const Duration(seconds: 10),
  }) async {
    if (!_isInitialized) {
      logger.e('Speech recognition not initialized');
      recognitionStatus.value = 'Not initialized';
      return null;
    }

    if (_isListening) {
      logger.w('Already listening');
      return null;
    }

    // Check microphone permission
    if (!await hasMicrophonePermission()) {
      final bool granted = await requestMicrophonePermission();
      if (!granted) {
        return null;
      }
    }

    try {
      _isListening = true;
      recognitionStatus.value = 'Listening...';
      recognitionResult.value = null;

      logger.i('Starting voice recognition');

      // TODO: Implement audio recording to temp file
      // For now, return placeholder since whisper_ggml requires a file path
      logger.w('Direct microphone transcription not yet implemented');
      recognitionStatus.value = 'Not implemented';

      return null;
    } catch (e, stackTrace) {
      logger.e('Failed to recognize speech', error: e, stackTrace: stackTrace);
      recognitionStatus.value = 'Recognition failed';
      return null;
    } finally {
      _isListening = false;
    }
  }

  /// Stop listening
  Future<void> stopListening() async {
    if (!_isListening) {
      return;
    }

    try {
      // Note: whisper_ggml transcribeFromMicrophone is blocking,
      // so we can't stop it mid-recording in the current implementation
      _isListening = false;
      recognitionStatus.value = 'Stopped';
      logger.i('Stopped listening');
    } catch (e, stackTrace) {
      logger.e('Failed to stop listening', error: e, stackTrace: stackTrace);
    }
  }

  /// Transcribe audio from a file
  ///
  /// [audioPath] - Path to the audio file (WAV, MP3, etc.)
  Future<String?> transcribeFromFile(String audioPath) async {
    if (!_isInitialized) {
      logger.e('Speech recognition not initialized');
      recognitionStatus.value = 'Not initialized';
      return null;
    }

    try {
      recognitionStatus.value = 'Transcribing...';
      logger.i('Transcribing audio from file: $audioPath');

      // TranscribeResult is not exported through whisper_ggml public API
      // ignore: always_specify_types
      final result = await _whisper!.transcribe(
        model: _model,
        audioPath: audioPath,
        lang: _language,
      );

      if (result != null && result.transcription.text.isNotEmpty) {
        final String transcribedText = result.transcription.text;
        recognitionResult.value = transcribedText;
        recognitionStatus.value = 'Transcription complete';
        logger.i('Transcription result: $transcribedText');
        return transcribedText;
      } else {
        recognitionStatus.value = 'No speech detected';
        logger.w('Empty transcription result');
        return null;
      }
    } catch (e, stackTrace) {
      logger.e(
        'Failed to transcribe audio file',
        error: e,
        stackTrace: stackTrace,
      );
      recognitionStatus.value = 'Transcription failed';
      return null;
    }
  }

  /// Release resources
  Future<void> dispose() async {
    if (!_isInitialized) {
      return;
    }

    try {
      // WhisperController doesn't have a dispose method
      _whisper = null;
      _isInitialized = false;
      _isListening = false;
      recognitionStatus.value = 'Disposed';
      logger.i('Speech recognition service disposed');
    } catch (e, stackTrace) {
      logger.e(
        'Failed to dispose speech recognition service',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
