// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// color_settings_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/appearance_settings/models/color_settings.dart';
import 'package:sanmill/shared/themes/ui_colors.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Default values
  // ---------------------------------------------------------------------------
  group('ColorSettings defaults', () {
    test('should have sensible default color values', () {
      const ColorSettings c = ColorSettings();

      expect(c.boardLineColor, UIColors.burntSienna);
      expect(c.darkBackgroundColor, UIColors.spruce);
      expect(c.boardBackgroundColor, UIColors.burlyWood);
      expect(c.whitePieceColor, Colors.white);
      expect(c.blackPieceColor, Colors.black);
      expect(c.pieceHighlightColor, Colors.red);
      expect(c.messageColor, Colors.white);
      expect(c.drawerColor, Colors.white);
      expect(c.drawerTextColor, UIColors.mediumJungleGreen);
      expect(c.drawerHighlightItemColor, UIColors.highlighterGreen20);
      expect(c.mainToolbarBackgroundColor, UIColors.burlyWood);
      expect(c.mainToolbarIconColor, UIColors.cocoaBean60);
      expect(c.navigationToolbarBackgroundColor, UIColors.burlyWood);
      expect(c.navigationToolbarIconColor, UIColors.cocoaBean60);
      expect(c.analysisToolbarBackgroundColor, UIColors.burlyWood);
      expect(c.analysisToolbarIconColor, UIColors.cocoaBean60);
      expect(c.annotationToolbarBackgroundColor, UIColors.burlyWood);
      expect(c.annotationToolbarIconColor, UIColors.cocoaBean60);
      expect(c.capturablePieceHighlightColor, Colors.orange);
    });
  });

  // ---------------------------------------------------------------------------
  // Constructor with custom values
  // ---------------------------------------------------------------------------
  group('ColorSettings construction', () {
    test('should allow overriding all color fields', () {
      const ColorSettings c = ColorSettings(
        boardLineColor: Colors.red,
        darkBackgroundColor: Colors.blue,
        boardBackgroundColor: Colors.green,
        whitePieceColor: Colors.yellow,
        blackPieceColor: Colors.purple,
        pieceHighlightColor: Colors.orange,
        messageColor: Colors.cyan,
        drawerColor: Colors.teal,
        drawerTextColor: Colors.pink,
        drawerHighlightItemColor: Colors.lime,
        mainToolbarBackgroundColor: Colors.indigo,
        mainToolbarIconColor: Colors.amber,
        navigationToolbarBackgroundColor: Colors.brown,
        navigationToolbarIconColor: Colors.grey,
        analysisToolbarBackgroundColor: Colors.deepPurple,
        analysisToolbarIconColor: Colors.lightBlue,
        annotationToolbarBackgroundColor: Colors.deepOrange,
        annotationToolbarIconColor: Colors.lightGreen,
        capturablePieceHighlightColor: Colors.redAccent,
      );

      expect(c.boardLineColor, Colors.red);
      expect(c.darkBackgroundColor, Colors.blue);
      expect(c.boardBackgroundColor, Colors.green);
      expect(c.whitePieceColor, Colors.yellow);
      expect(c.blackPieceColor, Colors.purple);
      expect(c.capturablePieceHighlightColor, Colors.redAccent);
    });
  });

  // ---------------------------------------------------------------------------
  // UIColors static constants
  // ---------------------------------------------------------------------------
  group('UIColors', () {
    test('should define all named colors', () {
      expect(UIColors.burlyWood, isNotNull);
      expect(UIColors.burntSienna, isNotNull);
      expect(UIColors.butterflyBlue, isNotNull);
      expect(UIColors.citrus, isNotNull);
      expect(UIColors.cocoaBean, isNotNull);
      expect(UIColors.cocoaBean60, isNotNull);
      expect(UIColors.darkJungleGreen, isNotNull);
      expect(UIColors.darkRoyalBlue, isNotNull);
      expect(UIColors.floralWhite, isNotNull);
      expect(UIColors.gondola, isNotNull);
      expect(UIColors.highlighterGreen, isNotNull);
      expect(UIColors.highlighterGreen20, isNotNull);
      expect(UIColors.mediumJungleGreen, isNotNull);
      expect(UIColors.osloGrey, isNotNull);
      expect(UIColors.papayaWhip, isNotNull);
      expect(UIColors.riverBed, isNotNull);
      expect(UIColors.riverBed60, isNotNull);
      expect(UIColors.rosewood, isNotNull);
      expect(UIColors.rosewood20, isNotNull);
      expect(UIColors.rosewood50, isNotNull);
      expect(UIColors.seashell, isNotNull);
      expect(UIColors.seashell50, isNotNull);
      expect(UIColors.semiTransparentBlack, isNotNull);
      expect(UIColors.spruce, isNotNull);
      expect(UIColors.starDust, isNotNull);
      expect(UIColors.starDust10, isNotNull);
      expect(UIColors.tahitiGold, isNotNull);
      expect(UIColors.tahitiGold60, isNotNull);
    });

    test('opaque colors should have full alpha', () {
      expect(UIColors.burlyWood.a, closeTo(1.0, 0.01));
      expect(UIColors.burntSienna.a, closeTo(1.0, 0.01));
      expect(UIColors.spruce.a, closeTo(1.0, 0.01));
    });

    test('semi-transparent colors should have reduced alpha', () {
      // cocoaBean60 is 0x99 = 153/255 ≈ 0.6
      expect(UIColors.cocoaBean60.a, closeTo(0.6, 0.05));
      // rosewood20 is 0x33 = 51/255 ≈ 0.2
      expect(UIColors.rosewood20.a, closeTo(0.2, 0.05));
      // highlighterGreen20 is 0x33 = 51/255 ≈ 0.2
      expect(UIColors.highlighterGreen20.a, closeTo(0.2, 0.05));
    });
  });
}
