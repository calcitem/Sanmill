// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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

import 'dart:ui';

import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:hive_flutter/adapters.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rule_settings.g.dart';

@HiveType(typeId: 4)
enum BoardFullAction {
  @HiveField(0)
  firstPlayerLose,
  @HiveField(1)
  firstAndSecondPlayerRemovePiece,
  @HiveField(2)
  secondAndFirstPlayerRemovePiece,
  @HiveField(3)
  sideToMoveRemovePiece,
  @HiveField(4)
  agreeToDraw,
}

@HiveType(typeId: 10)
enum MillFormationActionInPlacingPhase {
  @HiveField(0)
  removeOpponentsPieceFromBoard,
  @HiveField(1)
  removeOpponentsPieceFromHandThenOpponentsTurn,
  @HiveField(2)
  removeOpponentsPieceFromHandThenYourTurn,
  @HiveField(3)
  opponentRemovesOwnPiece,
  @HiveField(4)
  markAndDelayRemovingPieces,
}

@HiveType(typeId: 8)
enum StalemateAction {
  @HiveField(0)
  endWithStalemateLoss,
  @HiveField(1)
  changeSideToMove,
  @HiveField(2)
  removeOpponentsPieceAndMakeNextMove,
  @HiveField(3)
  removeOpponentsPieceAndChangeSideToMove,
  @HiveField(4)
  endWithStalemateDraw,
}

// Currently unused
String enumName(Object enumEntry) {
  final Map<Object, String> nameMap = <Object, String>{
    BoardFullAction.firstPlayerLose: "0-1",
    BoardFullAction.firstAndSecondPlayerRemovePiece: 'W->B',
    BoardFullAction.secondAndFirstPlayerRemovePiece: 'B->W',
    BoardFullAction.sideToMoveRemovePiece: 'X',
    BoardFullAction.agreeToDraw: '=',
    StalemateAction.endWithStalemateLoss: "0-1",
    StalemateAction.changeSideToMove: '->',
    StalemateAction.removeOpponentsPieceAndMakeNextMove: 'XM',
    StalemateAction.removeOpponentsPieceAndChangeSideToMove: 'X ->',
    StalemateAction.endWithStalemateDraw: '=',
  };

  return nameMap[enumEntry] ?? '';
}

/// Rule Settings data model
///
/// Holds the default rule settings for the Mill game.
/// Currently supported special rule settings include [TwelveMensMorrisRuleSettings].
/// To get the rule settings corresponding to a given local use [RuleSettings.fromLocale].
@HiveType(typeId: 3)
@JsonSerializable()
@CopyWith()
@immutable
class RuleSettings {
  const RuleSettings({
    this.piecesCount = 9,
    this.flyPieceCount = 3,
    this.piecesAtLeastCount = 3,
    this.hasDiagonalLines = false,
    @Deprecated('Use [millFormationActionInPlacingPhase] instead')
    this.hasBannedLocations = false,
    this.mayMoveInPlacingPhase = false,
    this.isDefenderMoveFirst = false,
    this.mayRemoveMultiple = false,
    this.mayRemoveFromMillsAlways = false,
    @Deprecated('Use [millFormationActionInPlacingPhase] instead')
    this.mayOnlyRemoveUnplacedPieceInPlacingPhase = false,
    @Deprecated('Use [boardFullAction] instead')
    this.isWhiteLoseButNotDrawWhenBoardFull = true,
    this.boardFullAction = BoardFullAction.firstPlayerLose,
    @Deprecated('Use [StalemateAction] instead')
    this.isLoseButNotChangeSideWhenNoWay = true,
    this.stalemateAction = StalemateAction.endWithStalemateLoss,
    this.mayFly = true,
    this.nMoveRule = 100,
    this.endgameNMoveRule = 100,
    this.threefoldRepetitionRule = true,
    this.millFormationActionInPlacingPhase =
        MillFormationActionInPlacingPhase.removeOpponentsPieceFromBoard,
    this.restrictRepeatedMillsFormation = false,
    this.oneTimeUseMill = false,
  });

  /// Encodes a Json style map into a [RuleSettings] object
  factory RuleSettings.fromJson(Map<String, dynamic> json) =>
      _$RuleSettingsFromJson(json);

  /// Creates a Rules object based on the given locale
  factory RuleSettings.fromLocale(Locale? locale) {
    switch (locale?.languageCode) {
      case "af": // Afrikaans
      case "zu": // Zulu
        return const MorabarabaRuleSettings();
      case "fa": // Iran
      case "si": // Sri Lanka
        return const TwelveMensMorrisRuleSettings();
      case "ru": // Russia
        return const OneTimeMillRuleSettings();
      case "ko": // Korea
        return const ChamGonuRuleSettings();
      default:
        return const RuleSettings();
    }
  }

  @HiveField(0)
  final int piecesCount;
  @HiveField(1)
  final int flyPieceCount;
  @HiveField(2)
  final int piecesAtLeastCount;
  @HiveField(3)
  final bool hasDiagonalLines;
  @Deprecated('Use [millFormationActionInPlacingPhase] instead')
  @HiveField(4)
  final bool hasBannedLocations;
  @HiveField(5, defaultValue: false)
  final bool mayMoveInPlacingPhase;
  @HiveField(6)
  final bool isDefenderMoveFirst;
  @HiveField(7)
  final bool mayRemoveMultiple;
  @HiveField(8)
  final bool mayRemoveFromMillsAlways;
  @Deprecated('Use [millFormationActionInPlacingPhase] instead')
  @HiveField(9)
  final bool mayOnlyRemoveUnplacedPieceInPlacingPhase;
  @Deprecated('Use [boardFullAction] instead')
  @HiveField(10)
  final bool isWhiteLoseButNotDrawWhenBoardFull;
  @Deprecated('Use [StalemateAction] instead')
  @HiveField(11)
  final bool isLoseButNotChangeSideWhenNoWay;
  @HiveField(12)
  final bool mayFly;
  @HiveField(13)
  final int nMoveRule;
  @HiveField(14)
  final int endgameNMoveRule;
  @HiveField(15)
  final bool threefoldRepetitionRule;
  @HiveField(16, defaultValue: BoardFullAction.firstPlayerLose)
  final BoardFullAction? boardFullAction;
  @HiveField(17, defaultValue: StalemateAction.endWithStalemateLoss)
  final StalemateAction? stalemateAction;
  @HiveField(18,
      defaultValue:
          MillFormationActionInPlacingPhase.removeOpponentsPieceFromBoard)
  final MillFormationActionInPlacingPhase? millFormationActionInPlacingPhase;
  @HiveField(19, defaultValue: false)
  final bool restrictRepeatedMillsFormation;
  @HiveField(20, defaultValue: false)
  final bool oneTimeUseMill;

  /// decodes a Json from a [RuleSettings] object
  Map<String, dynamic> toJson() => _$RuleSettingsToJson(this);

  bool isLikelyNineMensMorris() {
    return piecesCount == 9 &&
        !hasDiagonalLines &&
        !mayMoveInPlacingPhase &&
        !mayOnlyRemoveUnplacedPieceInPlacingPhase &&
        !oneTimeUseMill;
  }
}

// Defines an enumeration of all available rule sets for the Mill Game.
enum RuleSet {
  current,
  nineMensMorris,
  twelveMensMorris,
  morabaraba,
  dooz,
  laskerMorris,
  oneTimeMill,
  chamGonu,
  zhiQi,
  chengSanQi,
  daSanQi,
  mulMulan,
  nerenchi
}

/// Nine Men's Morris Rules
///
/// Those rules are the standard Nine Men's Morris rules.
class NineMensMorrisRuleSettings extends RuleSettings {
  const NineMensMorrisRuleSettings()
      : super(
          piecesCount: 9,
          hasDiagonalLines: false,
        );
}

/// Twelve Men's Morris Rules
///
/// Those rules are the standard Twelve Men's Morris rules.
class TwelveMensMorrisRuleSettings extends RuleSettings {
  const TwelveMensMorrisRuleSettings()
      : super(
          piecesCount: 12,
          hasDiagonalLines: true,
        );
}

/// Morabaraba Rules
///
/// https://en.wikipedia.org/wiki/Morabaraba
/// https://mindsports.nl/index.php/the-pit/542-morabaraba
class MorabarabaRuleSettings extends RuleSettings {
  const MorabarabaRuleSettings()
      : super(
          piecesCount: 12,
          hasDiagonalLines: true,
          boardFullAction: BoardFullAction.agreeToDraw,
          endgameNMoveRule: 10,
          restrictRepeatedMillsFormation: true,
        );
}

/// Dooz Rules
///
/// https://web.archive.org/web/20150919203008/http://dezyan.blogfa.com/post-146.aspx
class DoozRuleSettings extends RuleSettings {
  const DoozRuleSettings()
      : super(
          piecesCount: 12,
          hasDiagonalLines: true,
          millFormationActionInPlacingPhase: MillFormationActionInPlacingPhase
              .removeOpponentsPieceFromHandThenOpponentsTurn,
          boardFullAction: BoardFullAction.sideToMoveRemovePiece,
          mayRemoveFromMillsAlways: true,
        );
}

/// Lasker Morris
///
/// Those rules are the Lasker Morris rules.
class LaskerMorrisSettings extends RuleSettings {
  const LaskerMorrisSettings()
      : super(
          piecesCount: 10,
          mayMoveInPlacingPhase: true,
        );
}

/// Russian One-Time Mill Rules
///
/// Those rules are the One-Time Mill Rules rules.
class OneTimeMillRuleSettings extends RuleSettings {
  const OneTimeMillRuleSettings()
      : super(
          oneTimeUseMill: true,
          mayRemoveFromMillsAlways: true,
        );
}

/// Korean Cham Gonu Rules
///
/// Those rules are the Cham Gonu rules.
class ChamGonuRuleSettings extends RuleSettings {
  const ChamGonuRuleSettings()
      : super(
          piecesCount: 12,
          hasDiagonalLines: true,
          millFormationActionInPlacingPhase:
              MillFormationActionInPlacingPhase.markAndDelayRemovingPieces,
          mayFly: false,
          mayRemoveFromMillsAlways: true,
        );
}

/// Chinese Zhi Qi Rules
///
/// https://zh.wikipedia.org/wiki/%E5%8D%81%E4%BA%8C%E5%AD%90%E7%9B%B4%E6%A3%8B
class ZhiQiRuleSettings extends RuleSettings {
  const ZhiQiRuleSettings()
      : super(
          piecesCount: 12,
          hasDiagonalLines: true,
          millFormationActionInPlacingPhase:
              MillFormationActionInPlacingPhase.markAndDelayRemovingPieces,
          boardFullAction: BoardFullAction.firstAndSecondPlayerRemovePiece,
          mayFly: false,
          mayRemoveFromMillsAlways: true,
        );
}

/// Chinese Cheng San Qi Rules
///
/// https://baike.baidu.com/item/%E6%88%90%E4%B8%89%E6%A3%8B/241145
/// https://blog.csdn.net/liuweilhy/article/details/83832180
class ChengSanQiRuleSettings extends RuleSettings {
  const ChengSanQiRuleSettings()
      : super(
          millFormationActionInPlacingPhase:
              MillFormationActionInPlacingPhase.markAndDelayRemovingPieces,
          mayFly: false,
        );
}

/// Chinese Da San Qi Rules
///
/// https://baike.baidu.com/item/%E6%89%93%E4%B8%89%E6%A3%8B/1766527?fr=ge_ala
/// https://blog.csdn.net/liuweilhy/article/details/83832180
class DaSanQiRuleSettings extends RuleSettings {
  const DaSanQiRuleSettings()
      : super(
          piecesCount: 12,
          hasDiagonalLines: true,
          millFormationActionInPlacingPhase:
              MillFormationActionInPlacingPhase.markAndDelayRemovingPieces,
          boardFullAction: BoardFullAction.firstPlayerLose,
          isDefenderMoveFirst: true,
          mayFly: false,
          mayRemoveFromMillsAlways: true,
          mayRemoveMultiple: true,
        );
}

/// Indonesian Javanese Mul-Mulan Rules
///
/// https://id.wikibooks.org/wiki/Permainan_Tradisional_%22Catur%22_di_Indonesia/Mul-mulan_(Pulau_Jawa)
/// https://id.wikibooks.org/wiki/Permainan_Tradisional_%22Catur%22_di_Indonesia/Derek_Dua_Olas_(Lombok)
/// https://www.researchgate.net/publication/331483882_Adaptasi_Permainan_Tradisional_Mul-Mulan_ke_dalam_Perancangan_Game_Design_Document
/// TODO: Implement the gotong rule.
class MulMulanRuleSettings extends RuleSettings {
  const MulMulanRuleSettings()
      : super(
          hasDiagonalLines: true,
          mayFly: false,
          mayRemoveFromMillsAlways: true,
        );
}

/// Sri Lankan Nerenchi Rules
///
/// https://zh.wikipedia.org/wiki/%E5%8D%81%E4%BA%8C%E5%AD%90%E7%9B%B4%E6%A3%8B
/// https://web.archive.org/web/20150924020646/http://www.gamesmuseum.uwaterloo.ca/VirtualExhibits/rowgames/nerenchi.html
/// https://www.youtube.com/watch?v=9cfaO4GcFSM&ab_channel=HattonNationalBankPLC
/// https://www.youtube.com/watch?v=9nK7gPKtbKc&t=24s&ab_channel=ShalikaWickramasinghe
/// https://www.youtube.com/watch?v=iXYCtguLfUA&t=33s&ab_channel=PantherLk (Not Standard?)
/// TOOD: Each with 12 counters of one color, take turns placing one counter at a time on an empty point, until 22 counters are placed and two points are left empty.
/// TODO: A player making a Nerenchi during the placement phase, takes an extra turn.
class NerenchiRuleSettings extends RuleSettings {
  const NerenchiRuleSettings()
      : super(
          piecesCount: 12,
          hasDiagonalLines: true,
          isDefenderMoveFirst: true,
          mayRemoveFromMillsAlways: true, // TODO: Right?
        );
}

/// Rule Set Descriptions and Settings
const Map<RuleSet, String> ruleSetDescriptions = <RuleSet, String>{
  RuleSet.current: 'Use the current game settings.',
  RuleSet.nineMensMorris: "Classic Nine Men's Morris game.",
  RuleSet.twelveMensMorris: 'Extended version with twelve pieces per player.',
  RuleSet.morabaraba: 'Traditional South African variant, Morabaraba.',
  RuleSet.dooz: 'Persian variant called Dooz.',
  RuleSet.laskerMorris: 'A variation introduced by Emanuel Lasker.',
  RuleSet.oneTimeMill: 'A one-time mill challenge.',
  RuleSet.chamGonu: 'Cham Gonu, a traditional Korean board game.',
  RuleSet.zhiQi: 'Zhi Qi, a historical Chinese mill variant.',
  RuleSet.chengSanQi: 'Cheng San Qi, another Chinese strategic variant.',
  RuleSet.daSanQi: 'Da San Qi, another Chinese strategic variant.',
  RuleSet.mulMulan: 'Mul-Mulan, a Indonesian variation of the game.',
  RuleSet.nerenchi: 'Nerenchi, a Sri Lankan adaptation of the game.',
};

/// Rule Set Properties (e.g., Number of Pieces and Rule Settings)
const Map<RuleSet, RuleSettings> ruleSetProperties = <RuleSet, RuleSettings>{
  RuleSet.current: RuleSettings(),
  RuleSet.nineMensMorris: NineMensMorrisRuleSettings(),
  RuleSet.twelveMensMorris: TwelveMensMorrisRuleSettings(),
  RuleSet.morabaraba: MorabarabaRuleSettings(),
  RuleSet.dooz: DoozRuleSettings(),
  RuleSet.laskerMorris: LaskerMorrisSettings(),
  RuleSet.oneTimeMill: OneTimeMillRuleSettings(),
  RuleSet.chamGonu: ChamGonuRuleSettings(),
  RuleSet.zhiQi: ZhiQiRuleSettings(),
  RuleSet.chengSanQi: ChengSanQiRuleSettings(),
  RuleSet.daSanQi: DaSanQiRuleSettings(),
  RuleSet.mulMulan: MulMulanRuleSettings(),
  RuleSet.nerenchi: NerenchiRuleSettings(),
};
