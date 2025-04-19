// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// llm_config_dialog.dart

import 'package:flutter/material.dart';

import '../../../generated/intl/l10n.dart';
import '../../../shared/database/database.dart';
import '../../models/general_settings.dart';

/// A dialog for configuring LLM provider settings
class LlmConfigDialog extends StatefulWidget {
  const LlmConfigDialog({super.key});

  @override
  State<LlmConfigDialog> createState() => _LlmConfigDialogState();
}

class _LlmConfigDialogState extends State<LlmConfigDialog> {
  late LlmProvider _selectedProvider;
  late final TextEditingController _modelController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _baseUrlController;

  // Common model suggestions for each provider
  final Map<LlmProvider, List<String>> _modelSuggestions =
      <LlmProvider, List<String>>{
    LlmProvider.openai: <String>['gpt-4', 'gpt-4o', 'gpt-3.5-turbo'],
    LlmProvider.google: <String>['gemini-pro', 'gemini-1.5-pro'],
    LlmProvider.ollama: <String>['llama3', 'llama2', 'mistral', 'phi3'],
  };

  @override
  void initState() {
    super.initState();
    // Get current LLM settings from DB
    _selectedProvider = DB().generalSettings.llmProvider;
    _modelController =
        TextEditingController(text: DB().generalSettings.llmModel);
    _apiKeyController =
        TextEditingController(text: DB().generalSettings.llmApiKey);
    _baseUrlController =
        TextEditingController(text: DB().generalSettings.llmBaseUrl);
  }

  @override
  void dispose() {
    _modelController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  // Save the LLM configuration to database
  void _saveConfig() {
    // Update settings using copyWith method to modify only the necessary fields
    DB().generalSettings = DB().generalSettings.copyWith(
          llmProvider: _selectedProvider,
          llmModel: _modelController.text.trim(),
          llmApiKey: _apiKeyController.text.trim(),
          llmBaseUrl: _baseUrlController.text.trim(),
        );
    Navigator.of(context).pop();
  }

  // Get provider-specific model hint text
  String _getModelHint() {
    switch (_selectedProvider) {
      case LlmProvider.openai:
        return 'Enter any model name, e.g. gpt-4, gpt-4o';
      case LlmProvider.google:
        return 'Enter any model name, e.g. gemini-pro, gemini-1.5-pro';
      case LlmProvider.ollama:
        return 'Enter any model name, e.g. llama3, mistral, phi3';
    }
  }

  // Get provider-specific API key label
  String _getApiKeyLabel() {
    switch (_selectedProvider) {
      case LlmProvider.openai:
        return 'OpenAI API Key';
      case LlmProvider.google:
        return 'Google API Key';
      case LlmProvider.ollama:
        return 'API Key (Optional)';
    }
  }

  // Get provider-specific base URL hint
  String _getBaseUrlHint() {
    switch (_selectedProvider) {
      case LlmProvider.openai:
        return 'e.g. https://api.openai.com/v1';
      case LlmProvider.google:
        return '';
      case LlmProvider.ollama:
        return 'e.g. http://localhost:11434';
    }
  }

  // Check if base URL field should be shown
  bool _shouldShowBaseUrl() {
    return _selectedProvider == LlmProvider.openai ||
        _selectedProvider == LlmProvider.ollama;
  }

  // Display model suggestions dialog
  void _showModelSuggestions() {
    final List<String> suggestions =
        _modelSuggestions[_selectedProvider] ?? <String>[];

    if (suggestions.isEmpty) {
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('常用模型'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: suggestions
                  .map((String model) => ListTile(
                        title: Text(model),
                        onTap: () {
                          setState(() {
                            _modelController.text = model;
                          });
                          Navigator.pop(context);
                        },
                      ))
                  .toList(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(S.of(context).cancel),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'LLM 配置',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16.0),

            // Make dialog content scrollable
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Provider selection
                    const Text(
                      "提供商",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8.0),
                    DropdownButtonFormField<LlmProvider>(
                      value: _selectedProvider,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12.0, vertical: 8.0),
                      ),
                      items: LlmProvider.values.map((LlmProvider provider) {
                        return DropdownMenuItem<LlmProvider>(
                          value: provider,
                          child: Text(provider.name),
                        );
                      }).toList(),
                      onChanged: (LlmProvider? value) {
                        if (value != null) {
                          setState(() {
                            _selectedProvider = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16.0),

                    // Model name with suggestions button
                    Row(
                      children: <Widget>[
                        const Text(
                          "模型",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        // Add a suggestion button to help users
                        TextButton(
                          onPressed: _showModelSuggestions,
                          child: const Text("查看常用模型"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8.0),
                    // Free-form text field for model name
                    TextField(
                      controller: _modelController,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: _getModelHint(),
                        helperText:
                            "可输入任何模型名称", // "You can enter any model name"
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12.0, vertical: 8.0),
                      ),
                    ),
                    const SizedBox(height: 16.0),

                    // API Key
                    Text(
                      _getApiKeyLabel(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8.0),
                    TextField(
                      controller: _apiKeyController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12.0, vertical: 8.0),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16.0),

                    // Base URL (conditionally shown)
                    if (_shouldShowBaseUrl()) ...<Widget>[
                      const Text(
                        "Base URL",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8.0),
                      TextField(
                        controller: _baseUrlController,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText: _getBaseUrlHint(),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 8.0),
                        ),
                      ),
                      const SizedBox(height: 16.0),
                    ],
                  ],
                ),
              ),
            ),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(S.of(context).cancel), // "Cancel"
                ),
                const SizedBox(width: 8.0),
                ElevatedButton(
                  onPressed: _saveConfig,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
                  child: Text(
                    S.of(context).ok, // "Save"
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
