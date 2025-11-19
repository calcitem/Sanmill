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
    _initPickUpAnimation();
    _initPutDownAnimation();
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

  // Pick-up Animation (piece lift effect when selecting)
  late final AnimationController _pickUpAnimationController;
  late final Animation<double> _pickUpAnimation;

  AnimationController get pickUpAnimationController =>
      _pickUpAnimationController;
  Animation<double> get pickUpAnimation => _pickUpAnimation;

  // Put-down Animation (piece drop effect when placing)
  late final AnimationController _putDownAnimationController;
  late final Animation<double> _putDownAnimation;

  AnimationController get putDownAnimationController =>
      _putDownAnimationController;
  Animation<double> get putDownAnimation => _putDownAnimation;

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

  // Initialize Pick-up Animation
  // Uses easeOutBack curve for a slight overshoot effect when lifting
  void _initPickUpAnimation() {
    _pickUpAnimationController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 300),
    );

    _pickUpAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pickUpAnimationController,
        curve: Curves.easeOutBack,
      ),
    );
  }

  // Initialize Put-down Animation
  // Uses elasticOut curve for a bouncing landing effect
  void _initPutDownAnimation() {
    _putDownAnimationController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 400),
    );

    _putDownAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _putDownAnimationController,
        curve: Curves.elasticOut,
      ),
    );
  }

  // Properly dispose of the animation controllers
  void dispose() {
    _isDisposed = true; // Mark as disposed
    _placeAnimationController.dispose();
    _moveAnimationController.dispose();
    _removeAnimationController.dispose();
    _pickUpAnimationController.dispose();
    _putDownAnimationController.dispose();
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
    if ( /* GameController().isDisposed == true || */ _isDisposed) {
      // Avoid animation when GameController or AnimationManager is disposed
      return;
    }

    if (allowAnimations) {
      resetPlaceAnimation();

      // Trigger put-down animation when place animation completes
      _placeAnimationController.addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          animatePutDown();
        }
      });

      forwardPlaceAnimation();
    }
  }

  // Handle Move Animation with proper disposal check
  void animateMove() {
    if ( /* GameController().isDisposed == true || */ _isDisposed) {
      // Avoid animation when GameController or AnimationManager is disposed
      return;
    }

    if (allowAnimations) {
      resetMoveAnimation();

      // Trigger put-down animation when move animation completes
      _moveAnimationController.addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          animatePutDown();
        }
      });

      forwardMoveAnimation();
    }
  }

  // Handle Remove Animation with proper disposal check
  void animateRemove() {
    if ( /* GameController().isDisposed == true || */ _isDisposed) {
      // Avoid animation when GameController or AnimationManager is disposed
      return;
    }

    if (allowAnimations) {
      resetRemoveAnimation();

      _removeAnimationController.addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          GameController().gameInstance.removeIndex = null;
          // Reset move animation indices after custodian capture removal
          GameController().gameInstance.focusIndex = null;
          GameController().gameInstance.blurIndex = null;
        }
      });

      forwardRemoveAnimation();
    }
  }

  // Reset Pick-up Animation if not disposed
  void resetPickUpAnimation() {
    if (!_isDisposed) {
      _pickUpAnimationController.reset();
    }
  }

  // Start Pick-up Animation if not disposed
  void forwardPickUpAnimation() {
    if (!_isDisposed) {
      _pickUpAnimationController.forward();
    }
  }

  // Reset Put-down Animation if not disposed
  void resetPutDownAnimation() {
    if (!_isDisposed) {
      _putDownAnimationController.reset();
    }
  }

  // Start Put-down Animation if not disposed
  void forwardPutDownAnimation() {
    if (!_isDisposed) {
      _putDownAnimationController.forward();
    }
  }

  // Handle Pick-up Animation with proper disposal check
  // This animates the piece lifting effect when selected
  void animatePickUp() {
    if ( /* GameController().isDisposed == true || */ _isDisposed) {
      // Avoid animation when GameController or AnimationManager is disposed
      return;
    }

    if (allowAnimations) {
      resetPickUpAnimation();
      forwardPickUpAnimation();
    }
  }

  // Handle Put-down Animation with proper disposal check
  // This animates the piece landing effect when placed
  void animatePutDown() {
    if ( /* GameController().isDisposed == true || */ _isDisposed) {
      // Avoid animation when GameController or AnimationManager is disposed
      return;
    }

    if (allowAnimations) {
      resetPutDownAnimation();
      forwardPutDownAnimation();
    }
  }
}
