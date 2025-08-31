// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// special_pieces.dart

part of '../mill.dart';

/// Special pieces available in Zhuolu Chess variant.
/// Each piece has unique abilities triggered during placement, mill formation, or removal.
enum SpecialPiece {
  /// Emperor Huang Di - When placed, converts all adjacent opponent pieces to own pieces
  huangDi,

  /// Drought Demon Nu Ba - When placed, can convert one adjacent opponent piece to own piece
  nuBa,

  /// Flame Emperor Yan Di - When placed, can remove all adjacent opponent pieces
  yanDi,

  /// War God Chi You - When placed, can convert all adjacent empty squares to abandoned squares
  chiYou,

  /// Always First Chang Xian - When placed, can remove any opponent piece on the board
  changXian,

  /// Punishment Heaven Xing Tian - When placed, can remove one adjacent opponent piece
  xingTian,

  /// Fire God Zhu Rong - When forming mill, can additionally remove any opponent piece
  zhuRong,

  /// Rain Master Yu Shi - When forming mill, can convert any empty square to abandoned square
  yuShi,

  /// Wind Empress Feng Hou - Can be placed on abandoned squares
  fengHou,

  /// Flood God Gong Gong - Can ONLY be placed on abandoned squares
  gongGong,

  /// Creator Goddess Nu Wa - When placed, can convert all adjacent abandoned squares to own pieces
  nuWa,

  /// Creator God Fu Xi - When placed, can convert any abandoned square to own piece
  fuXi,

  /// Giant Kua Fu - Cannot be removed by opponent
  kuaFu,

  /// Responding Dragon Ying Long - Cannot be removed when adjacent to own pieces
  yingLong,

  /// Wind Earl Feng Bo - When placed, destroys any opponent piece without leaving abandoned square
  fengBo,
}

/// Extension methods for SpecialPiece enum
extension SpecialPieceExtension on SpecialPiece {
  /// Get the localized name of the special piece
  String localizedName(BuildContext context) {
    final S l10n = S.of(context);
    switch (this) {
      case SpecialPiece.huangDi:
        return l10n.huangDi;
      case SpecialPiece.nuBa:
        return l10n.nuBa;
      case SpecialPiece.yanDi:
        return l10n.yanDi;
      case SpecialPiece.chiYou:
        return l10n.chiYou;
      case SpecialPiece.changXian:
        return l10n.changXian;
      case SpecialPiece.xingTian:
        return l10n.xingTian;
      case SpecialPiece.zhuRong:
        return l10n.zhuRong;
      case SpecialPiece.yuShi:
        return l10n.yuShi;
      case SpecialPiece.fengHou:
        return l10n.fengHou;
      case SpecialPiece.gongGong:
        return l10n.gongGong;
      case SpecialPiece.nuWa:
        return l10n.nuWa;
      case SpecialPiece.fuXi:
        return l10n.fuXi;
      case SpecialPiece.kuaFu:
        return l10n.kuaFu;
      case SpecialPiece.yingLong:
        return l10n.yingLong;
      case SpecialPiece.fengBo:
        return l10n.fengBo;
    }
  }

  /// Get the localized description of the special piece's ability
  String localizedDescription(BuildContext context) {
    final S l10n = S.of(context);
    switch (this) {
      case SpecialPiece.huangDi:
        return l10n.huangDiDescription;
      case SpecialPiece.nuBa:
        return l10n.nuBaDescription;
      case SpecialPiece.yanDi:
        return l10n.yanDiDescription;
      case SpecialPiece.chiYou:
        return l10n.chiYouDescription;
      case SpecialPiece.changXian:
        return l10n.changXianDescription;
      case SpecialPiece.xingTian:
        return l10n.xingTianDescription;
      case SpecialPiece.zhuRong:
        return l10n.zhuRongDescription;
      case SpecialPiece.yuShi:
        return l10n.yuShiDescription;
      case SpecialPiece.fengHou:
        return l10n.fengHouDescription;
      case SpecialPiece.gongGong:
        return l10n.gongGongDescription;
      case SpecialPiece.nuWa:
        return l10n.nuWaDescription;
      case SpecialPiece.fuXi:
        return l10n.fuXiDescription;
      case SpecialPiece.kuaFu:
        return l10n.kuaFuDescription;
      case SpecialPiece.yingLong:
        return l10n.yingLongDescription;
      case SpecialPiece.fengBo:
        return l10n.fengBoDescription;
    }
  }

  /// Get the Chinese name of the special piece
  String get chineseName {
    switch (this) {
      case SpecialPiece.huangDi:
        return '黄帝';
      case SpecialPiece.nuBa:
        return '女魃';
      case SpecialPiece.yanDi:
        return '炎帝';
      case SpecialPiece.chiYou:
        return '蚩尤';
      case SpecialPiece.changXian:
        return '常先';
      case SpecialPiece.xingTian:
        return '刑天';
      case SpecialPiece.zhuRong:
        return '祝融';
      case SpecialPiece.yuShi:
        return '雨师';
      case SpecialPiece.fengHou:
        return '风后';
      case SpecialPiece.gongGong:
        return '共工';
      case SpecialPiece.nuWa:
        return '女娲';
      case SpecialPiece.fuXi:
        return '伏羲';
      case SpecialPiece.kuaFu:
        return '夸父';
      case SpecialPiece.yingLong:
        return '应龙';
      case SpecialPiece.fengBo:
        return '风伯';
    }
  }

  /// Get the English name of the special piece
  String get englishName {
    switch (this) {
      case SpecialPiece.huangDi:
        return 'Yellow Emperor';
      case SpecialPiece.nuBa:
        return 'Drought Demon';
      case SpecialPiece.yanDi:
        return 'Flame Emperor';
      case SpecialPiece.chiYou:
        return 'War God';
      case SpecialPiece.changXian:
        return 'Always First';
      case SpecialPiece.xingTian:
        return 'Punishment Heaven';
      case SpecialPiece.zhuRong:
        return 'Fire God';
      case SpecialPiece.yuShi:
        return 'Rain Master';
      case SpecialPiece.fengHou:
        return 'Wind Empress';
      case SpecialPiece.gongGong:
        return 'Flood God';
      case SpecialPiece.nuWa:
        return 'Creator Goddess';
      case SpecialPiece.fuXi:
        return 'Creator God';
      case SpecialPiece.kuaFu:
        return 'Giant';
      case SpecialPiece.yingLong:
        return 'Responding Dragon';
      case SpecialPiece.fengBo:
        return 'Wind Earl';
    }
  }

  /// Get the emoji representation of the special piece
  String get emoji {
    switch (this) {
      case SpecialPiece.huangDi:
        return '👑';
      case SpecialPiece.nuBa:
        return '🌞';
      case SpecialPiece.yanDi:
        return '🔥';
      case SpecialPiece.chiYou:
        return '🪓';
      case SpecialPiece.changXian:
        return '🎯';
      case SpecialPiece.xingTian:
        return '⚔️';
      case SpecialPiece.zhuRong:
        return '💥';
      case SpecialPiece.yuShi:
        return '🌧️';
      case SpecialPiece.fengHou:
        return '🌬️';
      case SpecialPiece.gongGong:
        return '🌊';
      case SpecialPiece.nuWa:
        return '🧱';
      case SpecialPiece.fuXi:
        return '☯️';
      case SpecialPiece.kuaFu:
        return '🗿';
      case SpecialPiece.yingLong:
        return '🐉';
      case SpecialPiece.fengBo:
        return '💨';
    }
  }

  /// Get the description of the special piece's ability
  String get description {
    switch (this) {
      case SpecialPiece.huangDi:
        return 'When placed, converts all adjacent opponent pieces to own pieces';
      case SpecialPiece.nuBa:
        return 'When placed, can convert one adjacent opponent piece to own piece';
      case SpecialPiece.yanDi:
        return 'When placed, can remove all adjacent opponent pieces';
      case SpecialPiece.chiYou:
        return 'When placed, can convert all adjacent empty squares to abandoned squares';
      case SpecialPiece.changXian:
        return 'When placed, can remove any opponent piece on the board';
      case SpecialPiece.xingTian:
        return 'When placed, can remove one adjacent opponent piece';
      case SpecialPiece.zhuRong:
        return 'When forming mill, can additionally remove any opponent piece';
      case SpecialPiece.yuShi:
        return 'When forming mill, can convert any empty square to abandoned square';
      case SpecialPiece.fengHou:
        return 'Can be placed on abandoned squares';
      case SpecialPiece.gongGong:
        return 'Can ONLY be placed on abandoned squares';
      case SpecialPiece.nuWa:
        return 'When placed, can convert all adjacent abandoned squares to own pieces';
      case SpecialPiece.fuXi:
        return 'When placed, can convert any abandoned square to own piece';
      case SpecialPiece.kuaFu:
        return 'Cannot be removed by opponent';
      case SpecialPiece.yingLong:
        return 'Cannot be removed when adjacent to own pieces';
      case SpecialPiece.fengBo:
        return 'When placed, destroys any opponent piece without leaving abandoned square';
    }
  }
}

/// Represents a player's selected special pieces for Zhuolu Chess
class SpecialPieceSelection {
  const SpecialPieceSelection({
    required this.whiteSelection,
    required this.blackSelection,
    this.isRevealed = false,
  });

  /// White player's selected 6 special pieces
  final List<SpecialPiece> whiteSelection;

  /// Black player's selected 6 special pieces
  final List<SpecialPiece> blackSelection;

  /// Whether the selections have been revealed to both players
  final bool isRevealed;

  /// Create a copy with updated values
  SpecialPieceSelection copyWith({
    List<SpecialPiece>? whiteSelection,
    List<SpecialPiece>? blackSelection,
    bool? isRevealed,
  }) {
    return SpecialPieceSelection(
      whiteSelection: whiteSelection ?? this.whiteSelection,
      blackSelection: blackSelection ?? this.blackSelection,
      isRevealed: isRevealed ?? this.isRevealed,
    );
  }

  /// Generate random selection of 6 pieces from all 15 available
  static List<SpecialPiece> generateRandomSelection() {
    final List<SpecialPiece> allPieces = SpecialPiece.values.toList();
    allPieces.shuffle();
    return allPieces.take(6).toList();
  }

  /// Create a selection with random pieces for both players
  static SpecialPieceSelection createRandom() {
    return SpecialPieceSelection(
      whiteSelection: generateRandomSelection(),
      blackSelection: generateRandomSelection(),
    );
  }
}
