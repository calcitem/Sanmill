// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// llm_prompt_dialog.dart

import 'package:flutter/material.dart';

import '../../../generated/intl/l10n.dart';
import '../../../shared/config/prompt_defaults.dart';
import '../../../shared/database/database.dart';
import '../../models/general_settings.dart';

/// A dialog for editing LLM prompt header and footer
class LlmPromptDialog extends StatefulWidget {
  const LlmPromptDialog({super.key});

  @override
  State<LlmPromptDialog> createState() => _LlmPromptDialogState();
}

class _LlmPromptDialogState extends State<LlmPromptDialog> {
  late final TextEditingController _headerController;
  late final TextEditingController _footerController;

  @override
  void initState() {
    super.initState();
    // Get current prompt settings from DB
    final String currentHeader = DB().generalSettings.llmPromptHeader;
    final String currentFooter = DB().generalSettings.llmPromptFooter;

    // Initialize controllers with current values, or default values if empty
    _headerController = TextEditingController(
        text: currentHeader.isEmpty
            ? PromptDefaults.llmPromptHeader
            : currentHeader);
    _footerController = TextEditingController(
        text: currentFooter.isEmpty
            ? PromptDefaults.llmPromptFooter
            : currentFooter);
  }

  @override
  void dispose() {
    _headerController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  // Save the prompt settings to database
  void _savePrompts() {
    // Get text from controllers
    final String headerText = _headerController.text;
    final String footerText = _footerController.text;

    // Use default values if fields are empty
    final String finalHeader =
        headerText.isEmpty ? PromptDefaults.llmPromptHeader : headerText;
    final String finalFooter =
        footerText.isEmpty ? PromptDefaults.llmPromptFooter : footerText;

    // Update settings using copyWith method to modify only the necessary fields
    DB().generalSettings = DB().generalSettings.copyWith(
          llmPromptHeader: finalHeader,
          llmPromptFooter: finalFooter,
        );
    Navigator.of(context).pop();
  }

  // Reset to default values
  void _resetToDefaults() {
    setState(() {
      _headerController.text = PromptDefaults.llmPromptHeader;
      _footerController.text = PromptDefaults.llmPromptFooter;
    });
  }

  // Show confirmation dialog before restoring defaults
  void _confirmResetToDefaults() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(S.of(context).restoreDefaultSettings),
          content: Text(S
              .of(context)
              .areYouSureYouWantToResetThePromptTemplatesToDefaultValues),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(S.of(context).cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _resetToDefaults();
              },
              child: Text(S.of(context).ok),
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
        // Make dialog scrollable to fit on all screen sizes
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              S.of(context).llmPrompt, // "LLM Prompt"
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
                    // Header section
                    Text(
                      S.of(context).llmPromptTemplateHeader,
                      // Using literal while waiting for translation
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8.0),
                    Container(
                      height: 200.0,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: SingleChildScrollView(
                        child: TextField(
                          controller: _headerController,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.all(8.0),
                            border: InputBorder.none,
                            hintText: S
                                .of(context)
                                .ifLeftEmptyDefaultTemplateWillBeUsed,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16.0),

                    // Footer section
                    Text(
                      S.of(context).llmPromptTemplateFooter,
                      // Using literal while waiting for translation
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8.0),
                    Container(
                      height: 120.0,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: SingleChildScrollView(
                        child: TextField(
                          controller: _footerController,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.all(8.0),
                            border: InputBorder.none,
                            hintText: S
                                .of(context)
                                .ifLeftEmptyDefaultTemplateWillBeUsed,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16.0),

            // Reset button
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _confirmResetToDefaults,
                child: Text(
                    S.of(context).restoreDefaultSettings), // "Reset to Default"
              ),
            ),

            const SizedBox(height: 8.0),

            // Cancel and OK buttons (following Android convention)
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
                  onPressed: _savePrompts,
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
