// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers
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
      appBar: AppBar(
        title: Text(
          widget.moveType == MoveType.place
              ? S.of(context).placeEffectAnimation
              : S.of(context).removeEffectAnimation,
          style: AppTheme.appBarTheme.titleTextStyle,
        ),
      ),
      body: GridView.builder(
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
      onTap: widget.onTap,
      child: Container(
        // Set the background color of each grid item here.
        color: DB()
            .colorSettings
            .boardBackgroundColor, // Change to your preferred color.
        child: Column(
          children: <Widget>[
            Expanded(
              child: AspectRatio(
                aspectRatio: 1.0,
                child: AnimatedBuilder(
                  animation: _animation,
                  builder: (BuildContext context, Widget? child) {
                    return CustomPaint(
                      painter: EffectPainter(
                        animation: widget.effectItem.animation,
                        animationValue: _animation.value,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 4.0),
            // Customize text color here.
            Text(
              widget.effectItem.name,
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