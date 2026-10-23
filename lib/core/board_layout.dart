/// Body fitting for the PCB assembly drawing.
///
/// Body sizes are estimated from package codes, so neighbouring parts can be
/// drawn on top of each other although they never touch on the real board.
/// [fitBodies] shrinks bodies around their unchanged centres until parts on
/// the same side no longer overlap. Estimated bodies shrink before sizes read
/// from a package code, larger before smaller. Bodies whose centres nearly
/// coincide are alternate footprints sharing one spot and are left alone.
library;

import 'dart:math' as math;

class BodyBox {
  const BodyBox({required this.x, required this.y, required this.rotation, required this.width, required this.height, required this.side, this.exact = false});

  final double x;
  final double y;

  /// Degrees, counter-clockwise.
  final double rotation;
  final double width;
  final double height;

  /// Parts only collide with parts of the same side.
  final int side;
  final bool exact;
}

/// Scale factors (width, height), each in (0, 1], per body; centres and
/// rotations are unchanged. A collision shrinks the dimension that faces the
/// neighbour first, so a row of long pads keeps its pads' width.
List<(double, double)> fitBodies(List<BodyBox> bodies, {double gap = 0.04, double minScale = 0.15}) {
  final n = bodies.length;
  final sw = List<double>.filled(n, 1), sh = List<double>.filled(n, 1);
  if (n < 2) return [for (var i = 0; i < n; i++) (1.0, 1.0)];
  final cos = List<double>.generate(n, (i) => math.cos(bodies[i].rotation * math.pi / 180));
  final sin = List<double>.generate(n, (i) => math.sin(bodies[i].rotation * math.pi / 180));
  // Axis-aligned half extents of the unscaled bodies (candidate search).
  final ex = List<double>.generate(n, (i) => (bodies[i].width * cos[i]).abs() / 2 + (bodies[i].height * sin[i]).abs() / 2);
  final ey = List<double>.generate(n, (i) => (bodies[i].width * sin[i]).abs() / 2 + (bodies[i].height * cos[i]).abs() / 2);

  // Sweep along X to collect the candidate pairs once.
  final order = List<int>.generate(n, (i) => i)..sort((a, b) => (bodies[a].x - ex[a]).compareTo(bodies[b].x - ex[b]));
  final pairs = <(int, int)>[];
  for (var k = 0; k < n; k++) {
    final a = order[k];
    final right = bodies[a].x + ex[a];
    for (var l = k + 1; l < n; l++) {
      final b = order[l];
      if (bodies[b].x - ex[b] > right) break;
      if (bodies[a].side != bodies[b].side) continue;
      if ((bodies[a].y - bodies[b].y).abs() >= ey[a] + ey[b]) continue;
      // Alternate footprints sharing one spot: nothing to separate. Estimated
      // sizes say little, so they count as at most 0.5 mm wide here.
      double short(BodyBox e) => math.min(math.min(e.width, e.height), e.exact ? double.infinity : 0.5);
      final dist = math.sqrt(math.pow(bodies[a].x - bodies[b].x, 2) + math.pow(bodies[a].y - bodies[b].y, 2));
      final long = math.max(math.max(bodies[a].width, bodies[a].height), math.max(bodies[b].width, bodies[b].height));
      if (dist < 0.6 * math.min(short(bodies[a]), short(bodies[b])) || dist < 0.12 * long) continue;
      pairs.add((a, b));
    }
  }

  // Width and height terms of body i projected on the unit axis (ux, uy).
  (double, double) terms(int i, double ux, double uy) =>
      ((bodies[i].width / 2 * sw[i] * (ux * cos[i] + uy * sin[i])).abs(), (bodies[i].height / 2 * sh[i] * (-ux * sin[i] + uy * cos[i])).abs());

  // Shrinks body i by up to [need] along the axis, larger term first;
  // returns what could not be removed.
  double shrink(int i, double ux, double uy, double need) {
    final (tw, th) = terms(i, ux, uy);
    for (final width in tw >= th ? [true, false] : [false, true]) {
      if (need <= 0) break;
      final term = width ? tw : th;
      final s = width ? sw[i] : sh[i];
      if (term <= 0 || s <= minScale) continue;
      final cut = math.min(need, term * (1 - minScale / s));
      final f = (term - cut) / term;
      if (width) {
        sw[i] *= f;
      } else {
        sh[i] *= f;
      }
      need -= cut;
    }
    return need;
  }

  double weight(int i) => bodies[i].width * bodies[i].height * sw[i] * sh[i] * (bodies[i].exact ? 0.25 : 1);

  for (var pass = 0; pass < 4; pass++) {
    var changed = false;
    for (final (a, b) in pairs) {
      // Separating axis needing the least shrinking.
      final dx = bodies[b].x - bodies[a].x, dy = bodies[b].y - bodies[a].y;
      var best = (0.0, 0.0, 0.0);
      var bestT = -double.infinity;
      for (final (ux, uy) in [(cos[a], sin[a]), (-sin[a], cos[a]), (cos[b], sin[b]), (-sin[b], cos[b])]) {
        final d = (dx * ux + dy * uy).abs() - gap;
        final (aw, ah) = terms(a, ux, uy);
        final (bw, bh) = terms(b, ux, uy);
        final t = d / (aw + ah + bw + bh);
        if (t > bestT) {
          bestT = t;
          best = (ux, uy, d);
        }
      }
      if (bestT >= 1 - 1e-9) continue;
      changed = true;
      final (ux, uy, d) = best;
      final (aw, ah) = terms(a, ux, uy);
      final (bw, bh) = terms(b, ux, uy);
      final over = aw + ah + bw + bh - math.max(d, 0);
      final (big, small) = weight(a) >= weight(b) ? (a, b) : (b, a);
      // A clearly bigger or estimated body gives way alone; similar ones share.
      final alone = weight(big) > 2 * weight(small);
      final first = shrink(big, ux, uy, alone ? over : over / 2);
      final rest = shrink(small, ux, uy, (alone ? 0 : over / 2) + first);
      if (rest > 0) shrink(big, ux, uy, rest);
    }
    if (!changed) break;
  }
  return [for (var i = 0; i < n; i++) (sw[i], sh[i])];
}
