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
import 'package:stack_trace/stack_trace.dart';

import 'board.dart';
import 'game_settings_page.dart';

class GamePage extends StatefulWidget {
  static double boardMargin = AppTheme.boardMargin;
  static double screenPaddingH = AppTheme.boardScreenPaddingH;

  final EngineType engineType;
  final Engine engine;

  GamePage(this.engineType) : engine = NativeEngine();

  @override
  _GamePageState createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with RouteAware {
  String? _tip = '';
  bool isReady = false;
  late Timer timer;

  @override
  void initState() {
    print("Engine type: ${widget.engineType}");

    Game.instance.setWhoIsAi(widget.engineType);

    super.initState();
    Game.instance.init();
    widget.engine.startup();

    timer = Timer.periodic(Duration(microseconds: 100), (Timer t) {
      _setReadyState();
    });
  }

  _setReadyState() async {
    print("Check if need to set Ready state...");
    if (!isReady && mounted && Config.settingsLoaded) {
      print("Set Ready State...");
      setState(() {});
      isReady = true;
      timer.cancel();
    }
  }

  showTip(String? tip) {
    if (!mounted) return;
    if (tip != null) print("Tip: $tip");

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
      print("Not ready, ignore tapping.");
      return false;
    }

    if (Game.instance.engineType == EngineType.aiVsAi ||
        Game.instance.engineType == EngineType.testViaLAN) {
      print("Engine type is no human, ignore tapping.");
      return false;
    }

    final position = Game.instance.position;

    int? sq = indexToSquare[index];

    if (sq == null) {
      print("sq is null, skip tapping.");
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
          print("AI is thinking, skip tapping.");
          return false;
        } else {
          print("AI is not thinking. AI is to move.");
          engineToGo();
          return false;
        }
      }
    }

    if (Game.instance.isAiToMove() || Game.instance.aiIsSearching()) {
      print("AI's turn, skip tapping.");
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
            print("putPiece: [$sq]");
            break;
          } else {
            print("putPiece: skip [$sq]");
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
              print("selectPiece: [$sq]");

              var us = Game.instance.sideToMove;
              if (position.phase == Phase.moving &&
                  rule.mayFly &&
                  Game.instance.position.pieceOnBoardCount[us] == 3) {
                print("May fly.");
                if (mounted) {
                  showTip(S.of(context).tipCanMoveToAnyPoint);
                }
              } else if (mounted) {
                showTip(S.of(context).tipPlace);
              }

              break;
            case -2:
              Audios.playTone(Audios.illegalSoundId);
              print("selectPiece: skip [$sq]");
              if (mounted && position.phase != Phase.gameOver) {
                showTip(S.of(context).tipCannotMove);
              }
              break;
            case -3:
              Audios.playTone(Audios.illegalSoundId);
              print("selectPiece: skip [$sq]");
              if (mounted) {
                showTip(S.of(context).tipCanMoveOnePoint);
              }
              break;
            case -4:
              Audios.playTone(Audios.illegalSoundId);
              print("selectPiece: skip [$sq]");
              if (mounted) {
                showTip(S.of(context).tipSelectPieceToMove);
              }
              break;
            default:
              Audios.playTone(Audios.illegalSoundId);
              print("selectPiece: skip [$sq]");
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
              print("removePiece: [$sq]");
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
              print("removePiece: Cannot Remove our pieces, skip [$sq]");
              if (mounted) {
                showTip(S.of(context).tipSelectOpponentsPiece);
              }
              break;
            case -3:
              Audios.playTone(Audios.illegalSoundId);
              print("removePiece: Cannot remove piece from Mill, skip [$sq]");
              if (mounted) {
                showTip(S.of(context).tipCannotRemovePieceFromMill);
              }
              break;
            default:
              Audios.playTone(Audios.illegalSoundId);
              print("removePiece: skip [$sq]");
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
        position.recorder.moveIn(m, position);

        setState(() {});

        if (position.winner == PieceColor.nobody) {
          engineToGo();
        } else {
          showTips();
        }
      }

      Game.instance.sideToMove = position.sideToMove() ?? PieceColor.nobody;

      setState(() {});
    });

    return ret;
  }

  engineToGo() async {
    if (!mounted) {
      print("!mounted, skip engineToGo.");
      return;
    }

    // TODO
    print("Engine to go, engine type is ${widget.engineType}");

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

      print("Searching...");
      final response = await widget.engine.search(Game.instance.position);
      print("Engine response type: ${response.type}");

      switch (response.type) {
        case 'move':
          Move mv = response.value;
          final Move move = new Move(mv.move);

          Game.instance.doMove(move.move);
          showTips();
          break;
        case 'timeout':
          if (mounted) {
            showTip(S.of(context).timeout);
          }

          if (Config.developerMode) {
            assert(false);
          }
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

  newGame() {
    confirm() {
      Navigator.of(context).pop();
      Game.instance.newGame();
      if (mounted) {
        showTip(S.of(context).gameStarted);
      }

      if (Game.instance.isAiToMove()) {
        print("New game, AI to move.");
        engineToGo();
      }
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          children: <Widget>[
            SimpleDialogOption(
                child: Text(
                  S.of(context).startNewGame,
                  style: AppTheme.simpleDialogOptionTextStyle,
                ),
                onPressed: confirm),
          ],
        );
      },
    );
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

    print("Game over reason: ${Game.instance.position.gameOverReason}");

    String? loseReasonStr = reasonMap[Game.instance.position.gameOverReason];

    if (loseReasonStr == null) {
      loseReasonStr = S.of(context).gameOverUnknownReason;
      print("Game over reason string: $loseReasonStr");
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
                style: TextStyle(color: AppTheme.dialogTitleColor)),
            content: Text(contentStr),
            actions: <Widget>[
              TextButton(
                  child: Text(S.of(context).yes),
                  onPressed: () {
                    if (!isTopLevel) Config.skillLevel++;
                    Config.save();
                    Navigator.of(context).pop();
                  }),
              TextButton(
                  child: Text(S.of(context).no),
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
                style: TextStyle(color: AppTheme.dialogTitleColor)),
            content: Text(getGameOverReasonString(
                Game.instance.position.gameOverReason,
                Game.instance.position.winner)),
            actions: <Widget>[
              TextButton(
                  child: Text(S.of(context).restart),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Game.instance.newGame();
                    if (mounted) {
                      showTip(S.of(context).gameStarted);
                    }

                    if (Game.instance.isAiToMove()) {
                      print("New game, AI to move.");
                      engineToGo();
                    }
                  }),
              TextButton(
                  child: Text(S.of(context).cancel),
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
            child: Text(_tip!, maxLines: 1, style: AppTheme.gamePageTipStyle),
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
          iconArrow = Icons.toggle_off_outlined;
          break;
        case PieceColor.black:
          iconArrow = Icons.toggle_on_outlined;
          break;
        default:
          iconArrow = Icons.view_agenda;
          break;
      }
    } else {
      switch (Game.instance.sideToMove) {
        case PieceColor.white:
          iconArrow = Icons.keyboard_arrow_left;
          break;
        case PieceColor.black:
          iconArrow = Icons.keyboard_arrow_right;
          break;
        default:
          iconArrow = Icons.code;
          break;
      }
    }

    return iconArrow;
  }

  Widget createBoard() {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: GamePage.screenPaddingH,
        vertical: GamePage.boardMargin,
      ),
      child: Board(
        width: MediaQuery.of(context).size.width - GamePage.screenPaddingH * 2,
        onBoardTap: onBoardTap,
      ),
    );
  }

  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
    final moveHistoryText = Game.instance.position.moveHistoryText;

    final analyzeText = getInfoText();

    var newGameButton = TextButton(
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
      onPressed: newGame,
    );

    var undoButton = TextButton(
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
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => GameSettingsPage()),
        );
      },
    );

    var moveHistoryButton = TextButton(
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
      onPressed: () => showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: AppTheme.moveHistoryDialogBackgroundColor,
            title: Text(S.of(context).moveList,
                style: TextStyle(color: AppTheme.moveHistoryTextColor)),
            content: SingleChildScrollView(
                child: Text(moveHistoryText,
                    style: AppTheme.moveHistoryTextStyle)),
            actions: <Widget>[
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
      ),
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
      onPressed: () => showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: AppTheme.infoDialogackgroundColor,
            content: SingleChildScrollView(
                child: Text(analyzeText, style: AppTheme.moveHistoryTextStyle)),
            actions: <Widget>[
              TextButton(
                child: Text(S.of(context).ok,
                    style: AppTheme.moveHistoryTextStyle),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      ),
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
        newGameButton,
        Expanded(child: SizedBox()),
        undoButton,
        Expanded(child: SizedBox()),
        moveHistoryButton,
        Expanded(child: SizedBox()), //dashboard_outlined
        infoButton,
        Expanded(child: SizedBox()),
      ]),
    );
  }

  Widget buildMoveHistoryPanel(String text) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 16),
        child: SingleChildScrollView(
            child: Text(text, style: AppTheme.moveHistoryTextStyle)),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute<dynamic>);
  }

  @override
  Widget build(BuildContext context) {
    calcScreenPaddingH();

    final header = createPageHeader();
    final board = createBoard();
    final toolbar = createToolbar();

    return Scaffold(
      backgroundColor: Color(Config.darkBackgroundColor),
      body: Column(children: <Widget>[header, board, toolbar]),
    );
  }

  @override
  void dispose() {
    print("dipose");
    widget.engine.shutdown();
    super.dispose();
    routeObserver.unsubscribe(this);
  }

  @override
  void didPush() {
    final route = ModalRoute.of(context)!.settings.name;
    print('Game Page didPush route: $route');
    widget.engine.setOptions();
  }

  @override
  void didPopNext() {
    final route = ModalRoute.of(context)!.settings.name;
    print('Game Page didPopNext route: $route');
    widget.engine.setOptions();
  }

  @override
  void didPushNext() {
    final route = ModalRoute.of(context)!.settings.name;
    print('Game Page didPushNext route: $route');
    widget.engine.setOptions();
  }

  @override
  void didPop() {
    final route = ModalRoute.of(context)!.settings.name;
    print('Game Page didPop route: $route');
  }
}
