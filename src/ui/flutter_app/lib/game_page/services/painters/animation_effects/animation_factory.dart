import 'package:flutter/material.dart';

import 'animation_types.dart';
import 'place_expansion_effect.dart';
import 'place_ripple_effect.dart';
import 'remove_fade_effect.dart';
import 'remove_particles_effect.dart';

/// Configuration for selecting animation effects.
class AnimationConfig {
  const AnimationConfig({
    required this.placeEffectType,
    required this.removeEffectType,
  });
  final PlaceEffectType placeEffectType;
  final RemoveEffectType removeEffectType;
}

/// Factory to retrieve the appropriate animation effect functions.
class AnimationFactory {
  AnimationFactory(this.config);
  final AnimationConfig config;

  /// Returns the place effect function based on the configuration.
  void Function(Canvas, Offset, double, double) getPlaceEffect() {
    switch (config.placeEffectType) {
      case PlaceEffectType.ripple:
        return drawPlaceRippleEffect;
      case PlaceEffectType.expansion:
        return drawPlaceExpansionEffect;
    }
  }

  /// Returns the remove effect function based on the configuration.
  void Function(Canvas, Offset, double, double) getRemoveEffect() {
    switch (config.removeEffectType) {
      case RemoveEffectType.particles:
        return drawRemoveParticleEffect;
      case RemoveEffectType.fade:
        return drawRemoveFadeEffect;
    }
  }
}
