part of 'check_view.dart';

enum _Dock { files, models, directions, detail, ai }

/// Kept by CheckView when a resized window temporarily uses the compact view.
class _WorkspaceLayout {
  _Dock? dock;
  double width = 340;
  bool initialized = false;
  CompareRow? selected;
  bool advanced = false;
  int? tourStep;
}

class _DesktopWorkspace extends StatefulWidget {
  const _DesktopWorkspace({
    required this.state,
    required this.layout,
    required this.search,
    required this.rows,
    required this.columns,
  });
  final AppState state;
  final _WorkspaceLayout layout;
  final TextEditingController search;
  final ScrollController rows, columns;
  @override
  State<_DesktopWorkspace> createState() => _DesktopWorkspaceState();
}

class _DesktopWorkspaceState extends State<_DesktopWorkspace> {
  final _searchFocus = FocusNode();
  AppState get state => widget.state;
  _WorkspaceLayout get layout => widget.layout;
  void open(_Dock? dock) =>
      setState(() => layout.dock = layout.dock == dock ? null : dock);
  void inspect(CompareRow row) {
    setState(() => layout.dock = _Dock.detail);
    state.select(row);
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  Widget command(
    BuildContext context,
    String label,
    VoidCallback? action, {
    Key? key,
    Lucide? icon,
    bool primary = false,
  }) => PillButton(
    key: key,
    label: label,
    icon: icon,
    onTap: action,
    kind: primary ? PillKind.primary : PillKind.ghost,
    height: Metrics.of(context).touch ? 44 : 32,
    fontSize: 12,
    padding: const EdgeInsets.symmetric(horizontal: 10),
  );

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context), s = Strings.of(context);
    final report = state.report;
    final busy = state.localBusy || state.cloudRunning;
    if (!layout.initialized) {
      layout.initialized = true;
      layout.dock = state.ready ? null : _Dock.files;
    }
    if (layout.tourStep != state.tourStep) {
      layout.tourStep = state.tourStep;
      if (state.tourStep case 1 || 2 || 3) {
        layout.dock = _Dock.files;
      } else if (state.tourStep == 5) {
        layout.dock = _Dock.models;
      } else if (state.tourStep != null) {
        layout.dock = null;
      }
    }
    if (!identical(layout.selected, state.selected)) {
      layout.selected = state.selected;
      if (state.selected != null) {
        layout.dock = _Dock.detail;
      } else if (layout.dock == _Dock.detail) {
        layout.dock = null;
      }
    }
    if (widget.search.text != state.search) widget.search.text = state.search;
    final usage = report?.localModel ?? (busy ? state.currentLocalUsage : null);
    final modelState =
        usage?.state ??
        (state.localAnalysisRequired && !state.localAnalysisReady
            ? 'unavailable'
            : 'idle');
    final localLabel = usage == null
        ? s.t(
            state.localAnalysisRequired && !state.localAnalysisReady
                ? 'ws_model_unavailable'
                : 'ws_models',
          )
        : usage.kind == 'analysis'
        ? s.t('ws_model_${usage.state}', {'n': usage.rows, 'all': usage.total})
        : '${usage.model} · ${s.t('local_state_${usage.state}')}';
    final directions =
        report?.rows.where((r) => r.orientation.isNotEmpty).toList() ??
        <CompareRow>[];
    final touch = Metrics.of(context).touch;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.escape): () => setState(() {
          layout.dock = null;
          state.select(null);
        }),
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const ValueKey('workspace-toolbar'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: c.solid,
              border: Border.symmetric(
                horizontal: BorderSide(color: c.lineStrong),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        command(
                          context,
                          s.t('ws_files', {'n': state.loadedCount}),
                          () => open(_Dock.files),
                          key: tourTargets.fileChecks,
                          icon: Lucide.fileCheck,
                        ),
                        const SizedBox(width: 4),
                        command(
                          context,
                          s.t('btn_run'),
                          state.ready && !busy
                              ? () {
                                  setState(() => layout.dock = null);
                                  runCheck(context, state);
                                }
                              : null,
                          key: tourTargets.runButton,
                          icon: Lucide.play,
                          primary: true,
                        ),
                        const SizedBox(width: 8),
                        KeyedSubtree(
                          key: tourTargets.modeSelector,
                          child: DropdownSelect<CheckMode>(
                            width: 118,
                            flat: true,
                            value: state.settings.checkMode,
                            options: [
                              for (final m in CheckMode.values)
                                (m, s.t('mode_${m.name}')),
                            ],
                            onChanged: busy
                                ? null
                                : (m) {
                                    state.setCheckMode(m);
                                    if (m != CheckMode.local &&
                                        !state.cloudReady) {
                                      state.openSettings(SettingsSection.ai);
                                    }
                                  },
                          ),
                        ),
                        command(
                          context,
                          s.t('btn_export_excel'),
                          state.canExportReport
                              ? () => exportReport(context, state)
                              : null,
                          key: tourTargets.checkExport,
                          icon: Lucide.download,
                        ),
                        GlassButton(
                          size: touch ? 44 : 30,
                          iconSize: 14,
                          icon: Lucide.trash,
                          tooltip: s.t('btn_clear'),
                          onTap: busy ? null : state.clearAll,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Hoverable(
                  tooltip: localLabel,
                  builder: (context, hover, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      command(
                        context,
                        usage?.state == 'done'
                            ? usage!.kind == 'analysis'
                                  ? 'AI ✓ ${usage.rows}/${usage.total}'
                                  : 'Embedding ✓ ${usage.texts}'
                            : 'AI ${s.t('local_state_$modelState')}',
                        () => open(_Dock.models),
                        key: tourTargets.localModels,
                        icon: Lucide.sparkles,
                      ),
                      command(
                        context,
                        s.t('ws_directions', {'n': directions.length}),
                        () => open(_Dock.directions),
                        key: const ValueKey('workspace-directions'),
                        icon: Lucide.alert,
                      ),
                      if (state.settings.checkMode != CheckMode.local)
                        command(context, 'AI', () => open(_Dock.ai)),
                      if (busy)
                        command(
                          context,
                          s.t('dlg_cancel'),
                          state.localBusy
                              ? state.cancelLocalAnalysis
                              : state.cancelCloud,
                          icon: Lucide.x,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (report != null) _filters(context),
          if (layout.advanced && report != null) _advanced(context),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final dockWidth = layout.width.clamp(
                  280.0,
                  math.max(280.0, math.min(480.0, box.maxWidth - 520)),
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: KeyedSubtree(
                        key: const ValueKey('check-results-viewport'),
                        child: report == null
                            ? _empty(context)
                            : _table(context),
                      ),
                    ),
                    if (layout.dock != null) ...[
                      Semantics(
                        label: s.t('ws_resize'),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            key: const ValueKey('workspace-splitter'),
                            onHorizontalDragUpdate: (d) => setState(
                              () =>
                                  layout.width = (dockWidth - d.delta.dx).clamp(
                                    280.0,
                                    math.max(
                                      280.0,
                                      math.min(480.0, box.maxWidth - 520),
                                    ),
                                  ),
                            ),
                            child: Container(width: 5, color: c.line),
                          ),
                        ),
                      ),
                      SizedBox(
                        key: const ValueKey('workspace-inspector'),
                        width: dockWidth.toDouble(),
                        child: _inspector(context, directions),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters(BuildContext context) {
    final c = AppTheme.of(context),
        s = Strings.of(context),
        report = state.report!;
    return Container(
      key: const ValueKey('workspace-filters'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        key: tourTargets.checkFilters,
        children: [
          SizedBox(
            width: 190,
            child: PillSearch(
              controller: widget.search,
              focusNode: _searchFocus,
              height: Metrics.of(context).touch ? 44 : 30,
              hint: '${s.t('search_hint')}  Ctrl+F',
              onChanged: state.setSearch,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              key: tourTargets.checkCards,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final st in <CheckStatus?>[null, ...CheckStatus.values])
                    Hoverable(
                      key: ValueKey('workspace-filter-${st?.name ?? 'all'}'),
                      onTap: () => state.setFilter(st),
                      tooltip: st == null
                          ? s.t('filter_all')
                          : s.t('verdict_${st.name}'),
                      builder: (context, hover, _) => Container(
                        height: Metrics.of(context).touch ? 44 : 30,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        decoration: BoxDecoration(
                          color: state.filter == st
                              ? c.blueTint
                              : hover
                              ? c.hover
                              : null,
                          border: state.filter == st
                              ? Border(
                                  bottom: BorderSide(color: c.blue, width: 2),
                                )
                              : null,
                        ),
                        child: Text(
                          '${st == null ? s.t('filter_all') : statusLabel(s, st)} ${st == null ? report.rows.length : report.count(st)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: state.filter == st
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: st == null ? c.tx : statusText(c, st),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          command(
            context,
            s.t('ws_filters') +
                (state.riskFilter != null || state.reasonFilter != null
                    ? ' •'
                    : ''),
            () => setState(() => layout.advanced = !layout.advanced),
          ),
          const SizedBox(width: 6),
          Text(
            '${state.visibleRows().length} / ${report.rows.length}',
            style: TextStyle(fontSize: 11, color: c.tx3),
          ),
        ],
      ),
    );
  }

  Widget _advanced(BuildContext context) {
    final s = Strings.of(context);
    final reasons = state.report!.rows.expand((r) => r.reasons).toSet().toList()
      ..sort();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          DropdownSelect<Risk?>(
            value: state.riskFilter,
            width: 160,
            options: [
              (null, s.t('risk_all')),
              for (final r in Risk.values) (r, s.t('risk_${r.name}')),
            ],
            onChanged: state.setRiskFilter,
          ),
          DropdownSelect<String?>(
            value: state.reasonFilter,
            width: 260,
            options: [
              (null, s.t('reason_all')),
              ('orientation', s.t('orientation_filter')),
              for (final r in reasons) (r, s.t('reason_$r')),
            ],
            onChanged: state.setReasonFilter,
          ),
          command(context, s.t('ws_reset_filters'), () {
            state.setFilter(null);
            state.setRiskFilter(null);
            state.setReasonFilter(null);
            state.setSearch('');
          }),
        ],
      ),
    );
  }

  Widget _table(BuildContext context) {
    final c = AppTheme.of(context),
        s = Strings.of(context),
        rows = state.visibleRows();
    return KeyedSubtree(
      key: tourTargets.checkTable,
      child: LayoutBuilder(
        builder: (context, box) {
          final width = math.max(1160.0, box.maxWidth);
          return ThinScrollbar(
            controller: widget.columns,
            horizontal: true,
            child: SingleChildScrollView(
              key: const PageStorageKey('check-table-columns'),
              controller: widget.columns,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Column(
                  children: [
                    Container(
                      height: 30,
                      color: c.well,
                      child: _sheetRow(
                        [
                              '#',
                              s.t('f_part_no'),
                              s.t('f_result'),
                              s.t('f_desc_both'),
                              s.t('f_qty_both'),
                              s.t('f_refs'),
                              s.t('ws_issues'),
                              s.t('orientation_title'),
                            ]
                            .map(
                              (t) => Text(
                                t,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: c.tx2,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    Expanded(
                      child: rows.isEmpty
                          ? EmptyState(
                              icon: Lucide.search,
                              text: s.t('empty_filter'),
                            )
                          : ThinScrollbar(
                              controller: widget.rows,
                              child: ListView.builder(
                                key: const PageStorageKey('check-table-rows'),
                                controller: widget.rows,
                                itemCount: rows.length,
                                itemBuilder: (context, i) {
                                  final r = rows[i],
                                      selected = identical(
                                        state.selected,
                                        rows[i],
                                      );
                                  final qty = r.field('quantity');
                                  final issue = _rowExplanation(s, r);
                                  Widget txt(
                                    String t, {
                                    Color? color,
                                    bool bold = false,
                                  }) => Text(
                                    t.isEmpty ? '—' : t,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.35,
                                      color: color ?? c.tx,
                                      fontWeight: bold
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  );
                                  return Hoverable(
                                    onTap: () =>
                                        selected && layout.dock == _Dock.detail
                                        ? state.select(null)
                                        : inspect(r),
                                    tooltip:
                                        '${r.partNo}\n${s.t('verdict_${r.status.name}')}\n$issue',
                                    builder: (context, hover, _) => Container(
                                      constraints: BoxConstraints(
                                        minHeight: Metrics.of(context).touch
                                            ? 60
                                            : 54,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? c.blueTint
                                            : hover
                                            ? c.hover
                                            : c.card,
                                        border: Border(
                                          bottom: BorderSide(color: c.line),
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6,
                                      ),
                                      child: _sheetRow([
                                        txt('${i + 1}', color: c.tx3),
                                        txt(r.partNo, bold: true),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 3,
                                          ),
                                          color: statusTint(c, r.status),
                                          child: txt(
                                            s.t('table_${r.status.name}'),
                                            color: statusText(c, r.status),
                                            bold: true,
                                          ),
                                        ),
                                        _sides(
                                          context,
                                          r.field('description'),
                                          single: r.description,
                                        ),
                                        txt(
                                          qty == null
                                              ? formatQuantity(
                                                  r.single?.quantity ??
                                                      r.merged?.quantity,
                                                )
                                              : qty.equal
                                              ? qty.single
                                              : '${qty.single} / ${qty.merged}',
                                          color: qty?.equal == false
                                              ? c.ngTx
                                              : c.tx,
                                        ),
                                        txt(
                                          (r.single?.refs ??
                                                  r.merged?.refs ??
                                                  [])
                                              .join(', '),
                                          color: r.field('refs')?.equal == false
                                              ? c.ngTx
                                              : c.tx2,
                                        ),
                                        txt(
                                          issue,
                                          color: r.status == CheckStatus.pass
                                              ? c.tx2
                                              : statusText(c, r.status),
                                        ),
                                        r.orientation.isEmpty
                                            ? txt('—', color: c.tx3)
                                            : txt(
                                                r.orientation
                                                    .map(
                                                      (h) => s.t(
                                                        'orientation_short_${h.code}',
                                                      ),
                                                    )
                                                    .join('；'),
                                                color: c.warnTx,
                                              ),
                                      ]),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sheetRow(List<Widget> cells) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      for (var i = 0; i < cells.length; i++)
        Expanded(
          flex: const [3, 17, 11, 27, 7, 15, 23, 20][i],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: cells[i],
          ),
        ),
    ],
  );

  Widget _empty(BuildContext context) {
    final c = AppTheme.of(context), s = Strings.of(context);
    final running = state.localBusy || state.cloudRunning;
    final error = state.localStatus == LocalStatus.failed
        ? '${s.t('local_analysis_no_result')}\n${s.t(state.localError)}'
        : state.cloudError.isEmpty
        ? ''
        : s.t(state.cloudError);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (running)
                const Spinner(size: 24)
              else
                LucideIcon(
                  error.isEmpty ? Lucide.clipboardCheck : Lucide.alert,
                  size: 30,
                  color: error.isEmpty ? c.tx3 : c.ngTx,
                ),
              const SizedBox(height: 16),
              Text(
                running
                    ? s.t(
                        state.localLoading
                            ? 'status_local_required_loading'
                            : state.localBusy
                            ? 'status_local_required_running'
                            : 'cloud_starting',
                      )
                    : error.isNotEmpty
                    ? error
                    : s.t(state.ready ? 'empty_ready' : 'empty_check_import'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.5, color: c.tx2),
              ),
              if (state.localBusy) ...[
                const SizedBox(height: 12),
                TrackBar(value: state.localProgress, color: c.blue),
                const SizedBox(height: 8),
                Text(
                  s.t('local_analysis_counts', {
                    'n': state.localRows,
                    'all': state.localTotal,
                    'b': state.localCalls,
                    'ms': state.localMillis,
                  }),
                  style: TextStyle(fontSize: 12, color: c.tx2),
                ),
              ],
              if (state.cloudRunning) ...[
                const SizedBox(height: 8),
                Text(
                  s.t('cloud_full_running', {
                    'done': state.cloudRun?.batchesDone ?? 0,
                    'all': state.cloudRun?.batches ?? 0,
                  }),
                  style: TextStyle(fontSize: 12, color: c.tx2),
                ),
              ],
              const SizedBox(height: 16),
              command(
                context,
                s.t(
                  running
                      ? 'dlg_cancel'
                      : state.ready
                      ? 'ws_models'
                      : 'files_expand',
                ),
                running
                    ? state.localBusy
                          ? state.cancelLocalAnalysis
                          : state.cancelCloud
                    : () => open(state.ready ? _Dock.models : _Dock.files),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inspector(BuildContext context, List<CompareRow> directions) {
    final c = AppTheme.of(context), s = Strings.of(context);
    return ColoredBox(
      color: c.solid,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.lineStrong)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final d in _Dock.values)
                          if (d != _Dock.ai ||
                              state.settings.checkMode != CheckMode.local)
                            Hoverable(
                              onTap: () => setState(() => layout.dock = d),
                              builder: (context, hover, _) => Container(
                                height: Metrics.of(context).touch ? 44 : 32,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: layout.dock == d
                                      ? c.blueTint
                                      : hover
                                      ? c.hover
                                      : null,
                                  border: layout.dock == d
                                      ? Border(
                                          bottom: BorderSide(
                                            color: c.blue,
                                            width: 2,
                                          ),
                                        )
                                      : null,
                                ),
                                child: Text(
                                  s.t('ws_tab_${d.name}'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: layout.dock == d ? c.blueTx : c.tx2,
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                GlassButton(
                  key: const ValueKey('workspace-close'),
                  icon: Lucide.x,
                  size: 30,
                  iconSize: 14,
                  tooltip: s.t('dlg_close'),
                  onTap: () => open(layout.dock),
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (layout.dock!) {
              _Dock.detail =>
                state.selected == null
                    ? EmptyState(
                        icon: Lucide.clipboardCheck,
                        text: s.t('ws_select_row'),
                      )
                    : _Detail(state: state),
              _Dock.files => ListView(
                padding: const EdgeInsets.all(10),
                children: [
                  for (final card in importCards(context, state))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: card,
                    ),
                  if (state.report != null) _ColumnsNote(report: state.report!),
                ],
              ),
              _Dock.models => SingleChildScrollView(
                padding: const EdgeInsets.all(10),
                child: LocalModelIndicator(
                  state: state,
                  compact: true,
                  alwaysExpanded: true,
                  registerTour: false,
                ),
              ),
              _Dock.ai => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: AiSwitch(state: state),
                  ),
                  Expanded(child: _AiPanel(state: state)),
                ],
              ),
              _Dock.directions => ListView(
                key: const PageStorageKey('workspace-direction-list'),
                padding: const EdgeInsets.all(12),
                children: [
                  Text(
                    s.t('orientation_scope'),
                    style: TextStyle(fontSize: 12, height: 1.5, color: c.tx2),
                  ),
                  const SizedBox(height: 8),
                  command(
                    context,
                    s.t('orientation_filter'),
                    () => state.setReasonFilter(
                      state.reasonFilter == 'orientation'
                          ? null
                          : 'orientation',
                    ),
                    key: const ValueKey('workspace-direction-filter'),
                    primary: state.reasonFilter == 'orientation',
                  ),
                  if (directions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        s.t(
                          state.report == null
                              ? 'orientation_wait'
                              : 'orientation_none',
                        ),
                        style: TextStyle(color: c.tx2),
                      ),
                    ),
                  for (final r in directions)
                    Hoverable(
                      onTap: () => inspect(r),
                      builder: (context, hover, _) => Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: hover ? c.hover : null,
                          border: Border(bottom: BorderSide(color: c.line)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.partNo,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: c.tx,
                              ),
                            ),
                            for (final h in r.orientation) ...[
                              const SizedBox(height: 5),
                              Text(
                                s.t('orientation_${h.code}'),
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: c.warnTx,
                                ),
                              ),
                              Text(
                                h.refs.isEmpty
                                    ? s.t('orientation_no_refs')
                                    : h.refs.join(', '),
                                style: TextStyle(fontSize: 12, color: c.tx2),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            },
          ),
        ],
      ),
    );
  }
}
