/// The next check's local model preference, separate from recorded usage.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/local_ai/model_store.dart';
import '../core/settings.dart';
import '../l10n/strings.dart';
import 'design.dart';
import 'theme.dart';
import 'widgets.dart';

class LocalModelControls extends StatelessWidget {
  const LocalModelControls({
    super.key,
    required this.state,
    this.manage = true,
  });

  final AppState state;
  final bool manage;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final c = AppTheme.of(context);
    final on = state.settings.localAiEnabled;
    final cloudOnly = state.settings.checkMode == CheckMode.cloudFull;
    final canToggle =
        !state.localBusy && !cloudOnly && (state.localModelsReady || on);
    final hint = state.localBusy
        ? 'local_wait'
        : cloudOnly
        ? 'local_state_cloudOnly'
        : !state.localModelsReady
        ? 'local_selected_unavailable'
        : state.report != null
        ? 'local_next_check'
        : 'local_usage_hint';

    final toggle = _ModelToggle(
      value: on,
      label: s.t('local_use'),
      onTap: canToggle ? () => state.setLocalAiEnabled(!on) : null,
    );
    final note = Text(
      s.t(hint),
      style: TextStyle(fontSize: 11.5, height: 1.4, color: c.tx2),
    );
    final manager = PillButton(
      label: s.t('local_manage'),
      kind: PillKind.ghost,
      height: 44,
      onTap: () => state.openSettings(SettingsSection.localAi),
    );
    final choice = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          s.t('local_pick_title'),
          style: TextStyle(fontSize: 12, color: c.tx2),
        ),
        const SizedBox(height: 4),
        DropdownSelect<String>(
          key: const ValueKey('local-model-choice'),
          value: state.activeEmbedding.id,
          width: double.infinity,
          flat: true,
          optionMaxLines: 3,
          options: [
            for (final m in embeddingModels)
              (
                m.id,
                '${m.name} · ${s.t(_statusKey(state.modelStatus[m.id]?.state))}',
              ),
          ],
          onChanged: state.localBusy
              ? null
              : (id) => state.setEmbeddingModel(embeddingModel(id)),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 700) {
          return Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [toggle, note],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(flex: 4, child: choice),
              if (manage) ...[const SizedBox(width: 16), manager],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            toggle,
            const SizedBox(height: 4),
            choice,
            const SizedBox(height: 6),
            note,
            if (manage) ...[const SizedBox(height: 4), manager],
          ],
        );
      },
    );
  }

  String _statusKey(ModelState? status) => switch (status) {
    ModelState.ready => 'model_ready',
    ModelState.downloading => 'local_choice_downloading',
    ModelState.verifying => 'local_choice_verifying',
    ModelState.failed => 'local_choice_failed',
    _ => 'model_missing',
  };
}

class _ModelToggle extends StatefulWidget {
  const _ModelToggle({
    required this.value,
    required this.label,
    required this.onTap,
  });
  final bool value;
  final String label;
  final VoidCallback? onTap;

  @override
  State<_ModelToggle> createState() => _ModelToggleState();
}

class _ModelToggleState extends State<_ModelToggle> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Semantics(
      key: const ValueKey('local-model-toggle'),
      label: widget.label,
      toggled: widget.value,
      enabled: widget.onTap != null,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: widget.onTap != null,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        child: Hoverable(
          onTap: widget.onTap,
          builder: (context, hover, _) => Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: hover ? c.hover : null,
              borderRadius: c.r(8),
              border: _focused ? Border.all(color: c.blue) : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: c.tx,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Opacity(
                  opacity: widget.onTap == null ? 0.4 : 1,
                  child: ToggleSwitch(value: widget.value),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
