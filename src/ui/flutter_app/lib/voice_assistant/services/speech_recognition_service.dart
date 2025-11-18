// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// speech_recognition_service.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../../shared/services/logger.dart';

/// Service to handle speech recognition using Whisper
class SpeechRecognitionService {
  factory SpeechRecognitionService() => _instance;

  SpeechRecognitionService._internal();

  static final SpeechRecognitionService _instance =
      SpeechRecognitionService._internal();

  WhisperController? _whisper;
  final AudioRecorder _audioRecorder = AudioRecorder();
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
  /// Records audio to a temporary file, then transcribes it using Whisper
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

    String? tempAudioPath;
    try {
      _isListening = true;
      recognitionStatus.value = 'Listening...';
      recognitionResult.value = null;

      logger.i('Starting voice recognition');

      // Get temporary directory for audio file
      final Directory tempDir = await getTemporaryDirectory();
      tempAudioPath =
          '${tempDir.path}/voice_recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Check if recorder has permission
      if (!await _audioRecorder.hasPermission()) {
        logger.w('Audio recorder permission check failed');
        recognitionStatus.value = 'Microphone permission denied';
        return null;
      }

      // Start recording
      await _audioRecorder.start(
        const RecordConfig(
          sampleRate: 16000, // Whisper works well with 16kHz
        ),
        path: tempAudioPath,
      );

      logger.i('Recording audio to: $tempAudioPath');
      recognitionStatus.value = 'Recording...';

      // Wait for max duration
      await Future<void>.delayed(maxDuration);

      // Stop recording
      final String? recordedPath = await _audioRecorder.stop();
      logger.i('Recording stopped, file: $recordedPath');

      if (recordedPath == null || !File(recordedPath).existsSync()) {
        logger.w('No audio recorded');
        recognitionStatus.value = 'No audio recorded';
        return null;
      }

      // Transcribe the recorded audio
      recognitionStatus.value = 'Transcribing...';
      final String? transcription = await transcribeFromFile(recordedPath);

      return transcription;
    } catch (e, stackTrace) {
      logger.e('Failed to recognize speech', error: e, stackTrace: stackTrace);
      recognitionStatus.value = 'Recognition failed';
      return null;
    } finally {
      _isListening = false;

      // Clean up temporary audio file
      if (tempAudioPath != null) {
        try {
          final File tempFile = File(tempAudioPath);
          if (tempFile.existsSync()) {
            tempFile.deleteSync();
            logger.i('Temporary audio file deleted: $tempAudioPath');
          }
        } catch (e) {
          logger.w('Failed to delete temporary audio file', error: e);
        }
      }
    }
  }

  /// Stop listening
  Future<void> stopListening() async {
    if (!_isListening) {
      return;
    }

    try {
      // Stop audio recording
      await _audioRecorder.stop();
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
      // Stop any ongoing recording
      if (_isListening) {
        await _audioRecorder.stop();
      }

      // Dispose audio recorder
      await _audioRecorder.dispose();

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
