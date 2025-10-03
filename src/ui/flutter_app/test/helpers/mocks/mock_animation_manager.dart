// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// mock_animation_manager.dart

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mockito/mockito.dart';
import 'package:sanmill/game_page/services/animation/animation_manager.dart';

/// Mock AnimationManager for testing
///
/// This mock provides a no-op implementation of AnimationManager
/// that doesn't require a real TickerProvider, making it suitable
/// for unit tests that don't have a widget tree.
class MockAnimationManager extends Mock implements AnimationManager {
  MockAnimationManager() {
    // Initialize mock animation controllers
    _placeAnimationController = _MockAnimationController();
    _moveAnimationController = _MockAnimationController();
    _removeAnimationController = _MockAnimationController();

    // Initialize mock animations
    _placeAnimation = const AlwaysStoppedAnimation<double>(0.0);
    _moveAnimation = const AlwaysStoppedAnimation<double>(0.0);
    _removeAnimation = const AlwaysStoppedAnimation<double>(0.0);
  }

  late final AnimationController _placeAnimationController;
  late final AnimationController _moveAnimationController;
  late final AnimationController _removeAnimationController;

  late final Animation<double> _placeAnimation;
  late final Animation<double> _moveAnimation;
  late final Animation<double> _removeAnimation;

  @override
  AnimationController get placeAnimationController => _placeAnimationController;

  @override
  Animation<double> get placeAnimation => _placeAnimation;

  @override
  AnimationController get moveAnimationController => _moveAnimationController;

  @override
  Animation<double> get moveAnimation => _moveAnimation;

  @override
  AnimationController get removeAnimationController =>
      _removeAnimationController;

  @override
  Animation<double> get removeAnimation => _removeAnimation;

  @override
  bool allowAnimations = false;

  @override
  void dispose() {
    // No-op for mock
  }

  @override
  void resetPlaceAnimation() {
    // No-op for mock
  }

  @override
  void forwardPlaceAnimation() {
    // No-op for mock
  }

  @override
  void resetMoveAnimation() {
    // No-op for mock
  }

  @override
  void forwardMoveAnimation() {
    // No-op for mock
  }

  @override
  void resetRemoveAnimation() {
    // No-op for mock
  }

  @override
  void forwardRemoveAnimation() {
    // No-op for mock
  }
}

/// Mock AnimationController that doesn't require a TickerProvider
class _MockAnimationController extends AnimationController {
  _MockAnimationController()
    : super(
        vsync: _MockTickerProvider(),
        duration: const Duration(milliseconds: 300),
      );
}

/// Mock TickerProvider for testing
class _MockTickerProvider implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) {
    return _MockTicker(onTick);
  }
}

/// Mock Ticker that doesn't actually tick
class _MockTicker extends Ticker {
  _MockTicker(super.onTick);
}
