/// Body fitting for the PCB assembly drawing.
///
/// Body sizes are estimated from package codes, so neighbouring parts can be
/// drawn on top of each other although they never touch on the real board.
/// [fitBodies] shrinks bodies proportionally around their unchanged centres
/// until parts on the same side no longer overlap. Estimated bodies shrink
/// before sizes read from a package code, larger before smaller. Bodies whose centres nearly
/// coincide are alternate footprints sharing one spot and are left alone.
library;

import 'dart:math' as math;

class BodyBox {
  const BodyBox({
    required this.x,
    required this.y,
    required this.rotation,
    required this.width,
    required this.height,
    required this.side,
    this.exact = false,
    this.solid = true,
  });

  final double x;
  final double y;

  /// Degrees, counter-clockwise.
  final double rotation;
  final double width;
  final double height;

  /// Parts only collide with parts of the same side.
  final int side;
  final bool exact;

  /// False for a footprint drawn empty (nothing placed): it makes way for
  /// placed parts and never pushes them aside.
  final bool solid;
}

/// Scale factors (width, height) per body; both are always equal, so a body
/// keeps its proportions and only gets smaller. Centres and rotations are
/// unchanged.
///
/// Every overlapping pair is separated along the axis needing the least
/// shrinking (separating axis test on the rotated rectangles). Afterwards
/// bodies of one package (same model and size) are brought to a common size,
/// the median of the group, so identical parts look identical; scales are
/// rounded down to steps of 5 %. Shrinking further never creates an overlap.
///
/// Bodies on a side listed in [yieldingSides] also make way for bodies of the
/// other side (the all-sides view, where the far side is drawn underneath);
/// in such a pair only the yielding body shrinks.
List<(double, double)> fitBodies(List<BodyBox> bodies, {double gap = 0.04, double minScale = 0.2, Set<int> yieldingSides = const {}}) {
  final n = bodies.length;
  final sc = List<double>.filled(n, 1);
  if (n < 2) return [for (var i = 0; i < n; i++) (1.0, 1.0)];
  final cos = List<double>.generate(n, (i) => math.cos(bodies[i].rotation * math.pi / 180));
  final sin = List<double>.generate(n, (i) => math.sin(bodies[i].rotation * math.pi / 180));
  // Axis-aligned half extents of the unscaled bodies (candidate search).
  final ex = List<double>.generate(n, (i) => (bodies[i].width * cos[i]).abs() / 2 + (bodies[i].height * sin[i]).abs() / 2);
  final ey = List<double>.generate(n, (i) => (bodies[i].width * sin[i]).abs() / 2 + (bodies[i].height * cos[i]).abs() / 2);

  // Sweep along X to collect the candidate pairs once.
  final order = List<int>.generate(n, (i) => i)..sort((a, b) => (bodies[a].x - ex[a]).compareTo(bodies[b].x - ex[b]));
  final pairs = <(int, int, bool)>[];
  bool yields(int i) => yieldingSides.contains(bodies[i].side);
  for (var k = 0; k < n; k++) {
    final a = order[k];
    final right = bodies[a].x + ex[a];
    for (var l = k + 1; l < n; l++) {
      final b = order[l];
      if (bodies[b].x - ex[b] > right) break;
      final cross = bodies[a].side != bodies[b].side;
      if (cross && !yields(a) && !yields(b)) continue;
      // An empty footprint on the near side does not push the far side away.
      if (cross && (!bodies[yields(a) ? b : a].solid)) continue;
      if ((bodies[a].y - bodies[b].y).abs() >= ey[a] + ey[b]) continue;
      // Alternate footprints sharing one spot: nothing to separate. Estimated
      // sizes say little, so they count as at most 0.5 mm wide here.
      double short(BodyBox e) => math.min(math.min(e.width, e.height), e.exact ? double.infinity : 0.5);
      final dist = math.sqrt(math.pow(bodies[a].x - bodies[b].x, 2) + math.pow(bodies[a].y - bodies[b].y, 2));
      final long = math.max(math.max(bodies[a].width, bodies[a].height), math.max(bodies[b].width, bodies[b].height));
      if (cross) {
        // Only a part right on top of another stays as it is.
        if (dist < 0.25 * math.min(math.min(bodies[a].width, bodies[a].height), math.min(bodies[b].width, bodies[b].height))) continue;
      } else if (dist < 0.6 * math.min(short(bodies[a]), short(bodies[b])) || dist < 0.12 * long) {
        continue;
      }
      pairs.add((a, b, cross));
    }
  }

  // Half extent of the unscaled body i projected on the unit axis (ux, uy).
  double reach(int i, double ux, double uy) =>
      (bodies[i].width / 2 * (ux * cos[i] + uy * sin[i])).abs() + (bodies[i].height / 2 * (-ux * sin[i] + uy * cos[i])).abs();

  // Shrinks body i by up to [need] along an axis where its full-size reach
  // is [r]; returns what could not be removed.
  double shrink(int i, double r, double need) {
    if (need <= 0 || r <= 0 || sc[i] <= minScale) return need;
    final cut = math.min(need, (sc[i] - minScale) * r);
    sc[i] -= cut / r;
    return need - cut;
  }

  double weight(int i) => bodies[i].width * bodies[i].height * sc[i] * sc[i] * (bodies[i].exact ? 0.25 : 1);

  for (var pass = 0; pass < 6; pass++) {
    var changed = false;
    for (final (a, b, cross) in pairs) {
      // Separating axis needing the least shrinking.
      final dx = bodies[b].x - bodies[a].x, dy = bodies[b].y - bodies[a].y;
      var best = (0.0, 0.0, 0.0);
      var bestT = -double.infinity;
      for (final (ux, uy) in [(cos[a], sin[a]), (-sin[a], cos[a]), (cos[b], sin[b]), (-sin[b], cos[b])]) {
        final d = (dx * ux + dy * uy).abs() - gap;
        final ra = reach(a, ux, uy), rb = reach(b, ux, uy);
        final t = d / (ra * sc[a] + rb * sc[b]);
        if (t > bestT) {
          bestT = t;
          best = (ra, rb, d);
        }
      }
      if (bestT >= 1 - 1e-9) continue;
      changed = true;
      final (ra, rb, d) = best;
      final over = ra * sc[a] + rb * sc[b] - math.max(d, 0);
      double r(int i) => i == a ? ra : rb;
      if (cross) {
        final y = yields(a) ? a : b;
        shrink(y, r(y), over);
        continue;
      }
      if (bodies[a].solid != bodies[b].solid) {
        final e = bodies[a].solid ? b : a;
        shrink(e, r(e), over);
        continue;
      }
      final (big, small) = weight(a) >= weight(b) ? (a, b) : (b, a);
      // A clearly bigger or estimated body gives way alone.
      if (weight(big) > 2 * weight(small)) {
        final rest = shrink(big, r(big), over);
        if (rest > 0) shrink(small, r(small), rest);
        continue;
      }
      // Similar bodies meet at one common scale, so a row of equal parts
      // comes out equal; one already smaller leaves the rest to the other.
      final common = math.max(math.max(d, 0) / (ra + rb), minScale);
      if (sc[a] > common && sc[b] > common) {
        sc[a] = common;
        sc[b] = common;
      } else {
        final (keep, give) = sc[a] <= sc[b] ? (a, b) : (b, a);
        final rest = shrink(give, r(give), over);
        if (rest > 0) shrink(keep, r(keep), rest);
      }
    }
    if (!changed) break;
  }

  // One size per package: the group's median scale caps every member.
  final groups = <(double, double, bool), List<int>>{};
  for (var i = 0; i < n; i++) {
    groups.putIfAbsent((bodies[i].width, bodies[i].height, bodies[i].solid), () => []).add(i);
  }
  for (final members in groups.values) {
    if (members.length < 3) continue;
    final sorted = [for (final i in members) sc[i]]..sort();
    final cap = sorted[sorted.length ~/ 2];
    for (final i in members) {
      sc[i] = math.min(sc[i], cap);
    }
  }
  return [
    for (var i = 0; i < n; i++)
      () {
        final q = sc[i] >= 1 ? 1.0 : math.max(minScale, (sc[i] * 20 + 1e-9).floorToDouble() / 20);
        return (q, q);
      }(),
  ];
}
