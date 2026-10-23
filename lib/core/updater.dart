/// Update check against the GitHub Releases of the project, and download of
/// the release package that matches this platform and CPU architecture.
library;

import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

const updateRepo = 'Marginal-Z/FAI-SMT';

class ReleaseAsset {
  ReleaseAsset(this.name, this.url, this.size);

  final String name;
  final String url;
  final int size;
}

class ReleaseInfo {
  ReleaseInfo({required this.version, required this.tag, required this.notes, required this.page, required this.assets});

  final String version;
  final String tag;
  final String notes;
  final String page;
  final List<ReleaseAsset> assets;

  factory ReleaseInfo.fromJson(Map<String, dynamic> j) {
    final tag = j['tag_name'] as String? ?? '';
    return ReleaseInfo(
      version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      tag: tag,
      notes: j['body'] as String? ?? '',
      page: j['html_url'] as String? ?? '',
      assets: [
        for (final a in (j['assets'] as List? ?? const []).cast<Map<String, dynamic>>())
          ReleaseAsset(a['name'] as String, a['browser_download_url'] as String, a['size'] as int? ?? 0),
      ],
    );
  }
}

class UpdateException implements Exception {
  UpdateException(this.code, [this.detail = '']);

  /// Localisation key suffix: `network`, `no_release`, `no_asset`, `download`,
  /// `install`, `signature`.
  final String code;
  final String detail;

  @override
  String toString() => 'UpdateException($code) $detail';
}

/// Compares dotted numeric versions: negative when [a] < [b].
int compareVersions(String a, String b) {
  List<int> parts(String v) => v.split(RegExp(r'[.+-]')).map((e) => int.tryParse(e) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// File-name suffix of the release package for an ABI, as produced by CI.
String? packageSuffix(Abi abi) => switch (abi) {
      Abi.windowsX64 => 'windows-x64.zip',
      Abi.windowsArm64 => 'windows-arm64.zip',
      Abi.linuxX64 => 'linux-x64.tar.gz',
      Abi.linuxArm64 => 'linux-arm64.tar.gz',
      Abi.androidArm64 => 'android-arm64-v8a.apk',
      Abi.androidArm => 'android-armeabi-v7a.apk',
      Abi.androidX64 => 'android-x86_64.apk',
      _ => null,
    };

/// Package for [abi]. [installer]: the app was installed with the Windows
/// setup program, so the update runs the new setup (it upgrades in place and
/// keeps the shortcuts and uninstall entry current).
ReleaseAsset? pickAsset(ReleaseInfo release, Abi abi, {bool installer = false}) {
  final suffix = packageSuffix(abi);
  if (suffix == null) return null;
  if (installer && suffix.endsWith('.zip')) {
    final setup = suffix.replaceAll('.zip', '-setup.exe');
    for (final a in release.assets) {
      if (a.name.endsWith(setup)) return a;
    }
  }
  for (final a in release.assets) {
    if (a.name.endsWith(suffix)) return a;
  }
  // Android: fall back to the universal APK.
  if (suffix.endsWith('.apk')) {
    for (final a in release.assets) {
      if (a.name.endsWith('android-universal.apk')) return a;
    }
  }
  return null;
}

HttpClient _client() => HttpClient()
  ..connectionTimeout = const Duration(seconds: 15)
  ..userAgent = 'SMT-FAI-updater';

Future<ReleaseInfo> fetchLatestRelease() async {
  final client = _client();
  try {
    final req = await client.getUrl(Uri.parse('https://api.github.com/repos/$updateRepo/releases/latest'));
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final res = await req.close().timeout(const Duration(seconds: 20));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode == 404) throw UpdateException('no_release');
    if (res.statusCode != 200) throw UpdateException('network', 'HTTP ${res.statusCode}');
    return ReleaseInfo.fromJson(jsonDecode(body) as Map<String, dynamic>);
  } on UpdateException {
    rethrow;
  } catch (e) {
    throw UpdateException('network', '$e');
  } finally {
    client.close();
  }
}

/// Downloads [asset] to [dir], reporting progress in 0..1.
Future<File> downloadAsset(ReleaseAsset asset, Directory dir, void Function(double) onProgress) async {
  final client = _client();
  final file = File('${dir.path}${Platform.pathSeparator}${asset.name}');
  try {
    await dir.create(recursive: true);
    final req = await client.getUrl(Uri.parse(asset.url));
    final res = await req.close();
    if (res.statusCode != 200) throw UpdateException('download', 'HTTP ${res.statusCode}');
    final total = res.contentLength > 0 ? res.contentLength : asset.size;
    final sink = file.openWrite();
    var received = 0;
    await for (final chunk in res) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress(received / total);
    }
    await sink.close();
    if (total > 0 && await file.length() != total) throw UpdateException('download', 'incomplete');
    return file;
  } on UpdateException {
    rethrow;
  } catch (e) {
    throw UpdateException('download', '$e');
  } finally {
    client.close();
  }
}
