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

import 'dart:async';

//import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sanmill/common/config.dart';
import 'package:sanmill/engine/engine.dart';
import 'package:sanmill/engine/native_engine.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/main.dart';
import 'package:sanmill/mill/game.dart';
import 'package:sanmill/mill/position.dart';
import 'package:sanmill/mill/rule.dart';
import 'package:sanmill/mill/types.dart';
import 'package:sanmill/services/audios.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/widgets/game_settings_page.dart';
//import 'package:screen_recorder/screen_recorder.dart';
import 'package:stack_trace/stack_trace.dart';

import 'board.dart';
import 'dialog.dart';
import 'game_settings_page.dart';
import 'picker.dart';

double boardWidth = 0.0;

class GamePage extends StatefulWidget {
  static double boardMargin = AppTheme.boardMargin;
  static double screenPaddingH = AppTheme.boardScreenPaddingH;

  final EngineType engineType;
  final Engine engine;

  GamePage(this.engineType) : engine = NativeEngine();

  @override
  _GamePageState createState() => _GamePageState();
}

class _GamePageState extends State<GamePage>
    with RouteAware, SingleTickerProviderStateMixin {
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
  late Animation animation;
  bool disposed = false;
  bool ltr = true;
  final String tag = "[game_page]";

  @override
  void initState() {
    print("$tag Engine type: ${widget.engineType}");

    Game.instance.setWhoIsAi(widget.engineType);

    super.initState();
    Game.instance.init();
    widget.engine.startup();

    timer = Timer.periodic(Duration(microseconds: 100), (Timer t) {
      _setReadyState();
    });

    _initAnimation();
  }

  _setReadyState() async {
    print("$tag Check if need to set Ready state...");
    if (!isReady && mounted && Config.settingsLoaded) {
      print("$tag Set Ready State...");
      setState(() {});
      isReady = true;
      timer.cancel();

      if (Localizations.localeOf(context).languageCode == "zh" &&
          !Config.isPrivacyPolicyAccepted) {
        onShowPrivacyDialog();
      }
    }
  }

  _initAnimation() {
    _animationController = AnimationController(
      vsync: this,
      duration:
          Duration(milliseconds: (Config.animationDuration * 1000).toInt()),
    );
    _animationController.addListener(() {});

    animation = Tween(
      begin: 1.27, // sqrt(1.618) = 1.272
      end: 1.0,
    ).animate(_animationController)
      ..addListener(() {
        setState(() {});
      });

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

  showTip(String? tip) {
    if (!mounted) return;
    if (tip != null) print("[tip] $tip");

    setState(() => _tip = tip);
  }

  void showTips() {
    if (!mounted) {
      return;
    }

    final winner = Game.instance.position.winner;

    Map<String, String> colorWinStrings = {
      PieceColor.white: S.of(context).whiteWin,
      PieceColor.black: S.of(context).blackWin,
      PieceColor.draw: S.of(context).draw
    };

    if (winner == PieceColor.nobody) {
      if (Game.instance.position.phase == Phase.placing) {
        if (mounted) {
          showTip(S.of(context).tipPlace);
        }
      } else if (Game.instance.position.phase == Phase.moving) {
        if (mounted) {
          showTip(S.of(context).tipMove);
        }
      }
    } else {
      if (mounted) {
        showTip(colorWinStrings[winner]);
      }
    }

    if (!Config.isAutoRestart) {
      showGameResult(winner);
    }
  }

  onBoardTap(BuildContext context, int index) {
    if (!isReady) {
      print("[tap] Not ready, ignore tapping.");
      return false;
    }

    disposed = false;
    _animationController.duration =
        Duration(milliseconds: (Config.animationDuration * 1000).toInt());
    _animationController.reset();

    if (Game.instance.engineType == EngineType.aiVsAi ||
        Game.instance.engineType == EngineType.testViaLAN) {
      print("$tag Engine type is no human, ignore tapping.");
      return false;
    }

    final position = Game.instance.position;

    int? sq = indexToSquare[index];

    if (sq == null) {
      print("$tag sq is null, skip tapping.");
      return;
    }

    // TODO
    // WAR: Fix first tap response slow when piece count changed
    if (position.phase == Phase.placing &&
        position.pieceOnBoardCount[PieceColor.white] == 0 &&
        position.pieceOnBoardCount[PieceColor.black] == 0) {
      Game.instance.newGame();

      if (Game.instance.isAiToMove()) {
        if (Game.instance.aiIsSearching()) {
          print("$tag AI is thinking, skip tapping.");
          return false;
        } else {
          print("[tap] AI is not thinking. AI is to move.");
          engineToGo(false);
          return false;
        }
      }
    }

    if (Game.instance.isAiToMove() || Game.instance.aiIsSearching()) {
      print("[tap] AI's turn, skip tapping.");
      return false;
    }

    if (position.phase == Phase.ready) {
      Game.instance.start();
    }

    bool ret = false;
    Chain.capture(() {
      switch (position.action) {
        case Act.place:
          if (position.putPiece(sq)) {
            if (position.action == Act.remove) {
              //Audios.playTone(Audios.millSoundId);
              if (mounted) {
                showTip(S.of(context).tipMill);
              }
            } else {
              //Audios.playTone(Audios.placeSoundId);
              if (Game.instance.engineType == EngineType.humanVsAi && mounted) {
                showTip(S.of(context).tipPlaced);
              } else if (mounted) {
                var side = Game.instance.sideToMove == PieceColor.white
                    ? S.of(context).black
                    : S.of(context).white;
                showTip(side + S.of(context).tipToMove);
              }
            }
            ret = true;
            print("[tap] putPiece: [$sq]");
            break;
          } else {
            print("[tap] putPiece: skip [$sq]");
            if (mounted) {
              showTip(S.of(context).tipBanPlace);
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
            }
            break;
          }
          int selectRet = position.selectPiece(sq);
          switch (selectRet) {
            case 0:
              Audios.playTone(Audios.selectSoundId);
              Game.instance.select(index);
              ret = true;
              print("[tap] selectPiece: [$sq]");

              var us = Game.instance.sideToMove;
              if (position.phase == Phase.moving &&
                  rule.mayFly &&
                  Game.instance.position.pieceOnBoardCount[us] == 3) {
                print("[tap] May fly.");
                if (mounted) {
                  showTip(S.of(context).tipCanMoveToAnyPoint);
                }
              } else if (mounted) {
                showTip(S.of(context).tipPlace);
              }

              break;
            case -2:
              Audios.playTone(Audios.illegalSoundId);
              print("[tap] selectPiece: skip [$sq]");
              if (mounted && position.phase != Phase.gameOver) {
                showTip(S.of(context).tipCannotMove);
              }
              break;
            case -3:
              Audios.playTone(Audios.illegalSoundId);
              print("[tap] selectPiece: skip [$sq]");
              if (mounted) {
                showTip(S.of(context).tipCanMoveOnePoint);
              }
              break;
            case -4:
              Audios.playTone(Audios.illegalSoundId);
              print("[tap] selectPiece: skip [$sq]");
              if (mounted) {
                showTip(S.of(context).tipSelectPieceToMove);
              }
              break;
            default:
              Audios.playTone(Audios.illegalSoundId);
              print("[tap] selectPiece: skip [$sq]");
              if (mounted) {
                showTip(S.of(context).tipSelectWrong);
              }
              break;
          }

          break;

        case Act.remove:
          int removeRet = position.removePiece(sq);

          switch (removeRet) {
            case 0:
              //Audios.playTone(Audios.removeSoundId);
              ret = true;
              print("[tap] removePiece: [$sq]");
              if (Game.instance.position.pieceToRemoveCount >= 1) {
                if (mounted) {
                  showTip(S.of(context).tipContinueMill);
                }
              } else {
                if (Game.instance.engineType == EngineType.humanVsAi) {
                  if (mounted) {
                    showTip(S.of(context).tipRemoved);
                  }
                } else {
                  if (mounted) {
                    var them = Game.instance.sideToMove == PieceColor.white
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
              Audios.playTone(Audios.illegalSoundId);
              print("[tap] removePiece: Cannot Remove our pieces, skip [$sq]");
              if (mounted) {
                showTip(S.of(context).tipSelectOpponentsPiece);
              }
              break;
            case -3:
              Audios.playTone(Audios.illegalSoundId);
              print(
                  "[tap] removePiece: Cannot remove piece from Mill, skip [$sq]");
              if (mounted) {
                showTip(S.of(context).tipCannotRemovePieceFromMill);
              }
              break;
            default:
              Audios.playTone(Audios.illegalSoundId);
              print("[tap] removePiece: skip [$sq]");
              if (mounted && position.phase != Phase.gameOver) {
                showTip(S.of(context).tipBanRemove);
              }
              break;
          }

          break;

        default:
          break;
      }

      if (ret) {
        Game.instance.sideToMove = position.sideToMove() ?? PieceColor.nobody;
        Game.instance.moveHistory.add(position.record);

        // TODO: Need Others?
        // Increment ply counters. In particular,
        // rule50 will be reset to zero later on
        // in case of a remove.
        ++position.gamePly;
        ++position.st.rule50;
        ++position.st.pliesFromNull;

        if (position.record.length > "-(1,2)".length) {
          if (posKeyHistory.length == 0 ||
              (posKeyHistory.length > 0 &&
                  position.st.key != posKeyHistory[posKeyHistory.length - 1])) {
            posKeyHistory.add(position.st.key);
            if (position.hasGameCycle()) {
              position.setGameOver(PieceColor.draw,
                  GameOverReason.drawReasonThreefoldRepetition);
            }
          }
        } else {
          posKeyHistory.clear();
        }

        //position.move = m;

        Move m = Move(position.record);
        position.recorder.prune();
        position.recorder.moveIn(m, position);

        setState(() {});

        if (position.winner == PieceColor.nobody) {
          engineToGo(false);
        } else {
          showTips();
        }
      }

      Game.instance.sideToMove = position.sideToMove() ?? PieceColor.nobody;

      setState(() {});
    });

    return ret;
  }

  engineToGo(bool isMoveNow) async {
    if (!mounted) {
      print("[engineToGo] !mounted, skip engineToGo.");
      return;
    }

    // TODO
    print("[engineToGo] engine type is ${widget.engineType}");

    if (isMoveNow == true) {
      if (!Game.instance.isAiToMove()) {
        print("[engineToGo] Human to Move. Cannot get search result now.");
        showSnackBar(S.of(context).notAIsTurn);
        return;
      }
      if (!Game.instance.position.recorder.isClean()) {
        print(
            "[engineToGo] History is not clean. Cannot get search result now.");
        showSnackBar(S.of(context).aiIsNotThinking);
        return;
      }
    }

    while ((Config.isAutoRestart == true ||
            Game.instance.position.winner == PieceColor.nobody) &&
        Game.instance.isAiToMove() &&
        mounted) {
      if (widget.engineType == EngineType.aiVsAi) {
        String score =
            Game.instance.position.score[PieceColor.white].toString() +
                " : " +
                Game.instance.position.score[PieceColor.black].toString() +
                " : " +
                Game.instance.position.score[PieceColor.draw].toString();

        showTip(score);
      } else {
        if (mounted) {
          showTip(S.of(context).thinking);
        }
      }

      late var response;

      if (!isMoveNow) {
        print("[engineToGo] Searching...");
        response = await widget.engine.search(Game.instance.position);
      } else {
        print("[engineToGo] Get search result now...");
        response = await widget.engine.search(null);
        isMoveNow = false;
      }

      print("[engineToGo] Engine response type: ${response.type}");

      switch (response.type) {
        case 'move':
          Move mv = response.value;
          final Move move = new Move(mv.move);

          _animationController.duration =
              Duration(milliseconds: (Config.animationDuration * 1000).toInt());

          if (!disposed) {
            _animationController.reset();
          } else {
            print(
                "[engineToGo] Disposed, so do not reset animationController.");
          }

          Game.instance.doMove(move.move);
          showTips();
          break;
        case 'timeout':
          if (mounted) {
            showTip(S.of(context).timeout);
          }

          //if (Config.developerMode) {
          //assert(false);
          //}
          return;
        default:
          showTip('Error: ${response.type}');
          break;
      }

      if (Config.isAutoRestart == true &&
          Game.instance.position.winner != PieceColor.nobody) {
        Game.instance.newGame();
      }
    }
  }

  onStartNewGameButtonPressed() async {
    Navigator.of(context).pop();
    Game.instance.newGame();
    if (mounted) {
      showTip(S.of(context).gameStarted);
    }

    if (Game.instance.isAiToMove()) {
      print("$tag New game, AI to move.");
      engineToGo(false);
    }
  }

  /*
  onStartRecordingButtonPressed() async {
    Navigator.of(context).pop();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text(
          S.of(context).appName,
          style: TextStyle(
            color: AppTheme.dialogTitleColor,
            fontSize: Config.fontSize + 4,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              S.of(context).experimental,
              style: TextStyle(
                fontSize: Config.fontSize,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            child: Text(
              S.of(context).ok,
              style: TextStyle(
                fontSize: Config.fontSize,
              ),
            ),
            onPressed: () => Navigator.of(context).pop(),
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
    Navigator.of(context).pop();
    screenRecorderController.stop();
    showSnackBar(
      S.of(context).stopRecording,
      duration: Duration(seconds: 2),
    );
  }

  onShowRecordingButtonPressed() async {
    Navigator.of(context).pop();
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

  onAutoReplayButtonPressed() async {
    Navigator.of(context).pop();

    await onTakeBackAllButtonPressed(pop: false);
    await onStepForwardAllButtonPressed(pop: false);
  }

  onGameButtonPressed() {
    //showModalBottomSheet(
    showDialog(
      context: context,
      //backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return SimpleDialog(
          backgroundColor: Colors.transparent,
          children: <Widget>[
            SimpleDialogOption(
              child: Text(
                S.of(context).startNewGame,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
              onPressed: onStartNewGameButtonPressed,
            ),
            /*
            SizedBox(height: AppTheme.sizedBoxHeight),
            Config.experimentsEnabled
                ? SimpleDialogOption(
                    child: Text(
                      S.of(context).startRecording,
                      style: AppTheme.simpleDialogOptionTextStyle,
                      textAlign: TextAlign.center,
                    ),
                    onPressed: onStartRecordingButtonPressed,
                  )
                : SizedBox(height: 1),
            Config.experimentsEnabled
                ? SizedBox(height: AppTheme.sizedBoxHeight)
                : SizedBox(height: 1),
            Config.experimentsEnabled
                ? SimpleDialogOption(
                    child: Text(
                      S.of(context).stopRecording,
                      style: AppTheme.simpleDialogOptionTextStyle,
                      textAlign: TextAlign.center,
                    ),
                    onPressed: onStopRecordingButtonPressed,
                  )
                : SizedBox(height: 1),
            Config.experimentsEnabled
                ? SizedBox(height: AppTheme.sizedBoxHeight)
                : SizedBox(height: 1),
            Config.experimentsEnabled
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
        );
      },
    );
  }

  onOptionButtonPressed() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => GameSettingsPage()),
    );
  }

  onMoveButtonPressed() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return SimpleDialog(
          backgroundColor: Colors.transparent,
          children: <Widget>[
            SimpleDialogOption(
              child: Text(
                S.of(context).takeBack,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
              onPressed: onTakeBackButtonPressed,
            ),
            SizedBox(height: AppTheme.sizedBoxHeight),
            SimpleDialogOption(
              child: Text(
                S.of(context).stepForward,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
              onPressed: onStepForwardButtonPressed,
            ),
            SizedBox(height: AppTheme.sizedBoxHeight),
            SimpleDialogOption(
              child: Text(
                S.of(context).takeBackAll,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
              onPressed: onTakeBackAllButtonPressed,
            ),
            SizedBox(height: AppTheme.sizedBoxHeight),
            SimpleDialogOption(
              child: Text(
                S.of(context).stepForwardAll,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
              onPressed: onStepForwardAllButtonPressed,
            ),
            SizedBox(height: AppTheme.sizedBoxHeight),
            SimpleDialogOption(
              child: Text(
                S.of(context).showMoveList,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
              onPressed: onMoveListButtonPressed,
            ),
            SizedBox(height: AppTheme.sizedBoxHeight),
            SimpleDialogOption(
              child: Text(
                S.of(context).moveNow,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
              onPressed: onMoveNowButtonPressed,
            ),
          ],
        );
      },
    );
  }

  onGotoHistoryButtonsPressed(var func, {bool pop = true}) async {
    if (pop == true) {
      Navigator.of(context).pop();
    }

    if (mounted) {
      showTip(S.of(context).waiting);
    }

    if (isGoingToHistory) {
      print("[TakeBack] Is going to history, ignore Take Back button press.");
      return;
    }

    isGoingToHistory = true;

    Audios.isTemporaryMute = Config.keepMuteWhenTakingBack;

    if (await func == false) {
      showSnackBar(S.of(context).atEnd);
    }

    Audios.isTemporaryMute = false;

    isGoingToHistory = false;

    if (mounted) {
      showTip(S.of(context).done);
    }
  }

  onTakeBackButtonPressed({bool pop = true}) async {
    onGotoHistoryButtonsPressed(Game.instance.position.takeBack(), pop: pop);
  }

  onStepForwardButtonPressed({bool pop = true}) async {
    onGotoHistoryButtonsPressed(Game.instance.position.stepForward(), pop: pop);
  }

  onTakeBackAllButtonPressed({bool pop = true}) async {
    onGotoHistoryButtonsPressed(Game.instance.position.takeBackAll(), pop: pop);
  }

  onStepForwardAllButtonPressed({bool pop = true}) async {
    onGotoHistoryButtonsPressed(Game.instance.position.stepForwardAll(),
        pop: pop);
  }

  onTakeBackNButtonPressed(int n, {bool pop = true}) async {
    onGotoHistoryButtonsPressed(Game.instance.position.takeBackN(n), pop: pop);
  }

  onMoveListButtonPressed() {
    final moveHistoryText = Game.instance.position.moveHistoryText;
    var end = Game.instance.moveHistory.length - 1;
    Navigator.of(context).pop();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.moveHistoryDialogBackgroundColor,
          title: Text(S.of(context).moveList,
              style: TextStyle(
                color: AppTheme.moveHistoryTextColor,
                fontSize: Config.fontSize + 2.0,
              )),
          content: SingleChildScrollView(
            child: Text(
              moveHistoryText,
              style: AppTheme.moveHistoryTextStyle,
              textDirection: TextDirection.ltr,
            ),
          ),
          actions: <Widget>[
            end > 0
                ? TextButton(
                    child: Text(S.of(context).rollback,
                        style: AppTheme.moveHistoryTextStyle),
                    onPressed: () async {
                      int selectValue = await showPickerNumber(
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
                : TextButton(
                    child: Text(""),
                    onPressed: () => Navigator.of(context).pop()),
            TextButton(
              child: Text(S.of(context).copy,
                  style: AppTheme.moveHistoryTextStyle),
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: moveHistoryText))
                      .then((_) {
                showSnackBar(S.of(context).moveHistoryCopied);
              }),
            ),
            TextButton(
              child: Text(S.of(context).cancel,
                  style: AppTheme.moveHistoryTextStyle),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  onMoveNowButtonPressed() async {
    Navigator.of(context).pop();
    await engineToGo(true);
  }

  onInfoButtonPressed() {
    final analyzeText = getInfoText();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.infoDialogBackgroundColor,
          content: SingleChildScrollView(
              child: Text(analyzeText, style: AppTheme.moveHistoryTextStyle)),
          actions: <Widget>[
            TextButton(
              child:
                  Text(S.of(context).ok, style: AppTheme.moveHistoryTextStyle),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  setPrivacyPolicyAccepted(bool value) async {
    setState(() {
      Config.isPrivacyPolicyAccepted = value;
    });

    print("[config] isPrivacyPolicyAccepted: $value");

    Config.save();
  }

  onShowPrivacyDialog() async {
    showPrivacyDialog(context, setPrivacyPolicyAccepted);
  }

  String getGameOverReasonString(GameOverReason? reason, String? winner) {
    //String winnerStr =
    //    winner == Color.white ? S.of(context).white : S.of(context).black;
    String loserStr =
        winner == PieceColor.white ? S.of(context).black : S.of(context).white;

    Map<GameOverReason, String> reasonMap = {
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
      GameOverReason.drawReasonBoardIsFull: S.of(context).drawReasonBoardIsFull,
      GameOverReason.drawReasonThreefoldRepetition:
          S.of(context).drawReasonThreefoldRepetition,
    };

    print("$tag Game over reason: ${Game.instance.position.gameOverReason}");

    String? loseReasonStr = reasonMap[Game.instance.position.gameOverReason];

    if (loseReasonStr == null) {
      loseReasonStr = S.of(context).gameOverUnknownReason;
      print("$tag Game over reason string: $loseReasonStr");
      if (Config.developerMode) {
        assert(false);
      }
    }

    return loseReasonStr;
  }

  GameResult getGameResult(var winner) {
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

  void showGameResult(var winner) {
    GameResult result = getGameResult(winner);
    Game.instance.position.result = result;

    switch (result) {
      case GameResult.win:
        //Audios.playTone(Audios.winSoundId);
        break;
      case GameResult.lose:
        //Audios.playTone(Audios.loseSoundId);
        break;
      case GameResult.draw:
        break;
      default:
        break;
    }

    Map<GameResult, String> retMap = {
      GameResult.win: Game.instance.engineType == EngineType.humanVsAi
          ? S.of(context).youWin
          : S.of(context).gameOver,
      GameResult.lose: S.of(context).gameOver,
      GameResult.draw: S.of(context).draw
    };

    var dialogTitle = retMap[result];

    if (dialogTitle == null) {
      return;
    }

    bool isTopLevel = (Config.skillLevel == 20); // TODO: 20

    if (result == GameResult.win &&
        !isTopLevel &&
        Game.instance.engineType == EngineType.humanVsAi) {
      var contentStr = getGameOverReasonString(
          Game.instance.position.gameOverReason, Game.instance.position.winner);

      if (!isTopLevel) {
        contentStr += "\n\n" +
            S.of(context).challengeHarderLevel +
            (Config.skillLevel + 1).toString() +
            "!";
      }

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(dialogTitle,
                style: TextStyle(
                  color: AppTheme.dialogTitleColor,
                  fontSize: Config.fontSize + 4,
                )),
            content: Text(
              contentStr,
              style: TextStyle(
                fontSize: Config.fontSize,
              ),
            ),
            actions: <Widget>[
              TextButton(
                  child: Text(
                    S.of(context).yes,
                    style: TextStyle(
                      fontSize: Config.fontSize,
                    ),
                  ),
                  onPressed: () {
                    if (!isTopLevel) Config.skillLevel++;
                    Config.save();
                    print("[config] skillLevel: ${Config.skillLevel}");
                    Navigator.of(context).pop();
                  }),
              TextButton(
                  child: Text(
                    S.of(context).no,
                    style: TextStyle(
                      fontSize: Config.fontSize,
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop()),
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
            title: Text(dialogTitle,
                style: TextStyle(
                  color: AppTheme.dialogTitleColor,
                  fontSize: Config.fontSize + 4,
                )),
            content: Text(
              getGameOverReasonString(Game.instance.position.gameOverReason,
                  Game.instance.position.winner),
              style: TextStyle(
                fontSize: Config.fontSize,
              ),
            ),
            actions: <Widget>[
              TextButton(
                  child: Text(
                    S.of(context).restart,
                    style: TextStyle(
                      fontSize: Config.fontSize,
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Game.instance.newGame();
                    if (mounted) {
                      showTip(S.of(context).gameStarted);
                    }

                    if (Game.instance.isAiToMove()) {
                      print("$tag New game, AI to move.");
                      engineToGo(false);
                    }
                  }),
              TextButton(
                  child: Text(
                    S.of(context).cancel,
                    style: TextStyle(
                      fontSize: Config.fontSize,
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop()),
            ],
          );
        },
      );
    }
  }

  void calcScreenPaddingH() {
    //
    // when screen's height/width rate is less than 16/9, limit witdh of board
    final windowSize = MediaQuery.of(context).size;
    double height = windowSize.height, width = windowSize.width;

    if (height / width < 16.0 / 9.0) {
      width = height * 9 / 16;
      GamePage.screenPaddingH =
          (windowSize.width - width) / 2 - AppTheme.boardMargin;
    }
  }

  Widget createPageHeader() {
    Map<EngineType, IconData> engineTypeToIconLeft = {
      EngineType.humanVsAi: Config.aiMovesFirst ? Icons.computer : Icons.person,
      EngineType.humanVsHuman: Icons.person,
      EngineType.aiVsAi: Icons.computer,
      EngineType.humanVsCloud: Icons.person,
      EngineType.humanVsLAN: Icons.person,
      EngineType.testViaLAN: Icons.cast,
    };

    Map<EngineType, IconData> engineTypeToIconRight = {
      EngineType.humanVsAi: Config.aiMovesFirst ? Icons.person : Icons.computer,
      EngineType.humanVsHuman: Icons.person,
      EngineType.aiVsAi: Icons.computer,
      EngineType.humanVsCloud: Icons.cloud,
      EngineType.humanVsLAN: Icons.cast,
      EngineType.testViaLAN: Icons.cast,
    };

    IconData iconArrow = getIconArrow();

    var iconColor = AppTheme.gamePageHeaderIconColor;

    var iconRow = Row(
      children: <Widget>[
        Expanded(child: SizedBox()),
        Icon(engineTypeToIconLeft[widget.engineType], color: iconColor),
        Icon(iconArrow, color: iconColor),
        Icon(engineTypeToIconRight[widget.engineType], color: iconColor),
        Expanded(child: SizedBox()),
      ],
    );

    return Container(
      margin: EdgeInsets.only(top: Config.boardTop),
      child: Column(
        children: <Widget>[
          iconRow,
          Container(
            height: 4,
            width: 180,
            margin: EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Color(Config.boardBackgroundColor),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _tip!,
              maxLines: 1,
              style: TextStyle(
                  fontSize: Config.fontSize, color: Color(Config.messageColor)),
            ), // TODO: Font Size
          ),
        ],
      ),
    );
  }

  IconData getIconArrow() {
    IconData iconArrow = Icons.code;

    if (Game.instance.position.phase == Phase.gameOver) {
      switch (Game.instance.position.winner) {
        case PieceColor.white:
          iconArrow =
              ltr ? Icons.toggle_off_outlined : Icons.toggle_on_outlined;
          break;
        case PieceColor.black:
          iconArrow =
              ltr ? Icons.toggle_on_outlined : Icons.toggle_off_outlined;
          break;
        default:
          iconArrow = Icons.view_agenda;
          break;
      }
    } else {
      switch (Game.instance.sideToMove) {
        case PieceColor.white:
          iconArrow =
              ltr ? Icons.keyboard_arrow_left : Icons.keyboard_arrow_right;
          break;
        case PieceColor.black:
          iconArrow =
              ltr ? Icons.keyboard_arrow_right : Icons.keyboard_arrow_left;
          break;
        default:
          iconArrow = Icons.code;
          break;
      }
    }

    return iconArrow;
  }

  Widget createBoard() {
    boardWidth =
        MediaQuery.of(context).size.width - GamePage.screenPaddingH * 2;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: GamePage.screenPaddingH,
        vertical: GamePage.boardMargin,
      ),
      child: Board(
        width: boardWidth,
        onBoardTap: onBoardTap,
        animationValue: animation.value,
      ),
    );
  }

  void showSnackBar(String message,
      {Duration duration = const Duration(milliseconds: 4000)}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        message,
        style: TextStyle(
          fontSize: Config.fontSize,
        ),
      ),
      duration: duration,
    ));
  }

  String getInfoText() {
    String ret = S.of(context).score +
        "\n" +
        S.of(context).player1 +
        ": " +
        Game.instance.position.score[PieceColor.white].toString() +
        "\n" +
        S.of(context).player2 +
        ": " +
        Game.instance.position.score[PieceColor.black].toString() +
        "\n" +
        S.of(context).draw +
        ": " +
        Game.instance.position.score[PieceColor.draw].toString() +
        "\n\n" +
        S.of(context).pieceCount +
        "\n" +
        S.of(context).player1 +
        " " +
        S.of(context).inHand +
        ": " +
        Game.instance.position.pieceInHandCount[PieceColor.white].toString() +
        "\n" +
        S.of(context).player2 +
        " " +
        S.of(context).inHand +
        ": " +
        Game.instance.position.pieceInHandCount[PieceColor.black].toString() +
        "\n" +
        S.of(context).player1 +
        " " +
        S.of(context).onBoard +
        ": " +
        Game.instance.position.pieceOnBoardCount[PieceColor.white].toString() +
        "\n" +
        S.of(context).player2 +
        " " +
        S.of(context).onBoard +
        ": " +
        Game.instance.position.pieceOnBoardCount[PieceColor.black].toString() +
        "\n";
    return ret;
  }

  Widget createToolbar() {
    var gameButton = TextButton(
      child: Column(
        // Replace with a Row for horizontal icon + text
        children: <Widget>[
          Icon(
            Icons.casino_outlined,
            color: AppTheme.toolbarIconColor,
          ),
          Text(S.of(context).game,
              style: TextStyle(color: AppTheme.toolbarTextColor)),
        ],
      ),
      onPressed: onGameButtonPressed,
    );

    var optionsButton = TextButton(
      child: Column(
        // Replace with a Row for horizontal icon + text
        children: <Widget>[
          Icon(
            Icons.room_preferences_outlined,
            color: AppTheme.toolbarIconColor,
          ),
          Text(S.of(context).options,
              style: TextStyle(color: AppTheme.toolbarTextColor)),
        ],
      ),
      onPressed: onOptionButtonPressed,
    );

    var moveButton = TextButton(
      child: Column(
        // Replace with a Row for horizontal icon + text
        children: <Widget>[
          Icon(
            Icons.list_alt,
            color: AppTheme.toolbarIconColor,
          ),
          Text(S.of(context).move,
              style: TextStyle(color: AppTheme.toolbarTextColor)),
        ],
      ),
      onPressed: onMoveButtonPressed,
    );

    var infoButton = TextButton(
      child: Column(
        // Replace with a Row for horizontal icon + text
        children: <Widget>[
          Icon(
            Icons.lightbulb_outline,
            color: AppTheme.toolbarIconColor,
          ),
          Text(S.of(context).info,
              style: TextStyle(color: AppTheme.toolbarTextColor)),
        ],
      ),
      onPressed: onInfoButtonPressed,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: Color(Config.boardBackgroundColor),
      ),
      margin: EdgeInsets.symmetric(horizontal: GamePage.screenPaddingH),
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(children: <Widget>[
        Expanded(child: SizedBox()),
        gameButton,
        Expanded(child: SizedBox()),
        optionsButton,
        Expanded(child: SizedBox()),
        moveButton,
        Expanded(child: SizedBox()), //dashboard_outlined
        infoButton,
        Expanded(child: SizedBox()),
      ]),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute<dynamic>);
  }

  @override
  Widget build(BuildContext context) {
    Locale currentLocale = Localizations.localeOf(context);
    if (currentLocale.languageCode == "ar" ||
        currentLocale.languageCode == "fa" ||
        currentLocale.languageCode == "he" ||
        currentLocale.languageCode == "ps" ||
        currentLocale.languageCode == "ur") {
      print("Bidirectionality: RTL");
      ltr = false;
    }

    if (_tip == '') {
      _tip = S.of(context).welcome;
    }

    calcScreenPaddingH();

    final header = createPageHeader();
    final board = createBoard();
    final toolbar = createToolbar();

    return Scaffold(
      backgroundColor: Color(Config.darkBackgroundColor),
      body: Column(children: <Widget>[header, board, toolbar]),
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
    print("$tag dispose");
    disposed = true;
    widget.engine.shutdown();
    _animationController.dispose();
    super.dispose();
    routeObserver.unsubscribe(this);
  }

  @override
  void didPush() {
    final route = ModalRoute.of(context)!.settings.name;
    print('$tag Game Page didPush route: $route');
    widget.engine.setOptions();
  }

  @override
  void didPopNext() {
    final route = ModalRoute.of(context)!.settings.name;
    print('$tag Game Page didPopNext route: $route');
    widget.engine.setOptions();
  }

  @override
  void didPushNext() {
    final route = ModalRoute.of(context)!.settings.name;
    print('$tag Game Page didPushNext route: $route');
    widget.engine.setOptions();
  }

  @override
  void didPop() {
    final route = ModalRoute.of(context)!.settings.name;
    print('$tag Game Page didPop route: $route');
  }
}
