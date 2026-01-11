// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// headless_animation_manager.dart

import 'package:flutter/scheduler.dart';

import 'animation_manager.dart';

/// A minimal ticker that does nothing. Suitable for headless environments.
class _HeadlessTicker extends Ticker {
  _HeadlessTicker() : super((_) {});
}

/// A headless ticker provider that returns a no-op ticker.
class _HeadlessTickerProvider implements TickerProvider {
  const _HeadlessTickerProvider();

  @override
  Ticker createTicker(TickerCallback onTick) {
    return _HeadlessTicker();
  }
}

/// Headless-friendly AnimationManager that disables animations and
/// avoids needing any widget tree vsync.
class HeadlessAnimationManager extends AnimationManager {
  HeadlessAnimationManager() : super(const _HeadlessTickerProvider()) {
    // Disable animations completely to avoid scheduling frames.
    allowAnimations = false;
  }
}
