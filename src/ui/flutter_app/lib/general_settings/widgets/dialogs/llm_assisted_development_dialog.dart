// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// llm_assisted_development_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../generated/intl/l10n.dart';
import '../../../shared/services/snackbar_service.dart';
import '../../../shared/utils/helpers/text_helpers/safe_text_editing_controller.dart';
import '../../../shared/utils/llm/llm_assisted_development_prompt_builder.dart';

/// A dialog that helps developers compose a prompt for an external LLM.
///
/// It prepends/appends fixed English instructions and optionally appends a log
/// snippet detected from the current clipboard content.
class LlmAssistedDevelopmentDialog extends StatefulWidget {
  const LlmAssistedDevelopmentDialog({super.key});

  @override
  State<LlmAssistedDevelopmentDialog> createState() =>
      _LlmAssistedDevelopmentDialogState();
}

class _LlmAssistedDevelopmentDialogState
    extends State<LlmAssistedDevelopmentDialog> {
  late final TextEditingController _taskController;
  bool _isCopying = false;

  @override
  void initState() {
    super.initState();
    _taskController = SafeTextEditingController();
  }

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard() async {
    final String task = _taskController.text.trim();
    if (task.isEmpty) {
      return;
    }

    final S strings = S.of(context);

    setState(() {
      _isCopying = true;
    });

    final ClipboardData? clipboard = await Clipboard.getData(
      Clipboard.kTextPlain,
    );

    if (!mounted) {
      return;
    }

    final String? log = extractSanmillLog(clipboard?.text ?? '');

    final String prompt = buildLlmAssistedDevelopmentPrompt(
      task: task,
      languageName: strings.languageName,
      log: log,
    );

    await Clipboard.setData(ClipboardData(text: prompt));

    if (!mounted) {
      return;
    }

    SnackBarService.showRootSnackBar(strings.copiedToClipboard);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bool canCopy = !_isCopying && _taskController.text.trim().isNotEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              S.of(context).llmAssistedDevelopment,
              style: const TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12.0),
            Expanded(
              child: TextField(
                controller: _taskController,
                minLines: 10,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                onChanged: (_) {
                  if (_isCopying) {
                    return;
                  }
                  setState(() {});
                },
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: S.of(context).llmAssistedDevelopmentInputHint,
                ),
              ),
            ),
            const SizedBox(height: 12.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                ElevatedButton(
                  onPressed: _isCopying
                      ? null
                      : () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
                  child: Text(
                    S.of(context).close,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                ElevatedButton(
                  onPressed: canCopy ? _copyToClipboard : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
                  child: _isCopying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          S.of(context).copy,
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
