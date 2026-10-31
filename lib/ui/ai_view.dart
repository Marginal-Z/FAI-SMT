/// AI check page: files, the request and the connection on one side, the
/// streamed analysis on the other. A separate feature — it never reads or
/// changes the local check results.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';

import '../ai_session.dart';
import '../app_state.dart';
import '../core/settings.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'design.dart';
import 'lucide.dart';
import 'theme.dart';
import 'widgets.dart';

const _tableExts = ['xlsx', 'xlsm', 'xls', 'csv', 'txt'];

class AiView extends StatefulWidget {
  const AiView({super.key, required this.state, this.compact = false});

  final AppState state;
  final bool compact;

  @override
  State<AiView> createState() => _AiViewState();
}

class _AiViewState extends State<AiView> {
  final _request = TextEditingController();
  final _url = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController();
  late AiProvider _provider;
  bool _requestInit = false;
  bool _saved = false;
  bool _dragging = false;
  final _out = ScrollController();

  AiSession get _ai => widget.state.ai;

  @override
  void initState() {
    super.initState();
    final s = widget.state.settings.ai;
    _provider = s.provider;
    _url.text = s.baseUrl;
    _key.text = s.apiKey;
    _model.text = s.model;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requestInit) {
      _requestInit = true;
      final saved = widget.state.settings.ai.prompt;
      _request.text = saved.isNotEmpty ? saved : Strings.of(context).t('ai_request_default');
    }
  }

  @override
  void dispose() {
    for (final c in [_request, _url, _key, _model]) {
      c.dispose();
    }
    _out.dispose();
    super.dispose();
  }

  AiSettings _collect({String? prompt}) => AiSettings(
        provider: _provider,
        baseUrl: _url.text.trim(),
        apiKey: _key.text.trim(),
        model: _model.text.trim(),
        prompt: prompt ?? widget.state.settings.ai.prompt,
      );

  void _saveConnection() {
    _ai.saveSettings(_collect());
    setState(() => _saved = true);
  }

  Future<void> _add() async {
    try {
      final file = await FilePicker.pickFile(dialogTitle: Strings.of(context).t('ai_add_file'), type: FileType.custom, allowedExtensions: _tableExts);
      if (file == null) return;
      _ai.addFile(file.name, await file.xFile.readAsBytes());
    } catch (e) {
      if (mounted) await showError(context, e);
    }
  }

  void _run() {
    final s = Strings.of(context);
    try {
      // Unsaved connection edits are used (and kept) for this run.
      _ai.saveSettings(_collect());
      _ai.run(system: s.t('ai_system'), request: _request.text.trim().isEmpty ? s.t('ai_request_default') : _request.text.trim());
    } catch (e) {
      showError(context, e);
    }
  }

  Future<void> _export() async {
    final name = _ai.files.isEmpty ? 'AI' : _ai.files.first.name.replaceAll(RegExp(r'\.[^.]+$'), '');
    await saveFile(context, '${name}_AI.md', Uint8List.fromList(utf8.encode(_ai.output)), ['md']);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final phone = isPhoneLayout(context);
    final narrow = widget.compact;
    final ai = _ai;

    final title = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!phone) Text(s.t('mod_ai'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: c.tx)),
      if (!phone) const SizedBox(height: 4),
      Text(s.t('ai_sub'), style: TextStyle(fontSize: 13.5, color: c.tx2)),
    ]);

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 10),
          child: Text(t, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.tx2)),
        );

    // ---- Files
    Widget filesCard = SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      borderColor: _dragging ? c.blue : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(s.t('ai_files'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.tx))),
          PillButton(label: s.t('ai_add_file'), icon: Lucide.plus, height: 32, fontSize: 13, onTap: ai.running ? null : _add),
        ]),
        const SizedBox(height: 6),
        if (ai.files.isEmpty) Text(s.t('ai_files_hint', {'n': AiSession.maxFiles}), style: TextStyle(fontSize: 12.5, color: c.tx3)),
        for (final f in ai.files)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              LucideIcon(Lucide.fileText, size: 15, color: c.tx2),
              const SizedBox(width: 8),
              Expanded(child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.tx))),
              Text(formatSize(f.size), style: TextStyle(fontSize: 12, color: c.tx3)),
              const SizedBox(width: 4),
              Hoverable(
                onTap: ai.running ? null : () => ai.removeFile(f),
                tooltip: s.t('file_remove'),
                builder: (context, hover, _) => Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: hover ? c.hover : null, shape: BoxShape.circle),
                  child: LucideIcon(Lucide.x, size: 14, color: c.tx2),
                ),
              ),
            ]),
          ),
      ]),
    );
    if (dropSupported) {
      filesCard = DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (detail) async {
          setState(() => _dragging = false);
          for (final file in detail.files) {
            final ext = file.name.split('.').last.toLowerCase();
            try {
              if (!_tableExts.contains(ext)) throw UserMessage('msg_bad_drop', {'ext': '.$ext', 'allowed': _tableExts.map((e) => '.$e').join(' / ')});
              ai.addFile(file.name, await file.readAsBytes());
            } catch (e) {
              if (context.mounted) await showError(context, e);
              break;
            }
          }
        },
        child: filesCard,
      );
    }

    // ---- Request
    final requestCard = SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        label(s.t('ai_request')),
        TextInput(controller: _request, maxLines: 6),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FlatButton(label: s.t('ai_save_request'), compact: true, onTap: () => ai.saveSettings(_collect(prompt: _request.text.trim()))),
          FlatButton(
            label: s.t('ai_reset_request'),
            compact: true,
            onTap: () {
              _request.text = s.t('ai_request_default');
              ai.saveSettings(_collect(prompt: ''));
            },
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: ai.running
                ? PillButton(label: s.t('ai_stop'), icon: Lucide.stop, kind: PillKind.soft, height: 42, onTap: ai.stop)
                : PillButton(label: s.t('ai_run'), icon: Lucide.sparkles, kind: PillKind.primary, height: 42, onTap: ai.files.isEmpty ? null : _run),
          ),
        ]),
        const SizedBox(height: 8),
        Text(s.t('ai_privacy'), style: TextStyle(fontSize: 12, color: c.tx3, height: 1.4)),
      ]),
    );

    // ---- Connection
    final anthropic = _provider == AiProvider.anthropic;
    final connCard = SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('ai_conn'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.tx)),
        label(s.t('ai_provider')),
        DropdownSelect<AiProvider>(
          value: _provider,
          width: 260,
          flat: true,
          options: [for (final p in AiProvider.values) (p, s.t('ai_provider_${p.name}'))],
          onChanged: (p) => setState(() {
            _provider = p;
            _saved = false;
          }),
        ),
        label(s.t('ai_url')),
        TextInput(controller: _url, hint: s.t(anthropic ? 'ai_url_hint_anthropic' : 'ai_url_hint_openai'), mono: true, onChanged: (_) => setState(() => _saved = false)),
        label(s.t('ai_key')),
        TextInput(controller: _key, obscure: true, mono: true, onChanged: (_) => setState(() => _saved = false)),
        label(s.t('ai_model')),
        TextInput(controller: _model, hint: s.t(anthropic ? 'ai_model_hint_anthropic' : 'ai_model_hint_openai'), mono: true, onChanged: (_) => setState(() => _saved = false)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Text(_saved ? s.t('ai_saved') : s.t('ai_key_note'), style: TextStyle(fontSize: 12, color: _saved ? c.okTx : c.tx3))),
          FlatButton(label: s.t('dlg_save'), compact: true, primary: true, onTap: _saveConnection),
        ]),
      ]),
    );

    // ---- Result
    final status = <Widget>[
      if (ai.running) Text(s.t('ai_running'), style: TextStyle(fontSize: 12.5, color: c.blueTx, fontWeight: FontWeight.w600)),
      if (!ai.running && ai.finishedAt != null && ai.errorKey == null) Text(s.t('ai_done', {'t': formatTime(ai.finishedAt!)}), style: TextStyle(fontSize: 12.5, color: c.okTx)),
      if (ai.errorKey != null) Text(s.t(ai.errorKey!, {'detail': ai.errorDetail}), style: TextStyle(fontSize: 12.5, color: c.ngTx)),
      if (ai.inputTruncated) Text(s.t('ai_input_truncated'), style: TextStyle(fontSize: 12.5, color: c.warnTx)),
      if (ai.outputTruncated) Text(s.t('ai_output_truncated'), style: TextStyle(fontSize: 12.5, color: c.warnTx)),
    ];
    final resultCard = DCard(
      radius: 24,
      clip: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
          child: Row(children: [
            Expanded(child: Text(s.t('ai_result'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.tx))),
            GlassButton(
              icon: Lucide.copy,
              size: 34,
              tooltip: s.t('ai_copy'),
              onTap: ai.output.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: ai.output));
                      if (context.mounted) await showMessage(context, title: s.t('ai_copy'), message: s.t('ai_copied'), ok: s.t('dlg_ok'));
                    },
            ),
            const SizedBox(width: 6),
            GlassButton(icon: Lucide.download, size: 34, tooltip: s.t('ai_export'), onTap: ai.output.isEmpty || ai.running ? null : _export),
            const SizedBox(width: 6),
            GlassButton(icon: Lucide.trash, size: 34, tooltip: s.t('ai_clear'), onTap: ai.running || ai.output.isEmpty ? null : ai.clearOutput),
          ]),
        ),
        if (status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: status),
          ),
        Container(height: 1, color: c.line),
        Expanded(
          child: ai.output.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(ai.running ? s.t('ai_running') : s.t('ai_empty'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.tx2)),
                  ),
                )
              : ThinScrollbar(
                  controller: _out,
                  child: SingleChildScrollView(
                    controller: _out,
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                    child: _Markdown(text: ai.output),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Text(s.t('ai_disclaimer'), style: TextStyle(fontSize: 12, color: c.tx3)),
        ),
      ]),
    );

    final pad = EdgeInsets.fromLTRB(narrow ? 16 : 24, phone ? 4 : 10, narrow ? 16 : 24, 0);
    if (narrow) {
      return ListView(
        padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, bottomInset(context) + 16),
        children: [
          title,
          const SizedBox(height: 14),
          filesCard,
          const SizedBox(height: 12),
          requestCard,
          const SizedBox(height: 12),
          SizedBox(height: 480, child: resultCard),
          const SizedBox(height: 12),
          connCard,
        ],
      );
    }
    return Padding(
      padding: pad,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        title,
        const SizedBox(height: 14),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 400,
              child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
                filesCard,
                const SizedBox(height: 12),
                requestCard,
                const SizedBox(height: 12),
                connCard,
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(child: Padding(padding: EdgeInsets.only(bottom: 16 + bottomInset(context)), child: resultCard)),
          ]),
        ),
      ]),
    );
  }
}

/// Minimal Markdown display: headings, list items and **bold**.
class _Markdown extends StatelessWidget {
  const _Markdown({required this.text});

  final String text;

  static final _bold = RegExp(r'\*\*(.+?)\*\*');

  List<TextSpan> _inline(String line, TextStyle base) {
    final spans = <TextSpan>[];
    var at = 0;
    for (final m in _bold.allMatches(line)) {
      if (m.start > at) spans.add(TextSpan(text: line.substring(at, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
      at = m.end;
    }
    if (at < line.length) spans.add(TextSpan(text: line.substring(at)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final base = TextStyle(fontSize: 13.5, height: 1.55, color: c.tx);
    final children = <Widget>[];
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trimRight();
      final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      if (h != null) {
        final level = h.group(1)!.length;
        children.add(Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 12, bottom: 4),
          child: Text.rich(TextSpan(children: _inline(h.group(2)!, base)), style: base.copyWith(fontSize: level <= 1 ? 18 : (level == 2 ? 16 : 14.5), fontWeight: FontWeight.w700)),
        ));
        continue;
      }
      final li = RegExp(r'^(\s*)([-*•]|\d+[.)])\s+(.*)$').firstMatch(line);
      if (li != null) {
        final indent = (li.group(1)!.length / 2).floor() * 14.0;
        final bullet = RegExp(r'\d').hasMatch(li.group(2)!) ? li.group(2)! : '•';
        children.add(Padding(
          padding: EdgeInsets.only(left: 4 + indent, bottom: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 22, child: Text(bullet, style: base.copyWith(color: c.tx2))),
            Expanded(child: Text.rich(TextSpan(children: _inline(li.group(3)!, base)), style: base)),
          ]),
        ));
        continue;
      }
      if (RegExp(r'^\s*([-*_]\s*){3,}$').hasMatch(line)) {
        children.add(Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Container(height: 1, color: c.line)));
        continue;
      }
      children.add(line.isEmpty ? const SizedBox(height: 8) : Text.rich(TextSpan(children: _inline(line, base)), style: base));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}
