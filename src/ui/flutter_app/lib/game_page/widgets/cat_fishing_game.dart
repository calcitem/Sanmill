// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/database/database.dart';

/// A simple cat fishing mini-game that can be played while waiting for LLM responses.
/// The game involves a cat trying to catch fish that move around the screen.
class CatFishingGame extends StatefulWidget {
  const CatFishingGame({super.key, this.onScoreUpdate});

  /// Callback when score changes
  final Function(int score)? onScoreUpdate;

  @override
  State<CatFishingGame> createState() => _CatFishingGameState();
}

class _CatFishingGameState extends State<CatFishingGame>
    with SingleTickerProviderStateMixin {
  // Game state
  int _score = 0;
  late Offset _catPosition;
  late Offset _fishPosition;
  late Size _gameSize;
  final double _catSize = 50.0;
  final double _fishSize = 30.0;

  // Animation controller for the game loop
  late AnimationController _controller;

  // Random for generating fish positions
  final math.Random _random = math.Random();

  // Timer for moving the fish periodically
  Timer? _fishMovementTimer;

  @override
  void initState() {
    super.initState();

    // Initialize animation controller for game loop
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16), // ~60 FPS
    )..repeat();

    // Set initial positions
    _catPosition = const Offset(100, 100);
    _fishPosition = const Offset(200, 200);

    // Start fish movement
    _startFishMovement();
  }

  @override
  void dispose() {
    _controller.dispose();
    _fishMovementTimer?.cancel();
    super.dispose();
  }

  // Generate a random position within game bounds
  Offset _getRandomPosition() {
    return Offset(
      _random.nextDouble() * (_gameSize.width - _fishSize * 2) + _fishSize,
      _random.nextDouble() * (_gameSize.height - _fishSize * 2) + _fishSize,
    );
  }

  // Start the fish movement logic
  void _startFishMovement() {
    _fishMovementTimer?.cancel();
    _fishMovementTimer =
        Timer.periodic(const Duration(milliseconds: 2000), (Timer timer) {
      if (mounted) {
        setState(() {
          _fishPosition = _getRandomPosition();
        });
      }
    });
  }

  // Check if cat has caught the fish (overlapping)
  bool _checkCatch() {
    final double distance = (_catPosition - _fishPosition).distance;
    return distance < (_catSize / 2 + _fishSize / 2);
  }

  // Handle cat movement via tap/drag
  void _moveCat(Offset position) {
    setState(() {
      _catPosition = position;

      // Check if cat caught the fish
      if (_checkCatch()) {
        _score++;
        widget.onScoreUpdate?.call(_score);
        _fishPosition = _getRandomPosition();

        // Reset fish movement timer to make game more dynamic
        _startFishMovement();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Store game size for bounds calculation
        _gameSize = Size(constraints.maxWidth, constraints.maxHeight);

        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            // Light blue background for water effect
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: <Widget>[
              // Fish
              AnimatedPositioned(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                left: _fishPosition.dx - _fishSize / 2,
                top: _fishPosition.dy - _fishSize / 2,
                child: _buildFish(),
              ),

              // Cat (paw)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                left: _catPosition.dx - _catSize / 2,
                top: _catPosition.dy - _catSize / 2,
                child: _buildCat(),
              ),

              // Score display
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '🐟 $_score',
                    style: TextStyle(
                      color: DB().colorSettings.messageColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),

              // Invisible GestureDetector covering the whole game area
              Positioned.fill(
                child: GestureDetector(
                  onTapDown: (TapDownDetails details) =>
                      _moveCat(details.localPosition),
                  onPanUpdate: (DragUpdateDetails details) =>
                      _moveCat(details.localPosition),
                  // Transparent so it doesn't interfere with visuals
                  child: Container(color: Colors.transparent),
                ),
              ),

              // Game instructions
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '点击或拖动来抓鱼！',
                      style: TextStyle(
                        color: DB().colorSettings.messageColor,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Build the cat (paw) widget
  Widget _buildCat() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        // Oscillate the paw slightly for a playful effect
        final double angle = math.sin(_controller.value * 2 * math.pi) * 0.1;

        return Transform.rotate(
          angle: angle,
          child: Container(
            width: _catSize,
            height: _catSize,
            decoration: const BoxDecoration(
              color: Colors.transparent,
            ),
            child: const Center(
              child: Text(
                '🐾',
                style: TextStyle(fontSize: 36),
              ),
            ),
          ),
        );
      },
    );
  }

  // Build the fish widget
  Widget _buildFish() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        // Fish wiggle animation
        final double angle = math.sin(_controller.value * 4 * math.pi) * 0.2;

        return Transform.rotate(
          angle: angle,
          child: Container(
            width: _fishSize,
            height: _fishSize,
            decoration: const BoxDecoration(
              color: Colors.transparent,
            ),
            child: const Center(
              child: Text(
                '🐟',
                style: TextStyle(fontSize: 24),
              ),
            ),
          ),
        );
      },
    );
  }
}
