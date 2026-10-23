/// Building blocks of the SMT-FAI design: mesh background, translucent
/// cards, glass and pill buttons, gradient icon tiles, badges, chips, tool
/// tiles, radio and segmented pills.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'lucide.dart';
import 'theme.dart';
import 'widgets.dart';

/// The page background: three soft colour blooms along the top edge.
class MeshBackground extends StatelessWidget {
  const MeshBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return CustomPaint(painter: _MeshPainter(c), child: child);
  }
}

class _MeshPainter extends CustomPainter {
  _MeshPainter(this.c);

  final AppColors c;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = c.bg);
    // radial-gradient(Wpx Hpx at X Y, colour, transparent 70%)
    for (final (cx, cy, rx, ry, color) in [
      (size.width * 0.16, -80.0, 900.0, 520.0, c.mesh1),
      (size.width * 0.86, -60.0, 820.0, 480.0, c.mesh2),
      (size.width * 0.56, 10.0, 700.0, 420.0, c.mesh3),
    ]) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(1, ry / rx);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
          stops: const [0, 0.7],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: rx));
      canvas.drawCircle(Offset.zero, rx, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MeshPainter old) => old.c != c;
}

/// Translucent rounded card with the design's soft shadow.
class DCard extends StatelessWidget {
  const DCard({super.key, required this.child, this.radius = 32, this.padding = EdgeInsets.zero, this.shadow, this.color, this.clip = false});

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final List<BoxShadow>? shadow;
  final Color? color;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(color: color ?? c.card, borderRadius: BorderRadius.circular(radius), boxShadow: shadow ?? c.shadow),
      child: child,
    );
  }
}

/// Glass button: a circle with an icon, or a pill with a label.
class GlassButton extends StatelessWidget {
  const GlassButton({super.key, this.icon, this.label, this.trailing, this.onTap, this.tooltip, this.size = 36, this.iconSize = 18});

  final Lucide? icon;
  final String? label;
  final Lucide? trailing;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Hoverable(
      onTap: onTap,
      tooltip: tooltip,
      builder: (context, hover, _) => Container(
        width: label == null ? size : null,
        height: size,
        padding: label == null ? null : const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: hover ? c.glass2 : c.glass, borderRadius: BorderRadius.circular(size / 2), boxShadow: c.shadowSm),
        child: label == null
            ? LucideIcon(icon!, size: iconSize, color: c.tx, stroke: 1.7)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[LucideIcon(icon!, size: 16, color: c.tx), const SizedBox(width: 6)],
                  Text(
                    label!,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.tx),
                  ),
                  if (trailing != null) ...[const SizedBox(width: 6), LucideIcon(trailing!, size: 12, color: c.tx, stroke: 2.4)],
                ],
              ),
      ),
    );
  }
}

enum PillKind { primary, soft, ghost, glass }

/// Rounded pill button: primary (blue), soft (tinted), ghost (transparent)
/// or glass.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.kind = PillKind.soft,
    this.height = 40,
    this.fontSize = 14,
    this.color,
    this.trailing,
    this.padding,
    this.iconSize,
    this.weight,
  });

  final String label;
  final Lucide? icon;
  final VoidCallback? onTap;
  final PillKind kind;
  final double height;
  final double fontSize;

  /// Text / icon colour override.
  final Color? color;

  /// Shown after the label (e.g. a keyboard hint).
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;
  final double? iconSize;
  final FontWeight? weight;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final enabled = onTap != null;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, pressed) {
        final primary = kind == PillKind.primary;
        final bg = switch (kind) {
          PillKind.primary => hover && enabled ? c.btnHover : c.btn,
          PillKind.soft => hover && enabled ? c.glass2 : c.hover,
          PillKind.ghost => hover && enabled ? c.hover : const Color(0x00000000),
          PillKind.glass => hover && enabled ? c.glass2 : c.glass,
        };
        final fg = color ?? (primary ? const Color(0xFFFFFFFF) : c.tx);
        return AnimatedScale(
          scale: pressed && enabled && kind != PillKind.ghost ? 0.97 : 1,
          duration: const Duration(milliseconds: 150),
          child: Opacity(
            opacity: enabled || !primary ? 1 : 0.4,
            child: Container(
              height: height,
              padding: padding ?? EdgeInsets.symmetric(horizontal: height >= 44 ? 22 : 16),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(height / 2),
                boxShadow: primary && enabled
                    ? const [BoxShadow(color: Color(0x5C0071E3), offset: Offset(0, 8), blurRadius: 22)]
                    : kind == PillKind.glass
                    ? c.shadowSm
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    LucideIcon(icon!, size: iconSize ?? (height >= 44 ? 18 : 15), color: enabled ? fg : c.tx3, stroke: 1.9),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: weight ?? (primary || height >= 44 ? FontWeight.w600 : FontWeight.w500),
                      letterSpacing: -0.01 * fontSize,
                      color: enabled || primary ? fg : c.tx3,
                    ),
                  ),
                  if (trailing != null) ...[const SizedBox(width: 12), trailing!],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Keyboard hint inside a primary button ("F5").
class KeyHint extends StatelessWidget {
  const KeyHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    height: 24,
    padding: const EdgeInsets.symmetric(horizontal: 9),
    alignment: Alignment.center,
    decoration: BoxDecoration(color: const Color(0x38FFFFFF), borderRadius: BorderRadius.circular(8)),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFFFFFFF)),
    ),
  );
}

/// Keyboard key in running text ("Ctrl+E").
class Kbd extends StatelessWidget {
  const Kbd(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: c.kbd, borderRadius: BorderRadius.circular(5)),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.tx),
      ),
    );
  }
}

/// Square icon tile with a diagonal gradient, glow and lit top edge.
class GradientTile extends StatelessWidget {
  const GradientTile({
    super.key,
    required this.icon,
    required this.colors,
    required this.glow,
    this.size = 60,
    this.radius = 18,
    this.iconSize = 28,
    this.badge,
  });

  final Lucide icon;

  /// Light and dark ends of the 145° gradient.
  final (Color, Color) colors;
  final Color glow;
  final double size;
  final double radius;
  final double iconSize;

  /// Small mark at the lower right (e.g. a check when loaded).
  final Widget? badge;

  static const blue = (Color(0xFF5AA9FF), Color(0xFF0A64E8));
  static const blueGlow = Color(0x520A64E8);
  static const teal = (Color(0xFF47D6B0), Color(0xFF0D9A78));
  static const tealGlow = Color(0x4D0D9A78);
  static const orange = (Color(0xFFFFB866), Color(0xFFEE7414));
  static const orangeGlow = Color(0x4DEE7414);
  static const gray = (Color(0xFFC7C7CC), Color(0xFF98989D));
  static const grayGlow = Color(0x40787880);
  static const graphite = (Color(0xFF3A3A3C), Color(0xFF111113));

  @override
  Widget build(BuildContext context) {
    // 145deg: from the top-left towards the bottom-right, slightly steeper.
    final angle = (145 - 90) * math.pi / 180;
    final begin = Alignment(-math.cos(angle), -math.sin(angle));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(begin: begin, end: -begin, colors: [colors.$1, colors.$2]),
        boxShadow: [BoxShadow(color: glow, offset: Offset(0, size / 6), blurRadius: size * 0.4)],
      ),
      alignment: Alignment.center,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          LucideIcon(icon, size: iconSize, color: const Color(0xFFFFFFFF)),
          if (badge != null) Positioned(right: -size * 0.18, bottom: -size * 0.18, child: badge!),
        ],
      ),
    );
  }
}

/// Small rounded tint tile with a coloured icon (e.g. unit / format cards).
class TintTile extends StatelessWidget {
  const TintTile({super.key, required this.icon, this.size = 44, this.radius = 14, this.iconSize = 22, this.tint, this.color});

  final Lucide icon;
  final double size;
  final double radius;
  final double iconSize;
  final Color? tint;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tint ?? c.blueTint, borderRadius: BorderRadius.circular(radius)),
      child: LucideIcon(icon, size: iconSize, color: color ?? c.blueTx),
    );
  }
}

/// Rounded result badge ("PASS", "NG").
class DBadge extends StatelessWidget {
  const DBadge({super.key, required this.text, required this.background, required this.color, this.height = 26});

  final String text;
  final Color background;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(height / 2)),
    child: Center(
      widthFactor: 1,
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.24, color: color),
      ),
    ),
  );
}

/// Designator chip with a leading dot.
class DotChip extends StatelessWidget {
  const DotChip({super.key, required this.text, required this.background, required this.color, this.strike = false});

  final String text;
  final Color background;
  final Color color;
  final bool strike;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(9)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.9), shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.4,
            color: color,
            decoration: strike ? TextDecoration.lineThrough : null,
            decorationColor: color,
          ),
        ),
      ],
    ),
  );
}

/// Toolbar tile: icon over a short label, blue tint when on.
class ToolTile extends StatelessWidget {
  const ToolTile({super.key, required this.icon, required this.label, this.onTap, this.active = false});

  final Lucide icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, _) => Container(
        constraints: const BoxConstraints(minWidth: 68),
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active
              ? c.blueTint
              : hover
              ? c.hover
              : null,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LucideIcon(icon, size: 24, color: active ? c.blueTx : c.tx),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: active ? c.blueTx : c.tx),
            ),
          ],
        ),
      ),
    );
  }
}

/// Radio choice drawn as a pill with a round marker.
class RadioPill extends StatelessWidget {
  const RadioPill({super.key, required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, _) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: on
              ? c.blueTint
              : hover
              ? c.hover
              : null,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(shape: BoxShape.circle, color: on ? c.btn : c.track),
              alignment: Alignment.center,
              child: on
                  ? Container(
                      width: 5.2,
                      height: 5.2,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFFFFFF)),
                    )
                  : null,
            ),
            const SizedBox(width: 9),
            Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: on ? c.blueTx : c.tx),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmented control: a tinted pill track with the chosen segment raised.
class SegmentedPill<T> extends StatelessWidget {
  const SegmentedPill({super.key, required this.value, required this.options, required this.onChanged});

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.hover, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Hoverable(
              onTap: () => onChanged(options[i].$1),
              builder: (context, hover, _) {
                final on = options[i].$1 == value;
                return Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? c.solid : (hover ? c.hover : null),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: on ? const [BoxShadow(color: Color(0x1A000000), offset: Offset(0, 2), blurRadius: 8)] : null,
                  ),
                  child: Text(
                    options[i].$2,
                    style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: on ? c.blueTx : c.tx2),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Small grey caption under a toolbar group or button.
class Caption extends StatelessWidget {
  const Caption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: 12, color: AppTheme.of(context).tx2));
}

/// Linear progress track (the design's 6 px bars).
class TrackBar extends StatelessWidget {
  const TrackBar({super.key, required this.value, required this.color, this.height = 6});

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: c.track)),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height / 2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill search / text field: glass with a soft shadow, or [flat] on the
/// hover tint inside cards.
class PillSearch extends StatefulWidget {
  const PillSearch({super.key, required this.controller, this.hint, this.onChanged, this.icon = Lucide.search, this.flat = false, this.height = 40});

  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final Lucide icon;
  final bool flat;
  final double height;

  @override
  State<PillSearch> createState() => _PillSearchState();
}

class _PillSearchState extends State<PillSearch> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    widget.controller.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void didUpdateWidget(PillSearch old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final style = baseTextStyle(c).copyWith(fontSize: 14);
    return GestureDetector(
      onTap: _focus.requestFocus,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Container(
          height: widget.height,
          padding: const EdgeInsets.only(left: 16, right: 16),
          decoration: BoxDecoration(
            color: widget.flat ? c.hover : c.glass,
            borderRadius: BorderRadius.circular(widget.height / 2),
            boxShadow: widget.flat ? null : c.shadowSm,
            border: _focus.hasFocus ? Border.all(color: c.blue, width: 2) : null,
          ),
          child: Row(
            children: [
              LucideIcon(widget.icon, size: 16, color: c.tx2, stroke: 2),
              const SizedBox(width: 10),
              Expanded(
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    if (widget.controller.text.isEmpty && widget.hint != null)
                      IgnorePointer(
                        child: Text(
                          widget.hint!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: style.copyWith(color: c.tx2),
                        ),
                      ),
                    EditableText(
                      controller: widget.controller,
                      focusNode: _focus,
                      style: style,
                      cursorColor: c.blue,
                      backgroundCursorColor: c.tx3,
                      selectionColor: c.blue.withValues(alpha: 0.3),
                      maxLines: 1,
                      onChanged: widget.onChanged,
                      rendererIgnoresPointer: false,
                      selectionControls: emptyTextSelectionControls,
                      enableInteractiveSelection: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
