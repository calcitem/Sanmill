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
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/models/chat_message.dart';
import 'package:sanmill/shared/services/ai_chat_service.dart';
import 'package:uuid/uuid.dart';

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
  final List<ChatMessage> _messages = <ChatMessage>[];
  final Uuid _uuid = const Uuid();

  bool _isSending = false;
  StreamSubscription<String>? _streamSubscription;

  @override
  void initState() {
    super.initState();
    // Add welcome message
    _messages.add(
      ChatMessage(
        id: _uuid.v4(),
        content: S.current.aiChatWelcomeMessage,
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
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

    // Add user message
    final ChatMessage userMessage = ChatMessage(
      id: _uuid.v4(),
      content: message,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isSending = true;
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
      _messages.add(aiMessage);
    });

    _scrollToBottom();

    // Stream the response
    try {
      final StringBuffer fullResponse = StringBuffer();

      _streamSubscription = _chatService.sendMessage(message).listen(
        (String chunk) {
          fullResponse.write(chunk);

          setState(() {
            // Find and update the AI message
            final int index = _messages.indexWhere((ChatMessage m) => m.id == aiMessageId);
            if (index != -1) {
              _messages[index] = _messages[index].copyWith(
                content: fullResponse.toString(),
              );
            }
          });

          _scrollToBottom();
        },
        onDone: () {
          setState(() {
            // Mark streaming as complete
            final int index = _messages.indexWhere((ChatMessage m) => m.id == aiMessageId);
            if (index != -1) {
              _messages[index] = _messages[index].copyWith(
                isStreaming: false,
              );
            }
            _isSending = false;
          });
        },
        onError: (Object error) {
          setState(() {
            // Update message with error
            final int index = _messages.indexWhere((ChatMessage m) => m.id == aiMessageId);
            if (index != -1) {
              _messages[index] = _messages[index].copyWith(
                content: S.current.aiChatErrorMessage,
                isStreaming: false,
              );
            }
            _isSending = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        final int index = _messages.indexWhere((ChatMessage m) => m.id == aiMessageId);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(
            content: S.current.aiChatErrorMessage,
            isStreaming: false,
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
        content: Text(S.current.aiChatNotConfigured),
        action: SnackBarAction(
          label: S.current.settings,
          onPressed: () {
            Navigator.of(context).pop();
            // Navigate to settings would be handled by the app
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: <Widget>[
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.smart_toy,
                      color: colorScheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        S.current.aiChatTitle,
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: S.current.close,
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Messages list
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (BuildContext context, int index) {
                    final ChatMessage message = _messages[index];
                    return _MessageBubble(
                      message: message,
                      colorScheme: colorScheme,
                      textTheme: textTheme,
                    );
                  },
                ),
              ),

              const Divider(height: 1),

              // Input area
              Container(
                padding: const EdgeInsets.all(16),
                child: SafeArea(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: S.current.aiChatInputHint,
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
                            ? colorScheme.primary.withOpacity(0.5)
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
                                : Icon(
                                    Icons.send,
                                    color: colorScheme.onPrimary,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Message bubble widget for displaying chat messages
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.colorScheme,
    required this.textTheme,
  });

  final ChatMessage message;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

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
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!isUser) ...<Widget>[
            CircleAvatar(
              backgroundColor: colorScheme.primary,
              radius: 16,
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(16).copyWith(
                  topLeft: isUser ? const Radius.circular(16) : Radius.zero,
                  topRight: isUser ? Radius.zero : const Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (!isUser && message.content.isNotEmpty)
                    MarkdownBody(
                      data: message.content,
                      styleSheet: MarkdownStyleSheet(
                        p: textTheme.bodyMedium?.copyWith(color: textColor),
                        code: textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          backgroundColor: colorScheme.surface,
                          color: colorScheme.onSurface,
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
                      style: textTheme.bodyMedium?.copyWith(color: textColor),
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
