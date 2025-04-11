// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// animation_manager.dart

import 'package:flutter/material.dart';

import '../../../shared/database/database.dart';
import '../mill.dart';

class AnimationManager {
  AnimationManager(this.vsync) {
    _initPlaceAnimation();
    _initMoveAnimation();
    _initRemoveAnimation();
  }

  final TickerProvider vsync;
  bool _isDisposed = false; // Track whether dispose() was called

  bool allowAnimations = true;

  // Place Animation
  late final AnimationController _placeAnimationController;
  late final Animation<double> _placeAnimation;

  AnimationController get placeAnimationController => _placeAnimationController;
  Animation<double> get placeAnimation => _placeAnimation;

  // Move Animation
  late final AnimationController _moveAnimationController;
  late final Animation<double> _moveAnimation;

  AnimationController get moveAnimationController => _moveAnimationController;
  Animation<double> get moveAnimation => _moveAnimation;

  // Remove Animation
  late final AnimationController _removeAnimationController;
  late final Animation<double> _removeAnimation;

  AnimationController get removeAnimationController =>
      _removeAnimationController;
  Animation<double> get removeAnimation => _removeAnimation;

  // Initialize Place Animation
  void _initPlaceAnimation() {
    _placeAnimationController = AnimationController(
      vsync: vsync,
      duration: Duration(
        milliseconds: (DB().displaySettings.animationDuration * 1000).toInt(),
      ),
    );

    _placeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _placeAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // Initialize Move Animation
  void _initMoveAnimation() {
    _moveAnimationController = AnimationController(
      vsync: vsync,
      duration: Duration(
        milliseconds: (DB().displaySettings.animationDuration * 1000).toInt(),
      ),
    );

    _moveAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _moveAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // Initialize Remove Animation
  void _initRemoveAnimation() {
    _removeAnimationController = AnimationController(
      vsync: vsync,
      duration: Duration(
        milliseconds: (DB().displaySettings.animationDuration * 1000).toInt(),
      ),
    );

    _removeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _removeAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // Properly dispose of the animation controllers
  void dispose() {
    _isDisposed = true; // Mark as disposed
    _placeAnimationController.dispose();
    _moveAnimationController.dispose();
    _removeAnimationController.dispose();
  }

  // Reset Place Animation if not disposed
  void resetPlaceAnimation() {
    if (!_isDisposed) {
      _placeAnimationController.reset();
    }
  }

  // Start Place Animation if not disposed
  void forwardPlaceAnimation() {
    if (!_isDisposed) {
      _placeAnimationController.forward();
    }
  }

  // Reset Move Animation if not disposed
  void resetMoveAnimation() {
    if (!_isDisposed) {
      _moveAnimationController.reset();
    }
  }

  // Start Move Animation if not disposed
  void forwardMoveAnimation() {
    if (!_isDisposed) {
      _moveAnimationController.forward();
    }
  }

  // Reset Remove Animation if not disposed
  void resetRemoveAnimation() {
    if (!_isDisposed) {
      _removeAnimationController.reset();
    }
  }

  // Start Remove Animation if not disposed
  void forwardRemoveAnimation() {
    if (!_isDisposed) {
      _removeAnimationController.forward();
    }
  }

  // Check if Remove Animation is currently animating
  bool isRemoveAnimationAnimating() {
    return !_isDisposed && _removeAnimationController.isAnimating;
  }

  // Handle Place Animation with proper disposal check
  void animatePlace() {
    // TODO: See f0c1f3d5df544e5910b194b8479d956dd10fe527
    if (/* GameController().isDisposed == true || */ _isDisposed) {
      // Avoid animation when GameController or AnimationManager is disposed
      return;
    }

    if (allowAnimations) {
      resetPlaceAnimation();
      forwardPlaceAnimation();
    }
  }

  // Handle Move Animation with proper disposal check
  void animateMove() {
    if (/* GameController().isDisposed == true || */ _isDisposed) {
      // Avoid animation when GameController or AnimationManager is disposed
      return;
    }

    if (allowAnimations) {
      resetMoveAnimation();
      forwardMoveAnimation();
    }
  }

  // Handle Remove Animation with proper disposal check
  void animateRemove() {
    if (/* GameController().isDisposed == true || */ _isDisposed) {
      // Avoid animation when GameController or AnimationManager is disposed
      return;
    }

    if (allowAnimations) {
      resetRemoveAnimation();

      _removeAnimationController.addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          GameController().gameInstance.removeIndex = null;
        }
      });

      forwardRemoveAnimation();
    }
  }
}
