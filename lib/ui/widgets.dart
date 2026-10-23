/// Hand-built desktop controls (no Material widgets).
library;

import 'package:flutter/widgets.dart';

import 'icons.dart';

import 'theme.dart';

/// Hover / press tracking for custom buttons.
class Hoverable extends StatefulWidget {
  const Hoverable({super.key, required this.builder, this.onTap, this.cursor = SystemMouseCursors.click, this.tooltip});

  final Widget Function(BuildContext context, bool hover, bool pressed) builder;
  final VoidCallback? onTap;
  final MouseCursor cursor;
  final String? tooltip;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    Widget child = MouseRegion(
      cursor: enabled ? widget.cursor : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: widget.builder(context, enabled && _hover, enabled && _pressed),
      ),
    );
    if (widget.tooltip != null) {
      child = Semantics(tooltip: widget.tooltip, child: child);
    }
    return child;
  }
}

/// Compact button with optional icon, used in toolbars and dialogs.
class FlatButton extends StatelessWidget {
  const FlatButton({super.key, this.icon, required this.label, this.onTap, this.primary = false, this.compact = false, this.danger = false});

  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool compact;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    final enabled = onTap != null;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, pressed) {
        final bg = primary ? (hover ? c.btnHover : c.btn) : (hover ? c.glass2 : c.hover);
        final fg = !enabled
            ? c.textFaint
            : primary
            ? c.accentText
            : danger
            ? c.ng
            : c.text;
        final h = compact ? (m.touch ? 36.0 : 32.0) : (m.touch ? 44.0 : 40.0);
        return AnimatedScale(
          scale: pressed && enabled ? 0.97 : 1,
          duration: const Duration(milliseconds: 150),
          child: Opacity(
            opacity: enabled || !primary ? 1 : 0.4,
            child: Container(
              height: h,
              padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(h / 2),
                boxShadow: primary && enabled ? const [BoxShadow(color: Color(0x4D0071E3), offset: Offset(0, 6), blurRadius: 16)] : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 6)],
                  Text(
                    label,
                    style: TextStyle(
                      color: primary ? const Color(0xFFFFFFFF) : fg,
                      fontSize: compact ? 13 : 14,
                      fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Square icon-only button.
class IconBtn extends StatelessWidget {
  const IconBtn({super.key, required this.icon, this.onTap, this.size, this.tooltip, this.active = false});

  final IconData icon;
  final VoidCallback? onTap;

  /// Defaults to the metrics' icon-button size.
  final double? size;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final size = this.size ?? Metrics.of(context).iconButton;
    return Hoverable(
      onTap: onTap,
      tooltip: tooltip,
      builder: (context, hover, pressed) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? c.blueTint
              : hover
              ? c.hover
              : null,
          borderRadius: BorderRadius.circular(size / 2),
        ),
        child: Icon(
          icon,
          size: (size * 0.6).clamp(14, 20),
          color: onTap == null
              ? c.textFaint
              : active
              ? c.accent
              : c.textDim,
        ),
      ),
    );
  }
}

/// Underlined tab used for ribbon tabs and workspace tabs.
class TabItem extends StatelessWidget {
  const TabItem({super.key, required this.label, required this.active, required this.onTap, this.icon, this.count, this.color, this.dense = false});

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;
  final Color? color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final accent = color ?? c.accent;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, pressed) => Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 16),
        decoration: BoxDecoration(
          color: active
              ? null
              : hover
              ? c.hover
              : null,
          border: Border(bottom: BorderSide(color: active ? accent : const Color(0x00000000), width: 2)),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 15, color: active ? accent : c.textDim), const SizedBox(width: 6)],
            Text(
              label,
              style: TextStyle(fontSize: 13, color: active ? c.text : c.textDim, fontWeight: active ? FontWeight.w600 : FontWeight.w400),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: active ? accent : c.hover, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  '$count',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: active ? const Color(0xFFFFFFFF) : c.textDim),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Designator chip: tinted fill, coloured border, status dot.
class RefChip extends StatelessWidget {
  const RefChip({super.key, required this.text, required this.color, required this.soft, this.strike = false});

  final String text;
  final Color color;
  final Color soft;
  final bool strike;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(9)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
              decoration: strike ? TextDecoration.lineThrough : null,
              decorationColor: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Solid result badge (PASS / NG / ...).
class ResultBadge extends StatelessWidget {
  const ResultBadge({super.key, required this.text, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13)),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.24, color: color),
      ),
    );
  }
}

/// Single- or multi-line text input built on [EditableText].
class TextInput extends StatefulWidget {
  const TextInput({super.key, required this.controller, this.hint, this.maxLines = 1, this.onChanged, this.prefix, this.mono = false, this.width});

  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final IconData? prefix;
  final bool mono;
  final double? width;

  @override
  State<TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<TextInput> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    widget.controller.addListener(_onText);
  }

  void _onText() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final style = baseTextStyle(c).copyWith(fontSize: 13, fontFamily: widget.mono ? monoFontFamily : null);
    final multi = widget.maxLines > 1;
    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Container(
          width: widget.width,
          height: multi ? null : (Metrics.of(context).touch ? 40 : 36),
          padding: EdgeInsets.symmetric(horizontal: multi ? 14 : 14, vertical: multi ? 10 : 0),
          decoration: BoxDecoration(
            color: c.hover,
            borderRadius: BorderRadius.circular(multi ? 16 : 18),
            border: Border.all(color: _focus.hasFocus ? c.blue : const Color(0x00000000), width: 2),
          ),
          child: Row(
            crossAxisAlignment: multi ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              if (widget.prefix != null) ...[Icon(widget.prefix, size: 14, color: c.textFaint), const SizedBox(width: 6)],
              Expanded(
                child: Stack(
                  children: [
                    if (widget.controller.text.isEmpty && widget.hint != null)
                      IgnorePointer(
                        child: Text(
                          widget.hint!,
                          style: style.copyWith(color: c.textFaint),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    EditableText(
                      controller: widget.controller,
                      focusNode: _focus,
                      style: style,
                      cursorColor: c.accent,
                      backgroundCursorColor: c.textFaint,
                      selectionColor: c.accent.withValues(alpha: 0.35),
                      maxLines: widget.maxLines,
                      minLines: multi ? widget.maxLines : null,
                      keyboardType: multi ? TextInputType.multiline : TextInputType.text,
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

class CheckBox extends StatelessWidget {
  const CheckBox({super.key, required this.value, required this.onChanged, required this.label});

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Hoverable(
      onTap: () => onChanged(!value),
      builder: (context, hover, pressed) => Padding(
        padding: EdgeInsets.symmetric(vertical: Metrics.of(context).touch ? 7 : 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: value ? c.accent : c.input,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: value
                      ? c.accent
                      : hover
                      ? c.textDim
                      : c.borderStrong,
                ),
              ),
              child: value ? const _CheckMark() : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label, style: TextStyle(color: c.text, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckMark extends StatelessWidget {
  const _CheckMark();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _CheckPainter());
}

class _CheckPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width * 0.22, size.height * 0.52)
      ..lineTo(size.width * 0.42, size.height * 0.72)
      ..lineTo(size.width * 0.78, size.height * 0.3);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Segmented selector, used instead of a dropdown.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, required this.onChanged});

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
                  height: Metrics.of(context).touch ? 36 : 32,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? c.solid : (hover ? c.hover : null),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: on ? const [BoxShadow(color: Color(0x1A000000), offset: Offset(0, 2), blurRadius: 8)] : null,
                  ),
                  child: Text(
                    options[i].$2,
                    style: TextStyle(fontSize: 13, color: on ? c.blueTx : c.tx2, fontWeight: on ? FontWeight.w600 : FontWeight.w500),
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

/// Panel with a slim title bar, like docked panels in CAD / image editors.
class DockPanel extends StatelessWidget {
  const DockPanel({super.key, required this.title, required this.child, this.actions = const []});

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      color: c.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: Metrics.of(context).touch ? 36 : 30,
            padding: const EdgeInsets.only(left: 12, right: 4),
            decoration: BoxDecoration(
              color: c.panel,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: c.textDim),
                  ),
                ),
                ...actions,
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class VDivider extends StatelessWidget {
  const VDivider({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    margin: EdgeInsets.symmetric(vertical: indent),
    color: AppTheme.of(context).border,
  );
}

class HDivider extends StatelessWidget {
  const HDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(height: 1, color: AppTheme.of(context).border);
}

/// Scrollbar without Material.
class ThinScrollbar extends StatelessWidget {
  const ThinScrollbar({super.key, required this.controller, required this.child, this.horizontal = false});

  final ScrollController controller;
  final Widget child;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return RawScrollbar(
      controller: controller,
      thumbColor: c.borderStrong,
      radius: const Radius.circular(3),
      thickness: 7,
      thumbVisibility: true,
      notificationPredicate: (n) => n.depth == 0,
      child: child,
    );
  }
}

/// Shows a modal dialog with a flat frame.
Future<T?> showAppDialog<T>(BuildContext context, {required String title, required Widget Function(BuildContext) body, double width = 520}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: const Color(0x52000000),
    transitionDuration: const Duration(milliseconds: 90),
    pageBuilder: (ctx, a1, a2) {
      final c = AppTheme.of(context);
      return AppTheme(
        colors: c,
        child: MetricsScope(
          metrics: Metrics.of(context),
          child: DefaultTextStyle(
            style: baseTextStyle(c),
            child: Center(
              child: Container(
                width: width.clamp(0, MediaQuery.sizeOf(ctx).width - 24).toDouble(),
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height - 48),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: c.solid, borderRadius: BorderRadius.circular(26), boxShadow: c.shadow),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 18, 14, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: c.tx),
                            ),
                          ),
                          IconBtn(icon: Ic.x, size: 32, onTap: () => Navigator.of(ctx).pop()),
                        ],
                      ),
                    ),
                    Flexible(child: body(ctx)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Simple message / confirm dialog. Returns true when confirmed.
Future<bool> showMessage(BuildContext context, {required String title, required String message, required String ok, String? cancel, bool error = false}) async {
  final r = await showAppDialog<bool>(
    context,
    title: title,
    width: 440,
    body: (ctx) {
      final c = AppTheme.of(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 12, top: 7),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: error ? c.ngSolid : c.blue),
                ),
                Expanded(
                  child: Text(message, style: TextStyle(color: c.text, fontSize: 14, height: 1.55)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (cancel != null) ...[FlatButton(label: cancel, onTap: () => Navigator.of(ctx).pop(false)), const SizedBox(width: 8)],
                FlatButton(label: ok, primary: true, onTap: () => Navigator.of(ctx).pop(true)),
              ],
            ),
          ],
        ),
      );
    },
  );
  return r ?? false;
}

/// Rounded filter pill with a colour dot and a count, used for result areas.
class FilterPill extends StatelessWidget {
  const FilterPill({super.key, required this.label, required this.active, required this.onTap, this.color, this.count});

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? color;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    final tone = color ?? c.accent;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, pressed) => Container(
        height: m.compactControl,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active
              ? tone.withValues(alpha: c.dark ? 0.18 : 0.10)
              : hover
              ? c.hover
              : null,
          borderRadius: BorderRadius.circular(m.compactControl / 2),
          border: Border.all(color: active ? tone.withValues(alpha: 0.75) : c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color ?? c.textDim, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(fontSize: 12.5, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: active ? c.text : c.textDim),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: active ? tone : c.textFaint,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Slide-in panel over the workspace (project drawer, floating inspector).
class OverlayPanel extends StatelessWidget {
  const OverlayPanel({super.key, required this.child, required this.onClose, this.left = false, this.width = 340});

  final Widget child;
  final VoidCallback onClose;
  final bool left;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: ColoredBox(color: c.dark ? const Color(0x66000000) : const Color(0x33000000)),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: left ? 0 : null,
          right: left ? null : 0,
          width: width.clamp(0, MediaQuery.sizeOf(context).width - 40).toDouble(),
          child: Container(
            decoration: BoxDecoration(
              color: c.panel,
              border: Border(
                right: left ? BorderSide(color: c.borderStrong) : BorderSide.none,
                left: left ? BorderSide.none : BorderSide(color: c.borderStrong),
              ),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24)],
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// Slim page header: title, context line, optional trailing actions.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.trailing = const []});

  final String title;
  final String? subtitle;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(8, m.touch ? 8 : 4, 0, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 30, height: 1.15, fontWeight: FontWeight.w700, color: c.text, letterSpacing: -0.84),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: c.textDim),
                  ),
                ],
              ],
            ),
          ),
          for (final t in trailing) ...[const SizedBox(width: 8), t],
        ],
      ),
    );
  }
}

/// Surface card with a hairline border and soft shadow.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.borderColor});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(26),
        border: borderColor == null ? null : Border.all(color: borderColor!),
        boxShadow: c.shadow,
      ),
      child: child,
    );
  }
}

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

String formatTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// Compact select box that opens a list below it.
class DropdownSelect<T> extends StatefulWidget {
  const DropdownSelect({super.key, required this.value, required this.options, required this.onChanged, this.width = 150, this.flat = false});

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final double width;

  /// Inside a card: hover tint, no glass shadow.
  final bool flat;

  @override
  State<DropdownSelect<T>> createState() => _DropdownSelectState<T>();
}

class _DropdownSelectState<T> extends State<DropdownSelect<T>> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    final current = widget.options.firstWhere((o) => o.$1 == widget.value, orElse: () => widget.options.first);
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _portal.hide),
            ),
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomLeft,
              offset: const Offset(0, 6),
              child: Align(
                alignment: Alignment.topLeft,
                child: AppTheme(
                  colors: c,
                  child: DefaultTextStyle(
                    style: baseTextStyle(c),
                    child: Container(
                      width: widget.width < 150 ? 150 : widget.width,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: c.solid, borderRadius: BorderRadius.circular(18), boxShadow: c.shadow),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final (v, label) in widget.options)
                            Hoverable(
                              onTap: () {
                                _portal.hide();
                                widget.onChanged(v);
                              },
                              builder: (context, hover, _) => Container(
                                height: m.touch ? 40 : 36,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                alignment: Alignment.centerLeft,
                                decoration: BoxDecoration(
                                  color: v == widget.value
                                      ? c.blueTint
                                      : hover
                                      ? c.hover
                                      : null,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: v == widget.value ? c.blueTx : c.text,
                                    fontWeight: v == widget.value ? FontWeight.w600 : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        child: Hoverable(
          onTap: _portal.toggle,
          builder: (context, hover, _) => Container(
            width: widget.width,
            height: m.touch ? 44 : 40,
            padding: const EdgeInsets.only(left: 16, right: 14),
            decoration: BoxDecoration(
              color: widget.flat ? (hover ? Color.alphaBlend(c.hover, c.hover) : c.hover) : (hover ? c.glass2 : c.glass),
              borderRadius: BorderRadius.circular(22),
              boxShadow: widget.flat ? null : c.shadowSm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    current.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.text),
                  ),
                ),
                const SizedBox(width: 6),
                CustomPaint(size: const Size(10, 10), painter: _DownCaret(c.textDim)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DownCaret extends CustomPainter {
  _DownCaret(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.15, size.height * 0.35)
        ..lineTo(size.width * 0.5, size.height * 0.7)
        ..lineTo(size.width * 0.85, size.height * 0.35),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_DownCaret old) => old.color != color;
}

/// Page banner: large title, description and a flat circuit illustration.
class PageBanner extends StatelessWidget {
  const PageBanner({super.key, required this.title, required this.subtitle, this.leading, this.trailing});

  final String title;
  final String subtitle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      height: 104,
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(right: 0, top: 0, bottom: 0, width: 420, child: CustomPaint(painter: _CircuitArt(c.accent, c.dark))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 18)],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.text, letterSpacing: 0.3),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.textDim),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Faint chip and traces drawn with flat strokes, fading by opacity steps.
class _CircuitArt extends CustomPainter {
  _CircuitArt(this.accent, this.dark);

  final Color accent;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final base = dark ? 0.16 : 0.12;
    Paint line(double a, [double w = 1.4]) => Paint()
      ..color = accent.withValues(alpha: a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    final cx = size.width * 0.62, cy = size.height * 0.52;
    final chip = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy), width: 70, height: 70), const Radius.circular(8));
    canvas.drawRRect(chip, Paint()..color = accent.withValues(alpha: base * 0.6));
    canvas.drawRRect(chip, line(base * 2));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy), width: 40, height: 40), const Radius.circular(4)), line(base * 1.6));
    for (var i = -3; i <= 3; i++) {
      final d = i * 9.0;
      canvas.drawLine(Offset(cx + d, cy - 35), Offset(cx + d, cy - 44), line(base * 2));
      canvas.drawLine(Offset(cx + d, cy + 35), Offset(cx + d, cy + 44), line(base * 2));
      canvas.drawLine(Offset(cx - 35, cy + d), Offset(cx - 44, cy + d), line(base * 2));
      canvas.drawLine(Offset(cx + 35, cy + d), Offset(cx + 44, cy + d), line(base * 2));
    }
    // Traces leaving the chip, fainter with distance.
    final traces = [
      [Offset(cx - 44, cy - 18), Offset(cx - 110, cy - 18), Offset(cx - 140, cy - 48), Offset(cx - 260, cy - 48)],
      [Offset(cx - 44, cy + 9), Offset(cx - 150, cy + 9), Offset(cx - 180, cy + 39), Offset(cx - 300, cy + 39)],
      [Offset(cx + 44, cy - 9), Offset(cx + 100, cy - 9), Offset(cx + 120, cy - 29), Offset(cx + 200, cy - 29)],
      [Offset(cx + 44, cy + 18), Offset(cx + 90, cy + 18), Offset(cx + 115, cy + 43), Offset(cx + 200, cy + 43)],
      [Offset(cx - 9, cy - 44), Offset(cx - 9, cy - 70)],
      [Offset(cx + 18, cy + 44), Offset(cx + 18, cy + 70)],
    ];
    for (final t in traces) {
      for (var i = 0; i < t.length - 1; i++) {
        canvas.drawLine(t[i], t[i + 1], line(base * (1.6 - i * 0.35).clamp(0.4, 1.6)));
      }
      canvas.drawCircle(t.last, 3, line(base * 0.9));
    }
  }

  @override
  bool shouldRepaint(_CircuitArt old) => old.accent != accent || old.dark != dark;
}

/// Small coloured status icon: ok / warning / error.
enum Status { ok, warning, error, idle }
