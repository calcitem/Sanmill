// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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

  void dispose() {
    _placeAnimationController.dispose();
    _moveAnimationController.dispose();
    _removeAnimationController.dispose();
  }

  void resetPlaceAnimation() {
    _placeAnimationController.reset();
  }

  void forwardPlaceAnimation() {
    _placeAnimationController.forward();
  }

  void resetMoveAnimation() {
    _moveAnimationController.reset();
  }

  void forwardMoveAnimation() {
    _moveAnimationController.forward();
  }

  void resetRemoveAnimation() {
    _removeAnimationController.reset();
  }

  void forwardRemoveAnimation() {
    _removeAnimationController.forward();
  }

  void animatePlace() {
    if (GameController().isDisposed == true) {
      // TODO: See f0c1f3d5df544e5910b194b8479d956dd10fe527
      //return;
    }

    if (allowAnimations) {
      resetPlaceAnimation();
      forwardPlaceAnimation();
    }
  }

  bool isRemoveAnimationAnimating() {
    if (_removeAnimationController.isAnimating) {
      return true;
    }
    return false;
  }

  void animateMove() {
    if (GameController().isDisposed == true) {
      // TODO: See f0c1f3d5df544e5910b194b8479d956dd10fe527
      //return;
    }

    if (allowAnimations) {
      resetMoveAnimation();
      forwardMoveAnimation();
    }
  }

  void animateRemove() {
    if (GameController().isDisposed == true) {
      // TODO: See f0c1f3d5df544e5910b194b8479d956dd10fe527
      //return;
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
