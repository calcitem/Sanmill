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
import '../../shared/utils/helpers/text_helpers/safe_text_editing_controller.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../services/import_export/pgn.dart';
import '../services/mill.dart';
import 'branch_tree_painter.dart';
import 'cat_fishing_game.dart';
import 'mini_board.dart';
import 'saved_games_page.dart';

// Key for the LLM prompt dialog screen
const String _kLlmPromptDialogKey = 'llm_prompt_dialog';
// Text for the S.of(context).askLlm button
// Text for when LLM is loading
const String _kLlmLoading = 'Loading response...';

/// ViewModel for a single row in the Active Path table
///
/// Each row represents either a White move, Black move, or both (a complete round).
/// Contains the main move node and its alternative variations (siblings).
class _ActivePathRowData {
  _ActivePathRowData({
    required this.node,
    required this.siblings,
    required this.roundIndex,
    required this.isWhite,
    required this.isActiveNode,
  });

  final PgnNode<ExtMove> node;
  final List<PgnNode<ExtMove>> siblings;
  final int roundIndex;
  final bool isWhite;
  final bool isActiveNode;
}

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

  /// Calculates the Active Path: nodes from root to activeNode and beyond (following children[0]).
  ///
  /// Returns a list of nodes representing the current "branch" being viewed,
  /// similar to git log showing commits on the current branch.
  List<PgnNode<ExtMove>> _calculateActivePathNodes() {
    final PgnNode<ExtMove> root = GameController().gameRecorder.pgnRoot;
    final PgnNode<ExtMove>? active = GameController().gameRecorder.activeNode;

    final List<PgnNode<ExtMove>> pathNodes = <PgnNode<ExtMove>>[];

    // Part 1: From root to activeNode (backward traversal, then reverse)
    if (active != null) {
      final List<PgnNode<ExtMove>> backwardPath = <PgnNode<ExtMove>>[];
      PgnNode<ExtMove>? current = active;
      while (current != null && current != root) {
        backwardPath.add(current);
        current = current.parent;
      }
      // Reverse to get root->...->active order
      pathNodes.addAll(backwardPath.reversed);
    }

    // Part 2: From activeNode (or root if active==null) forward along children[0]
    PgnNode<ExtMove> current = active ?? root;
    while (current.children.isNotEmpty) {
      current = current.children.first;
      // Only add if not already in path (avoid duplication at activeNode)
      if (active == null || current != active) {
        pathNodes.add(current);
      }
    }

    return pathNodes;
  }

  /// Calculates Active Path with variation (sibling) information for each node.
  ///
  /// Returns a list of row data containing:
  /// - The main node on the active path
  /// - Sibling nodes (alternative moves at the same position)
  /// - Round index
  /// - Side (White/Black)
  /// - Whether it's the current activeNode
  List<_ActivePathRowData> _calculateActivePathWithVariations() {
    final List<PgnNode<ExtMove>> activePathNodes = _calculateActivePathNodes();
    final PgnNode<ExtMove>? activeNode =
        GameController().gameRecorder.activeNode;

    final List<_ActivePathRowData> rows = <_ActivePathRowData>[];

    // Calculate roundIndex on-the-fly (similar to _refreshAllNodes logic)
    int currentRound = 1;
    PieceColor? lastNonRemoveSide;

    for (int i = 0; i < activePathNodes.length; i++) {
      final PgnNode<ExtMove> node = activePathNodes[i];
      final ExtMove? data = node.data;
      if (data == null) {
        continue;
      }

      // Update roundIndex based on side transitions
      if (data.type != MoveType.remove) {
        if (lastNonRemoveSide == PieceColor.black &&
            data.side == PieceColor.white) {
          currentRound++;
        }
        lastNonRemoveSide = data.side;
      }

      // Get siblings (alternative moves at this position)
      final PgnNode<ExtMove>? parent = node.parent;
      final List<PgnNode<ExtMove>> siblings = <PgnNode<ExtMove>>[];
      if (parent != null) {
        siblings.addAll(
          parent.children.where((PgnNode<ExtMove> child) => child != node),
        );
      }

      rows.add(
        _ActivePathRowData(
          node: node,
          siblings: siblings,
          roundIndex: currentRound,
          isWhite: data.side == PieceColor.white,
          isActiveNode: node == activeNode,
        ),
      );
    }

    return rows;
  }

  /// Clears and refreshes _allNodes from the game recorder.
  /// Now includes all variations with branch graph metadata.
  void _refreshAllNodes() {
    _allNodes.clear();

    final PgnNode<ExtMove> root = GameController().gameRecorder.pgnRoot;

    // Track which columns have active branches
    int nextColumnIndex = 0;

    // Collect all nodes including variations using DFS with branch tracking
    void collectNodesWithBranchInfo(
      PgnNode<ExtMove> parent, {
      int depth = 0,
      int parentColumn = 0,
      List<bool> parentActiveColumns = const <bool>[],
    }) {
      final int childCount = parent.children.length;

      for (int i = 0; i < childCount; i++) {
        final PgnNode<ExtMove> node = parent.children[i];
        final bool isVariation = i > 0;
        final bool isLastSibling = i == childCount - 1;

        // Determine column for this node
        int nodeColumn = parentColumn;
        if (isVariation) {
          // Variation gets a new column
          nodeColumn = nextColumnIndex++;
        }

        // Mark if this is a variation
        node.data?.isVariation = isVariation;
        node.data?.variationDepth = depth;
        node.data?.siblingIndex = i;
        node.data?.isLastSibling = isLastSibling;
        node.data?.branchColumn = nodeColumn;

        // Calculate active columns for this node
        final List<bool> currentActiveColumns = List<bool>.filled(
          nextColumnIndex,
          false,
        );

        // Copy parent's active columns
        for (int j = 0; j < parentActiveColumns.length; j++) {
          if (j < currentActiveColumns.length) {
            currentActiveColumns[j] = parentActiveColumns[j];
          }
        }

        // Mark current column as active
        if (nodeColumn < currentActiveColumns.length) {
          currentActiveColumns[nodeColumn] = true;
        }

        node.data?.branchColumns = List<bool>.from(currentActiveColumns);

        // Determine branch line type
        if (isVariation) {
          if (node.children.isEmpty) {
            node.data?.branchLineType = 'variation_end';
          } else {
            node.data?.branchLineType = 'variation_start';
          }
        } else {
          // Mainline or continuation
          if (parent.children.length > 1) {
            // Parent has variations, this is a fork point
            node.data?.branchLineType = 'fork_start';
          } else if (node.children.isEmpty) {
            node.data?.branchLineType = 'variation_end';
          } else if (node.children.length > 1) {
            node.data?.branchLineType = 'fork_start';
          } else {
            node.data?.branchLineType = isVariation
                ? 'variation_continue'
                : 'mainline';
          }
        }

        _allNodes.add(node);

        // Recursively collect children
        if (node.children.isNotEmpty) {
          // Update active columns for children
          final List<bool> childActiveColumns = List<bool>.from(
            currentActiveColumns,
          );
          if (node.children.length > 1) {
            // This node forks, keep its column active for variations
            if (nodeColumn < childActiveColumns.length) {
              childActiveColumns[nodeColumn] = true;
            }
          }

          collectNodesWithBranchInfo(
            node,
            depth: isVariation ? depth + 1 : depth,
            parentColumn: nodeColumn,
            parentActiveColumns: childActiveColumns,
          );
        }
      }
    }

    collectNodesWithBranchInfo(root);

    // Assign move indices and round indices
    int currentMoveIndex = 0;
    int currentRound = 1;
    PieceColor? lastNonRemoveSide;

    for (int i = 0; i < _allNodes.length; i++) {
      final PgnNode<ExtMove> node = _allNodes[i];

      // Set moveIndex
      if (i == 0) {
        node.data?.moveIndex = currentMoveIndex;
      } else if (node.data?.type == MoveType.remove) {
        node.data?.moveIndex = _allNodes[i - 1].data?.moveIndex;
      } else {
        currentMoveIndex = (_allNodes[i - 1].data?.moveIndex ?? 0) + 1;
        node.data?.moveIndex = currentMoveIndex;
      }

      // Calculate and assign roundIndex
      if (node.data != null) {
        if (node.data!.type == MoveType.remove) {
          node.data!.roundIndex = currentRound;
        } else {
          if (lastNonRemoveSide == PieceColor.black &&
              node.data!.side == PieceColor.white) {
            currentRound++;
          }
          node.data!.roundIndex = currentRound;
          lastNonRemoveSide = node.data!.side;
        }
      }
    }
  }

  /// Helper method to load a game, then refresh.
  Future<void> _loadGame() async {
    // Navigate to SavedGamesPage to pick a PGN with previews
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const SavedGamesPage(),
      ),
    );
    // After returning, refresh our list of nodes (game may have changed)
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(_refreshAllNodes);
    }
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
        SnackBar(content: Text(S.of(context).noLlmPromptAvailable)),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: promptText));

    if (!mounted) {
      return;
    }
    rootScaffoldMessengerKey.currentState!.showSnackBarClear(
      S.of(context).llmPromptCopiedToClipboard,
    );
  }

  /// Shows a dialog with LLM prompt content that can be edited and copied
  Future<void> _showLLMPromptDialog() async {
    // Get the initial prompt text
    final String initialPrompt = GameController().gameRecorder.moveListPrompt;

    if (initialPrompt.isEmpty) {
      rootScaffoldMessengerKey.currentState!.showSnackBar(
        SnackBar(content: Text(S.of(context).noLlmPromptAvailable)),
      );
      return;
    }

    // Create a controller for the text editing
    final TextEditingController controller = SafeTextEditingController(
      text: initialPrompt,
    );

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
        final Color bgColor =
            dialogThemeObj.backgroundColor ??
            Theme.of(context).colorScheme.surface;
        final Color textColor = DB().colorSettings.messageColor;
        final Color borderColor = DB().colorSettings.messageColor.withValues(
          alpha: 0.3,
        );

        // Local state for checkbox
        bool localUseCurrentLanguage = useCurrentLanguage;

        // LLM state variables
        bool isLoading = false;
        String llmResponse = '';
        bool showLlmResponse = false;
        final bool isLlmConfigured = LlmService()
            .isLlmConfigured(); // Check if LLM is configured

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
                  llmResponse = S
                      .of(context)
                      .llmNotConfiguredPleaseCheckYourSettings;
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
                loadingTimer = Timer.periodic(const Duration(seconds: 1), (
                  Timer t,
                ) {
                  // Update elapsed time every second while loading
                  if (!isDialogActive) {
                    // Cancel timer if dialog is closed
                    t.cancel();
                    return;
                  }
                  setState(() {
                    elapsedSeconds = DateTime.now()
                        .difference(requestStartTime!)
                        .inSeconds;
                  });
                });
              });

              final String promptToUse = _getPromptWithLanguage(
                controller.text,
                localUseCurrentLanguage,
              );

              // Call LLM service for real response
              final LlmService llmService = LlmService();
              String fullResponse = '';
              try {
                await for (final String chunk in llmService.generateResponse(
                  promptToUse,
                  context,
                )) {
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
              final String extractedMoves = LlmService().extractMoves(
                llmResponse,
              );

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
                    rootScaffoldMessengerKey.currentState?.showSnackBarClear(
                      S.of(context).gameImported,
                    );
                    GameController().headerTipNotifier.showTip(
                      S.of(context).gameImported,
                    );

                    // Wait briefly, then refresh the move list in the parent page
                    Future<void>.delayed(
                      const Duration(milliseconds: 500),
                    ).then((_) {
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
                                    FluentIcons.document_edit_24_regular,
                                  ),
                                  tooltip: S.of(context).llmPromptTemplate,
                                  color: DB().colorSettings.pieceHighlightColor,
                                ),
                                // LLM Config button
                                IconButton(
                                  onPressed: showLlmConfigDialog,
                                  icon: const Icon(
                                    FluentIcons.settings_24_regular,
                                  ),
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
                                              color:
                                                  Theme.of(context)
                                                      .dialogTheme
                                                      .backgroundColor ??
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.surface,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            child: Column(
                                              children: <Widget>[
                                                Padding(
                                                  padding: const EdgeInsets.all(
                                                    8.0,
                                                  ),
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
                                                          Icons.close,
                                                        ),
                                                        onPressed: () =>
                                                            Navigator.of(
                                                              context,
                                                            ).pop(),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          8.0,
                                                        ),
                                                    child: CatFishingGame(
                                                      onScoreUpdate: (int score) {
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
                                      _getPromptWithLanguage(
                                        controller.text,
                                        localUseCurrentLanguage,
                                      );
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
                        height: 8,
                      ), // Vertical spacing between dots and text
                      Text(
                        waitingMessage,
                        style: TextStyle(color: textColor, fontSize: 14),
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
                        horizontal: 10,
                        vertical: 6,
                      ),
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
                                DB().colorSettings.pieceHighlightColor
                                    .withValues(alpha: 0.7),
                                DB().colorSettings.pieceHighlightColor,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ).createShader(const Rect.fromLTWH(0, 0, 60, 24)),
                          shadows: <Shadow>[
                            Shadow(
                              color: DB().colorSettings.pieceHighlightColor
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
    final Locale currentLocale =
        DB().displaySettings.locale ?? _resolveSystemLocale();

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

  Locale _resolveSystemLocale() {
    try {
      final String rawLocale = Platform.localeName;
      final String sanitized = rawLocale.split('.').first.split('@').first;
      final List<String> subtags = sanitized.split(RegExp('[-_]'));

      if (subtags.isEmpty || subtags.first.isEmpty) {
        return const Locale('en');
      }

      final String primaryCode = subtags.first.toLowerCase() == 'und'
          ? 'en'
          : subtags.first.toLowerCase();
      String? scriptCode;
      String? regionCode;

      for (int i = 1; i < subtags.length; i++) {
        final String candidate = subtags[i].split('.').first;
        if (candidate.isEmpty) {
          continue;
        }

        if (scriptCode == null && _looksLikeScriptSubtag(candidate)) {
          scriptCode = _normalizeScriptCode(candidate);
          continue;
        }

        if (regionCode == null) {
          final String? normalizedRegion = _normalizeRegionCode(candidate);
          if (normalizedRegion != null) {
            regionCode = normalizedRegion;
          }
        }
      }

      if (scriptCode != null || regionCode != null) {
        return Locale.fromSubtags(
          languageCode: primaryCode,
          scriptCode: scriptCode,
          countryCode: regionCode,
        );
      }

      return Locale(primaryCode);
    } catch (e) {
      return const Locale('en');
    }
  }

  bool _looksLikeScriptSubtag(String value) {
    return RegExp(r'^[A-Za-z]{4}$').hasMatch(value);
  }

  String _normalizeScriptCode(String value) {
    final String lower = value.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  String? _normalizeRegionCode(String value) {
    final String cleaned = value.split('.').first;
    if (RegExp(r'^[A-Za-z]{2}$').hasMatch(cleaned)) {
      return cleaned.toUpperCase();
    }
    if (RegExp(r'^[0-9]{3}$').hasMatch(cleaned)) {
      return cleaned;
    }
    return null;
  }

  String _systemLanguageCode() {
    return _resolveSystemLocale().languageCode;
  }

  /// Adds a language instruction to the prompt if needed
  String _getPromptWithLanguage(
    String originalPrompt,
    bool useCurrentLanguage,
  ) {
    if (!useCurrentLanguage) {
      return originalPrompt;
    }

    // Get language name or code
    final String languageNameOrCode = _getCurrentLanguageName();

    // Get the language code for LLM instruction
    final String languageCode =
        DB().displaySettings.locale?.languageCode ?? _systemLanguageCode();

    // Create a language instruction for the LLM
    // We include both the language name (possibly in native form) and the language code
    // This helps the LLM better understand which language to use
    final String languageInstruction =
        '\n\nPlease provide your analysis in $languageNameOrCode language (code: $languageCode).\n';

    // Find the prompt footer section if it exists, and insert before it
    // Otherwise, just append to the end
    if (originalPrompt.contains(PromptDefaults.llmPromptFooter)) {
      return originalPrompt.replaceFirst(
        PromptDefaults.llmPromptFooter,
        '$languageInstruction${PromptDefaults.llmPromptFooter}',
      );
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
          Icon(icon, size: 64, color: DB().colorSettings.messageColor),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: DB().colorSettings.messageColor)),
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
  /// New implementation: shows Active Path with variation chips at branching points.
  Widget _buildThreeColumnListLayout() {
    final List<_ActivePathRowData> rows = _calculateActivePathWithVariations();

    // Group rows by round
    final Map<int, List<_ActivePathRowData>> roundMap =
        <int, List<_ActivePathRowData>>{};
    for (final _ActivePathRowData row in rows) {
      roundMap
          .putIfAbsent(row.roundIndex, () => <_ActivePathRowData>[])
          .add(row);
    }

    // Get sorted round indexes
    final List<int> sortedRoundsAsc = roundMap.keys.toList()..sort();
    final List<int> sortedRounds = _isReversedOrder
        ? sortedRoundsAsc.reversed.toList()
        : sortedRoundsAsc;

    return ListView.builder(
      controller: _scrollController,
      itemCount: sortedRounds.length,
      itemBuilder: (BuildContext context, int index) {
        final int roundIndex = sortedRounds[index];
        final List<_ActivePathRowData> roundRows = roundMap[roundIndex]!;

        // Separate white and black moves
        _ActivePathRowData? whiteRow;
        _ActivePathRowData? blackRow;

        for (final _ActivePathRowData row in roundRows) {
          if (row.isWhite) {
            whiteRow = row;
          } else {
            blackRow = row;
          }
        }

        // Determine if this row contains the activeNode
        final bool isActiveRow =
            (whiteRow?.isActiveNode ?? false) ||
            (blackRow?.isActiveNode ?? false);

        return _buildRoundRow(
          roundIndex: roundIndex,
          whiteRow: whiteRow,
          blackRow: blackRow,
          isActiveRow: isActiveRow,
        );
      },
    );
  }

  /// Builds a single round row with White and Black move cells
  Widget _buildRoundRow({
    required int roundIndex,
    required _ActivePathRowData? whiteRow,
    required _ActivePathRowData? blackRow,
    required bool isActiveRow,
  }) {
    // Use zebra striping for better readability
    final bool isEvenRow = roundIndex.isEven;
    final Color backgroundColor = isActiveRow
        ? DB().colorSettings.pieceHighlightColor.withValues(alpha: 0.3)
        : isEvenRow
        ? DB().colorSettings.darkBackgroundColor
        : DB().colorSettings.darkBackgroundColor.withValues(alpha: 0.7);

    return Container(
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Round number
          SizedBox(
            width: 35,
            child: Text(
              "$roundIndex.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DB().colorSettings.messageColor,
                fontFamily: 'monospace',
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // White move cell
          Expanded(
            child: whiteRow != null
                ? _buildMoveCell(whiteRow)
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
          // Black move cell
          Expanded(
            child: blackRow != null
                ? _buildMoveCell(blackRow)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// Builds a single move cell with main move and variation chips
  Widget _buildMoveCell(_ActivePathRowData rowData) {
    // Build main move text (could include multiple moves if followed by remove moves)
    final String mainMoveText = _buildMoveText(rowData.node);

    // Maximum number of chips to show before using "+K" overflow
    const int maxChipsToShow = 3;
    final bool hasOverflow = rowData.siblings.length > maxChipsToShow;
    final List<PgnNode<ExtMove>> visibleSiblings = hasOverflow
        ? rowData.siblings.sublist(0, maxChipsToShow)
        : rowData.siblings;

    return GestureDetector(
      onTap: () => _navigateToNode(rowData.node),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Main move text
            Text(
              mainMoveText,
              style: TextStyle(
                color: rowData.isActiveNode
                    ? DB().colorSettings.pieceHighlightColor
                    : DB().colorSettings.messageColor,
                fontFamily: 'monospace',
                fontSize: 14,
                fontWeight: rowData.isActiveNode
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            // Variation chips (if any siblings exist)
            if (rowData.siblings.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: <Widget>[
                  ...visibleSiblings.map((PgnNode<ExtMove> sibling) {
                    return _buildVariationChip(sibling);
                  }),
                  if (hasOverflow)
                    _buildOverflowChip(
                      count: rowData.siblings.length - maxChipsToShow,
                      allSiblings: rowData.siblings.sublist(maxChipsToShow),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Builds the move text, handling remove moves that follow the main move
  String _buildMoveText(PgnNode<ExtMove> node) {
    final List<String> moves = <String>[node.data!.notation];

    // Check for following remove moves in the same sequence
    PgnNode<ExtMove>? current = node;
    while (current!.children.isNotEmpty &&
        current.children.first.data?.type == MoveType.remove) {
      current = current.children.first;
      moves.add(current.data!.notation);

      // Stop after collecting remove moves
      if (current.children.isEmpty ||
          current.children.first.data?.type != MoveType.remove) {
        break;
      }
    }

    return moves.join(' ');
  }

  /// Builds a variation chip for an alternative move
  Widget _buildVariationChip(PgnNode<ExtMove> variationNode) {
    final String notation = variationNode.data?.notation ?? '';

    return GestureDetector(
      onTap: () => _navigateToNode(variationNode),
      onLongPress: () => _showVariationPreviewDialog(variationNode),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _showVariationHoverPreview(variationNode),
        onExit: (_) => _hideVariationHoverPreview(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: DB().colorSettings.messageColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: DB().colorSettings.messageColor.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            notation,
            style: TextStyle(
              color: DB().colorSettings.messageColor.withValues(alpha: 0.7),
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  /// Shows hover preview for desktop (currently placeholder - would need overlay implementation)
  void _showVariationHoverPreview(PgnNode<ExtMove> variationNode) {
    // TODO: Implement hover preview with overlay
    // This requires tracking mouse position and showing a positioned overlay
    // For now, we'll rely on the long-press dialog for both mobile and desktop
  }

  /// Hides hover preview for desktop
  void _hideVariationHoverPreview() {
    // TODO: Implement overlay hiding
  }

  /// Shows variation preview dialog (for mobile long-press and desktop interaction)
  void _showVariationPreviewDialog(PgnNode<ExtMove> variationNode) {
    final String? boardLayout = variationNode.data?.boardLayout;
    final String notation = variationNode.data?.notation ?? '';

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
            decoration: BoxDecoration(
              color: DB().colorSettings.darkBackgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: DB().colorSettings.pieceHighlightColor.withValues(
                  alpha: 0.5,
                ),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Header with notation
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DB().colorSettings.pieceHighlightColor.withValues(
                      alpha: 0.2,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(10),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        'Variation: $notation',
                        style: TextStyle(
                          color: DB().colorSettings.messageColor,
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          FluentIcons.dismiss_24_regular,
                          color: DB().colorSettings.messageColor,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // MiniBoard preview
                if (boardLayout != null && boardLayout.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: MiniBoard(
                        boardLayout: boardLayout,
                        extMove: variationNode.data,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No board preview available',
                      style: TextStyle(
                        color: DB().colorSettings.messageColor.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ),
                // Action buttons
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _navigateToNode(variationNode);
                        },
                        icon: const Icon(
                          FluentIcons.arrow_right_24_regular,
                          color: Colors.white,
                        ),
                        label: const Text('Jump to variation'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              DB().colorSettings.pieceHighlightColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _showVariationContextMenu(variationNode);
                        },
                        icon: const Icon(FluentIcons.more_vertical_24_regular),
                        label: const Text('More'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DB().colorSettings.messageColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Shows context menu for variation operations
  void _showVariationContextMenu(PgnNode<ExtMove> variationNode) {
    final String notation = variationNode.data?.notation ?? '';

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Variation: $notation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ListTile(
                leading: const Icon(FluentIcons.arrow_right_24_regular),
                title: const Text('Jump to this variation'),
                subtitle: const Text('Switch to this branch'),
                onTap: () {
                  Navigator.of(context).pop();
                  _navigateToNode(variationNode);
                },
              ),
              ListTile(
                leading: const Icon(FluentIcons.arrow_sort_up_24_regular),
                title: const Text('Set as main line'),
                subtitle: const Text('Make this the primary variation'),
                onTap: () {
                  Navigator.of(context).pop();
                  _promoteToMainLine(variationNode);
                },
              ),
              ListTile(
                leading: Icon(
                  FluentIcons.delete_24_regular,
                  color: Colors.red.shade700,
                ),
                title: Text(
                  'Delete branch',
                  style: TextStyle(color: Colors.red.shade700),
                ),
                subtitle: const Text('Remove this variation permanently'),
                onTap: () {
                  Navigator.of(context).pop();
                  _confirmDeleteBranch(variationNode);
                },
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.of(context).close),
            ),
          ],
        );
      },
    );
  }

  /// Promotes a variation to main line by moving it to children[0]
  void _promoteToMainLine(PgnNode<ExtMove> variationNode) {
    final PgnNode<ExtMove>? parent = variationNode.parent;
    if (parent == null) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Cannot promote: no parent node')),
      );
      return;
    }

    // Check if it's already the main line
    if (parent.children.isNotEmpty && parent.children.first == variationNode) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Already the main variation')),
      );
      return;
    }

    setState(() {
      // Remove from current position
      parent.children.remove(variationNode);
      // Insert at position 0 (main line)
      parent.children.insert(0, variationNode);

      // Checkout to this node
      GameController().gameRecorder.activeNode = variationNode;
    });

    rootScaffoldMessengerKey.currentState?.showSnackBarClear(
      'Set as main variation',
    );

    // Refresh the display
    _refreshAllNodes();
  }

  /// Shows confirmation dialog before deleting a branch
  void _confirmDeleteBranch(PgnNode<ExtMove> variationNode) {
    final String notation = variationNode.data?.notation ?? '';
    final PgnNode<ExtMove>? activeNode =
        GameController().gameRecorder.activeNode;

    // Check if this variation contains the active node
    final bool containsActiveNode = _isNodeOrDescendant(
      variationNode,
      activeNode,
    );

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Branch'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Are you sure you want to delete the variation "$notation" and all its continuations?',
              ),
              const SizedBox(height: 16),
              if (containsActiveNode)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade700),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        FluentIcons.warning_24_regular,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Warning: This branch contains your current position. You will be moved to the parent position.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.of(context).cancel),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteBranch(variationNode);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  /// Checks if targetNode is the same as or a descendant of node
  bool _isNodeOrDescendant(
    PgnNode<ExtMove> node,
    PgnNode<ExtMove>? targetNode,
  ) {
    if (targetNode == null) {
      return false;
    }

    PgnNode<ExtMove>? current = targetNode;
    while (current != null) {
      if (current == node) {
        return true;
      }
      current = current.parent;
    }

    return false;
  }

  /// Deletes a branch and adjusts activeNode if necessary
  void _deleteBranch(PgnNode<ExtMove> variationNode) {
    final PgnNode<ExtMove>? parent = variationNode.parent;
    if (parent == null) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Cannot delete: no parent node')),
      );
      return;
    }

    final PgnNode<ExtMove>? activeNode =
        GameController().gameRecorder.activeNode;
    final bool containsActiveNode = _isNodeOrDescendant(
      variationNode,
      activeNode,
    );

    setState(() {
      // If deleting a branch that contains activeNode, move activeNode to parent
      if (containsActiveNode) {
        GameController().gameRecorder.activeNode = parent;
      }

      // Remove the variation node from parent's children
      parent.children.remove(variationNode);
    });

    rootScaffoldMessengerKey.currentState?.showSnackBarClear('Branch deleted');

    // Refresh the display
    _refreshAllNodes();
  }

  /// Builds an overflow chip showing "+K" for hidden variations
  Widget _buildOverflowChip({
    required int count,
    required List<PgnNode<ExtMove>> allSiblings,
  }) {
    return InkWell(
      onTap: () => _showOverflowVariationsDialog(allSiblings),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: DB().colorSettings.pieceHighlightColor.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: DB().colorSettings.pieceHighlightColor.withValues(
              alpha: 0.5,
            ),
          ),
        ),
        child: Text(
          '+$count',
          style: TextStyle(
            color: DB().colorSettings.pieceHighlightColor,
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Shows a dialog with all overflow variations
  void _showOverflowVariationsDialog(List<PgnNode<ExtMove>> variations) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Variations'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: variations.map((PgnNode<ExtMove> node) {
                return ListTile(
                  title: Text(
                    node.data?.notation ?? '',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _navigateToNode(node);
                  },
                );
              }).toList(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.of(context).close),
            ),
          ],
        );
      },
    );
  }

  /// Navigate to a specific node
  Future<void> _navigateToNode(PgnNode<ExtMove> node) async {
    // Await navigation so activeNode is updated before rebuilding.
    await HistoryNavigator.gotoNode(context, node, pop: false);
    if (!mounted) {
      return;
    }
    setState(() {
      // Rebuild to reflect the new active path and highlights.
    });
  }

  /// Checks if the current active node is on a variation branch (not mainline)
  bool _isOnVariationBranch() {
    final PgnNode<ExtMove>? activeNode =
        GameController().gameRecorder.activeNode;
    if (activeNode == null) {
      return false;
    }

    // Traverse from activeNode back to root
    // If at any point the node is not children[0] of its parent, it's a variation
    PgnNode<ExtMove>? current = activeNode;
    while (current != null && current.parent != null) {
      final PgnNode<ExtMove> parent = current.parent!;
      // Check if current is the first child (main line)
      if (parent.children.isNotEmpty && parent.children.first != current) {
        return true; // Found a variation
      }
      current = parent;
    }

    return false; // On mainline
  }

  /// Builds a banner indicating the user is on a variation branch
  Widget _buildVariationBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: DB().colorSettings.pieceHighlightColor.withValues(alpha: 0.15),
        border: Border(
          bottom: BorderSide(
            color: DB().colorSettings.pieceHighlightColor.withValues(
              alpha: 0.3,
            ),
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            FluentIcons.branch_fork_24_regular,
            color: DB().colorSettings.pieceHighlightColor,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            'Currently on variation branch',
            style: TextStyle(
              color: DB().colorSettings.pieceHighlightColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _jumpToMainLine,
            style: TextButton.styleFrom(
              foregroundColor: DB().colorSettings.pieceHighlightColor,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Jump to main line',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Jumps to the main line from the current position
  void _jumpToMainLine() {
    final PgnNode<ExtMove>? activeNode =
        GameController().gameRecorder.activeNode;
    if (activeNode == null) {
      return;
    }

    // Find the nearest ancestor on the main line
    PgnNode<ExtMove>? current = activeNode;
    while (current != null && current.parent != null) {
      final PgnNode<ExtMove> parent = current.parent!;
      if (parent.children.isNotEmpty && parent.children.first == current) {
        // current is on mainline, stop here
        break;
      }
      // Move up to parent's mainline child
      if (parent.children.isNotEmpty) {
        current = parent.children.first;
        break;
      }
      current = parent;
    }

    if (current != null && current != activeNode) {
      _navigateToNode(current);
    }
  }

  /// Finds all branch points (nodes with multiple children) in the active path
  List<PgnNode<ExtMove>> _findBranchPoints() {
    final List<PgnNode<ExtMove>> activePathNodes = _calculateActivePathNodes();
    final List<PgnNode<ExtMove>> branchPoints = <PgnNode<ExtMove>>[];

    for (final PgnNode<ExtMove> node in activePathNodes) {
      if (node.parent != null && node.parent!.children.length > 1) {
        branchPoints.add(node);
      }
    }

    return branchPoints;
  }

  /// Jumps to the previous branch point
  void _jumpToPreviousBranchPoint() {
    final PgnNode<ExtMove>? activeNode =
        GameController().gameRecorder.activeNode;
    if (activeNode == null) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('No active position')),
      );
      return;
    }

    final List<PgnNode<ExtMove>> branchPoints = _findBranchPoints();
    if (branchPoints.isEmpty) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('No branch points found')),
      );
      return;
    }

    // Find the first branch point before activeNode
    PgnNode<ExtMove>? previousBranch;
    for (int i = branchPoints.length - 1; i >= 0; i--) {
      final PgnNode<ExtMove> branchNode = branchPoints[i];
      // Check if this branch is before activeNode
      if (_isNodeBefore(branchNode, activeNode)) {
        previousBranch = branchNode;
        break;
      }
    }

    if (previousBranch != null) {
      _navigateToNode(previousBranch);
      rootScaffoldMessengerKey.currentState?.showSnackBarClear(
        'Jumped to previous branch point',
      );
    } else {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('No previous branch point')),
      );
    }
  }

  /// Jumps to the next branch point
  void _jumpToNextBranchPoint() {
    final PgnNode<ExtMove>? activeNode =
        GameController().gameRecorder.activeNode;
    if (activeNode == null) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('No active position')),
      );
      return;
    }

    final List<PgnNode<ExtMove>> branchPoints = _findBranchPoints();
    if (branchPoints.isEmpty) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('No branch points found')),
      );
      return;
    }

    // Find the first branch point after activeNode
    PgnNode<ExtMove>? nextBranch;
    for (final PgnNode<ExtMove> branchNode in branchPoints) {
      // Check if this branch is after activeNode
      if (_isNodeBefore(activeNode, branchNode)) {
        nextBranch = branchNode;
        break;
      }
    }

    if (nextBranch != null) {
      _navigateToNode(nextBranch);
      rootScaffoldMessengerKey.currentState?.showSnackBarClear(
        'Jumped to next branch point',
      );
    } else {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('No next branch point')),
      );
    }
  }

  /// Checks if node1 comes before node2 in the active path
  bool _isNodeBefore(PgnNode<ExtMove> node1, PgnNode<ExtMove> node2) {
    final List<PgnNode<ExtMove>> activePathNodes = _calculateActivePathNodes();
    final int index1 = activePathNodes.indexOf(node1);
    final int index2 = activePathNodes.indexOf(node2);

    // If either node is not in the active path, use depth as fallback
    if (index1 == -1 || index2 == -1) {
      return _getNodeDepth(node1) < _getNodeDepth(node2);
    }

    return index1 < index2;
  }

  /// Gets the depth of a node from the root
  int _getNodeDepth(PgnNode<ExtMove> node) {
    int depth = 0;
    PgnNode<ExtMove>? current = node;
    while (current != null && current.parent != null) {
      depth++;
      current = current.parent;
    }
    return depth;
  }

  /// Builds the main body widget according to the chosen view layout.
  Widget _buildBody() {
    final bool hasMoves =
        GameController().gameRecorder.pgnRoot.children.isNotEmpty;
    if (!hasMoves) {
      return _buildEmptyState();
    }

    // Default: hide side branches for readability.
    // Advanced: show full tree when branch tree mode is enabled.
    final bool showFullTree = DB().displaySettings.showBranchTree;
    final List<PgnNode<ExtMove>> nodesToDisplay = showFullTree
        ? (_allNodes.isNotEmpty ? _allNodes : _calculateActivePathNodes())
        : _calculateActivePathNodes();

    switch (_currentLayout) {
      case MovesViewLayout.large:
      case MovesViewLayout.medium:
      case MovesViewLayout.details:
        // Single-column ListView of MoveListItem.
        return ListView.builder(
          controller: _scrollController,
          itemCount: nodesToDisplay.length,
          itemBuilder: (BuildContext context, int index) {
            final int idx = _isReversedOrder
                ? (nodesToDisplay.length - 1 - index)
                : index;
            final PgnNode<ExtMove> node = nodesToDisplay[idx];
            return MoveListItem(
              node: node,
              layout: _currentLayout,
              showNextMoveChips: !showFullTree,
              onNavigate: _navigateToNode,
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
          itemCount: nodesToDisplay.length,
          itemBuilder: (BuildContext context, int index) {
            final int idx = _isReversedOrder
                ? (nodesToDisplay.length - 1 - index)
                : index;
            return MoveListItem(
              node: nodesToDisplay[idx],
              layout: _currentLayout,
              onNavigate: _navigateToNode,
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
    DB().displaySettings = DB().displaySettings.copyWith(
      movesViewLayout: newLayout,
    );
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
          // Branch tree toggle icon
          IconButton(
            icon: Icon(
              DB().displaySettings.showBranchTree
                  ? FluentIcons.branch_fork_24_regular
                  : FluentIcons.branch_24_regular,
            ),
            tooltip: DB().displaySettings.showBranchTree
                ? 'Hide branch tree'
                : 'Show branch tree',
            onPressed: () {
              setState(() {
                DB().displaySettings = DB().displaySettings.copyWith(
                  showBranchTree: !DB().displaySettings.showBranchTree,
                );
                _refreshAllNodes();
              });
            },
          ),
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
                    children: MovesViewLayout.values.map((
                      MovesViewLayout layout,
                    ) {
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
                case 'prev_branch':
                  _jumpToPreviousBranchPoint();
                  break;
                case 'next_branch':
                  _jumpToNextBranchPoint();
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
                    const Icon(
                      FluentIcons.arrow_upload_24_regular,
                      color: Colors.black54,
                    ),
                    const SizedBox(width: 8),
                    Text(S.of(context).top),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'bottom',
                child: Row(
                  children: <Widget>[
                    const Icon(
                      FluentIcons.arrow_download_24_regular,
                      color: Colors.black54,
                    ),
                    const SizedBox(width: 8),
                    Text(S.of(context).bottom),
                  ],
                ),
              ),
              // Branch navigation (only show for list layout)
              if (_currentLayout ==
                  MovesViewLayout.list) ...<PopupMenuEntry<String>>[
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'prev_branch',
                  child: Row(
                    children: <Widget>[
                      Icon(
                        FluentIcons.branch_fork_24_regular,
                        color: Colors.black54,
                      ),
                      SizedBox(width: 8),
                      Text('Previous branch point'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'next_branch',
                  child: Row(
                    children: <Widget>[
                      Icon(
                        FluentIcons.branch_fork_24_regular,
                        color: Colors.black54,
                      ),
                      SizedBox(width: 8),
                      Text('Next branch point'),
                    ],
                  ),
                ),
              ],
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'save_game',
                child: Row(
                  children: <Widget>[
                    const Icon(
                      FluentIcons.save_24_regular,
                      color: Colors.black54,
                    ),
                    const SizedBox(width: 8),
                    Text(S.of(context).saveGame),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'load_game',
                child: Row(
                  children: <Widget>[
                    const Icon(
                      FluentIcons.folder_open_24_regular,
                      color: Colors.black54,
                    ),
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
                    const Icon(
                      FluentIcons.clipboard_paste_24_regular,
                      color: Colors.black54,
                    ),
                    const SizedBox(width: 8),
                    Text(S.of(context).importGame),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'export_game',
                child: Row(
                  children: <Widget>[
                    const Icon(
                      FluentIcons.copy_24_regular,
                      color: Colors.black54,
                    ),
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
                    const Icon(
                      FluentIcons.text_grammar_wand_24_regular,
                      color: Colors.black54,
                    ),
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
      body: Column(
        children: <Widget>[
          // Branch indicator banner (only for list view)
          if (!DB().displaySettings.showBranchTree && _isOnVariationBranch())
            _buildVariationBanner(),
          // Main content
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                // Hide any active mini board and dismiss keyboard.
                MiniBoardState.hideActiveBoard();
                FocusScope.of(context).unfocus();
              },
              child: _buildBody(),
            ),
          ),
        ],
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
    this.showNextMoveChips = false,
    this.onNavigate,
    super.key,
  });

  final PgnNode<ExtMove> node;
  final MovesViewLayout layout;

  /// Whether to show child-branch chips (next move options) under this move.
  /// This is used for the simplified active-path view.
  final bool showNextMoveChips;

  /// Navigation callback provided by the parent page.
  /// When set, it should also refresh the move list after navigation.
  final Future<void> Function(PgnNode<ExtMove> node)? onNavigate;

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
    _editingController = SafeTextEditingController(text: _comment);
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
            ? Text(_comment, style: style)
            : Icon(
                FluentIcons.edit_16_regular,
                size: 16,
                color: style.color?.withAlpha(120),
              ),
      );
    }
  }

  /// Computes the round index for a node based on its parent chain.
  ///
  /// This avoids incorrect numbering caused by traversing a full variation tree
  /// in an arbitrary order (e.g., DFS order).
  int _computeRoundIndexForNode(PgnNode<ExtMove> node) {
    final PgnNode<ExtMove> root = GameController().gameRecorder.pgnRoot;

    // Build path root->...->node (excluding the root which has no move data).
    final List<PgnNode<ExtMove>> path = <PgnNode<ExtMove>>[];
    PgnNode<ExtMove>? current = node;
    while (current != null && current != root) {
      path.insert(0, current);
      current = current.parent;
    }

    int round = 1;
    PieceColor? lastNonRemoveSide;
    for (final PgnNode<ExtMove> n in path) {
      final ExtMove? data = n.data;
      if (data == null) {
        continue;
      }
      if (data.type != MoveType.remove) {
        if (lastNonRemoveSide == PieceColor.black &&
            data.side == PieceColor.white) {
          round++;
        }
        lastNonRemoveSide = data.side;
      }
    }

    return round;
  }

  /// Builds the appropriate widget based on [widget.layout].
  @override
  Widget build(BuildContext context) {
    final ExtMove? moveData = widget.node.data;
    if (moveData == null) {
      return const SizedBox.shrink();
    }

    final String notation = moveData.notation;
    final String boardLayout = moveData.boardLayout ?? "";
    // Determine side: used to decide how to show "roundIndex..."
    final bool isWhite = (moveData.side == PieceColor.white);
    final int roundIndex = _computeRoundIndexForNode(widget.node);
    final String roundNotation = isWhite ? "$roundIndex. " : "$roundIndex... ";

    // Check if this move is a variation
    final bool isVariation = moveData.isVariation ?? false;
    final int variationDepth = moveData.variationDepth ?? 0;

    // Get branch graph metadata
    final List<bool> branchColumns = moveData.branchColumns ?? <bool>[];
    final int branchColumn = moveData.branchColumn ?? 0;
    final String branchLineType = moveData.branchLineType ?? 'mainline';
    final bool isLastSibling = moveData.isLastSibling ?? false;
    final int siblingIndex = moveData.siblingIndex ?? 0;

    // Common text style with monospace font for notation
    final TextStyle combinedStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: isVariation
          ? DB().colorSettings.pieceHighlightColor.withValues(alpha: 0.8)
          : DB().colorSettings.messageColor,
      fontFamily: 'monospace', // Add monospace font
    );

    // Build branch tree widget (only if enabled)
    final Widget branchTree =
        DB().displaySettings.showBranchTree && branchColumns.isNotEmpty
        ? BranchTreeWidget(
            branchColumns: branchColumns,
            branchColumn: branchColumn,
            branchLineType: branchLineType,
            isLastSibling: isLastSibling,
            siblingIndex: siblingIndex,
            color: isVariation
                ? DB().colorSettings.pieceHighlightColor.withValues(alpha: 0.7)
                : DB().colorSettings.messageColor.withValues(alpha: 0.5),
          )
        : const SizedBox.shrink();

    // Wrap the widget with branch tree visualization
    Widget content;
    switch (widget.layout) {
      case MovesViewLayout.large:
        content = _buildLargeLayoutWithBranch(
          notation,
          boardLayout,
          roundNotation,
          combinedStyle,
          branchTree,
        );
        break;
      case MovesViewLayout.medium:
        content = _buildMediumLayoutWithBranch(
          notation,
          boardLayout,
          roundNotation,
          combinedStyle,
          branchTree,
        );
        break;
      case MovesViewLayout.small:
        content = _buildSmallLayout(
          notation,
          boardLayout,
          roundNotation,
          combinedStyle,
        );
        break;
      case MovesViewLayout.list:
        // The "list" layout is now handled in MovesListPageState._buildThreeColumnListLayout()
        // so we can return an empty container here.
        return const SizedBox.shrink();
      case MovesViewLayout.details:
        content = _buildDetailsLayoutWithBranch(
          notation,
          roundNotation,
          combinedStyle,
          branchTree,
        );
        break;
    }

    // If branch tree is disabled, add simple indentation for variations
    if (!DB().displaySettings.showBranchTree &&
        isVariation &&
        widget.layout != MovesViewLayout.list) {
      return Padding(
        padding: EdgeInsets.only(left: 16.0 * variationDepth),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: DB().colorSettings.pieceHighlightColor.withValues(
                  alpha: 0.6,
                ),
                width: 3,
              ),
            ),
          ),
          child: content,
        ),
      );
    }

    return content;
  }

  /// Large boards: single column, board on top, then "roundNotation + notation", then comment.
  Widget _buildLargeLayoutWithBranch(
    String notation,
    String boardLayout,
    String roundNotation,
    TextStyle combinedStyle,
    Widget branchTree,
  ) {
    return GestureDetector(
      onTap: () => _navigateToNode(),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Container(
          color: _isActiveNode()
              ? DB().colorSettings.pieceHighlightColor.withValues(alpha: 0.3)
              : DB().colorSettings.darkBackgroundColor,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Branch tree on the left
              branchTree,
              const SizedBox(width: 8),
              // Main content
              Expanded(
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
                    _buildNextMoveChips(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Check if this node is the currently active node
  bool _isActiveNode() {
    return GameController().gameRecorder.activeNode == widget.node;
  }

  /// Navigate to a node.
  ///
  /// If the parent provides [MoveListItem.onNavigate], use it so the move list
  /// can refresh after navigation.
  Future<void> _navigateToNode([PgnNode<ExtMove>? target]) async {
    final PgnNode<ExtMove> node = target ?? widget.node;
    if (widget.onNavigate != null) {
      await widget.onNavigate!(node);
      return;
    }
    await HistoryNavigator.gotoNode(context, node, pop: false);
  }

  bool _isNodeOrDescendantOfActive(PgnNode<ExtMove> node) {
    final PgnNode<ExtMove>? activeNode =
        GameController().gameRecorder.activeNode;
    if (activeNode == null) {
      return false;
    }
    PgnNode<ExtMove>? cur = activeNode;
    while (cur != null) {
      if (cur == node) {
        return true;
      }
      cur = cur.parent;
    }
    return false;
  }

  Widget _buildChildBranchChip(PgnNode<ExtMove> child) {
    final String label = child.data?.notation ?? '';
    final bool isSelected = _isNodeOrDescendantOfActive(child);

    return InkWell(
      onTap: () => _navigateToNode(child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? DB().colorSettings.pieceHighlightColor.withValues(alpha: 0.25)
              : DB().colorSettings.messageColor.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? DB().colorSettings.pieceHighlightColor.withValues(alpha: 0.6)
                : DB().colorSettings.messageColor.withValues(alpha: 0.25),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? DB().colorSettings.pieceHighlightColor
                : DB().colorSettings.messageColor.withValues(alpha: 0.85),
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  void _showChildBranchPickerDialog(List<PgnNode<ExtMove>> children) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Branch moves'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: children.map((PgnNode<ExtMove> child) {
                return ListTile(
                  title: Text(
                    child.data?.notation ?? '',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _navigateToNode(child);
                  },
                );
              }).toList(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.of(context).close),
            ),
          ],
        );
      },
    );
  }

  /// Builds next-move branch chips for this node.
  ///
  /// The chips represent the immediate children of the current node (i.e., the
  /// next move options). This matches how chess GUIs display branching at the
  /// parent move (e.g., show the alternatives under "1... d6").
  Widget _buildNextMoveChips() {
    if (!widget.showNextMoveChips) {
      return const SizedBox.shrink();
    }

    final List<PgnNode<ExtMove>> children = widget.node.children
        .where((PgnNode<ExtMove> c) => c.data != null)
        .toList();
    if (children.length <= 1) {
      return const SizedBox.shrink();
    }

    const int maxChipsToShow = 4;
    final List<PgnNode<ExtMove>> visible = children
        .take(maxChipsToShow)
        .toList();
    final int overflowCount = children.length - visible.length;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          ...visible.map(_buildChildBranchChip),
          if (overflowCount > 0)
            InkWell(
              onTap: () => _showChildBranchPickerDialog(children),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: DB().colorSettings.pieceHighlightColor.withValues(
                    alpha: 0.18,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: DB().colorSettings.pieceHighlightColor.withValues(
                      alpha: 0.45,
                    ),
                  ),
                ),
                child: Text(
                  '+$overflowCount',
                  style: TextStyle(
                    color: DB().colorSettings.pieceHighlightColor,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Medium boards: board on the left, "roundNotation + notation" and comment on the right.
  /// Medium boards: board on the left, "roundNotation + notation" and comment on the right.
  Widget _buildMediumLayoutWithBranch(
    String notation,
    String boardLayout,
    String roundNotation,
    TextStyle combinedStyle,
    Widget branchTree,
  ) {
    return GestureDetector(
      onTap: () => _navigateToNode(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
        child: Container(
          decoration: BoxDecoration(
            color: _isActiveNode()
                ? DB().colorSettings.pieceHighlightColor.withValues(alpha: 0.3)
                : DB().colorSettings.darkBackgroundColor,
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
              // Branch tree on the left
              branchTree,
              const SizedBox(width: 4),
              // Mini board
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
              // Text content
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
                      _buildNextMoveChips(),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
    return GestureDetector(
      onTap: () => _navigateToNode(),
      child: Padding(
        padding: const EdgeInsets.all(6.0),
        child: Container(
          color: _isActiveNode()
              ? DB().colorSettings.pieceHighlightColor.withValues(alpha: 0.3)
              : DB().colorSettings.darkBackgroundColor,
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
      ),
    );
  }

  /// Details layout: single row: "roundNotation + notation" on the left, comment on the right.
  Widget _buildDetailsLayoutWithBranch(
    String notation,
    String roundNotation,
    TextStyle combinedStyle,
    Widget branchTree,
  ) {
    return GestureDetector(
      onTap: () => _navigateToNode(),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Container(
          decoration: BoxDecoration(
            color: _isActiveNode()
                ? DB().colorSettings.pieceHighlightColor.withValues(alpha: 0.3)
                : DB().colorSettings.darkBackgroundColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: <Widget>[
              // Branch tree on the left
              branchTree,
              const SizedBox(width: 8),
              // Move notation
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(roundNotation + notation, style: combinedStyle),
                    _buildNextMoveChips(),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Comment
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
