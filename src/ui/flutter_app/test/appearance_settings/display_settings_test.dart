// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// display_settings_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Default values
  // ---------------------------------------------------------------------------
  group('DisplaySettings defaults', () {
    test('should have sensible defaults for all fields', () {
      const DisplaySettings d = DisplaySettings();

      expect(d.locale, isNull);
      expect(d.isFullScreen, isFalse);
      expect(d.isPieceCountInHandShown, isTrue);
      expect(d.isUnplacedAndRemovedPiecesShown, isTrue);
      expect(d.isNotationsShown, isTrue);
      expect(d.isHistoryNavigationToolbarShown, isTrue);
      expect(d.boardBorderLineWidth, 2.0);
      expect(d.boardInnerLineWidth, 2.0);
      expect(d.pointPaintingStyle, PointPaintingStyle.none);
      expect(d.pointWidth, 10.0);
      expect(d.pieceWidth, 0.9);
      expect(d.fontScale, 1.0);
      expect(d.boardTop, kToolbarHeight);
      expect(d.animationDuration, 1.0);
      expect(d.isPositionalAdvantageIndicatorShown, isTrue);
      expect(d.backgroundImagePath, '');
      expect(d.isNumbersOnPiecesShown, isFalse);
      expect(d.isAnalysisToolbarShown, isFalse);
      expect(d.whitePieceImagePath, '');
      expect(d.blackPieceImagePath, '');
      expect(d.markedPieceImagePath, '');
      expect(d.boardImagePath, '');
      expect(d.vignetteEffectEnabled, isFalse);
      expect(d.placeEffectAnimation, 'Default');
      expect(d.removeEffectAnimation, 'Default');
      expect(d.isToolbarAtBottom, isFalse);
      expect(d.customBackgroundImagePath, isNull);
      expect(d.customBoardImagePath, isNull);
      expect(d.customWhitePieceImagePath, isNull);
      expect(d.customBlackPieceImagePath, isNull);
      expect(d.boardCornerRadius, 5.0);
      expect(d.isAdvantageGraphShown, isFalse);
      expect(d.isAnnotationToolbarShown, isFalse);
      expect(d.movesViewLayout, MovesViewLayout.medium);
      expect(d.swipeToRevealTheDrawer, isTrue);
      expect(d.isScreenshotGameInfoShown, isTrue);
      expect(d.boardInnerRingSize, 1.0);
      expect(d.boardShadowEnabled, isFalse);
      expect(d.isCapturablePiecesHighlightShown, isFalse);
      expect(d.isPiecePickUpAnimationEnabled, isTrue);
      expect(d.showBranchTree, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // PointPaintingStyle
  // ---------------------------------------------------------------------------
  group('PointPaintingStyle', () {
    test('should have three values', () {
      expect(PointPaintingStyle.values.length, 3);
    });

    test('should include none, fill, stroke', () {
      expect(
        PointPaintingStyle.values,
        containsAll(<PointPaintingStyle>[
          PointPaintingStyle.none,
          PointPaintingStyle.fill,
          PointPaintingStyle.stroke,
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // MovesViewLayout
  // ---------------------------------------------------------------------------
  group('MovesViewLayout', () {
    test('should have five values', () {
      expect(MovesViewLayout.values.length, 5);
    });

    test('should include large, medium, small, list, details', () {
      expect(
        MovesViewLayout.values,
        containsAll(<MovesViewLayout>[
          MovesViewLayout.large,
          MovesViewLayout.medium,
          MovesViewLayout.small,
          MovesViewLayout.list,
          MovesViewLayout.details,
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Numeric field boundaries
  // ---------------------------------------------------------------------------
  group('DisplaySettings numeric boundaries', () {
    test('boardBorderLineWidth default is reasonable', () {
      const DisplaySettings d = DisplaySettings();
      expect(d.boardBorderLineWidth, greaterThan(0));
      expect(d.boardBorderLineWidth, lessThanOrEqualTo(10));
    });

    test('boardInnerLineWidth default is reasonable', () {
      const DisplaySettings d = DisplaySettings();
      expect(d.boardInnerLineWidth, greaterThan(0));
      expect(d.boardInnerLineWidth, lessThanOrEqualTo(10));
    });

    test('pointWidth default is positive', () {
      const DisplaySettings d = DisplaySettings();
      expect(d.pointWidth, greaterThan(0));
    });

    test('pieceWidth default is in 0-1 range', () {
      const DisplaySettings d = DisplaySettings();
      expect(d.pieceWidth, greaterThan(0));
      expect(d.pieceWidth, lessThanOrEqualTo(1));
    });

    test('fontScale default is 1.0', () {
      const DisplaySettings d = DisplaySettings();
      expect(d.fontScale, 1.0);
    });

    test('animationDuration default is 1.0', () {
      const DisplaySettings d = DisplaySettings();
      expect(d.animationDuration, 1.0);
    });

    test('boardCornerRadius default is 5.0', () {
      const DisplaySettings d = DisplaySettings();
      expect(d.boardCornerRadius, 5.0);
    });

    test('boardInnerRingSize default is 1.0', () {
      const DisplaySettings d = DisplaySettings();
      expect(d.boardInnerRingSize, 1.0);
    });
  });
}
