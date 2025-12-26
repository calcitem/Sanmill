// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:uuid/uuid.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/models/chat_message.dart';
import '../../shared/services/ai_chat_service.dart';

/// AI Chat Assistant Dialog
///
/// A bottom sheet dialog for chatting with an AI assistant about the current game.
/// Features:
/// - Context-aware advice based on current board state
/// - Markdown rendering for formatted responses
/// - Streaming responses with typewriter effect
/// - Professional chat UI
class AiChatDialog extends StatefulWidget {
  const AiChatDialog({super.key});

  @override
  State<AiChatDialog> createState() => _AiChatDialogState();
}

class _AiChatDialogState extends State<AiChatDialog> {
  final AiChatService _chatService = AiChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Uuid _uuid = const Uuid();

  bool _isSending = false;
  StreamSubscription<String>? _streamSubscription;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
  }

  void _initializeWelcomeMessage(BuildContext context) {
    if (!_isInitialized && _chatService.sessionManager.isEmpty) {
      _isInitialized = true;
      _chatService.sessionManager.addMessage(
        ChatMessage(
          id: _uuid.v4(),
          content: S.of(context).aiChatWelcomeMessage,
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _streamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final String message = _messageController.text.trim();
    if (message.isEmpty || _isSending) {
      return;
    }

    // Check if LLM is configured
    if (!_chatService.isConfigured()) {
      _showConfigurationError();
      return;
    }

    // Cancel any existing stream subscription to prevent overlapping requests
    await _streamSubscription?.cancel();

    // Add user message to session
    final ChatMessage userMessage = ChatMessage(
      id: _uuid.v4(),
      content: message,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _chatService.sessionManager.addMessage(userMessage);
      _isSending = true;
      _retryCount = 0; // Reset retry counter
    });

    _messageController.clear();
    _scrollToBottom();

    // Create AI message that will be updated with streaming content
    final String aiMessageId = _uuid.v4();
    final ChatMessage aiMessage = ChatMessage(
      id: aiMessageId,
      content: '',
      isUser: false,
      timestamp: DateTime.now(),
      isStreaming: true,
    );

    setState(() {
      _chatService.sessionManager.addMessage(aiMessage);
    });

    _scrollToBottom();

    // Stream the response with retry logic
    await _streamResponseWithRetry(message, aiMessageId);
  }

  /// Stream response with automatic retry on network errors
  Future<void> _streamResponseWithRetry(
    String message,
    String aiMessageId,
  ) async {
    try {
      final StringBuffer fullResponse = StringBuffer();
      bool hasReceivedData = false;

      _streamSubscription = _chatService
          .sendMessage(message)
          .listen(
            (String chunk) {
              if (!mounted) {
                return;
              }

              hasReceivedData = true;
              fullResponse.write(chunk);

              setState(() {
                // Update the AI message in session
                final ChatMessage? currentMessage = _chatService
                    .sessionManager
                    .messages
                    .cast<ChatMessage?>()
                    .firstWhere(
                      (ChatMessage? m) => m?.id == aiMessageId,
                      orElse: () => null,
                    );

                if (currentMessage != null) {
                  _chatService.sessionManager.updateMessage(
                    aiMessageId,
                    currentMessage.copyWith(content: fullResponse.toString()),
                  );
                }
              });

              _scrollToBottom();
            },
            onDone: () {
              if (!mounted) {
                return;
              }

              setState(() {
                // Mark streaming as complete in session
                final ChatMessage? currentMessage = _chatService
                    .sessionManager
                    .messages
                    .cast<ChatMessage?>()
                    .firstWhere(
                      (ChatMessage? m) => m?.id == aiMessageId,
                      orElse: () => null,
                    );

                if (currentMessage != null) {
                  _chatService.sessionManager.updateMessage(
                    aiMessageId,
                    currentMessage.copyWith(isStreaming: false),
                  );
                }
                _isSending = false;
                _retryCount = 0; // Reset on success
              });
            },
            onError: (Object error) async {
              if (!mounted) {
                return;
              }

              // Retry logic for network errors
              if (_retryCount < _maxRetries && !hasReceivedData) {
                _retryCount++;

                // Exponential backoff: 1s, 2s, 4s
                final int delaySeconds = 1 << (_retryCount - 1);
                await Future<void>.delayed(Duration(seconds: delaySeconds));

                if (mounted) {
                  setState(() {
                    // Update message to show retry attempt
                    final ChatMessage? currentMessage = _chatService
                        .sessionManager
                        .messages
                        .cast<ChatMessage?>()
                        .firstWhere(
                          (ChatMessage? m) => m?.id == aiMessageId,
                          orElse: () => null,
                        );

                    if (currentMessage != null) {
                      _chatService.sessionManager.updateMessage(
                        aiMessageId,
                        currentMessage.copyWith(
                          content:
                              'Retrying... (attempt $_retryCount/$_maxRetries)',
                        ),
                      );
                    }
                  });

                  // Retry the request
                  await _streamResponseWithRetry(message, aiMessageId);
                }
              } else {
                // Max retries reached or partial data received
                setState(() {
                  final ChatMessage? currentMessage = _chatService
                      .sessionManager
                      .messages
                      .cast<ChatMessage?>()
                      .firstWhere(
                        (ChatMessage? m) => m?.id == aiMessageId,
                        orElse: () => null,
                      );

                  if (currentMessage != null) {
                    if (mounted) {
                      final String errorMessage = _retryCount >= _maxRetries
                          ? '${S.of(context).aiChatErrorMessage}\n(Failed after $_maxRetries retries)'
                          : S.of(context).aiChatErrorMessage;

                      _chatService.sessionManager.updateMessage(
                        aiMessageId,
                        currentMessage.copyWith(
                          content: errorMessage,
                          isStreaming: false,
                        ),
                      );
                    }
                  }
                  _isSending = false;
                  _retryCount = 0;
                });
              }
            },
          );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        final ChatMessage? currentMessage = _chatService.sessionManager.messages
            .cast<ChatMessage?>()
            .firstWhere(
              (ChatMessage? m) => m?.id == aiMessageId,
              orElse: () => null,
            );

        if (currentMessage != null) {
          _chatService.sessionManager.updateMessage(
            aiMessageId,
            currentMessage.copyWith(
              content: S.of(context).aiChatErrorMessage,
              isStreaming: false,
            ),
          );
        }
        _isSending = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showConfigurationError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).aiChatNotConfigured),
        action: SnackBarAction(
          label: S.of(context).settings,
          onPressed: () {
            Navigator.of(context).pop();
            // Navigate to settings would be handled by the app
          },
        ),
      ),
    );
  }

  Future<void> _showClearHistoryDialog() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(S.of(context).aiChatClearHistoryConfirm),
          content: Text(S.of(context).aiChatClearHistoryMessage),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(S.of(context).cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(S.of(context).ok),
            ),
          ],
        );
      },
    );

    if ((confirmed ?? false) && mounted) {
      _clearHistory();
    }
  }

  void _clearHistory() {
    setState(() {
      _chatService.sessionManager.clearSession();
      _isInitialized =
          false; // Reset to allow welcome message to be shown again
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).aiChatCleared),
        duration: const Duration(seconds: 2),
      ),
    );

    // Re-initialize welcome message
    _initializeWelcomeMessage(context);
  }

  @override
  Widget build(BuildContext context) {
    // Initialize welcome message on first build
    _initializeWelcomeMessage(context);

    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final double keyboardHeight = mediaQuery.viewInsets.bottom;
    final Orientation orientation = mediaQuery.orientation;
    final Size screenSize = mediaQuery.size;

    // Detect landscape mode
    final bool isLandscape = orientation == Orientation.landscape;

    // Adaptive layout based on orientation
    if (isLandscape) {
      // Landscape: Side panel layout (right side)
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboardHeight),
          child: Container(
            width: screenSize.width * 0.4, // 40% of screen width in landscape
            height: screenSize.height,
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.95),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(20),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 15,
                  spreadRadius: 2,
                  offset: const Offset(-3, 0),
                ),
              ],
            ),
            child: _buildChatContent(colorScheme, textTheme, isLandscape: true),
          ),
        ),
      );
    }

    // Portrait: Bottom sheet layout (default)
    return Padding(
      // Add padding for keyboard avoidance
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (BuildContext context, ScrollController scrollController) {
          return Container(
            decoration: BoxDecoration(
              // Semi-transparent background with blur effect
              color: colorScheme.surface.withValues(alpha: 0.95),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 15,
                  spreadRadius: 2,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: _buildChatContent(
              colorScheme,
              textTheme,
              isLandscape: false,
            ),
          );
        },
      ),
    );
  }

  /// Build the chat content UI (reusable for both portrait and landscape)
  Widget _buildChatContent(
    ColorScheme colorScheme,
    TextTheme textTheme, {
    required bool isLandscape,
  }) {
    return Column(
      children: <Widget>[
        // Handle bar (only in portrait mode)
        if (!isLandscape)
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

        // Header (compact in landscape)
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isLandscape ? 12 : 16,
            vertical: isLandscape ? 8 : 12,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.smart_toy,
                color: colorScheme.primary,
                size: isLandscape ? 24 : 28,
              ),
              SizedBox(width: isLandscape ? 8 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      S.of(context).aiChatTitle,
                      style:
                          (isLandscape
                                  ? textTheme.titleMedium
                                  : textTheme.titleLarge)
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                    ),
                    // Token usage indicator (when near limit)
                    if (_chatService.sessionManager.isNearTokenLimit)
                      Text(
                        '⚠️ ${_chatService.sessionManager.tokenBudgetRemaining} tokens left',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep),
                iconSize: isLandscape ? 20 : 24,
                onPressed: _isSending ? null : _showClearHistoryDialog,
                tooltip: S.of(context).aiChatClearHistory,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                iconSize: isLandscape ? 20 : 24,
                onPressed: () => Navigator.of(context).pop(),
                tooltip: S.of(context).close,
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Messages list (compact padding in landscape)
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.all(isLandscape ? 12 : 16),
            itemCount: _chatService.sessionManager.messages.length,
            itemBuilder: (BuildContext context, int index) {
              final ChatMessage message =
                  _chatService.sessionManager.messages[index];
              return _MessageBubble(
                message: message,
                colorScheme: colorScheme,
                textTheme: textTheme,
                isCompact: isLandscape,
              );
            },
          ),
        ),

        const Divider(height: 1),

        // Input area (compact in landscape)
        Container(
          padding: EdgeInsets.all(isLandscape ? 12 : 16),
          child: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: S.of(context).aiChatInputHint,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                    ),
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    enabled: !_isSending,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: _isSending
                      ? colorScheme.primary.withValues(alpha: 0.5)
                      : colorScheme.primary,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    onTap: _isSending ? null : _sendMessage,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      child: _isSending
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  colorScheme.onPrimary,
                                ),
                              ),
                            )
                          : Icon(Icons.send, color: colorScheme.onPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Message bubble widget for displaying chat messages
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.colorScheme,
    required this.textTheme,
    this.isCompact = false,
  });

  final ChatMessage message;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.isUser;
    final Color backgroundColor = isUser
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final Color textColor = isUser
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;

    return Padding(
      padding: EdgeInsets.only(bottom: isCompact ? 12 : 16),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!isUser) ...<Widget>[
            CircleAvatar(
              backgroundColor: colorScheme.primary,
              radius: isCompact ? 14 : 16,
              child: Icon(
                Icons.smart_toy,
                size: 18,
                color: colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 12 : 16,
                vertical: isCompact ? 10 : 12,
              ),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(isCompact ? 12 : 16)
                    .copyWith(
                      topLeft: isUser
                          ? Radius.circular(isCompact ? 12 : 16)
                          : Radius.zero,
                      topRight: isUser
                          ? Radius.zero
                          : Radius.circular(isCompact ? 12 : 16),
                    ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (!isUser && message.content.isNotEmpty)
                    MarkdownBody(
                      data: message.content,
                      styleSheet: MarkdownStyleSheet(
                        p:
                            (isCompact
                                    ? textTheme.bodySmall
                                    : textTheme.bodyMedium)
                                ?.copyWith(color: textColor),
                        code: textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          backgroundColor: colorScheme.surface,
                          color: colorScheme.onSurface,
                          fontSize: isCompact ? 11 : null,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    )
                  else
                    Text(
                      message.content,
                      style:
                          (isCompact
                                  ? textTheme.bodySmall
                                  : textTheme.bodyMedium)
                              ?.copyWith(color: textColor),
                    ),
                  if (message.isStreaming) ...<Widget>[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(textColor),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) ...<Widget>[
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: colorScheme.secondary,
              radius: 16,
              child: Icon(
                Icons.person,
                size: 18,
                color: colorScheme.onSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
