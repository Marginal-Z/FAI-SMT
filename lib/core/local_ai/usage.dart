/// Actual language analysis or embedding use, preserved with the report.
class LocalModelUsage {
  const LocalModelUsage({
    this.state = 'disabled',
    this.model = '',
    this.texts = 0,
    this.paired = 0,
    this.millis = 0,
    this.error = '',
    this.kind = 'embedding',
    this.rows = 0,
    this.total = 0,
    this.calls = 0,
  });
  final String state;
  final String model;
  final int texts;
  final int paired;
  final int millis;
  final String error;
  final String kind;
  final int rows;
  final int total;
  final int calls;
  Map<String, dynamic> toJson() => {
    'state': state,
    'model': model,
    'texts': texts,
    'paired': paired,
    'millis': millis,
    'error': error,
    'kind': kind, 'rows': rows, 'total': total, 'calls': calls,
  };
  factory LocalModelUsage.fromJson(Map<String, dynamic> j) => LocalModelUsage(
    state: '${j['state'] ?? 'unknown'}',
    model: '${j['model'] ?? ''}',
    texts: (j['texts'] as num?)?.toInt() ?? 0,
    paired: (j['paired'] as num?)?.toInt() ?? 0,
    millis: (j['millis'] as num?)?.toInt() ?? 0,
    error: '${j['error'] ?? ''}',
    kind: '${j['kind'] ?? 'embedding'}',
    rows: (j['rows'] as num?)?.toInt() ?? 0,
    total: (j['total'] as num?)?.toInt() ?? 0,
    calls: (j['calls'] as num?)?.toInt() ?? 0,
  );
}
