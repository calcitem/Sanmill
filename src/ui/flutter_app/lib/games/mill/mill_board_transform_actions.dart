// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';

import '../../game_page/services/transform/transform.dart';
import '../../generated/intl/l10n.dart';

class MillBoardTransformAction {
  const MillBoardTransformAction({
    required this.id,
    required this.type,
    required this.icon,
    required this.label,
  });

  final String id;
  final TransformationType type;
  final IconData icon;
  final String Function(S strings) label;
}

const List<MillBoardTransformAction> millBoardTransformActions =
    <MillBoardTransformAction>[
      MillBoardTransformAction(
        id: 'rotate',
        type: TransformationType.rotate90,
        icon: FluentIcons.arrow_rotate_clockwise_24_regular,
        label: _rotateLabel,
      ),
      MillBoardTransformAction(
        id: 'vertical_flip',
        type: TransformationType.mirrorVertical,
        icon: FluentIcons.flip_vertical_24_regular,
        label: _verticalFlipLabel,
      ),
      MillBoardTransformAction(
        id: 'horizontal_flip',
        type: TransformationType.mirrorHorizontal,
        icon: FluentIcons.flip_horizontal_24_regular,
        label: _horizontalFlipLabel,
      ),
      MillBoardTransformAction(
        id: 'inner_outer_flip',
        type: TransformationType.swap,
        icon: FluentIcons.arrow_expand_24_regular,
        label: _innerOuterFlipLabel,
      ),
    ];

const List<MillBoardTransformAction> allMillBoardTransformActions =
    <MillBoardTransformAction>[
      MillBoardTransformAction(
        id: 'identity',
        type: TransformationType.identity,
        icon: FluentIcons.square_24_regular,
        label: _identityLabel,
      ),
      MillBoardTransformAction(
        id: 'rotate',
        type: TransformationType.rotate90,
        icon: FluentIcons.arrow_rotate_clockwise_24_regular,
        label: _rotateLabel,
      ),
      MillBoardTransformAction(
        id: 'rotate_180',
        type: TransformationType.rotate180,
        icon: FluentIcons.arrow_rotate_clockwise_24_regular,
        label: _flipBoardLabel,
      ),
      MillBoardTransformAction(
        id: 'rotate_270',
        type: TransformationType.rotate270,
        icon: FluentIcons.arrow_rotate_counterclockwise_24_regular,
        label: _flipBoardLabel,
      ),
      MillBoardTransformAction(
        id: 'vertical_flip',
        type: TransformationType.mirrorVertical,
        icon: FluentIcons.flip_vertical_24_regular,
        label: _verticalFlipLabel,
      ),
      MillBoardTransformAction(
        id: 'horizontal_flip',
        type: TransformationType.mirrorHorizontal,
        icon: FluentIcons.flip_horizontal_24_regular,
        label: _horizontalFlipLabel,
      ),
      MillBoardTransformAction(
        id: 'backslash_flip',
        type: TransformationType.mirrorBackslash,
        icon: FluentIcons.flip_horizontal_24_regular,
        label: _flipBoardLabel,
      ),
      MillBoardTransformAction(
        id: 'slash_flip',
        type: TransformationType.mirrorSlash,
        icon: FluentIcons.flip_vertical_24_regular,
        label: _flipBoardLabel,
      ),
      MillBoardTransformAction(
        id: 'inner_outer_flip',
        type: TransformationType.swap,
        icon: FluentIcons.arrow_expand_24_regular,
        label: _innerOuterFlipLabel,
      ),
      MillBoardTransformAction(
        id: 'swap_rotate_90',
        type: TransformationType.swapRotate90,
        icon: FluentIcons.arrow_rotate_clockwise_24_regular,
        label: _flipBoardLabel,
      ),
      MillBoardTransformAction(
        id: 'swap_rotate_180',
        type: TransformationType.swapRotate180,
        icon: FluentIcons.arrow_rotate_clockwise_24_regular,
        label: _flipBoardLabel,
      ),
      MillBoardTransformAction(
        id: 'swap_rotate_270',
        type: TransformationType.swapRotate270,
        icon: FluentIcons.arrow_rotate_counterclockwise_24_regular,
        label: _flipBoardLabel,
      ),
      MillBoardTransformAction(
        id: 'swap_vertical_flip',
        type: TransformationType.swapMirrorVertical,
        icon: FluentIcons.flip_vertical_24_regular,
        label: _flipBoardLabel,
      ),
      MillBoardTransformAction(
        id: 'swap_horizontal_flip',
        type: TransformationType.swapMirrorHorizontal,
        icon: FluentIcons.flip_horizontal_24_regular,
        label: _flipBoardLabel,
      ),
      MillBoardTransformAction(
        id: 'swap_backslash_flip',
        type: TransformationType.swapMirrorBackslash,
        icon: FluentIcons.flip_horizontal_24_regular,
        label: _flipBoardLabel,
      ),
      MillBoardTransformAction(
        id: 'swap_slash_flip',
        type: TransformationType.swapMirrorSlash,
        icon: FluentIcons.flip_vertical_24_regular,
        label: _flipBoardLabel,
      ),
    ];

String _identityLabel(S strings) => strings.board;

String _rotateLabel(S strings) => strings.rotate;

String _horizontalFlipLabel(S strings) => strings.horizontalFlip;

String _verticalFlipLabel(S strings) => strings.verticalFlip;

String _innerOuterFlipLabel(S strings) => strings.innerOuterFlip;

String _flipBoardLabel(S strings) => strings.flipBoard;
