// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

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
    _setupStatusListeners();
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
    final double totalDuration = DB().displaySettings.animationDuration * 1000;

    // Calculate pick-up and put-down durations to subtract from total
    final int pickUpDuration = (totalDuration * 0.2).toInt().clamp(100, 300);
    final int putDownDuration = (totalDuration * 0.2).toInt().clamp(100, 300);

    // Calculate move duration: Total - PickUp - PutDown
    // Ensure it has a reasonable minimum value (e.g., 40% of total or at least 100ms)
    // if the total duration is very short.
    int moveDuration = (totalDuration - pickUpDuration - putDownDuration)
        .toInt();

    if (moveDuration < totalDuration * 0.4) {
      moveDuration = (totalDuration * 0.4).toInt();
    }
    if (totalDuration > 0 && moveDuration < 50) {
      moveDuration = 50; // Minimum 50ms for move if total > 0
    }

    _moveAnimationController = AnimationController(
      vsync: vsync,
      duration: Duration(milliseconds: moveDuration),
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
  // Uses easeOutCubic curve for a smooth lifting effect
  void _initPickUpAnimation() {
    final double totalDuration = DB().displaySettings.animationDuration * 1000;

    // Calculate pick-up duration (approx 15-20% of total, clamped)
    final int pickUpDuration = (totalDuration * 0.2).toInt().clamp(100, 300);

    _pickUpAnimationController = AnimationController(
      vsync: vsync,
      duration: Duration(milliseconds: pickUpDuration),
    );

    _pickUpAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pickUpAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // Initialize Put-down Animation
  // Uses easeOutCubic curve for a smooth landing effect
  void _initPutDownAnimation() {
    final double totalDuration = DB().displaySettings.animationDuration * 1000;

    // Calculate put-down duration (approx 15-20% of total, clamped)
    final int putDownDuration = (totalDuration * 0.2).toInt().clamp(100, 300);

    _putDownAnimationController = AnimationController(
      vsync: vsync,
      duration: Duration(milliseconds: putDownDuration),
    );

    _putDownAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _putDownAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // Setup status listeners once during initialization to avoid memory leaks
  void _setupStatusListeners() {
    // Trigger put-down animation after place animation completes
    _placeAnimationController.addStatusListener(_onPlaceAnimationStatus);

    // Trigger put-down animation after move animation completes
    _moveAnimationController.addStatusListener(_onMoveAnimationStatus);

    // Clean up indices after remove animation completes
    _removeAnimationController.addStatusListener(_onRemoveAnimationStatus);
  }

  // Handler for place animation status changes
  void _onPlaceAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_isDisposed) {
      // Trigger put-down animation when piece arrives at destination
      if (DB().displaySettings.isPiecePickUpAnimationEnabled) {
        animatePutDown();
      }
    }
  }

  // Handler for move animation status changes
  void _onMoveAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_isDisposed) {
      // Trigger put-down animation when piece arrives at destination
      animatePutDown();
    }
  }

  // Handler for remove animation status changes
  void _onRemoveAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_isDisposed) {
      GameController().gameInstance.removeIndex = null;
      GameController().gameInstance.removePieceColor = null;
      GameController().gameInstance.removeByColor = null;
      // Reset move animation indices after custodian capture removal
      GameController().gameInstance.focusIndex = null;
      GameController().gameInstance.blurIndex = null;
    }
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
      forwardPlaceAnimation();
      // Note: Put-down animation is triggered automatically via status listener
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
      forwardMoveAnimation();
      // Note: Put-down animation is triggered automatically via status listener
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
      forwardRemoveAnimation();
      // Note: Index cleanup is handled automatically via status listener
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

  // Reverse the pick-up animation (animate piece going back down)
  // Called when a piece is deselected without being placed
  void reversePickUp() {
    if ( /* GameController().isDisposed == true || */ _isDisposed) {
      // Avoid animation when GameController or AnimationManager is disposed
      return;
    }

    if (allowAnimations &&
        _pickUpAnimationController.status != AnimationStatus.dismissed) {
      _pickUpAnimationController.reverse();
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
