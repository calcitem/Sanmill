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

part of '../game_page.dart';

class MoveListDialog extends StatelessWidget {
  const MoveListDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final GameController controller = GameController();
    String? fen;
    List<String> mergedMoves = _getMergedMoves(controller);
    if (mergedMoves.isNotEmpty) {
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

    // ValueNotifier to track the selected index
    final ValueNotifier<int?> selectedIndex = ValueNotifier<int?>(null);

    return GamePageActionSheet(
      child: AlertDialog(
        backgroundColor: UIColors.semiTransparentBlack,
        title: Text(
          S.of(context).moveList,
          style: _getTitleTextStyle(context),
        ),
        content: SizedBox(
          width: calculateNCharWidth(context, 32),
          height:
              calculateNCharWidth(context, mergedMoves.length * 2 + fenHeight),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              if (fen != null)
                InkWell(
                  onTap: () => _importGame(context, mergedMoves, fen, -1),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 24.0),
                    child: Text.rich(
                      TextSpan(
                        text: "$fen\r\n",
                        style: _getTitleTextStyle(context),
                      ),
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
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Expanded(
                child: TextButton(
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

  List<String> _getMergedMoves(GameController controller) {
    // Retrieve the move history text
    final String moveHistoryText = controller.gameRecorder.moveHistoryText;

    final List<String> mergedMoves = <String>[];
    String remainingText = moveHistoryText;

    // Check if the first character is '['
    if (moveHistoryText.startsWith('[')) {
      // Find the position of the last ']'
      final int endIndex = moveHistoryText.lastIndexOf(']') + 1;
      if (endIndex > 0) {
        // Add the part from '[' to ']' as the first merged move
        mergedMoves.add(moveHistoryText.substring(0, endIndex));
        // Update the remaining text to be processed
        remainingText = moveHistoryText.substring(endIndex).trim();
      }
    }

    // Split the remaining text by whitespace, filter, and process
    final List<String> moves = remainingText
        .split(RegExp(r'\s+'))
        .where((String s) => s.isNotEmpty && !s.contains('.'))
        .toList();

    // Process each move and merge if necessary
    for (final String move in moves) {
      if (move.startsWith('x') &&
          mergedMoves.isNotEmpty &&
          !mergedMoves[mergedMoves.length - 1].contains('[') &&
          !mergedMoves[mergedMoves.length - 1].contains(']')) {
        mergedMoves[mergedMoves.length - 1] += move;
      } else {
        mergedMoves.add(move);
      }
    }

    return mergedMoves;
  }

  Widget _buildMoveListItem(BuildContext context, List<String> mergedMoves,
      String? fen, int index, ValueNotifier<int?> selectedIndex) {
    final int moveIndex = index * 2;
    final List<InlineSpan> spans = <InlineSpan>[];

    spans.add(
      WidgetSpan(
        child: Text(
          '${(index + 1).toString().padLeft(3)}.  ',
          style: _getTitleTextStyle(context),
          textDirection: TextDirection.ltr,
        ),
      ),
    );

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
            valueListenable: selectedIndex,
            builder: (BuildContext context, int? value, Widget? child) {
              final bool isSelected = value == moveIndex + i;
              return InkWell(
                onTap: () {
                  selectedIndex.value = moveIndex + i;
                  _importGame(context, mergedMoves, fen, moveIndex + i);
                },
                child: Container(
                  padding: const EdgeInsets.only(right: 24.0),
                  color: isSelected
                      ? AppTheme.gamePageActionSheetTextBackgroundColor
                      : null,
                  child: Text(
                    moveText,
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
      padding: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        title: Text.rich(
          TextSpan(
            children: spans,
            style: const TextStyle(height: 1.2),
          ),
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
