import 'package:flutter/material.dart';
import 'utils.dart';

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
