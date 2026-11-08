/// Counterparts for lines the rules left unmatched, proposed by the local
/// embedding model. A proposal is kept only when the two lines are each
/// other's best match, clearly ahead of the next candidate, of compatible
/// kinds and without conflicting parameters; even then the line is REVIEW,
/// never PASS.
library;

import 'dart:isolate';

import '../bom.dart';
import '../bom_compare.dart';
import '../params.dart';
import 'local_ai.dart';

double _dot(List<double> a, List<double> b) {
  var s = 0.0;
  for (var i = 0; i < a.length && i < b.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

String _text(BomPart p) => [if (p.kind != ItemKind.unknown) p.kind.name, p.description, if ((p.extra['mpn'] ?? '').isNotEmpty) p.extra['mpn']!].join(' ');

/// Proposals for [first]'s unmatched lines. Descriptions are embedded in
/// batches (progress 0–1 to [onProgress], stopped by [cancelled]); the
/// similarity search runs on a worker isolate and only compares items of
/// compatible kinds.
Future<SemanticSuggestions> semanticSuggestions(
  CompareReport first,
  LocalModels ai, {
  double minSimilarity = 0.85,
  double margin = 0.03,
  void Function(double)? onProgress,
  bool Function()? cancelled,
}) async {
  final left = [for (final r in first.rows) if (r.status == CheckStatus.unmatched && r.single != null) r.single!];
  final right = [for (final r in first.rows) if (r.status == CheckStatus.unmatched && r.merged != null) r.merged!];
  if (left.isEmpty || right.isEmpty) return const {};
  final texts = [for (final p in [...left, ...right]) _text(p)];
  final vectors = <List<double>>[];
  const batch = 128;
  for (var i = 0; i < texts.length; i += batch) {
    if (cancelled?.call() ?? false) return const {};
    vectors.addAll(await ai.embed(texts.sublist(i, i + batch > texts.length ? texts.length : i + batch)));
    onProgress?.call(vectors.length / texts.length);
  }
  final vl = vectors.sublist(0, left.length), vr = vectors.sublist(left.length);
  final kl = [for (final p in left) p.kind.index], kr = [for (final q in right) q.kind.index];
  final unknown = ItemKind.unknown.index;
  // Best counterpart of each side, on a worker.
  final (bestR, bestL) = await Isolate.run(() => _bestMatches(vl, vr, kl, kr, unknown));
  final out = <String, (String, double)>{};
  for (var i = 0; i < left.length; i++) {
    final (j, s1, s2) = bestR[i];
    if (j < 0 || s1 < minSimilarity || s1 - s2 < margin || bestL[j] != i) continue;
    final p = left[i], q = right[j];
    if (compareParams(p.description, q.description).verdict == ParamVerdict.conflict) continue;
    out[p.partNo] = (q.partNo, s1);
  }
  return out;
}

/// For each left vector the best right one (index, score, second score) and
/// for each right vector its best left one, comparing only compatible kinds.
(List<(int, double, double)>, List<int>) _bestMatches(List<List<double>> vl, List<List<double>> vr, List<int> kl, List<int> kr, int unknown) {
  final bestR = List<(int, double, double)>.filled(vl.length, (-1, -1.0, -1.0));
  final bestLScore = List<double>.filled(vr.length, -1);
  final bestL = List<int>.filled(vr.length, -1);
  for (var i = 0; i < vl.length; i++) {
    var b = -1, s1 = -1.0, s2 = -1.0;
    for (var j = 0; j < vr.length; j++) {
      if (kl[i] != kr[j] && kl[i] != unknown && kr[j] != unknown) continue;
      final s = _dot(vl[i], vr[j]);
      if (s > s1) {
        s2 = s1;
        s1 = s;
        b = j;
      } else if (s > s2) {
        s2 = s;
      }
      if (s > bestLScore[j]) {
        bestLScore[j] = s;
        bestL[j] = i;
      }
    }
    bestR[i] = (b, s1, s2);
  }
  return (bestR, bestL);
}
