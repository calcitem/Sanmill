// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// position.dart
//
// MIGRATION STATUS (Phase 6.B pre-flight audit — 2026-05-01):
//   This file is the legacy Dart copy of the Mill rule machine — phase
//   transitions, mill detection, capture obligations, fly-piece rules and
//   threefold repetition.  The migration target is the Rust-native
//   `crates/tgf-mill::MillRules`, surfaced to Dart through
//   `lib/game_platform/engine/tgf_kernel.dart` and consumed via
//   `NativeMillRulesPort` / `NativeMillGameSession`.
//
//   VARIANT PARITY STATUS (as of Phase 6.B.0 audit):
//
//   COMPLETE — verified via `random_walk_native_and_legacy_agree_*` differential:
//     ✅ 9MM defaults (piece_count=9, standard rules)
//     ✅ 12MM with diagonal lines (piece_count=12, has_diagonal_lines=true)
//     ✅ Morabaraba (piece_count=12, diagonal, may_remove_multiple=true)
//     ✅ custodian_capture (Rust-only self-play; no C++ equivalent)
//     ✅ intervention_capture (Rust-only self-play)
//     ✅ restrict_repeated_mills_formation (Rust-only self-play)
//
//   PARTIAL / KNOWN GAP:
//     ⚠️ mayMoveInPlacingPhase (Lasker Morris, piece_count=10):
//          Phase-tag sync is correct (sync_phase_for_may_move_in_placing in
//          rules.rs), but legal-action generation diverges from C++ when one
//          player exhausts their hand before the other.  Tracked for a
//          dedicated fix; the native session still supports this variant in
//          practice — the divergence only manifests under very specific board
//          transitions that Dart currently handles via this legacy file.
//
//   Methods such as `_putPiece`, `_removePiece`, `handleMovingPhaseForPutPiece`
//   and `_isThreefoldRepetition` have direct Rust equivalents in
//   `MillRules::apply` / `MillRules::legal_actions` / `MillRules::outcome`
//   and will be removed in Phase 6.C once parity is confirmed via a wider
//   integration-test run.
//
//   When extending the Rust ruleset, mirror the change in
//   `MillVariantOptionsMapper.toTgfMillVariantOptions`, update the differential
//   test in `crates/tgf-frb/src/api/simple.rs`, and remove the corresponding
//   branch here.

part of '../mill.dart';

// ---------------------------------------------------------------------------
// _Mills — board topology tables (inlined from the deleted mills.dart).
//
// Mill boards have concentric square rings joined by edges and an empty
// middle. Mill games are typically played on the vertices not the cells.
//
//     31 ----- 24 ----- 25
//     | \       |      / |
//     |  23 -- 16 -- 17  |
//     |  | \    |   / |  |
//     |  |  15 08 09  |  |
//     30-22-14    10-18-26
//     |  |  13 12 11  |  |
//     |  | /    |   \ |  |
//     |  21 -- 20 -- 19  |
//     | /       |     \  |
//     29 ----- 28 ----- 27
// ---------------------------------------------------------------------------

// ignore_for_file: always_specify_types
class _Mills {
  const _Mills._();

  static List<List<int>> get adjacentSquaresInit {
    return DB().ruleSettings.hasDiagonalLines
        ? _adjacentSquaresDiagonal
        : _adjacentSquares;
  }

  static List<List<List<int>>> get millTableInit {
    return DB().ruleSettings.hasDiagonalLines ? _millTableDiagonal : _millTable;
  }

  // Note: Not follow order of MoveDirection array
  static const List<List<int>> _adjacentSquares = [
    /*  0 */ [0, 0, 0, 0],
    /*  1 */ [0, 0, 0, 0],
    /*  2 */ [0, 0, 0, 0],
    /*  3 */ [0, 0, 0, 0],
    /*  4 */ [0, 0, 0, 0],
    /*  5 */ [0, 0, 0, 0],
    /*  6 */ [0, 0, 0, 0],
    /*  7 */ [0, 0, 0, 0],
    /*  8 */ [16, 9, 15, 0],
    /*  9 */ [10, 8, 0, 0],
    /* 10 */ [18, 11, 9, 0],
    /* 11 */ [12, 10, 0, 0],
    /* 12 */ [20, 13, 11, 0],
    /* 13 */ [14, 12, 0, 0],
    /* 14 */ [22, 15, 13, 0],
    /* 15 */ [8, 14, 0, 0],
    /* 16 */ [8, 24, 17, 23],
    /* 17 */ [18, 16, 0, 0],
    /* 18 */ [10, 26, 19, 17],
    /* 19 */ [20, 18, 0, 0],
    /* 20 */ [12, 28, 21, 19],
    /* 21 */ [22, 20, 0, 0],
    /* 22 */ [14, 30, 23, 21],
    /* 23 */ [16, 22, 0, 0],
    /* 24 */ [16, 25, 31, 0],
    /* 25 */ [26, 24, 0, 0],
    /* 26 */ [18, 27, 25, 0],
    /* 27 */ [28, 26, 0, 0],
    /* 28 */ [20, 29, 27, 0],
    /* 29 */ [30, 28, 0, 0],
    /* 30 */ [22, 31, 29, 0],
    /* 31 */ [24, 30, 0, 0],
    /* 32 */ [0, 0, 0, 0],
    /* 33 */ [0, 0, 0, 0],
    /* 34 */ [0, 0, 0, 0],
    /* 35 */ [0, 0, 0, 0],
    /* 36 */ [0, 0, 0, 0],
    /* 37 */ [0, 0, 0, 0],
    /* 38 */ [0, 0, 0, 0],
    /* 39 */ [0, 0, 0, 0],
  ];

  static const List<List<int>> _adjacentSquaresDiagonal = [
    /*  0 */ [0, 0, 0, 0],
    /*  1 */ [0, 0, 0, 0],
    /*  2 */ [0, 0, 0, 0],
    /*  3 */ [0, 0, 0, 0],
    /*  4 */ [0, 0, 0, 0],
    /*  5 */ [0, 0, 0, 0],
    /*  6 */ [0, 0, 0, 0],
    /*  7 */ [0, 0, 0, 0],
    /*  8 */ [9, 15, 16, 0],
    /*  9 */ [17, 8, 10, 0],
    /* 10 */ [9, 11, 18, 0],
    /* 11 */ [19, 10, 12, 0],
    /* 12 */ [11, 13, 20, 0],
    /* 13 */ [21, 12, 14, 0],
    /* 14 */ [13, 15, 22, 0],
    /* 15 */ [23, 8, 14, 0],
    /* 16 */ [17, 23, 8, 24],
    /* 17 */ [9, 25, 16, 18],
    /* 18 */ [17, 19, 10, 26],
    /* 19 */ [11, 27, 18, 20],
    /* 20 */ [19, 21, 12, 28],
    /* 21 */ [13, 29, 20, 22],
    /* 22 */ [21, 23, 14, 30],
    /* 23 */ [15, 31, 16, 22],
    /* 24 */ [25, 31, 16, 0],
    /* 25 */ [17, 24, 26, 0],
    /* 26 */ [25, 27, 18, 0],
    /* 27 */ [19, 26, 28, 0],
    /* 28 */ [27, 29, 20, 0],
    /* 29 */ [21, 28, 30, 0],
    /* 30 */ [29, 31, 22, 0],
    /* 31 */ [23, 24, 30, 0],
    /* 32 */ [0, 0, 0, 0],
    /* 33 */ [0, 0, 0, 0],
    /* 34 */ [0, 0, 0, 0],
    /* 35 */ [0, 0, 0, 0],
    /* 36 */ [0, 0, 0, 0],
    /* 37 */ [0, 0, 0, 0],
    /* 38 */ [0, 0, 0, 0],
    /* 39 */ [0, 0, 0, 0],
  ];

  static const List<List<List<int>>> _millTable = [
    /* 0 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 1 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 2 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 3 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 4 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 5 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 6 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 7 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 8 */ [
      [16, 24],
      [9, 15],
      [0, 0],
    ],
    /* 9 */ [
      [0, 0],
      [15, 8],
      [10, 11],
    ],
    /* 10 */ [
      [18, 26],
      [11, 9],
      [0, 0],
    ],
    /* 11 */ [
      [0, 0],
      [9, 10],
      [12, 13],
    ],
    /* 12 */ [
      [20, 28],
      [13, 11],
      [0, 0],
    ],
    /* 13 */ [
      [0, 0],
      [11, 12],
      [14, 15],
    ],
    /* 14 */ [
      [22, 30],
      [15, 13],
      [0, 0],
    ],
    /* 15 */ [
      [0, 0],
      [13, 14],
      [8, 9],
    ],
    /* 16 */ [
      [8, 24],
      [17, 23],
      [0, 0],
    ],
    /* 17 */ [
      [0, 0],
      [23, 16],
      [18, 19],
    ],
    /* 18 */ [
      [10, 26],
      [19, 17],
      [0, 0],
    ],
    /* 19 */ [
      [0, 0],
      [17, 18],
      [20, 21],
    ],
    /* 20 */ [
      [12, 28],
      [21, 19],
      [0, 0],
    ],
    /* 21 */ [
      [0, 0],
      [19, 20],
      [22, 23],
    ],
    /* 22 */ [
      [14, 30],
      [23, 21],
      [0, 0],
    ],
    /* 23 */ [
      [0, 0],
      [21, 22],
      [16, 17],
    ],
    /* 24 */ [
      [8, 16],
      [25, 31],
      [0, 0],
    ],
    /* 25 */ [
      [0, 0],
      [31, 24],
      [26, 27],
    ],
    /* 26 */ [
      [10, 18],
      [27, 25],
      [0, 0],
    ],
    /* 27 */ [
      [0, 0],
      [25, 26],
      [28, 29],
    ],
    /* 28 */ [
      [12, 20],
      [29, 27],
      [0, 0],
    ],
    /* 29 */ [
      [0, 0],
      [27, 28],
      [30, 31],
    ],
    /* 30 */ [
      [14, 22],
      [31, 29],
      [0, 0],
    ],
    /* 31 */ [
      [0, 0],
      [29, 30],
      [24, 25],
    ],
    /* 32 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 33 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 34 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 35 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 36 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 37 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 38 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 39 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
  ];

  static const List<List<List<int>>> _millTableDiagonal = [
    /*  0 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /*  1 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /*  2 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /*  3 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /*  4 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /*  5 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /*  6 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /*  7 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /*  8 */ [
      [16, 24],
      [9, 15],
      [0, 0],
    ],
    /*  9 */ [
      [17, 25],
      [15, 8],
      [10, 11],
    ],
    /* 10 */ [
      [18, 26],
      [11, 9],
      [0, 0],
    ],
    /* 11 */ [
      [19, 27],
      [9, 10],
      [12, 13],
    ],
    /* 12 */ [
      [20, 28],
      [13, 11],
      [0, 0],
    ],
    /* 13 */ [
      [21, 29],
      [11, 12],
      [14, 15],
    ],
    /* 14 */ [
      [22, 30],
      [15, 13],
      [0, 0],
    ],
    /* 15 */ [
      [23, 31],
      [13, 14],
      [8, 9],
    ],
    /* 16 */ [
      [8, 24],
      [17, 23],
      [0, 0],
    ],
    /* 17 */ [
      [9, 25],
      [23, 16],
      [18, 19],
    ],
    /* 18 */ [
      [10, 26],
      [19, 17],
      [0, 0],
    ],
    /* 19 */ [
      [11, 27],
      [17, 18],
      [20, 21],
    ],
    /* 20 */ [
      [12, 28],
      [21, 19],
      [0, 0],
    ],
    /* 21 */ [
      [13, 29],
      [19, 20],
      [22, 23],
    ],
    /* 22 */ [
      [14, 30],
      [23, 21],
      [0, 0],
    ],
    /* 23 */ [
      [15, 31],
      [21, 22],
      [16, 17],
    ],
    /* 24 */ [
      [8, 16],
      [25, 31],
      [0, 0],
    ],
    /* 25 */ [
      [9, 17],
      [31, 24],
      [26, 27],
    ],
    /* 26 */ [
      [10, 18],
      [27, 25],
      [0, 0],
    ],
    /* 27 */ [
      [11, 19],
      [25, 26],
      [28, 29],
    ],
    /* 28 */ [
      [12, 20],
      [29, 27],
      [0, 0],
    ],
    /* 29 */ [
      [13, 21],
      [27, 28],
      [30, 31],
    ],
    /* 30 */ [
      [14, 22],
      [31, 29],
      [0, 0],
    ],
    /* 31 */ [
      [15, 23],
      [29, 30],
      [24, 25],
    ],
    /* 32 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 33 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 34 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 35 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 36 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 37 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 38 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
    /* 39 */ [
      [0, 0],
      [0, 0],
      [0, 0],
    ],
  ];

  static const List<List<int>> _horizontalAndVerticalLines = [
    // Horizontal lines
    [31, 24, 25], [23, 16, 17], [15, 8, 9],
    [30, 22, 14], [10, 18, 26], [13, 12, 11],
    [21, 20, 19], [29, 28, 27],
    // Vertical lines
    [31, 30, 29], [23, 22, 21], [15, 14, 13],
    [24, 16, 8], [12, 20, 28], [9, 10, 11],
    [17, 18, 19], [25, 26, 27],
  ];

  static const List<List<int>> _diagonalLines = [
    [31, 23, 15],
    [9, 17, 25],
    [29, 21, 13],
    [11, 19, 27],
  ];
}

// ---------------------------------------------------------------------------
// _Zobrist — Zobrist hash tables (inlined from the deleted zobrist.dart).
// ---------------------------------------------------------------------------
class _Zobrist {
  const _Zobrist._();

  static const int keyMiscBit = 2;
  static const List<List<int>> psq = <List<int>>[
    <int>[
      0x4E421A,
      0x3962FF,
      0x6DB6EE,
      0x219AE1,
      0x1F3DE2,
      0xD9AACB,
      0xD51733,
      0xD3F9EA,
      0xF5A7BB,
      0xDC4109,
      0xEE4319,
      0x7CDA7A,
      0xFD7B4D,
      0x4138BE,
      0xCCBB2D,
      0xDA6097,
      0x06D827,
      0xCBC16C,
      0x46F125,
      0xE29F22,
      0xCAAB94,
      0x5B02DB,
      0x877CD6,
      0x35E438,
      0x49FDAE,
      0xE68314,
      0xBE1664,
      0x1F49D3,
      0x50F5B1,
      0x149AAF,
      0xF509B9,
      0x47AEB5,
      0x18E993,
      0x76BB4F,
      0xFE1739,
      0xF87B87,
      0x0A8CD2,
      0x630C6B,
      0x88F5B4,
      0x0A583E,
    ],
    <int>[
      0xA0128E,
      0x6F2251,
      0x51E99D,
      0x6D35BF,
      0x66D6D9,
      0x87D366,
      0x75A57A,
      0x534FC4,
      0x1FE34B,
      0xAD6FB0,
      0xE5679D,
      0xF88AFF,
      0x0462DA,
      0x4BDE96,
      0xF28912,
      0x10537E,
      0x26D8EA,
      0x37E6E7,
      0x0871D9,
      0xCD5F4F,
      0xF4AFA1,
      0x44A51B,
      0x772656,
      0x8B7965,
      0xD8F17D,
      0x80F3D7,
      0x6B6206,
      0x19B8BB,
      0xFBC229,
      0x0FCAB4,
      0xFD7374,
      0xA647B9,
      0x296A8D,
      0xA3D742,
      0x624D6D,
      0x459FD4,
      0xCE8C26,
      0x965448,
      0x410171,
      0x1EDD7A,
    ],
    <int>[
      0x1FCF95,
      0xA5634E,
      0x21976A,
      0x32902D,
      0x55A27C,
      0x49EC5F,
      0x0176A1,
      0xCAAAEF,
      0x145886,
      0xB4C808,
      0x0153EE,
      0x7D78DF,
      0xE9C3C5,
      0x66B7A6,
      0x3CD930,
      0xDBBA23,
      0xF19841,
      0x6BEFDF,
      0xB979FE,
      0xBA4D06,
      0x96AECF,
      0x33B96E,
      0x76A99C,
      0x1B8762,
      0x747B20,
      0x0DEC24,
      0xA4E632,
      0xBA2442,
      0x59C91B,
      0x41482D,
      0xF2CD39,
      0x30E9C1,
      0x6B156D,
      0xC7F191,
      0x012D36,
      0xC66B36,
      0x631560,
      0xA891FC,
      0xF6C8AC,
      0xD80B94,
    ],
    <int>[
      0xF641E9,
      0xF164BF,
      0x2DBE4C,
      0xE2A40C,
      0x53FA06,
      0x4F3117,
      0x0ACA70,
      0x2C72F5,
      0xC81047,
      0x4B76AE,
      0xEB55C8,
      0x0DB6EF,
      0x7F57AB,
      0x22D060,
      0x390554,
      0xDE9A43,
      0x6583AF,
      0x41D141,
      0x9CBF92,
      0x7E528F,
      0x2BEFA1,
      0x5C5FDC,
      0x4DDAFA,
      0x7C98A1,
      0x65A13B,
      0x2953BF,
      0x8769A8,
      0xE6DCA1,
      0xD01A6E,
      0xBCD935,
      0x175659,
      0xAD5A73,
      0xB04E7D,
      0x815F53,
      0x12469A,
      0xB2F25C,
      0x564E4B,
      0xD19437,
      0xA4F63C,
      0x7169E5,
    ],
  ];

  static const List<List<int>> custodianTarget = <List<int>>[
    <int>[
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
    ],
    <int>[
      0xD18C0B,
      0x3971A7,
      0x8444F8,
      0x881B90,
      0xF716FA,
      0x30BBAD,
      0xE9899C,
      0x212CB9,
      0x23727B,
      0xDFA5EC,
      0x2C2B00,
      0x10BAF6,
      0xC9F3E3,
      0x764550,
      0xC18847,
      0x400C09,
      0x9AE26D,
      0x40BAC1,
      0x35D91B,
      0x65383C,
      0x5F13BA,
      0xC5EE40,
      0x66710C,
      0xCB5363,
      0x412086,
      0x509E77,
      0xA28643,
      0xDBAD3D,
      0x8AE041,
      0x2B2064,
      0x653E08,
      0xE21DFE,
    ],
    <int>[
      0x4457D3,
      0x519890,
      0xF09313,
      0xD07997,
      0x3EFF75,
      0x1BF9D3,
      0x87296C,
      0x1004E4,
      0xC84A24,
      0x41D5B9,
      0x482B8C,
      0x366263,
      0x61528A,
      0xCBA795,
      0x4C69A8,
      0x7B0929,
      0xAFFA29,
      0x36768A,
      0x443003,
      0x9D889C,
      0xA311D9,
      0xBD3630,
      0x9CAA4A,
      0x73F315,
      0xFF07C1,
      0x0949D0,
      0x156398,
      0x2F4CD2,
      0xC49599,
      0x88375E,
      0xA74700,
      0xA46058,
    ],
  ];

  static const List<List<int>> custodianCount = <List<int>>[
    <int>[0, 0, 0, 0, 0],
    <int>[0x3AB8E3, 0xAEC2FF, 0x59FE69, 0x7C3298, 0xA20BF0],
    <int>[0x30337E, 0x951936, 0x992396, 0xBC371E, 0x2A1778],
  ];

  static const List<List<int>> interventionTarget = <List<int>>[
    <int>[
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
    ],
    <int>[
      0x5E02A1,
      0xA4D957,
      0x3F7C6E,
      0x12B9F4,
      0x89D214,
      0x6E4308,
      0xF0A6C3,
      0x7B9E12,
      0xC4578B,
      0x1E63FD,
      0x54AB08,
      0x9374C2,
      0x20D8AF,
      0xE14679,
      0x3AB5E1,
      0x7F0C52,
      0xD5E3A4,
      0x48BC17,
      0x9A04C6,
      0x6CF2D3,
      0xB1705A,
      0x2E39CF,
      0xC8A5B4,
      0x14567E,
      0xF92D01,
      0x8B73AC,
      0x31EF59,
      0xDA4682,
      0x5C9BD7,
      0x07E214,
      0xBE5836,
      0x4AD0F1,
    ],
    <int>[
      0x7C51E2,
      0x0FA943,
      0xE2D578,
      0x98B01F,
      0x467CDA,
      0x1AB5C0,
      0xD93F85,
      0x62E7FA,
      0x0B8C4D,
      0xF43197,
      0x2CD065,
      0xAE7B1C,
      0x5389F2,
      0x0D47BC,
      0x9146E8,
      0x3FAD21,
      0xC8E05B,
      0x74B932,
      0x8FD6AE,
      0x59C384,
      0xB7A210,
      0x261FDB,
      0xE98543,
      0x40C87A,
      0xA3F2D6,
      0x1C5AE9,
      0x6BED54,
      0xDF0893,
      0x85264F,
      0x39B1D0,
      0xF50E6A,
      0x12C497,
    ],
  ];

  static const List<List<int>> interventionCount = <List<int>>[
    <int>[0, 0, 0, 0, 0, 0, 0, 0, 0],
    <int>[
      0x51A2E9,
      0x83D45C,
      0x1BE790,
      0xA6C53F,
      0x7E08B1,
      0x3D9426,
      0xF250DA,
      0x4691FE,
      0x9C3074,
    ],
    <int>[
      0x6F1C83,
      0x24A5D7,
      0xBD4072,
      0x90E68F,
      0x58B13C,
      0x0ED5A8,
      0xC78159,
      0x3A4CEF,
      0xF9B026,
    ],
  ];

  static const List<List<int>> leapTarget = <List<int>>[
    <int>[
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
      0x000000,
    ],
    <int>[
      0xA1B2C3,
      0xD4E5F6,
      0x123456,
      0x789ABC,
      0xDEF012,
      0x345678,
      0x9ABCDE,
      0xF01234,
      0x567890,
      0xABCDEF,
      0x013579,
      0x2468AC,
      0xBDF135,
      0x79E024,
      0x68ACF1,
      0x357BDE,
      0x902468,
      0xACE135,
      0x79BDF0,
      0x2468AC,
      0xE13579,
      0x0246BD,
      0xF13579,
      0xACE024,
      0x68BDF1,
      0x35790A,
      0xCE2468,
      0xBD1357,
      0x9F0246,
      0x8ACE13,
      0x57902B,
      0xDF1468,
    ],
    <int>[
      0x9C8D7E,
      0x6F5A4B,
      0x3C2D1E,
      0x0F9E8D,
      0x7C6B5A,
      0x4938271,
      0xE6D5C4,
      0xB3A291,
      0x807F6E,
      0x5D4C3B,
      0x2A1908,
      0xF7E6D5,
      0xC4B3A2,
      0x918071,
      0x6F5E4D,
      0x3C2B1A,
      0x091807,
      0xF6E5D4,
      0xC3B2A1,
      0x908F7E,
      0x6D5C4B,
      0x3A2918,
      0x071605,
      0xF4E3D2,
      0xC1B0A0,
      0x8F7E6D,
      0x5C4B3A,
      0x291807,
      0x060504,
      0xE3D2C1,
      0xB0A090,
      0x7F6E5D,
    ],
  ];

  static const List<List<int>> leapCount = <List<int>>[
    <int>[0, 0],
    <int>[0x8B3D2F, 0x4C7E91],
    <int>[0x6A5F3E, 0x2D8B4C],
  ];

  static const int side = 0x201906;
}

List<int> posKeyHistory = <int>[];

// Three-point line definitions on the board (used by custodian, intervention,
// and leap capture rules)
const List<List<int>> _threePointSquareEdgeLines = <List<int>>[
  <int>[31, 24, 25],
  <int>[23, 16, 17],
  <int>[15, 8, 9],
  <int>[13, 12, 11],
  <int>[21, 20, 19],
  <int>[29, 28, 27],
  <int>[31, 30, 29],
  <int>[23, 22, 21],
  <int>[15, 14, 13],
  <int>[9, 10, 11],
  <int>[17, 18, 19],
  <int>[25, 26, 27],
];

const List<List<int>> _threePointCrossLines = <List<int>>[
  <int>[30, 22, 14],
  <int>[10, 18, 26],
  <int>[24, 16, 8],
  <int>[12, 20, 28],
];

const List<List<int>> _threePointDiagonalLines = <List<int>>[
  <int>[31, 23, 15],
  <int>[9, 17, 25],
  <int>[29, 21, 13],
  <int>[11, 19, 27],
];

class SquareAttribute {
  SquareAttribute({required this.placedPieceNumber});

  int placedPieceNumber;
}

class StateInfo {
  // Copied when making a move
  int rule50 = 0;
  int pliesFromNull = 0;

  // Not copied when making a move (will be recomputed anyhow)
  int key = 0;
}

class Position {
  Position();

  GameResult? result;

  final List<PieceColor> _board = List<PieceColor>.filled(
    sqNumber,
    PieceColor.none,
  );
  final List<PieceColor> _grid = List<PieceColor>.filled(
    7 * 7,
    PieceColor.none,
  );

  int placedPieceNumber = 0;
  int selectedPieceNumber = 0;
  late List<SquareAttribute> sqAttrList = List<SquareAttribute>.generate(
    sqNumber,
    (int index) => SquareAttribute(placedPieceNumber: 0),
  );

  final Map<PieceColor, int> pieceInHandCount = <PieceColor, int>{
    PieceColor.white: DB().ruleSettings.piecesCount,
    PieceColor.black: DB().ruleSettings.piecesCount,
  };
  final Map<PieceColor, int> pieceOnBoardCount = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
  };
  final Map<PieceColor, int> pieceToRemoveCount = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
  };

  static const int _kMaxCustodianRemoval = 4;
  static const int _kMaxInterventionRemoval = 8;

  final Map<PieceColor, int> _custodianCaptureTargets = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
  };

  final Map<PieceColor, int> _custodianRemovalCount = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
  };

  final Map<PieceColor, int> _interventionCaptureTargets = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
  };

  final Map<PieceColor, int> _interventionRemovalCount = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
  };

  final Map<PieceColor, int> _leapCaptureTargets = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
  };

  final Map<PieceColor, int> _leapRemovalCount = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
  };

  @visibleForTesting
  Map<PieceColor, int> get leapCaptureTargets => _leapCaptureTargets;

  @visibleForTesting
  Map<PieceColor, int> get leapRemovalCount => _leapRemovalCount;

  // Indicates whether a mill capture is available at the start of the current
  // removal phase for each side. This is used to prevent choosing generic
  // mill removals when only custodian/intervention capture is available.
  final Map<PieceColor, bool> _millAvailableAtRemoval = <PieceColor, bool>{
    PieceColor.white: false,
    PieceColor.black: false,
  };

  int pieceCountDiff() {
    return pieceOnBoardCount[PieceColor.white]! +
        pieceInHandCount[PieceColor.white]! -
        pieceOnBoardCount[PieceColor.black]! -
        pieceInHandCount[PieceColor.black]!;
  }

  bool isEmpty() {
    return pieceInHandCount[PieceColor.white]! ==
            DB().ruleSettings.piecesCount &&
        pieceInHandCount[PieceColor.black]! == DB().ruleSettings.piecesCount &&
        pieceOnBoardCount[PieceColor.white]! == 0 &&
        pieceOnBoardCount[PieceColor.black]! == 0;
  }

  bool isNeedStalemateRemoval = false;
  bool isStalemateRemoving = false;
  // Tracks that both players are performing stalemate removals
  // (bothPlayersRemoveOpponentsPiece). Adjacency restriction applies
  // to both sides while this flag is set.
  bool isBothStalemateRemoving = false;

  // Used during move import to specify which capture line should be selected
  // when there are multiple intervention capture lines available
  int? preferredRemoveTarget;

  bool isNoDraw() {
    if (score[PieceColor.white]! > 0 || score[PieceColor.black]! > 0) {
      return true;
    }
    return false;
  }

  int _gamePly = 0;

  /// _roundNumber tracks which round we are in. Each cycle of White->Black
  /// is one complete round. Whenever we switch from Black back to White,
  /// we increment this counter.
  int _roundNumber = 1;

  PieceColor _sideToMove = PieceColor.white;

  final StateInfo st = StateInfo();

  PieceColor _them = PieceColor.black;
  PieceColor winner = PieceColor.nobody;

  GameOverReason? gameOverReason;

  /// Indicates whether the current position already has a game result.
  bool get hasGameResult => phase == Phase.gameOver;

  /// The reason for game over, if any.
  GameOverReason? get reason => gameOverReason;

  Phase phase = Phase.placing;
  Act action = Act.place;

  static Map<PieceColor, int> score = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
    PieceColor.draw: 0,
  };

  String get scoreString =>
      "${score[PieceColor.white]} - ${score[PieceColor.draw]} - ${score[PieceColor.black]}";

  static void resetScore() => score[PieceColor.white] =
      score[PieceColor.black] = score[PieceColor.draw] = 0;

  Map<PieceColor, int> _currentSquare = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
    PieceColor.draw: 0,
  };

  Map<PieceColor, int> _lastMillFromSquare = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
    PieceColor.draw: 0,
  };

  Map<PieceColor, int> _lastMillToSquare = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
    PieceColor.draw: 0,
  };

  Map<PieceColor, int> _formedMillsBB = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
    PieceColor.draw: 0,
  };

  Map<PieceColor, List<List<int>>> _formedMills = <PieceColor, List<List<int>>>{
    PieceColor.white: <List<int>>[],
    PieceColor.black: <List<int>>[],
    PieceColor.draw: <List<int>>[],
  };

  Map<PieceColor, List<List<int>>> get formedMills => _formedMills;

  ExtMove? _record;

  static List<List<List<int>>> get _millTable => _Mills.millTableInit;

  static List<List<int>> get _adjacentSquares => _Mills.adjacentSquaresInit;

  static List<List<int>> get _millLinesHV => _Mills._horizontalAndVerticalLines;

  static List<List<int>> get _millLinesD => _Mills._diagonalLines;

  PieceColor pieceOnGrid(int index) => _grid[index];

  PieceColor get sideToMove => _sideToMove;

  set sideToMove(PieceColor color) {
    _sideToMove = color;
    _them = _sideToMove.opponent;
  }

  @visibleForTesting
  List<PieceColor> get board => _board;

  @visibleForTesting
  int get key => st.key;

  bool _movePiece(int from, int to) {
    // Ensure selecting the piece succeeds before placing it.
    // Previously this method ignored the return value of _selectPiece
    // and relied on exceptions, which _selectPiece does not throw.
    final GameResponse selectResult = _selectPiece(from);
    if (selectResult is! GameResponseOK) {
      return false;
    }

    return _putPiece(to);
  }

  /// Returns a FEN representation of the position.
  /// Example: "@*O@O*O*/O*@@O@@@/O@O*@*O* b m s 8 0 9 0 0 0 0 0 0 0 3 10"
  /// Format: "[Inner ring]/[Middle Ring]/[Outer Ring]
  /// [Side to Move] [Phase] [Action]
  /// [White Piece On Board] [White Piece In Hand]
  /// [Black Piece On Board] [Black Piece In Hand]
  /// [White Piece to Remove] [Black Piece to Remove]
  /// [White Piece Last Mill From Square] [White Piece Last Mill To Square]
  /// [Black Piece Last Mill From Square] [Black Piece Last Mill To Square]
  /// [MillsBitmask]
  /// [Rule50] [Ply]"
  ///
  /// ([Rule50] and [Ply] are unused right now.)
  /// Param:
  ///
  /// Ring
  /// @ - Black piece
  /// O - White piece
  /// * - Empty point
  /// X - Marked point
  ///
  /// Side to move
  /// w - White to Move
  /// b - Black to Move
  ///
  /// Phase
  /// p - Placing Phase
  /// m - Moving Phase
  ///
  /// Action
  /// p - Place Action
  /// s - Select Action
  /// r - Remove Action
  String? get fen {
    final StringBuffer buffer = StringBuffer();

    // Piece placement data
    for (int file = 1; file <= fileNumber; file++) {
      for (int rank = 1; rank <= rankNumber; rank++) {
        final PieceColor piece = pieceOnGrid(
          squareToIndex[makeSquare(file, rank)]!,
        );
        buffer.write(piece.string);
      }

      if (file == 3) {
        buffer.writeSpace();
      } else {
        buffer.write("/");
      }
    }

    // Active color
    buffer.writeSpace(_sideToMove == PieceColor.white ? "w" : "b");

    // Phrase
    buffer.writeSpace(phase.fen);

    // Action
    if (action == Act.remove) {
      if (pieceToRemoveCount[_sideToMove] == 0) {
        // Only log in debug mode to avoid log spam during rapid state changes
        assert(() {
          logger.e("Invalid FEN: No piece to remove.");
          return true;
        }());
      }
      if (pieceOnBoardCount[_sideToMove.opponent] == 0 &&
          DB().ruleSettings.millFormationActionInPlacingPhase !=
              MillFormationActionInPlacingPhase.opponentRemovesOwnPiece) {
        assert(() {
          logger.e("Invalid FEN: No piece to remove.");
          return true;
        }());
      }
    }
    buffer.writeSpace(action.fen);

    buffer.writeSpace(pieceOnBoardCount[PieceColor.white]);
    buffer.writeSpace(pieceInHandCount[PieceColor.white]);
    buffer.writeSpace(pieceOnBoardCount[PieceColor.black]);
    buffer.writeSpace(pieceInHandCount[PieceColor.black]);
    buffer.writeSpace(pieceToRemoveCount[PieceColor.white]);
    buffer.writeSpace(pieceToRemoveCount[PieceColor.black]);
    buffer.writeSpace(_lastMillFromSquare[PieceColor.white]);
    buffer.writeSpace(_lastMillToSquare[PieceColor.white]);
    buffer.writeSpace(_lastMillFromSquare[PieceColor.black]);
    buffer.writeSpace(_lastMillToSquare[PieceColor.black]);

    buffer.writeSpace(
      (_formedMillsBB[PieceColor.white]! << 32) |
          _formedMillsBB[PieceColor.black]!,
    );

    final int sideIsBlack = _sideToMove == PieceColor.black ? 1 : 0;

    buffer.write("${st.rule50} ${1 + (_gamePly - sideIsBlack) ~/ 2}");

    void appendCapture(
      String label,
      Map<PieceColor, int> removalCount,
      Map<PieceColor, int> captureTargets,
    ) {
      final bool hasData =
          (removalCount[PieceColor.white] ?? 0) > 0 ||
          (removalCount[PieceColor.black] ?? 0) > 0 ||
          (captureTargets[PieceColor.white] ?? 0) != 0 ||
          (captureTargets[PieceColor.black] ?? 0) != 0;

      if (!hasData) {
        return;
      }

      buffer
        ..write(' ')
        ..write(label)
        ..write(':');

      void appendColor(String prefix, PieceColor color) {
        buffer
          ..write(prefix)
          ..write('-')
          ..write(removalCount[color])
          ..write('-');

        bool first = true;
        final int targets = captureTargets[color]!;
        for (int sq = sqBegin; sq < sqEnd; ++sq) {
          if ((targets & squareBb(sq)) == 0) {
            continue;
          }

          if (!first) {
            buffer.write('.');
          }

          buffer.write(sq);
          first = false;
        }
      }

      appendColor('w', PieceColor.white);
      buffer.write('|');
      appendColor('b', PieceColor.black);
    }

    appendCapture('c', _custodianRemovalCount, _custodianCaptureTargets);
    appendCapture('i', _interventionRemovalCount, _interventionCaptureTargets);
    appendCapture('l', _leapRemovalCount, _leapCaptureTargets);

    // Append preferredRemoveTarget if set
    // Format: " p:21" where 21 is the square number
    // This is appended at the end for backward compatibility
    if (preferredRemoveTarget != null) {
      buffer.write(' p:$preferredRemoveTarget');
    }

    // Append stalemate removal state if active
    // Format: " s:1" for isStalemateRemoving,
    //         " s:2" for isBothStalemateRemoving
    if (isStalemateRemoving) {
      buffer.write(' s:1');
    } else if (isBothStalemateRemoving) {
      buffer.write(' s:2');
    }

    logger.t("FEN is $buffer");

    final String fen = buffer.toString();

    // Only log validation errors in debug mode to prevent log spam
    if (validateFen(fen) == false) {
      assert(() {
        logger.e("Invalid FEN: $fen");
        return true;
      }());
    }

    return fen;
  }

  bool setFen(String fen) {
    const bool ret = true;
    final String trimmedFen = fen.trim();
    final List<int> extraIndices = <int>[
      trimmedFen.indexOf(' c:'),
      trimmedFen.indexOf(' i:'),
      trimmedFen.indexOf(' l:'),
      trimmedFen.indexOf(' p:'),
      trimmedFen.indexOf(' s:'),
    ].where((int index) => index >= 0).toList();

    int firstExtra = trimmedFen.length;
    for (final int index in extraIndices) {
      if (index < firstExtra) {
        firstExtra = index;
      }
    }

    String extras = '';
    String coreFen = trimmedFen;
    if (firstExtra < trimmedFen.length) {
      extras = trimmedFen.substring(firstExtra).trim();
      coreFen = trimmedFen.substring(0, firstExtra).trimRight();
    }

    String custodianData = '';
    String interventionData = '';
    String leapData = '';
    int? preferredTarget;
    int? stalemateRemovalFlag;
    if (extras.isNotEmpty) {
      final List<String> tokens = extras.split(RegExp(r'\s+'));
      for (final String token in tokens) {
        if (token.startsWith('c:')) {
          custodianData = token.substring(2);
        } else if (token.startsWith('i:')) {
          interventionData = token.substring(2);
        } else if (token.startsWith('l:')) {
          leapData = token.substring(2);
        } else if (token.startsWith('p:')) {
          // Parse preferredRemoveTarget
          final String targetStr = token.substring(2);
          preferredTarget = int.tryParse(targetStr);
        } else if (token.startsWith('s:')) {
          // Parse stalemate removal state
          // Format: "s:1" for isStalemateRemoving,
          //         "s:2" for isBothStalemateRemoving
          stalemateRemovalFlag = int.tryParse(token.substring(2));
        }
      }
    }

    final List<String> fields = coreFen.split(RegExp(r'\s+'));
    if (fields.length < 17) {
      logger.e('FEN does not contain enough parts.');
      return false;
    }

    final String boardStr = fields[0];
    final List<String> ring = boardStr.split("/");

    final Map<String, PieceColor> pieceMap = <String, PieceColor>{
      "*": PieceColor.none,
      "O": PieceColor.white,
      "@": PieceColor.black,
      "X": PieceColor.marked,
    };

    // Piece placement data
    for (int file = 1; file <= fileNumber; file++) {
      for (int rank = 1; rank <= rankNumber; rank++) {
        final PieceColor p = pieceMap[ring[file - 1][rank - 1]]!;
        final int sq = makeSquare(file, rank);
        _board[sq] = p;
        _grid[squareToIndex[sq]!] = p;
      }
    }

    final String sideToMoveStr = fields[1];

    final Map<String, PieceColor> sideToMoveMap = <String, PieceColor>{
      "w": PieceColor.white,
      "b": PieceColor.black,
    };

    _sideToMove = sideToMoveMap[sideToMoveStr]!;
    _them = _sideToMove.opponent;

    final String phaseStr = fields[2];

    final Map<String, Phase> phaseMap = <String, Phase>{
      "r": Phase.ready,
      "p": Phase.placing,
      "m": Phase.moving,
      "o": Phase.gameOver,
    };

    phase = phaseMap[phaseStr]!;

    final String actionStr = fields[3];

    final Map<String, Act> actionMap = <String, Act>{
      "p": Act.place,
      "s": Act.select,
      "r": Act.remove,
    };

    action = actionMap[actionStr]!;

    final String whitePieceOnBoardCountStr = fields[4];
    pieceOnBoardCount[PieceColor.white] = int.parse(whitePieceOnBoardCountStr);

    final String whitePieceInHandCountStr = fields[5];
    pieceInHandCount[PieceColor.white] = int.parse(whitePieceInHandCountStr);

    final String blackPieceOnBoardCountStr = fields[6];
    pieceOnBoardCount[PieceColor.black] = int.parse(blackPieceOnBoardCountStr);

    final String blackPieceInHandCountStr = fields[7];
    pieceInHandCount[PieceColor.black] = int.parse(blackPieceInHandCountStr);

    final String whitePieceToRemoveCountStr = fields[8];
    pieceToRemoveCount[PieceColor.white] = int.parse(
      whitePieceToRemoveCountStr,
    );

    final String blackPieceToRemoveCountStr = fields[9];
    pieceToRemoveCount[PieceColor.black] = int.parse(
      blackPieceToRemoveCountStr,
    );

    final String whiteLastMillFromSquareStr = fields[10];
    _lastMillFromSquare[PieceColor.white] = int.parse(
      whiteLastMillFromSquareStr,
    );

    final String whiteLastMillToSquareStr = fields[11];
    _lastMillToSquare[PieceColor.white] = int.parse(whiteLastMillToSquareStr);

    final String blackLastMillFromSquareStr = fields[12];
    _lastMillFromSquare[PieceColor.black] = int.parse(
      blackLastMillFromSquareStr,
    );

    final String blackLastMillToSquareStr = fields[13];
    _lastMillToSquare[PieceColor.black] = int.parse(blackLastMillToSquareStr);

    final String millsBitmaskStr = fields[14];
    setFormedMillsBB(int.parse(millsBitmaskStr));

    final String rule50Str = fields[15];
    st.rule50 = int.parse(rule50Str);

    final String gamePlyStr = fields[16];
    final int fullMoveNumber = int.parse(gamePlyStr);

    // Convert from fullmove starting from 1 to gamePly starting from 0,
    // handle also common incorrect FEN with fullmove = 0.
    _gamePly =
        max(2 * (fullMoveNumber - 1), 0) +
        (_sideToMove == PieceColor.black ? 1 : 0);

    // Misc
    winner = PieceColor.nobody;
    gameOverReason = null;
    _currentSquare[PieceColor.white] = _currentSquare[PieceColor.black] = 0;
    _record = null;

    if (!_parseCustodianFen(custodianData)) {
      logger.e('Failed to parse custodian FEN data: $custodianData');
      return false;
    }
    if (!_parseInterventionFen(interventionData)) {
      logger.e('Failed to parse intervention FEN data: $interventionData');
      return false;
    }
    if (!_parseLeapFen(leapData)) {
      logger.e('Failed to parse leap FEN data: $leapData');
      return false;
    }

    // Set preferredRemoveTarget if present in FEN
    if (preferredTarget != null) {
      preferredRemoveTarget = preferredTarget;
    }

    // Set stalemate removal flags from FEN (default false)
    isStalemateRemoving = stalemateRemovalFlag == 1;
    isBothStalemateRemoving = stalemateRemovalFlag == 2;

    return ret;
  }

  // TODO: Implement with C++ in engine
  bool validateFen(String fen) {
    final String trimmedFen = fen.trim();
    final List<int> extraIndices = <int>[
      trimmedFen.indexOf(' c:'),
      trimmedFen.indexOf(' i:'),
      trimmedFen.indexOf(' l:'),
      trimmedFen.indexOf(' p:'),
      trimmedFen.indexOf(' s:'),
    ].where((int index) => index >= 0).toList();

    int firstExtra = trimmedFen.length;
    for (final int index in extraIndices) {
      if (index < firstExtra) {
        firstExtra = index;
      }
    }

    String extras = '';
    String coreFen = trimmedFen;
    if (firstExtra < trimmedFen.length) {
      extras = trimmedFen.substring(firstExtra).trim();
      coreFen = trimmedFen.substring(0, firstExtra).trimRight();
    }

    String custodianData = '';
    String interventionData = '';
    if (extras.isNotEmpty) {
      final List<String> tokens = extras.split(RegExp(r'\s+'));
      for (final String token in tokens) {
        if (token.startsWith('c:')) {
          custodianData = token.substring(2);
        } else if (token.startsWith('i:')) {
          interventionData = token.substring(2);
        }
      }
    }

    final List<String> parts = coreFen.split(RegExp(r'\s+'));
    if (parts.length < 17) {
      logger.e('FEN does not contain enough parts.');
      return false;
    }

    // Part 0: Piece placement
    final String board = parts[0];
    if (board.length != 26 ||
        board[8] != '/' ||
        board[17] != '/' ||
        !RegExp(r'^[*OX@/]+$').hasMatch(board)) {
      logger.e('Invalid piece placement format.');
      return false;
    }

    // Part 1: Active color
    final String activeColor = parts[1];
    if (activeColor != 'w' && activeColor != 'b') {
      logger.e('Invalid active color. Must be "w" or "b".');
      return false;
    }

    // Part 2: Phrase
    final String phrase = parts[2];
    if (!RegExp(r'^[rpmo]$').hasMatch(phrase)) {
      logger.e('Invalid phrase. Must be one of "r", "p", "m", "o".');
      return false;
    }

    // Part 3: Action
    final String action = parts[3];
    if (!RegExp(r'^[psr]$').hasMatch(action)) {
      logger.e('Invalid action. Must be one of "p", "s", "r".');
      return false;
    }

    // Part 4: White piece on board
    final int whitePieceOnBoard = int.parse(parts[4]);
    if (phrase == 'm' &&
        whitePieceOnBoard < DB().ruleSettings.piecesAtLeastCount) {
      // Use assert to reduce log spam in release builds
      assert(() {
        logger.e(
          'Invalid white piece on board. Must be at least ${DB().ruleSettings.piecesAtLeastCount}.',
        );
        return true;
      }());
      return false;
    }
    if (whitePieceOnBoard < 0 ||
        whitePieceOnBoard > DB().ruleSettings.piecesCount) {
      assert(() {
        logger.e('Invalid white piece on board. Must be between 0 and 12.');
        return true;
      }());
      return false;
    }

    // Part 5: White piece in hand
    final int whitePieceInHand = int.parse(parts[5]);
    if (whitePieceInHand < 0 ||
        whitePieceInHand > DB().ruleSettings.piecesCount) {
      assert(() {
        logger.e('Invalid white piece in hand. Must be between 0 and 12.');
        return true;
      }());
      return false;
    }
    if (activeColor == 'w' &&
        phrase == 'p' &&
        action != 'r' &&
        whitePieceInHand == 0) {
      assert(() {
        logger.e('Invalid white piece in hand. Must be greater than 0.');
        return true;
      }());
      return false;
    }

    // Part 6: Black piece on board
    final int blackPieceOnBoard = int.parse(parts[6]);
    if (phrase == 'm' &&
        blackPieceOnBoard < DB().ruleSettings.piecesAtLeastCount) {
      assert(() {
        logger.e(
          'Invalid black piece on board. Must be at least ${DB().ruleSettings.piecesAtLeastCount}.',
        );
        return true;
      }());
      return false;
    }
    if (blackPieceOnBoard < 0 ||
        blackPieceOnBoard > DB().ruleSettings.piecesCount) {
      assert(() {
        logger.e('Invalid black piece on board. Must be between 0 and 12.');
        return true;
      }());
      return false;
    }

    // Part 7: Black piece in hand
    final int blackPieceInHand = int.parse(parts[7]);
    if (blackPieceInHand < 0 ||
        blackPieceInHand > DB().ruleSettings.piecesCount) {
      assert(() {
        logger.e('Invalid black piece in hand. Must be between 0 and 12.');
        return true;
      }());
      return false;
    }

    // Parts 4-7: Counts on and off board
    List<int> counts = parts.getRange(4, 8).map(int.parse).toList();
    if (counts.any(
          (int count) => count < 0 || count > DB().ruleSettings.piecesCount,
        ) ||
        counts.every((int count) => count == 0)) {
      logger.e('Invalid counts. Must be between 0 and 12 and not all zero.');
      return false;
    }

    // Parts 8-9: Need to remove
    counts = parts.getRange(8, 10).map(int.parse).toList();
    if (counts.any((int count) => count < -7 || count > 7)) {
      logger.e('Invalid need to remove count. Must be between -7 and 7.');
      return false;
    }

    // Parts 10-13: Last mill square
    counts = parts.getRange(10, 14).map(int.parse).toList();
    if (counts.any((int count) => count != 0 && (count < 8 || count > 32))) {
      logger.e('Invalid last mill square. Must be 0 or between 8 and 32.');
      return false;
    }

    // Part 14: Mills bitmask
    final int millsBitmask = int.parse(parts[14]);
    // Check if the lowest 8 bits are not zero
    if ((millsBitmask & 0xFF) != 0) {
      logger.e('The lowest 8 bits are not zero.');
      return false;
    }

    // Check if bits 32 to 39 are not zero
    // 0xFF << 32 shifts 0xFF (which is 8 bits of 1s) left by 32 positions to reach the 32nd position
    if ((millsBitmask & (0xFF << 32)) != 0) {
      logger.e('Bits 32 to 39 are not zero.');
      return false;
    }

    // Part 15: Half-move clock
    final int halfMoveClock = int.parse(parts[15]);
    if (halfMoveClock < 0) {
      logger.e('Invalid half-move clock. Cannot be negative.');
      return false;
    }

    // Part 16: Full move number
    final int fullMoveNumber = int.parse(parts[16]);
    if (fullMoveNumber < 1) {
      logger.e('Invalid full move number. Must start at 1.');
      return false;
    }

    if (!_validateCustodianFen(custodianData)) {
      return false;
    }

    if (!_validateInterventionFen(interventionData)) {
      return false;
    }

    return true;
  }

  @visibleForTesting
  bool doMove(String move) {
    // TODO: Resign is not implemented
    if (move.length > "Player".length &&
        move.substring(0, "Player".length - 1) == "Player") {
      // TODO: What?
      if (move["Player".length] == "1") {
        return _resign(PieceColor.white);
      } else {
        return _resign(PieceColor.black);
      }
    }

    // TODO: Right?
    if (move == "Threefold Repetition. Draw!") {
      return true;
    }

    // TODO: Duplicate with switch (m.type) and should throw exception.
    if (move == "none") {
      return false;
    }

    // TODO: Duplicate with switch (m.type)
    if (move == "draw") {
      phase = Phase.gameOver;
      winner = PieceColor.draw;

      score[PieceColor.draw] = score[PieceColor.draw]! + 1;

      // TODO: WAR to judge rule50, and endgameNMoveRule is not right.
      if (DB().ruleSettings.nMoveRule > 0 &&
          posKeyHistory.length >= DB().ruleSettings.nMoveRule - 1) {
        gameOverReason = GameOverReason.drawFiftyMove;
      } else if (DB().ruleSettings.endgameNMoveRule <
              DB().ruleSettings.nMoveRule &&
          _isThreeEndgame &&
          posKeyHistory.length >= DB().ruleSettings.endgameNMoveRule - 1) {
        gameOverReason = GameOverReason.drawEndgameFiftyMove;
      } else if (DB().ruleSettings.threefoldRepetitionRule) {
        gameOverReason = GameOverReason.drawThreefoldRepetition; // TODO: Sure?
      } else {
        gameOverReason = GameOverReason.drawFullBoard; // TODO: Sure?
      }

      return true;
    }

    // TODO: Above is diff from position.cpp

    bool ret = false;

    final ExtMove m = ExtMove(move, side: _sideToMove);

    // TODO: [Leptopoda] The below functions should all throw exceptions so the ret and conditional stuff can be removed
    switch (m.type) {
      case MoveType.remove:
        if (_removePiece(m.to) == const GameResponseOK()) {
          ret = true;
          st.rule50 = 0;

          GameController().gameInstance.removeIndex = squareToIndex[m.to];
          GameController().gameInstance.blurIndex = null;
          GameController().gameInstance.focusIndex = null;
          GameController().animationManager.animateRemove();
        } else {
          return false;
        }

        GameController().gameRecorder.lastPositionWithRemove =
            GameController().position.fen;

        break;
      case MoveType.move:
        ret = _movePiece(m.from, m.to);
        if (ret) {
          ++st.rule50;
          GameController().gameInstance.removeIndex = null;
          GameController().gameInstance.blurIndex = squareToIndex[m.from];
          GameController().gameInstance.focusIndex = squareToIndex[m.to];
          GameController().animationManager.animateMove();
        }
        break;
      case MoveType.place:
        ret = _putPiece(m.to);
        if (ret) {
          // Reset rule 50 counter
          st.rule50 = 0;
          GameController().gameInstance.removeIndex = null;
          //GameController().gameInstance.focusIndex = squareToIndex[m.to];
          //GameController().gameInstance.blurIndex = squareToIndex[m.from];
          GameController().animationManager.animatePlace();
        }
        break;
      case MoveType.draw:
        return false; // TODO
      case MoveType.none:
        throw const EngineNoBestMove();
    }

    if (!ret) {
      return false;
    }

    // Increment ply counters. In particular, rule50 will be reset to zero later on
    // in case of a capture.
    ++_gamePly;
    ++st.pliesFromNull;

    // Check move type instead of string length for position key history
    if (_record != null && _record!.type == MoveType.move) {
      if (st.key != posKeyHistory.lastF) {
        posKeyHistory.add(st.key);
        if (DB().ruleSettings.threefoldRepetitionRule && _hasGameCycle) {
          setGameOver(PieceColor.draw, GameOverReason.drawThreefoldRepetition);
        }
      }
    } else {
      posKeyHistory.clear();
    }

    return true;
  }

  bool get _hasGameCycle {
    final int repetition = posKeyHistory.where((int i) => st.key == i).length;

    if (repetition >= 3) {
      logger.i("[position] Has game cycle.");
      return true;
    }

    return false;
  }

  ///////////////////////////////////////////////////////////////////////////////

  @visibleForTesting
  bool putPieceForTest(int s) {
    return _putPiece(s);
  }

  bool _putPiece(int s) {
    final PieceColor us = _sideToMove;

    if (phase == Phase.gameOver ||
        !(sqBegin <= s && s < sqEnd) ||
        _board[s] == us.opponent ||
        _board[s] == PieceColor.marked) {
      return false;
    }

    if (!canMoveDuringPlacingPhase() && _board[s] != PieceColor.none) {
      return false;
    }

    if (DB().ruleSettings.restrictRepeatedMillsFormation &&
        _currentSquare[us] == _lastMillToSquare[us] &&
        _currentSquare[us] != 0 &&
        s == _lastMillFromSquare[us]) {
      if (_potentialMillsCount(s, us, from: _currentSquare[us]!) > 0 &&
          _potentialMillsCount(_currentSquare[us]!, us) > 0) {
        // TODO: Show text
        rootScaffoldMessengerKey.currentState!.showSnackBarClear("3->3 X");
        return false;
      }
    }

    isNeedStalemateRemoval = false;

    if (phase == Phase.placing && action == Act.place) {
      if (canMoveDuringPlacingPhase()) {
        if (_board[s] == PieceColor.none) {
          if (_currentSquare[us] != 0) {
            return handleMovingPhaseForPutPiece(s);
          } else {
            selectedPieceNumber = 0;
            GameController().gameInstance.blurIndex = null;
          }
        } else {
          // Select piece
          if (_currentSquare[us] == s) {
            // Deselecting the currently selected piece
            _currentSquare[us] = 0;
            selectedPieceNumber = 0;
            GameController().gameInstance.focusIndex = null;
            GameController().gameInstance.blurIndex = null;
            // Reverse the pick-up animation to animate piece going back down
            GameController().animationManager.reversePickUp();
            // The piece is put back down (not a mill). Use the "place" sound.
            if (DB().displaySettings.isPiecePickUpAnimationEnabled) {
              SoundManager().playTone(Sound.place);
            }
          } else {
            _currentSquare[us] = s;
            GameController().gameInstance.focusIndex = squareToIndex[s];
            SoundManager().playTone(Sound.select);
          }
          selectedPieceNumber = sqAttrList[s].placedPieceNumber;
          GameController().gameInstance.blurIndex = null;
          return true;
        }
      }

      if (pieceInHandCount[us] != null) {
        if (pieceInHandCount[us] == 0) {
          // TODO: Maybe setup invalid position and tap the board.
          rootScaffoldMessengerKey.currentState!.showSnackBarClear(
            "FEN: ${GameController().position.fen}",
          );
          return false;
        }
        pieceInHandCount[us] = pieceInHandCount[us]! - 1;
      }

      if (pieceOnBoardCount[us] != null) {
        pieceOnBoardCount[us] = pieceOnBoardCount[us]! + 1;
      }

      // Set square number
      placedPieceNumber++;
      sqAttrList[s].placedPieceNumber = placedPieceNumber;

      _grid[squareToIndex[s]!] = sideToMove;
      _board[s] = sideToMove;

      _currentSquare[sideToMove] = 0;
      _lastMillFromSquare[sideToMove] = _lastMillToSquare[sideToMove] = 0;

      // Record includes boardLayout
      _record = ExtMove(
        ExtMove.sqToNotation(s),
        side: us,
        boardLayout: generateBoardLayoutAfterThisMove(),
        moveIndex: _gamePly,
        roundIndex: _roundNumber,
      );

      _updateKey(s);

      final int n = _millsCount(s);

      // Early exit: check if any capture rules are enabled
      final bool anyCaptureEnabled =
          DB().ruleSettings.enableCustodianCapture ||
          DB().ruleSettings.enableInterventionCapture ||
          DB().ruleSettings.enableLeapCapture;

      int custodianRemoval = 0;
      int interventionRemoval = 0;
      bool hasCustodianCapture = false;
      bool hasInterventionCapture = false;
      final List<int> custodianCaptured = <int>[];
      final List<int> interventionCaptured = <int>[];

      // Only check captures if rules are enabled
      // Note: Leap capture is NOT checked here in placing phase because:
      // - When placing a new piece (no movement), leap doesn't apply
      // - When mayMoveInPlacingPhase is enabled and moving a piece,
      //   the code path goes through handleMovingPhaseForPutPiece instead
      if (anyCaptureEnabled) {
        if (DB().ruleSettings.enableCustodianCapture) {
          hasCustodianCapture = _checkCustodianCapture(
            s,
            us,
            custodianCaptured,
          );
        }
        if (DB().ruleSettings.enableInterventionCapture) {
          hasInterventionCapture = _checkInterventionCapture(
            s,
            us,
            interventionCaptured,
          );
        }
        // Leap capture is handled in handleMovingPhaseForPutPiece
        // when mayMoveInPlacingPhase is enabled
      }

      if (n == 0) {
        // If no Mill

        if (pieceToRemoveCount[PieceColor.white]! != 0 ||
            pieceToRemoveCount[PieceColor.black]! != 0) {
          logger.e("[position] putPiece: pieceToRemoveCount is not 0.");
          return false;
        }

        _lastMillToSquare[sideToMove] = 0;
        _lastMillToSquare[sideToMove] = 0;

        // Only activate captures if any were detected
        if (hasCustodianCapture) {
          custodianRemoval = _activateCustodianCapture(us, custodianCaptured);
        } else if (anyCaptureEnabled) {
          _setCustodianCaptureState(us, 0, 0);
        }

        if (hasInterventionCapture) {
          interventionRemoval = _activateInterventionCapture(
            us,
            interventionCaptured,
          );
        } else if (anyCaptureEnabled) {
          _setInterventionCaptureState(us, 0, 0);
        }

        // Leap capture is not applicable in placing phase
        final int totalCaptureRemoval = custodianRemoval + interventionRemoval;

        if (totalCaptureRemoval > 0) {
          // No mill, only custodian/intervention capture is available
          _millAvailableAtRemoval[sideToMove] = false;
          pieceToRemoveCount[sideToMove] = totalCaptureRemoval;
          _updateKeyMisc();
          action = Act.remove;
          // Don't return here - need to check placing phase end logic
        }

        // Only play sound and set focus if no capture was triggered
        if (totalCaptureRemoval == 0) {
          GameController().gameInstance.focusIndex = squareToIndex[s];
          // Sound plays when piece lands (put-down animation completes)
          // If pick-up animation is disabled, play immediately
          if (!DB().displaySettings.isPiecePickUpAnimationEnabled) {
            SoundManager().playTone(Sound.place);
          }
        }

        if (DB().ruleSettings.millFormationActionInPlacingPhase ==
            MillFormationActionInPlacingPhase.removalBasedOnMillCounts) {
          if (pieceInHandCount[PieceColor.white]! == 0 &&
              pieceInHandCount[PieceColor.black]! == 0) {
            if (!handlePlacingPhaseEnd()) {
              changeSideToMove();
            }

            // Check if Stalemate and change side to move if needed
            if (_checkIfGameIsOver()) {
              return true;
            }
            return true;
          }
        }

        // If we have custodian capture to handle, return early
        if (totalCaptureRemoval > 0 && pieceToRemoveCount[sideToMove]! > 0) {
          return true;
        }

        // Begin of set side to move

        // Check if only two empty squares remain - force transition to
        // moving phase (only for 12-piece games when rule is enabled)
        if (DB().ruleSettings.piecesCount == 12 &&
            DB().ruleSettings.stopPlacingWhenTwoEmptySquares &&
            _countEmptySquares() == 2) {
          // Clear all remaining pieces in hand
          pieceInHandCount[PieceColor.white] = 0;
          pieceInHandCount[PieceColor.black] = 0;

          // Transition to moving phase
          if (!handlePlacingPhaseEnd()) {
            changeSideToMove();
          }

          // Check if game is over
          if (_checkIfGameIsOver()) {
            return true;
          }

          return true;
        }

        // Board is full at the end of Placing phase
        if (DB().ruleSettings.piecesCount == 12 &&
            (pieceOnBoardCount[PieceColor.white]! +
                    pieceOnBoardCount[PieceColor.black]! >=
                rankNumber * fileNumber)) {
          // TODO: BoardFullAction: Support other actions
          switch (DB().ruleSettings.boardFullAction) {
            case BoardFullAction.firstPlayerLose:
              setGameOver(PieceColor.black, GameOverReason.loseFullBoard);
              return true;
            case BoardFullAction.firstAndSecondPlayerRemovePiece:
              pieceToRemoveCount[PieceColor.white] =
                  pieceToRemoveCount[PieceColor.black] = 1;
              changeSideToMove();
              break;
            case BoardFullAction.secondAndFirstPlayerRemovePiece:
              pieceToRemoveCount[PieceColor.white] =
                  pieceToRemoveCount[PieceColor.black] = 1;
              keepSideToMove();
              break;
            case BoardFullAction.sideToMoveRemovePiece:
              _sideToMove = DB().ruleSettings.isDefenderMoveFirst
                  ? PieceColor.black
                  : PieceColor.white;
              pieceToRemoveCount[sideToMove] = 1;
              keepSideToMove();
              break;
            case BoardFullAction.agreeToDraw:
              setGameOver(PieceColor.draw, GameOverReason.drawFullBoard);
              return true;
            case null:
              logger.e("[position] putPiece: Invalid BoardFullAction.");
              break;
          }
        } else {
          // Board is not full at the end of Placing phase
          if (!handlePlacingPhaseEnd()) {
            changeSideToMove();
          }

          // Check if Stalemate and change side to move if needed
          if (_checkIfGameIsOver()) {
            return true;
          }
        }
        // End of set side to move
      } else {
        // If forming Mill
        int rm = 0;

        if (DB().ruleSettings.millFormationActionInPlacingPhase ==
            MillFormationActionInPlacingPhase.removalBasedOnMillCounts) {
          pieceToRemoveCount[sideToMove] = 0;
          _setCustodianCaptureState(us, 0, 0);
          _setInterventionCaptureState(us, 0, 0);
        } else {
          rm = DB().ruleSettings.mayRemoveMultiple ? n : 1;
          pieceToRemoveCount[sideToMove] = rm;
        }

        GameController().gameInstance.focusIndex = squareToIndex[s];
        // Play mill sound when the piece lands (put-down completes) when
        // animations are enabled; otherwise play immediately.
        //
        // Also create a one-shot barrier so AI can delay an immediate remove
        // move until the mill sound has finished, avoiding overlapping audio.
        final Game game = GameController().gameInstance;
        final bool canDelayMillSoundToLanding =
            DB().displaySettings.isPiecePickUpAnimationEnabled &&
            DB().displaySettings.animationDuration > 0 &&
            GameController().animationManager.allowAnimations;

        final Completer<void>? prevBarrier = game.pendingMillSoundCompleter;
        if (prevBarrier != null && !prevBarrier.isCompleted) {
          logger.w(
            "[position] pendingMillSoundCompleter was not completed; "
            "completing defensively.",
          );
          prevBarrier.complete();
        }

        if (canDelayMillSoundToLanding) {
          game.playMillSoundOnLanding = true;
          game.pendingMillSoundCompleter = Completer<void>();
        } else {
          final Completer<void> barrier = Completer<void>();
          game.pendingMillSoundCompleter = barrier;
          SoundManager().playToneAndWait(Sound.mill).whenComplete(() {
            if (!barrier.isCompleted) {
              barrier.complete();
            }
            if (game.pendingMillSoundCompleter == barrier) {
              game.pendingMillSoundCompleter = null;
            }
          });
        }

        if ((DB().ruleSettings.millFormationActionInPlacingPhase ==
                    MillFormationActionInPlacingPhase
                        .removeOpponentsPieceFromHandThenYourTurn ||
                DB().ruleSettings.millFormationActionInPlacingPhase ==
                    MillFormationActionInPlacingPhase
                        .removeOpponentsPieceFromHandThenOpponentsTurn) &&
            pieceInHandCount[_them] != null) {
          _setCustodianCaptureState(us, 0, 0);
          _setInterventionCaptureState(us, 0, 0);
          for (int i = 0; i < rm; i++) {
            if (pieceInHandCount[_them] == 0) {
              // Mill-based removal will follow
              _millAvailableAtRemoval[sideToMove] = true;
              pieceToRemoveCount[sideToMove] = rm - i;
              _updateKeyMisc();
              action = Act.remove;
              return true;
            } else {
              if (pieceInHandCount[_them] == 0) {
                logger.e("[position] putPiece: pieceInHandCount[_them] is 0.");
              }
              pieceInHandCount[_them] = pieceInHandCount[_them]! - 1;

              if (pieceToRemoveCount[sideToMove] == 0) {
                logger.e(
                  "[position] putPiece: pieceToRemoveCount[sideToMove] is 0.",
                );
              }
              pieceToRemoveCount[sideToMove] =
                  pieceToRemoveCount[sideToMove]! - 1;

              _updateKeyMisc();
            }

            if (!(pieceInHandCount[PieceColor.white]! >= 0 &&
                pieceInHandCount[PieceColor.black]! >= 0)) {
              logger.e("[position] putPiece: pieceInHandCount is negative.");
            }
          }

          if (!handlePlacingPhaseEnd()) {
            if (DB().ruleSettings.millFormationActionInPlacingPhase ==
                MillFormationActionInPlacingPhase
                    .removeOpponentsPieceFromHandThenOpponentsTurn) {
              changeSideToMove();
            }
          }

          if (_checkIfGameIsOver()) {
            return true;
          }
        } else {
          if (DB().ruleSettings.millFormationActionInPlacingPhase ==
              MillFormationActionInPlacingPhase.removalBasedOnMillCounts) {
            if (pieceInHandCount[PieceColor.white]! == 0 &&
                pieceInHandCount[PieceColor.black]! == 0) {
              if (!handlePlacingPhaseEnd()) {
                changeSideToMove();
              }

              // Check if Stalemate and change side to move if needed
              if (_checkIfGameIsOver()) {
                return true;
              }
              return true;
            } else {
              changeSideToMove();
            }
          } else {
            if (anyCaptureEnabled && DB().ruleSettings.mayRemoveMultiple) {
              int additionalRemoval = 0;

              if (hasCustodianCapture) {
                final int custodianRemoval = _activateCustodianCapture(
                  us,
                  custodianCaptured,
                );
                if (custodianRemoval > 0) {
                  additionalRemoval += custodianRemoval;
                } else {
                  _setCustodianCaptureState(us, 0, 0);
                }
              } else {
                _setCustodianCaptureState(us, 0, 0);
              }

              if (hasInterventionCapture) {
                final int interventionRemoval = _activateInterventionCapture(
                  us,
                  interventionCaptured,
                );
                if (interventionRemoval > 0) {
                  additionalRemoval += interventionRemoval;
                } else {
                  _setInterventionCaptureState(us, 0, 0);
                }
              } else {
                _setInterventionCaptureState(us, 0, 0);
              }

              if (additionalRemoval > 0) {
                pieceToRemoveCount[sideToMove] =
                    pieceToRemoveCount[sideToMove]! + additionalRemoval;
              }
            } else {
              // When mayRemoveMultiple is false, we still need to store capture
              // targets to allow player choice, but don't add to pieceToRemoveCount
              if (hasCustodianCapture) {
                _activateCustodianCapture(us, custodianCaptured);
              } else {
                _setCustodianCaptureState(us, 0, 0);
              }

              if (hasInterventionCapture) {
                _activateInterventionCapture(us, interventionCaptured);
              } else {
                _setInterventionCaptureState(us, 0, 0);
              }
            }

            // We are in mill-formed branch; entering removal due to mill
            _millAvailableAtRemoval[sideToMove] = true;
            _updateKeyMisc();
            action = Act.remove;
          }
          return true;
        }
      }
    } else if (phase == Phase.moving) {
      return handleMovingPhaseForPutPiece(s);
    } else {
      return false;
    }

    return true;
  }

  bool handleMovingPhaseForPutPiece(int s) {
    if (_board[s] != PieceColor.none) {
      return false;
    }

    if (_checkIfGameIsOver()) {
      return true;
    }

    // If illegal: normally restrict to adjacent moves unless we can legally
    // perform a leap capture in the moving phase.
    if (pieceOnBoardCount[sideToMove]! > DB().ruleSettings.flyPieceCount ||
        !DB().ruleSettings.mayFly ||
        pieceInHandCount[sideToMove]! > 0) {
      int md;
      bool isAdjacent = false;

      for (md = 0; md < moveDirectionNumber; md++) {
        if (s == _adjacentSquares[_currentSquare[sideToMove]!][md]) {
          isAdjacent = true;
          break;
        }
      }

      // Not in moveTable - check if leap is allowed
      if (!isAdjacent) {
        bool leapAllowed = false;
        if (DB().ruleSettings.enableLeapCapture &&
            DB().ruleSettings.leapCaptureInMovingPhase &&
            _currentSquare[sideToMove] != 0) {
          final List<int> tmp = <int>[];
          leapAllowed = _checkLeapCapture(
            s,
            sideToMove,
            tmp,
            _currentSquare[sideToMove],
          );
        }

        if (!leapAllowed) {
          logger.i(
            "[position] putPiece: [$s] is not in [${_currentSquare[sideToMove]}]'s move table.",
          );
          return false;
        }
      }
    }

    // Include boardLayout
    _record = ExtMove(
      "${ExtMove.sqToNotation(_currentSquare[sideToMove]!)}-${ExtMove.sqToNotation(s)}",
      side: sideToMove,
      boardLayout: generateBoardLayoutAfterThisMove(),
      moveIndex: _gamePly,
      roundIndex: _roundNumber,
    );

    st.rule50++;

    _board[s] = _grid[squareToIndex[s]!] = _board[_currentSquare[sideToMove]!];
    _updateKey(s);
    _revertKey(_currentSquare[sideToMove]!);

    if (_currentSquare[sideToMove] == 0) {
      // TODO: Find the root cause and fix it
      logger.e("[position] putPiece: _currentSquare[sideToMove] is 0.");
      return false;
    }
    _board[_currentSquare[sideToMove]!] =
        _grid[squareToIndex[_currentSquare[sideToMove]!]!] = PieceColor.none;

    // Set square number
    sqAttrList[s].placedPieceNumber = placedPieceNumber;

    if (selectedPieceNumber != 0) {
      sqAttrList[s].placedPieceNumber = selectedPieceNumber;
      selectedPieceNumber = 0;
    } else {
      sqAttrList[s].placedPieceNumber = placedPieceNumber;
    }

    final int n = _millsCount(s);

    // Early exit: check if any capture rules are enabled
    final bool anyCaptureEnabled =
        DB().ruleSettings.enableCustodianCapture ||
        DB().ruleSettings.enableInterventionCapture ||
        DB().ruleSettings.enableLeapCapture;

    int custodianRemoval = 0;
    int interventionRemoval = 0;
    int leapRemoval = 0;
    bool hasCustodianCapture = false;
    bool hasInterventionCapture = false;
    bool hasLeapCapture = false;
    final List<int> custodianCaptured = <int>[];
    final List<int> interventionCaptured = <int>[];
    final List<int> leapCaptured = <int>[];

    // Only check captures if rules are enabled
    if (anyCaptureEnabled) {
      if (DB().ruleSettings.enableCustodianCapture) {
        hasCustodianCapture = _checkCustodianCapture(
          s,
          sideToMove,
          custodianCaptured,
        );
      }
      if (DB().ruleSettings.enableInterventionCapture) {
        hasInterventionCapture = _checkInterventionCapture(
          s,
          sideToMove,
          interventionCaptured,
        );
      }
      if (DB().ruleSettings.enableLeapCapture) {
        hasLeapCapture = _checkLeapCapture(
          s,
          sideToMove,
          leapCaptured,
          _currentSquare[sideToMove],
        );
      }
    }

    if (n == 0) {
      // If no mill during Moving phase
      _currentSquare[sideToMove] = 0;
      _lastMillFromSquare[sideToMove] = _lastMillToSquare[sideToMove] = 0;

      // Only activate captures if any were detected. If leap capture is
      // available, it takes precedence over custodian/intervention. The
      // player must remove exactly the jumped piece and mill/custodian/
      // intervention removals are disallowed for this move.
      if (hasLeapCapture) {
        leapRemoval = _activateLeapCapture(sideToMove, leapCaptured);
        // Clear other capture modes to enforce single capture mode
        if (hasCustodianCapture || _custodianRemovalCount[sideToMove]! > 0) {
          _setCustodianCaptureState(sideToMove, 0, 0);
        }
        if (hasInterventionCapture ||
            _interventionRemovalCount[sideToMove]! > 0) {
          _setInterventionCaptureState(sideToMove, 0, 0);
        }
        // No mill available in a leap capture turn
        _millAvailableAtRemoval[sideToMove] = false;
        // Exactly one removal for leap capture
        pieceToRemoveCount[sideToMove] = 1;
        _updateKeyMisc();
        action = Act.remove;
        return true;
      } else {
        if (hasCustodianCapture) {
          custodianRemoval = _activateCustodianCapture(
            sideToMove,
            custodianCaptured,
          );
        } else if (anyCaptureEnabled) {
          _setCustodianCaptureState(sideToMove, 0, 0);
        }

        if (hasInterventionCapture) {
          interventionRemoval = _activateInterventionCapture(
            sideToMove,
            interventionCaptured,
          );
        } else if (anyCaptureEnabled) {
          _setInterventionCaptureState(sideToMove, 0, 0);
        }

        if (anyCaptureEnabled) {
          _setLeapCaptureState(sideToMove, 0, 0);
        }
      }

      final int totalCaptureRemoval =
          custodianRemoval + interventionRemoval + leapRemoval;

      if (totalCaptureRemoval > 0) {
        // No mill, only custodian/intervention/leap capture is available
        _millAvailableAtRemoval[sideToMove] = false;
        pieceToRemoveCount[sideToMove] = totalCaptureRemoval;
        _updateKeyMisc();
        action = Act.remove;
        GameController().gameInstance.focusIndex = squareToIndex[s];
        return true;
      }

      if (anyCaptureEnabled) {
        _setCustodianCaptureState(sideToMove, 0, 0);
        _setInterventionCaptureState(sideToMove, 0, 0);
        _setLeapCaptureState(sideToMove, 0, 0);
      }
      changeSideToMove();

      if (_checkIfGameIsOver()) {
        return true;
      }

      GameController().gameInstance.focusIndex = squareToIndex[s];

      // Sound plays when piece lands (put-down animation completes)
      // If pick-up animation is disabled, play immediately
      if (!DB().displaySettings.isPiecePickUpAnimationEnabled) {
        SoundManager().playTone(Sound.place);
      }
    } else {
      // If forming mill during Moving phase
      if (DB().ruleSettings.restrictRepeatedMillsFormation) {
        final int m = _potentialMillsCount(
          _currentSquare[sideToMove]!,
          sideToMove,
        );
        if (_currentSquare[sideToMove] == _lastMillToSquare[sideToMove] &&
            s == _lastMillFromSquare[sideToMove] &&
            m > 0) {
          return false;
        }

        if (m > 0) {
          _lastMillFromSquare[sideToMove] = _currentSquare[sideToMove]!;
          _lastMillToSquare[sideToMove] = s;
        } else {
          _lastMillFromSquare[sideToMove] = 0;
          _lastMillToSquare[sideToMove] = 0;
        }
      }

      _currentSquare[sideToMove] = 0;

      // Force leap capture precedence over mill when a leap capture is
      // available on the same move that also forms a mill. According to the
      // rule, the player must resolve the leap capture (remove exactly the
      // jumped piece), mill removal is not allowed in this case, and the turn
      // passes immediately to the opponent after the single removal.
      if (hasLeapCapture) {
        // Activate only leap capture and clear the other capture states
        _activateLeapCapture(sideToMove, leapCaptured);
        if (hasCustodianCapture || _custodianRemovalCount[sideToMove]! > 0) {
          _setCustodianCaptureState(sideToMove, 0, 0);
        }
        if (hasInterventionCapture ||
            _interventionRemovalCount[sideToMove]! > 0) {
          _setInterventionCaptureState(sideToMove, 0, 0);
        }

        // Disallow mill removal and restrict to exactly one removal
        _millAvailableAtRemoval[sideToMove] = false;
        pieceToRemoveCount[sideToMove] = 1;
        _updateKeyMisc();
        action = Act.remove;
        GameController().gameInstance.focusIndex = squareToIndex[s];
        return true;
      }

      // When leap is not available, allow mill vs custodian/intervention
      // choice. Initially publish capture targets; the first removal will
      // determine the mode.
      if (anyCaptureEnabled) {
        if (hasCustodianCapture) {
          _activateCustodianCapture(sideToMove, custodianCaptured);
        } else {
          _setCustodianCaptureState(sideToMove, 0, 0);
        }

        if (hasInterventionCapture) {
          _activateInterventionCapture(sideToMove, interventionCaptured);
        } else {
          _setInterventionCaptureState(sideToMove, 0, 0);
        }
      }

      // Start with mill removal count; first removal may switch to capture
      pieceToRemoveCount[sideToMove] = DB().ruleSettings.mayRemoveMultiple
          ? n
          : 1;

      // Mill is available at removal start
      _millAvailableAtRemoval[sideToMove] = true;
      _updateKeyMisc();
      action = Act.remove;
      GameController().gameInstance.focusIndex = squareToIndex[s];
      // Play mill sound when the piece lands (put-down completes) when
      // animations are enabled; otherwise play immediately.
      //
      // Also create a one-shot barrier so AI can delay an immediate remove
      // move until the mill sound has finished, avoiding overlapping audio.
      final Game game = GameController().gameInstance;
      final bool canDelayMillSoundToLanding =
          DB().displaySettings.isPiecePickUpAnimationEnabled &&
          DB().displaySettings.animationDuration > 0 &&
          GameController().animationManager.allowAnimations;

      final Completer<void>? prevBarrier = game.pendingMillSoundCompleter;
      if (prevBarrier != null && !prevBarrier.isCompleted) {
        logger.w(
          "[position] pendingMillSoundCompleter was not completed; "
          "completing defensively.",
        );
        prevBarrier.complete();
      }

      if (canDelayMillSoundToLanding) {
        game.playMillSoundOnLanding = true;
        game.pendingMillSoundCompleter = Completer<void>();
      } else {
        final Completer<void> barrier = Completer<void>();
        game.pendingMillSoundCompleter = barrier;
        SoundManager().playToneAndWait(Sound.mill).whenComplete(() {
          if (!barrier.isCompleted) {
            barrier.complete();
          }
          if (game.pendingMillSoundCompleter == barrier) {
            game.pendingMillSoundCompleter = null;
          }
        });
      }
    }

    return true;
  }

  @visibleForTesting
  GameResponse removePieceForTest(int s) {
    return _removePiece(s);
  }

  GameResponse _removePiece(int s) {
    if (phase == Phase.ready || phase == Phase.gameOver) {
      return const IllegalPhase();
    }

    if (action != Act.remove) {
      return const IllegalAction();
    }

    final int mask = squareBb(s);
    final int custodianTargets = _custodianCaptureTargets[sideToMove]!;
    final int custodianCount = _custodianRemovalCount[sideToMove]!;
    final int interventionTargets = _interventionCaptureTargets[sideToMove]!;
    final int interventionCount = _interventionRemovalCount[sideToMove]!;
    final int leapTargets = _leapCaptureTargets[sideToMove]!;
    final int leapCount = _leapRemovalCount[sideToMove]!;
    final int remainingRemovals = pieceToRemoveCount[sideToMove]!;

    if (remainingRemovals == 0) {
      return const NoPieceToRemove();
    } else if (remainingRemovals > 0) {
      if (_board[s] != sideToMove.opponent) {
        return const CanNotRemoveSelf();
      }

      final bool isCustodianTarget = (custodianTargets & mask) != 0;
      final bool isInterventionTarget = (interventionTargets & mask) != 0;
      final bool isLeapTarget = (leapTargets & mask) != 0;
      final bool isCaptureTarget =
          isCustodianTarget || isInterventionTarget || isLeapTarget;
      final int captureCount = custodianCount + interventionCount + leapCount;
      final bool millAvailable = _millAvailableAtRemoval[sideToMove] ?? false;

      // If the first removal chooses a custodian/intervention/leap target when
      // mill is also available, lock the capture mode and disallow mill.
      // For intervention: always enforce removal count equals the intervention
      // obligation so the next removal must take the paired piece, regardless
      // of mayRemoveMultiple setting.
      // For custodian: always only removes one piece, regardless of mayRemoveMultiple.
      // For leap: always only removes one piece, regardless of mayRemoveMultiple.
      if (isInterventionTarget && interventionCount > 0) {
        // Choosing intervention capture locks out mill
        _millAvailableAtRemoval[sideToMove] = false;
        if (custodianTargets != 0 || custodianCount > 0) {
          _setCustodianCaptureState(sideToMove, 0, 0);
        }
        if (leapTargets != 0 || leapCount > 0) {
          _setLeapCaptureState(sideToMove, 0, 0);
        }
        // Intervention capture always requires removing both pieces from the line
        pieceToRemoveCount[sideToMove] = interventionCount;
      } else if (isCustodianTarget && custodianCount > 0) {
        // Choosing custodian capture locks out mill
        _millAvailableAtRemoval[sideToMove] = false;
        if (interventionTargets != 0 || interventionCount > 0) {
          _setInterventionCaptureState(sideToMove, 0, 0);
        }
        if (leapTargets != 0 || leapCount > 0) {
          _setLeapCaptureState(sideToMove, 0, 0);
        }
        // Custodian capture always only removes one piece (the trapped piece)
        pieceToRemoveCount[sideToMove] = 1;
      } else if (isLeapTarget && leapCount > 0) {
        // Choosing leap capture locks out mill
        _millAvailableAtRemoval[sideToMove] = false;
        if (interventionTargets != 0 || interventionCount > 0) {
          _setInterventionCaptureState(sideToMove, 0, 0);
        }
        if (custodianTargets != 0 || custodianCount > 0) {
          _setCustodianCaptureState(sideToMove, 0, 0);
        }
        // Leap capture always removes exactly one piece
        pieceToRemoveCount[sideToMove] = 1;
      }

      // Allow player to choose between mill capture and custodian/intervention/leap capture
      // When multiple capture modes are available, player's first removal determines the mode
      if (millAvailable && !isCaptureTarget && captureCount > 0) {
        // Player chooses mill capture over custodian/intervention/leap
        // When switching to mill mode, subtract the pre-added capture counts
        // that were added during placing phase (if mayRemoveMultiple was true)
        if (pieceToRemoveCount[sideToMove]! > captureCount) {
          pieceToRemoveCount[sideToMove] =
              pieceToRemoveCount[sideToMove]! - captureCount;
          _updateKeyMisc();
        }
        // Clear custodian/intervention/leap state to enforce single capture mode selection
        _setCustodianCaptureState(sideToMove, 0, 0);
        _setInterventionCaptureState(sideToMove, 0, 0);
        _setLeapCaptureState(sideToMove, 0, 0);
      } else if (!millAvailable && !isCaptureTarget && captureCount > 0) {
        // No mill available: must remove only from custodian/intervention/leap targets
        return const IllegalAction();
      } else if (!isCaptureTarget && captureCount >= remainingRemovals) {
        // No mill available: must remove only from capture targets
        return const IllegalAction();
      }

      if (isCustodianTarget && custodianCount > 0) {
        int newTargets = custodianTargets & ~mask;
        final int newCount = custodianCount - 1;

        if (newCount <= 0) {
          newTargets = 0;
        }

        _setCustodianCaptureState(sideToMove, newTargets, newCount);
      }

      if (isInterventionTarget && interventionCount > 0) {
        int newTargets = interventionTargets & ~mask;
        final int newCount = interventionCount - 1;

        if (newCount <= 0) {
          newTargets = 0;
        } else if (newCount == 1 && interventionCount == 2) {
          // When removing the first of two intervention targets,
          // ensure the second target is from the same line
          // This enforces the rule that intervention capture must remove pieces from one line
          newTargets = _findPairedInterventionTarget(s, interventionTargets);
        }

        _setInterventionCaptureState(sideToMove, newTargets, newCount);
      }

      if (isLeapTarget && leapCount > 0) {
        int newTargets = leapTargets & ~mask;
        final int newCount = leapCount - 1;

        if (newCount <= 0) {
          newTargets = 0;
        }

        _setLeapCaptureState(sideToMove, newTargets, newCount);
      }
    } else {
      if (_board[s] != sideToMove) {
        return const ShouldRemoveSelf();
      }

      if (_custodianCaptureTargets[sideToMove]! != 0 ||
          _custodianRemovalCount[sideToMove]! != 0) {
        _setCustodianCaptureState(sideToMove, 0, 0);
      }

      if (_interventionCaptureTargets[sideToMove]! != 0 ||
          _interventionRemovalCount[sideToMove]! != 0) {
        _setInterventionCaptureState(sideToMove, 0, 0);
      }

      if (_leapCaptureTargets[sideToMove]! != 0 ||
          _leapRemovalCount[sideToMove]! != 0) {
        _setLeapCaptureState(sideToMove, 0, 0);
      }
    }

    if (isStalemateRemoval(sideToMove)) {
      if (isAdjacentTo(s, sideToMove) == false) {
        return const CanNotRemoveNonadjacent();
      }
    } else if (!DB().ruleSettings.mayRemoveFromMillsAlways &&
        _potentialMillsCount(s, PieceColor.nobody) > 0 &&
        !_isAllInMills(sideToMove.opponent)) {
      return const CanNotRemoveMill();
    }

    // Cache remove animation info for UI.
    // The piece is cleared from the board state before the remove animation
    // begins, so the painter needs this cached color to draw the removed piece.
    GameController().gameInstance.removePieceColor = _board[s];
    GameController().gameInstance.removeByColor = sideToMove;

    _revertKey(s);

    if (DB().ruleSettings.millFormationActionInPlacingPhase ==
            MillFormationActionInPlacingPhase.markAndDelayRemovingPieces &&
        phase == Phase.placing) {
      // Remove and mark
      _board[s] = _grid[squareToIndex[s]!] = PieceColor.marked;
      _updateKey(s);
    } else {
      // Remove only
      _board[s] = _grid[squareToIndex[s]!] = PieceColor.none;
    }

    // Record includes boardLayout
    _record = ExtMove(
      "x${ExtMove.sqToNotation(s)}",
      side: sideToMove,
      boardLayout: generateBoardLayoutAfterThisMove(),
      moveIndex: _gamePly,
      roundIndex: _roundNumber,
    );
    st.rule50 = 0; // TODO: Need to move out?

    if (pieceOnBoardCount[_them] != null) {
      pieceOnBoardCount[_them] = pieceOnBoardCount[_them]! - 1;
    }

    if (pieceOnBoardCount[_them]! + pieceInHandCount[_them]! <
        DB().ruleSettings.piecesAtLeastCount) {
      setGameOver(sideToMove, GameOverReason.loseFewerThanThree);
      SoundManager().playTone(Sound.remove);
      return const GameResponseOK();
    }

    _currentSquare[sideToMove] = 0;

    if (pieceToRemoveCount[sideToMove]! > 0) {
      pieceToRemoveCount[sideToMove] = pieceToRemoveCount[sideToMove]! - 1;
    } else {
      pieceToRemoveCount[sideToMove] = pieceToRemoveCount[sideToMove]! + 1;
    }

    _updateKeyMisc();

    // Need to remove rest pieces.
    if (pieceToRemoveCount[sideToMove] != 0) {
      SoundManager().playTone(Sound.remove);
      return const GameResponseOK();
    }

    // Clear mill availability at end of removal phase
    _millAvailableAtRemoval[sideToMove] = false;
    _setCustodianCaptureState(sideToMove, 0, 0);
    _setInterventionCaptureState(sideToMove, 0, 0);

    // Clear preferred remove target after all removals are complete
    preferredRemoveTarget = null;

    if (handlePlacingPhaseEnd() == false) {
      if (isStalemateRemoving) {
        isStalemateRemoving = false;
        keepSideToMove();
      } else {
        changeSideToMove();
      }
    }

    if (pieceToRemoveCount[sideToMove] != 0) {
      // Audios().playTone(Sound.remove);
      return const GameResponseOK();
    }

    // Clear the both-stalemate-removing flag once both sides have
    // finished their stalemate removals.
    if (isBothStalemateRemoving) {
      isBothStalemateRemoving = false;
    }

    if (pieceInHandCount[sideToMove] == 0) {
      if (_checkIfGameIsOver()) {
        SoundManager().playTone(Sound.remove);
        return const GameResponseOK();
      }
    }

    SoundManager().playTone(Sound.remove);
    return const GameResponseOK();
  }

  /// Get all capturable pieces for the current side to move
  /// Returns a list of square indices that can be captured
  List<int> getCapturablePieces() {
    final List<int> capturablePieces = <int>[];

    // Only show capturable pieces when it's removal phase
    if (action != Act.remove) {
      return capturablePieces;
    }

    final int remainingRemovals = pieceToRemoveCount[sideToMove]!;
    if (remainingRemovals == 0) {
      return capturablePieces;
    }

    final int custodianTargets = _custodianCaptureTargets[sideToMove]!;
    final int custodianCount = _custodianRemovalCount[sideToMove]!;
    final int interventionTargets = _interventionCaptureTargets[sideToMove]!;
    final int interventionCount = _interventionRemovalCount[sideToMove]!;
    final int leapTargets = _leapCaptureTargets[sideToMove]!;
    final int leapCount = _leapRemovalCount[sideToMove]!;

    final int captureCount = custodianCount + interventionCount + leapCount;

    // Check each square on the board
    for (int s = sqBegin; s < sqEnd; s++) {
      // Must be opponent's piece
      if (_board[s] != sideToMove.opponent) {
        continue;
      }

      final int mask = squareBb(s);
      final bool isCustodianTarget = (custodianTargets & mask) != 0;
      final bool isInterventionTarget = (interventionTargets & mask) != 0;
      final bool isLeapTarget = (leapTargets & mask) != 0;
      final bool isCaptureTarget =
          isCustodianTarget || isInterventionTarget || isLeapTarget;

      // If there are capture obligations, only those pieces are capturable
      if (captureCount > 0) {
        if (isCaptureTarget) {
          capturablePieces.add(s);
        }
        continue;
      }

      // If no capture obligations, check mill rules
      if (!DB().ruleSettings.mayRemoveFromMillsAlways &&
          _potentialMillsCount(s, PieceColor.nobody) > 0 &&
          !_isAllInMills(sideToMove.opponent)) {
        // Piece is in a mill and cannot be removed
        continue;
      }

      // This piece is capturable
      capturablePieces.add(s);
    }

    return capturablePieces;
  }

  GameResponse _selectPiece(int sq) {
    // Allow selecting pieces during placing phase if allowed
    if (phase != Phase.moving &&
        !(phase == Phase.placing && canMoveDuringPlacingPhase())) {
      return const IllegalPhase();
    }

    if (action != Act.select && action != Act.place) {
      return const IllegalAction();
    }

    if (_board[sq] == PieceColor.none) {
      return const NoPieceSelected();
    }

    if (!(_board[sq] == sideToMove)) {
      return const SelectOurPieceToMove();
    }

    _currentSquare[sideToMove] = sq;
    action = Act.place;
    GameController().gameInstance.blurIndex = squareToIndex[sq];

    // Trigger pick-up animation when piece is selected
    GameController().animationManager.animatePickUp();

    // Set square number
    selectedPieceNumber = sqAttrList[sq].placedPieceNumber;

    return const GameResponseOK();
  }

  bool handlePlacingPhaseEnd() {
    if (phase != Phase.placing ||
        pieceInHandCount[PieceColor.white]! > 0 ||
        pieceInHandCount[PieceColor.black]! > 0 ||
        pieceToRemoveCount[PieceColor.white]!.abs() > 0 ||
        pieceToRemoveCount[PieceColor.black]!.abs() > 0) {
      return false;
    }

    final bool invariant =
        DB().ruleSettings.millFormationActionInPlacingPhase ==
            MillFormationActionInPlacingPhase
                .removeOpponentsPieceFromHandThenOpponentsTurn ||
        (DB().ruleSettings.millFormationActionInPlacingPhase ==
                MillFormationActionInPlacingPhase
                    .removeOpponentsPieceFromHandThenYourTurn &&
            DB().ruleSettings.mayRemoveMultiple == true) ||
        DB().ruleSettings.mayMoveInPlacingPhase == true;

    if (DB().ruleSettings.millFormationActionInPlacingPhase ==
        MillFormationActionInPlacingPhase.markAndDelayRemovingPieces) {
      _removeMarkedStones();
    } else if (DB().ruleSettings.millFormationActionInPlacingPhase ==
        MillFormationActionInPlacingPhase.removalBasedOnMillCounts) {
      _calculateRemovalBasedOnMillCounts();
    } else if (invariant) {
      if (DB().ruleSettings.isDefenderMoveFirst == true) {
        setSideToMove(PieceColor.black);
        return true;
      } else {
        // Ignore
        return false;
      }
    }

    setSideToMove(
      DB().ruleSettings.isDefenderMoveFirst == true
          ? PieceColor.black
          : PieceColor.white,
    );

    return true;
  }

  bool canMoveDuringPlacingPhase() {
    return DB().ruleSettings.mayMoveInPlacingPhase;
  }

  bool _resign(PieceColor loser) {
    if (phase == Phase.ready || phase == Phase.gameOver) {
      return false;
    }

    setGameOver(loser.opponent, GameOverReason.loseResign);

    return true;
  }

  void setGameOver(PieceColor w, GameOverReason reason) {
    phase = Phase.gameOver;
    gameOverReason = reason;
    winner = w;

    logger.i("[position] Game over, $w win, because of $reason");
    _updateScore();

    GameController().gameInstance.focusIndex = null;
    GameController().gameInstance.blurIndex = null;
    GameController().gameInstance.removeIndex = null;
  }

  void _updateScore() {
    if (phase == Phase.gameOver) {
      score[winner] = score[winner]! + 1;
    }
  }

  bool get _isThreeEndgame {
    if (phase == Phase.placing) {
      return false;
    }

    return pieceOnBoardCount[PieceColor.white] == 3 ||
        pieceOnBoardCount[PieceColor.black] == 3;
  }

  bool _checkIfGameIsOver() {
    if (phase == Phase.ready || phase == Phase.gameOver) {
      return true;
    }

    if (pieceOnBoardCount[sideToMove]! + pieceInHandCount[sideToMove]! <
        DB().ruleSettings.piecesAtLeastCount) {
      // Engine doesn't have this because of improving performance.
      setGameOver(sideToMove.opponent, GameOverReason.loseFewerThanThree);
      return true;
    }

    if (DB().ruleSettings.nMoveRule > 0 &&
        posKeyHistory.length >= DB().ruleSettings.nMoveRule) {
      setGameOver(PieceColor.draw, GameOverReason.drawFiftyMove);
      return true;
    }

    if (DB().ruleSettings.endgameNMoveRule < DB().ruleSettings.nMoveRule &&
        _isThreeEndgame &&
        posKeyHistory.length >= DB().ruleSettings.endgameNMoveRule) {
      setGameOver(PieceColor.draw, GameOverReason.drawEndgameFiftyMove);
      return true;
    }

    // Stalemate.
    if (phase == Phase.moving &&
        action == Act.select &&
        _isAllSurrounded(sideToMove)) {
      switch (DB().ruleSettings.stalemateAction) {
        case StalemateAction.endWithStalemateLoss:
          setGameOver(sideToMove.opponent, GameOverReason.loseNoLegalMoves);
          return true;
        case StalemateAction.changeSideToMove:
          changeSideToMove(); // TODO(calcitem): Need?
          break;
        case StalemateAction.removeOpponentsPieceAndMakeNextMove:
          pieceToRemoveCount[sideToMove] = 1;
          isStalemateRemoving = true;
          break;
        case StalemateAction.removeOpponentsPieceAndChangeSideToMove:
          pieceToRemoveCount[sideToMove] = 1;
          break;
        case StalemateAction.endWithStalemateDraw:
          setGameOver(PieceColor.draw, GameOverReason.drawStalemateCondition);
          return true;
        case StalemateAction.bothPlayersRemoveOpponentsPiece:
          // Both players remove one of the opponent's adjacent pieces,
          // then the game continues. The stalemated side removes first.
          pieceToRemoveCount[sideToMove] = 1;
          pieceToRemoveCount[sideToMove.opponent] = 1;
          // Track that both sides are performing stalemate removals
          // so adjacency restriction is enforced for both removals.
          isBothStalemateRemoving = true;
          break;
        case null:
          logger.e("[position] _checkIfGameIsOver: Invalid StalemateAction.");
          break;
      }
    }

    if (pieceToRemoveCount[sideToMove]! > 0 ||
        pieceToRemoveCount[sideToMove]! < 0) {
      action = Act.remove;
    }

    return false;
  }

  void _removeMarkedStones() {
    assert(
      DB().ruleSettings.millFormationActionInPlacingPhase ==
          MillFormationActionInPlacingPhase.markAndDelayRemovingPieces,
    );

    int s = 0;

    for (int f = 1; f <= fileNumber; f++) {
      for (int r = 0; r < rankNumber; r++) {
        s = f * rankNumber + r;

        if (_board[s] == PieceColor.marked) {
          _board[s] = _grid[squareToIndex[s]!] = PieceColor.none;
          _revertKey(s);
        }
      }
    }
  }

  void _calculateRemovalBasedOnMillCounts() {
    final int whiteMills = totalMillsCount(PieceColor.white);
    final int blackMills = totalMillsCount(PieceColor.black);

    int whiteRemove = 1;
    int blackRemove = 1;

    if (whiteMills == 0 && blackMills == 0) {
      whiteRemove = -1;
      blackRemove = -1;
    } else if (whiteMills > 0 && blackMills == 0) {
      whiteRemove = 2;
      blackRemove = 1;
    } else if (blackMills > 0 && whiteMills == 0) {
      whiteRemove = 1;
      blackRemove = 2;
    } else {
      if (whiteMills == blackMills) {
        whiteRemove = whiteMills;
        blackRemove = blackMills;
      } else {
        if (whiteMills > blackMills) {
          blackRemove = blackMills;
          whiteRemove = blackRemove + 1;
        } else if (whiteMills < blackMills) {
          whiteRemove = whiteMills;
          blackRemove = whiteRemove + 1;
        } else {
          assert(false);
        }
      }
    }

    pieceToRemoveCount[PieceColor.white] = whiteRemove;
    pieceToRemoveCount[PieceColor.black] = blackRemove;

    // TODO: Bits count is not enough
    _updateKeyMisc();
  }

  void setSideToMove(PieceColor c) {
    final PieceColor oldSide = _sideToMove;

    if (sideToMove != c) {
      sideToMove = c;
      // us = c;

      // If we just switched from Black -> White, that means a new round:
      if (oldSide == PieceColor.black && c == PieceColor.white) {
        _roundNumber++;
      }

      st.key ^= _Zobrist.side;
    }

    _them = sideToMove.opponent;

    if (pieceInHandCount[sideToMove]! == 0) {
      phase = Phase.moving;
      action = Act.select;
    } else if (pieceInHandCount[sideToMove]! > 0) {
      phase = Phase.placing;
      action = Act.place;
    } else {
      logger.e("[position] setSideToMove: Invalid pieceInHandCount.");
    }

    if (pieceToRemoveCount[sideToMove]! > 0 ||
        pieceToRemoveCount[sideToMove]! < 0) {
      action = Act.remove;
    }
  }

  void keepSideToMove() {
    setSideToMove(_sideToMove);
    logger.t("[position] Keep $_sideToMove to move.");
  }

  void changeSideToMove() {
    setSideToMove(_sideToMove.opponent);

    logger.t("[position] $_sideToMove to move.");
  }

  /// Updates square if it hasn't been updated yet.
  int _updateKey(int s) {
    final PieceColor pieceType = _board[s];

    return st.key ^= _Zobrist.psq[pieceType.index][s];
  }

  /// If the square has been updated,
  /// then another update is equivalent to returning to
  /// the state before the update
  /// The significance of this function is to improve code readability.
  int _revertKey(int s) => _updateKey(s);

  void _updateKeyMisc() {
    st.key = st.key << _Zobrist.keyMiscBit >> _Zobrist.keyMiscBit;

    // TODO: pieceToRemoveCount[sideToMove] or
    // abs(pieceToRemoveCount[sideToMove] - pieceToRemoveCount[~sideToMove])?
    // TODO: If pieceToRemoveCount[sideToMove]! <= 3,
    //  the top 2 bits can store its value correctly;
    //  if it is greater than 3, since only 2 bits are left,
    //  the storage will be truncated or directly get 0,
    //  and the original value cannot be completely retained.
    st.key |= pieceToRemoveCount[sideToMove]! << (32 - _Zobrist.keyMiscBit);
  }

  void _setCustodianCaptureState(PieceColor color, int targets, int count) {
    if (color != PieceColor.white && color != PieceColor.black) {
      return;
    }

    final int previousTargets = _custodianCaptureTargets[color]!;
    final int previousCount = _custodianRemovalCount[color]!;

    final int clampedPrev = previousCount.clamp(0, _kMaxCustodianRemoval);
    final int clampedNew = count.clamp(0, _kMaxCustodianRemoval);

    if (clampedPrev != clampedNew) {
      st.key ^= _Zobrist.custodianCount[color.index][clampedPrev];
      st.key ^= _Zobrist.custodianCount[color.index][clampedNew];
    }

    if (previousTargets != targets) {
      for (int sq = sqBegin; sq < sqEnd; ++sq) {
        final int mask = squareBb(sq);

        if ((previousTargets & mask) != 0) {
          st.key ^= _Zobrist.custodianTarget[color.index][sq];
        }

        if ((targets & mask) != 0) {
          st.key ^= _Zobrist.custodianTarget[color.index][sq];
        }
      }
    }

    _custodianCaptureTargets[color] = targets;
    _custodianRemovalCount[color] = count;
  }

  void _setInterventionCaptureState(PieceColor color, int targets, int count) {
    if (color != PieceColor.white && color != PieceColor.black) {
      return;
    }

    final int previousTargets = _interventionCaptureTargets[color]!;
    final int previousCount = _interventionRemovalCount[color]!;

    final int clampedPrev = previousCount.clamp(0, _kMaxInterventionRemoval);
    final int clampedNew = count.clamp(0, _kMaxInterventionRemoval);

    if (clampedPrev != clampedNew) {
      st.key ^= _Zobrist.interventionCount[color.index][clampedPrev];
      st.key ^= _Zobrist.interventionCount[color.index][clampedNew];
    }

    if (previousTargets != targets) {
      for (int sq = sqBegin; sq < sqEnd; ++sq) {
        final int mask = squareBb(sq);

        if ((previousTargets & mask) != 0) {
          st.key ^= _Zobrist.interventionTarget[color.index][sq];
        }

        if ((targets & mask) != 0) {
          st.key ^= _Zobrist.interventionTarget[color.index][sq];
        }
      }
    }

    _interventionCaptureTargets[color] = targets;
    _interventionRemovalCount[color] = count;
  }

  // Sets the state for a leap capture, including target pieces and removal count.
  // This function updates the Zobrist key to reflect the new capture state.
  @visibleForTesting
  void setLeapCaptureStateForTest(PieceColor color, int targets, int count) {
    _setLeapCaptureState(color, targets, count);
  }

  void _setLeapCaptureState(PieceColor color, int targets, int count) {
    if (color != PieceColor.white && color != PieceColor.black) {
      return;
    }

    final int previousTargets = _leapCaptureTargets[color]!;
    final int previousCount = _leapRemovalCount[color]!;

    final int clampedPrev = previousCount.clamp(0, 1);
    final int clampedNew = count.clamp(0, 1);

    if (clampedPrev != clampedNew) {
      st.key ^= _Zobrist.leapCount[color.index][clampedPrev];
      st.key ^= _Zobrist.leapCount[color.index][clampedNew];
    }

    if (previousTargets != targets) {
      for (int sq = sqBegin; sq < sqEnd; ++sq) {
        final int mask = squareBb(sq);

        if ((previousTargets & mask) != 0) {
          st.key ^= _Zobrist.leapTarget[color.index][sq];
        }

        if ((targets & mask) != 0) {
          st.key ^= _Zobrist.leapTarget[color.index][sq];
        }
      }
    }

    _leapCaptureTargets[color] = targets;
    _leapRemovalCount[color] = count;
  }

  int _activateCustodianCapture(PieceColor color, List<int> capturedPieces) {
    if (capturedPieces.isEmpty) {
      _setCustodianCaptureState(color, 0, 0);
      return 0;
    }

    int targets = 0;
    for (final int square in capturedPieces) {
      targets |= squareBb(square);
    }

    // Custodian capture allows capturing one piece from multiple candidates.
    // Although multiple pieces may be sandwiched, the player can only
    // choose to capture one of them, regardless of mayRemoveMultiple setting.
    const int allowedRemovals = 1;

    _setCustodianCaptureState(color, targets, allowedRemovals);

    return allowedRemovals;
  }

  int _activateInterventionCapture(PieceColor color, List<int> capturedPieces) {
    if (capturedPieces.isEmpty) {
      _setInterventionCaptureState(color, 0, 0);
      return 0;
    }

    int targets = 0;
    for (final int target in capturedPieces) {
      targets |= squareBb(target);
    }

    // Intervention capture always captures all pieces that are trapped
    // between the moving piece and another friendly piece, regardless
    // of mayRemoveMultiple setting
    final int allowedRemovals = capturedPieces.length;

    _setInterventionCaptureState(color, targets, allowedRemovals);

    return allowedRemovals;
  }

  // Activates the leap capture rule after a move.
  // Sets the leap capture targets and the number of pieces to be removed.
  // Only one piece can be captured per leap.
  int _activateLeapCapture(PieceColor color, List<int> capturedPieces) {
    if (capturedPieces.isEmpty) {
      _setLeapCaptureState(color, 0, 0);
      return 0;
    }

    int targets = 0;
    for (final int target in capturedPieces) {
      targets |= squareBb(target);
    }

    // Leap capture allows jumping over one opponent piece and capturing it.
    // The player can only capture one piece at a time, regardless of
    // mayRemoveMultiple setting.
    const int allowedRemovals = 1;

    _setLeapCaptureState(color, targets, allowedRemovals);

    return allowedRemovals;
  }

  bool _checkCustodianCapture(int sq, PieceColor us, List<int> capturedPieces) {
    capturedPieces.clear();

    final RuleSettings ruleSettings = DB().ruleSettings;

    if (!ruleSettings.enableCustodianCapture) {
      return false;
    }

    final bool placingPhase = phase == Phase.placing;
    final bool movingPhase = phase == Phase.moving;

    if ((placingPhase && !ruleSettings.custodianCaptureInPlacingPhase) ||
        (movingPhase && !ruleSettings.custodianCaptureInMovingPhase) ||
        (!placingPhase && !movingPhase)) {
      return false;
    }

    // Check piece count condition: only in moving phase and based on remaining pieces
    if (ruleSettings.custodianCaptureOnlyWhenOwnPiecesLeq3) {
      // This condition only applies in moving phase
      if (movingPhase) {
        final int usPieces = pieceOnBoardCount[us]!;
        final int themPieces = pieceOnBoardCount[us.opponent]!;

        // If both sides have ≤3 pieces, both can use custodian capture
        // If only one side has ≤3 pieces, only that side can use it
        // If neither side has ≤3 pieces, neither can use it
        if (usPieces > 3 && themPieces > 3) {
          // Neither side qualifies
          return false;
        } else if (usPieces > 3 && themPieces <= 3) {
          // Only opponent qualifies, current player cannot use
          return false;
        }
        // If us <= 3, we can use it (regardless of opponent's count)
      }
      // In placing phase, piece count condition doesn't apply
    }

    int captured = 0;

    void processLine(List<int> line) {
      if (sq == line[0]) {
        final int middle = line[1];
        final int far = line[2];

        if (_board[middle] == us.opponent && _board[far] == us) {
          captured |= squareBb(middle);
        }
      } else if (sq == line[2]) {
        final int middle = line[1];
        final int far = line[0];

        if (_board[middle] == us.opponent && _board[far] == us) {
          captured |= squareBb(middle);
        }
      }
    }

    if (ruleSettings.custodianCaptureOnSquareEdges) {
      _threePointSquareEdgeLines.forEach(processLine);
    }

    if (ruleSettings.custodianCaptureOnCrossLines) {
      _threePointCrossLines.forEach(processLine);
    }

    if (ruleSettings.hasDiagonalLines &&
        ruleSettings.custodianCaptureOnDiagonalLines) {
      _threePointDiagonalLines.forEach(processLine);
    }

    if (captured == 0) {
      return false;
    }

    int validTargets = 0;

    for (int target = sqBegin; target < sqEnd; ++target) {
      final int mask = squareBb(target);

      if ((captured & mask) == 0) {
        continue;
      }

      if (_board[target] != us.opponent) {
        continue;
      }

      if (!ruleSettings.mayRemoveFromMillsAlways &&
          _potentialMillsCount(target, PieceColor.nobody) > 0 &&
          !_isAllInMills(us.opponent)) {
        continue;
      }

      validTargets |= mask;
    }

    if (validTargets == 0) {
      return false;
    }

    for (int target = sqBegin; target < sqEnd; ++target) {
      if ((validTargets & squareBb(target)) != 0) {
        capturedPieces.add(target);
      }
    }

    return capturedPieces.isNotEmpty;
  }

  /// Find the paired target in the same intervention capture line
  /// This is used after removing the first piece to determine which piece must be removed next
  int _findPairedInterventionTarget(int removedSquare, int allTargets) {
    // Get all remaining target squares from the bitboard
    final List<int> targetSquares = <int>[];
    for (int sq = sqBegin; sq < sqEnd; ++sq) {
      if ((allTargets & squareBb(sq)) != 0 && sq != removedSquare) {
        targetSquares.add(sq);
      }
    }

    // Check all intervention capture lines to find which two pieces are on the same line
    final List<List<List<int>>> allLines = <List<List<int>>>[
      if (DB().ruleSettings.interventionCaptureOnCrossLines)
        _threePointCrossLines,
      if (DB().ruleSettings.interventionCaptureOnSquareEdges)
        _threePointSquareEdgeLines,
      if (DB().ruleSettings.hasDiagonalLines &&
          DB().ruleSettings.interventionCaptureOnDiagonalLines)
        _threePointDiagonalLines,
    ];

    for (final List<List<int>> lineSet in allLines) {
      for (final List<int> line in lineSet) {
        if (line.length != 3) {
          continue;
        }

        final int first = line[0];
        final int second = line[2];

        // Check if removedSquare and any remaining target are on the same line
        for (final int target in targetSquares) {
          if ((removedSquare == first && target == second) ||
              (removedSquare == second && target == first)) {
            return squareBb(target);
          }
        }
      }
    }

    // Fallback: return all remaining targets (shouldn't happen in valid game)
    int result = 0;
    for (final int sq in targetSquares) {
      result |= squareBb(sq);
    }
    return result;
  }

  bool _checkInterventionCapture(
    int sq,
    PieceColor us,
    List<int> capturedPieces,
  ) {
    capturedPieces.clear();

    if (!DB().ruleSettings.enableInterventionCapture) {
      return false;
    }

    final int? preferredTarget = preferredRemoveTarget;

    final bool placingPhase = phase == Phase.placing;
    final bool movingPhase = phase == Phase.moving;

    if ((placingPhase &&
            !DB().ruleSettings.interventionCaptureInPlacingPhase) ||
        (movingPhase && !DB().ruleSettings.interventionCaptureInMovingPhase) ||
        (!placingPhase && !movingPhase)) {
      return false;
    }

    if (DB().ruleSettings.interventionCaptureOnlyWhenOwnPiecesLeq3) {
      if (movingPhase) {
        final int usPieces = pieceOnBoardCount[us]!;
        final int themPieces = pieceOnBoardCount[us.opponent]!;

        if (usPieces > 3 && themPieces > 3) {
          return false;
        } else if (usPieces > 3 && themPieces <= 3) {
          return false;
        }
      }
    }

    // Store all possible capture lines separately
    // Each line can capture 2 pieces, but only pieces from ONE line should be captured
    final List<Set<int>> captureLines = <Set<int>>[];

    void processLine(List<int> line) {
      if (sq != line[1]) {
        return;
      }

      final int first = line[0];
      final int second = line[2];

      if (_board[first] == us.opponent && _board[second] == us.opponent) {
        // Store this line's captures separately instead of accumulating them
        final Set<int> lineCaptured = <int>{first, second};
        captureLines.add(lineCaptured);
      }
    }

    // Process cross lines first, then square edges, then diagonals
    // This ensures that when placing at a cross center, the cross line
    // (more intuitive) is prioritized over the square edge line
    if (DB().ruleSettings.interventionCaptureOnCrossLines) {
      _threePointCrossLines.forEach(processLine);
    }

    if (DB().ruleSettings.interventionCaptureOnSquareEdges) {
      _threePointSquareEdgeLines.forEach(processLine);
    }

    if (DB().ruleSettings.hasDiagonalLines == true &&
        DB().ruleSettings.interventionCaptureOnDiagonalLines == true) {
      _threePointDiagonalLines.forEach(processLine);
    }

    if (captureLines.isEmpty) {
      return false;
    }

    // Select the capture line to use
    Set<int> captured;
    if (preferredTarget != null) {
      // If a preferred target is specified, find the line containing it
      // This is used during move import to select the correct capture line
      captured = captureLines.firstWhere(
        (Set<int> line) => line.contains(preferredTarget),
        orElse: () => captureLines[0],
      );
    } else {
      // If multiple lines are available, only use the first one
      // This ensures that when placing a piece at a cross center,
      // only 2 pieces from one line are captured, not all 4 pieces
      captured = captureLines[0];
    }

    for (final int target in captured) {
      if (_board[target] != us.opponent) {
        continue;
      }

      if (!DB().ruleSettings.mayRemoveFromMillsAlways &&
          _potentialMillsCount(target, PieceColor.nobody) > 0 &&
          !_isAllInMills(us.opponent)) {
        continue;
      }

      capturedPieces.add(target);
    }

    return capturedPieces.isNotEmpty;
  }

  @visibleForTesting
  bool checkLeapCaptureForTest(
    int sq,
    PieceColor us,
    List<int> capturedPieces, [
    int? from,
  ]) {
    return _checkLeapCapture(sq, us, capturedPieces, from);
  }

  bool _checkLeapCapture(
    int sq,
    PieceColor us,
    List<int> capturedPieces, [
    int? from,
  ]) {
    capturedPieces.clear();

    final RuleSettings ruleSettings = DB().ruleSettings;

    if (!ruleSettings.enableLeapCapture) {
      return false;
    }

    // Leap capture requires a movement action with a valid 'from' square
    // Without it, we cannot distinguish leap from custodian capture
    if (from == null) {
      return false;
    }

    // Check phase-specific conditions
    if (phase == Phase.placing) {
      // In placing phase, leap is only valid when mayMoveInPlacingPhase is enabled
      if (!ruleSettings.mayMoveInPlacingPhase ||
          !ruleSettings.leapCaptureInPlacingPhase) {
        return false;
      }
    } else if (phase == Phase.moving) {
      if (!ruleSettings.leapCaptureInMovingPhase) {
        return false;
      }
    } else {
      // Not in a valid phase for leap capture
      return false;
    }

    // Check piece count condition: only in moving phase and based on remaining pieces
    if (ruleSettings.leapCaptureOnlyWhenOwnPiecesLeq3) {
      final int usPieces = pieceOnBoardCount[us]!;
      final int themPieces = pieceOnBoardCount[us.opponent]!;

      if (usPieces > 3 && themPieces > 3) {
        return false;
      } else if (usPieces > 3 && themPieces <= 3) {
        return false;
      }
    }

    // Process leap capture: check pattern [from] - [opponent] - [sq]
    // where 'from' is the jump origin and 'sq' is the destination
    int captured = 0;

    void processLine(List<int> line) {
      // Check if sq is at position 2 (end of line) and from is at position 0
      if (sq == line[2] && from == line[0]) {
        final int middle = line[1];
        // Check pattern: [from] - [middle(opponent)] - [sq]
        if (_board[middle] == us.opponent) {
          captured |= squareBb(middle);
        }
      }
      // Check if sq is at position 0 (start of line) and from is at position 2
      else if (sq == line[0] && from == line[2]) {
        final int middle = line[1];
        // Check pattern: [sq] - [middle(opponent)] - [from]
        if (_board[middle] == us.opponent) {
          captured |= squareBb(middle);
        }
      }
    }

    if (ruleSettings.leapCaptureOnSquareEdges) {
      _threePointSquareEdgeLines.forEach(processLine);
    }

    if (ruleSettings.leapCaptureOnCrossLines) {
      _threePointCrossLines.forEach(processLine);
    }

    if (ruleSettings.hasDiagonalLines &&
        ruleSettings.leapCaptureOnDiagonalLines) {
      _threePointDiagonalLines.forEach(processLine);
    }

    if (captured == 0) {
      return false;
    }

    // Validate captured pieces are removable
    int validTargets = 0;

    for (int target = sqBegin; target < sqEnd; ++target) {
      final int mask = squareBb(target);

      if ((captured & mask) == 0) {
        continue;
      }

      if (_board[target] != us.opponent) {
        continue;
      }

      // Check if piece can be removed according to mill rules
      if (!ruleSettings.mayRemoveFromMillsAlways &&
          _potentialMillsCount(target, PieceColor.nobody) > 0 &&
          !_isAllInMills(us.opponent)) {
        continue;
      }

      validTargets |= mask;
    }

    if (validTargets == 0) {
      return false;
    }

    for (int target = sqBegin; target < sqEnd; ++target) {
      if ((validTargets & squareBb(target)) != 0) {
        capturedPieces.add(target);
      }
    }

    return capturedPieces.isNotEmpty;
  }

  bool _validateCustodianFen(String data) {
    if (data.isEmpty) {
      return true;
    }

    final List<String> segments = data.split('|');

    for (final String rawSegment in segments) {
      final String segment = rawSegment.trim();

      if (segment.isEmpty) {
        continue;
      }

      if (segment.length < 3 || segment[1] != '-') {
        logger.e('Invalid custodian capture segment: $segment');
        return false;
      }

      final String colorChar = segment[0];
      if (colorChar != 'w' && colorChar != 'b') {
        logger.e('Invalid custodian capture color: $colorChar');
        return false;
      }

      final int secondDash = segment.indexOf('-', 2);
      if (secondDash == -1) {
        logger.e('Invalid custodian capture segment: $segment');
        return false;
      }

      final String countStr = segment.substring(2, secondDash).trim();
      if (int.tryParse(countStr) == null) {
        logger.e('Invalid custodian capture count: $countStr');
        return false;
      }

      final String listStr = segment.substring(secondDash + 1);
      if (listStr.isEmpty) {
        continue;
      }

      for (final String token in listStr.split('.')) {
        final String squareText = token.trim();
        if (squareText.isEmpty) {
          continue;
        }

        final int? squareValue = int.tryParse(squareText);
        if (squareValue == null ||
            squareValue < sqBegin ||
            squareValue >= sqEnd) {
          logger.e('Invalid custodian capture target: $squareText');
          return false;
        }
      }
    }

    return true;
  }

  bool _validateInterventionFen(String data) {
    if (data.isEmpty) {
      return true;
    }

    final List<String> segments = data.split('|');

    for (final String rawSegment in segments) {
      final String segment = rawSegment.trim();

      if (segment.isEmpty || segment.length < 3 || segment[1] != '-') {
        continue;
      }

      final String colorChar = segment[0];
      if (colorChar != 'w' && colorChar != 'b') {
        logger.e('Invalid intervention capture segment: $segment');
        return false;
      }

      final int secondDash = segment.indexOf('-', 2);
      if (secondDash == -1) {
        logger.e('Invalid intervention capture segment: $segment');
        return false;
      }

      final String countStr = segment.substring(2, secondDash).trim();
      if (int.tryParse(countStr) == null) {
        logger.e('Invalid intervention capture count: $countStr');
        return false;
      }

      final String listStr = segment.substring(secondDash + 1);
      if (listStr.isEmpty) {
        continue;
      }

      for (final String token in listStr.split('.')) {
        final String squareText = token.trim();
        if (squareText.isEmpty) {
          continue;
        }

        final int? squareValue = int.tryParse(squareText);
        if (squareValue == null ||
            squareValue < sqBegin ||
            squareValue >= sqEnd) {
          logger.e('Invalid intervention capture target: $squareText');
          return false;
        }
      }
    }

    return true;
  }

  bool _parseCustodianFen(String data) {
    final Map<PieceColor, int> targets = <PieceColor, int>{
      PieceColor.white: 0,
      PieceColor.black: 0,
    };
    final Map<PieceColor, int> counts = <PieceColor, int>{
      PieceColor.white: 0,
      PieceColor.black: 0,
    };
    final Map<PieceColor, bool> hasColor = <PieceColor, bool>{
      PieceColor.white: false,
      PieceColor.black: false,
    };

    if (data.isEmpty) {
      for (final PieceColor color in <PieceColor>[
        PieceColor.white,
        PieceColor.black,
      ]) {
        _setCustodianCaptureState(color, 0, 0);
      }
      return true;
    }

    final List<String> segments = data.split('|');

    for (final String rawSegment in segments) {
      final String segment = rawSegment.trim();

      if (segment.isEmpty || segment.length < 3 || segment[1] != '-') {
        continue;
      }

      PieceColor? color;
      switch (segment[0]) {
        case 'w':
          color = PieceColor.white;
          break;
        case 'b':
          color = PieceColor.black;
          break;
        default:
          color = null;
          break;
      }

      if (color == null) {
        continue;
      }

      final int secondDash = segment.indexOf('-', 2);
      if (secondDash == -1) {
        continue;
      }

      final int? parsedCount = int.tryParse(
        segment.substring(2, secondDash).trim(),
      );
      if (parsedCount == null) {
        continue;
      }

      int targetMask = 0;
      final String listStr = segment.substring(secondDash + 1);

      if (listStr.isNotEmpty) {
        for (final String token in listStr.split('.')) {
          final String sqText = token.trim();
          if (sqText.isEmpty) {
            continue;
          }

          final int? squareValue = int.tryParse(sqText);
          if (squareValue == null ||
              squareValue < sqBegin ||
              squareValue >= sqEnd) {
            logger.e('Invalid custodian capture target square: $sqText');
            return false; // Reject entire FEN as per FR-035
          }

          // Verify that the target square actually contains an opponent piece
          if (_board[squareValue] == PieceColor.none) {
            logger.e('Custodian target square $squareValue is empty');
            return false; // Reject entire FEN as per FR-035
          }

          targetMask |= squareBb(squareValue);
        }
      }

      // Validate count matches number of targets (only when there are targets)
      final int actualTargetCount = _countBits(targetMask);
      if (parsedCount > 0 &&
          targetMask > 0 &&
          actualTargetCount != parsedCount) {
        logger.e(
          'Custodian count mismatch: expected $parsedCount, found $actualTargetCount',
        );
        return false; // Reject entire FEN as per FR-035
      }

      targets[color] = targetMask;
      counts[color] = parsedCount;
      hasColor[color] = true;
    }

    for (final PieceColor color in <PieceColor>[
      PieceColor.white,
      PieceColor.black,
    ]) {
      if (hasColor[color]!) {
        _setCustodianCaptureState(color, targets[color]!, counts[color]!);
      } else {
        _setCustodianCaptureState(color, 0, 0);
      }
    }

    return true;
  }

  bool _parseInterventionFen(String data) {
    final Map<PieceColor, int> targets = <PieceColor, int>{
      PieceColor.white: 0,
      PieceColor.black: 0,
    };
    final Map<PieceColor, int> counts = <PieceColor, int>{
      PieceColor.white: 0,
      PieceColor.black: 0,
    };
    final Map<PieceColor, bool> hasColor = <PieceColor, bool>{
      PieceColor.white: false,
      PieceColor.black: false,
    };

    if (data.isEmpty) {
      for (final PieceColor color in <PieceColor>[
        PieceColor.white,
        PieceColor.black,
      ]) {
        _setInterventionCaptureState(color, 0, 0);
      }
      return true;
    }

    final List<String> segments = data.split('|');

    for (final String rawSegment in segments) {
      final String segment = rawSegment.trim();

      if (segment.isEmpty || segment.length < 3 || segment[1] != '-') {
        continue;
      }

      PieceColor? color;
      switch (segment[0]) {
        case 'w':
          color = PieceColor.white;
          break;
        case 'b':
          color = PieceColor.black;
          break;
        default:
          color = null;
          break;
      }

      if (color == null) {
        continue;
      }

      final int secondDash = segment.indexOf('-', 2);
      if (secondDash == -1) {
        continue;
      }

      final int? parsedCount = int.tryParse(
        segment.substring(2, secondDash).trim(),
      );
      if (parsedCount == null) {
        continue;
      }

      int targetMask = 0;
      final String listStr = segment.substring(secondDash + 1);

      if (listStr.isNotEmpty) {
        for (final String token in listStr.split('.')) {
          final String sqText = token.trim();
          if (sqText.isEmpty) {
            continue;
          }

          final int? squareValue = int.tryParse(sqText);
          if (squareValue == null ||
              squareValue < sqBegin ||
              squareValue >= sqEnd) {
            logger.e('Invalid intervention capture target square: $sqText');
            return false; // Reject entire FEN as per FR-035
          }

          // Verify that the target square actually contains an opponent piece
          if (_board[squareValue] == PieceColor.none) {
            logger.e('Intervention target square $squareValue is empty');
            return false; // Reject entire FEN as per FR-035
          }

          targetMask |= squareBb(squareValue);
        }
      }

      // Validate count matches number of targets (only when there are targets)
      final int actualTargetCount = _countBits(targetMask);
      if (parsedCount > 0 &&
          targetMask > 0 &&
          actualTargetCount != parsedCount) {
        logger.e(
          'Intervention count mismatch: expected $parsedCount, found $actualTargetCount',
        );
        return false; // Reject entire FEN as per FR-035
      }

      targets[color] = targetMask;
      counts[color] = parsedCount;
      hasColor[color] = true;
    }

    for (final PieceColor color in <PieceColor>[
      PieceColor.white,
      PieceColor.black,
    ]) {
      if (hasColor[color]!) {
        _setInterventionCaptureState(color, targets[color]!, counts[color]!);
      } else {
        _setInterventionCaptureState(color, 0, 0);
      }
    }

    return true;
  }

  bool _parseLeapFen(String data) {
    final Map<PieceColor, int> targets = <PieceColor, int>{
      PieceColor.white: 0,
      PieceColor.black: 0,
    };
    final Map<PieceColor, int> counts = <PieceColor, int>{
      PieceColor.white: 0,
      PieceColor.black: 0,
    };
    final Map<PieceColor, bool> hasColor = <PieceColor, bool>{
      PieceColor.white: false,
      PieceColor.black: false,
    };

    if (data.isEmpty) {
      for (final PieceColor color in <PieceColor>[
        PieceColor.white,
        PieceColor.black,
      ]) {
        _setLeapCaptureState(color, 0, 0);
      }
      return true;
    }

    final List<String> segments = data.split('|');

    for (final String rawSegment in segments) {
      final String segment = rawSegment.trim();

      if (segment.isEmpty || segment.length < 3 || segment[1] != '-') {
        continue;
      }

      PieceColor? color;
      switch (segment[0]) {
        case 'w':
          color = PieceColor.white;
          break;
        case 'b':
          color = PieceColor.black;
          break;
        default:
          color = null;
          break;
      }

      if (color == null) {
        continue;
      }

      final int secondDash = segment.indexOf('-', 2);
      if (secondDash == -1) {
        continue;
      }

      final int? parsedCount = int.tryParse(
        segment.substring(2, secondDash).trim(),
      );
      if (parsedCount == null) {
        continue;
      }

      int targetMask = 0;
      final String listStr = segment.substring(secondDash + 1);

      if (listStr.isNotEmpty) {
        for (final String token in listStr.split('.')) {
          final String sqText = token.trim();
          if (sqText.isEmpty) {
            continue;
          }

          final int? squareValue = int.tryParse(sqText);
          if (squareValue == null ||
              squareValue < sqBegin ||
              squareValue >= sqEnd) {
            logger.e('Invalid leap capture target square: $sqText');
            return false;
          }

          // Verify that the target square actually contains an opponent piece
          if (_board[squareValue] == PieceColor.none) {
            logger.e('Leap target square $squareValue is empty');
            return false;
          }

          targetMask |= squareBb(squareValue);
        }
      }

      // Validate count matches number of targets (only when there are targets)
      final int actualTargetCount = _countBits(targetMask);
      if (parsedCount > 0 &&
          targetMask > 0 &&
          actualTargetCount != parsedCount) {
        logger.e(
          'Leap count mismatch: expected $parsedCount, found $actualTargetCount',
        );
        return false;
      }

      targets[color] = targetMask;
      counts[color] = parsedCount;
      hasColor[color] = true;
    }

    for (final PieceColor color in <PieceColor>[
      PieceColor.white,
      PieceColor.black,
    ]) {
      if (hasColor[color]!) {
        _setLeapCaptureState(color, targets[color]!, counts[color]!);
      } else {
        _setLeapCaptureState(color, 0, 0);
      }
    }

    return true;
  }

  ///////////////////////////////////////////////////////////////////////////////

  /// Count the number of set bits in a bitmask
  int _countBits(int mask) {
    int count = 0;
    while (mask != 0) {
      count++;
      mask &= mask - 1; // Clear the lowest set bit
    }
    return count;
  }

  // Count the number of empty squares on the board
  // Uses the precomputed piece counts for efficiency
  int _countEmptySquares() {
    return rankNumber * fileNumber -
        pieceOnBoardCount[PieceColor.white]! -
        pieceOnBoardCount[PieceColor.black]!;
  }

  int _potentialMillsCount(int to, PieceColor c, {int from = 0}) {
    int n = 0;
    PieceColor locbak = PieceColor.none;
    PieceColor color = c;

    assert(0 <= from && from < sqEnd);

    if (c == PieceColor.nobody) {
      color = _board[to];
    }

    if (from != 0 && from >= sqBegin && from < sqEnd) {
      locbak = _board[from];
      _board[from] = _grid[squareToIndex[from]!] = PieceColor.none;
    }

    if (DB().ruleSettings.oneTimeUseMill) {
      for (int ld = 0; ld < lineDirectionNumber; ld++) {
        final List<int> mill = <int>[
          _millTable[to][ld][0],
          _millTable[to][ld][1],
          to,
        ];

        if (color == _board[mill[0]] && color == _board[mill[1]]) {
          if (c == PieceColor.nobody) {
            n++;
          } else {
            final int millBB =
                squareBb(mill[0]) | squareBb(mill[1]) | squareBb(mill[2]);
            if (!(millBB & _formedMillsBB[color]! == millBB)) {
              n++;
            }
          }
        }
      }
    } else {
      for (int ld = 0; ld < lineDirectionNumber; ld++) {
        if (color == _board[_millTable[to][ld][0]] &&
            color == _board[_millTable[to][ld][1]]) {
          n++;
        }
      }
    }

    if (from != 0) {
      _board[from] = _grid[squareToIndex[from]!] = locbak;
    }

    return n;
  }

  int totalMillsCount(PieceColor pieceColor) {
    assert(pieceColor == PieceColor.white || pieceColor == PieceColor.black);

    int n = 0;

    for (final List<int> line in _millLinesHV) {
      if (_board[line[0]] == pieceColor &&
          _board[line[1]] == pieceColor &&
          _board[line[2]] == pieceColor) {
        n++;
      }
    }

    if (DB().ruleSettings.hasDiagonalLines == true) {
      for (final List<int> line in _millLinesD) {
        if (_board[line[0]] == pieceColor &&
            _board[line[1]] == pieceColor &&
            _board[line[2]] == pieceColor) {
          n++;
        }
      }
    }

    return n;
  }

  int _millsCount(int s) {
    int n = 0;
    final PieceColor m = _board[s];

    for (int i = 0; i < lineDirectionNumber; i++) {
      final List<int> mill = <int>[_millTable[s][i][0], _millTable[s][i][1], s];
      mill.sort();

      if (m == _board[mill[0]] &&
          m == _board[mill[1]] &&
          m == _board[mill[2]]) {
        final int millBB =
            squareBb(mill[0]) | squareBb(mill[1]) | squareBb(mill[2]);
        if (!DB().ruleSettings.oneTimeUseMill ||
            !(millBB & _formedMillsBB[m]! == millBB)) {
          _formedMillsBB[m] = _formedMillsBB[m]! | millBB;
          _formedMills[m]?.add(mill);
          n++;
        }
      }
    }

    return n;
  }

  // Helper function to check if two lists are equal
  bool listEquals(List<int> list1, List<int> list2) {
    if (list1.length != list2.length) {
      return false;
    }
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) {
        return false;
      }
    }
    return true;
  }

  bool _isAllInMills(PieceColor c) {
    for (int i = sqBegin; i < sqEnd; i++) {
      if (_board[i] == c) {
        if (_potentialMillsCount(i, PieceColor.nobody) == 0) {
          return false;
        }
      }
    }

    return true;
  }

  bool _isAllSurrounded(PieceColor c) {
    // Full
    if (pieceOnBoardCount[PieceColor.white]! +
            pieceOnBoardCount[PieceColor.black]! >=
        rankNumber * fileNumber) {
      return true;
    }

    // restrictRepeatedMillsFormation only restricts the single piece at
    // lastMillToSquare from returning to lastMillFromSquare. The remaining
    // (flyPieceCount - 1) pieces are unrestricted and can fly to any empty
    // square, so the player always has at least one legal move when flying.
    if (pieceOnBoardCount[c]! <= DB().ruleSettings.flyPieceCount &&
        DB().ruleSettings.mayFly) {
      return false;
    }

    for (int s = sqBegin; s < sqEnd; s++) {
      if (c != _board[s]) {
        continue;
      }

      bool pieceCanMove = false;

      for (int d = moveDirectionBegin; d < moveDirectionNumber; d++) {
        final int moveSquare = _adjacentSquares[s][d];
        if (moveSquare == 0 || _board[moveSquare] != PieceColor.none) {
          continue;
        }

        // Found an empty adjacent square. Check whether
        // restrictRepeatedMillsFormation blocks this move.
        if (DB().ruleSettings.restrictRepeatedMillsFormation &&
            s == _lastMillToSquare[c] &&
            _lastMillFromSquare[c] != 0 &&
            moveSquare == _lastMillFromSquare[c]) {
          bool sInMill = false;
          for (int ld = 0; ld < lineDirectionNumber; ld++) {
            if (c == _board[_millTable[s][ld][0]] &&
                c == _board[_millTable[s][ld][1]]) {
              if (DB().ruleSettings.oneTimeUseMill) {
                final int line =
                    squareBb(s) |
                    squareBb(_millTable[s][ld][0]) |
                    squareBb(_millTable[s][ld][1]);
                if (line & _formedMillsBB[c]! == line) {
                  continue;
                }
              }
              sInMill = true;
              break;
            }
          }

          if (sInMill) {
            bool wouldFormMill = false;
            for (int ld = 0; ld < lineDirectionNumber; ld++) {
              final int sq1 = _millTable[moveSquare][ld][0];
              final int sq2 = _millTable[moveSquare][ld][1];
              final PieceColor c1 = (sq1 == s) ? PieceColor.none : _board[sq1];
              final PieceColor c2 = (sq2 == s) ? PieceColor.none : _board[sq2];

              if (c1 == c && c2 == c) {
                if (DB().ruleSettings.oneTimeUseMill) {
                  final int millBB =
                      squareBb(moveSquare) | squareBb(sq1) | squareBb(sq2);
                  if (millBB & _formedMillsBB[c]! != millBB) {
                    wouldFormMill = true;
                    break;
                  }
                } else {
                  wouldFormMill = true;
                  break;
                }
              }
            }

            if (wouldFormMill) {
              continue;
            }
          }
        }

        pieceCanMove = true;
        break;
      }

      if (!pieceCanMove) {
        pieceCanMove = _hasLeapMove(s, c);
      }

      if (pieceCanMove) {
        return false;
      }
    }

    return true;
  }

  bool _isMoveRestricted(int from, int to, PieceColor c) {
    final RuleSettings rs = DB().ruleSettings;
    if (!rs.restrictRepeatedMillsFormation ||
        from != _lastMillToSquare[c] ||
        _lastMillFromSquare[c] == 0 ||
        to != _lastMillFromSquare[c]) {
      return false;
    }

    bool fromInMill = false;
    for (int ld = 0; ld < lineDirectionNumber; ld++) {
      if (c == _board[_millTable[from][ld][0]] &&
          c == _board[_millTable[from][ld][1]]) {
        if (rs.oneTimeUseMill) {
          final int line =
              squareBb(from) |
              squareBb(_millTable[from][ld][0]) |
              squareBb(_millTable[from][ld][1]);
          if (line & _formedMillsBB[c]! == line) {
            continue;
          }
        }
        fromInMill = true;
        break;
      }
    }
    if (!fromInMill) {
      return false;
    }

    for (int ld = 0; ld < lineDirectionNumber; ld++) {
      final int sq1 = _millTable[to][ld][0];
      final int sq2 = _millTable[to][ld][1];
      final PieceColor c1 = (sq1 == from) ? PieceColor.none : _board[sq1];
      final PieceColor c2 = (sq2 == from) ? PieceColor.none : _board[sq2];
      if (c1 == c && c2 == c) {
        if (rs.oneTimeUseMill) {
          final int millBB = squareBb(to) | squareBb(sq1) | squareBb(sq2);
          if (millBB & _formedMillsBB[c]! != millBB) {
            return true;
          }
        } else {
          return true;
        }
      }
    }
    return false;
  }

  bool _hasLeapMove(int from, PieceColor c) {
    final RuleSettings rs = DB().ruleSettings;
    if (!rs.enableLeapCapture) {
      return false;
    }
    final bool leapEnabled =
        (phase == Phase.moving && rs.leapCaptureInMovingPhase) ||
        (phase == Phase.placing &&
            rs.mayMoveInPlacingPhase &&
            rs.leapCaptureInPlacingPhase);
    if (!leapEnabled || pieceInHandCount[c]! > 0) {
      return false;
    }

    bool checkLine(List<int> line) {
      final int a = line[0], mid = line[1], b = line[2];
      if (a == from &&
          _board[b] == PieceColor.none &&
          _board[mid] == c.opponent) {
        if (_isMoveRestricted(from, b, c)) {
          return false;
        }
        final List<int> captured = <int>[];
        if (_checkLeapCapture(b, c, captured, from)) {
          return true;
        }
      }
      if (b == from &&
          _board[a] == PieceColor.none &&
          _board[mid] == c.opponent) {
        if (_isMoveRestricted(from, a, c)) {
          return false;
        }
        final List<int> captured = <int>[];
        if (_checkLeapCapture(a, c, captured, from)) {
          return true;
        }
      }
      return false;
    }

    for (final List<int> line in _threePointSquareEdgeLines) {
      if (checkLine(line)) {
        return true;
      }
    }
    for (final List<int> line in _threePointCrossLines) {
      if (checkLine(line)) {
        return true;
      }
    }
    if (rs.hasDiagonalLines && rs.leapCaptureOnDiagonalLines) {
      for (final List<int> line in _threePointDiagonalLines) {
        if (checkLine(line)) {
          return true;
        }
      }
    }
    return false;
  }

  void setFormedMillsBB(int millsBitmask) {
    final int whiteMills = (millsBitmask >> 32) & 0xFFFFFFFF;
    final int blackMills = millsBitmask & 0xFFFFFFFF;

    _formedMillsBB[PieceColor.white] = whiteMills;
    _formedMillsBB[PieceColor.black] = blackMills;
  }

  @visibleForTesting
  String? get movesSinceLastRemove {
    final GameRecorder recorder = GameController().gameRecorder;

    // Build the move list up to (and including) the activeNode, not beyond it.
    final List<ExtMove> pathMoves = <ExtMove>[];
    PgnNode<ExtMove>? cur = recorder.activeNode;

    // Guard against circular references in PGN tree
    final Set<PgnNode<ExtMove>> visitedNodes = <PgnNode<ExtMove>>{};

    while (cur != null && cur.parent != null) {
      // Detecting circular references: If the current node has already been visited, it indicates a cycle in the tree, and the process should be terminated immediately.
      if (visitedNodes.contains(cur)) {
        logger.e(
          "[position] Circular reference detected in PGN tree during movesSinceLastRemove traversal",
        );
        break;
      }
      visitedNodes.add(cur);

      if (cur.data != null) {
        pathMoves.add(cur.data!);
      }
      cur = cur.parent;
    }
    if (pathMoves.isEmpty) {
      return null;
    }

    // Reverse to go from root -> activeNode
    final List<ExtMove> moves = pathMoves.reversed.toList();

    // 1) Start from the end of the truncated list
    int idx = moves.length - 1;

    // 2) Go backwards until the last remove (starts with 'x')
    while (idx >= 0 && !moves[idx].move.startsWith('x')) {
      idx--;
    }

    // 3) Collect everything after that remove
    idx++;

    final StringBuffer buffer = StringBuffer();
    for (int i = idx; i < moves.length; i++) {
      buffer.writeSpace(moves[i].move);
    }

    final String result = buffer.toString();
    return result.isEmpty ? null : result;
  }

  // ----------------------------------------------------------------------------------------
  // Dynamic board layout string in ExtMove
  // ----------------------------------------------------------------------------------------

  /// generateBoardLayoutAfterThisMove returns a 3-rings layout string,
  /// each ring has 8 positions, representing the outer/middle/inner ring.
  /// For example: "OO***@**/@@**O@*@/O@O*@*O*"
  /// 'O' means White, '@' means Black, 'X' means Marked, '*' means None or empty.
  String generateBoardLayoutAfterThisMove() {
    // <-- ADDED
    // Helper to map PieceColor to a single char
    String pieceChar(PieceColor c) {
      // Keep mapping consistent with MiniBoardPainter._charToPieceColor
      if (c == PieceColor.white) {
        return 'O';
      }
      if (c == PieceColor.black) {
        return '@';
      }
      if (c == PieceColor.marked) {
        return 'X';
      }
      return '*';
    }

    // We know squares 8..15 = outer ring, 16..23 = middle ring, 24..31 = inner ring
    String ringToString(int startIndex) {
      final StringBuffer sb = StringBuffer();
      for (int i = 0; i < 8; i++) {
        final PieceColor p = _board[startIndex + i];
        sb.write(pieceChar(p));
      }
      return sb.toString();
    }

    final String outer = ringToString(8);
    final String middle = ringToString(16);
    final String inner = ringToString(24);

    return "$outer/$middle/$inner";
  }
}

extension SetupPosition on Position {
  PieceColor get sideToSetup => _sideToMove;

  set sideToSetup(PieceColor color) {
    _sideToMove = color;
  }

  void reset() {
    phase = Phase.placing;
    action = Act.place;

    _sideToMove = PieceColor.white;
    _them = PieceColor.black;

    result = null;
    winner = PieceColor.nobody;
    gameOverReason = null;

    _record = null;
    _currentSquare[PieceColor.white] = _currentSquare[PieceColor.black] = 0;
    _lastMillFromSquare[PieceColor.white] =
        _lastMillFromSquare[PieceColor.black] = 0;
    _lastMillToSquare[PieceColor.white] = _lastMillToSquare[PieceColor.black] =
        0;
    _formedMillsBB[PieceColor.white] = _formedMillsBB[PieceColor.black] = 0;
    _formedMills[PieceColor.white] = <List<int>>[];
    _formedMills[PieceColor.black] = <List<int>>[];

    _gamePly = 0;

    pieceOnBoardCount[PieceColor.white] = 0;
    pieceOnBoardCount[PieceColor.black] = 0;

    pieceInHandCount[PieceColor.white] = DB().ruleSettings.piecesCount;
    pieceInHandCount[PieceColor.black] = DB().ruleSettings.piecesCount;

    pieceToRemoveCount[PieceColor.white] = 0;
    pieceToRemoveCount[PieceColor.black] = 0;

    _custodianCaptureTargets[PieceColor.white] = 0;
    _custodianCaptureTargets[PieceColor.black] = 0;
    _custodianRemovalCount[PieceColor.white] = 0;
    _custodianRemovalCount[PieceColor.black] = 0;
    _interventionCaptureTargets[PieceColor.white] = 0;
    _interventionCaptureTargets[PieceColor.black] = 0;
    _interventionRemovalCount[PieceColor.white] = 0;
    _interventionRemovalCount[PieceColor.black] = 0;
    _leapCaptureTargets[PieceColor.white] = 0;
    _leapCaptureTargets[PieceColor.black] = 0;
    _leapRemovalCount[PieceColor.white] = 0;
    _leapRemovalCount[PieceColor.black] = 0;

    isNeedStalemateRemoval = false;
    isStalemateRemoving = false;
    isBothStalemateRemoving = false;

    placedPieceNumber = 0;
    selectedPieceNumber = 0;
    for (int i = 0; i < sqNumber; i++) {
      sqAttrList[i].placedPieceNumber = 0;
    }

    for (int i = 0; i < sqNumber; i++) {
      _board[i] = PieceColor.none;
    }

    for (int i = 0; i < 7 * 7; i++) {
      _grid[i] = PieceColor.none;
    }

    st.rule50 = 0;
    st.key = 0;
    st.pliesFromNull = 0;

    posKeyHistory.clear();
  }

  void copyWith(Position pos) {
    phase = pos.phase;
    action = pos.action;

    _sideToMove = pos._sideToMove;
    _them = pos._them;

    result = pos.result;
    winner = pos.winner;
    gameOverReason = pos.gameOverReason;

    _record = pos._record;
    _currentSquare = pos._currentSquare;
    _lastMillFromSquare = pos._lastMillFromSquare;
    _lastMillToSquare = pos._lastMillToSquare;
    _formedMillsBB = pos._formedMillsBB;
    _formedMills = pos._formedMills;

    _gamePly = pos._gamePly;

    pieceOnBoardCount[PieceColor.white] =
        pos.pieceOnBoardCount[PieceColor.white]!;
    pieceOnBoardCount[PieceColor.black] =
        pos.pieceOnBoardCount[PieceColor.black]!;

    if (pieceOnBoardCount[PieceColor.white]! < 0 ||
        pieceOnBoardCount[PieceColor.black]! < 0) {
      logger.e("[position] copyWith: pieceOnBoardCount is less than 0.");
    }

    pieceInHandCount[PieceColor.white] =
        pos.pieceInHandCount[PieceColor.white]!;
    pieceInHandCount[PieceColor.black] =
        pos.pieceInHandCount[PieceColor.black]!;

    if (pieceInHandCount[PieceColor.white]! < 0 ||
        pieceInHandCount[PieceColor.black]! < 0) {
      logger.e("[position] copyWith: pieceInHandCount is less than 0.");
    }

    pieceToRemoveCount[PieceColor.white] =
        pos.pieceToRemoveCount[PieceColor.white]!;
    pieceToRemoveCount[PieceColor.black] =
        pos.pieceToRemoveCount[PieceColor.black]!;

    _custodianCaptureTargets[PieceColor.white] =
        pos._custodianCaptureTargets[PieceColor.white]!;
    _custodianCaptureTargets[PieceColor.black] =
        pos._custodianCaptureTargets[PieceColor.black]!;
    _custodianRemovalCount[PieceColor.white] =
        pos._custodianRemovalCount[PieceColor.white]!;
    _custodianRemovalCount[PieceColor.black] =
        pos._custodianRemovalCount[PieceColor.black]!;
    _interventionCaptureTargets[PieceColor.white] =
        pos._interventionCaptureTargets[PieceColor.white]!;
    _interventionCaptureTargets[PieceColor.black] =
        pos._interventionCaptureTargets[PieceColor.black]!;
    _interventionRemovalCount[PieceColor.white] =
        pos._interventionRemovalCount[PieceColor.white]!;
    _interventionRemovalCount[PieceColor.black] =
        pos._interventionRemovalCount[PieceColor.black]!;
    _leapCaptureTargets[PieceColor.white] =
        pos._leapCaptureTargets[PieceColor.white]!;
    _leapCaptureTargets[PieceColor.black] =
        pos._leapCaptureTargets[PieceColor.black]!;
    _leapRemovalCount[PieceColor.white] =
        pos._leapRemovalCount[PieceColor.white]!;
    _leapRemovalCount[PieceColor.black] =
        pos._leapRemovalCount[PieceColor.black]!;

    // Copy preferredRemoveTarget to maintain it across position cloning
    preferredRemoveTarget = pos.preferredRemoveTarget;

    isNeedStalemateRemoval = pos.isNeedStalemateRemoval;
    isStalemateRemoving = pos.isStalemateRemoving;
    isBothStalemateRemoving = pos.isBothStalemateRemoving;

    placedPieceNumber = pos.placedPieceNumber;
    selectedPieceNumber = pos.selectedPieceNumber;
    for (int i = 0; i < sqNumber; i++) {
      sqAttrList[i].placedPieceNumber = pos.sqAttrList[i].placedPieceNumber;
    }

    for (int i = 0; i < sqNumber; i++) {
      _board[i] = pos._board[i];
    }

    for (int i = 0; i < 7 * 7; i++) {
      _grid[i] = pos._grid[i];
    }

    st.rule50 = pos.st.rule50;
    st.key = pos.st.key;
    st.pliesFromNull = pos.st.pliesFromNull;
  }

  Position clone() {
    final Position pos = Position();
    pos.copyWith(this);
    return pos;
  }

  bool putPieceForSetupPosition(int s) {
    final PieceColor piece = GameController().isPieceMarkedInPositionSetup
        ? PieceColor.marked
        : sideToMove;
    //final us = _sideToMove;

    // TODO: Allow to overwrite.
    if (_board[s] != PieceColor.none) {
      SoundManager().playTone(Sound.illegal);
      return false;
    }

    if (countPieceOnBoard(piece) == DB().ruleSettings.piecesCount) {
      SoundManager().playTone(Sound.illegal);
      return false;
    }

    if (DB().ruleSettings.millFormationActionInPlacingPhase ==
        MillFormationActionInPlacingPhase.markAndDelayRemovingPieces) {
      if (countTotalPieceOnBoard() >= DB().ruleSettings.piecesCount * 2) {
        SoundManager().playTone(Sound.illegal);
        return false;
      }
    }

    /*
    // No need to update
    if (pieceInHandCount[us] != null) {
      pieceInHandCount[us] = pieceInHandCount[us]! - 1;
    }

    if (pieceOnBoardCount[us] != null) {
      pieceOnBoardCount[us] = pieceOnBoardCount[us]! + 1;
    }
     */

    _grid[squareToIndex[s]!] = piece;
    _board[s] = piece;

    //GameController().gameInstance.focusIndex = squareToIndex[s];
    SoundManager().playTone(
      GameController().isPieceMarkedInPositionSetup
          ? Sound.remove
          : Sound.place,
    );

    GameController().setupPositionNotifier.updateIcons();

    return true;
  }

  GameResponse _removePieceForSetupPosition(int s) {
    if (action != Act.remove) {
      SoundManager().playTone(Sound.illegal);
      return const IllegalAction();
    }

    if (_board[s] == PieceColor.none) {
      SoundManager().playTone(Sound.illegal);
      return const IllegalAction();
    }

    // Remove only
    _board[s] = _grid[squareToIndex[s]!] = PieceColor.none;

    /*
    // No need to update
    // TODO: How to use it to verify?
    if (pieceOnBoardCount[_them] != null) {
      pieceOnBoardCount[_them] = pieceOnBoardCount[_them]! - 1;
    }
     */

    SoundManager().playTone(Sound.remove);
    GameController().setupPositionNotifier.updateIcons();

    return const GameResponseOK();
  }

  int countPieceOnBoard(PieceColor pieceColor) {
    int count = 0;
    for (int i = 0; i < sqNumber; i++) {
      if (_board[i] == pieceColor) {
        count++;
      }
    }
    return count;
  }

  int countPieceOnBoardMax() {
    final int w = countPieceOnBoard(PieceColor.white);
    final int b = countPieceOnBoard(PieceColor.black);

    return w > b ? w : b;
  }

  int countTotalPieceOnBoard() {
    return countPieceOnBoard(PieceColor.white) +
        countPieceOnBoard(PieceColor.black) +
        countPieceOnBoard(PieceColor.marked);
  }

  bool isBoardFullRemovalAtPlacingPhaseEnd() {
    if (DB().ruleSettings.piecesCount == 12 &&
        DB().ruleSettings.boardFullAction != BoardFullAction.firstPlayerLose &&
        DB().ruleSettings.boardFullAction != BoardFullAction.agreeToDraw &&
        phase == Phase.placing &&
        pieceInHandCount[PieceColor.white] == 0 &&
        pieceInHandCount[PieceColor.black] == 0 &&
        // TODO: Performance
        totalMillsCount(PieceColor.black) == 0) {
      return true;
    }

    return false;
  }

  bool isAdjacentTo(int sq, PieceColor c) {
    for (int d = moveDirectionBegin; d < moveDirectionNumber; d++) {
      final int moveSquare = Position._adjacentSquares[sq][d];
      if (moveSquare != 0 && _board[moveSquare] == c) {
        return true;
      }
    }
    return false;
  }

  bool isStalemateRemoval(PieceColor c) {
    if (isBoardFullRemovalAtPlacingPhaseEnd()) {
      return true;
    }

    if ((DB().ruleSettings.stalemateAction ==
                StalemateAction.removeOpponentsPieceAndChangeSideToMove ||
            DB().ruleSettings.stalemateAction ==
                StalemateAction.removeOpponentsPieceAndMakeNextMove ||
            DB().ruleSettings.stalemateAction ==
                StalemateAction.bothPlayersRemoveOpponentsPiece) ==
        false) {
      return false;
    }

    if (isStalemateRemoving == true) {
      return true;
    }

    // Both-stalemate-removing flag: adjacency restriction applies to
    // both the stalemated side and the non-stalemated side.
    if (isBothStalemateRemoving == true) {
      return true;
    }

    // TODO: StalemateAction: Improve performance.
    if (_isAllSurrounded(c)) {
      return true;
    }

    return false;
  }
}
