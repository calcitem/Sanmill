// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

/// A vertex on the board, in unit square coordinates (0,0)–(1,1).
@immutable
class BoardPoint {
  const BoardPoint({required this.id, required this.x, required this.y});

  final int id;
  final double x;
  final double y;
}

/// An undirected edge between two [BoardPoint.id] values.
///
/// [kindTag] mirrors `tgf_core::Edge::kind_tag` and lets games with
/// multi-modal connections (军棋: railroad vs ordinary edges, xiangqi:
/// river-crossing edges) classify their adjacency without parsing the
/// edge id.  Defaults to `0` for games whose edges are uniform.
@immutable
class BoardEdge {
  const BoardEdge(this.a, this.b, {this.kindTag = 0});

  final int a;
  final int b;
  final int kindTag;
}

enum BoardLayoutKind { graph, grid, region }

/// A named set of board points, such as a starting camp, target area, hand, or
/// scoring zone. Rendering remains module-owned; the platform only carries the
/// stable ids.
///
/// [role] mirrors `tgf_core::Zone::role` and points at one of the
/// canonical role tokens defined in `boardZoneRole` (`hand`, `goal`,
/// `home_base`, `camp`, `headquarters`, `railroad`, `river`, …).  An
/// empty string means the zone is not classified.
@immutable
class BoardZone {
  const BoardZone({
    required this.id,
    required this.pointIds,
    this.label,
    this.role = '',
  });

  final String id;
  final List<int> pointIds;
  final String? label;
  final String role;
}

/// Canonical role tokens shared with `tgf_core::board_topology::zone_role`.
///
/// Games may emit custom role strings; using these constants where
/// applicable lets cross-game tooling recognise common roles without
/// per-game branches.
class BoardZoneRole {
  const BoardZoneRole._();

  static const String none = '';
  static const String hand = 'hand';
  static const String capturePile = 'capture_pile';
  static const String promotion = 'promotion';
  static const String homeBase = 'home_base';
  static const String goal = 'goal';
  static const String camp = 'camp';
  static const String headquarters = 'headquarters';
  static const String railroad = 'railroad';
  static const String river = 'river';
}

/// Board topology for hit-testing, painting, and a11y.
///
/// Every board-game module should expose its own geometry so shared shell code
/// can reason about points without importing the game's position model. Mill
/// uses 24+ vertices; [demoProbe] uses a tiny toy graph.
@immutable
class BoardGeometry {
  const BoardGeometry({
    required this.points,
    required this.edges,
    this.kind = BoardLayoutKind.graph,
    this.zones = const <BoardZone>[],
  });

  final List<BoardPoint> points;
  final List<BoardEdge> edges;
  final BoardLayoutKind kind;
  final List<BoardZone> zones;

  /// Look up the [BoardEdge.kindTag] of the edge between [a] and [b],
  /// independent of orientation.  Returns `null` when the two points
  /// are not directly connected.  Useful for renderers that draw
  /// edges with different styles per kind (军棋: solid vs dashed).
  int? kindOfEdge(int a, int b) {
    for (final BoardEdge e in edges) {
      if ((e.a == a && e.b == b) || (e.a == b && e.b == a)) {
        return e.kindTag;
      }
    }
    return null;
  }

  /// Return the canonical [BoardZone.role] of the first zone that
  /// contains [pointId], or an empty string when no zone with a
  /// non-empty role applies.
  String zoneRoleAt(int pointId) {
    for (final BoardZone z in zones) {
      if (z.role.isEmpty) {
        continue;
      }
      if (z.pointIds.contains(pointId)) {
        return z.role;
      }
    }
    return BoardZoneRole.none;
  }
}
