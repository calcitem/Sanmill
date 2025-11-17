// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// speech_recognition_service.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../../shared/services/logger.dart';
import '../models/voice_assistant_settings.dart';

/// Service to handle speech recognition using Whisper
class SpeechRecognitionService {
  factory SpeechRecognitionService() => _instance;

  SpeechRecognitionService._internal();

  static final SpeechRecognitionService _instance =
      SpeechRecognitionService._internal();

  WhisperGgml? _whisper;
  bool _isInitialized = false;
  bool _isListening = false;

  /// Whether the service is initialized
  bool get isInitialized => _isInitialized;

  /// Whether actively listening
  bool get isListening => _isListening;

  /// Recognition result notifier
  final ValueNotifier<String?> recognitionResult = ValueNotifier<String?>(null);

  /// Recognition status notifier
  final ValueNotifier<String> recognitionStatus =
      ValueNotifier<String>('Ready');

  /// Initialize the Whisper model
  ///
  /// [modelPath] - Path to the downloaded model file
  /// [language] - Language code (e.g., 'en', 'zh')
  Future<bool> initialize(String modelPath, String language) async {
    if (_isInitialized) {
      logger.i('Speech recognition already initialized');
      return true;
    }

    try {
      recognitionStatus.value = 'Initializing...';

      // Check if model file exists
      final File modelFile = File(modelPath);
      if (!await modelFile.exists()) {
        throw Exception('Model file not found: $modelPath');
      }

      // Initialize Whisper
      _whisper = WhisperGgml();
      await _whisper!.init(
        modelPath: modelPath,
        language: language,
      );

      _isInitialized = true;
      recognitionStatus.value = 'Ready';
      logger.i('Speech recognition initialized successfully');
      return true;
    } catch (e, stackTrace) {
      logger.e('Failed to initialize speech recognition',
          error: e, stackTrace: stackTrace);
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
      logger.e('Failed to request microphone permission',
          error: e, stackTrace: stackTrace);
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

      // Start recording and transcription
      final String? result = await _whisper!.transcribeFromMicrophone(
        maxDuration: maxDuration.inSeconds,
      );

      if (result != null && result.isNotEmpty) {
        recognitionResult.value = result;
        recognitionStatus.value = 'Recognition complete';
        logger.i('Recognition result: $result');
      } else {
        recognitionStatus.value = 'No speech detected';
        logger.w('No speech detected or empty result');
      }

      return result;
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

      final String? result = await _whisper!.transcribeFromFile(audioPath);

      if (result != null && result.isNotEmpty) {
        recognitionResult.value = result;
        recognitionStatus.value = 'Transcription complete';
        logger.i('Transcription result: $result');
      } else {
        recognitionStatus.value = 'No speech detected';
        logger.w('Empty transcription result');
      }

      return result;
    } catch (e, stackTrace) {
      logger.e('Failed to transcribe audio file',
          error: e, stackTrace: stackTrace);
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
      await _whisper?.dispose();
      _whisper = null;
      _isInitialized = false;
      _isListening = false;
      recognitionStatus.value = 'Disposed';
      logger.i('Speech recognition service disposed');
    } catch (e, stackTrace) {
      logger.e('Failed to dispose speech recognition service',
          error: e, stackTrace: stackTrace);
    }
  }
}
