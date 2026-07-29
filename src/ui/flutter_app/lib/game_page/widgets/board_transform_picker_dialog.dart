// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../games/mill/mill_board_transform_actions.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/themes/app_styles.dart';
import '../services/transform/transform.dart';
import 'mini_board.dart';

/// A shared 4 × 4 picker for all Mill board symmetries.
///
/// [currentBoardLayout] is the current 26-character inner/middle/outer board
/// field. Each preview applies its transformation relative to that layout.
class BoardTransformPickerDialog extends StatelessWidget {
  const BoardTransformPickerDialog({
    required this.sheetKey,
    required this.keyPrefix,
    required this.title,
    required this.currentBoardLayout,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onSelected,
    super.key,
  });

  final Key sheetKey;
  final String keyPrefix;
  final String title;
  final String currentBoardLayout;
  final Color backgroundColor;
  final Color foregroundColor;
  final ValueChanged<MillBoardTransformAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final List<_BoardTransformPreview> previews = _previews();
    assert(previews.isNotEmpty, 'Board transform picker must show options.');
    // The complete Mill transformation group has 16 entries, including the
    // identity. Keep the picker as a stable 4 × 4 matrix on phones as well as
    // larger screens so every option is visible without a ragged final row.
    final int crossAxisCount = math.min(4, math.max(1, previews.length));
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      key: sheetKey,
      backgroundColor: backgroundColor,
      surfaceTintColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(MediaQuery.sizeOf(context).width, 560),
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: IconTheme.merge(
          data: IconThemeData(color: foregroundColor),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: foregroundColor),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Text(
                      title,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: foregroundColor),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.builder(
                    key: Key('${keyPrefix}_grid'),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1,
                    ),
                    itemCount: previews.length,
                    itemBuilder: (BuildContext context, int index) {
                      final _BoardTransformPreview preview = previews[index];
                      return _BoardTransformPreviewTile(
                        key: Key('${keyPrefix}_${preview.action.id}'),
                        label: preview.action.label(S.of(context)),
                        boardLayout: preview.boardLayout,
                        borderColor: colorScheme.outlineVariant,
                        onTap: () {
                          final NavigatorState navigator = Navigator.of(
                            context,
                          );
                          navigator.pop();
                          if (preview.action.type ==
                              TransformationType.identity) {
                            return;
                          }
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => onSelected(preview.action),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<_BoardTransformPreview> _previews() {
    return <_BoardTransformPreview>[
      for (final MillBoardTransformAction action
          in allMillBoardTransformActions)
        _BoardTransformPreview(
          action: action,
          boardLayout: _boardLayoutAfter(action.type),
        ),
    ];
  }

  String _boardLayoutAfter(TransformationType type) {
    assert(
      currentBoardLayout.length == 26,
      'Board transform preview requires inner/middle/outer layout.',
    );
    final String boardOnly = currentBoardLayout.replaceAll('/', '');
    assert(boardOnly.length == 24, 'Board layout must contain 24 points.');
    final String transformed = transformString(boardOnly, type);
    return '${transformed.substring(0, 8)}/'
        '${transformed.substring(8, 16)}/'
        '${transformed.substring(16, 24)}';
  }
}

class _BoardTransformPreview {
  const _BoardTransformPreview({
    required this.action,
    required this.boardLayout,
  });

  final MillBoardTransformAction action;
  final String boardLayout;
}

class _BoardTransformPreviewTile extends StatelessWidget {
  const _BoardTransformPreviewTile({
    super.key,
    required this.label,
    required this.boardLayout,
    required this.borderColor,
    required this.onTap,
  });

  final String label;
  final String boardLayout;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppStyles.compactRadius),
            onTap: onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppStyles.compactRadius),
                border: Border.all(color: borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppStyles.compactRadius),
                  child: ColoredBox(
                    color: DB().colorSettings.boardBackgroundColor,
                    child: CustomPaint(
                      painter: MiniBoardPainter(boardLayout: boardLayout),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
