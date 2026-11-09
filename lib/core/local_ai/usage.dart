/// A snapshot of actual embedding use for one check, preserved in its report.
class LocalModelUsage {
  const LocalModelUsage({
    this.state = 'disabled',
    this.model = '',
    this.texts = 0,
    this.paired = 0,
    this.millis = 0,
    this.error = '',
  });
  final String state;
  final String model;
  final int texts;
  final int paired;
  final int millis;
  final String error;
  Map<String, dynamic> toJson() => {
    'state': state,
    'model': model,
    'texts': texts,
    'paired': paired,
    'millis': millis,
    'error': error,
  };
  factory LocalModelUsage.fromJson(Map<String, dynamic> j) => LocalModelUsage(
    state: '${j['state'] ?? 'unknown'}',
    model: '${j['model'] ?? ''}',
    texts: (j['texts'] as num?)?.toInt() ?? 0,
    paired: (j['paired'] as num?)?.toInt() ?? 0,
    millis: (j['millis'] as num?)?.toInt() ?? 0,
    error: '${j['error'] ?? ''}',
  );
}
