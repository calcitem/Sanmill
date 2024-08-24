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

class AnimationManager {
  AnimationManager(this.vsync) {
    _initAnimation();
  }

  final TickerProvider vsync;

  late final AnimationController _animationController;
  late final Animation<double> _animation;

  AnimationController get animationController => _animationController;
  Animation<double> get animation => _animation;

  void _initAnimation() {
    // TODO: Check _initAnimation on branch master
    _animationController = AnimationController(
      vsync: vsync,
      duration: Duration(
        seconds: DB().displaySettings.animationDuration.toInt(),
      ),
    );

    _animation =
        Tween<double>(begin: 1.27, end: 1.0).animate(_animationController);
  }

  void dispose() {
    _animationController.dispose();
  }

  void resetAnimation() {
    _animationController.reset();
  }

  void forwardAnimation() {
    _animationController.forward();
  }

  void animateToEnd() {
    _animationController.animateTo(1.0);
  }
}
