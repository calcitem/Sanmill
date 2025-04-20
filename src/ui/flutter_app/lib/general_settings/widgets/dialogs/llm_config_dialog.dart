// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// llm_config_dialog.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
  late double _temperature;

  // Common model suggestions for each provider
  final Map<LlmProvider, List<String>> _modelSuggestions =
      <LlmProvider, List<String>>{
    LlmProvider.openai: <String>['o4-mini', 'gpt-4.1', 'gpt-3.5-turbo'],
    LlmProvider.google: <String>['gemini-pro', 'gemini-1.5-pro'],
    LlmProvider.ollama: <String>['gemma3', 'qwq', 'llama3.3', 'phi4'],
  };

  // Suggested base URLs for each provider, ordered by popularity
  final Map<LlmProvider, List<String>> _baseUrlSuggestions =
      <LlmProvider, List<String>>{
    LlmProvider.openai: <String>[
      'https://api.openai.com/v1', // Official endpoint
      'https://openrouter.ai/api/v1',
      'https://api.mistral.ai/v1',
      'https://api.together.xyz/v1',
      'https://api.endpoints.anyscale.com/v1',
      'https://api.groq.com/openai/v1',
      'https://api.perplexity.ai',
      'https://api.fireworks.ai/inference/v1',
      'https://api.siliconflow.cn/v1',
      'https://api.deepseek.com/v1',
    ],
    LlmProvider.google: <String>[
      // Google models use API key directly – no custom base URL needed
    ],
    LlmProvider.ollama: <String>[
      'http://localhost:11434',
      'http://192.168.1.100:11434',
    ],
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
    _temperature = DB().generalSettings.llmTemperature;
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
          // ignore: undefined_named_parameter
          llmTemperature: _temperature,
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
        return S.of(context).apiKeyOptional;
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

  // Get model suggestions considering both provider and base URL
  List<String> _getContextualModelSuggestions() {
    // For providers other than OpenAI, return the default list
    if (_selectedProvider != LlmProvider.openai) {
      return _modelSuggestions[_selectedProvider] ?? <String>[];
    }

    final String base = _baseUrlController.text.trim();

    // Suggestions for OpenAI
    if (base.startsWith('https://api.openai.com')) {
      return <String>[
        'o4-mini',
        'o3',
        'o3-mini',
        'o1',
        'o1-mini',
        'o1-pro',
        'gpt-4.1',
        'gpt-4.1-mini',
        'gpt-4.1-nano',
        'gpt-4',
        'gpt-4-0613',
        'gpt-4-32k',
        'gpt-4-32k-0613',
        'gpt-3.5-turbo',
        'gpt-3.5-turbo-0613',
        'gpt-3.5-turbo-16k',
        'gpt-3.5-turbo-16k-0613',
      ];
    }

    // Suggestions for OpenRouter
    if (base.startsWith('https://openrouter.ai')) {
      return <String>[
        'openai/gpt-4o',
        'openai/gpt-4o-mini',
        'anthropic/claude-3.5-sonnet',
        'google/gemma-3-27b-it',
        'google/gemini-2.0-flash-001',
        'google/gemini-flash-1.5',
        'google/gemini-flash-1.5-8b',
        'google/gemini-2.0-flash-lite-001',
        'meta-llama/llama-3.3-70b-instruct',
        'mistralai/mistral-7b-instruct',
        'deepseek/deepseek-r1',
        'deepseek/deepseek-r1:free',
        'deepseek/deepseek-chat-v3-0324:free',
        'deepseek/deepseek-chat-v3-0324',
        'qwen/qwq-32b',
      ];
    }

    // Suggestions for Mistral AI
    if (base.startsWith('https://api.mistral.ai')) {
      return <String>[
        'codestral-latest',
        'mistral-large-latest',
        'pixtral-large-latest',
        'mistral-saba-latest',
        'ministral-3b-latest',
        'ministral-8b-latest',
      ];
    }

    // Suggestions for Together AI
    if (base.startsWith('https://api.together.ai')) {
      return <String>[
        'meta-llama/Llama-4-Maverick-17B-128E-Instruct-FP8',
        'meta-llama/Llama-4-Scout-17B-16E-Instruct',
        'deepseek-ai/DeepSeek-R1',
        'deepseek-ai/DeepSeek-R1-Distill-Llama-70B-free',
        'deepseek-ai/DeepSeek-V3',
        'google/gemma-3-27b-it',
        'Qwen/QwQ-32B',
      ];
    }

    // Suggestions for Fireworks AI
    if (base.startsWith('https://api.siliconflow.cn')) {
      return <String>[
        'Pro/deepseek-ai/DeepSeek-R1',
        'Pro/deepseek-ai/DeepSeek-V3',
        'deepseek-ai/DeepSeek-V3',
        'Qwen/QwQ-32B',
      ];
    }

    // Suggestions for SiliconFlow
    if (base.startsWith('https://api.fireworks.ai')) {
      return <String>[
        'accounts/fireworks/models/deepseek-r1',
        'accounts/fireworks/models/deepseek-v3',
        'accounts/fireworks/models/deepseek-v3-0324',
      ];
    }

    // Suggestions for DeepSeek
    if (base.startsWith('https://api.deepseek.com')) {
      return <String>[
        'deepseek-chat',
        'deepseek-reasoner',
      ];
    }

    // Default OpenAI hosted suggestions
    return _modelSuggestions[LlmProvider.openai] ?? <String>[];
  }

  // Show dialog with base URL suggestions
  void _showBaseUrlSuggestions() {
    final List<String> suggestions =
        _baseUrlSuggestions[_selectedProvider] ?? <String>[];

    if (suggestions.isEmpty) {
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(S.of(context).commonBaseUrls),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: suggestions
                  .map((String url) => ListTile(
                        title: Text(url),
                        onTap: () {
                          setState(() {
                            _baseUrlController.text = url;
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

  // Display model suggestions dialog
  void _showModelSuggestions() {
    final List<String> suggestions = _getContextualModelSuggestions();

    if (suggestions.isEmpty) {
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(S.of(context).commonlyUsedModels),
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

  // Build a temperature slider widget
  Widget _buildTemperatureSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          S.of(context).temperature,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Slider(
          value: _temperature,
          divisions: 10,
          label: _temperature.toStringAsFixed(1),
          onChanged: (double value) {
            setState(() {
              _temperature = value;
            });
          },
        ),
      ],
    );
  }

  // Launch URL for API key generation depending on provider/base URL
  Future<void> _launchApiKeyUrl() async {
    String url = '';

    // Trimmed base URL for matching
    final String base = _baseUrlController.text.trim();

    switch (_selectedProvider) {
      case LlmProvider.openai:
        // When provider is OpenAI, the user may actually be using third‑party compatible endpoints.
        if (base.startsWith('https://openrouter.ai')) {
          url = 'https://openrouter.ai/keys';
        } else if (base.startsWith('https://api.mistral.ai')) {
          url = 'https://console.mistral.ai/api-keys';
        } else if (base.startsWith('https://api.together.ai') ||
            base.startsWith('https://api.together.xyz')) {
          url = 'https://docs.together.ai/docs/api-keys';
        } else if (base.startsWith('https://api.endpoints.anyscale.com')) {
          url = 'https://console.anyscale.com';
        } else if (base.startsWith('https://api.groq.com')) {
          url = 'https://console.groq.com/keys';
        } else if (base.startsWith('https://api.perplexity.ai')) {
          url = 'https://www.perplexity.ai';
        } else if (base.startsWith('https://api.fireworks.ai')) {
          url =
              'https://docs.fireworks.ai/api-reference/create-api-key#create-api-key';
        } else if (base.startsWith('https://api.siliconflow.cn')) {
          url = 'https://cloud.siliconflow.cn/account/ak';
        } else if (base.startsWith('https://api.deepseek.com')) {
          url = 'https://platform.deepseek.com';
        } else {
          // Default to OpenAI
          url = 'https://platform.openai.com/api-keys';
        }
        break;
      case LlmProvider.google:
        url = 'https://aistudio.google.com/app/u/1/apikey';
        break;
      case LlmProvider.ollama:
        url = 'https://ollama.com/';
        break;
    }

    if (url.isEmpty) {
      return;
    }
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
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
            Text(
              S.of(context).llmConfig,
              style: const TextStyle(
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
                    Text(
                      S.of(context).llmProvider,
                      style: const TextStyle(fontWeight: FontWeight.bold),
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
                          child: Text(
                            provider.name,
                            style: const TextStyle(fontSize: 14.0),
                          ),
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

                    // Base URL (conditionally shown)
                    if (_shouldShowBaseUrl()) ...<Widget>[
                      // Base URL label with suggestions button
                      Row(
                        children: <Widget>[
                          Text(
                            S.of(context).baseUrl,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _showBaseUrlSuggestions,
                            child: Text(S.of(context).viewCommonUrls),
                          ),
                        ],
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

                    // Model name with suggestions button
                    Row(
                      children: <Widget>[
                        Text(
                          S.of(context).model,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        // Add a suggestion button to help users
                        TextButton(
                          onPressed: _showModelSuggestions,
                          child: Text(S.of(context).viewCommonModels),
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
                        helperText: S.of(context).youCanEnterAnyModelName,
                        // "You can enter any model name"
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
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        // Show Get API Key button only for non-Ollama providers
                        suffixIcon: _selectedProvider != LlmProvider.ollama
                            ? IconButton(
                                icon: const Icon(Icons.open_in_new),
                                tooltip: S.of(context).getApiKey,
                                onPressed: _launchApiKeyUrl,
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12.0, vertical: 8.0),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16.0),

                    // Temperature slider
                    _buildTemperatureSlider(),

                    // Add extra spacing before buttons
                    const SizedBox(height: 24.0),
                  ],
                ),
              ),
            ),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                // Cancel button on the left
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
                  child: Text(
                    S.of(context).cancel, // "Cancel"
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                // OK button on the right
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
