/// Counterparts for lines the rules left unmatched, proposed by the local
/// embedding model. A proposal is kept only when the two lines are each
/// other's best match, clearly ahead of the next candidate, of compatible
/// kinds and without conflicting parameters; even then the line is REVIEW,
/// never PASS.
library;

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

Future<SemanticSuggestions> semanticSuggestions(CompareReport first, LocalModels ai, {double minSimilarity = 0.85, double margin = 0.03}) async {
  final left = [for (final r in first.rows) if (r.status == CheckStatus.unmatched && r.single != null) r.single!];
  final right = [for (final r in first.rows) if (r.status == CheckStatus.unmatched && r.merged != null) r.merged!];
  if (left.isEmpty || right.isEmpty) return const {};
  final vectors = await ai.embed([for (final p in [...left, ...right]) _text(p)]);
  final vl = vectors.sublist(0, left.length), vr = vectors.sublist(left.length);
  // Best and second-best on each side.
  final bestR = <int, (int, double, double)>{};
  for (var i = 0; i < left.length; i++) {
    var b = -1, s1 = -1.0, s2 = -1.0;
    for (var j = 0; j < right.length; j++) {
      final s = _dot(vl[i], vr[j]);
      if (s > s1) {
        s2 = s1;
        s1 = s;
        b = j;
      } else if (s > s2) {
        s2 = s;
      }
    }
    bestR[i] = (b, s1, s2);
  }
  final bestL = <int, int>{};
  for (var j = 0; j < right.length; j++) {
    var b = -1, s1 = -1.0;
    for (var i = 0; i < left.length; i++) {
      final s = _dot(vl[i], vr[j]);
      if (s > s1) {
        s1 = s;
        b = i;
      }
    }
    bestL[j] = b;
  }
  final out = <String, (String, double)>{};
  for (final e in bestR.entries) {
    final (j, s1, s2) = e.value;
    if (j < 0 || s1 < minSimilarity || s1 - s2 < margin || bestL[j] != e.key) continue;
    final p = left[e.key], q = right[j];
    final kindsOk = p.kind == q.kind || p.kind == ItemKind.unknown || q.kind == ItemKind.unknown;
    if (!kindsOk || compareParams(p.description, q.description).verdict == ParamVerdict.conflict) continue;
    out[p.partNo] = (q.partNo, s1);
  }
  return out;
}
