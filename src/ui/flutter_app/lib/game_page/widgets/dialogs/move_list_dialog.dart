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
    List<String> mergedMoves = _getMergedMoves(controller);
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

  /// 1) Tokenize the move history string, treating annotation blocks `{...}` as single tokens.
  List<String> _lexTokens(String moveHistoryText) {
    final List<String> tokens = <String>[];

    int i = 0;
    while (i < moveHistoryText.length) {
      final String c = moveHistoryText[i];

      // (A) If we encounter '{', collect until the matching '}' as a single annotation token.
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
        tokens.add(moveHistoryText.substring(start, i).trim());
        continue;
      }

      // (B) Skip whitespace
      if (RegExp(r'\s').hasMatch(c)) {
        i++;
        continue;
      }

      // (C) Otherwise, collect a normal token until whitespace or '{'
      final int start = i;
      while (i < moveHistoryText.length) {
        final String cc = moveHistoryText[i];
        if (cc == '{' || RegExp(r'\s').hasMatch(cc)) {
          break;
        }
        i++;
      }
      tokens.add(moveHistoryText.substring(start, i).trim());
    }

    tokens.removeWhere((String t) => t.isEmpty);
    return tokens;
  }

  /// 2) Merge tokens:
  ///   - Combine multiple "x" captures into one move (e.g. "d6-d5" + "xd7" => "d6-d5xd7").
  ///   - If a new capture token appears, discard previous annotations.
  ///   - Handle NAG tokens (like !, ?, !?, ?!, !!, ??) with **no space** before them,
  ///     so the final move looks like "d4!" or "d4!?" etc.
  ///   - Only one space precedes the "{...}" comment block if there are comments.
  List<String> _mergeMoves(List<String> tokens) {
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
              current!.comments.map(_stripBraces).join(' ');
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
        final String inside = _stripOuterBraces(token).trim();
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
            current!.nags
                .clear(); // NAGs also get discarded if a new 'x' appears
          }
          // Merge capture into the moveText
          current!.moveText += token;
          current!.hasX = true;
        }
        continue;
      }

      // (D) Otherwise, this is a new move token; finalize the previous one first.
      finalizeCurrent();
      current = TempMove()..moveText = token;
    }

    // Finalize the last move if any.
    finalizeCurrent();
    return results;
  }

  /// Strip outer braces from an annotation block like "{...}".
  String _stripOuterBraces(String block) {
    if (block.startsWith('{') && block.endsWith('}') && block.length >= 2) {
      return block.substring(1, block.length - 1);
    }
    return block;
  }

  /// Remove all braces inside the text to avoid nested braces issues.
  String _stripBraces(String text) {
    return text.replaceAll('{', '').replaceAll('}', '');
  }

  /// Merge all moves, preserving optional [FEN] block (if present) as the first item.
  List<String> _getMergedMoves(GameController controller) {
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
    final List<String> rawTokens = _lexTokens(remainingText);

    // (2) Merge tokens (capture merges, NAG merges, annotation merges).
    final List<String> moves = _mergeMoves(rawTokens);

    mergedMoves.addAll(moves);
    return mergedMoves;
  }

  Widget _buildMoveListItem(
    BuildContext context,
    List<String> mergedMoves,
    String? fen,
    int index,
    ValueNotifier<int?> selectedIndex,
  ) {
    final int moveIndex = index * 2;
    final List<InlineSpan> spans = <InlineSpan>[];

    for (int i = 0; i < 2; i++) {
      if (moveIndex + i >= mergedMoves.length) {
        break;
      }

      final String moveText = DB().generalSettings.screenReaderSupport
          ? mergedMoves[moveIndex + i].toUpperCase()
          : mergedMoves[moveIndex + i];
      spans.add(
        WidgetSpan(
          child: ValueListenableBuilder<int?>(
            key: Key(
                'move_list_dialog_move_item_${moveIndex + i}_value_listenable_builder'),
            valueListenable: selectedIndex,
            builder: (BuildContext context, int? value, Widget? child) {
              final bool isSelected = value == moveIndex + i;
              return InkWell(
                key: Key('move_list_dialog_move_item_${moveIndex + i}_inkwell'),
                onTap: () {
                  selectedIndex.value = moveIndex + i;
                  _importGame(context, mergedMoves, fen, moveIndex + i);
                },
                child: Container(
                  key: Key(
                      'move_list_dialog_move_item_${moveIndex + i}_container'),
                  padding: const EdgeInsets.only(right: 24.0),
                  color: isSelected
                      ? AppTheme.gamePageActionSheetTextBackgroundColor
                      : null,
                  child: Text(
                    moveText,
                    key:
                        Key('move_list_dialog_move_item_${moveIndex + i}_text'),
                    style: _getTitleTextStyle(context).copyWith(
                      color: isSelected
                          ? AppTheme.gamePageActionSheetTextColor
                          : AppTheme.gamePageActionSheetTextColor,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return Padding(
      key: Key('move_list_dialog_move_item_${index}_padding'),
      padding: EdgeInsets.zero,
      child: ListTile(
        key: Key('move_list_dialog_move_item_${index}_list_tile'),
        dense: true,
        title: Text.rich(
          TextSpan(
            children: spans,
            style: const TextStyle(height: 1.2),
          ),
          key: Key('move_list_dialog_move_item_${index}_text_rich'),
          textDirection: TextDirection.ltr,
        ),
        contentPadding: EdgeInsets.zero,
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
