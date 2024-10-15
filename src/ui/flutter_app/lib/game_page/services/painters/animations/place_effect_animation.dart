// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../../../shared/database/database.dart';

/// Abstract class for PlaceEffect animations.
abstract class PlaceEffectAnimation {
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue);
}

/// Default implementation of the PlaceEffect animation.
class DefaultPlaceEffectAnimation implements PlaceEffectAnimation {
  @override
  void draw(
      Canvas canvas, Offset center, double diameter, double animationValue) {
    if (DB().displaySettings.animationDuration == 0.0) {
      return;
    }

    // Apply easing to the animation value.
    final double easedAnimation = Curves.easeOut.transform(animationValue);

    // Calculate the maximum and current radius based on the diameter and animation.
    final double maxRadius = diameter * 0.25;
    final double currentRadius = diameter + maxRadius * easedAnimation;

    // Define the main and secondary opacities.
    final double mainOpacity = 0.6 * (1.0 - easedAnimation);
    final double secondOpacity = mainOpacity * 0.8;

    // Cache the board line color to avoid repeated calls.
    final ui.Color boardLineColor = DB().colorSettings.boardLineColor;

    // Define the configuration for each effect layer.
    final List<_EffectLayer> layers = <_EffectLayer>[
      // Main layer.
      _EffectLayer(
        radiusFactor: 1.0,
        opacityFactor: 0.8,
      ),
      // Second layer.
      _EffectLayer(
        radiusFactor: 0.75,
        opacityFactor: 0.5,
      ),
      // Third layer.
      _EffectLayer(
        radiusFactor: 0.5,
        opacityFactor: 0.2,
      ),
    ];

    // Iterate over each layer configuration to draw the circles.
    for (final _EffectLayer layer in layers) {
      // Determine the radius for the current layer.
      final double layerRadius = currentRadius * layer.radiusFactor;

      // Determine the opacity for the current layer.
      double layerOpacity;
      if (layer.opacityFactor == 1.0) {
        layerOpacity = mainOpacity;
      } else if (layer.opacityFactor == 0.8) {
        layerOpacity = secondOpacity;
      } else {
        layerOpacity = mainOpacity * layer.opacityFactor;
      }

      // Create the paint with a radial gradient shader.
      final Paint paint = Paint()
        ..shader = RadialGradient(
          colors: <ui.Color>[
            boardLineColor.withOpacity(layerOpacity),
            boardLineColor.withOpacity(0.0),
          ],
          stops: const <double>[
            0.0,
            1.0,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: layerRadius))
        ..style = PaintingStyle.fill;

      // Draw the circle on the canvas.
      canvas.drawCircle(center, layerRadius, paint);
    }
  }
}

/// A helper class to define the properties of each effect layer.
class _EffectLayer {
  _EffectLayer({
    required this.radiusFactor,
    required this.opacityFactor,
  });

  /// The factor by which to multiply the current radius.
  final double radiusFactor;

  /// The factor by which to multiply the main opacity.
  final double opacityFactor;
}
