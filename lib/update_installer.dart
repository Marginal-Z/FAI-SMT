/// Applies a downloaded update package.
///
/// * Windows (.zip) / Linux (.tar.gz): unpack next to the download, then a
///   small detached script waits for this process to exit, copies the new
///   files over the install folder and restarts the app.
/// * Linux installed read-only (e.g. the .deb in /opt): opens the .deb with
///   the system package installer instead.
/// * Windows installed with the setup program: runs the new setup silently;
///   it closes this app, upgrades in place and starts the new version.
/// * Android (.apk): checks that the package is signed with the same key as
///   the installed app (otherwise Android refuses the update), then hands it
///   to the system package installer.
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

import 'core/updater.dart';

const _channel = MethodChannel('smt_fai/update');

/// Windows: the app lives in a folder made by the setup program.
bool get installedWithSetup =>
    Platform.isWindows && File('${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}unins000.exe').existsSync();

/// Returns normally only when the caller should keep running (Android, or
/// the .deb fallback); otherwise the process exits for the copy to happen.
Future<void> installUpdate(File package, ReleaseInfo release) async {
  try {
    if (Platform.isAndroid) {
      final signature = await _channel.invokeMethod<String>('apkSignature', {'path': package.path});
      if (signature == 'mismatch') throw UpdateException('signature');
      await _channel.invokeMethod('installApk', {'path': package.path});
      return;
    }
    if (package.path.endsWith('.exe')) {
      await Process.start(package.path, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'], mode: ProcessStartMode.detached);
      exit(0);
    }
    final installDir = File(Platform.resolvedExecutable).parent;
    if (Platform.isLinux && !await _writable(installDir)) {
      final deb = release.assets.where((a) => a.name.endsWith(package.path.contains('arm64') ? 'linux-arm64.deb' : 'linux-x64.deb'));
      if (deb.isEmpty) throw UpdateException('install', 'read-only install folder');
      final file = await downloadAsset(deb.first, package.parent, (_) {});
      await Process.start('xdg-open', [file.path], mode: ProcessStartMode.detached);
      return;
    }

    final staging = Directory('${package.parent.path}${Platform.pathSeparator}staging');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    final bytes = await package.readAsBytes();
    final archive = package.path.endsWith('.zip')
        ? ZipDecoder().decodeBytes(bytes)
        : TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    for (final entry in archive) {
      final out = '${staging.path}${Platform.pathSeparator}${entry.name.replaceAll('/', Platform.pathSeparator)}';
      if (entry.isFile) {
        final f = File(out);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(entry.content as List<int>);
      } else {
        await Directory(out).create(recursive: true);
      }
    }
    // The Linux tarball wraps the bundle in one folder.
    var source = staging;
    final children = staging.listSync();
    if (children.length == 1 && children.single is Directory) source = children.single as Directory;

    if (Platform.isWindows) {
      await _runWindowsSwap(source.path, installDir.path, Platform.resolvedExecutable, package.parent.path);
    } else {
      await _runPosixSwap(source.path, installDir.path, Platform.resolvedExecutable);
    }
    exit(0);
  } on UpdateException {
    rethrow;
  } catch (e) {
    throw UpdateException('install', '$e');
  }
}

Future<bool> _writable(Directory dir) async {
  try {
    final probe = File('${dir.path}${Platform.pathSeparator}.smt_fai_write_test');
    await probe.writeAsString('x');
    await probe.delete();
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _runWindowsSwap(String source, String target, String exe, String work) async {
  final script = File('$work\\apply_update.cmd');
  await script.writeAsString('''@echo off\r
chcp 65001 >NUL\r
:wait\r
tasklist /FI "PID eq $pid" 2>NUL | find "$pid" >NUL\r
if not errorlevel 1 (\r
  timeout /t 1 /nobreak >NUL\r
  goto wait\r
)\r
robocopy "$source" "$target" /E /R:5 /W:1 /NFL /NDL /NJH /NJS /NP >NUL\r
start "" "$exe"\r
''');
  // `start` gives the script its own minimised console; the first quoted
  // argument is the window title.
  await Process.start('cmd', ['/c', 'start', 'SMT-FAI update', '/min', script.path], mode: ProcessStartMode.detached);
}

Future<void> _runPosixSwap(String source, String target, String exe) async {
  final script = File('${Directory.systemTemp.path}/smt_fai_apply_update.sh');
  await script.writeAsString('''#!/bin/sh
while kill -0 $pid 2>/dev/null; do sleep 0.5; done
cp -a "$source/." "$target/"
chmod +x "$exe"
nohup "$exe" >/dev/null 2>&1 &
''');
  await Process.start('sh', [script.path], mode: ProcessStartMode.detached);
}
