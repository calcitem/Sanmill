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
        label: _rotate90Label,
      ),
      MillBoardTransformAction(
        id: 'rotate_180',
        type: TransformationType.rotate180,
        icon: FluentIcons.arrow_rotate_clockwise_24_regular,
        label: _rotate180Label,
      ),
      MillBoardTransformAction(
        id: 'rotate_270',
        type: TransformationType.rotate270,
        icon: FluentIcons.arrow_rotate_counterclockwise_24_regular,
        label: _rotate270Label,
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
        label: _backslashFlipLabel,
      ),
      MillBoardTransformAction(
        id: 'slash_flip',
        type: TransformationType.mirrorSlash,
        icon: FluentIcons.flip_vertical_24_regular,
        label: _slashFlipLabel,
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
        label: _swapRotate90Label,
      ),
      MillBoardTransformAction(
        id: 'swap_rotate_180',
        type: TransformationType.swapRotate180,
        icon: FluentIcons.arrow_rotate_clockwise_24_regular,
        label: _swapRotate180Label,
      ),
      MillBoardTransformAction(
        id: 'swap_rotate_270',
        type: TransformationType.swapRotate270,
        icon: FluentIcons.arrow_rotate_counterclockwise_24_regular,
        label: _swapRotate270Label,
      ),
      MillBoardTransformAction(
        id: 'swap_vertical_flip',
        type: TransformationType.swapMirrorVertical,
        icon: FluentIcons.flip_vertical_24_regular,
        label: _swapVerticalFlipLabel,
      ),
      MillBoardTransformAction(
        id: 'swap_horizontal_flip',
        type: TransformationType.swapMirrorHorizontal,
        icon: FluentIcons.flip_horizontal_24_regular,
        label: _swapHorizontalFlipLabel,
      ),
      MillBoardTransformAction(
        id: 'swap_backslash_flip',
        type: TransformationType.swapMirrorBackslash,
        icon: FluentIcons.flip_horizontal_24_regular,
        label: _swapBackslashFlipLabel,
      ),
      MillBoardTransformAction(
        id: 'swap_slash_flip',
        type: TransformationType.swapMirrorSlash,
        icon: FluentIcons.flip_vertical_24_regular,
        label: _swapSlashFlipLabel,
      ),
    ];

String _identityLabel(S strings) => strings.boardTransformIdentity;

String _rotateLabel(S strings) => strings.rotate;

String _rotate90Label(S strings) => strings.boardTransformRotateDegrees(90);

String _rotate180Label(S strings) => strings.boardTransformRotateDegrees(180);

String _rotate270Label(S strings) => strings.boardTransformRotateDegrees(270);

String _horizontalFlipLabel(S strings) => strings.horizontalFlip;

String _verticalFlipLabel(S strings) => strings.verticalFlip;

String _innerOuterFlipLabel(S strings) => strings.innerOuterFlip;

String _backslashFlipLabel(S strings) => strings.boardTransformBackslashMirror;

String _slashFlipLabel(S strings) => strings.boardTransformSlashMirror;

String _swapLabel(S strings, String transform) =>
    '${strings.innerOuterFlip} + $transform';

String _swapRotate90Label(S strings) =>
    _swapLabel(strings, _rotate90Label(strings));

String _swapRotate180Label(S strings) =>
    _swapLabel(strings, _rotate180Label(strings));

String _swapRotate270Label(S strings) =>
    _swapLabel(strings, _rotate270Label(strings));

String _swapVerticalFlipLabel(S strings) =>
    _swapLabel(strings, _verticalFlipLabel(strings));

String _swapHorizontalFlipLabel(S strings) =>
    _swapLabel(strings, _horizontalFlipLabel(strings));

String _swapBackslashFlipLabel(S strings) =>
    _swapLabel(strings, _backslashFlipLabel(strings));

String _swapSlashFlipLabel(S strings) =>
    _swapLabel(strings, _slashFlipLabel(strings));
