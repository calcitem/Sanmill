// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Assuming database.dart provides DB().colorSettings.messageColor
// If not, replace with a default color like Colors.white
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';

// Enum to define fish types
enum FishType {
  normal, // Common fish, average properties
  fast, // Fast-moving fish
  large, // Larger fish worth more points
  golden, // Rare valuable fish
  tiny, // Very small fish, hard to catch
  jellyfish, // Erratic movement pattern
  shark, // Large and aggressive
  bubblefish, // Moves in bubble-like patterns
  crab // Moves sideways more than forward
}

// Enum for movement direction
enum Direction { up, down, left, right }

/// A game combining cat fishing and snake mechanics.
/// Cat segments grow after catching fish, creating a snake-like chain.
/// The player must navigate the cat chain to catch fish without colliding with itself.
/// Movement speed is controlled by gesture speed.
class CatFishingGame extends StatefulWidget {
  const CatFishingGame({super.key, this.onScoreUpdate});

  /// Callback when score changes
  final Function(int score)? onScoreUpdate;

  @override
  State<CatFishingGame> createState() => _CatFishingGameState();
}

class _CatFishingGameState extends State<CatFishingGame>
    with SingleTickerProviderStateMixin {
  // Current score and remaining time
  int _score = 0;
  int _timeLeft = 60; // 60-second countdown
  bool _isGameOver = false;
  String _gameOverReason = '';

  // Debug mode flag
  final bool _isDebug = false; // Set to true to enable debug logging

  // Size of game area
  late Size _gameSize = Size.zero;

  // Snake-like cat chain
  final Queue<Offset> _catSegments = Queue<Offset>();
  int _catLength = 3; // Initial length
  Direction _direction = Direction.right; // Initial direction
  Direction _nextDirection = Direction.right; // Buffer for next direction
  final double _catSegmentSize = 24.0;

  // Speed control properties
  final double _baseMoveDistance = 4.0; // Base movement distance per update
  double _currentMoveDistance =
      4.0; // Current movement distance (adjusted by gestures)
  final double _maxMoveDistance = 16.0; // Maximum move distance (speed limit)
  final double _speedDecayRate =
      0.95; // Speed decay rate (slows down gradually)
  final double _minMoveDistance = 2.0; // Minimum move distance
  DateTime _lastGestureTime = DateTime.now(); // Track time of last gesture

  // Movement update timer (separate from animation for better control)
  Timer? _moveTimer;

  // Animation controller for visual effects
  late AnimationController _controller;

  // Countdown timer
  Timer? _gameTimer;

  // Random generator for spawning
  final math.Random _random = math.Random();

  // List of active fish
  final List<_Fish> _fishes = <_Fish>[];
  final int _numFish = 7; // number of fish on screen

  // Track fish eaten count to adjust difficulty
  int _fishEatenCount = 0;

  // Speed boost for fish after each catch
  final double _fishSpeedBoostPerCatch = 0.05;

  // Maximum speed multiplier for fish to prevent too much difficulty
  final double _maxFishSpeedMultiplier = 2.5;

  // Base chance for fish to change direction randomly
  double _fishRandomDirectionChance = 0.3;

  // Maximum chance for fish direction change (increases with difficulty)
  final double _maxFishRandomDirectionChance = 0.7;

  // Base amount of directional change
  double _fishDirectionChangeAmount = 0.4;

  // Maximum direction change amount (increases with difficulty)
  final double _maxFishDirectionChangeAmount = 1.2;

  // Color for text messages
  late Color _messageColor;

  // Floating text effects when catching fish
  final List<_CatchEffect> _catchEffects = <_CatchEffect>[];

  @override
  void initState() {
    super.initState();

    // Try to load message color from database; fallback to white
    try {
      _messageColor = DB().colorSettings.messageColor;
    } catch (e) {
      _messageColor = Colors.white;
      logger.w(
          "Warning: Could not get color from DB().colorSettings.messageColor. Using fallback.");
    }

    // Set up the animation controller for visual effects
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    // Start the countdown timer
    _startGameTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize game components once we know the layout size
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_gameSize != Size.zero && _catSegments.isEmpty) {
        _initializeGame();
      }
    });
  }

  /// Initialize game components based on the game area size.
  void _initializeGame() {
    // Set initial cat position in the center
    final double centerX = (_gameSize.width / 2).floorToDouble();
    final double centerY = (_gameSize.height / 2).floorToDouble();

    _catSegments.clear();
    // Create initial cat segments with more spacing to avoid immediate self-collision
    for (int i = 0; i < _catLength; i++) {
      _catSegments
          .addFirst(Offset(centerX - i * _baseMoveDistance * 2, centerY));
    }

    // Initialize fish
    _initializeFish();

    // Start movement timer
    _startMovementTimer();

    setState(() {});
  }

  /// Initialize fish positions and properties based on the game area size.
  void _initializeFish() {
    if (_gameSize == Size.zero) {
      return;
    }
    _fishes.clear();
    for (int i = 0; i < _numFish; i++) {
      _fishes.add(_Fish.random(_random, _gameSize));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _gameTimer?.cancel();
    _moveTimer?.cancel();
    super.dispose();
  }

  /// Starts the movement timer for cat chain updates with faster interval
  /// for smoother movement at different speeds
  void _startMovementTimer() {
    _moveTimer?.cancel();
    // Faster update interval (50ms) for smoother movement
    _moveTimer =
        Timer.periodic(const Duration(milliseconds: 50), (Timer timer) {
      if (!mounted || _isGameOver) {
        timer.cancel();
        return;
      }
      _updateCatPosition();

      // Apply speed decay when no recent gesture input (natural slowdown)
      final DateTime now = DateTime.now();
      if (now.difference(_lastGestureTime).inMilliseconds > 300) {
        _decaySpeed();
      }
    });
  }

  /// Gradually reduce speed when no gesture input is detected
  void _decaySpeed() {
    if (_currentMoveDistance > _baseMoveDistance) {
      setState(() {
        _currentMoveDistance =
            math.max(_baseMoveDistance, _currentMoveDistance * _speedDecayRate);
      });
    }
  }

  /// Stops the movement timer
  void _stopMovementTimer() {
    _moveTimer?.cancel();
  }

  /// Starts or restarts the 60-second countdown timer.
  void _startGameTimer() {
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_timeLeft > 0) {
          _timeLeft--;
        } else {
          // Time's up → game over
          _gameOver("⏰");
        }
      });
    });
  }

  /// Increase fish speed and difficulty after catching a fish
  void _increaseFishDifficulty() {
    // Increase fish eaten count
    _fishEatenCount++;

    // Calculate difficulty factor (scales with fish eaten)
    math.min(1.0, _fishEatenCount / 30);

    // Update fish movement parameters based on difficulty
    _fishRandomDirectionChance = _fishRandomDirectionChance +
        ((_maxFishRandomDirectionChance - _fishRandomDirectionChance) * 0.1);

    _fishDirectionChangeAmount = _fishDirectionChangeAmount +
        ((_maxFishDirectionChangeAmount - _fishDirectionChangeAmount) * 0.1);

    // Apply speed boost to all remaining fish
    for (final _Fish fish in _fishes) {
      // Increase speed multiplier but cap at maximum
      fish.speedMultiplier = math.min(_maxFishSpeedMultiplier,
          fish.speedMultiplier + _fishSpeedBoostPerCatch);

      // Increase wiggle amount and speed with difficulty
      fish.wiggleAmount = math.min(0.8, fish.wiggleAmount + 0.02);
      fish.wiggleSpeed = math.min(8.0, fish.wiggleSpeed + 0.1);
    }
  }

  /// Update cat position based on direction and current speed
  void _updateCatPosition() {
    if (_isGameOver || !mounted) {
      return;
    }

    setState(() {
      // Update direction from input buffer
      _direction = _nextDirection;

      // Calculate new head position
      final Offset head = _catSegments.first;
      Offset newHead;

      // Move in current direction using the current speed
      switch (_direction) {
        case Direction.up:
          newHead = Offset(head.dx, head.dy - _currentMoveDistance);
          break;
        case Direction.down:
          newHead = Offset(head.dx, head.dy + _currentMoveDistance);
          break;
        case Direction.left:
          newHead = Offset(head.dx - _currentMoveDistance, head.dy);
          break;
        case Direction.right:
          newHead = Offset(head.dx + _currentMoveDistance, head.dy);
          break;
      }

      // Check wall collision with wrap-around
      if (newHead.dx < 0) {
        newHead = Offset(_gameSize.width, newHead.dy);
      } else if (newHead.dx > _gameSize.width) {
        newHead = Offset(0, newHead.dy);
      }

      if (newHead.dy < 0) {
        newHead = Offset(newHead.dx, _gameSize.height);
      } else if (newHead.dy > _gameSize.height) {
        newHead = Offset(newHead.dx, 0);
      }

      // Add new head
      _catSegments.addFirst(newHead);

      // Check self-collision only if cat is long enough to have a chance of collision
      // A more reliable collision detection that avoids false positives
      bool selfCollision = false;

      // Only check collision if the cat is long enough
      if (_catSegments.length > 5) {
        // Skip at least the head + 5 segments,
        // or 1/3 of the total length if the cat is large.
        // This helps reduce false collision when making sharp turns.
        final int segmentsToSkip = math.max(5, _catSegments.length ~/ 3);

        // Get the head position
        final Offset headPos = _catSegments.first;
        final double collisionThreshold =
            _catSegmentSize * 0.4; // Reduced collision threshold

        // Check each segment after the skipped ones
        int index = 0;
        for (final Offset segment in _catSegments) {
          // Skip head and the first few segments
          if (index <= segmentsToSkip) {
            index++;
            continue;
          }

          // Calculate distance between head and this segment
          final double distance = (segment - headPos).distance;

          // Check if collision occurred with this segment
          if (distance < collisionThreshold) {
            selfCollision = true;

            // Log collision info for debugging
            if (_isDebug) {
              logger.i(
                  'Collision detected! Distance: $distance, Threshold: $collisionThreshold, Segment: $index');
            }

            break;
          }

          index++;
        }
      }

      if (selfCollision) {
        _gameOver("😮🐱🦷");

        // Remove the head we just added since we're ending the game
        if (_catSegments.isNotEmpty) {
          _catSegments.removeFirst();
        }

        return;
      }

      // Check fish collision
      for (final _Fish fish in _fishes) {
        final double distance = (fish.position - newHead).distance;
        final double catchDistance = _catSegmentSize / 2 + fish.size / 2;

        if (distance < catchDistance * 0.8) {
          // 0.8 multiplier for better feel
          // Caught a fish!
          _score += fish.points;
          widget.onScoreUpdate?.call(_score);

          // Create catch effect
          _createCatchEffect(fish);

          // Grow the cat by fish points
          _catLength += fish.points;

          // Increase difficulty after catching a fish
          _increaseFishDifficulty();

          // Respawn fish
          fish.respawn(_random, _gameSize);

          break;
        }
      }

      // Remove tail segments if we haven't grown
      while (_catSegments.length > _catLength) {
        _catSegments.removeLast();
      }

      // Update fish
      _updateFish();
    });
  }

  /// Update fish positions
  void _updateFish() {
    if (_isGameOver || _gameSize == Size.zero || _fishes.isEmpty) {
      return;
    }

    // Calculate time delta (smaller for smoother movement)
    const double dt = 0.05; // 50ms for smooth movement

    // Update each fish
    for (final _Fish fish in _fishes) {
      // Decrement the heading change timer
      fish.headingChangeTimer -= dt;

      // Check if it's time to change direction
      if (fish.headingChangeTimer <= 0) {
        // Reset timer
        fish.headingChangeTimer = fish.headingChangeInterval;

        // Set a new target heading based on fish type
        if (fish.type == FishType.jellyfish) {
          // Jellyfish make more erratic turns
          fish.targetHeading =
              fish.heading + (_random.nextDouble() * math.pi - math.pi / 2);
        } else if (fish.type == FishType.bubblefish) {
          // Bubblefish tend to make circular patterns
          fish.targetHeading =
              fish.heading + (_random.nextDouble() * math.pi / 2);
        } else if (fish.type == FishType.crab) {
          // Crabs tend to move sideways more
          final double sideChance = _random.nextDouble();
          if (sideChance < 0.6) {
            // 60% chance of turning perpendicular to current heading
            fish.targetHeading =
                fish.heading + (math.pi / 2 * (_random.nextBool() ? 1 : -1));
          } else {
            // 40% chance of normal direction change
            fish.targetHeading =
                fish.heading + (_random.nextDouble() * math.pi - math.pi / 2);
          }
        } else if (fish.type == FishType.shark) {
          // Sharks occasionally make sudden lunges in their current direction
          final double lungeChance = _random.nextDouble();
          if (lungeChance < 0.2) {
            // Increase speed temporarily without changing direction much
            fish.velocity = fish.velocity * 1.5;
            // Small direction change
            fish.targetHeading =
                fish.heading + (_random.nextDouble() * 0.4 - 0.2);
          } else {
            // Normal direction change
            fish.targetHeading = fish.heading +
                (_random.nextDouble() * math.pi / 2 - math.pi / 4);
          }
        } else {
          // Default fish behavior - smooth turns within a reasonable range
          // Higher difficulty = potentially wider turns
          final double turnRange =
              math.pi / 2 * (1.0 + (_fishEatenCount / 60).clamp(0.0, 1.0));
          fish.targetHeading =
              fish.heading + (_random.nextDouble() * turnRange - turnRange / 2);
        }

        // Normalize target heading to be between 0 and 2π
        while (fish.targetHeading < 0) {
          fish.targetHeading += math.pi * 2;
        }
        while (fish.targetHeading >= math.pi * 2) {
          fish.targetHeading -= math.pi * 2;
        }
      }

      // Gradually turn towards target heading
      // Calculate the shortest path to turn (clockwise or counter-clockwise)
      double headingDiff = fish.targetHeading - fish.heading;

      // Normalize the difference to be between -π and π
      if (headingDiff > math.pi) {
        headingDiff -= math.pi * 2;
      }
      if (headingDiff < -math.pi) {
        headingDiff += math.pi * 2;
      }

      // Apply turn rate limit
      final double turnAmount = headingDiff.abs() < fish.turnRate
          ? headingDiff // If we're close enough, just set it directly
          : fish.turnRate * headingDiff.sign; // Otherwise turn at max rate

      // Update heading
      fish.heading +=
          turnAmount * dt * 20; // Multiply by 20 to scale with 50ms dt

      // Normalize heading to be between 0 and 2π
      while (fish.heading < 0) {
        fish.heading += math.pi * 2;
      }
      while (fish.heading >= math.pi * 2) {
        fish.heading -= math.pi * 2;
      }

      // Update velocity based on heading
      final double speedMultiplier = fish.speedMultiplier;
      final double effectiveSpeed = fish.baseSpeed * speedMultiplier;

      // Update velocity based on the current heading
      fish.velocity = Offset(math.cos(fish.heading), math.sin(fish.heading)) *
          effectiveSpeed;

      // Move fish according to its velocity
      Offset newPos = fish.position + fish.velocity * dt;

      // Calculate bounce boundaries
      final double half = fish.size / 2;

      // Track if the fish bounced
      bool didBounce = false;

      // Bounce off left/right walls by flipping heading
      if (newPos.dx - half < 0) {
        newPos = Offset(half, newPos.dy);
        // Bounce by reflecting heading across vertical axis
        fish.heading = math.pi - fish.heading;
        fish.targetHeading = fish.heading; // Reset target to match new heading
        didBounce = true;
      } else if (newPos.dx + half > _gameSize.width) {
        newPos = Offset(_gameSize.width - half, newPos.dy);
        // Bounce by reflecting heading across vertical axis
        fish.heading = math.pi - fish.heading;
        fish.targetHeading = fish.heading; // Reset target to match new heading
        didBounce = true;
      }

      // Bounce off top/bottom walls by flipping heading
      if (newPos.dy - half < 0) {
        newPos = Offset(newPos.dx, half);
        // Bounce by reflecting heading across horizontal axis
        fish.heading = -fish.heading;
        fish.targetHeading = fish.heading; // Reset target to match new heading
        didBounce = true;
      } else if (newPos.dy + half > _gameSize.height) {
        newPos = Offset(newPos.dx, _gameSize.height - half);
        // Bounce by reflecting heading across horizontal axis
        fish.heading = -fish.heading;
        fish.targetHeading = fish.heading; // Reset target to match new heading
        didBounce = true;
      }

      // Normalize heading after bounces
      while (fish.heading < 0) {
        fish.heading += math.pi * 2;
      }
      while (fish.heading >= math.pi * 2) {
        fish.heading -= math.pi * 2;
      }

      // If fish bounced, apply a slight speed reduction
      if (didBounce) {
        // Apply slight damping on bounce (reduce speed by 5%)
        fish.baseSpeed *= 0.95;

        // Update velocity based on new heading after bounce
        fish.velocity = Offset(math.cos(fish.heading), math.sin(fish.heading)) *
            (fish.baseSpeed * fish.speedMultiplier);
      }

      // Add very subtle random movement perpendicular to direction
      // This creates a more organic swimming motion without chaotic path changes
      final double wiggleFactor =
          0.01 * (1.0 + (_fishEatenCount / 100).clamp(0.0, 1.0));
      final double perpAngle =
          fish.heading + math.pi / 2; // Perpendicular to swim direction
      final double lateralAmount =
          (math.sin(fish.wigglePhase) * fish.wiggleAmount) *
              fish.size *
              wiggleFactor; // Ties lateral motion to visual wiggle

      newPos += Offset(math.cos(perpAngle) * lateralAmount,
          math.sin(perpAngle) * lateralAmount);

      fish.position = newPos;

      // Update fish animation state (wiggle factor)
      fish.wigglePhase += dt * fish.wiggleSpeed;
      if (fish.wigglePhase > math.pi * 2) {
        fish.wigglePhase -= math.pi * 2; // Keep in 0 to 2π range
      }
    }

    // Update and remove expired catch effects
    _updateCatchEffects(0.05);
  }

  /// Moves each catch-effect text upward and fades it out over time.
  void _updateCatchEffects(double dt) {
    for (final _CatchEffect effect in _catchEffects) {
      effect.position =
          Offset(effect.position.dx, effect.position.dy - 20 * dt);
      effect.life -= dt;
    }
    _catchEffects.removeWhere((_CatchEffect e) => e.life <= 0);
  }

  /// Add a new floating text effect at the fish's position.
  void _createCatchEffect(_Fish fish) {
    // Format score text to include size information
    String text;

    if (fish.type == FishType.golden) {
      // Special text for golden fish
      text = 'Golden! +${fish.points}';
    } else {
      // For other fish, show points and size information
      // Format with size to 1 decimal place
      fish.size.toStringAsFixed(1);
      text = '+${fish.points}';
    }

    _catchEffects.add(_CatchEffect(
      text: text,
      position: fish.position,
      life: 1.0,
    ));
  }

  /// Change direction based on key or gesture input
  void _changeDirection(Direction newDirection) {
    // Prevent 180-degree turns (can't go directly opposite)
    if (_direction == Direction.up && newDirection == Direction.down) {
      return;
    }
    if (_direction == Direction.down && newDirection == Direction.up) {
      return;
    }
    if (_direction == Direction.left && newDirection == Direction.right) {
      return;
    }
    if (_direction == Direction.right && newDirection == Direction.left) {
      return;
    }

    _nextDirection = newDirection;
  }

  /// Process directional key input for desktop/keyboard control
  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final LogicalKeyboardKey key = event.logicalKey;

      if (key == LogicalKeyboardKey.arrowUp) {
        _changeDirection(Direction.up);
      } else if (key == LogicalKeyboardKey.arrowDown) {
        _changeDirection(Direction.down);
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        _changeDirection(Direction.left);
      } else if (key == LogicalKeyboardKey.arrowRight) {
        _changeDirection(Direction.right);
      }
    }
  }

  /// Adjust movement speed based on gesture velocity
  void _adjustSpeedFromGesture(Offset velocity) {
    // Calculate the magnitude of the gesture velocity
    final double speed = velocity.distance;

    // Map the gesture speed to movement distance, with upper and lower bounds
    // Speed mapping: faster gesture = faster cat movement, but with limits
    final double newSpeed = math.min(
        _maxMoveDistance,
        _minMoveDistance +
            (speed / 200) * (_maxMoveDistance - _minMoveDistance));

    // Update current move distance
    setState(() {
      _currentMoveDistance = newSpeed;
      _lastGestureTime = DateTime.now(); // Update last gesture time
    });
  }

  /// Trigger game over state with reason
  void _gameOver(String reason) {
    if (_isGameOver) {
      return;
    }
    setState(() {
      _isGameOver = true;
      _gameOverReason = reason;
      _stopMovementTimer();
      _gameTimer?.cancel();
    });
  }

  /// Reset game state for a new round.
  void _restartGame() {
    if (!mounted) {
      return;
    }
    setState(() {
      _score = 0;
      _timeLeft = 60;
      _isGameOver = false;
      _gameOverReason = '';
      _catLength = 3;
      _direction = Direction.right;
      _nextDirection = Direction.right;
      _currentMoveDistance = _baseMoveDistance;
      _fishEatenCount = 0;
      _fishRandomDirectionChance = 0.3;
      _fishDirectionChangeAmount = 0.4;

      _initializeGame();
      _catchEffects.clear();

      _startGameTimer();
      _startMovementTimer();

      widget.onScoreUpdate?.call(_score);
    });
  }

  // Display current speed indicator with smaller width

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: _handleKeyEvent,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Update game size if layout changes
          final Size newSize =
              Size(constraints.maxWidth, constraints.maxHeight);
          if (_gameSize != newSize) {
            _gameSize = newSize;
            if (_catSegments.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _initializeGame();
              });
            }
          }

          // Determine if we're on a mobile platform or desktop/web platform
          // For mobile platforms (iOS, Android), we use swipe gesture control
          // For desktop (macOS, Windows, Linux) and web platforms, we use tap control
          final bool isMobilePlatform =
              !kIsWeb && (Platform.isAndroid || Platform.isIOS);
          final bool isDesktopOrWebPlatform = kIsWeb ||
              Platform.isMacOS ||
              Platform.isWindows ||
              Platform.isLinux;

          return GestureDetector(
            // Enable swipe gesture controls only on mobile platforms
            onVerticalDragUpdate: isMobilePlatform
                ? (DragUpdateDetails details) {
                    // Determine direction
                    if (details.delta.dy < 0) {
                      _changeDirection(Direction.up);
                    } else {
                      _changeDirection(Direction.down);
                    }

                    // Adjust speed based on gesture velocity
                    _adjustSpeedFromGesture(details.primaryDelta != null
                        ? Offset(0, details.primaryDelta! * 10)
                        : Offset.zero);
                  }
                : null,
            onHorizontalDragUpdate: isMobilePlatform
                ? (DragUpdateDetails details) {
                    // Determine direction
                    if (details.delta.dx < 0) {
                      _changeDirection(Direction.left);
                    } else {
                      _changeDirection(Direction.right);
                    }

                    // Adjust speed based on gesture velocity
                    _adjustSpeedFromGesture(details.primaryDelta != null
                        ? Offset(details.primaryDelta! * 10, 0)
                        : Offset.zero);
                  }
                : null,
            // Enable tap control only on desktop and web platforms
            onTapDown: isDesktopOrWebPlatform
                ? (TapDownDetails details) {
                    if (_catSegments.isEmpty || _isGameOver) {
                      return;
                    }

                    // Get tap position and cat head position
                    final Offset tapPosition = details.localPosition;
                    final Offset headPosition = _catSegments.first;

                    // Calculate direction vector from head to tap position
                    final Offset direction = tapPosition - headPosition;

                    // Calculate distance for speed adjustment
                    final double distance = direction.distance;

                    // Determine primary direction (up, down, left, right)
                    // We compare the absolute values of x and y to determine if the movement is primarily horizontal or vertical
                    if (direction.dx.abs() > direction.dy.abs()) {
                      // Horizontal movement is primary
                      if (direction.dx > 0) {
                        _changeDirection(Direction.right);
                      } else {
                        _changeDirection(Direction.left);
                      }
                    } else {
                      // Vertical movement is primary
                      if (direction.dy > 0) {
                        _changeDirection(Direction.down);
                      } else {
                        _changeDirection(Direction.up);
                      }
                    }

                    // Adjust speed based on distance from head to tap position
                    // Map the distance to a speed value between min and max speed
                    // The normalization factor (150.0) controls how quickly speed increases with distance
                    // Clamping ensures the speed stays within allowed limits
                    final double speedFactor =
                        (distance / 150.0).clamp(0.2, 1.0);
                    final double newSpeed = _minMoveDistance +
                        speedFactor * (_maxMoveDistance - _minMoveDistance);

                    setState(() {
                      _currentMoveDistance = newSpeed;
                      _lastGestureTime =
                          DateTime.now(); // Update last gesture time
                    });
                  }
                : null,
            child: Stack(
              children: <Widget>[
                // Background water color
                Container(color: Colors.lightBlue.shade100),

                // Grid lines for visual reference (optional)
                CustomPaint(
                  size: Size.infinite,
                  painter: _GridPainter(),
                ),

                // Render all fish
                ..._fishes.map((_Fish fish) => Positioned(
                      left: fish.position.dx - fish.size / 2,
                      top: fish.position.dy - fish.size / 2,
                      child: Transform.rotate(
                        // Prevent fish from appearing upside-down by adjusting the angle
                        // We want fish to always have their back/top side facing upward
                        // First determine the base angle from heading (direction of movement)
                        angle: _calculateFishDisplayAngle(fish),
                        child: Text(
                          fish.emoji,
                          style: TextStyle(fontSize: fish.size),
                        ),
                      ),
                    )),

                // Cat chain segments
                ..._catSegments
                    .toList()
                    .asMap()
                    .entries
                    .map((MapEntry<int, Offset> entry) {
                  final int index = entry.key;
                  final Offset segment = entry.value;
                  final bool isHead = index == 0;

                  return Positioned(
                    left: segment.dx - _catSegmentSize / 2,
                    top: segment.dy - _catSegmentSize / 2,
                    child: Container(
                      width: _catSegmentSize,
                      height: _catSegmentSize,
                      decoration: BoxDecoration(
                        color: isHead
                            ? Colors.orange
                            : Colors.orange.withValues(
                                alpha: math.max(0.1, 0.8 - index * 0.01)),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.brown,
                          width: 2,
                        ),
                      ),
                      child: isHead
                          ? const Center(
                              child: Text(
                                '🐱',
                                style: TextStyle(fontSize: 14),
                              ),
                            )
                          : index % 3 == 0
                              ? const Center(
                                  child: Text(
                                    '🐾',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                )
                              : null,
                    ),
                  );
                }),

                // 计时器 - 左上角
                Positioned(
                  top: 10,
                  left: 10,
                  child: _buildInfoChip('⏱️ $_timeLeft'),
                ),

                // 鱼的数量 - 右上角
                Positioned(
                  top: 10,
                  right: 10,
                  child: _buildInfoChip('🐟 ${_catLength - 3}'),
                ),

                // Floating catch effects
                ..._catchEffects.map((_CatchEffect effect) {
                  final double alpha = (effect.life / 1.0).clamp(0.0, 1.0);
                  return Positioned(
                    left: effect.position.dx,
                    top: effect.position.dy,
                    child: Opacity(
                      opacity: alpha,
                      child: Text(
                        effect.text,
                        style: const TextStyle(
                          color: Colors.yellow,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          shadows: <Shadow>[
                            Shadow(blurRadius: 4.0, color: Colors.black26),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

                // Difficulty indicator in debug mode
                if (_isDebug)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.black.withValues(alpha: 0.5),
                      child: Text(
                        'Fish eaten: $_fishEatenCount\nDifficulty: ${(_fishEatenCount / 30).clamp(0.0, 1.0).toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),

                // Game Over overlay
                if (_isGameOver)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.7),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              S.of(context).gameOver,
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                shadows: <Shadow>[
                                  Shadow(
                                    blurRadius: 8.0,
                                    color: Colors.black.withValues(alpha: 0.5),
                                  )
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _gameOverReason,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${_catLength - 3} 🐟',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.lightBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 30, vertical: 15),
                                textStyle: const TextStyle(fontSize: 18),
                              ),
                              onPressed: _restartGame,
                              child: const Text('🔄'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Helper for creating the score/timer display
  Widget _buildInfoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: _messageColor,
          fontWeight: FontWeight.bold,
          fontSize: 16,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  /// Calculate the angle to display fish correctly
  double _calculateFishDisplayAngle(_Fish fish) {
    // First normalize the heading to be between 0 and 2π
    double baseAngle = fish.heading;
    while (baseAngle < 0) {
      baseAngle += math.pi * 2;
    }
    while (baseAngle >= math.pi * 2) {
      baseAngle -= math.pi * 2;
    }

    // Add wiggle effect for tail movement - this creates the swimming motion
    double finalAngle =
        baseAngle + math.sin(fish.wigglePhase) * fish.wiggleAmount;

    // Add π to make emoji face in the direction of movement (emojis typically face left by default)
    finalAngle += math.pi;

    // Now check if fish would appear upside down (back facing downward)
    // This happens when the heading is in the bottom half of the circle
    // We need to flip the fish horizontally when it's swimming downward to keep back upward

    // Check if fish is swimming downward (heading in bottom half of circle)
    final bool facingDownward =
        baseAngle > math.pi / 2 && baseAngle < math.pi * 3 / 2;

    if (facingDownward) {
      // Flip the fish horizontally to ensure back stays up
      // We do this by reflecting the angle across the vertical axis
      finalAngle = math.pi - (finalAngle - math.pi);

      // Ensure the angle stays within 0 to 2π
      while (finalAngle < 0) {
        finalAngle += math.pi * 2;
      }
      while (finalAngle >= math.pi * 2) {
        finalAngle -= math.pi * 2;
      }
    }

    return finalAngle;
  }
}

/// Internal Fish model with randomized properties and controlled speed.
class _Fish {
  _Fish({
    required this.position,
    required this.velocity,
    required this.size,
    required this.type,
    required this.emoji,
    required this.points,
    required this.speedMultiplier,
    required this.baseSpeed,
    required this.heading,
    required this.targetHeading,
    required this.headingChangeTimer,
    required this.headingChangeInterval,
    required this.turnRate,
    this.wigglePhase = 0.0,
    this.wiggleSpeed = 5.0,
    this.wiggleAmount = 0.2,
  });

  // How much the fish wiggles

  /// Create a fish with random properties, with much lower base speed.
  factory _Fish.random(math.Random rng, Size bounds) {
    final FishType type = _getRandomFishType(rng);

    double size, speedMultiplier;
    String emoji;
    int basePoints = 1; // Base points value before size adjustment

    // Base speed range significantly lowered: 5-15 px/sec
    final double baseSpeed = rng.nextDouble() * 10 + 10;

    switch (type) {
      case FishType.fast:
        size = rng.nextDouble() * 10 + 20; // 20–30 px
        emoji = '🐟';
        basePoints = 3; // Base points before size adjustment
        speedMultiplier = 1.2; // increased speed for fast fish
        break;
      case FishType.large:
        size = rng.nextDouble() * 20 + 40; // 40–60 px
        emoji = '🐡';
        basePoints = 7; // Base points before size adjustment
        speedMultiplier = 0.6; // slow but not too slow
        break;
      case FishType.golden:
        size = rng.nextDouble() * 10 + 30; // 30–40 px
        emoji = '🪙';
        basePoints = 9; // Golden fish have high base value
        speedMultiplier = 0.8; // medium speed
        break;
      case FishType.tiny:
        // Very small fish that are harder to catch but not worth many points
        size = rng.nextDouble() * 5 + 10; // 10–15 px (tiny)
        emoji = '🐡'; // Small puffer fish emoji
        basePoints = 2; // Base points before size adjustment
        speedMultiplier = 1.5; // very fast
        break;
      case FishType.jellyfish:
        // Unique movement pattern with more direction changes
        size = rng.nextDouble() * 15 + 25; // 25-40 px
        emoji = '🪼';
        basePoints = 5; // Base points before size adjustment
        speedMultiplier = 0.5; // slow but changes direction frequently
        break;
      case FishType.shark:
        // Larger, aggressive fish worth more points
        size = rng.nextDouble() * 25 + 45; // 45-70 px
        emoji = '🦈';
        basePoints = 8; // Base points before size adjustment
        speedMultiplier = 1.0; // moderate speed
        break;
      case FishType.bubblefish:
        // Fish that moves in bubble-like patterns
        size = rng.nextDouble() * 12 + 18; // 18-30 px
        emoji = '🫧';
        basePoints = 1; // Base points before size adjustment
        speedMultiplier = 0.7; // medium-slow
        break;
      case FishType.crab:
        // Moves sideways more than forward
        size = rng.nextDouble() * 15 + 20; // 20-35 px
        emoji = '🦀';
        basePoints = 4; // Base points before size adjustment
        speedMultiplier = 0.4; // slow but unpredictable
        break;
      case FishType.normal:
        size = rng.nextDouble() * 15 + 25; // 25–40 px
        emoji = '🐠';
        basePoints = 6; // Base points before size adjustment
        speedMultiplier = 0.9; // normal speed
        break;
    }

    // Calculate final points based on size
    // Points formula: base points + size-based bonus
    // Reference size for normalization is 25px (average fish size)
    final double sizeMultiplier = size / 25.0;
    final int sizeBonus = (sizeMultiplier * 2).floor();

    // Total points combines base value of fish type with size-based bonus
    final int points = basePoints + sizeBonus;

    // Spawn fully within bounds
    final Offset pos = Offset(
      rng.nextDouble() * (bounds.width - size) + size / 2,
      rng.nextDouble() * (bounds.height - size) + size / 2,
    );

    // Initialize heading properties
    final double initialHeading = rng.nextDouble() * 2 * math.pi;
    final double targetHeading = initialHeading;

    // Create initial velocity from heading
    final Offset vel =
        Offset(math.cos(initialHeading), math.sin(initialHeading)) * baseSpeed;

    // Set heading change parameters based on fish type
    double headingChangeInterval =
        3.0; // Default: change direction every 3 seconds
    double turnRate =
        0.05; // Default: maximum turn rate per update (in radians)

    // Customize heading change parameters by fish type
    switch (type) {
      case FishType.jellyfish:
        headingChangeInterval = 1.0; // Changes direction more frequently
        turnRate = 0.08; // Turns more sharply
        break;
      case FishType.bubblefish:
        headingChangeInterval = 1.5;
        turnRate = 0.04; // Gentle turns
        break;
      case FishType.crab:
        headingChangeInterval = 2.0;
        turnRate = 0.12; // Can make sharper turns
        break;
      case FishType.shark:
        headingChangeInterval = 4.0; // More persistence in direction
        turnRate = 0.03; // Slower to turn
        break;
      case FishType.fast:
        headingChangeInterval = 2.5;
        turnRate = 0.06;
        break;
      case FishType.normal:
      case FishType.large:
      case FishType.golden:
      case FishType.tiny:
        // Keep defaults for other types
        break;
    }

    // Randomize the initial timer value to avoid all fish changing direction at once
    final double headingChangeTimer = rng.nextDouble() * headingChangeInterval;

    // Randomize wiggle animation parameters
    final double wiggleSpeed = rng.nextDouble() * 2.0 + 1.5; // 1.5-3.5 rad/sec
    final double wiggleAmount =
        rng.nextDouble() * 0.15 + 0.05; // 0.05-0.2 wiggle amount (reduced)
    final double wigglePhase =
        rng.nextDouble() * math.pi * 2; // Random starting phase

    return _Fish(
      position: pos,
      velocity: vel,
      size: size,
      type: type,
      emoji: emoji,
      points: points,
      speedMultiplier: speedMultiplier,
      baseSpeed: baseSpeed,
      heading: initialHeading,
      targetHeading: targetHeading,
      headingChangeTimer: headingChangeTimer,
      headingChangeInterval: headingChangeInterval,
      turnRate: turnRate,
      wigglePhase: wigglePhase,
      wiggleSpeed: wiggleSpeed,
      wiggleAmount: wiggleAmount,
    );
  }

  Offset position;
  Offset velocity;
  double size;
  FishType type;
  String emoji;
  int points;
  double speedMultiplier;

  // New properties for heading-based movement
  double baseSpeed; // Base movement speed
  double heading; // Current heading in radians
  double targetHeading; // Target heading to turn towards
  double headingChangeTimer; // Timer to track when to change heading
  double headingChangeInterval; // How often to change heading (seconds)
  double turnRate; // Maximum turning rate per update (radians)

  // Properties for fish animation
  double wigglePhase; // Current phase of the wiggle animation
  double wiggleSpeed; // How fast the fish wiggles
  double wiggleAmount;

  /// Randomly choose fish type by weighted probability.
  static FishType _getRandomFishType(math.Random rng) {
    final double chance = rng.nextDouble();
    if (chance < 0.03) {
      return FishType.golden; // Rarest and most valuable fish
    } else if (chance < 0.07) {
      return FishType.shark;
    } else if (chance < 0.12) {
      return FishType.jellyfish;
    } else if (chance < 0.20) {
      return FishType.large;
    } else if (chance < 0.30) {
      return FishType.crab;
    } else if (chance < 0.40) {
      return FishType.bubblefish;
    } else if (chance < 0.55) {
      return FishType.fast;
    } else if (chance < 0.70) {
      return FishType.tiny;
    } else {
      return FishType.normal;
    }
  }

  /// Respawn fish with new random properties.
  void respawn(math.Random rng, Size bounds) {
    final _Fish newFish = _Fish.random(rng, bounds);
    position = newFish.position;
    velocity = newFish.velocity;
    size = newFish.size;
    type = newFish.type;
    emoji = newFish.emoji;
    points = newFish.points;
    speedMultiplier = newFish.speedMultiplier;
    baseSpeed = newFish.baseSpeed;
    heading = newFish.heading;
    targetHeading = newFish.targetHeading;
    headingChangeTimer = newFish.headingChangeTimer;
    headingChangeInterval = newFish.headingChangeInterval;
    turnRate = newFish.turnRate;
    wigglePhase = newFish.wigglePhase;
    wiggleSpeed = newFish.wiggleSpeed;
    wiggleAmount = newFish.wiggleAmount;
  }
}

/// Floating text effect for when a fish is caught.
class _CatchEffect {
  _CatchEffect({
    required this.text,
    required this.position,
    required this.life,
  });

  String text;
  Offset position;
  double life; // Remaining time in seconds
}

/// Grid painter for visual background reference
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 1;

    // Draw vertical lines
    for (double x = 0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw horizontal lines
    for (double y = 0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
