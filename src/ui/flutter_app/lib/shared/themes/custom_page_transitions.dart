// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

/// A page transition that slides the new page in from the right,
/// but keeps the background page fixed (no parallax effect).
class SlideLeftFixedBackgroundPageTransitionsBuilder
    extends PageTransitionsBuilder {
  const SlideLeftFixedBackgroundPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Use a curve that mimics the native iOS slide
    const Curve curve = Curves.easeOutCubic;

    // Only animate the incoming page using 'animation'.
    // We ignore 'secondaryAnimation' to keep the background page fixed.
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: animation,
              curve: curve,
              reverseCurve: Curves.easeInCubic,
            ),
          ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(-2, 0),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}
