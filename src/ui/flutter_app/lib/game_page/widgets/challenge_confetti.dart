// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
// Enhanced by Gemini for realism and visual appeal
//
// Updated for smoother and more natural confetti effects

import 'dart:async';
import 'dart:math' as math;

// Using ui prefix to avoid conflicts
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'; // Import for TickerProvider

// Define different confetti shape types
enum ConfettiShape {
  rectangle,
  circle,
  triangle,
  star,
  streamer,
}

/// A widget that displays a highly customizable and visually enhanced confetti animation.
class ChallengeConfetti extends StatefulWidget {
  const ChallengeConfetti({
    super.key,
    this.particlesPerWave = 20, // Slightly increased default
    this.numberOfWaves = 4, // More waves for prolonged effect
    this.waveDelayMs = 250, // Shorter delay per wave
    this.emissionSource,
    this.initialBurstIntensity = 120.0, // Slightly lowered burst
    this.gravity = 160.0, // Reduced gravity for slower fall
    this.initialFallSpeedRange = 40.0, // Less initial downward push
    this.windStrength = 50.0, // Reduced wind for softer drift
    this.airResistance = 0.08, // Lowered for more float
    this.spinDamping = 0.98, // Spins last a bit longer
    this.flutterIntensity = 90.0, // Subtle increase for more flutter
    this.minParticleSize = 6.0,
    this.maxParticleSize = 14.0,
    this.allowedShapes = const <ConfettiShape>[
      ConfettiShape.rectangle,
      ConfettiShape.circle,
      ConfettiShape.triangle,
      ConfettiShape.star,
      ConfettiShape.streamer,
    ],
    this.confettiColors = _defaultColors,
    this.metallicProbability = 0.20, // Increased chance for metallic
    this.maxLifetimeMs = 7000, // Longer max lifetime
    this.minLifetimeMs = 3000, // Same min lifetime
  });

  // --- Configurable Parameters ---

  /// Number of confetti particles to launch per wave.
  final int particlesPerWave;

  /// Number of launch waves.
  final int numberOfWaves;

  /// Delay between launch waves in milliseconds (base value, with added randomness).
  final int waveDelayMs;

  /// Optional area from which confetti originates. Defaults to top center edge.
  final Rect? emissionSource;

  /// Intensity of the initial upward/outward burst. Higher values mean stronger burst.
  final double initialBurstIntensity;

  /// Base gravity acceleration affecting particles.
  final double gravity;

  /// Range of initial downward velocity added after the burst.
  final double initialFallSpeedRange;

  /// Base strength of the simulated wind force.
  final double windStrength;

  /// How quickly particles lose velocity due to air resistance (0.0 to 1.0).
  final double airResistance;

  /// How quickly particles lose rotational speed (0.0 to 1.0, closer to 1 means slower damping).
  final double spinDamping;

  /// Intensity of the fluttering/tumbling effect.
  final double flutterIntensity;

  /// Minimum size of confetti particles.
  final double minParticleSize;

  /// Maximum size of confetti particles.
  final double maxParticleSize;

  /// List of allowed confetti shapes.
  final List<ConfettiShape> allowedShapes;

  /// List of colors for the confetti particles.
  final List<Color> confettiColors;

  /// Probability (0.0 to 1.0) of a particle being metallic.
  final double metallicProbability;

  /// Maximum lifetime of a particle in milliseconds.
  final int maxLifetimeMs;

  /// Minimum lifetime of a particle in milliseconds.
  final int minLifetimeMs;

  // Default vibrant color palette
  static const List<Color> _defaultColors = <Color>[
    Color(0xFFFF4C40),
    Color(0xFF6347A6),
    Color(0xFF7FB13B),
    Color(0xFF82A0D1),
    Color(0xFFF7B3B2),
    Color(0xFF864542),
    Color(0xFFB04A98),
    Color(0xFF008F6C),
    Color(0xFFFFD033),
    Color(0xFFFF6F7C),
    Color(0xFF00BCD4),
    Color(0xFFFF9800),
    Color(0xFF4CAF50),
    Color(0xFF9C27B0),
    Color(0xFF3F51B5),
  ];

  // Default metallic color palette
  static const List<Color> _metallicColors = <Color>[
    Color(0xFFD4AF37), // Gold
    Color(0xFFA8A9AD), // Silver
    Color(0xFFCD7F32), // Bronze
    Color(0xFFE5E4E2), // Platinum-ish
  ];

  @override
  State<ChallengeConfetti> createState() => _ChallengeConfettiState();
}

class _ChallengeConfettiState extends State<ChallengeConfetti>
    with TickerProviderStateMixin {
  // Holds the confetti data and their state
  final List<ConfettiParticle> _particles = <ConfettiParticle>[];

  // A random generator for producing random values
  final math.Random _random = math.Random();

  // Ticker for driving the physics simulation
  late final Ticker _ticker;

  // Tracks the last timestamp for calculating delta time (dt)
  double _lastTimestamp = 0.0;

  // Tracks elapsed time for wind variation
  double _elapsedTime = 0.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();

    // Start confetti throw after the first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _startConfettiWaves();
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    // Dispose controllers held by particles
    for (final ConfettiParticle particle in _particles) {
      particle.controller.dispose();
    }
    _particles.clear();
    super.dispose();
  }

  /// Callback for the ticker, drives the physics simulation
  void _tick(Duration elapsed) {
    if (!mounted) {
      return;
    }

    final double now = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final double dt = (_lastTimestamp == 0.0)
        ? 0.016
        : now - _lastTimestamp; // Use an estimate for the first frame
    _lastTimestamp = now;
    _elapsedTime += dt;

    // Avoid large jumps or negative time steps
    if (dt <= 0 || dt > 0.1) {
      return;
    }

    final List<ConfettiParticle> particlesToRemove = <ConfettiParticle>[];
    final Size screenSize = MediaQuery.of(context).size;

    // Calculate current wind force (varies subtly over time)
    final double currentWind =
        widget.windStrength * (1 + 0.1 * math.sin(_elapsedTime * 1.5));

    for (final ConfettiParticle particle in _particles) {
      particle.update(dt, screenSize, currentWind, widget.gravity,
          widget.airResistance, widget.flutterIntensity, widget.spinDamping);
      if (particle.isOffScreen(screenSize) ||
          particle.controller.status == AnimationStatus.completed) {
        particlesToRemove.add(particle);
      }
    }

    if (particlesToRemove.isNotEmpty || _particles.isNotEmpty) {
      // Use addPostFrameCallback to avoid calling setState during build/layout/paint phase
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          for (final ConfettiParticle particle in particlesToRemove) {
            _particles.remove(particle);
            particle.controller.dispose(); // Dispose controller when removing
          }
        });
      });
    }
  }

  /// Starts launching multiple waves of confetti with a slight random delay per wave.
  void _startConfettiWaves() {
    for (int wave = 0; wave < widget.numberOfWaves; wave++) {
      // Add a small random factor to the wave delay to make the burst less uniform
      final int randomWaveDelay = widget.waveDelayMs +
          _random.nextInt((widget.waveDelayMs / 2).floor());
      Future<void>.delayed(Duration(milliseconds: randomWaveDelay * wave), () {
        if (!mounted) {
          return;
        }
        for (int i = 0; i < widget.particlesPerWave; i++) {
          _launchConfetti();
        }
      });
    }

    // Schedule a potential cleanup check far in the future, just in case
    final int totalDuration =
        widget.waveDelayMs * widget.numberOfWaves + widget.maxLifetimeMs + 1000;
    Future<void>.delayed(Duration(milliseconds: totalDuration), () {
      _cleanupLingeringParticles();
    });
  }

  /// Creates one confetti piece and adds it to the simulation.
  void _launchConfetti() {
    if (!mounted) {
      return;
    }

    final Size screenSize = MediaQuery.of(context).size;

    // Determine emission source properties
    final Rect source = widget.emissionSource ??
        Rect.fromCenter(
            center: Offset(screenSize.width / 2, -20),
            // Default: top center edge
            width: screenSize.width * 0.5,
            // Default width
            height: 40); // Default height (allows some vertical spread)

    // Start position within the source rectangle
    final double startX = source.left + _random.nextDouble() * source.width;
    final double startY = source.top + _random.nextDouble() * source.height;
    final Offset startPosition = Offset(startX, startY);

    // Initial velocity: Burst effect + random downward drift
    final double burstAngle =
        (_random.nextDouble() - 0.5) * math.pi * 0.8; // Spread angle
    final double burstSpeed =
        widget.initialBurstIntensity * (0.5 + _random.nextDouble() * 0.5);
    final double initialSpeedX = math.sin(burstAngle) * burstSpeed;
    final double initialSpeedY =
        -math.cos(burstAngle) * burstSpeed // Upward component
            +
            _random.nextDouble() * widget.initialFallSpeedRange;

    final Offset initialVelocity = Offset(initialSpeedX, initialSpeedY);

    // --- Particle Properties ---

    // Determine if metallic and pick color palette
    final bool isMetallic = _random.nextDouble() < widget.metallicProbability;
    final List<Color> colorPalette =
        isMetallic ? ChallengeConfetti._metallicColors : widget.confettiColors;
    Color color = colorPalette[_random.nextInt(colorPalette.length)];

    // Add slight random HSL variation to the base color for non-metallics
    if (!isMetallic) {
      final HSLColor hslColor = HSLColor.fromColor(color);
      // Vary Hue slightly (+/- 5 degrees), Saturation (+/- 0.05), Lightness (+/- 0.05)
      final double hueVariation = (_random.nextDouble() - 0.5) * 10.0;
      final double saturationVariation = (_random.nextDouble() - 0.5) * 0.1;
      final double lightnessVariation = (_random.nextDouble() - 0.5) * 0.1;
      color = hslColor
          .withHue((hslColor.hue + hueVariation) % 360.0)
          .withSaturation(
              (hslColor.saturation + saturationVariation).clamp(0.0, 1.0))
          .withLightness(
              (hslColor.lightness + lightnessVariation).clamp(0.0, 1.0))
          .toColor();
    }

    // Pick a random shape from the allowed list
    final ConfettiShape shape =
        widget.allowedShapes[_random.nextInt(widget.allowedShapes.length)];

    // Random size for the confetti
    final double size = _random.nextDouble() *
            (widget.maxParticleSize - widget.minParticleSize) +
        widget.minParticleSize;
    final double massFactor = (size / widget.maxParticleSize) * 0.5 +
        0.75; // Larger particles are slightly heavier (range 0.75 to 1.25)

    // Random initial rotation angle (3D orientation) and spin speed
    final double initialAngle = _random.nextDouble() * 2 * math.pi;
    final double initialSpin = (_random.nextDouble() * 4 - 2) * math.pi;

    // Random lifetime for the particle
    final int lifetimeMs =
        _random.nextInt(widget.maxLifetimeMs - widget.minLifetimeMs) +
            widget.minLifetimeMs;

    // Create animation controller for lifetime and fade effects
    final AnimationController controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: lifetimeMs),
    );

    // Create the particle
    final ConfettiParticle particle = ConfettiParticle(
      controller: controller,
      initialPosition: startPosition,
      initialVelocity: initialVelocity,
      color: color,
      isMetallic: isMetallic,
      size: size,
      massFactor: massFactor,
      initialAngle: initialAngle,
      initialSpin: initialSpin,
      shape: shape,
      random: _random,
    );

    // Use addPostFrameCallback to ensure setState is not called during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _particles.add(particle);
      });
    });

    // Start the controller (manages lifetime and fade)
    controller.forward();
  }

  /// Periodically clean up particles that might have stalled off-screen (fallback).
  void _cleanupLingeringParticles() {
    if (!mounted) {
      return;
    }
    final Size screenSize = MediaQuery.of(context).size;
    final List<ConfettiParticle> particlesToRemove = <ConfettiParticle>[];

    for (final ConfettiParticle particle in _particles) {
      // Check if particle is old, slow, and off-screen
      if (particle.timeAlive > 2.0 && // Existed for > 2 seconds
          particle.velocity.distanceSquared < 10.0 && // Moving very slowly
          particle.isOffScreen(screenSize)) {
        particlesToRemove.add(particle);
      }
    }

    if (particlesToRemove.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          for (final ConfettiParticle particle in particlesToRemove) {
            _particles.remove(particle);
            particle.controller.dispose();
          }
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // IgnorePointer allows user interactions to pass through the confetti layer
    return IgnorePointer(
      child: CustomPaint(
        painter: ConfettiPainter(
          particles: _particles,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Represents a single confetti particle with physics state and visual properties.
class ConfettiParticle {
  ConfettiParticle({
    required this.controller,
    required this.initialPosition,
    required this.initialVelocity,
    required this.color,
    required this.isMetallic,
    required this.size,
    required this.massFactor,
    required this.initialAngle,
    required this.initialSpin,
    required this.shape,
    required this.random,
  })  : currentPosition = initialPosition,
        velocity = initialVelocity,
        currentAngle = initialAngle,
        angularVelocity = initialSpin,
        _anglePhase = random.nextDouble() * 2 * math.pi;

  final AnimationController controller; // Controls lifetime and fade
  final Offset initialPosition;
  final Offset initialVelocity;
  final Color color;
  final bool isMetallic;
  final double size;

  /// Factor affecting gravity and resistance (simulates mass/density). Range ~0.75 to 1.25.
  final double massFactor;
  final double initialAngle;
  final double initialSpin;
  final ConfettiShape shape;
  final math.Random random;

  // Mutable state updated by physics simulation
  Offset currentPosition;
  Offset velocity;

  /// Represents the rotation around the particle's axis (for drawing).
  double currentAngle;

  /// Speed of rotation.
  double angularVelocity;

  /// Time elapsed since the particle was created.
  double timeAlive = 0.0;

  /// Used to offset the 3D rotation simulation for variety.
  final double _anglePhase;

  /// Represents the simulated tilt/rotation in 3D space (0=edge-on, 1=face-on).
  double scaleY = 1.0;

  /// Updates the particle's state based on physics simulation for a time step 'dt'.
  void update(double dt, Size screenSize, double windStrength, double gravity,
      double airResistance, double flutterIntensity, double spinDamping) {
    timeAlive += dt;

    // 1. Apply Gravity (affected by massFactor)
    velocity = velocity + Offset(0, gravity * massFactor * dt);

    // Simulated 3D rotation/tilt based on angular velocity and phase
    final double rotation3D = math.cos(currentAngle + _anglePhase + timeAlive);
    scaleY = math.cos(rotation3D * math.pi * 0.5).abs();
    // Smoothstep to make transitions less abrupt
    scaleY = scaleY * scaleY * (3.0 - 2.0 * scaleY);

    // 2. Apply Air Resistance (higher when face-on, lower when edge-on)
    final double resistanceFactor = 0.2 + 0.8 * scaleY;
    final double dragMagnitude = velocity.distanceSquared *
        airResistance *
        resistanceFactor /
        massFactor *
        dt;

    if (dragMagnitude > velocity.distance) {
      velocity = Offset.zero;
    } else if (velocity.distanceSquared > 0) {
      velocity = velocity -
          velocity.scale(dragMagnitude / velocity.distance,
              dragMagnitude / velocity.distance);
    }

    // 3. Apply Wind (less effect on heavier particles)
    final double windForce = windStrength / (massFactor * 1.5) * dt;
    velocity = velocity + Offset(windForce, 0);

    // 4. Apply Flutter (random sideways/vertical force)
    final double flutterFactor = (1.0 - scaleY) * flutterIntensity / massFactor;
    final double flutterX =
        (random.nextDouble() - 0.5) * 2 * flutterFactor * dt;
    final double flutterY =
        (random.nextDouble() - 0.5) * flutterFactor * 0.4 * dt;
    velocity = velocity + Offset(flutterX, flutterY);

    // 5. Update Position
    currentPosition = currentPosition + velocity * dt;

    // 6. Update Angular Velocity (damping)
    angularVelocity *= math.pow(spinDamping, dt).toDouble();

    // 7. Update Angle (visual rotation)
    currentAngle += angularVelocity * dt;
    currentAngle %= 2 * math.pi;
  }

  /// Calculates the current opacity based on the lifetime controller's value.
  double get currentOpacity {
    const double fadeInEnd = 0.15;
    const double fadeOutStart = 0.75;
    const double minEndOpacity = 0.15; // Minimum opacity at the end

    final double progress = controller.value;

    if (progress < fadeInEnd) {
      final double normalized = progress / fadeInEnd;
      return Curves.easeOutCubic.transform(normalized).clamp(0.0, 1.0);
    } else if (progress > fadeOutStart) {
      final double normalized =
          (progress - fadeOutStart) / (1.0 - fadeOutStart);
      final double eased = Curves.easeInCubic.transform(normalized);
      return (1.0 - eased)
          .clamp(minEndOpacity, 1.0); // Clamp to minimum opacity
    } else {
      return 1.0;
    }
  }

  /// Checks if the particle is significantly off-screen.
  bool isOffScreen(Size screenSize) {
    final double buffer = size * 8;
    return currentPosition.dy > screenSize.height + buffer ||
        currentPosition.dy < -buffer * 2 ||
        currentPosition.dx < -buffer ||
        currentPosition.dx > screenSize.width + buffer;
  }
}

/// A custom painter that draws all confetti particles with enhanced visuals.
class ConfettiPainter extends CustomPainter {
  ConfettiPainter({required this.particles})
      : super(
          repaint: Listenable.merge(
            particles.map((ConfettiParticle p) => p.controller).toList(),
          ),
        );

  final List<ConfettiParticle> particles;

  // Pre-computed metallic gradients (optional)
  final Map<Color, LinearGradient> _metallicGradients =
      <Color, LinearGradient>{};

  LinearGradient _createMetallicGradient(Color baseColor) {
    final HSLColor hsl = HSLColor.fromColor(baseColor);
    final Color lightColor =
        hsl.withLightness((hsl.lightness + 0.15).clamp(0.0, 1.0)).toColor();
    final Color darkColor =
        hsl.withLightness((hsl.lightness - 0.15).clamp(0.0, 1.0)).toColor();
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[lightColor, baseColor, darkColor],
      stops: const <double>[0.0, 0.5, 1.0],
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fillPaint = Paint()..style = PaintingStyle.fill;
    final Paint highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (final ConfettiParticle particle in particles) {
      final double opacity = particle.currentOpacity;
      if (opacity <= 0.0) {
        continue;
      }

      canvas.save();
      canvas.translate(
          particle.currentPosition.dx, particle.currentPosition.dy);
      canvas.rotate(particle.currentAngle);
      canvas.scale(1.0, particle.scaleY);

      final Color baseColor = particle.color;
      fillPaint.color = baseColor.withValues(alpha: opacity);

      // Metallic shader
      if (particle.isMetallic) {
        final LinearGradient gradient = _metallicGradients.putIfAbsent(
          baseColor,
          () => _createMetallicGradient(baseColor),
        );
        fillPaint.shader = gradient.createShader(
          Rect.fromCenter(
            center: Offset.zero,
            width: particle.size,
            height: particle.size,
          ),
        );
      } else {
        fillPaint.shader = null;
      }

      // Subtle highlight
      final double highlightVisibility = particle.scaleY * 0.8;
      final double highlightOpacity = (opacity *
              highlightVisibility *
              (1.0 - particle.controller.value * 0.6))
          .clamp(0.0, 0.5);
      highlightPaint.color = Colors.white.withValues(alpha: highlightOpacity);

      final double pSize = particle.size;
      switch (particle.shape) {
        case ConfettiShape.rectangle:
          _drawRectangle(canvas, pSize, fillPaint, highlightPaint);
          break;
        case ConfettiShape.circle:
          _drawCircle(canvas, pSize, fillPaint, highlightPaint);
          break;
        case ConfettiShape.triangle:
          _drawTriangle(canvas, pSize, fillPaint, highlightPaint);
          break;
        case ConfettiShape.star:
          _drawStar(canvas, pSize, fillPaint, highlightPaint);
          break;
        case ConfettiShape.streamer:
          _drawStreamer(canvas, pSize, fillPaint);
          break;
      }

      canvas.restore();
    }
  }

  // --- Shape Drawing Methods ---

  void _drawRectangle(
      Canvas canvas, double size, Paint paint, Paint highlightPaint) {
    final double width = size * 0.8;
    final double height = size * 1.2;
    final Rect rect =
        Rect.fromCenter(center: Offset.zero, width: width, height: height);
    canvas.drawRect(rect, paint);
    if (highlightPaint.color.a > 0) {
      final Rect highlightRect = Rect.fromCenter(
        center: Offset.zero,
        width: width * 0.5,
        height: height * 0.5,
      );
      canvas.drawRect(highlightRect, highlightPaint);
    }
  }

  void _drawCircle(
      Canvas canvas, double size, Paint paint, Paint highlightPaint) {
    final double radius = size / 2;
    canvas.drawCircle(Offset.zero, radius, paint);
    if (highlightPaint.color.a > 0) {
      canvas.drawCircle(
        Offset.zero,
        radius * 0.4,
        highlightPaint..style = PaintingStyle.fill,
      );
    }
  }

  void _drawTriangle(
      Canvas canvas, double size, Paint paint, Paint highlightPaint) {
    final Path path = Path();
    final double halfSize = size / 2;
    final double height = size * math.sqrt(3) / 2;
    path.moveTo(0, -height / 2);
    path.lineTo(-halfSize, height / 2);
    path.lineTo(halfSize, height / 2);
    path.close();
    canvas.drawPath(path, paint);
    if (highlightPaint.color.a > 0) {
      canvas.drawCircle(
        Offset(0, height * 0.1),
        size / 10,
        highlightPaint..style = PaintingStyle.fill,
      );
    }
  }

  void _drawStar(
      Canvas canvas, double size, Paint paint, Paint highlightPaint) {
    final Path path = Path();
    final double outerRadius = size / 2;
    final double innerRadius = size / 4.5;
    const int numPoints = 5;
    const double startAngleOffset = -math.pi / 2;

    for (int i = 0; i < numPoints * 2; i++) {
      final double radius = i.isEven ? outerRadius : innerRadius;
      final double angle = startAngleOffset + (i * math.pi) / numPoints;
      final double x = radius * math.cos(angle);
      final double y = radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
    if (highlightPaint.color.a > 0) {
      canvas.drawCircle(
        Offset(0, -size * 0.05),
        size / 10,
        highlightPaint..style = PaintingStyle.fill,
      );
    }
  }

  void _drawStreamer(Canvas canvas, double size, Paint paint) {
    final double width = size * 0.2;
    final double height = size * 3.0;
    final Rect rect =
        Rect.fromCenter(center: Offset.zero, width: width, height: height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2.0)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant ConfettiPainter oldDelegate) {
    return oldDelegate.particles != particles;
  }
}
