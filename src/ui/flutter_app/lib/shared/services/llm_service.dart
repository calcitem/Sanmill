// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// llm_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../general_settings/models/general_settings.dart';
import '../../generated/intl/l10n.dart';
import '../database/database.dart';
import 'logger.dart';

/// A service to interact with LLM providers like OpenAI API
class LlmService {
  /// Factory constructor
  factory LlmService() {
    return _instance;
  }

  /// Private constructor
  LlmService._internal();

  /// Singleton instance of LlmService
  static final LlmService _instance = LlmService._internal();

  /// HTTP client for API requests
  final http.Client _httpClient = http.Client();

  /// Returns a stream of string chunks as they are received
  Stream<String> generateResponse(String prompt, BuildContext context) async* {
    final GeneralSettings settings = DB().generalSettings;

    // Check if LLM is configured
    if (!isLlmConfigured()) {
      yield S.of(context).llmNotConfiguredPleaseCheckYourSettings;
      return;
    }

    try {
      // System prompt to guide the LLM's role
      final String systemPrompt = "You are a Nine Men's Morris game expert. "
          '${S.of(context).analyzeTheMovesAndProvideInsights}';

      switch (settings.llmProvider) {
        case LlmProvider.openai:
          // Use OpenAI API
          final String response = await _callOpenAI(
            apiKey: settings.llmApiKey,
            baseUrl: settings.llmBaseUrl.isNotEmpty
                ? settings.llmBaseUrl
                : 'https://api.openai.com/v1',
            model: settings.llmModel,
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            temperature: settings.llmTemperature,
          );

          yield response;
          break;

        case LlmProvider.google:
          // Use Google Generative AI API
          final String response = await _callGoogleAI(
            apiKey: settings.llmApiKey,
            model: settings.llmModel,
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            temperature: settings.llmTemperature,
          );

          yield response;
          break;

        case LlmProvider.ollama:
          // Use Ollama API
          final String response = await _callOllama(
            baseUrl: settings.llmBaseUrl,
            model: settings.llmModel,
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            temperature: settings.llmTemperature,
          );

          yield response;
          break;
      }
    } catch (e) {
      logger.e('Error generating LLM response: $e');
      yield 'Error: $e';
    }
  }

  /// Call OpenAI API
  Future<String> _callOpenAI({
    required String apiKey,
    required String baseUrl,
    required String model,
    required String systemPrompt,
    required String userPrompt,
    required double temperature,
  }) async {
    // Compose the final endpoint. Users might pass either
    // 1) "https://api.openai.com/v1"  (recommended)
    // 2) "https://api.openai.com/v1/" (trailing slash)
    // 3) "https://api.openai.com/v1/chat/completions" (full endpoint)
    // To avoid duplicating the path, only append "/chat/completions" when
    // it is NOT already present.

    String endpoint;
    final String trimmed = baseUrl.trim();
    if (trimmed.contains('/chat/completions')) {
      endpoint = trimmed;
    } else if (trimmed.endsWith('/')) {
      endpoint = '${trimmed}chat/completions';
    } else {
      endpoint = '$trimmed/chat/completions';
    }

    final Uri uri = Uri.parse(endpoint);

    // Ensure the API key does not mistakenly carry the "Bearer " prefix or extra whitespace
    String sanitizedKey = apiKey.trim();
    if (sanitizedKey.toLowerCase().startsWith('bearer ')) {
      sanitizedKey = sanitizedKey.substring(7).trim();
    }

    final Map<String, dynamic> body = <String, dynamic>{
      'model': model,
      'messages': <Map<String, String>>[
        <String, String>{'role': 'system', 'content': systemPrompt},
        <String, String>{'role': 'user', 'content': userPrompt},
      ],
      'temperature': temperature,
    };

    final http.Response response = await _httpClient.post(
      uri,
      headers: <String, String>{
        // Explicitly declare UTF-8 to avoid encoding issues with non‑ASCII text.
        'Content-Type': 'application/json; charset=utf-8',
        // Attach the sanitized key in the required format
        'Authorization': 'Bearer $sanitizedKey',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      // Decode using UTF-8 to ensure Chinese characters are handled correctly.
      final Map<String, dynamic> data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final List<dynamic> choices = data['choices'] as List<dynamic>;
      if (choices.isNotEmpty) {
        final Map<String, dynamic> choice = choices[0] as Map<String, dynamic>;
        final Map<String, dynamic> message =
            choice['message'] as Map<String, dynamic>;
        final String content = message['content'] as String;
        return content;
      }
      throw Exception('OpenAI API error: No choices found in response.');
    } else {
      throw Exception(
          'OpenAI API error: ${response.statusCode} ${response.body}');
    }
  }

  /// Call Google AI API
  Future<String> _callGoogleAI({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userPrompt,
    required double temperature,
  }) async {
    final Uri uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey');

    final Map<String, dynamic> body = <String, dynamic>{
      'contents': <Map<String, Object>>[
        <String, Object>{
          'role': 'user',
          'parts': <Map<String, String>>[
            <String, String>{'text': '$systemPrompt\n\n$userPrompt'}
          ]
        }
      ],
      'generationConfig': <String, double>{
        'temperature': temperature,
      }
    };

    final http.Response response = await _httpClient.post(
      uri,
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> candidates = data['candidates'] as List<dynamic>;
      final Map<String, dynamic> candidate =
          candidates[0] as Map<String, dynamic>;
      final Map<String, dynamic> content =
          candidate['content'] as Map<String, dynamic>;
      final List<dynamic> parts = content['parts'] as List<dynamic>;
      final Map<String, dynamic> part = parts[0] as Map<String, dynamic>;
      final String text = part['text'] as String;
      return text;
    } else {
      throw Exception(
          'Google AI API error: ${response.statusCode} ${response.body}');
    }
  }

  /// Call Ollama API
  Future<String> _callOllama({
    required String baseUrl,
    required String model,
    required String systemPrompt,
    required String userPrompt,
    required double temperature,
  }) async {
    final Uri uri = Uri.parse('$baseUrl/api/chat');

    final Map<String, dynamic> body = <String, dynamic>{
      'model': model,
      'messages': <Map<String, String>>[
        <String, String>{'role': 'system', 'content': systemPrompt},
        <String, String>{'role': 'user', 'content': userPrompt},
      ],
      'options': <String, double>{
        'temperature': temperature,
      },
      'stream': false,
    };

    final http.Response response = await _httpClient.post(
      uri,
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> messageData =
          data['message'] as Map<String, dynamic>;
      final String content = messageData['content'] as String;
      return content;
    } else {
      throw Exception(
          'Ollama API error: ${response.statusCode} ${response.body}');
    }
  }

  /// Extracts moves from LLM response for importing
  String extractMoves(String llmResponse) {
    // Look for content between triple backticks
    final RegExp codeBlockRegex = RegExp(r'```(.+?)```', dotAll: true);
    final RegExpMatch? match = codeBlockRegex.firstMatch(llmResponse);

    if (match != null && match.groupCount >= 1) {
      return match.group(1)!.trim();
    }

    // If no code block found, look for numbered lines that might be moves
    final RegExp moveLines = RegExp(r'\d+\.\s+\w+.*');
    final Iterable<RegExpMatch> allMatches = moveLines.allMatches(llmResponse);

    if (allMatches.isNotEmpty) {
      return allMatches
          .map((RegExpMatch m) => m.group(0))
          .whereType<String>()
          .join('\n');
    }

    // If no structured content found, return the original response
    return llmResponse;
  }

  /// Check if the LLM is properly configured
  bool isLlmConfigured() {
    final GeneralSettings settings = DB().generalSettings;

    // Basic model check for all providers
    if (settings.llmModel.isEmpty) {
      return false;
    }

    switch (settings.llmProvider) {
      case LlmProvider.openai:
        return settings.llmApiKey.isNotEmpty;
      case LlmProvider.google:
        return settings.llmApiKey.isNotEmpty;
      case LlmProvider.ollama:
        return settings.llmBaseUrl.isNotEmpty;
    }
  }

  /// Close the HTTP client
  void dispose() {
    _httpClient.close();
  }
}
