// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// voice_button.dart

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/services/snackbar_service.dart';
import '../models/voice_assistant_settings.dart';
import '../services/voice_assistant_service.dart';
import '../services/voice_command_processor.dart';

/// Floating action button for voice assistant
class VoiceAssistantButton extends StatefulWidget {
  const VoiceAssistantButton({super.key});

  @override
  State<VoiceAssistantButton> createState() => _VoiceAssistantButtonState();
}

class _VoiceAssistantButtonState extends State<VoiceAssistantButton>
    with SingleTickerProviderStateMixin {
  final VoiceAssistantService _service = VoiceAssistantService();
  bool _isListening = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VoiceAssistantSettings settings = DB().voiceAssistantSettings;

    // Don't show button if voice assistant is disabled or button is hidden
    if (!settings.enabled || !settings.showVoiceButton) {
      return const SizedBox.shrink();
    }

    // Don't show button if not ready
    if (!_service.isReady) {
      return const SizedBox.shrink();
    }

    return FloatingActionButton(
      onPressed: _isListening ? null : _onPressed,
      backgroundColor: _isListening ? Colors.red : Colors.blue,
      child: _isListening
          ? AnimatedBuilder(
              animation: _animationController,
              builder: (BuildContext context, Widget? child) {
                return Icon(
                  Icons.mic,
                  color: Colors.white.withOpacity(
                    0.5 + (_animationController.value * 0.5),
                  ),
                );
              },
            )
          : const Icon(Icons.mic, color: Colors.white),
    );
  }

  Future<void> _onPressed() async {
    setState(() {
      _isListening = true;
    });

    final S loc = S.of(context);

    // Show listening snackbar
    SnackBarService.showRootSnackBar(loc.voiceAssistantListening);

    try {
      // Start listening
      final VoiceCommandResult? result = await _service.startListening(context);

      if (mounted) {
        if (result != null) {
          // Show result message
          final String message =
              result.message ?? _getDefaultMessage(result.type, result.success, loc);
          SnackBarService.showRootSnackBar(
            message,
            duration: const Duration(seconds: 2),
          );
        } else {
          // No result
          SnackBarService.showRootSnackBar(
            loc.voiceAssistantNoSpeechDetected,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.showRootSnackBar(
          loc.voiceAssistantError,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
    }
  }

  String _getDefaultMessage(
    VoiceCommandType type,
    bool success,
    S loc,
  ) {
    if (success) {
      switch (type) {
        case VoiceCommandType.move:
          return loc.voiceCommandMoveSuccess;
        case VoiceCommandType.undo:
          return loc.voiceCommandUndoSuccess;
        case VoiceCommandType.redo:
          return loc.voiceCommandRedoSuccess;
        case VoiceCommandType.restart:
          return loc.voiceCommandRestartSuccess;
        case VoiceCommandType.aiMove:
          return loc.voiceCommandAiMoveSuccess;
        case VoiceCommandType.settings:
          return loc.voiceCommandSettingsSuccess;
        case VoiceCommandType.help:
          return loc.voiceCommandHelpSuccess;
        case VoiceCommandType.unknown:
          return loc.voiceCommandUnknown;
      }
    } else {
      return loc.voiceCommandFailed;
    }
  }
}

/// Inline voice button widget (for use in toolbars)
class VoiceAssistantIconButton extends StatefulWidget {
  const VoiceAssistantIconButton({super.key});

  @override
  State<VoiceAssistantIconButton> createState() =>
      _VoiceAssistantIconButtonState();
}

class _VoiceAssistantIconButtonState extends State<VoiceAssistantIconButton> {
  final VoiceAssistantService _service = VoiceAssistantService();
  bool _isListening = false;

  @override
  Widget build(BuildContext context) {
    final VoiceAssistantSettings settings = DB().voiceAssistantSettings;

    // Don't show button if voice assistant is disabled
    if (!settings.enabled || !_service.isReady) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: Icon(
        Icons.mic,
        color: _isListening ? Colors.red : null,
      ),
      onPressed: _isListening ? null : _onPressed,
      tooltip: S.of(context).voiceAssistant,
    );
  }

  Future<void> _onPressed() async {
    setState(() {
      _isListening = true;
    });

    final S loc = S.of(context);

    try {
      final VoiceCommandResult? result = await _service.startListening(context);

      if (mounted && result != null) {
        final String message = result.message ?? loc.voiceCommandSuccess;
        SnackBarService.showRootSnackBar(message);
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.showRootSnackBar(loc.voiceAssistantError);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
    }
  }
}
