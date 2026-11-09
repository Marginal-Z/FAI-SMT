/// Retry a truncated batch as smaller independent requests. Partial JSON is
/// never consumed; successful siblings remain available when a leaf fails.
library;

import 'provider.dart';

Future<void> adaptiveCloudBatch<T>(
  List<T> items, {
  required Future<CloudReply> Function(List<T>) request,
  required void Function(List<T>, CloudReply) onReply,
  required void Function(List<T>, CloudException) onError,
  void Function(CloudException)? onSplit,
  CloudCancel? cancel,
}) async {
  if (cancel?.cancelled ?? false) return;
  try {
    final reply = await request(items);
    if (cancel?.cancelled ?? false) return;
    onReply(items, reply);
  } on CloudException catch (e) {
    if (e.code != 'truncated' ||
        items.length <= 1 ||
        (cancel?.cancelled ?? false)) {
      onError(items, e);
      return;
    }
    onSplit?.call(e);
    final middle = items.length ~/ 2;
    for (final half in [items.sublist(0, middle), items.sublist(middle)]) {
      await adaptiveCloudBatch(
        half,
        request: request,
        onReply: onReply,
        onError: onError,
        onSplit: onSplit,
        cancel: cancel,
      );
    }
  }
}
