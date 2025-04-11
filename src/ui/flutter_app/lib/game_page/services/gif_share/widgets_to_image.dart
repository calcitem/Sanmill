// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// widgets_to_image.dart

import 'package:flutter/material.dart';

import 'widgets_to_image_controller.dart';

class WidgetsToImage extends StatelessWidget {
  const WidgetsToImage({
    super.key,
    required this.child,
    required this.controller,
  });
  final Widget? child;
  final WidgetsToImageController controller;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: controller.containerKey,
      child: child,
    );
  }
}
