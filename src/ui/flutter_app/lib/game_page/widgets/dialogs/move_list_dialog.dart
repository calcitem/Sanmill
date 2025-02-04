// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// move_list_dialog.dart

part of '../game_page.dart';

/// Represents a "temporary move" with move text, a list of NAGs, and annotations.
class TempMove {
  String moveText = "";
  final List<String> nags = <String>[]; // NAG tokens (e.g., !, ?, !?, ?!)
  final List<String> comments = <String>[]; // Comments (from { ... })
  bool hasX = false;
}

class MoveListDialog extends StatelessWidget {
  const MoveListDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final GameController controller = GameController();
    String? fen;
    List<String> mergedMoves = getMergedMoves(controller);
    if (mergedMoves.isNotEmpty) {
      // If the first token is a PGN/FEN tag block, separate it out.
      if (mergedMoves[0].isNotEmpty) {
        final String firstMove = mergedMoves[0];
        if (firstMove.startsWith('[')) {
          fen = firstMove;
          mergedMoves = mergedMoves.sublist(1);
        }
      }
    }
    final int movesCount = (mergedMoves.length + 1) ~/ 2;
    final int fenHeight = fen == null ? 2 : 14;
    // Determine if any move contains a comment block.
    final bool globalHasComment =
        mergedMoves.any((String move) => move.contains('{'));

    if (DB().generalSettings.screenReaderSupport) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (rootScaffoldMessengerKey.currentState != null) {
          rootScaffoldMessengerKey.currentState!.clearSnackBars();
        }
      });
    }

    // ValueNotifier to track the selected index in the move list.
    final ValueNotifier<int?> selectedIndex = ValueNotifier<int?>(null);

    return GamePageActionSheet(
      child: AlertDialog(
        key: const Key('move_list_dialog_alert_dialog'),
        backgroundColor: UIColors.semiTransparentBlack,
        title: Text(
          S.of(context).moveList,
          key: const Key('move_list_dialog_title_text'),
          style: _getTitleTextStyle(context),
        ),
        content: SizedBox(
          key: const Key('move_list_dialog_content_sized_box'),
          width: calculateNCharWidth(context, 32),
          height:
              calculateNCharWidth(context, mergedMoves.length * 2 + fenHeight),
          child: ListView(
            key: const Key('move_list_dialog_list_view'),
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              if (fen != null)
                InkWell(
                  key: const Key('move_list_dialog_fen_inkwell'),
                  onTap: () => _importGame(context, mergedMoves, fen, -1),
                  child: Padding(
                    key: const Key('move_list_dialog_fen_padding'),
                    padding: const EdgeInsets.only(right: 24.0),
                    child: Text.rich(
                      TextSpan(
                        text: "$fen\r\n",
                        style: _getTitleTextStyle(context),
                      ),
                      key: const Key('move_list_dialog_fen_text'),
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                ),
              ...List<Widget>.generate(
                movesCount,
                (int index) => _buildMoveListItem(
                  context,
                  mergedMoves,
                  fen,
                  index,
                  selectedIndex,
                  globalHasComment,
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          Row(
            key: const Key('move_list_dialog_actions_row'),
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Expanded(
                child: TextButton(
                  key: const Key('move_list_dialog_copy_button'),
                  child: Text(
                    S.of(context).copy,
                    style: _getButtonTextStyle(context),
                  ),
                  onPressed: () {
                    GameController.export(context);
                    if (DB().displaySettings.isHistoryNavigationToolbarShown) {
                      Navigator.pop(context);
                    }
                  },
                ),
              ),
              Expanded(
                child: TextButton(
                  key: const Key('move_list_dialog_paste_button'),
                  child: Text(
                    S.of(context).paste,
                    style: _getButtonTextStyle(context),
                  ),
                  onPressed: () {
                    GameController.import(context);
                    if (DB().displaySettings.isHistoryNavigationToolbarShown) {
                      Navigator.pop(context);
                    }
                  },
                ),
              ),
              Expanded(
                child: TextButton(
                  key: const Key('move_list_dialog_cancel_button'),
                  child: Text(
                    S.of(context).cancel,
                    style: _getButtonTextStyle(context),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    if (DB().displaySettings.isHistoryNavigationToolbarShown) {
                      Navigator.pop(context);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Returns a text style for move text.
  /// If any move contains a comment block, the overall font size is reduced.
  TextStyle _getMoveTextStyle(BuildContext context, bool hasComment) {
    final TextStyle baseStyle = _getTitleTextStyle(context);
    if (hasComment) {
      return baseStyle.copyWith(fontSize: baseStyle.fontSize! * 0.8);
    }
    return baseStyle;
  }

  Widget _buildMoveListItem(
    BuildContext context,
    List<String> mergedMoves,
    String? fen,
    int index,
    ValueNotifier<int?> selectedIndex,
    bool globalHasComment,
  ) {
    // White and black indices
    final int whiteIndex = index * 2;
    final int blackIndex = whiteIndex + 1;

    // If we run out of tokens for the white move, skip the entire row.
    if (whiteIndex >= mergedMoves.length) {
      return const SizedBox.shrink();
    }

    final String whiteMove = mergedMoves[whiteIndex];
    // blackMove might be missing when the total moves are odd
    final String? blackMove =
        (blackIndex < mergedMoves.length) ? mergedMoves[blackIndex] : null;

    // If both whiteMove and blackMove are empty (unlikely unless input is weird), skip the row
    if (whiteMove.isEmpty && (blackMove?.isEmpty ?? true)) {
      return const SizedBox.shrink();
    }

    // If the token is '(' or ')', we set it in italic font.
    final bool isParenWhite = whiteMove == '(' || whiteMove == ')';
    final bool isParenBlack = blackMove == '(' || blackMove == ')';

    // Return a tile with up to 3 columns:
    // 1) Leading = row number (e.g. "1.")
    // 2) White move
    // 3) Black move (optional)
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Text(
        '${index + 1}.',
        style: _getTitleTextStyle(context),
      ),
      title: Row(
        children: <Widget>[
          // White move
          Expanded(
            child: ValueListenableBuilder<int?>(
              valueListenable: selectedIndex,
              builder: (BuildContext context, int? value, Widget? child) {
                final bool isSelected = (value == whiteIndex);
                return InkWell(
                  onTap: () {
                    selectedIndex.value = whiteIndex;
                    _importGame(context, mergedMoves, fen, whiteIndex);
                  },
                  child: Container(
                    color: isSelected
                        ? AppTheme.gamePageActionSheetTextBackgroundColor
                        : null,
                    padding: const EdgeInsets.only(right: 24.0),
                    child: Text(
                      whiteMove,
                      style:
                          _getMoveTextStyle(context, globalHasComment).copyWith(
                        color: AppTheme.gamePageActionSheetTextColor,
                        fontStyle:
                            isParenWhite ? FontStyle.italic : FontStyle.normal,
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                );
              },
            ),
          ),

          // Black move (only render if exists)
          if (blackMove != null)
            Expanded(
              child: ValueListenableBuilder<int?>(
                valueListenable: selectedIndex,
                builder: (BuildContext context, int? value, Widget? child) {
                  final bool isSelected = (value == blackIndex);
                  return InkWell(
                    onTap: () {
                      selectedIndex.value = blackIndex;
                      _importGame(context, mergedMoves, fen, blackIndex);
                    },
                    child: Container(
                      color: isSelected
                          ? AppTheme.gamePageActionSheetTextBackgroundColor
                          : null,
                      padding: const EdgeInsets.only(right: 24.0),
                      child: Text(
                        blackMove,
                        style: _getMoveTextStyle(context, globalHasComment)
                            .copyWith(
                          color: AppTheme.gamePageActionSheetTextColor,
                          fontStyle: isParenBlack
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _importGame(BuildContext context, List<String> mergedMoves,
      String? fen, int clickedIndex) async {
    String ml = mergedMoves.sublist(0, clickedIndex + 1).join(' ');
    if (fen != null) {
      ml = '$fen $ml';
    }
    final SnackBar snackBar = SnackBar(
      key: const Key('move_list_dialog_import_snack_bar'),
      content: Text(ml),
      duration: const Duration(seconds: 2),
    );
    if (!ScaffoldMessenger.of(context).mounted) {
      return;
    }
    if (EnvironmentConfig.devMode) {
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }
    try {
      ImportService.import(ml);
    } catch (exception) {
      if (!context.mounted) {
        return;
      }
      final String tip = S.of(context).cannotImport(ml);
      GameController().headerTipNotifier.showTip(tip);
      Navigator.pop(context);
      return;
    }
    if (!context.mounted) {
      return;
    }
    await HistoryNavigator.takeBackAll(context, pop: false);
    if (!context.mounted) {
      return;
    }
    if (await HistoryNavigator.stepForwardAll(context, pop: false) ==
        const HistoryOK()) {
      if (!context.mounted) {
        return;
      }
    } else {
      if (!context.mounted) {
        return;
      }
      final String tip =
          S.of(context).cannotImport(HistoryNavigator.importFailedStr);
      GameController().headerTipNotifier.showTip(tip);
      HistoryNavigator.importFailedStr = "";
    }
  }

  TextStyle _getTitleTextStyle(BuildContext context) {
    return Theme.of(context).textTheme.titleLarge!.copyWith(
          color: AppTheme.gamePageActionSheetTextColor,
          fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
          fontFamily: getMonospaceTitleTextStyle(context).fontFamily,
        );
  }

  TextStyle _getButtonTextStyle(BuildContext context) {
    return Theme.of(context).textTheme.titleMedium!.copyWith(
          color: AppTheme.gamePageActionSheetTextColor,
          fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
        );
  }
}

/// Tokenize the move history string, treating annotation blocks `{...}` as single tokens.
/// Filter out:
///   1) Empty/whitespace-only tokens
///   2) Tokens that match "digits + '.' + optional whitespace"
List<String> lexTokens(String moveHistoryText) {
  final List<String> tokens = <String>[];
  int i = 0;

  while (i < moveHistoryText.length) {
    final String c = moveHistoryText[i];

    // (A) If we encounter '{', collect until the matching '}' as one annotation token.
    if (c == '{') {
      final int start = i;
      i++;
      int braceLevel = 1;
      while (i < moveHistoryText.length && braceLevel > 0) {
        if (moveHistoryText[i] == '{') {
          braceLevel++;
        } else if (moveHistoryText[i] == '}') {
          braceLevel--;
        }
        i++;
      }
      final String block = moveHistoryText.substring(start, i).trim();
      if (block.isNotEmpty) {
        tokens.add(block);
      }
      continue;
    }

    // (B) Skip whitespace characters directly.
    if (RegExp(r'\s').hasMatch(c)) {
      i++;
      continue;
    }

    // If we encounter '(' or ')', treat them as single tokens,
    // so that we can later handle variations.
    if (c == '(' || c == ')') {
      tokens.add(c);
      i++;
      continue;
    }

    // (C) Otherwise, collect a normal token until whitespace or '{'.
    final int start = i;
    while (i < moveHistoryText.length) {
      final String cc = moveHistoryText[i];
      // Stop if we hit '{', '(', ')' or any whitespace.
      if (cc == '{' || cc == '(' || cc == ')' || RegExp(r'\s').hasMatch(cc)) {
        break;
      }
      i++;
    }

    // Extract and trim the token.
    final String rawToken = moveHistoryText.substring(start, i);
    final String trimmed = rawToken.trim();

    // 1) Skip if the token is empty or whitespace-only.
    if (trimmed.isEmpty) {
      continue;
    }
    // 2) Skip if the token matches "digits + '.' + optional whitespace".
    //    Example matches: "1.", "12.", "3.   "
    if (RegExp(r'^\d+\.\s*$').hasMatch(trimmed)) {
      continue;
    }

    // If it doesn't match any skip rules, add it to our tokens list.
    tokens.add(trimmed);
  }

  return tokens;
}

/// Remove all braces inside the text to avoid nested braces issues.
String stripBraces(String text) {
  return text.replaceAll('{', '').replaceAll('}', '');
}

/// Strip outer braces from an annotation block like "{...}".
String stripOuterBraces(String block) {
  if (block.startsWith('{') && block.endsWith('}') && block.length >= 2) {
    return block.substring(1, block.length - 1);
  }
  return block;
}

/// 2) Merge tokens:
///   - Combine multiple "x" captures into one move (e.g. "d6-d5" + "xd7" => "d6-d5xd7").
///   - If a new capture token appears, discard previous annotations.
///   - Handle NAG tokens (like !, ?, !?, ?!, !!, ??) with **no space** before them,
///     so the final move looks like "d4!" or "d4!?" etc.
///   - Only one space precedes the "{...}" comment block if there are comments.
List<String> mergeMoves(List<String> tokens) {
  final List<String> results = <String>[];

  TempMove? current;

  // Flush current move to results.
  void finalizeCurrent() {
    if (current != null && current!.moveText.isNotEmpty) {
      // Construct final string: moveText + (NAGs attached) + optional " {comments...}"
      final StringBuffer sb = StringBuffer(current!.moveText);

      // If we have NAGs, append them directly with no space before them.
      // e.g., if nags = ["!", "?"] => moveText + "!?"
      if (current!.nags.isNotEmpty) {
        sb.write(current!.nags.join());
      }

      // If we have comments, add exactly one space before the {..} block.
      if (current!.comments.isNotEmpty) {
        final String joinedComments =
            current!.comments.map(stripBraces).join(' ');
        sb.write(' {$joinedComments}');
      }

      results.add(sb.toString());
    }
    current = null;
  }

  // Check if token is a typical NAG.
  bool isNAG(String token) {
    const List<String> nagTokens = <String>['!', '?', '!!', '??', '!?', '?!'];
    return nagTokens.contains(token);
  }

  for (final String token in tokens) {
    // (A) If it's an annotation block { ... }, store inside comments.
    if (token.startsWith('{') && token.endsWith('}')) {
      current ??= TempMove();
      final String inside = stripOuterBraces(token).trim();
      current!.comments.add(inside);
      continue;
    }

    // (B) If this token is a typical NAG (e.g., !, ?, !?, ?!, !!, ??),
    // attach it directly to the move text with no preceding space.
    if (isNAG(token)) {
      current ??= TempMove();
      current!.nags.add(token);
      continue;
    }

    // (C) If token starts with 'x', treat it as a capture.
    if (token.startsWith('x')) {
      if (current == null) {
        current = TempMove()
          ..moveText = token
          ..hasX = true;
      } else {
        // If previous move did not have 'x', discard previous annotations/NAGs.
        if (!current!.hasX) {
          current!.comments.clear();
          current!.nags.clear(); // Discard NAGs if a new 'x' appears
        }
        // Merge capture into the moveText
        current!.moveText += token;
        current!.hasX = true;
      }
      continue;
    }

    // (D) If the token is '(' or ')', treat it as a standalone bracket token.
    //     Finalize current move first, then store the bracket directly.
    if (token == '(' || token == ')') {
      finalizeCurrent();
      // Directly add parentheses token to results
      results.add(token);
      continue;
    }

    // (E) Otherwise, this is a new move token; finalize the previous one first.
    finalizeCurrent();
    current = TempMove()..moveText = token;
  }

  // Finalize the last move if any.
  finalizeCurrent();
  return results;
}

/// Merge all moves, preserving optional [FEN] block (if present) as the first item.
List<String> getMergedMoves(GameController controller) {
  final String moveHistoryText = controller.gameRecorder.moveHistoryText;
  final List<String> mergedMoves = <String>[];
  String remainingText = moveHistoryText;

  // If the string starts with '[', treat it as FEN/PGN tag block.
  if (remainingText.startsWith('[')) {
    final int bracketEnd = remainingText.lastIndexOf(']') + 1;
    if (bracketEnd > 0) {
      mergedMoves.add(remainingText.substring(0, bracketEnd));
      remainingText = remainingText.substring(bracketEnd).trim();
    }
  }

  // (1) Lexical split (treat { ... } as single token).
  final List<String> rawTokens = lexTokens(remainingText);

  // (2) Merge tokens (capture merges, NAG merges, annotation merges).
  final List<String> moves = mergeMoves(rawTokens);

  mergedMoves.addAll(moves);
  return mergedMoves;
}
