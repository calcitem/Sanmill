/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

//import 'dart:typed_data';

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/main.dart';
import 'package:sanmill/mill/game.dart';
import 'package:sanmill/mill/position.dart';
import 'package:sanmill/mill/rule.dart';
import 'package:sanmill/mill/types.dart';
import 'package:sanmill/screens/game_settings/game_settings_page.dart';
import 'package:sanmill/services/audios.dart';
import 'package:sanmill/services/engine/engine.dart';
import 'package:sanmill/services/engine/native_engine.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/dialog.dart';
import 'package:sanmill/shared/picker.dart';
import 'package:sanmill/shared/snack_bar.dart';
import 'package:sanmill/shared/theme/app_theme.dart';
//import 'package:screen_recorder/screen_recorder.dart';
import 'package:stack_trace/stack_trace.dart';

part 'package:sanmill/screens/game_page/board.dart';
part 'package:sanmill/screens/game_page/game_page_tool_bar.dart';
part 'package:sanmill/shared/painters/board_painter.dart';
part 'package:sanmill/shared/painters/painter_base.dart';
part 'package:sanmill/shared/painters/pieces_painter.dart';

double boardWidth = 0.0;

class GamePage extends StatefulWidget {
  final EngineType engineType;

  const GamePage(this.engineType, {Key? key}) : super(key: key);

  @override
  _GamePageState createState() => _GamePageState();
}

class _GamePageState extends State<GamePage>
    with RouteAware, SingleTickerProviderStateMixin {
  final Engine _engine = NativeEngine();

  double screenPaddingH = AppTheme.boardScreenPaddingH;
  final double boardMargin = AppTheme.boardMargin;

  String? _tip = '';
  bool isReady = false;
  bool isGoingToHistory = false;
  late Timer timer;
  /*
  ScreenRecorderController screenRecorderController = ScreenRecorderController(
    pixelRatio: 1.0,
    skipFramesBetweenCaptures: 0,
  );
  */
  late AnimationController _animationController;
  late Animation<double> animation;
  bool disposed = false;
  late bool ltr;
  final String tag = "[game_page]";

  Future<void> _setReadyState() async {
    debugPrint("$tag Check if need to set Ready state...");
    if (!isReady && mounted) {
      debugPrint("$tag Set Ready State...");
      setState(() {});
      isReady = true;
      timer.cancel();

      if (Localizations.localeOf(context).languageCode == "zh" &&
          !LocalDatabaseService.preferences.isPrivacyPolicyAccepted) {
        onShowPrivacyDialog();
      }
    }
  }

  void _initAnimation() {
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds:
            (LocalDatabaseService.display.animationDuration * 1000).toInt(),
      ),
    );
    _animationController.addListener(() {});

    animation = Tween(
      begin: 1.27, // sqrt(1.618) = 1.272
      end: 1.0,
    ).animate(_animationController)
      ..addListener(() => setState(() {}));

    _animationController.addStatusListener((state) {
      if (state == AnimationStatus.completed ||
          state == AnimationStatus.dismissed) {
        if (disposed) {
          return;
        }
        _animationController.forward();
      }
    });

    if (!disposed) {
      _animationController.forward();
    }
  }

  void showTip(String? tip) {
    if (!mounted) return;
    if (tip != null) {
      debugPrint("[tip] $tip");
      if (LocalDatabaseService.preferences.screenReaderSupport) {
        //showSnackBar(context, tip);
      }
    }
    setState(() => _tip = tip);
  }

  void showTips() {
    if (!mounted) {
      return;
    }

    final winner = gameInstance.position.winner;

    final Map<String, String> colorWinStrings = {
      PieceColor.white: S.of(context).whiteWin,
      PieceColor.black: S.of(context).blackWin,
      PieceColor.draw: S.of(context).isDraw
    };

    if (winner == PieceColor.nobody) {
      if (gameInstance.position.phase == Phase.placing) {
        if (mounted) {
          showTip(S.of(context).tipPlace);
        }
      } else if (gameInstance.position.phase == Phase.moving) {
        if (mounted) {
          showTip(S.of(context).tipMove);
        }
      }
    } else {
      if (mounted) {
        showTip(colorWinStrings[winner]);
      }
    }

    if (!LocalDatabaseService.preferences.isAutoRestart) {
      showGameResult(winner);
    }
  }

  Future<dynamic> onBoardTap(int index) async {
    if (!isReady) {
      debugPrint("[tap] Not ready, ignore tapping.");
      return false;
    }

    disposed = false;
    _animationController.duration = Duration(
      milliseconds:
          (LocalDatabaseService.display.animationDuration * 1000).toInt(),
    );
    _animationController.reset();

    if (gameInstance.engineType == EngineType.aiVsAi ||
        gameInstance.engineType == EngineType.testViaLAN) {
      debugPrint("$tag Engine type is no human, ignore tapping.");
      return false;
    }

    final position = gameInstance.position;

    final int? sq = indexToSquare[index];

    if (sq == null) {
      debugPrint("$tag sq is null, skip tapping.");
      return;
    }

    // If nobody has placed, start to go.

    // TODO
    // WAR: Fix first tap response slow when piece count changed
    if (position.phase == Phase.placing &&
        position.pieceOnBoardCount[PieceColor.white] == 0 &&
        position.pieceOnBoardCount[PieceColor.black] == 0) {
      gameInstance.newGame();

      if (gameInstance.isAiToMove) {
        if (gameInstance.aiIsSearching) {
          debugPrint("$tag AI is thinking, skip tapping.");
          return false;
        } else {
          debugPrint("[tap] AI is not thinking. AI is to move.");
          await engineToGo(false);
          return false;
        }
      }
    }

    if (gameInstance.isAiToMove || gameInstance.aiIsSearching) {
      debugPrint("[tap] AI's turn, skip tapping.");
      return false;
    }

    if (position.phase == Phase.ready) {
      gameInstance.start();
    }

    // Human to go

    bool ret = false;
    await Chain.capture(() async {
      switch (position.action) {
        case Act.place:
          if (await position.putPiece(sq)) {
            if (position.action == Act.remove) {
              //Audios.playTone(Audios.mill);
              if (mounted) {
                showTip(S.of(context).tipMill);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  showSnackBar(context, S.of(context).tipMill);
                }
              }
            } else {
              //Audios.playTone(Audios.place);
              if (gameInstance.engineType == EngineType.humanVsAi && mounted) {
                if (rule.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                  showTip(S.of(context).continueToMakeMove);
                } else {
                  showTip(S.of(context).tipPlaced);
                }
              } else if (mounted) {
                if (rule.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                  showTip(
                    S.of(context).tipPlaced,
                  ); // TODO: HumanVsHuman - Change tip
                } else {
                  final side = gameInstance.sideToMove == PieceColor.white
                      ? S.of(context).black
                      : S.of(context).white;
                  showTip(side + S.of(context).tipToMove);
                }
              }
            }
            ret = true;
            debugPrint("[tap] putPiece: [$sq]");
            break;
          } else {
            debugPrint("[tap] putPiece: skip [$sq]");
            if (mounted) {
              showTip(S.of(context).tipBanPlace);
              if (LocalDatabaseService.preferences.screenReaderSupport) {
                ScaffoldMessenger.of(context).clearSnackBars();
                showSnackBar(context, S.of(context).tipBanPlace);
              }
            }
          }

          // If cannot move, retry select, do not break
          //[[fallthrough]];
          continue select;
        select:
        case Act.select:
          if (position.phase == Phase.placing) {
            if (mounted) {
              showTip(S.of(context).tipCannotPlace);
              if (LocalDatabaseService.preferences.screenReaderSupport) {
                ScaffoldMessenger.of(context).clearSnackBars();
                showSnackBar(context, S.of(context).tipCannotPlace);
              }
            }
            break;
          }
          final int selectRet = position.selectPiece(sq);
          switch (selectRet) {
            case 0:
              await Audios.playTone(Sound.select);
              gameInstance.select(index);
              ret = true;
              debugPrint("[tap] selectPiece: [$sq]");

              final us = gameInstance.sideToMove;
              if (position.phase == Phase.moving &&
                  rule.mayFly &&
                  (gameInstance.position.pieceOnBoardCount[us] ==
                          LocalDatabaseService.rules.flyPieceCount ||
                      gameInstance.position.pieceOnBoardCount[us] == 3)) {
                debugPrint("[tap] May fly.");
                if (mounted) {
                  showTip(S.of(context).tipCanMoveToAnyPoint);
                  if (LocalDatabaseService.preferences.screenReaderSupport) {
                    ScaffoldMessenger.of(context).clearSnackBars();
                    showSnackBar(context, S.of(context).tipCanMoveToAnyPoint);
                  }
                }
              } else if (mounted) {
                showTip(S.of(context).tipPlace);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  showSnackBar(context, S.of(context).selected);
                }
              }

              break;
            case -2:
              await Audios.playTone(Sound.illegal);
              debugPrint("[tap] selectPiece: skip [$sq]");
              if (mounted && position.phase != Phase.gameOver) {
                showTip(S.of(context).tipCannotMove);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  showSnackBar(context, S.of(context).tipCannotMove);
                }
              }
              break;
            case -3:
              await Audios.playTone(Sound.illegal);
              debugPrint("[tap] selectPiece: skip [$sq]");
              if (mounted) {
                showTip(S.of(context).tipCanMoveOnePoint);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  showSnackBar(context, S.of(context).tipCanMoveOnePoint);
                }
              }
              break;
            case -4:
              await Audios.playTone(Sound.illegal);
              debugPrint("[tap] selectPiece: skip [$sq]");
              if (mounted) {
                showTip(S.of(context).tipSelectPieceToMove);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  showSnackBar(context, S.of(context).tipSelectPieceToMove);
                }
              }
              break;
            default:
              await Audios.playTone(Sound.illegal);
              debugPrint("[tap] selectPiece: skip [$sq]");
              if (mounted) {
                showTip(S.of(context).tipSelectWrong);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  showSnackBar(context, S.of(context).tipSelectWrong);
                }
              }
              break;
          }

          break;

        case Act.remove:
          final int removeRet = await position.removePiece(sq);

          switch (removeRet) {
            case 0:
              //Audios.playTone(Audios.remove);
              ret = true;
              debugPrint("[tap] removePiece: [$sq]");
              if (gameInstance.position.pieceToRemoveCount >= 1) {
                if (mounted) {
                  showTip(S.of(context).tipContinueMill);
                  if (LocalDatabaseService.preferences.screenReaderSupport) {
                    showSnackBar(context, S.of(context).tipContinueMill);
                  }
                }
              } else {
                if (gameInstance.engineType == EngineType.humanVsAi) {
                  if (mounted) {
                    showTip(S.of(context).tipRemoved);
                  }
                } else {
                  if (mounted) {
                    final them = gameInstance.sideToMove == PieceColor.white
                        ? S.of(context).black
                        : S.of(context).white;
                    if (mounted) {
                      showTip(them + S.of(context).tipToMove);
                    }
                  }
                }
              }
              break;
            case -2:
              await Audios.playTone(Sound.illegal);
              debugPrint(
                "[tap] removePiece: Cannot Remove our pieces, skip [$sq]",
              );
              if (mounted) {
                showTip(S.of(context).tipSelectOpponentsPiece);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  showSnackBar(context, S.of(context).tipSelectOpponentsPiece);
                }
              }
              break;
            case -3:
              await Audios.playTone(Sound.illegal);
              debugPrint(
                "[tap] removePiece: Cannot remove piece from Mill, skip [$sq]",
              );
              if (mounted) {
                showTip(S.of(context).tipCannotRemovePieceFromMill);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  showSnackBar(
                    context,
                    S.of(context).tipCannotRemovePieceFromMill,
                  );
                }
              }
              break;
            default:
              await Audios.playTone(Sound.illegal);
              debugPrint("[tap] removePiece: skip [$sq]");
              if (mounted && position.phase != Phase.gameOver) {
                showTip(S.of(context).tipBanRemove);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  showSnackBar(context, S.of(context).tipBanRemove);
                }
              }
              break;
          }

          break;

        default:
          break;
      }

      if (ret) {
        gameInstance.sideToMove = position.sideToMove;
        gameInstance.moveHistory.add(position.record!);

        // TODO: Need Others?
        // Increment ply counters. In particular,
        // rule50 will be reset to zero later on
        // in case of a remove.
        ++position.gamePly;
        ++position.st.rule50;
        ++position.st.pliesFromNull;

        if (position.record!.length > "-(1,2)".length) {
          if (posKeyHistory.isEmpty ||
              (posKeyHistory.isNotEmpty &&
                  position.st.key != posKeyHistory[posKeyHistory.length - 1])) {
            posKeyHistory.add(position.st.key);
            if (rule.threefoldRepetitionRule && position.hasGameCycle()) {
              position.setGameOver(
                PieceColor.draw,
                GameOverReason.drawReasonThreefoldRepetition,
              );
            }
          }
        } else {
          posKeyHistory.clear();
        }

        //position.move = m;

        final Move m = Move(position.record);
        position.recorder!.prune();
        position.recorder!.moveIn(m, position);

        /*
        if (LocalDatabaseService.preferences.screenReaderSupport && m.notation != null) {
          showSnackBar(context, S.of(context).human + ": " + m.notation!);
        }
        */

        setState(() {});

        if (position.winner == PieceColor.nobody) {
          engineToGo(false);
        } else {
          showTips();
        }
      }

      gameInstance.sideToMove = position.sideToMove;

      setState(() {});
    }); // Chain.capture

    return ret;
  }

  Future<void> engineToGo(bool isMoveNow) async {
    bool _isMoveNow = isMoveNow;

    if (!mounted) {
      debugPrint("[engineToGo] !mounted, skip engineToGo.");
      return;
    }

    // TODO
    debugPrint("[engineToGo] engine type is ${widget.engineType}");

    if (_isMoveNow) {
      if (!gameInstance.isAiToMove) {
        debugPrint("[engineToGo] Human to Move. Cannot get search result now.");
        ScaffoldMessenger.of(context).clearSnackBars();
        showSnackBar(context, S.of(context).notAIsTurn);
        return;
      }
      if (!gameInstance.position.recorder!.isClean()) {
        debugPrint(
          "[engineToGo] History is not clean. Cannot get search result now.",
        );
        ScaffoldMessenger.of(context).clearSnackBars();
        showSnackBar(context, S.of(context).aiIsNotThinking);
        return;
      }
    }

    while ((LocalDatabaseService.preferences.isAutoRestart == true ||
            gameInstance.position.winner == PieceColor.nobody) &&
        gameInstance.isAiToMove &&
        mounted) {
      if (widget.engineType == EngineType.aiVsAi) {
        final String score =
            "${gameInstance.position.score[PieceColor.white]} : ${gameInstance.position.score[PieceColor.black]} : ${gameInstance.position.score[PieceColor.draw]}";

        showTip(score);
      } else {
        if (mounted) {
          showTip(S.of(context).thinking);

          final Move? m = gameInstance.position.recorder!.lastMove;

          if (LocalDatabaseService.preferences.screenReaderSupport &&
              gameInstance.position.action != Act.remove &&
              m != null &&
              m.notation != null) {
            showSnackBar(context, "${S.of(context).human}: ${m.notation!}");
          }
        }
      }

      late EngineResponse response;

      if (!_isMoveNow) {
        debugPrint("[engineToGo] Searching...");
        response = await _engine.search(gameInstance.position);
      } else {
        debugPrint("[engineToGo] Get search result now...");
        response = await _engine.search(null);
        _isMoveNow = false;
      }

      debugPrint("[engineToGo] Engine response type: ${response.type}");

      switch (response.type) {
        case 'move':
          final Move mv = response.value as Move;
          final Move move = Move(mv.move);

          _animationController.duration = Duration(
            milliseconds:
                (LocalDatabaseService.display.animationDuration * 1000).toInt(),
          );

          if (!disposed) {
            _animationController.reset();
          } else {
            debugPrint(
              "[engineToGo] Disposed, so do not reset animationController.",
            );
          }

          await gameInstance.doMove(move.move!);
          showTips();
          if (LocalDatabaseService.preferences.screenReaderSupport &&
              move.notation != null) {
            showSnackBar(context, "${S.of(context).ai}: ${move.notation!}");
          }
          break;
        case 'timeout':
          if (mounted) {
            showTip(S.of(context).timeout);
            if (LocalDatabaseService.preferences.screenReaderSupport) {
              showSnackBar(context, S.of(context).timeout);
            }
          }

          //if (LocalDatabaseService.developerMode) {
          //assert(false);
          //}
          return;
        default:
          showTip('Error: ${response.type}');
          break;
      }

      if (LocalDatabaseService.preferences.isAutoRestart == true &&
          gameInstance.position.winner != PieceColor.nobody) {
        gameInstance.newGame();
      }
    }
  }

  Future<void> onStartNewGameButtonPressed() async {
    Navigator.pop(context);

    if (gameInstance.isAiToMove) {
      // TODO: Move now
      //debugPrint("$tag New game, AI to move, move now.");
      //await engineToGo(true);
    }

    gameInstance.newGame();

    if (mounted) {
      showTip(S.of(context).gameStarted);
      if (LocalDatabaseService.preferences.screenReaderSupport) {
        ScaffoldMessenger.of(context).clearSnackBars();
        showSnackBar(context, S.of(context).gameStarted);
      }
    }

    if (gameInstance.isAiToMove) {
      debugPrint("$tag New game, AI to move.");
      engineToGo(false);
    }
  }

  Future<void> onImportGameButtonPressed() async {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).clearSnackBars();

    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);

    if (data == null || data.text == null) {
      return;
    }

    final String text = data.text!;

    debugPrint("Clipboard text:");
    debugPrint(text);

    await onTakeBackAllButtonPressed(false);
    gameInstance.position.recorder!.clear();
    final importFailedStr = gameInstance.position.recorder!.import(text);

    if (importFailedStr != "") {
      showTip("${S.of(context).cannotImport} $importFailedStr");
      if (LocalDatabaseService.preferences.screenReaderSupport) {
        ScaffoldMessenger.of(context).clearSnackBars();
        showSnackBar(context, "${S.of(context).cannotImport} $importFailedStr");
      }
      return;
    }

    await onStepForwardAllButtonPressed(false);

    showTip(S.of(context).gameImported);
    if (LocalDatabaseService.preferences.screenReaderSupport) {
      ScaffoldMessenger.of(context).clearSnackBars();
      showSnackBar(context, S.of(context).gameImported);
    }
  }

  Future<void> onExportGameButtonPressed() async {
    Navigator.pop(context);

    final moveHistoryText = gameInstance.position.moveHistoryText;

    Clipboard.setData(ClipboardData(text: moveHistoryText)).then((_) {
      showSnackBar(context, S.of(context).moveHistoryCopied);
    });
  }

  /*
  onStartRecordingButtonPressed() async {
    Navigator.pop(context);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text(
          S.of(context).appName,
          style: TextStyle(
            color: AppTheme.dialogTitleColor,
            fontSize: LocalDatabaseService.display.fontSize + 4,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              S.of(context).experimental,
              style: TextStyle(
                fontSize: LocalDatabaseService.display.fontSize,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            child: Text(
              S.of(context).ok,
              style: TextStyle(
                fontSize: LocalDatabaseService.display.fontSize,
              ),
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );

    screenRecorderController.start();
    showSnackBar(
      S.of(context).recording,
      duration: Duration(seconds: 1 << 31),
    );
  }

  onStopRecordingButtonPressed() async {
    Navigator.pop(context);
    screenRecorderController.stop();
    showSnackBar(
      S.of(context).stopRecording,
      duration: Duration(seconds: 2),
    );
  }

  onShowRecordingButtonPressed() async {
    Navigator.pop(context);
    showSnackBar(
      S.of(context).pleaseWait,
      duration: Duration(seconds: 1 << 31),
    );
    var gif = await screenRecorderController.export();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (gif == null) {
      showSnackBar(S.of(context).noRecording);
      return;
    }

    var image = Image.memory(
      Uint8List.fromList(gif),
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(backgroundColor: Colors.black, content: image);
      },
    );
  }
  */

  Future<void> onAutoReplayButtonPressed() async {
    Navigator.pop(context);

    await onTakeBackAllButtonPressed(false);
    await onStepForwardAllButtonPressed(false);
  }

  void onGameButtonPressed() {
    showModalBottomSheet(
      //showDialog(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Semantics(
        label: S.of(context).game,
        child: SimpleDialog(
          backgroundColor: Colors.transparent,
          children: <Widget>[
            SimpleDialogOption(
              onPressed: onStartNewGameButtonPressed,
              child: Text(
                S.of(context).newGame,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppTheme.sizedBoxHeight),
            SimpleDialogOption(
              onPressed: onImportGameButtonPressed,
              child: Text(
                S.of(context).importGame,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppTheme.sizedBoxHeight),
            SimpleDialogOption(
              onPressed: onExportGameButtonPressed,
              child: Text(
                S.of(context).exportGame,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppTheme.sizedBoxHeight),
            if (LocalDatabaseService.preferences.screenReaderSupport)
              SimpleDialogOption(
                child: Text(
                  S.of(context).close,
                  style: AppTheme.simpleDialogOptionTextStyle,
                  textAlign: TextAlign.center,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            /*
            SizedBox(height: AppTheme.sizedBoxHeight),
            LocalDatabaseService.experimentsEnabled
                ? SimpleDialogOption(
                    child: Text(
                      S.of(context).startRecording,
                      style: AppTheme.simpleDialogOptionTextStyle,
                      textAlign: TextAlign.center,
                    ),
                    onPressed: onStartRecordingButtonPressed,
                  )
                : SizedBox(height: 1),
            LocalDatabaseService.experimentsEnabled
                ? SizedBox(height: AppTheme.sizedBoxHeight)
                : SizedBox(height: 1),
            LocalDatabaseService.experimentsEnabled
                ? SimpleDialogOption(
                    child: Text(
                      S.of(context).stopRecording,
                      style: AppTheme.simpleDialogOptionTextStyle,
                      textAlign: TextAlign.center,
                    ),
                    onPressed: onStopRecordingButtonPressed,
                  )
                : SizedBox(height: 1),
            LocalDatabaseService.experimentsEnabled
                ? SizedBox(height: AppTheme.sizedBoxHeight)
                : SizedBox(height: 1),
            LocalDatabaseService.experimentsEnabled
                ? SimpleDialogOption(
                    child: Text(
                      S.of(context).showRecording,
                      style: AppTheme.simpleDialogOptionTextStyle,
                      textAlign: TextAlign.center,
                    ),
                    onPressed: onShowRecordingButtonPressed,
                  )
                : SizedBox(height: 1),
            */
            /*
            SizedBox(height: AppTheme.sizedBoxHeight),
            SimpleDialogOption(
              child: Text(
                S.of(context).autoReplay,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
              onPressed: onAutoReplayButtonPressed,
            ),
            */
          ],
        ),
      ),
    );
  }

  void onOptionButtonPressed() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => GameSettingsPage()),
    );
  }

  void onMoveButtonPressed() {
    final List<Widget> _historyNavigation = [
      SimpleDialogOption(
        onPressed: onTakeBackButtonPressed,
        child: Text(
          S.of(context).takeBack,
          style: AppTheme.simpleDialogOptionTextStyle,
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      SimpleDialogOption(
        onPressed: onStepForwardButtonPressed,
        child: Text(
          S.of(context).stepForward,
          style: AppTheme.simpleDialogOptionTextStyle,
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      SimpleDialogOption(
        onPressed: onTakeBackAllButtonPressed,
        child: Text(
          S.of(context).takeBackAll,
          style: AppTheme.simpleDialogOptionTextStyle,
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      SimpleDialogOption(
        onPressed: onStepForwardAllButtonPressed,
        child: Text(
          S.of(context).stepForwardAll,
          style: AppTheme.simpleDialogOptionTextStyle,
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Semantics(
        label: S.of(context).move,
        child: SimpleDialog(
          backgroundColor: Colors.transparent,
          children: <Widget>[
            if (!LocalDatabaseService.display.isHistoryNavigationToolbarShown)
              ..._historyNavigation,
            SimpleDialogOption(
              onPressed: onMoveListButtonPressed,
              child: Text(
                S.of(context).showMoveList,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppTheme.sizedBoxHeight),
            SimpleDialogOption(
              onPressed: onMoveNowButtonPressed,
              child: Text(
                S.of(context).moveNow,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppTheme.sizedBoxHeight),
            if (LocalDatabaseService.preferences.screenReaderSupport)
              SimpleDialogOption(
                child: Text(
                  S.of(context).close,
                  style: AppTheme.simpleDialogOptionTextStyle,
                  textAlign: TextAlign.center,
                ),
                onPressed: () => Navigator.pop(context),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> onGotoHistoryButtonsPressed(
    HistoryMove move, {
    bool pop = true,
    int? number,
  }) async {
    if (pop == true) {
      Navigator.pop(context);
    }

    if (mounted) {
      showTip(S.of(context).waiting);
    }

    if (isGoingToHistory) {
      debugPrint(
        "[TakeBack] Is going to history, ignore Take Back button press.",
      );
      return;
    }

    isGoingToHistory = true;

    final errMove = await gameInstance.position.gotoHistory(move, number);

    switch (errMove) {
      case "":
        break;
      case "null":
      case "out-of-range":
      case "equal":
        ScaffoldMessenger.of(context).clearSnackBars();
        showSnackBar(context, S.of(context).atEnd);
        break;
      default:
        ScaffoldMessenger.of(context).clearSnackBars();
        showSnackBar(context, S.of(context).movesAndRulesNotMatch);
        break;
    }

    isGoingToHistory = false;

    if (mounted) {
      final pos = gameInstance.position;
      /*
      String us = "";
      String them = "";
      if (pos.side == PieceColor.white) {
        us = S.of(context).player1;
        them = S.of(context).player2;
      } else if (pos.side == PieceColor.black) {
        us = S.of(context).player2;
        them = S.of(context).player1;
      }
      */

      late final String text;
      final lastEffectiveMove = pos.recorder!.lastEffectiveMove;
      if (lastEffectiveMove != null && lastEffectiveMove.notation != null) {
        text = "${S.of(context).lastMove}: ${lastEffectiveMove.notation}";
      } else {
        text = S.of(context).atEnd;
      }

      showTip(text);

      if (LocalDatabaseService.preferences.screenReaderSupport) {
        ScaffoldMessenger.of(context).clearSnackBars();
        showSnackBar(context, text);
      }
    }
  }

  Future<void> onTakeBackButtonPressed([bool pop = true]) async =>
      onGotoHistoryButtonsPressed(
        HistoryMove.backOne,
        pop: pop,
      );

  Future<void> onStepForwardButtonPressed([bool pop = true]) async =>
      onGotoHistoryButtonsPressed(
        HistoryMove.farward,
        pop: pop,
      );

  Future<void> onTakeBackAllButtonPressed([bool pop = true]) async =>
      onGotoHistoryButtonsPressed(
        HistoryMove.backAll,
        pop: pop,
      );

  Future<void> onStepForwardAllButtonPressed([bool pop = true]) async {
    onGotoHistoryButtonsPressed(
      HistoryMove.forwardAll,
      pop: pop,
    );
  }

  Future<void> onTakeBackNButtonPressed(int n, [bool pop = true]) async =>
      onGotoHistoryButtonsPressed(
        HistoryMove.backN,
        number: n,
        pop: pop,
      );

  void onMoveListButtonPressed() {
    final moveHistoryText = gameInstance.position.moveHistoryText;
    final end = gameInstance.moveHistory.length - 1;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).clearSnackBars();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.moveHistoryDialogBackgroundColor,
          title: Text(
            S.of(context).moveList,
            style: TextStyle(
              color: AppTheme.moveHistoryTextColor,
              fontSize: LocalDatabaseService.display.fontSize + 2.0,
            ),
          ),
          content: SingleChildScrollView(
            child: Text(
              moveHistoryText,
              style: AppTheme.moveHistoryTextStyle,
              textDirection: TextDirection.ltr,
            ),
          ),
          actions: <Widget>[
            if (end > 0)
              TextButton(
                child: Text(
                  S.of(context).rollback,
                  style: AppTheme.moveHistoryTextStyle,
                ),
                onPressed: () async {
                  final int selectValue = await showPickerNumber(
                    context,
                    1,
                    end,
                    1,
                    S.of(context).moves,
                  );

                  if (selectValue != 0) {
                    onTakeBackNButtonPressed(selectValue);
                  }
                },
              )
            else
              TextButton(
                child: const Text(""),
                onPressed: () => Navigator.pop(context),
              ),
            TextButton(
              child: Text(
                S.of(context).copy,
                style: AppTheme.moveHistoryTextStyle,
              ),
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: moveHistoryText))
                      .then((_) {
                ScaffoldMessenger.of(context).clearSnackBars();
                showSnackBar(context, S.of(context).moveHistoryCopied);
              }),
            ),
            TextButton(
              child: Text(
                S.of(context).cancel,
                style: AppTheme.moveHistoryTextStyle,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }

  Future<void> onMoveNowButtonPressed() async {
    Navigator.pop(context);
    await engineToGo(true);
  }

  void onInfoButtonPressed() {
    final analyzeText = infoText;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.infoDialogBackgroundColor,
          content: SingleChildScrollView(
            child: Text(analyzeText, style: AppTheme.moveHistoryTextStyle),
          ),
          actions: <Widget>[
            TextButton(
              child:
                  Text(S.of(context).ok, style: AppTheme.moveHistoryTextStyle),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }

  Future<void> setPrivacyPolicyAccepted(bool value) async {
    LocalDatabaseService.preferences = LocalDatabaseService.preferences
        .copyWith(isPrivacyPolicyAccepted: value);

    debugPrint("[config] isPrivacyPolicyAccepted: $value");
  }

  Future<void> onShowPrivacyDialog() async {
    showPrivacyDialog(context, setPrivacyPolicyAccepted);
  }

  String getGameOverReasonString(GameOverReason? reason, String? winner) {
    //String winnerStr =
    //    winner == Color.white ? S.of(context).white : S.of(context).black;
    final String loserStr =
        winner == PieceColor.white ? S.of(context).black : S.of(context).white;

    final Map<GameOverReason, String> reasonMap = {
      GameOverReason.loseReasonlessThanThree:
          loserStr + S.of(context).loseReasonlessThanThree,
      GameOverReason.loseReasonResign:
          loserStr + S.of(context).loseReasonResign,
      GameOverReason.loseReasonNoWay: loserStr + S.of(context).loseReasonNoWay,
      GameOverReason.loseReasonBoardIsFull:
          loserStr + S.of(context).loseReasonBoardIsFull,
      GameOverReason.loseReasonTimeOver:
          loserStr + S.of(context).loseReasonTimeOver,
      GameOverReason.drawReasonRule50: S.of(context).drawReasonRule50,
      GameOverReason.drawReasonEndgameRule50:
          S.of(context).drawReasonEndgameRule50,
      GameOverReason.drawReasonBoardIsFull: S.of(context).drawReasonBoardIsFull,
      GameOverReason.drawReasonThreefoldRepetition:
          S.of(context).drawReasonThreefoldRepetition,
    };

    debugPrint(
      "$tag Game over reason: ${gameInstance.position.gameOverReason}",
    );

    String? loseReasonStr = reasonMap[gameInstance.position.gameOverReason];

    if (loseReasonStr == null) {
      loseReasonStr = S.of(context).gameOverUnknownReason;
      debugPrint("$tag Game over reason string: $loseReasonStr");
      if (LocalDatabaseService.preferences.developerMode) {
        assert(false);
      }
    }

    return loseReasonStr;
  }

  GameResult getGameResult(String winner) {
    if (isAi[PieceColor.white]! && isAi[PieceColor.black]!) {
      return GameResult.none;
    }

    if (winner == PieceColor.white) {
      if (isAi[PieceColor.white]!) {
        return GameResult.lose;
      } else {
        return GameResult.win;
      }
    }

    if (winner == PieceColor.black) {
      if (isAi[PieceColor.black]!) {
        return GameResult.lose;
      } else {
        return GameResult.win;
      }
    }

    if (winner == PieceColor.draw) {
      return GameResult.draw;
    }

    return GameResult.none;
  }

  void showGameResult(String winner) {
    final GameResult result = getGameResult(winner);
    gameInstance.position.result = result;

    switch (result) {
      case GameResult.win:
        //Audios.playTone(Audios.win);
        break;
      case GameResult.lose:
        //Audios.playTone(Audios.lose);
        break;
      case GameResult.draw:
        break;
      default:
        break;
    }

    final Map<GameResult, String> retMap = {
      GameResult.win: gameInstance.engineType == EngineType.humanVsAi
          ? S.of(context).youWin
          : S.of(context).gameOver,
      GameResult.lose: S.of(context).gameOver,
      GameResult.draw: S.of(context).isDraw
    };

    final dialogTitle = retMap[result];

    if (dialogTitle == null) {
      return;
    }

    final bool isTopLevel =
        LocalDatabaseService.preferences.skillLevel == 30; // TODO: 30

    if (result == GameResult.win &&
        !isTopLevel &&
        gameInstance.engineType == EngineType.humanVsAi) {
      var contentStr = getGameOverReasonString(
        gameInstance.position.gameOverReason,
        gameInstance.position.winner,
      );

      if (!isTopLevel) {
        contentStr +=
            "\n\n${S.of(context).challengeHarderLevel}${LocalDatabaseService.preferences.skillLevel + 1}!";
      }

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(
              dialogTitle,
              style: TextStyle(
                color: AppTheme.dialogTitleColor,
                fontSize: LocalDatabaseService.display.fontSize + 4,
              ),
            ),
            content: Text(
              contentStr,
              style: TextStyle(
                fontSize: LocalDatabaseService.display.fontSize,
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(
                  S.of(context).yes,
                  style: TextStyle(
                    fontSize: LocalDatabaseService.display.fontSize,
                  ),
                ),
                onPressed: () async {
                  if (!isTopLevel) {
                    final _pref = LocalDatabaseService.preferences;
                    LocalDatabaseService.preferences =
                        _pref.copyWith(skillLevel: _pref.skillLevel + 1);
                    debugPrint(
                      "[config] skillLevel: ${LocalDatabaseService.preferences.skillLevel}",
                    );
                  }
                  Navigator.pop(context);
                },
              ),
              TextButton(
                child: Text(
                  S.of(context).no,
                  style: TextStyle(
                    fontSize: LocalDatabaseService.display.fontSize,
                  ),
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          );
        },
      );
    } else {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(
              dialogTitle,
              style: TextStyle(
                color: AppTheme.dialogTitleColor,
                fontSize: LocalDatabaseService.display.fontSize + 4,
              ),
            ),
            content: Text(
              getGameOverReasonString(
                gameInstance.position.gameOverReason,
                gameInstance.position.winner,
              ),
              style: TextStyle(
                fontSize: LocalDatabaseService.display.fontSize,
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(
                  S.of(context).restart,
                  style: TextStyle(
                    fontSize: LocalDatabaseService.display.fontSize,
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  gameInstance.newGame();
                  if (mounted) {
                    showTip(S.of(context).gameStarted);
                    if (LocalDatabaseService.preferences.screenReaderSupport) {
                      ScaffoldMessenger.of(context).clearSnackBars();
                      showSnackBar(context, S.of(context).gameStarted);
                    }
                  }

                  if (gameInstance.isAiToMove) {
                    debugPrint("$tag New game, AI to move.");
                    engineToGo(false);
                  }
                },
              ),
              TextButton(
                child: Text(
                  S.of(context).cancel,
                  style: TextStyle(
                    fontSize: LocalDatabaseService.display.fontSize,
                  ),
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          );
        },
      );
    }
  }

  double get _screenPaddingH {
    //
    // when screen's height/width rate is less than 16/9, limit width of board
    final windowSize = MediaQuery.of(context).size;
    final double height = windowSize.height;
    double width = windowSize.width;

    // TODO: maybe use windowSize.aspectratio
    if (height / width < 16.0 / 9.0) {
      width = height * 9 / 16;
      return (windowSize.width - width) / 2 - AppTheme.boardMargin;
    } else {
      return AppTheme.boardScreenPaddingH;
    }
  }

  Widget get header {
    final Map<EngineType, IconData> engineTypeToIconLeft = {
      EngineType.humanVsAi: LocalDatabaseService.preferences.aiMovesFirst
          ? FluentIcons.bot_24_filled
          : FluentIcons.person_24_filled,
      EngineType.humanVsHuman: FluentIcons.person_24_filled,
      EngineType.aiVsAi: FluentIcons.bot_24_filled,
      EngineType.humanVsCloud: FluentIcons.person_24_filled,
      EngineType.humanVsLAN: FluentIcons.person_24_filled,
      EngineType.testViaLAN: FluentIcons.wifi_1_24_filled,
    };

    final Map<EngineType, IconData> engineTypeToIconRight = {
      EngineType.humanVsAi: LocalDatabaseService.preferences.aiMovesFirst
          ? FluentIcons.person_24_filled
          : FluentIcons.bot_24_filled,
      EngineType.humanVsHuman: FluentIcons.person_24_filled,
      EngineType.aiVsAi: FluentIcons.bot_24_filled,
      EngineType.humanVsCloud: FluentIcons.cloud_24_filled,
      EngineType.humanVsLAN: FluentIcons.wifi_1_24_filled,
      EngineType.testViaLAN: FluentIcons.wifi_1_24_filled,
    };

    final iconColor = LocalDatabaseService.colorSettings.messageColor;

    final iconRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(engineTypeToIconLeft[widget.engineType], color: iconColor),
        Icon(iconArrow, color: iconColor),
        Icon(engineTypeToIconRight[widget.engineType], color: iconColor),
      ],
    );

    return Container(
      margin: EdgeInsets.only(top: LocalDatabaseService.display.boardTop),
      child: Column(
        children: <Widget>[
          iconRow,
          Container(
            height: 4,
            width: 180,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: LocalDatabaseService.colorSettings.boardBackgroundColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _tip!,
              maxLines: 1,
              style: TextStyle(
                fontSize: LocalDatabaseService.display.fontSize,
                color: LocalDatabaseService.colorSettings.messageColor,
              ),
            ),
          ), // TODO: Font Size
        ],
      ),
    );
  }

  IconData get iconArrow {
    IconData iconArrow = FluentIcons.code_24_regular;

    if (gameInstance.position.phase == Phase.gameOver) {
      switch (gameInstance.position.winner) {
        case PieceColor.white:
          iconArrow = ltr
              ? FluentIcons.toggle_left_24_regular
              : FluentIcons.toggle_right_24_regular;
          break;
        case PieceColor.black:
          iconArrow = ltr
              ? FluentIcons.toggle_right_24_regular
              : FluentIcons.toggle_left_24_regular;
          break;
        default:
          iconArrow = FluentIcons.handshake_24_regular;
          break;
      }
    } else {
      switch (gameInstance.sideToMove) {
        case PieceColor.white:
          iconArrow = FluentIcons.chevron_left_24_regular;
          break;
        case PieceColor.black:
          iconArrow = FluentIcons.chevron_right_24_regular;
          break;
        default:
          iconArrow = FluentIcons.code_24_regular;
          break;
      }
    }

    return iconArrow;
  }

  Widget get board {
    boardWidth = MediaQuery.of(context).size.width - screenPaddingH * 2;

    return Container(
      margin: EdgeInsets.symmetric(vertical: boardMargin),
      child: Board(
        width: boardWidth,
        onBoardTap: onBoardTap,
        animationValue: animation.value,
      ),
    );
  }

  String get infoText {
    String phase = "";
    final String period =
        LocalDatabaseService.preferences.screenReaderSupport ? "." : "";
    final String comma =
        LocalDatabaseService.preferences.screenReaderSupport ? "," : "";

    final pos = gameInstance.position;

    switch (pos.phase) {
      case Phase.placing:
        phase = S.of(context).placingPhase;
        break;
      case Phase.moving:
        phase = S.of(context).movingPhase;
        break;
      default:
        break;
    }

    final String pieceCountInHand = pos.phase == Phase.placing
        ? "${S.of(context).player1} ${S.of(context).inHand}: ${pos.pieceInHandCount[PieceColor.white]}$comma\n${S.of(context).player2} ${S.of(context).inHand}: ${pos.pieceInHandCount[PieceColor.black]}$comma\n"
        : "";

    String us = "";
    String them = "";
    if (pos.side == PieceColor.white) {
      us = S.of(context).player1;
      them = S.of(context).player2;
    } else if (pos.side == PieceColor.black) {
      us = S.of(context).player2;
      them = S.of(context).player1;
    }

    final String tip =
        (_tip == null || !LocalDatabaseService.preferences.screenReaderSupport)
            ? ""
            : "\n$_tip";

    String lastMove = "";
    if (pos.recorder?.lastMove?.notation != null) {
      final String n1 = pos.recorder!.lastMove!.notation!;

      if (n1.startsWith("x")) {
        final String n2 =
            pos.recorder!.moveAt(pos.recorder!.movesCount - 2).notation!;
        lastMove = n2 + n1;
      } else {
        lastMove = n1;
      }
      if (LocalDatabaseService.preferences.screenReaderSupport) {
        lastMove = "${S.of(context).lastMove}: $them, $lastMove$period\n";
      } else {
        lastMove = "${S.of(context).lastMove}: $lastMove$period\n";
      }
    }

    String addedPeriod = "";
    if (LocalDatabaseService.preferences.screenReaderSupport &&
        tip.isNotEmpty &&
        tip[tip.length - 1] != '.' &&
        tip[tip.length - 1] != '!') {
      addedPeriod = ".";
    }

    final String ret =
        "$phase$period\n$lastMove${S.of(context).sideToMove}: $us$period$tip$addedPeriod\n\n${S.of(context).pieceCount}:\n$pieceCountInHand${S.of(context).player1} ${S.of(context).onBoard}: ${pos.pieceOnBoardCount[PieceColor.white]}$comma\n${S.of(context).player2} ${S.of(context).onBoard}: ${pos.pieceOnBoardCount[PieceColor.black]}$period\n\n${S.of(context).score}:\n${S.of(context).player1}: ${pos.score[PieceColor.white]}$comma\n${S.of(context).player2}: ${pos.score[PieceColor.black]}$comma\n${S.of(context).draw}: ${pos.score[PieceColor.draw]}$period";
    return ret;
  }

  Widget get toolbar {
    final gameButton = TextButton(
      onPressed: onGameButtonPressed,
      child: Column(
        // Replace with a Row for horizontal icon + text
        children: <Widget>[
          Icon(
            FluentIcons.table_simple_24_regular,
            color: LocalDatabaseService.colorSettings.mainToolbarIconColor,
          ),
          Text(
            S.of(context).game,
            style: TextStyle(
              color: LocalDatabaseService.colorSettings.mainToolbarIconColor,
            ),
          ),
        ],
      ),
    );

    final optionsButton = TextButton(
      onPressed: onOptionButtonPressed,
      child: Column(
        // Replace with a Row for horizontal icon + text
        children: <Widget>[
          Icon(
            FluentIcons.settings_24_regular,
            color: LocalDatabaseService.colorSettings.mainToolbarIconColor,
          ),
          Text(
            S.of(context).options,
            style: TextStyle(
              color: LocalDatabaseService.colorSettings.mainToolbarIconColor,
            ),
          ),
        ],
      ),
    );

    final moveButton = TextButton(
      onPressed: onMoveButtonPressed,
      child: Column(
        // Replace with a Row for horizontal icon + text
        children: <Widget>[
          Icon(
            FluentIcons.calendar_agenda_24_regular,
            color: LocalDatabaseService.colorSettings.mainToolbarIconColor,
          ),
          Text(
            S.of(context).move,
            style: TextStyle(
              color: LocalDatabaseService.colorSettings.mainToolbarIconColor,
            ),
          ),
        ],
      ),
    );

    final infoButton = TextButton(
      onPressed: onInfoButtonPressed,
      child: Column(
        // Replace with a Row for horizontal icon + text
        children: <Widget>[
          Icon(
            FluentIcons.book_information_24_regular,
            color: LocalDatabaseService.colorSettings.mainToolbarIconColor,
          ),
          Text(
            S.of(context).info,
            style: TextStyle(
              color: LocalDatabaseService.colorSettings.mainToolbarIconColor,
            ),
          ),
        ],
      ),
    );

    return GamePageToolBar(
      children: <Widget>[
        gameButton,
        optionsButton,
        moveButton,
        infoButton,
      ],
    );
  }

  Widget get historyNavToolbar {
    final takeBackAllButton = TextButton(
      child: Semantics(
        label: S.of(context).takeBackAll,
        child: Icon(
          ltr
              ? FluentIcons.arrow_previous_24_regular
              : FluentIcons.arrow_next_24_regular,
          color: LocalDatabaseService.colorSettings.navigationToolbarIconColor,
        ),
      ),
      onPressed: () => onTakeBackAllButtonPressed(false),
    );

    final takeBackButton = TextButton(
      child: Semantics(
        label: S.of(context).takeBack,
        child: Icon(
          ltr
              ? FluentIcons.chevron_left_24_regular
              : FluentIcons.chevron_right_24_regular,
          color: LocalDatabaseService.colorSettings.navigationToolbarIconColor,
        ),
      ),
      onPressed: () async => onTakeBackButtonPressed(false),
    );

    final stepForwardButton = TextButton(
      child: Semantics(
        label: S.of(context).stepForward,
        child: Icon(
          ltr
              ? FluentIcons.chevron_right_24_regular
              : FluentIcons.chevron_left_24_regular,
          color: LocalDatabaseService.colorSettings.navigationToolbarIconColor,
        ),
      ),
      onPressed: () async => onStepForwardButtonPressed(false),
    );

    final stepForwardAllButton = TextButton(
      child: Semantics(
        label: S.of(context).stepForwardAll,
        child: Icon(
          ltr
              ? FluentIcons.arrow_next_24_regular
              : FluentIcons.arrow_previous_24_regular,
          color: LocalDatabaseService.colorSettings.navigationToolbarIconColor,
        ),
      ),
      onPressed: () async => onStepForwardAllButtonPressed(false),
    );

    return GamePageToolBar(
      children: <Widget>[
        takeBackAllButton,
        takeBackButton,
        stepForwardButton,
        stepForwardAllButton,
      ],
    );
  }

  @override
  void initState() {
    debugPrint("$tag Engine type: ${widget.engineType}");

    gameInstance.setWhoIsAi(widget.engineType);

    super.initState();
    gameInstance.init();
    _engine.startup();

    timer = Timer.periodic(
      const Duration(microseconds: 100),
      (_) => _setReadyState(),
    );

    _initAnimation();

    LocalDatabaseService.listenPreferences.addListener(_refeshEngine);
  }

  Future<void> _refeshEngine() async {
    await _engine.setOptions();
    debugPrint("$tag reloaded engine options");
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(
      this,
      ModalRoute.of(context)! as PageRoute<dynamic>,
    );
    screenPaddingH = _screenPaddingH;
    ltr = Directionality.of(context) == TextDirection.ltr;
  }

  @override
  Widget build(BuildContext context) {
    if (_tip == '') {
      _tip = S.of(context).welcome;
    }

    return Scaffold(
      backgroundColor: LocalDatabaseService.colorSettings.darkBackgroundColor,
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: screenPaddingH),
        child: Column(
          children: <Widget>[
            BlockSemantics(child: header),
            board,
            if (LocalDatabaseService.display.isHistoryNavigationToolbarShown)
              historyNavToolbar,
            toolbar,
          ],
        ),
      ),
      /*
      body: Column(children: <Widget>[
        header,
        ScreenRecorder(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.width,
          controller: screenRecorderController,
          child: board,
        ),
        toolbar
      ]),
      */
    );
  }

  @override
  void dispose() {
    debugPrint("$tag dispose");
    disposed = true;
    _engine.shutdown();
    _animationController.dispose();
    routeObserver.unsubscribe(this);
    LocalDatabaseService.listenPreferences.removeListener(_refeshEngine);
    super.dispose();
  }

  @override
  void didPush() {
    final route = ModalRoute.of(context)!.settings.name;
    debugPrint('$tag Game Page didPush route: $route');
  }

  @override
  void didPopNext() {
    final route = ModalRoute.of(context)!.settings.name;
    debugPrint('$tag Game Page didPopNext route: $route');
  }

  @override
  void didPushNext() {
    final route = ModalRoute.of(context)!.settings.name;
    debugPrint('$tag Game Page didPushNext route: $route');
  }

  @override
  void didPop() {
    final route = ModalRoute.of(context)!.settings.name;
    debugPrint('$tag Game Page didPop route: $route');
  }
}
