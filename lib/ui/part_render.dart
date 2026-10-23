/// Drawing of library part models (core/part_library.dart) for the PCB
/// navigator and the part library page. A part is built from leads on the
/// board surface, stacked body tiers (each with a top face and, in 3D, lit
/// side walls) and details printed or moulded on its top.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../core/footprints.dart';
import '../core/part_library.dart';

/// Board (mm, Y up, Z out of the board) → screen. An orthographic camera:
/// mirror, rotation about the board normal, then a tilt that tips the far
/// edge away from the viewer. Without tilt it is the plain top view.
class BoardProjection {
  BoardProjection(this.cx, this.cy, this.theta, this.mirror, this.pitch, this.scale, this.origin)
    : _cosT = math.cos(theta),
      _sinT = math.sin(theta),
      cosP = math.cos(pitch),
      sinP = math.sin(pitch);

  final double cx;
  final double cy;

  /// View rotation and tilt in radians.
  final double theta;
  final bool mirror;
  final double pitch;
  final double _cosT, _sinT;
  final double cosP, sinP;

  /// Pixels per mm.
  final double scale;

  /// Screen position of the board centre.
  final Offset origin;

  bool get tilted => pitch > 1e-4;

  /// Board-plane direction after mirror and rotation (X right, Y away).
  Offset plane(double x, double y) {
    final vx = mirror ? -x : x;
    return Offset(vx * _cosT - y * _sinT, vx * _sinT + y * _cosT);
  }

  Offset project(double x, double y, [double z = 0]) {
    final v = plane(x - cx, y - cy);
    return origin + Offset(v.dx * scale, -(v.dy * cosP + z * sinP) * scale);
  }

  /// Screen offset of a height [z] (mm) above the board.
  Offset lift(double z) => Offset(0, -z * sinP * scale);

  /// Larger is farther from the viewer.
  double depthOf(double x, double y) => plane(x - cx, y - cy).dy;

  /// Screen offset of a part-local vector (mm) for a part rotated [rotDeg].
  Offset localDelta(double rotDeg, double lx, double ly) {
    final v = localPlane(rotDeg, lx, ly);
    return Offset(v.dx * scale, -v.dy * cosP * scale);
  }

  /// Board-plane direction of a part-local vector, for face normals.
  Offset localPlane(double rotDeg, double lx, double ly) {
    final a = rotDeg * math.pi / 180;
    return plane(lx * math.cos(a) - ly * math.sin(a), lx * math.sin(a) + ly * math.cos(a));
  }

  /// Puts the canvas into the part's frame (mm, Y up) on the plane through
  /// [at], parallel to the board.
  void applyPart(Canvas canvas, Offset at, double rotDeg) {
    final ex = localDelta(rotDeg, 1, 0), ey = localDelta(rotDeg, 0, 1);
    canvas.translate(at.dx, at.dy);
    canvas.transform(Float64List.fromList([ex.dx, ex.dy, 0, 0, ey.dx, ey.dy, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
  }
}

/// Light direction in view space (X right, Y away, Z up): from the upper
/// left and slightly in front, so shadows fall back and to the right.
const lightDir = (-0.5, -0.3, 0.81);

/// Brightness of a face with view-space normal (nx, ny, nz) relative to a
/// top face.
double faceShade(double nx, double ny, double nz) {
  double k(double x, double y, double z) => 0.35 + 0.65 * math.max(0, x * lightDir.$1 + y * lightDir.$2 + z * lightDir.$3);
  return (k(nx, ny, nz) / k(0, 0, 1)).clamp(0.25, 1.0);
}

// Materials.
const _tin = Color(0xFFD5DAE0);
const _tinShade = Color(0xFF9AA2AB);
const _gold = Color(0xFFD9B35A);
const _copper = Color(0xFFC0844A);
const _wire = Color(0xFFB8763E);
const _silver = Color(0xFFC9CED4);
const _plastic = Color(0xFF1F2023);
const _beige = Color(0xFFE3D8BF);
const _white = Color(0xFFF1F0EC);
const _ceramic = Color(0xFFE8DCC4);
const _alumina = Color(0xFFE7E4DC);
const _ferrite = Color(0xFF2C2E31);
const _substrate = Color(0xFF2F4A35);
const _moduleBoard = Color(0xFF2D5E86);
const _phosphor = Color(0xFFF2DD7A);
const _hole = Color(0xFF15171A);

enum TierShape { rect, round, circle, frame }

/// One block of a body: [rect] in part coordinates (mm), from height [z0] to
/// [z1] (mm). [side] colours the walls when it differs from the top.
class Tier {
  const Tier(this.rect, this.z0, this.z1, this.color, {this.shape = TierShape.rect, this.radius = 0, this.side, this.frame = 0});

  final Rect rect;
  final double z0;
  final double z1;
  final Color color;
  final TierShape shape;
  final double radius;
  final Color? side;

  /// Ring width of a [TierShape.frame].
  final double frame;
}

/// Flat metal on the board or at a height: leads, pads, terminals.
class Lead {
  const Lead(this.rect, this.color, {this.z = 0, this.round = false});

  final Rect rect;
  final Color color;
  final double z;
  final bool round;
}

class PartBuild {
  PartBuild(this.leads, this.tiers, {this.decor, this.decorZ = 0});

  final List<Lead> leads;
  final List<Tier> tiers;

  /// Details on the top face at height [decorZ], drawn in part coordinates.
  final void Function(Canvas canvas, double px)? decor;
  final double decorZ;

  double get top => tiers.isEmpty ? 0 : tiers.map((t) => t.z1).reduce(math.max);
}

Color _dark(Color c, double t) => Color.lerp(c, const Color(0xFF000000), t)!;
Color _light(Color c, double t) => Color.lerp(c, const Color(0xFFFFFFFF), t)!;

/// Builds model [shape.model] at [shape]'s size with body colour [body].
/// [real] is true when the body colour is the part's own (real colours mode).
PartBuild buildPart(PartShape shape, Color body, {required bool real}) {
  final w = shape.width, h = shape.height;
  final hh = math.max(shape.bodyHeight, 0.0);
  final small = math.min(w, h);
  final mark = body.computeLuminance() > 0.45 ? const Color(0x55202226) : const Color(0x55F0F0F0);
  Rect r(double cx, double cy, double rw, double rh) => Rect.fromCenter(center: Offset(cx, cy), width: rw, height: rh);
  final full = r(0, 0, w, h);
  Paint fill(Color c) => Paint()..color = c;

  // Laser marking: short bars like printed text, in the lower part of the
  // top so the designator in the middle stays clear.
  void marking(Canvas c, double px, {int lines = 2, double scale = 1}) {
    if (small < 0.9) return;
    final lw = w * 0.36 * scale, lh = math.max(small * 0.045, px);
    for (var i = 0; i < lines; i++) {
      final y = -h * 0.3 + (i - (lines - 1) / 2) * small * 0.12 * scale;
      c.drawRRect(RRect.fromRectAndRadius(r(0, y, lw * (i.isOdd ? 0.7 : 1), lh), Radius.circular(lh / 2)), fill(mark));
    }
  }

  void pin1(Canvas c, double px, {double at = 0.15}) {
    final p = Offset(-w / 2 + small * at, h / 2 - small * at);
    c.drawCircle(p, small * 0.065, fill(_dark(body, 0.35)));
    c.drawCircle(
      p,
      small * 0.065,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = px
        ..color = _light(body, 0.3),
    );
  }

  // Two-tone gull-wing lead leaving the body edge at [from] along [dir].
  List<Lead> gull(Offset from, Offset dir, double length, double width) {
    final mid = from + dir * (length * 0.45), foot = from + dir * length;
    Rect span(Offset a, Offset b) => Rect.fromPoints(a + Offset(dir.dy, dir.dx) * (width / 2), b - Offset(dir.dy, dir.dx) * (width / 2));
    return [Lead(span(from, mid), _tinShade), Lead(span(mid, foot), _tin)];
  }

  // Leads along the ±Y edges (and ±X when [four]) of a w × h body.
  List<Lead> edgeLeads(int perSide, double length, {bool four = false, bool flat = false}) {
    final out = <Lead>[];
    final pitchX = w / (perSide + 1), pitchY = h / (perSide + 1);
    final lw = math.min(math.min(pitchX, four ? pitchY : pitchX) * 0.55, 0.45);
    for (var i = 1; i <= perSide; i++) {
      final x = -w / 2 + pitchX * i;
      for (final s in [1.0, -1.0]) {
        if (flat) {
          out.add(Lead(r(x, s * (h / 2 - length * 0.3), lw, length), _tin));
        } else {
          out.addAll(gull(Offset(x, s * h / 2), Offset(0, s), length, lw));
        }
      }
      if (four) {
        final y = -h / 2 + pitchY * i;
        for (final s in [1.0, -1.0]) {
          if (flat) {
            out.add(Lead(r(s * (w / 2 - length * 0.3), y, length, lw), _tin));
          } else {
            out.addAll(gull(Offset(s * w / 2, y), Offset(s, 0), length, lw));
          }
        }
      }
    }
    return out;
  }

  // Chip with metal end caps.
  PartBuild chip({Color caps = _tin, Color? side, void Function(Canvas, double)? decor, double cap = 0.2}) {
    final t = w * cap;
    return PartBuild(
      const [],
      [
        Tier(Rect.fromLTRB(-w / 2 + t, -h / 2, w / 2 - t, h / 2), 0, hh, body, side: side),
        Tier(Rect.fromLTRB(-w / 2, -h / 2, -w / 2 + t, h / 2), 0, hh * 1.03, caps, side: _dark(caps, 0.1)),
        Tier(Rect.fromLTRB(w / 2 - t, -h / 2, w / 2, h / 2), 0, hh * 1.03, caps, side: _dark(caps, 0.1)),
      ],
      decor: decor,
      decorZ: hh,
    );
  }

  final pins = shape.pins;
  switch (shape.model) {
    case 'chip_resistor':
      return chip(
        cap: 0.18,
        side: real ? _alumina : null,
        decor: (c, px) {
          // Printed value code: three digits.
          if (small < 0.45) return;
          for (var i = -1; i <= 1; i++) {
            c.drawRect(r(i * w * 0.13, -h * 0.18, w * 0.08, h * 0.3), fill(real ? const Color(0x99E8E8E8) : mark));
          }
        },
      );
    case 'thermistor' || 'varistor' || 'fuse' || 'mlcc' || 'chip_inductor' || 'bead':
      return chip(
        cap: shape.model == 'mlcc' ? 0.22 : 0.18,
        decor: shape.model == 'fuse' ? (c, px) => c.drawRect(r(0, 0, w * 0.32, h * 0.12), fill(const Color(0xFFC94A3A))) : null,
      );
    case 'antenna':
      return chip(caps: _silver, cap: 0.14, decor: (c, px) => c.drawRect(r(-w * 0.05, 0, w * 0.5, h * 0.08), fill(_silver)));
    case 'res_array':
      final n = math.max(2, (w / 0.5).round().clamp(2, 8));
      return PartBuild(
        const [],
        [
          Tier(full, 0, hh, body),
          for (var i = 0; i < n; i++)
            for (final s in [1.0, -1.0]) Tier(r(-w / 2 + w * (i + 0.5) / n, s * (h / 2 - h * 0.11), w / n * 0.55, h * 0.22), 0, hh * 1.02, _tin),
        ],
        decor: (c, px) => marking(c, px, lines: 1, scale: 0.8),
        decorZ: hh,
      );
    case 'melf' || 'diode_melf':
      final t = w * 0.16;
      final diode = shape.model == 'diode_melf';
      return PartBuild(
        const [],
        [
          Tier(Rect.fromLTRB(-w / 2 + t, -h / 2, w / 2 - t, h / 2), 0, hh, body, shape: TierShape.round, radius: h * 0.2),
          Tier(Rect.fromLTRB(-w / 2, -h / 2, -w / 2 + t, h / 2), 0, hh, _tin, shape: TierShape.round, radius: h * 0.2),
          Tier(Rect.fromLTRB(w / 2 - t, -h / 2, w / 2, h / 2), 0, hh, _tin, shape: TierShape.round, radius: h * 0.2),
        ],
        decor: (c, px) {
          final bands = diode ? [(-w * 0.2, _plastic)] : [(-w * 0.18, const Color(0xFFB04A2F)), (-w * 0.06, _plastic), (w * 0.06, const Color(0xFFD38B2C))];
          for (final (x, col) in bands) {
            c.drawRect(r(x, 0, w * 0.07, h), fill(col));
          }
        },
        decorZ: hh,
      );
    case 'tantalum' || 'polymer':
      return PartBuild(
        [
          Lead(Rect.fromLTRB(-w / 2 - w * 0.03, -h * 0.3, -w / 2 + w * 0.12, h * 0.3), _tin),
          Lead(Rect.fromLTRB(w / 2 - w * 0.12, -h * 0.3, w / 2 + w * 0.03, h * 0.3), _tin),
        ],
        [Tier(r(0, 0, w * 0.9, h), 0, hh, body)],
        decor: (c, px) {
          // Anode stripe.
          c.drawRect(r(-w * 0.32, 0, w * 0.1, h * 0.9), fill(shape.model == 'tantalum' && real ? const Color(0xFF8A5A1A) : _dark(body, 0.4)));
          marking(c, px, lines: 2, scale: 0.7);
        },
        decorZ: hh,
      );
    case 'elcap':
      final d = small * 0.94;
      return PartBuild(
        [Lead(r(-w / 2 - w * 0.06, 0, w * 0.2, h * 0.2), _tin), Lead(r(w / 2 + w * 0.06, 0, w * 0.2, h * 0.2), _tin)],
        [Tier(full, 0, hh * 0.12, _plastic), Tier(r(0, 0, d, d), hh * 0.12, hh, body, shape: TierShape.circle)],
        decor: (c, px) {
          // Negative-side marking and the vent cross.
          final rect = r(0, 0, d, d);
          c.drawArc(rect.deflate(px), math.pi * 0.62, math.pi * 0.76, true, fill(real ? _plastic : _dark(body, 0.5)));
          final vent = Paint()
            ..color = _dark(body, 0.28)
            ..strokeWidth = math.max(px, d * 0.02);
          c.drawLine(Offset(-d * 0.22, 0), Offset(d * 0.22, 0), vent);
          c.drawLine(Offset(0, -d * 0.22), Offset(0, d * 0.22), vent);
        },
        decorZ: hh,
      );
    case 'power_inductor':
      return PartBuild(
        [
          Lead(Rect.fromLTRB(-w / 2 - w * 0.02, -h * 0.36, -w / 2 + w * 0.18, h * 0.36), _copper),
          Lead(Rect.fromLTRB(w / 2 - w * 0.18, -h * 0.36, w / 2 + w * 0.02, h * 0.36), _copper),
        ],
        [Tier(full, 0, hh, body, shape: TierShape.round, radius: small * 0.1)],
        decor: (c, px) {
          marking(c, px, lines: 2, scale: 0.8);
          c.drawCircle(Offset(-w * 0.32, h * 0.3), small * 0.05, fill(mark));
        },
        decorZ: hh,
      );
    case 'drum_inductor':
      final d = small * 0.9;
      return PartBuild(
        [Lead(r(-w / 2 - w * 0.04, 0, w * 0.18, h * 0.3), _tin), Lead(r(w / 2 + w * 0.04, 0, w * 0.18, h * 0.3), _tin)],
        [
          Tier(full, 0, hh * 0.18, real ? _ferrite : _dark(body, 0.3), shape: TierShape.round, radius: small * 0.08),
          Tier(r(0, 0, d * 0.92, d * 0.92), hh * 0.18, hh * 0.84, _wire, shape: TierShape.circle),
          Tier(r(0, 0, d, d), hh * 0.84, hh, body, shape: TierShape.circle),
        ],
        decor: (c, px) => c.drawCircle(Offset.zero, d * 0.18, fill(_light(body, 0.12))),
        decorZ: hh,
      );
    case 'cm_choke':
      return PartBuild(
        [
          for (final sx in [-1.0, 1.0])
            for (final sy in [-1.0, 1.0]) Lead(r(sx * (w / 2 + w * 0.03), sy * h * 0.25, w * 0.12, h * 0.22), _tin),
        ],
        [Tier(full, 0, hh, body, shape: TierShape.round, radius: small * 0.06)],
        decor: (c, px) {
          pin1(c, px);
          marking(c, px, lines: 1, scale: 0.8);
        },
        decorZ: hh,
      );
    case 'transformer':
      return PartBuild(
        edgeLeads(4, h * 0.1),
        [Tier(full, 0, hh * 0.25, _beige), Tier(r(0, 0, w * 0.86, h * 0.7), hh * 0.25, hh, body)],
        decor: (c, px) => c.drawRect(r(0, 0, w * 0.86, math.max(px, h * 0.02)), fill(_dark(body, 0.4))),
        decorZ: hh,
      );
    case 'diode_sod' || 'diode_sma':
      final sma = shape.model == 'diode_sma';
      return PartBuild(
        [
          Lead(Rect.fromLTRB(-w / 2 - w * (sma ? 0.05 : 0.12), -h * (sma ? 0.32 : 0.22), -w / 2 + w * 0.06, h * (sma ? 0.32 : 0.22)), _tin),
          Lead(Rect.fromLTRB(w / 2 - w * 0.06, -h * (sma ? 0.32 : 0.22), w / 2 + w * (sma ? 0.05 : 0.12), h * (sma ? 0.32 : 0.22)), _tin),
        ],
        [Tier(full, 0, hh, body, shape: TierShape.round, radius: small * 0.06)],
        decor: (c, px) {
          c.drawRect(r(-w * 0.32, 0, w * 0.1, h * 0.94), fill(const Color(0xFFD9DCE0)));
          marking(c, px, lines: 1, scale: 0.6);
        },
        decorZ: hh,
      );
    case 'led_chip':
      final t = w * 0.16;
      return PartBuild(
        const [],
        [
          Tier(Rect.fromLTRB(-w / 2 + t, -h / 2, w / 2 - t, h / 2), 0, hh * 0.6, body),
          Tier(Rect.fromLTRB(-w / 2, -h / 2, -w / 2 + t, h / 2), 0, hh * 0.6, _tin),
          Tier(Rect.fromLTRB(w / 2 - t, -h / 2, w / 2, h / 2), 0, hh * 0.6, _tin),
          Tier(r(0, 0, w - 2 * t, h * 0.82), hh * 0.6, hh, _phosphor, side: _light(_phosphor, 0.3)),
        ],
        decor: (c, px) => c.drawPath(
          Path()..addPolygon([Offset(-w / 2 + t, h * 0.41), Offset(-w / 2 + t + h * 0.3, h * 0.41), Offset(-w / 2 + t, h * 0.1)], true),
          fill(const Color(0xFF3FA66A)),
        ),
        decorZ: hh,
      );
    case 'led_plcc':
      final per = w > 4.5 ? 3 : 2;
      return PartBuild(
        [
          for (var i = 0; i < per; i++)
            for (final s in [-1.0, 1.0]) Lead(r(s * (w / 2 + w * 0.02), -h / 2 + h * (i + 0.5) / per, w * 0.1, h / per * 0.55), _tin),
        ],
        [Tier(full, 0, hh, body)],
        decor: (c, px) {
          final d = small * 0.8;
          c.drawCircle(Offset.zero, d / 2, fill(_phosphor));
          c.drawCircle(
            Offset.zero,
            d / 2,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(px, d * 0.04)
              ..color = const Color(0xFFC9B24E),
          );
          c.drawPath(
            Path()..addPolygon([Offset(-w / 2, h / 2), Offset(-w / 2 + small * 0.22, h / 2), Offset(-w / 2, h / 2 - small * 0.22)], true),
            fill(_dark(body, 0.4)),
          );
        },
        decorZ: hh,
      );
    case 'sot23' || 'sot23_6':
      final lw = math.min(0.42, w * 0.15), ll = h * 0.45;
      final six = shape.model == 'sot23_6';
      return PartBuild(
        [
          for (final x in six ? [-w * 0.33, 0.0, w * 0.33] : [-w * 0.33, w * 0.33]) ...gull(Offset(x, -h / 2), const Offset(0, -1), ll, lw),
          for (final x in six ? [-w * 0.33, 0.0, w * 0.33] : [0.0]) ...gull(Offset(x, h / 2), const Offset(0, 1), ll, lw),
        ],
        [Tier(full, 0, hh, body, shape: TierShape.round, radius: small * 0.06)],
        decor: (c, px) {
          marking(c, px, lines: 1, scale: 0.7);
          if (six) pin1(c, px, at: 0.2);
        },
        decorZ: hh,
      );
    case 'sot89' || 'sot223':
      final lw = w * (shape.model == 'sot89' ? 0.1 : 0.11), ll = h * 0.3;
      return PartBuild(
        [
          for (final x in [-w * 0.33, 0.0, w * 0.33]) ...gull(Offset(x, -h / 2), const Offset(0, -1), ll, lw),
          ...gull(Offset(0, h / 2), const Offset(0, 1), ll * 0.8, w * 0.45),
        ],
        [Tier(full, 0, hh, body, shape: TierShape.round, radius: small * 0.04)],
        decor: (c, px) => marking(c, px, lines: 2, scale: 0.7),
        decorZ: hh,
      );
    case 'dpak' || 'd2pak':
      final front = h * 0.72;
      return PartBuild(
        [
          for (final x in shape.model == 'dpak' ? [-w * 0.3, w * 0.3] : [-w * 0.33, 0.0, w * 0.33])
            ...gull(Offset(x, -h / 2), const Offset(0, -1), h * 0.22, w * 0.1),
          Lead(Rect.fromLTRB(-w * 0.42, h / 2 - h * 0.3, w * 0.42, h / 2 + h * 0.04), _tin),
        ],
        [Tier(Rect.fromLTRB(-w / 2, -h / 2, w / 2, -h / 2 + front), 0, hh, body)],
        decor: (c, px) => marking(c, px, lines: 2, scale: 0.7),
        decorZ: hh,
      );
    case 'power_dfn':
      return PartBuild(
        [
          for (final x in [-0.375, -0.125, 0.125, 0.375]) Lead(r(x * w * 1.6 / 1.6, -h / 2, w * 0.12, h * 0.1), _tin),
          Lead(r(0, h / 2, w * 0.85, h * 0.1), _tin),
        ],
        [Tier(full, 0, hh, body)],
        decor: (c, px) {
          pin1(c, px);
          marking(c, px, lines: 2, scale: 0.7);
        },
        decorZ: hh,
      );
    case 'soic':
      final n = pins > 0 ? pins : math.max(3, ((w - 0.4) / 1.27).round());
      return PartBuild(
        edgeLeads(n, h * 0.27),
        [
          Tier(full, 0, hh * 0.45, body, shape: TierShape.round, radius: small * 0.03),
          Tier(r(0, 0, w * 0.97, h * 0.94), hh * 0.45, hh, body, shape: TierShape.round, radius: small * 0.03),
        ],
        decor: (c, px) {
          pin1(c, px, at: 0.18);
          marking(c, px, lines: 2);
        },
        decorZ: hh,
      );
    case 'qfp':
      final n = pins > 0 ? pins : math.max(4, ((w - 1) / 0.5).round().clamp(4, 36));
      return PartBuild(
        edgeLeads(n, w * 0.12, four: true),
        [Tier(full, 0, hh, body, shape: TierShape.round, radius: small * 0.02)],
        decor: (c, px) {
          pin1(c, px, at: 0.12);
          c.drawCircle(Offset(w * 0.3, -h * 0.3), small * 0.08, fill(_light(body, 0.05)));
          marking(c, px, lines: 3, scale: 0.9);
        },
        decorZ: hh,
      );
    case 'qfn':
      final square = (w - h).abs() < 0.2;
      final n = pins > 0 ? pins : math.max(2, (w / 0.5).floor() - 1);
      return PartBuild(
        edgeLeads(n, small * 0.1, four: square, flat: true),
        [Tier(full, 0, hh, body)],
        decor: (c, px) {
          pin1(c, px, at: 0.14);
          marking(c, px, lines: 2, scale: 0.8);
        },
        decorZ: hh,
      );
    case 'bga':
      return PartBuild(
        const [],
        [Tier(full, 0, hh * 0.3, _substrate), Tier(full.deflate(small * 0.04), hh * 0.3, hh, body, shape: TierShape.round, radius: small * 0.015)],
        decor: (c, px) {
          c.drawPath(
            Path()..addPolygon([Offset(-w / 2, h / 2), Offset(-w / 2 + small * 0.08, h / 2), Offset(-w / 2, h / 2 - small * 0.08)], true),
            fill(_gold),
          );
          pin1(c, px, at: 0.1);
          marking(c, px, lines: 3, scale: 0.9);
        },
        decorZ: hh,
      );
    case 'wlcsp':
      return PartBuild(
        const [],
        [Tier(full, 0, hh, body)],
        decor: (c, px) {
          c.drawRect(full.deflate(small * 0.08), fill(_light(body, 0.06)));
          pin1(c, px, at: 0.16);
        },
        decorZ: hh,
      );
    case 'module':
      final pads = math.max(4, (w / 1.5).round());
      return PartBuild(
        [
          for (var i = 0; i < pads; i++)
            for (final s in [1.0, -1.0]) Lead(r(-w / 2 + w * (i + 0.5) / pads, s * h / 2, w / pads * 0.45, small * 0.06), _gold),
        ],
        [
          Tier(full, 0, hh * 0.3, real ? _moduleBoard : _dark(body, 0.4)),
          Tier(full.deflate(small * 0.05), hh * 0.3, hh, body, shape: TierShape.round, radius: small * 0.02),
        ],
        decor: (c, px) {
          c.drawRect(r(-w * 0.08, h * 0.05, w * 0.55, h * 0.45), fill(const Color(0xFFF4F3EF)));
          marking(c, px, lines: 2, scale: 0.5);
          pin1(c, px, at: 0.1);
        },
        decorZ: hh,
      );
    case 'crystal_smd' || 'oscillator':
      final pw = w * 0.24, ph = h * 0.3;
      return PartBuild(
        [
          for (final (sx, sy) in [(-1, -1), (1, -1), (1, 1), (-1, 1)]) Lead(r(sx * (w / 2 - pw * 0.35), sy * (h / 2 - ph * 0.35), pw, ph), _tin),
        ],
        [Tier(full, 0, hh * 0.45, _ceramic), Tier(full.deflate(small * 0.08), hh * 0.45, hh, body, shape: TierShape.round, radius: small * 0.1)],
        decor: (c, px) {
          c.drawRRect(
            RRect.fromRectAndRadius(full.deflate(small * 0.14), Radius.circular(small * 0.08)),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = px
              ..color = _light(body, 0.35),
          );
          if (shape.model == 'oscillator') pin1(c, px, at: 0.22);
          marking(c, px, lines: 2, scale: 0.6);
        },
        decorZ: hh,
      );
    case 'hc49':
      return PartBuild(
        [Lead(r(-w / 2 - w * 0.03, 0, w * 0.1, h * 0.35), _tin), Lead(r(w / 2 + w * 0.03, 0, w * 0.1, h * 0.35), _tin)],
        [Tier(full, 0, hh * 0.15, _plastic), Tier(r(0, 0, w * 0.96, h * 0.88), hh * 0.15, hh, body, shape: TierShape.round, radius: h * 0.4)],
        decor: (c, px) => c.drawRect(r(0, h * 0.18, w * 0.7, math.max(px, h * 0.04)), fill(_light(body, 0.35))),
        decorZ: hh,
      );
    case 'fpc':
      final n = ((w - 2) / 0.5).round().clamp(4, 60);
      return PartBuild(
        [
          for (var i = 0; i < n; i++) Lead(r(-w / 2 + 1 + (w - 2) * (i + 0.5) / n, -h / 2 - h * 0.04, (w - 2) / n * 0.5, h * 0.18), _gold),
          Lead(r(-w / 2 + 0.35, -h * 0.15, 0.6, h * 0.5), _tin),
          Lead(r(w / 2 - 0.35, -h * 0.15, 0.6, h * 0.5), _tin),
        ],
        [
          Tier(Rect.fromLTRB(-w / 2, -h / 2, w / 2, h * 0.2), 0, hh * 0.8, body),
          Tier(Rect.fromLTRB(-w / 2 + 0.1, h * 0.2, w / 2 - 0.1, h / 2), 0, hh, _plastic),
        ],
        decor: (c, px) {
          for (var i = 0; i < n; i++) {
            c.drawRect(r(-w / 2 + 1 + (w - 2) * (i + 0.5) / n, -h * 0.2, (w - 2) / n * 0.4, h * 0.3), fill(_dark(body, 0.25)));
          }
        },
        decorZ: hh * 0.8,
      );
    case 'btb':
      final n = ((w - 1.2) / 0.4).round().clamp(4, 80);
      return PartBuild(
        [
          for (var i = 0; i < n; i++)
            for (final s in [1.0, -1.0]) Lead(r(-w / 2 + 0.6 + (w - 1.2) * (i + 0.5) / n, s * (h / 2 + h * 0.03), (w - 1.2) / n * 0.5, h * 0.14), _gold),
          Lead(r(-w / 2, 0, w * 0.06, h * 0.7), _tin),
          Lead(r(w / 2, 0, w * 0.06, h * 0.7), _tin),
        ],
        [Tier(full, 0, hh, body)],
        decor: (c, px) {
          c.drawRect(r(0, 0, w * 0.86, h * 0.5), fill(_dark(body, 0.35)));
          c.drawRect(r(0, 0, w * 0.82, h * 0.16), fill(body));
          for (var i = 0; i < n; i++) {
            for (final s in [1.0, -1.0]) {
              c.drawRect(r(-w / 2 + 0.6 + (w - 1.2) * (i + 0.5) / n, s * h * 0.16, (w - 1.2) / n * 0.45, h * 0.1), fill(_gold));
            }
          }
        },
        decorZ: hh,
      );
    case 'wire_to_board':
      final n = ((w - 2) / 1.25).round().clamp(2, 40);
      return PartBuild(
        [
          for (var i = 0; i < n; i++) Lead(r(-w / 2 + 1 + (w - 2) * (i + 0.5) / n, -h / 2 - h * 0.05, (w - 2) / n * 0.35, h * 0.16), _tin),
          Lead(r(-w / 2 - w * 0.02, h * 0.2, w * 0.08, h * 0.35), _tin),
          Lead(r(w / 2 + w * 0.02, h * 0.2, w * 0.08, h * 0.35), _tin),
        ],
        [Tier(full, 0, hh, body)],
        decor: (c, px) {
          c.drawRect(r(0, h * 0.08, w * 0.88, h * 0.55), fill(_dark(body, 0.2)));
          for (var i = 0; i < n; i++) {
            c.drawRect(r(-w / 2 + 1 + (w - 2) * (i + 0.5) / n, h * 0.08, (w - 2) / n * 0.3, h * 0.22), fill(_gold));
          }
        },
        decorZ: hh,
      );
    case 'pin_header':
      final rows = h > 3.6 ? 2 : 1;
      final cols = math.max(1, (w / 2.54).round());
      return PartBuild(const [], [
        Tier(full, 0, hh, body),
        for (var i = 0; i < cols; i++)
          for (var j = 0; j < rows; j++) Tier(r(-w / 2 + w * (i + 0.5) / cols, -h / 2 + h * (j + 0.5) / rows, 0.64, 0.64), hh, hh + 1.5, _gold),
      ]);
    case 'usb_c' || 'micro_usb' || 'usb_a':
      final legs = [
        for (final sx in [-1.0, 1.0])
          for (final sy in [-0.25, 0.3]) Lead(r(sx * (w / 2 + w * 0.04), sy * h, w * 0.1, h * 0.12), _tin),
      ];
      final signals = shape.model == 'usb_c' ? 12 : (shape.model == 'micro_usb' ? 5 : 4);
      return PartBuild(
        [
          ...legs,
          for (var i = 0; i < signals; i++) Lead(r(-w * 0.3 + w * 0.6 * (i + 0.5) / signals, h / 2 + h * 0.04, w * 0.6 / signals * 0.45, h * 0.12), _tin),
        ],
        [Tier(full, 0, hh, body, shape: TierShape.round, radius: shape.model == 'usb_c' ? small * 0.12 : small * 0.03)],
        decor: (c, px) {
          final opening = shape.model == 'usb_a' ? r(0, -h / 2 + h * 0.06, w * 0.82, h * 0.08) : r(0, -h / 2 + h * 0.07, w * 0.7, h * 0.1);
          c.drawRRect(RRect.fromRectAndRadius(opening, Radius.circular(opening.height / 2)), fill(_hole));
          c.drawRect(r(0, h * 0.05, w * 0.82, math.max(px, h * 0.015)), fill(_dark(body, 0.2)));
          if (shape.model == 'usb_a') {
            for (final x in [-w * 0.2, w * 0.2]) {
              c.drawRect(r(x, h * 0.2, w * 0.12, h * 0.1), fill(_hole));
            }
          }
        },
        decorZ: hh,
      );
    case 'sim' || 'sd_card':
      final n = shape.model == 'sim' ? 6 : 8;
      return PartBuild(
        [
          for (final sx in [-1.0, 1.0])
            for (final sy in [-0.35, 0.35]) Lead(r(sx * (w / 2 + w * 0.02), sy * h, w * 0.06, h * 0.08), _tin),
        ],
        [Tier(full, 0, hh, body, side: _dark(body, 0.1))],
        decor: (c, px) {
          c.drawRect(r(0, -h * 0.05, w * 0.8, h * 0.7), fill(_dark(body, 0.12)));
          for (var i = 0; i < n; i++) {
            c.drawRect(r(-w * 0.3 + w * 0.6 * (i + 0.5) / n, -h * 0.05, w * 0.6 / n * 0.4, h * 0.4), fill(_gold));
          }
          c.drawRect(r(0, -h / 2 + h * 0.04, w * 0.9, math.max(px, h * 0.02)), fill(_hole));
        },
        decorZ: hh,
      );
    case 'rj45':
      return PartBuild(
        [
          for (final sx in [-1.0, 1.0]) Lead(r(sx * (w / 2 + w * 0.03), 0, w * 0.08, h * 0.12), _tin),
        ],
        [Tier(full, 0, hh, body)],
        decor: (c, px) {
          c.drawRect(r(0, -h / 2 + h * 0.05, w * 0.78, h * 0.08), fill(_hole));
          c.drawRect(r(-w * 0.36, -h / 2 + h * 0.05, w * 0.1, h * 0.05), fill(const Color(0xFF4CC36E)));
          c.drawRect(r(w * 0.36, -h / 2 + h * 0.05, w * 0.1, h * 0.05), fill(const Color(0xFFF2C14E)));
        },
        decorZ: hh,
      );
    case 'dc_jack':
      return PartBuild(
        [
          for (final (x, y) in [(-w * 0.55, h * 0.1), (w * 0.55, h * 0.1), (0.0, h * 0.55)]) Lead(r(x, y, w * 0.18, h * 0.08), _tin),
        ],
        [Tier(full, 0, hh, body)],
        decor: (c, px) {
          c.drawCircle(Offset(0, -h * 0.1), small * 0.3, fill(_dark(body, 0.4)));
          c.drawCircle(Offset(0, -h * 0.1), small * 0.08, fill(_silver));
        },
        decorZ: hh,
      );
    case 'spring':
      return PartBuild(
        const [],
        [Tier(full, 0, hh * 0.2, body), Tier(r(w * 0.08, 0, w * 0.7, h * 0.6), hh * 0.2, hh, _light(body, 0.08), shape: TierShape.round, radius: h * 0.15)],
        decor: (c, px) => c.drawCircle(Offset(w * 0.2, 0), h * 0.16, fill(_light(body, 0.3))),
        decorZ: hh,
      );
    case 'tact_switch':
      return PartBuild(
        [
          for (final sx in [-1.0, 1.0])
            for (final sy in [-1.0, 1.0]) Lead(r(sx * (w / 2 + w * 0.06), sy * h * 0.33, w * 0.16, h * 0.12), _tin),
        ],
        [
          Tier(full, 0, hh * 0.45, _plastic),
          Tier(full.deflate(small * 0.03), hh * 0.45, hh * 0.55, body),
          Tier(r(0, 0, small * 0.58, small * 0.58), hh * 0.55, hh, _plastic, shape: TierShape.circle),
        ],
        decor: (c, px) => c.drawCircle(Offset(-small * 0.08, small * 0.08), small * 0.12, fill(_light(_plastic, 0.12))),
        decorZ: hh,
      );
    case 'side_switch':
      return PartBuild(
        [Lead(r(-w / 2 - w * 0.05, h * 0.2, w * 0.12, h * 0.2), _tin), Lead(r(w / 2 + w * 0.05, h * 0.2, w * 0.12, h * 0.2), _tin)],
        [Tier(full, 0, hh, body), Tier(r(0, -h / 2 - h * 0.12, w * 0.4, h * 0.26), hh * 0.2, hh * 0.85, _plastic)],
      );
    case 'slide_switch':
      return PartBuild(edgeLeads(3, h * 0.25), [
        Tier(full, 0, hh * 0.6, _plastic),
        Tier(full.deflate(small * 0.04), hh * 0.6, hh * 0.7, body == _plastic ? _silver : body),
        Tier(r(-w * 0.1, 0, w * 0.18, h * 0.45), hh * 0.7, hh * 1.4, _white),
      ]);
    case 'buzzer':
      return PartBuild(
        [Lead(r(-w / 2 - w * 0.04, 0, w * 0.1, h * 0.16), _tin), Lead(r(w / 2 + w * 0.04, 0, w * 0.1, h * 0.16), _tin)],
        [Tier(full, 0, hh, body, shape: TierShape.round, radius: small * 0.12)],
        decor: (c, px) {
          c.drawCircle(Offset.zero, small * 0.12, fill(_hole));
          final plus = Paint()
            ..color = mark
            ..strokeWidth = small * 0.03;
          c.drawLine(Offset(-w * 0.34, h * 0.3), Offset(-w * 0.26, h * 0.3), plus);
          c.drawLine(Offset(-w * 0.3, h * 0.26), Offset(-w * 0.3, h * 0.34), plus);
        },
        decorZ: hh,
      );
    case 'mic':
      return PartBuild(
        const [],
        [Tier(full, 0, hh * 0.3, _substrate), Tier(full.deflate(small * 0.06), hh * 0.3, hh, body, shape: TierShape.round, radius: small * 0.1)],
        decor: (c, px) => c.drawCircle(Offset(w * 0.25, 0), small * 0.1, fill(_hole)),
        decorZ: hh,
      );
    case 'relay':
      return PartBuild(edgeLeads(4, h * 0.12), [Tier(full, 0, hh, body)], decor: (c, px) => marking(c, px, lines: 3, scale: 0.8), decorZ: hh);
    case 'coin_cell':
      final d = small * 0.9;
      return PartBuild(
        [Lead(r(-w / 2 - w * 0.03, 0, w * 0.08, h * 0.2), _tin), Lead(r(w / 2 + w * 0.03, 0, w * 0.08, h * 0.2), _tin)],
        [
          Tier(full, 0, hh * 0.25, _plastic, shape: TierShape.round, radius: small * 0.1),
          Tier(r(0, 0, d, d), hh * 0.25, hh * 0.85, body, shape: TierShape.circle),
          Tier(r(0, 0, w * 0.9, h * 0.16), hh * 0.85, hh, _silver),
        ],
        decor: (c, px) {
          final plus = Paint()
            ..color = _dark(body, 0.45)
            ..strokeWidth = small * 0.02;
          c.drawLine(Offset(-small * 0.06, -h * 0.25), Offset(small * 0.06, -h * 0.25), plus);
          c.drawLine(Offset(0, -h * 0.25 - small * 0.06), Offset(0, -h * 0.25 + small * 0.06), plus);
        },
        decorZ: hh * 0.85,
      );
    case 'shield':
      return PartBuild(const [], [Tier(full, 0, hh, body, shape: TierShape.frame, frame: math.max(0.15, small * 0.03))]);
    case 'heatsink':
      final fins = math.max(3, (w / 1.5).round());
      return PartBuild(const [], [
        Tier(full, 0, hh * 0.2, body),
        for (var i = 0; i < fins; i++) Tier(r(-w / 2 + w * (i + 0.5) / fins, 0, w / fins * 0.4, h * 0.96), hh * 0.2, hh, body),
      ]);
    case 'mount_hole':
      return PartBuild(
        const [],
        const [],
        decor: (c, px) {
          c.drawCircle(Offset.zero, small / 2, fill(body));
          c.drawCircle(Offset.zero, small * 0.28, fill(_hole));
        },
      );
    case 'test_point':
      return PartBuild(
        const [],
        const [],
        decor: (c, px) {
          if ((w - h).abs() < 0.05) {
            c.drawCircle(Offset.zero, w / 2, fill(body));
            c.drawCircle(
              Offset.zero,
              w / 2,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = px
                ..color = _dark(body, 0.3),
            );
            c.drawCircle(Offset(-w * 0.1, w * 0.1), w * 0.16, fill(_light(body, 0.35)));
          } else {
            c.drawRRect(RRect.fromRectAndRadius(full, Radius.circular(small * 0.25)), fill(body));
            c.drawRRect(RRect.fromRectAndRadius(full.deflate(small * 0.18), Radius.circular(small * 0.15)), fill(_light(body, 0.18)));
          }
        },
      );
    case 'fiducial':
      return PartBuild(
        const [],
        const [],
        decor: (c, px) {
          c.drawCircle(Offset.zero, w * 0.9, fill(const Color(0x33000000)));
          c.drawCircle(Offset.zero, w / 2, fill(body));
          c.drawCircle(Offset(-w * 0.12, w * 0.12), w * 0.18, fill(_light(body, 0.35)));
        },
      );
    default:
      return PartBuild(
        const [],
        [Tier(full, 0, hh, body, shape: TierShape.round, radius: small * 0.08)],
        decor: (c, px) => marking(c, px, lines: 1, scale: 0.7),
        decorZ: hh,
      );
  }
}

/// Outline of a tier in part coordinates, counter-clockwise (Y up).
List<Offset> _outline(Tier t) {
  final r = t.rect;
  switch (t.shape) {
    case TierShape.circle:
      return [
        for (var i = 0; i < 24; i++) Offset(r.center.dx + r.width / 2 * math.cos(i * math.pi / 12), r.center.dy + r.height / 2 * math.sin(i * math.pi / 12)),
      ];
    case TierShape.round:
      final rad = math.min(t.radius, math.min(r.width, r.height) / 2);
      if (rad <= 0) return [r.bottomLeft, r.bottomRight, r.topRight, r.topLeft];
      final out = <Offset>[];
      for (final (c, a0) in [
        (Offset(r.right - rad, r.top + rad), -math.pi / 2),
        (Offset(r.right - rad, r.bottom - rad), 0.0),
        (Offset(r.left + rad, r.bottom - rad), math.pi / 2),
        (Offset(r.left + rad, r.top + rad), math.pi),
      ]) {
        for (var i = 0; i <= 3; i++) {
          final a = a0 + i * math.pi / 6;
          out.add(c + Offset(rad * math.cos(a), rad * math.sin(a)));
        }
      }
      return out;
    case TierShape.rect || TierShape.frame:
      // Rect.top is the smaller Y, the bottom edge in Y-up coordinates.
      return [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
  }
}

void _face(Canvas canvas, Tier t) {
  final paint = Paint()..color = t.color;
  switch (t.shape) {
    case TierShape.rect:
      canvas.drawRect(t.rect, paint);
    case TierShape.round:
      canvas.drawRRect(RRect.fromRectAndRadius(t.rect, Radius.circular(t.radius)), paint);
    case TierShape.circle:
      canvas.drawOval(t.rect, paint);
    case TierShape.frame:
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(t.rect)
          ..addRect(t.rect.deflate(t.frame)),
        paint,
      );
  }
}

/// Draws a built part whose foot is at screen point [at]. [raised] stands it
/// up (3D view); otherwise everything lies on the board plane.
void renderPart(Canvas canvas, BoardProjection view, Offset at, double rotation, PartBuild b, {required bool raised, required double px}) {
  Offset lift(double z) => raised ? view.lift(z) : Offset.zero;
  if (b.leads.isNotEmpty) {
    canvas.save();
    view.applyPart(canvas, at, rotation);
    for (final l in b.leads) {
      if (l.z > 0) continue;
      final p = Paint()..color = l.color;
      l.round ? canvas.drawOval(l.rect, p) : canvas.drawRect(l.rect, p);
    }
    canvas.restore();
  }
  for (final t in b.tiers) {
    if (raised && view.tilted && t.z1 > t.z0) {
      final pts = _outline(t);
      final base = [for (final p in pts) at + lift(t.z0) + view.localDelta(rotation, p.dx, p.dy)];
      final top = [for (final p in pts) at + lift(t.z1) + view.localDelta(rotation, p.dx, p.dy)];
      final wall = t.side ?? t.color;
      for (var i = 0; i < pts.length; i++) {
        final j = (i + 1) % pts.length;
        final e = pts[j] - pts[i];
        final len = e.distance;
        if (len <= 0) continue;
        final n = view.localPlane(rotation, e.dy / len, -e.dx / len);
        if (n.dy >= -1e-3) continue;
        canvas.drawPath(
          Path()..addPolygon([base[i], base[j], top[j], top[i]], true),
          Paint()..color = Color.lerp(const Color(0xFF000000), wall, faceShade(n.dx, n.dy, 0))!,
        );
      }
    }
    canvas.save();
    view.applyPart(canvas, at + lift(t.z1), rotation);
    _face(canvas, t);
    // Lit rim so dark bodies stand out from a dark board.
    if (identical(t, b.tiers.last) && t.shape != TierShape.frame) {
      final rim = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = px
        ..color = Color.lerp(t.color, const Color(0xFFFFFFFF), 0.3)!.withValues(alpha: 0.55);
      switch (t.shape) {
        case TierShape.circle:
          canvas.drawOval(t.rect.deflate(px / 2), rim);
        case TierShape.round:
          canvas.drawRRect(RRect.fromRectAndRadius(t.rect.deflate(px / 2), Radius.circular(t.radius)), rim);
        default:
          canvas.drawRect(t.rect.deflate(px / 2), rim);
      }
    }
    canvas.restore();
  }
  if (b.decor != null) {
    canvas.save();
    view.applyPart(canvas, at + lift(b.decorZ), rotation);
    b.decor!(canvas, px);
    canvas.restore();
  }
}

/// Convex hull (monotone chain) of a few points.
List<Offset> convexHull(List<Offset> pts) {
  final p = [...pts]..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  double cross(Offset o, Offset a, Offset b) => (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
  final lower = <Offset>[], upper = <Offset>[];
  for (final q in p) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, q) <= 0) {
      lower.removeLast();
    }
    lower.add(q);
  }
  for (final q in p.reversed) {
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, q) <= 0) {
      upper.removeLast();
    }
    upper.add(q);
  }
  return [...lower..removeLast(), ...upper..removeLast()];
}

/// A single library model drawn in a small 3D view, for the part library.
class PartPreview extends StatelessWidget {
  const PartPreview({super.key, required this.model, required this.body, required this.real, this.board});

  final PartModel model;
  final Color body;
  final bool real;
  final Color? board;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _PreviewPainter(model, body, real, board));
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.model, this.body, this.real, this.board);

  final PartModel model;
  final Color body;
  final bool real;
  final Color? board;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = PartShape(model.kind, model.width, model.height, model: model.id, bga: model.id == 'bga');
    final b = buildPart(shape, body, real: real);
    final pitch = model.bodyHeight > 0 ? 0.75 : 0.45;
    // Fit the projected body (with leads and height) into the tile.
    final unit = BoardProjection(0, 0, -0.45, false, pitch, 1, Offset.zero);
    final w2 = model.width * 0.62, h2 = model.height * 0.62, top = math.max(b.top, 0.0);
    final pts = [
      for (final (x, y) in [(-w2, -h2), (w2, -h2), (w2, h2), (-w2, h2)]) ...[unit.project(x, y), unit.project(x, y, top)],
    ];
    var l = double.infinity, t = double.infinity, r = -double.infinity, btm = -double.infinity;
    for (final p in pts) {
      l = math.min(l, p.dx);
      r = math.max(r, p.dx);
      t = math.min(t, p.dy);
      btm = math.max(btm, p.dy);
    }
    final scale = math.min((size.width - 24) / (r - l), (size.height - 20) / (btm - t));
    final centre = Offset(size.width / 2 - (l + r) / 2 * scale, size.height / 2 - (t + btm) / 2 * scale);
    final view = BoardProjection(0, 0, -0.45, false, pitch, scale, centre);
    canvas.clipRect(Offset.zero & size);
    if (board != null) canvas.drawRect(Offset.zero & size, Paint()..color = board!);
    // Shadow under the part.
    if (top > 0) {
      final off = Offset(-top * lightDir.$1 / lightDir.$3 * scale, top * lightDir.$2 / lightDir.$3 * view.cosP * scale);
      final hw = model.width / 2, hh = model.height / 2;
      final base = [
        for (final (x, y) in [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]) view.project(x, y),
      ];
      canvas.drawPath(Path()..addPolygon(convexHull([...base, for (final p in base) p + off]), true), Paint()..color = const Color(0x26000000));
    }
    renderPart(canvas, view, view.project(0, 0), 0, b, raised: true, px: 1 / scale);
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.model != model || old.body != body || old.real != real || old.board != board;
}
