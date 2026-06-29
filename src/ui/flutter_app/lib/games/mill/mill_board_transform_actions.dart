// SPDX-License-Identifier: GPL-3.0-or-later
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
        id: 'horizontal_flip',
        type: TransformationType.mirrorHorizontal,
        icon: FluentIcons.flip_horizontal_24_regular,
        label: _horizontalFlipLabel,
      ),
      MillBoardTransformAction(
        id: 'vertical_flip',
        type: TransformationType.mirrorVertical,
        icon: FluentIcons.flip_vertical_24_regular,
        label: _verticalFlipLabel,
      ),
      MillBoardTransformAction(
        id: 'inner_outer_flip',
        type: TransformationType.swap,
        icon: FluentIcons.arrow_expand_24_regular,
        label: _innerOuterFlipLabel,
      ),
    ];

const List<MillBoardTransformAction> millBoardTransformFullActions =
    <MillBoardTransformAction>[
      ...millBoardTransformActions,
      MillBoardTransformAction(
        id: 'rotate_180',
        type: TransformationType.rotate180,
        icon: FluentIcons.arrow_rotate_clockwise_24_regular,
        label: _rotate180Label,
      ),
      MillBoardTransformAction(
        id: 'rotate_270',
        type: TransformationType.rotate270,
        icon: FluentIcons.arrow_rotate_clockwise_24_regular,
        label: _rotate270Label,
      ),
      MillBoardTransformAction(
        id: 'mirror_backslash',
        type: TransformationType.mirrorBackslash,
        icon: FluentIcons.flip_horizontal_24_regular,
        label: _mirrorBackslashLabel,
      ),
      MillBoardTransformAction(
        id: 'mirror_slash',
        type: TransformationType.mirrorSlash,
        icon: FluentIcons.flip_vertical_24_regular,
        label: _mirrorSlashLabel,
      ),
      MillBoardTransformAction(
        id: 'swap_rotate_90',
        type: TransformationType.swapRotate90,
        icon: FluentIcons.arrow_expand_24_regular,
        label: _swapRotate90Label,
      ),
      MillBoardTransformAction(
        id: 'swap_rotate_180',
        type: TransformationType.swapRotate180,
        icon: FluentIcons.arrow_expand_24_regular,
        label: _swapRotate180Label,
      ),
      MillBoardTransformAction(
        id: 'swap_rotate_270',
        type: TransformationType.swapRotate270,
        icon: FluentIcons.arrow_expand_24_regular,
        label: _swapRotate270Label,
      ),
      MillBoardTransformAction(
        id: 'swap_mirror_vertical',
        type: TransformationType.swapMirrorVertical,
        icon: FluentIcons.arrow_expand_24_regular,
        label: _swapMirrorVerticalLabel,
      ),
      MillBoardTransformAction(
        id: 'swap_mirror_horizontal',
        type: TransformationType.swapMirrorHorizontal,
        icon: FluentIcons.arrow_expand_24_regular,
        label: _swapMirrorHorizontalLabel,
      ),
      MillBoardTransformAction(
        id: 'swap_mirror_backslash',
        type: TransformationType.swapMirrorBackslash,
        icon: FluentIcons.arrow_expand_24_regular,
        label: _swapMirrorBackslashLabel,
      ),
      MillBoardTransformAction(
        id: 'swap_mirror_slash',
        type: TransformationType.swapMirrorSlash,
        icon: FluentIcons.arrow_expand_24_regular,
        label: _swapMirrorSlashLabel,
      ),
    ];

String _rotateLabel(S strings) => strings.rotate;

String _horizontalFlipLabel(S strings) => strings.horizontalFlip;

String _verticalFlipLabel(S strings) => strings.verticalFlip;

String _innerOuterFlipLabel(S strings) => strings.innerOuterFlip;

String _rotate180Label(S strings) => '${strings.rotate} x2';

String _rotate270Label(S strings) => '${strings.rotate} x3';

String _mirrorBackslashLabel(S strings) =>
    '${strings.horizontalFlip} + ${strings.rotate}';

String _mirrorSlashLabel(S strings) =>
    '${strings.verticalFlip} + ${strings.rotate}';

String _swapRotate90Label(S strings) =>
    '${strings.innerOuterFlip} + ${strings.rotate}';

String _swapRotate180Label(S strings) =>
    '${strings.innerOuterFlip} + ${strings.rotate} x2';

String _swapRotate270Label(S strings) =>
    '${strings.innerOuterFlip} + ${strings.rotate} x3';

String _swapMirrorVerticalLabel(S strings) =>
    '${strings.innerOuterFlip} + ${strings.verticalFlip}';

String _swapMirrorHorizontalLabel(S strings) =>
    '${strings.innerOuterFlip} + ${strings.horizontalFlip}';

String _swapMirrorBackslashLabel(S strings) =>
    '${strings.innerOuterFlip} + ${strings.horizontalFlip} + '
    '${strings.rotate}';

String _swapMirrorSlashLabel(S strings) =>
    '${strings.innerOuterFlip} + ${strings.verticalFlip} + ${strings.rotate}';
