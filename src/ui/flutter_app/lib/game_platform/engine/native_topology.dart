// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Phase 3 topology adapter: converts the Rust-native TGF topology blob into
// the existing Flutter BoardGeometry value object.

import '../../src/rust/api/simple.dart' as tgf;
import '../board_geometry.dart';

/// Converts Rust TGF topology data into the existing Flutter geometry model.
class NativeTopologyFactory {
  const NativeTopologyFactory();

  /// Fetch the standard Mill topology from Rust and convert it to BoardGeometry.
  ///
  /// The returned geometry intentionally keeps the same dense node ids (0..23)
  /// used by the legacy Mill UI, so current Flutter painters and hit testing
  /// can migrate without coordinate changes.
  BoardGeometry millBoardGeometry() {
    final tgf.TopologyBlob blob = tgf.kernelTopology();

    return BoardGeometry(
      points: blob.points
          .map((tgf.TopologyPoint p) => BoardPoint(id: p.id, x: p.x, y: p.y))
          .toList(growable: false),
      edges: blob.edges
          .map((tgf.TopologyEdge e) => BoardEdge(e.a, e.b))
          .toList(growable: false),
    );
  }
}
