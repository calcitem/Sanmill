// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// moves_list_page.dart

import 'dart:async';
import 'dart:io' show Platform;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../appearance_settings/models/display_settings.dart';
import '../../general_settings/widgets/dialogs/llm_config_dialog.dart';
import '../../general_settings/widgets/dialogs/llm_prompt_dialog.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/config/prompt_defaults.dart';
import '../../shared/database/database.dart';
import '../../shared/services/environment_config.dart';
import '../../shared/services/language_locale_mapping.dart';
import '../../shared/services/llm_service.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../services/import_export/pgn.dart';
import '../services/mill.dart';
import 'cat_fishing_game.dart';
import 'mini_board.dart';

// Key for the LLM prompt dialog screen
const String _kLlmPromptDialogKey = 'llm_prompt_dialog';
// Text for the S.of(context).askLlm button
// Text for when LLM is loading
const String _kLlmLoading = 'Loading response...';

/// MovesListPage can display PGN nodes in different layouts.
/// The user can pick from a set of layout options via a single active icon which,
/// when tapped, reveals a row of layout icons.
class MovesListPage extends StatefulWidget {
  const MovesListPage({super.key});

  @override
  MovesListPageState createState() => MovesListPageState();
}

class MovesListPageState extends State<MovesListPage> {
  /// A flat list of all PGN nodes (collected recursively).
  final List<PgnNode<ExtMove>> _allNodes = <PgnNode<ExtMove>>[];

  /// Whether to reverse the order of the nodes.
  bool _isReversedOrder = false;

  /// ScrollController to control the scrolling of the ListView or GridView.
  final ScrollController _scrollController = ScrollController();

  /// Current layout selection, loaded from DB settings
  MovesViewLayout _currentLayout = DB().displaySettings.movesViewLayout;

  // Timer to track elapsed seconds while waiting for LLM response
  Timer? loadingTimer;
  DateTime? requestStartTime;
  int elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    // Collect all nodes from the PGN tree into _allNodes.
    // For example:
    // final PgnNode<ExtMove> root = GameController().gameRecorder.pgnRoot;
    // _collectAllNodes(root);
    _refreshAllNodes();
  }

  // Uncomment if you want a fully recursive collecting method.
  // void _collectAllNodes(PgnNode<ExtMove> node) {
  //   _allNodes.add(node);
  //   for (final PgnNode<ExtMove> child in node.children) {
  //     _collectAllNodes(child);
  //   }
  // }

  /// Clears and refreshes _allNodes from the game recorder.
  void _refreshAllNodes() {
    _allNodes
      ..clear()
      ..addAll(GameController().gameRecorder.mainlineNodes);

    int currentMoveIndex = 0; // Initialize move index for the first node
    int currentRound = 1; // Initialize round number starting at 1
    PieceColor?
        lastNonRemoveSide; // To track the side of the last non-remove move

    for (int i = 0; i < _allNodes.length; i++) {
      final PgnNode<ExtMove> node = _allNodes[i];

      // Set moveIndex as before
      if (i == 0) {
        // First node always gets moveIndex 0
        node.data?.moveIndex = currentMoveIndex;
      } else if (node.data?.type == MoveType.remove) {
        // If it's a remove type, use the previous node's moveIndex
        node.data?.moveIndex = _allNodes[i - 1].data?.moveIndex;
      } else {
        // Otherwise, increment the previous node's moveIndex
        currentMoveIndex = (_allNodes[i - 1].data?.moveIndex ?? 0) + 1;
        node.data?.moveIndex = currentMoveIndex;
      }

      // Calculate and assign roundIndex for each move
      if (node.data != null) {
        if (node.data!.type == MoveType.remove) {
          // For remove moves, assign the same round as the last non-remove move
          node.data!.roundIndex = currentRound;
        } else {
          // For non-remove moves:
          // If the last non-remove move was made by Black and current move is by White,
          // it indicates a new round should start.
          if (lastNonRemoveSide == PieceColor.black &&
              node.data!.side == PieceColor.white) {
            currentRound++;
          }
          node.data!.roundIndex = currentRound;
          lastNonRemoveSide =
              node.data!.side; // Update last non-remove move side
        }
      }
    }
  }

  /// Helper method to load a game, then refresh.
  Future<void> _loadGame() async {
    await GameController.load(context, shouldPop: false);
    // Wait briefly, then refresh our list of nodes.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    setState(_refreshAllNodes);
  }

  /// Helper method to import a game, then refresh.
  Future<void> _importGame() async {
    await GameController.import(context, shouldPop: false);
    // Wait briefly, then refresh our list of nodes.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    setState(_refreshAllNodes);
  }

  void _saveGame() {
    GameController.save(context, shouldPop: false);
  }

  void _exportGame() {
    GameController.export(context, shouldPop: false);
  }

  /// Copies the moveListPrompt (a special format for LLM) into the clipboard.
  /// Displays a SnackBar indicating success or if there's no prompt data.
  Future<void> _copyLLMPrompt(String promptText) async {
    if (promptText.isEmpty) {
      rootScaffoldMessengerKey.currentState!.showSnackBar(
          SnackBar(content: Text(S.of(context).noLlmPromptAvailable)));
      return;
    }
    await Clipboard.setData(ClipboardData(text: promptText));

    if (!mounted) {
      return;
    }
    rootScaffoldMessengerKey.currentState!
        .showSnackBarClear(S.of(context).llmPromptCopiedToClipboard);
  }

  /// Shows a dialog with LLM prompt content that can be edited and copied
  Future<void> _showLLMPromptDialog() async {
    // Get the initial prompt text
    final String initialPrompt = GameController().gameRecorder.moveListPrompt;

    if (initialPrompt.isEmpty) {
      rootScaffoldMessengerKey.currentState!.showSnackBar(
          SnackBar(content: Text(S.of(context).noLlmPromptAvailable)));
      return;
    }

    // Create a controller for the text editing
    final TextEditingController controller =
        TextEditingController(text: initialPrompt);

    // Flag to track if user wants the response in current app language
    const bool useCurrentLanguage = true;

    // Show dialog and await result
    if (!mounted) {
      return;
    }

    // Calculate dialog size based on screen size
    final Size screenSize = MediaQuery.of(context).size;
    final double dialogWidth = screenSize.width * 0.85;
    final double dialogHeight = screenSize.height * 0.7;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        // Use app theme colors
        final DialogThemeData dialogThemeObj = Theme.of(context).dialogTheme;
        final Color bgColor = dialogThemeObj.backgroundColor ??
            Theme.of(context).colorScheme.surface;
        final Color textColor = DB().colorSettings.messageColor;
        final Color borderColor =
            DB().colorSettings.messageColor.withValues(alpha: 0.3);

        // Local state for checkbox
        bool localUseCurrentLanguage = useCurrentLanguage;

        // LLM state variables
        bool isLoading = false;
        String llmResponse = '';
        bool showLlmResponse = false;
        final bool isLlmConfigured =
            LlmService().isLlmConfigured(); // Check if LLM is configured

        // Add a flag to track if the dialog is still active
        bool isDialogActive = true;

        return StatefulBuilder(
          key: const Key(_kLlmPromptDialogKey),
          builder: (BuildContext context, StateSetter setState) {
            // Function to generate LLM response
            Future<void> generateLlmResponse() async {
              if (!isLlmConfigured) {
                setState(() {
                  showLlmResponse = true;
                  llmResponse =
                      S.of(context).llmNotConfiguredPleaseCheckYourSettings;
                  isLoading = false;
                });
                return;
              }

              setState(() {
                isLoading = true;
                showLlmResponse = true;
                llmResponse = _kLlmLoading;

                // Initialize timer for fun loading messages
                requestStartTime = DateTime.now();
                elapsedSeconds = 0;

                loadingTimer?.cancel();
                loadingTimer =
                    Timer.periodic(const Duration(seconds: 1), (Timer t) {
                  // Update elapsed time every second while loading
                  if (!isDialogActive) {
                    // Cancel timer if dialog is closed
                    t.cancel();
                    return;
                  }
                  setState(() {
                    elapsedSeconds =
                        DateTime.now().difference(requestStartTime!).inSeconds;
                  });
                });
              });

              final String promptToUse = _getPromptWithLanguage(
                  controller.text, localUseCurrentLanguage);

              // Call LLM service for real response
              final LlmService llmService = LlmService();
              String fullResponse = '';
              try {
                await for (final String chunk
                    in llmService.generateResponse(promptToUse, context)) {
                  // Check if the dialog is still active
                  if (!isDialogActive) {
                    // Dialog closed, interrupt processing
                    break;
                  }
                  setState(() {
                    fullResponse += chunk;
                    llmResponse = fullResponse;
                  });
                }
              } catch (e) {
                // Check if the dialog is still active
                if (isDialogActive) {
                  setState(() {
                    llmResponse = 'Error: $e';
                  });
                }
              } finally {
                // Check if the dialog is still active
                if (isDialogActive) {
                  setState(() {
                    isLoading = false;
                    loadingTimer?.cancel();
                  });
                } else {
                  // Ensure timer is cancelled
                  loadingTimer?.cancel();
                }
              }
            }

            // Function to import moves from LLM response
            void importMovesFromResponse() {
              final String extractedMoves =
                  LlmService().extractMoves(llmResponse);

              try {
                // Import the moves directly without using the clipboard
                ImportService.import(extractedMoves);

                // Ensure the widget is still in the widget tree before using the context
                if (!context.mounted) {
                  return;
                }

                // Close the dialog first
                Navigator.of(context).pop();

                // Perform history navigation to refresh the board state
                HistoryNavigator.takeBackAll(context, pop: false).then((_) {
                  if (context.mounted) {
                    // Show success message
                    rootScaffoldMessengerKey.currentState
                        ?.showSnackBarClear(S.of(context).gameImported);
                    GameController()
                        .headerTipNotifier
                        .showTip(S.of(context).gameImported);

                    // Wait briefly, then refresh the move list in the parent page
                    Future<void>.delayed(const Duration(milliseconds: 500))
                        .then((_) {
                      if (mounted) {
                        // Call the parent setState to refresh nodes
                        this.setState(_refreshAllNodes);
                      }
                    });
                  }
                });
              } catch (e) {
                logger.e('Error importing moves: $e');

                if (context.mounted) {
                  rootScaffoldMessengerKey.currentState!.showSnackBar(
                    SnackBar(content: Text(S.of(context).cannotImport(e))),
                  );
                  Navigator.of(context).pop();
                }
              }
            }

            // Function to show LLM config dialog
            void showLlmConfigDialog() {
              // Store reference to the current outer context
              final BuildContext outerContext = context;

              showDialog<void>(
                context: context,
                barrierDismissible:
                    false, // Prevent dismissing by tapping outside
                builder: (BuildContext context) => const LlmConfigDialog(),
              ).then((_) {
                // No need to reopen the LLM prompt dialog since we never closed it
                // Just refresh any data that might have been updated in config dialog if needed
                if (outerContext.mounted) {
                  setState(() {
                    // Update any state that might have changed in the config dialog
                  });
                }
              });
            }

            // Function to show LLM prompt template dialog
            void showLlmPromptTemplateDialog() {
              // Store reference to the current outer context
              final BuildContext outerContext = context;

              showDialog<void>(
                context: context,
                barrierDismissible:
                    false, // Prevent dismissing by tapping outside
                builder: (BuildContext context) => const LlmPromptDialog(),
              ).then((_) {
                // No need to reopen the LLM prompt dialog since we never closed it
                // Just refresh any data that might have been updated in template dialog if needed
                if (outerContext.mounted) {
                  setState(() {
                    // Update any state that might have changed in the template dialog
                  });
                }
              });
            }

            return PopScope<dynamic>(
              onPopInvokedWithResult: (bool didPop, dynamic result) {
                // Set flag and cancel timer when dialog is closed
                isDialogActive = false;
                loadingTimer?.cancel();
              },
              child: Dialog(
                insetPadding: const EdgeInsets.all(16.0),
                backgroundColor: bgColor,
                child: SizedBox(
                  width: dialogWidth,
                  height: dialogHeight,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // Dialog title
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              S.of(context).llmPrompt,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                // LLM Prompt Template button
                                IconButton(
                                  onPressed: showLlmPromptTemplateDialog,
                                  icon: const Icon(
                                      FluentIcons.document_edit_24_regular),
                                  tooltip: S.of(context).llmPromptTemplate,
                                  color: DB().colorSettings.pieceHighlightColor,
                                ),
                                // LLM Config button
                                IconButton(
                                  onPressed: showLlmConfigDialog,
                                  icon: const Icon(
                                      FluentIcons.settings_24_regular),
                                  tooltip: S.of(context).llmConfig,
                                  color: DB().colorSettings.pieceHighlightColor,
                                ),
                                // Close button - with enhanced visibility
                                Container(
                                  margin: const EdgeInsets.only(left: 8.0),
                                  child: IconButton(
                                    iconSize: 26,
                                    icon: Icon(
                                      FluentIcons.dismiss_24_filled,
                                      color: DB()
                                          .colorSettings
                                          .pieceHighlightColor,
                                    ),
                                    tooltip: S.of(context).close,
                                    onPressed: () {
                                      // Set flag and cancel timer when user closes dialog
                                      isDialogActive = false;
                                      loadingTimer?.cancel();
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Content area - either prompt input or LLM response
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: showLlmResponse
                                ? _buildLlmResponseWidget(
                                    llmResponse,
                                    isLoading,
                                    elapsedSeconds,
                                    textColor,
                                    borderColor,
                                  )
                                : _buildPromptInputWidget(
                                    controller,
                                    textColor,
                                    borderColor,
                                  ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Only show language checkbox when prompt is visible
                        if (!showLlmResponse)
                          Row(
                            children: <Widget>[
                              Checkbox(
                                value: localUseCurrentLanguage,
                                activeColor:
                                    DB().colorSettings.pieceHighlightColor,
                                checkColor: Colors.white,
                                onChanged: (bool? value) {
                                  setState(() {
                                    localUseCurrentLanguage = value ?? true;
                                  });
                                },
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  // Using app language for output text
                                  S.of(context).outputInCurrentLanguage,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                              // Fish button for debugging the cat fishing mini-game
                              // Only shown in dev mode to help with testing
                              if (EnvironmentConfig.devMode)
                                IconButton(
                                  icon: const Icon(
                                    Icons.catching_pokemon, // Fish-like icon
                                    color: Colors.lightBlue,
                                  ),
                                  tooltip: 'Fish Game (Dev)',
                                  onPressed: () {
                                    // Show dialog with cat fishing game for testing
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (BuildContext context) {
                                        return Dialog(
                                          backgroundColor: Colors.transparent,
                                          child: Container(
                                            width: 500,
                                            height: 500,
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                      .dialogTheme
                                                      .backgroundColor ??
                                                  Theme.of(context)
                                                      .colorScheme
                                                      .surface,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            child: Column(
                                              children: <Widget>[
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.all(8.0),
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: <Widget>[
                                                      Text(
                                                        'Cat Fishing Game (Dev)',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: DB()
                                                              .colorSettings
                                                              .messageColor,
                                                        ),
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(
                                                            Icons.close),
                                                        onPressed: () =>
                                                            Navigator.of(
                                                                    context)
                                                                .pop(),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            8.0),
                                                    child: CatFishingGame(
                                                      onScoreUpdate:
                                                          (int score) {
                                                        // Optional: do something with score
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                            ],
                          ),

                        const SizedBox(height: 16),

                        // Bottom action buttons
                        if (!showLlmResponse)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              // Ask LLM button - left side
                              ElevatedButton(
                                onPressed: isLlmConfigured
                                    ? () => generateLlmResponse()
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      DB().colorSettings.pieceHighlightColor,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.grey,
                                ),
                                child: Text(S.of(context).askLlm),
                              ),
                              // Copy button - right side
                              ElevatedButton(
                                onPressed: () {
                                  final String promptWithLanguage =
                                      _getPromptWithLanguage(controller.text,
                                          localUseCurrentLanguage);
                                  _copyLLMPrompt(promptWithLanguage);
                                  // Set flag and cancel timer
                                  isDialogActive = false;
                                  loadingTimer?.cancel();
                                  Navigator.of(context).pop();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      DB().colorSettings.pieceHighlightColor,
                                  foregroundColor: Colors.white,
                                ),
                                child: Text(S.of(context).copy),
                              ),
                            ],
                          )
                        else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              // Import button - left side (disabled during loading)
                              ElevatedButton(
                                onPressed: isLoading
                                    ? null
                                    : () => importMovesFromResponse(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isLoading
                                      ? Colors.grey
                                      : DB().colorSettings.pieceHighlightColor,
                                  foregroundColor: Colors.white,
                                ),
                                child: Text(S.of(context).import),
                              ),
                              // Copy button - right side
                              ElevatedButton(
                                onPressed: isLoading
                                    ? null
                                    : () {
                                        _copyLLMPrompt(llmResponse);
                                        // Set flag and cancel timer
                                        isDialogActive = false;
                                        loadingTimer?.cancel();
                                        Navigator.of(context).pop();
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isLoading
                                      ? Colors.grey
                                      : DB().colorSettings.pieceHighlightColor,
                                  foregroundColor: Colors.white,
                                ),
                                child: Text(S.of(context).copy),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      // Ensure timer is cancelled when dialog is closed
      loadingTimer?.cancel();
    });

    // Make sure to dispose of the controller
    controller.dispose();
  }

  /// Widget for displaying the LLM prompt input text field
  Widget _buildPromptInputWidget(
    TextEditingController controller,
    Color textColor,
    Color borderColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(4),
        color: DB().colorSettings.darkBackgroundColor,
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: TextField(
          controller: controller,
          maxLines: null,
          expands: true,
          cursorColor: textColor,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            hintText: S.of(context).llmPromptContent,
            hintStyle: TextStyle(color: textColor.withValues(alpha: 0.5)),
          ),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            color: textColor,
          ),
        ),
      ),
    );
  }

  /// Widget for displaying the LLM response with progress indicator if loading
  Widget _buildLlmResponseWidget(
    String responseText,
    bool isLoading,
    int elapsedSeconds,
    Color textColor,
    Color borderColor,
  ) {
    // Determine message according to elapsed time
    String waitingMessage;
    if (elapsedSeconds < 20) {
      waitingMessage = S.of(context).llmCommandReceivedProcessing;
    } else if (elapsedSeconds < 60) {
      waitingMessage = S.of(context).llmDeepThinkingWait;
    } else {
      waitingMessage = S.of(context).llmPresentingSoon;
    }

    // Build a simple but fun loading animation consisting of 4 dots that move
    Widget funLoadingDots(Color highlightColor) {
      // Active dot cycles every second
      final int activeDot = elapsedSeconds % 4;
      return SizedBox(
        // Fixed height container to prevent layout jumps
        height: 12.0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List<Widget>.generate(4, (int index) {
            final bool isActive = index == activeDot;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              width: isActive ? 12 : 8,
              height: isActive ? 12 : 8,
              decoration: BoxDecoration(
                color: isActive
                    ? highlightColor
                    : highlightColor.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
            );
          }),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(4),
        color: DB().colorSettings.darkBackgroundColor,
      ),
      child: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Add padding at the top to move dots away from edge
                  const SizedBox(height: 24.0),
                  // Game title and waiting message
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      funLoadingDots(DB().colorSettings.pieceHighlightColor),
                      const SizedBox(
                          height: 8), // Vertical spacing between dots and text
                      Text(
                        waitingMessage,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                        ),
                        textAlign:
                            TextAlign.center, // Center the text horizontally
                      ),
                    ],
                  ),
                  // Digital clock-style display with LED-like effect
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        '${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          fontFamily: 'monospace',
                          foreground: Paint()
                            ..shader = LinearGradient(
                              colors: <Color>[
                                DB()
                                    .colorSettings
                                    .pieceHighlightColor
                                    .withValues(alpha: 0.7),
                                DB().colorSettings.pieceHighlightColor,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ).createShader(const Rect.fromLTWH(0, 0, 60, 24)),
                          shadows: <Shadow>[
                            Shadow(
                              color: DB()
                                  .colorSettings
                                  .pieceHighlightColor
                                  .withValues(alpha: 0.8),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Cat fishing mini-game
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: <Widget>[
                          const SizedBox(height: 4),
                          Expanded(
                            child: CatFishingGame(
                              onScoreUpdate: (int score) {
                                // Optional: do something with score
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(8.0),
              child: SelectableText(
                responseText,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  color: textColor,
                ),
              ),
            ),
    );
  }

  /// Get the current app language name in English
  String _getCurrentLanguageName() {
    // Get current locale from settings or system
    Locale currentLocale;

    // Try to get locale from app settings
    final Locale? configuredLocale = DB().displaySettings.locale;

    if (configuredLocale == null) {
      // If null, it means "system default" - try to get platform locale
      try {
        final String platformLocale = Platform.localeName;
        final List<String> parts = platformLocale.split('_');
        // e.g. "en_US" -> language: "en", country: "US"
        final String languageCode = parts[0];
        final String? countryCode = parts.length > 1 ? parts[1] : null;

        if (countryCode != null) {
          currentLocale = Locale(languageCode, countryCode);
        } else {
          currentLocale = Locale(languageCode);
        }
      } catch (e) {
        // Fallback to English if we can't get platform locale
        currentLocale = const Locale('en');
      }
    } else {
      // Use app's configured locale
      currentLocale = configuredLocale;
    }

    // Use the localeToLanguageName map to get the language name in its native form
    // This map is defined in language_locale_mapping.dart
    String? languageName;

    // Try exact match first (language + country code if available)
    if (localeToLanguageName.containsKey(currentLocale)) {
      languageName = localeToLanguageName[currentLocale];
    } else {
      // Try matching just the language code
      final Locale languageOnlyLocale = Locale(currentLocale.languageCode);
      if (localeToLanguageName.containsKey(languageOnlyLocale)) {
        languageName = localeToLanguageName[languageOnlyLocale];
      }
    }

    // If language name is found, use it, otherwise fall back to language code
    return languageName ?? currentLocale.languageCode;
  }

  /// Adds a language instruction to the prompt if needed
  String _getPromptWithLanguage(
      String originalPrompt, bool useCurrentLanguage) {
    if (!useCurrentLanguage) {
      return originalPrompt;
    }

    // Get language name or code
    final String languageNameOrCode = _getCurrentLanguageName();

    // Get the language code for LLM instruction
    final String languageCode = DB().displaySettings.locale?.languageCode ??
        Platform.localeName.split('_')[0];

    // Create a language instruction for the LLM
    // We include both the language name (possibly in native form) and the language code
    // This helps the LLM better understand which language to use
    final String languageInstruction =
        '\n\nPlease provide your analysis in $languageNameOrCode language (code: $languageCode).\n';

    // Find the prompt footer section if it exists, and insert before it
    // Otherwise, just append to the end
    if (originalPrompt.contains(PromptDefaults.llmPromptFooter)) {
      return originalPrompt.replaceFirst(PromptDefaults.llmPromptFooter,
          '$languageInstruction${PromptDefaults.llmPromptFooter}');
    } else {
      return '$originalPrompt$languageInstruction';
    }
  }

  /// Scrolls the list/grid to the top with an animation.
  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Scrolls the list/grid to the bottom with an animation.
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
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
  }

  /// Builds a single large icon with a label, used in the empty state.
  Widget _emptyStateIcon({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            size: 64,
            color: DB().colorSettings.messageColor,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: DB().colorSettings.messageColor),
          ),
        ],
      ),
    );
  }

  /// Builds a simple empty-state page with two large icons: Load game and Import game.
  Widget _buildEmptyState() {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _emptyStateIcon(
            icon: FluentIcons.folder_open_24_regular,
            label: S.of(context).loadGame,
            onTap: _loadGame,
          ),
          const SizedBox(width: 40),
          _emptyStateIcon(
            icon: FluentIcons.clipboard_paste_24_regular,
            label: S.of(context).importGame,
            onTap: _importGame,
          ),
        ],
      ),
    );
  }

  /// Builds the "3-column list layout": Round, White, Black.
  Widget _buildThreeColumnListLayout() {
    // 1. Group all moves by round.
    final Map<int, List<PgnNode<ExtMove>>> roundMap =
        <int, List<PgnNode<ExtMove>>>{};
    for (final PgnNode<ExtMove> node in _allNodes) {
      final ExtMove? data = node.data;
      if (data == null) {
        continue;
      }
      final int roundIndex = data.roundIndex ?? 0;
      roundMap.putIfAbsent(roundIndex, () => <PgnNode<ExtMove>>[]).add(node);
    }

    // Get sorted round indexes in ascending order.
    final List<int> sortedRoundsAsc = roundMap.keys.toList()..sort();
    // Use reversed order if _isReversedOrder is true.
    final List<int> sortedRounds =
        _isReversedOrder ? sortedRoundsAsc.reversed.toList() : sortedRoundsAsc;

    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        children: sortedRounds.map((int roundIndex) {
          final List<PgnNode<ExtMove>> nodesOfRound = roundMap[roundIndex]!;

          // 2. Separate moves into white vs black.
          final List<String> whites = <String>[];
          final List<String> blacks = <String>[];

          for (final PgnNode<ExtMove> n in nodesOfRound) {
            final PieceColor? side = n.data?.side;
            final String notation = n.data?.notation ?? '';
            if (side == PieceColor.white) {
              // Remove the "X." prefix, e.g. "5. e4" -> "e4"
              final String cleaned =
                  notation.replaceAll(RegExp(r'^\d+\.\s*'), '');
              whites.add(cleaned);
            } else if (side == PieceColor.black) {
              // Remove the "X..." prefix, e.g. "5... c5" -> "c5"
              final String cleaned =
                  notation.replaceAll(RegExp(r'^\d+\.\.\.\s*'), '');
              blacks.add(cleaned);
            }
          }

          final String whiteMoves = whites.join();
          final String blackMoves = blacks.join();

          return Card(
            color: DB().colorSettings.darkBackgroundColor,
            margin: const EdgeInsets.all(6.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 30,
                    child: Text(
                      "$roundIndex. ",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: DB().colorSettings.messageColor,
                        fontFamily: 'monospace', // Add monospace font
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      whiteMoves,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: DB().colorSettings.messageColor,
                        fontFamily: 'monospace', // Add monospace font
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      blackMoves,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: DB().colorSettings.messageColor,
                        fontFamily: 'monospace', // Add monospace font
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Builds the main body widget according to the chosen view layout.
  Widget _buildBody() {
    if (_allNodes.isEmpty) {
      return _buildEmptyState();
    }

    switch (_currentLayout) {
      case MovesViewLayout.large:
      case MovesViewLayout.medium:
      case MovesViewLayout.details:
        // Single-column ListView of MoveListItem with reversed index if needed.
        return ListView.builder(
          controller: _scrollController,
          itemCount: _allNodes.length,
          itemBuilder: (BuildContext context, int index) {
            final int idx =
                _isReversedOrder ? (_allNodes.length - 1 - index) : index;
            final PgnNode<ExtMove> node = _allNodes[idx];
            return MoveListItem(
              node: node,
              layout: _currentLayout,
            );
          },
        );

      case MovesViewLayout.small:
        // For small boards, display a grid with 3 or 5 columns.
        final bool isPortrait =
            MediaQuery.of(context).orientation == Orientation.portrait;
        final int crossAxisCount = isPortrait ? 3 : 5;

        return GridView.builder(
          controller: _scrollController,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.9,
          ),
          itemCount: _allNodes.length,
          itemBuilder: (BuildContext context, int index) {
            final int idx =
                _isReversedOrder ? (_allNodes.length - 1 - index) : index;
            return MoveListItem(
              node: _allNodes[idx],
              layout: _currentLayout,
            );
          },
        );

      case MovesViewLayout.list:
        // Now replaced with 3-column layout: Round / White / Black.
        return _buildThreeColumnListLayout();
    }
  }

  /// Maps each layout to its corresponding Fluent icon.
  IconData _iconForLayout(MovesViewLayout layout) {
    switch (layout) {
      case MovesViewLayout.large:
        return FluentIcons.square_24_regular;
      case MovesViewLayout.medium:
        return FluentIcons.apps_list_24_regular;
      case MovesViewLayout.small:
        return FluentIcons.grid_24_regular;
      case MovesViewLayout.list:
        return FluentIcons.text_column_two_24_regular;
      case MovesViewLayout.details:
        return FluentIcons.text_column_two_left_24_regular;
    }
  }

  /// Updates the current layout and saves it to settings
  void _updateLayout(MovesViewLayout newLayout) {
    if (newLayout == _currentLayout) {
      return;
    }

    setState(() {
      _currentLayout = newLayout;
    });

    // Save the setting to DB
    DB().displaySettings =
        DB().displaySettings.copyWith(movesViewLayout: newLayout);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appBarTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          S.of(context).moveList,
          style: AppTheme.appBarTheme.titleTextStyle,
        ),
        actions: <Widget>[
          // Reverse order icon.
          IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (Widget child, Animation<double> anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: _isReversedOrder
                  ? const Icon(
                      FluentIcons.arrow_sort_up_24_regular,
                      key: ValueKey<String>('descending'),
                    )
                  : const Icon(
                      FluentIcons.arrow_sort_down_24_regular,
                      key: ValueKey<String>('ascending'),
                    ),
            ),
            onPressed: () {
              setState(() {
                // Only toggle the flag; do not physically reverse _allNodes.
                _isReversedOrder = !_isReversedOrder;
              });
            },
          ),
          // Layout selection: one active icon in the AppBar.
          // Tapping it opens a popup with a horizontal row of icons.
          PopupMenuButton<void>(
            icon: Icon(_iconForLayout(_currentLayout)),
            onSelected: (_) {},
            itemBuilder: (BuildContext context) {
              return <PopupMenuEntry<void>>[
                PopupMenuItem<void>(
                  enabled: false,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children:
                        MovesViewLayout.values.map((MovesViewLayout layout) {
                      final bool isSelected = layout == _currentLayout;
                      return IconButton(
                        icon: Icon(
                          _iconForLayout(layout),
                          color: isSelected ? Colors.black : Colors.black87,
                        ),
                        onPressed: () {
                          _updateLayout(layout);
                          Navigator.pop(context);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ];
            },
          ),
          // The "three vertical dots" menu with multiple PopupMenuItem.
          PopupMenuButton<String>(
            onSelected: (String value) async {
              switch (value) {
                case 'top':
                  _scrollToTop();
                  break;
                case 'bottom':
                  _scrollToBottom();
                  break;
                case 'save_game':
                  _saveGame();
                  break;
                case 'load_game':
                  await _loadGame();
                  break;
                case 'import_game':
                  await _importGame();
                  break;
                case 'export_game':
                  _exportGame();
                  break;
                case 'copy_llm_prompt':
                  await _showLLMPromptDialog();
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'top',
                child: Row(
                  children: <Widget>[
                    const Icon(FluentIcons.arrow_upload_24_regular,
                        color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(S.of(context).top),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'bottom',
                child: Row(
                  children: <Widget>[
                    const Icon(FluentIcons.arrow_download_24_regular,
                        color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(S.of(context).bottom),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'save_game',
                child: Row(
                  children: <Widget>[
                    const Icon(FluentIcons.save_24_regular,
                        color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(S.of(context).saveGame),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'load_game',
                child: Row(
                  children: <Widget>[
                    const Icon(FluentIcons.folder_open_24_regular,
                        color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(S.of(context).loadGame),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'import_game',
                child: Row(
                  children: <Widget>[
                    const Icon(FluentIcons.clipboard_paste_24_regular,
                        color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(S.of(context).importGame),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'export_game',
                child: Row(
                  children: <Widget>[
                    const Icon(FluentIcons.copy_24_regular,
                        color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(S.of(context).exportGame),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'copy_llm_prompt',
                child: Row(
                  children: <Widget>[
                    const Icon(FluentIcons.text_grammar_wand_24_regular,
                        color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(S.of(context).llm),
                  ],
                ),
              ),
            ],
            icon: const Icon(FluentIcons.more_vertical_24_regular),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          // Hide any active mini board and dismiss keyboard.
          MiniBoardState.hideActiveBoard();
          FocusScope.of(context).unfocus();
        },
        child: _buildBody(),
      ),
    );
  }
}

/// A single item in the move list.
/// It adapts its layout depending on [layout].
class MoveListItem extends StatefulWidget {
  const MoveListItem({
    required this.node,
    required this.layout,
    super.key,
  });

  final PgnNode<ExtMove> node;
  final MovesViewLayout layout;

  @override
  MoveListItemState createState() => MoveListItemState();
}

class MoveListItemState extends State<MoveListItem> {
  /// Whether the comment is in editing mode.
  bool _isEditing = false;

  /// FocusNode to handle tap outside the TextField.
  late final FocusNode _focusNode;

  /// Controller for editing the comment text.
  late final TextEditingController _editingController;

  /// Cached comment text displayed in read-only mode.
  String _comment = "";

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
    _comment = _retrieveComment(widget.node);
    _editingController = TextEditingController(text: _comment);
  }

  /// Retrieves comment from node.data, joined if multiple.
  String _retrieveComment(PgnNode<ExtMove> node) {
    final ExtMove? data = node.data;
    if (data?.comments != null && data!.comments!.isNotEmpty) {
      return data.comments!.join(" ");
    } else if (data?.startingComments != null &&
        data!.startingComments!.isNotEmpty) {
      return data.startingComments!.join(" ");
    }
    return "";
  }

  /// Handle losing focus. If editing, finalize the edit.
  void _handleFocusChange() {
    if (!_focusNode.hasFocus && _isEditing) {
      _finalizeEditing();
    }
  }

  /// Saves the edited comment back into the PGN node.
  void _finalizeEditing() {
    setState(() {
      _isEditing = false;
      final String newComment = _editingController.text.trim();
      _comment = newComment;

      widget.node.data?.comments ??= <String>[];
      widget.node.data?.comments!.clear();
      if (newComment.isNotEmpty) {
        widget.node.data?.comments!.add(newComment);
      }
    });
  }

  /// Builds a reusable widget that either shows a comment or a TextField to edit it.
  Widget _buildEditableComment(TextStyle style) {
    final bool hasComment = _comment.isNotEmpty;
    if (_isEditing) {
      return TextField(
        focusNode: _focusNode,
        controller: _editingController,
        style: style,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
        ),
        onEditingComplete: () {
          _finalizeEditing();
          FocusScope.of(context).unfocus();
        },
      );
    } else {
      return GestureDetector(
        onTap: () {
          setState(() {
            _isEditing = true;
            _editingController.text = hasComment ? _comment : "";
          });
          _focusNode.requestFocus();
        },
        child: hasComment
            ? Text(
                _comment,
                style: style,
              )
            : Icon(
                FluentIcons.edit_16_regular,
                size: 16,
                color: style.color?.withAlpha(120),
              ),
      );
    }
  }

  /// Builds the appropriate widget based on [widget.layout].
  @override
  Widget build(BuildContext context) {
    final ExtMove? moveData = widget.node.data;
    final String notation = moveData?.notation ?? "";
    final String boardLayout = moveData?.boardLayout ?? "";
    // Determine side: used to decide how to show "roundIndex..."
    final bool isWhite = (moveData?.side == PieceColor.white);
    final int? roundIndex = moveData?.roundIndex;
    final String roundNotation = (roundIndex != null)
        ? (isWhite ? "$roundIndex. " : "$roundIndex... ")
        : "";

    // Common text style with monospace font for notation
    final TextStyle combinedStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: DB().colorSettings.messageColor,
      fontFamily: 'monospace', // Add monospace font
    );

    switch (widget.layout) {
      case MovesViewLayout.large:
        return _buildLargeLayout(
            notation, boardLayout, roundNotation, combinedStyle);
      case MovesViewLayout.medium:
        return _buildMediumLayout(
            notation, boardLayout, roundNotation, combinedStyle);
      case MovesViewLayout.small:
        return _buildSmallLayout(
            notation, boardLayout, roundNotation, combinedStyle);
      case MovesViewLayout.list:
        // The "list" layout is now handled in MovesListPageState._buildThreeColumnListLayout()
        // so we can return an empty container here.
        return const SizedBox.shrink();
      case MovesViewLayout.details:
        return _buildDetailsLayout(notation, roundNotation, combinedStyle);
    }
  }

  /// Large boards: single column, board on top, then "roundNotation + notation", then comment.
  Widget _buildLargeLayout(
    String notation,
    String boardLayout,
    String roundNotation,
    TextStyle combinedStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        color: DB().colorSettings.darkBackgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (boardLayout.isNotEmpty)
              AspectRatio(
                aspectRatio: 1.0,
                child: MiniBoard(
                  boardLayout: boardLayout,
                  extMove: widget.node.data,
                ),
              ),
            const SizedBox(height: 8),
            Text(roundNotation + notation, style: combinedStyle),
            const SizedBox(height: 6),
            _buildEditableComment(
              TextStyle(
                fontSize: 12,
                color: DB().colorSettings.messageColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Medium boards: board on the left, "roundNotation + notation" and comment on the right.
  Widget _buildMediumLayout(
    String notation,
    String boardLayout,
    String roundNotation,
    TextStyle combinedStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      child: Container(
        decoration: BoxDecoration(
          color: DB().colorSettings.darkBackgroundColor,
          borderRadius: BorderRadius.circular(4),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Colors.black26,
              blurRadius: 2,
              offset: Offset(2, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Left: mini board.
            Expanded(
              flex: 382,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: boardLayout.isNotEmpty
                    ? MiniBoard(
                        boardLayout: boardLayout,
                        extMove: widget.node.data,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            // Right: text.
            Expanded(
              flex: 618,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      roundNotation + notation,
                      style: combinedStyle,
                      softWrap: true,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    _buildEditableComment(
                      TextStyle(
                        fontSize: 12,
                        color: DB().colorSettings.messageColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Small boards: grid cells with board on top, then "roundNotation + notation".
  Widget _buildSmallLayout(
    String notation,
    String boardLayout,
    String roundNotation,
    TextStyle combinedStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.all(6.0),
      child: Container(
        color: DB().colorSettings.darkBackgroundColor,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (boardLayout.isNotEmpty)
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: MiniBoard(
                    boardLayout: boardLayout,
                    extMove: widget.node.data,
                  ),
                ),
              )
            else
              const Expanded(child: SizedBox.shrink()),
            const SizedBox(height: 4),
            Text(
              roundNotation + notation,
              style: combinedStyle.copyWith(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Details layout: single row: "roundNotation + notation" on the left, comment on the right.
  Widget _buildDetailsLayout(
    String notation,
    String roundNotation,
    TextStyle combinedStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        decoration: BoxDecoration(
          color: DB().colorSettings.darkBackgroundColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: <Widget>[
            // Left side.
            Expanded(
              child: Text(roundNotation + notation, style: combinedStyle),
            ),
            const SizedBox(width: 8),
            // Right side: editable comment.
            Expanded(
              child: _buildEditableComment(
                TextStyle(
                  fontSize: 12,
                  color: DB().colorSettings.messageColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant MoveListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If not editing, sync comment if the node changed.
    if (!_isEditing) {
      final String newComment = _retrieveComment(widget.node);
      if (newComment != _comment) {
        setState(() {
          _comment = newComment;
          _editingController.text = newComment;
        });
      }
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _editingController.dispose();
    super.dispose();
  }
}
