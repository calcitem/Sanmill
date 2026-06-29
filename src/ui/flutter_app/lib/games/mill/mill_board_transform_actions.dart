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

String _rotateLabel(S strings) => strings.rotate;

String _horizontalFlipLabel(S strings) => strings.horizontalFlip;

String _verticalFlipLabel(S strings) => strings.verticalFlip;

String _innerOuterFlipLabel(S strings) => strings.innerOuterFlip;
