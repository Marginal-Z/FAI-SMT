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

/// Large ribbon button: icon above label, like CAD / image-editor ribbons.
class RibbonButton extends StatelessWidget {
  const RibbonButton({super.key, required this.icon, required this.label, this.onTap, this.active = false, this.badge});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  /// Small status dot colour (e.g. file loaded).
  final Color? badge;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final enabled = onTap != null;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, pressed) => Container(
        constraints: const BoxConstraints(minWidth: 64),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        decoration: BoxDecoration(
          color: active
              ? c.selected
              : pressed
                  ? c.pressed
                  : hover
                      ? c.hover
                      : null,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? c.accent.withValues(alpha: 0.6) : const Color(0x00000000)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 26, color: enabled ? (active ? c.accent : c.text) : c.textFaint),
                if (badge != null)
                  Positioned(
                    right: -3,
                    bottom: -1,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: badge, shape: BoxShape.circle, border: Border.all(color: c.ribbon, width: 1.5)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(fontSize: 12, color: enabled ? c.text : c.textFaint)),
          ],
        ),
      ),
    );
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
    final enabled = onTap != null;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, pressed) {
        final bg = primary
            ? (pressed ? c.accent.withValues(alpha: 0.8) : hover ? c.accent.withValues(alpha: 0.9) : c.accent)
            : (pressed ? c.pressed : hover ? c.hover : c.panelAlt);
        final fg = !enabled ? c.textFaint : primary ? c.accentText : danger ? c.ng : c.text;
        return Container(
          height: compact ? 26 : 30,
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 14),
          decoration: BoxDecoration(
            color: enabled ? bg : c.panelAlt,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: primary && enabled ? c.accent : c.borderStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label, style: TextStyle(color: fg, fontSize: 12.5)),
            ],
          ),
        );
      },
    );
  }
}

/// Square icon-only button.
class IconBtn extends StatelessWidget {
  const IconBtn({super.key, required this.icon, this.onTap, this.size = 26, this.tooltip, this.active = false});

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Hoverable(
      onTap: onTap,
      tooltip: tooltip,
      builder: (context, hover, pressed) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.selected : pressed ? c.pressed : hover ? c.hover : null,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Icon(icon, size: size * 0.6, color: onTap == null ? c.textFaint : active ? c.accent : c.textDim),
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
          color: active ? null : hover ? c.hover : null,
          border: Border(bottom: BorderSide(color: active ? accent : const Color(0x00000000), width: 2)),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: active ? accent : c.textDim),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  color: active ? c.text : c.textDim,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                )),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: active ? accent : c.hover,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: active ? const Color(0xFFFFFFFF) : c.textDim,
                    )),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
                decoration: strike ? TextDecoration.lineThrough : null,
                decorationColor: color,
              )),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFFFFFFF)),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFFFFFFF))),
        ],
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
    final style = baseTextStyle(c).copyWith(
      fontSize: 13,
      fontFamily: widget.mono ? monoFontFamily : null,
    );
    final multi = widget.maxLines > 1;
    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Container(
          width: widget.width,
          height: multi ? null : 28,
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: multi ? 6 : 0),
          decoration: BoxDecoration(
            color: c.input,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: _focus.hasFocus ? c.accent : c.borderStrong),
          ),
          child: Row(
            crossAxisAlignment: multi ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              if (widget.prefix != null) ...[
                Icon(widget.prefix, size: 14, color: c.textFaint),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Stack(
                  children: [
                    if (widget.controller.text.isEmpty && widget.hint != null)
                      IgnorePointer(child: Text(widget.hint!, style: style.copyWith(color: c.textFaint), maxLines: 1, overflow: TextOverflow.ellipsis)),
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
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: value ? c.accent : c.input,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: value ? c.accent : hover ? c.textDim : c.borderStrong),
              ),
              child: value ? const _CheckMark() : null,
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(label, style: TextStyle(color: c.text, fontSize: 13))),
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
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: c.borderStrong),
        color: c.input,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            Hoverable(
              onTap: () => onChanged(options[i].$1),
              builder: (context, hover, _) {
                final on = options[i].$1 == value;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? c.accent : hover ? c.hover : null,
                    border: i == 0 ? null : Border(left: BorderSide(color: c.borderStrong)),
                  ),
                  child: Text(options[i].$2, style: TextStyle(fontSize: 12.5, color: on ? c.accentText : c.text)),
                );
              },
            ),
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
            height: 28,
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(color: c.panelAlt, border: Border(bottom: BorderSide(color: c.border))),
            child: Row(
              children: [
                Expanded(
                  child: Text(title.toUpperCase(),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: c.textDim)),
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
    barrierColor: const Color(0x66000000),
    transitionDuration: const Duration(milliseconds: 90),
    pageBuilder: (ctx, a1, a2) {
      final c = AppTheme.of(context);
      return AppTheme(
        colors: c,
        child: DefaultTextStyle(
          style: baseTextStyle(c),
          child: Center(
            child: Container(
              width: width,
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height - 80),
              decoration: BoxDecoration(
                color: c.panel,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.borderStrong),
                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 8))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 36,
                    padding: const EdgeInsets.only(left: 14, right: 6),
                    decoration: BoxDecoration(color: c.panelAlt, border: Border(bottom: BorderSide(color: c.border))),
                    child: Row(
                      children: [
                        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
                        IconBtn(icon: Ic.x, onTap: () => Navigator.of(ctx).pop()),
                      ],
                    ),
                  ),
                  Flexible(child: body(ctx)),
                ],
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
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 3, height: 18, color: error ? c.ng : c.accent, margin: const EdgeInsets.only(right: 10, top: 1)),
                Expanded(child: Text(message, style: TextStyle(color: c.text))),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (cancel != null) ...[
                  FlatButton(label: cancel, onTap: () => Navigator.of(ctx).pop(false)),
                  const SizedBox(width: 8),
                ],
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
