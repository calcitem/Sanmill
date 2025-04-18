// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// piece_effect_selection_page.dart

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../game_page/services/mill.dart';
import '../../game_page/services/painters/animations/piece_effect_animation.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/themes/app_theme.dart';

/// Effect item model to hold the name and animation instance.
class EffectItem {
  EffectItem({required this.name, required this.animation});

  final String name;
  final PieceEffectAnimation animation;
}

/// The main page that displays the animations in a grid.
class PieceEffectSelectionPage extends StatefulWidget {
  const PieceEffectSelectionPage({super.key, required this.moveType});

  final MoveType moveType;

  @override
  PieceEffectSelectionPageState createState() =>
      PieceEffectSelectionPageState();
}

class PieceEffectSelectionPageState extends State<PieceEffectSelectionPage> {
  late List<EffectItem> effects;

  @override
  void initState() {
    super.initState();

    final List<EffectItem> placeEffectAnimation = <EffectItem>[
      EffectItem(name: 'Aura', animation: AuraPieceEffectAnimation()),
      EffectItem(name: 'Echo', animation: EchoPieceEffectAnimation()),
      EffectItem(name: 'Ripple', animation: RipplePieceEffectAnimation()),
      EffectItem(name: 'Spiral', animation: SpiralPieceEffectAnimation()),
      EffectItem(name: 'Rotate', animation: RotatePieceEffectAnimation()),
      EffectItem(name: 'Orbit', animation: OrbitPieceEffectAnimation()),
      EffectItem(name: 'Radial', animation: RadialPieceEffectAnimation()),
      EffectItem(name: 'Expand', animation: ExpandPieceEffectAnimation()),
      EffectItem(name: 'Glow', animation: GlowPieceEffectAnimation()),
      EffectItem(name: 'Disperse', animation: DispersePieceEffectAnimation()),
      EffectItem(name: 'Sparkle', animation: SparklePieceEffectAnimation()),
      EffectItem(name: 'Burst', animation: BurstPieceEffectAnimation()),
      EffectItem(name: 'Shatter', animation: ShatterPieceEffectAnimation()),
      EffectItem(name: 'Fireworks', animation: FireworksPieceEffectAnimation()),
      EffectItem(name: 'Explode', animation: ExplodePieceEffectAnimation()),
      EffectItem(
          name: 'RippleGradient',
          animation: RippleGradientPieceEffectAnimation()),
      EffectItem(name: 'WarpWave', animation: WarpWavePieceEffectAnimation()),
      EffectItem(name: 'ShockWave', animation: ShockWavePieceEffectAnimation()),
      EffectItem(name: 'PulseRing', animation: PulseRingPieceEffectAnimation()),
      EffectItem(
          name: 'RainbowWave', animation: RainbowWavePieceEffectAnimation()),
      EffectItem(name: 'Twist', animation: TwistPieceEffectAnimation()),
      EffectItem(
          name: 'ShadowPulse', animation: ShadowPulsePieceEffectAnimation()),
      EffectItem(
          name: 'RainRipple', animation: RainRipplePieceEffectAnimation()),
      EffectItem(name: 'NeonFlash', animation: NeonFlashPieceEffectAnimation()),
      EffectItem(name: 'InkSpread', animation: InkSpreadPieceEffectAnimation()),
      EffectItem(name: 'BubblePop', animation: BubblePopPieceEffectAnimation()),
      EffectItem(
          name: 'ColorSwirl', animation: ColorSwirlPieceEffectAnimation()),
      EffectItem(name: 'Starburst', animation: StarburstPieceEffectAnimation()),
      EffectItem(
          name: 'PixelGlitch', animation: PixelGlitchPieceEffectAnimation()),
      EffectItem(name: 'FireTrail', animation: FireTrailPieceEffectAnimation()),
    ];

    // Initialize the list of effect items.
    final List<EffectItem> removeEffectAnimation = <EffectItem>[
      EffectItem(name: 'Vanish', animation: VanishPieceEffectAnimation()),
      EffectItem(name: 'Fade', animation: FadePieceEffectAnimation()),
      EffectItem(name: 'Melt', animation: MeltPieceEffectAnimation()),
      ...placeEffectAnimation,
    ];

    effects = widget.moveType == MoveType.place
        ? placeEffectAnimation
        : removeEffectAnimation;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('piece_effect_selection_page_scaffold'),
      appBar: AppBar(
        key: const Key('piece_effect_selection_page_appbar'),
        title: Text(
          widget.moveType == MoveType.place
              ? S.of(context).placeEffectAnimation
              : S.of(context).removeEffectAnimation,
          key: const Key('piece_effect_selection_page_appbar_title'),
          style: AppTheme.appBarTheme.titleTextStyle,
        ),
      ),
      body: GridView.builder(
        key: const Key('piece_effect_selection_page_gridview_builder'),
        padding: const EdgeInsets.all(8.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, // 3 items per row
          crossAxisSpacing: 8.0,
          mainAxisSpacing: 8.0,
        ),
        itemCount: effects.length,
        itemBuilder: (BuildContext context, int index) {
          final EffectItem effectItem = effects[index];
          return EffectGridItem(
            key: Key('effect_grid_item_$index'),
            effectItem: effectItem,
            onTap: () {
              // Handle the selection logic here.
              if (kDebugMode) {
                print('Selected effect: ${effectItem.name}');
              }

              Navigator.pop(context,
                  effectItem); // Return the selected effect to the previous page.
            },
          );
        },
      ),
    );
  }
}

/// Widget representing each grid item in the selection page.
class EffectGridItem extends StatefulWidget {
  const EffectGridItem({
    super.key,
    required this.effectItem,
    required this.onTap,
  });

  final EffectItem effectItem;
  final VoidCallback onTap;

  @override
  EffectGridItemState createState() => EffectGridItemState();
}

class EffectGridItemState extends State<EffectGridItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    // Initialize the animation controller.
    _controller = AnimationController(
      duration: const Duration(seconds: 2), // Duration of each animation cycle.
      vsync: this,
    );

    _animation = CurvedAnimation(parent: _controller, curve: Curves.linear);

    // Repeat the animation indefinitely.
    _controller.repeat();
  }

  @override
  void dispose() {
    // Dispose the animation controller to free resources.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('effect_grid_item_gesture_detector'),
      onTap: widget.onTap,
      child: Container(
        key: const Key('effect_grid_item_container'),
        // Set the background color of each grid item here.
        color: DB()
            .colorSettings
            .boardBackgroundColor, // Change to your preferred color.
        child: Column(
          key: const Key('effect_grid_item_column'),
          children: <Widget>[
            Expanded(
              child: AspectRatio(
                aspectRatio: 1.0,
                child: AnimatedBuilder(
                  key: const Key('effect_grid_item_animated_builder'),
                  animation: _animation,
                  builder: (BuildContext context, Widget? child) {
                    return CustomPaint(
                      key: const Key('effect_grid_item_custom_paint'),
                      painter: EffectPainter(
                        animation: widget.effectItem.animation,
                        animationValue: _animation.value,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(
              key: Key('effect_grid_item_sized_box'),
              height: 4.0,
            ),
            // Customize text color here.
            Text(
              widget.effectItem.name,
              key: const Key('effect_grid_item_text'),
              style: TextStyle(
                color: DB()
                    .colorSettings
                    .boardLineColor
                    .withAlpha(100), // Set the effect name text color.
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter that uses the PieceEffectAnimation to draw the effect.
class EffectPainter extends CustomPainter {
  EffectPainter({required this.animation, required this.animationValue});

  final PieceEffectAnimation animation;
  final double animationValue;

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate the center and diameter based on the size of the widget.
    final Offset center = Offset(size.width / 2, size.height / 2);
    // Reduce the diameter by applying a scale factor.
    const double scale = 0.5; // Set this between 0 and 1 to adjust the size.
    final double diameter = min(size.width, size.height) * scale;

    // Use the animation's draw method to render the effect.
    animation.draw(canvas, center, diameter, animationValue);
  }

  @override
  bool shouldRepaint(covariant EffectPainter oldDelegate) {
    // Repaint when the animation value changes.
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.animation != animation;
  }
}
