// Renders the logo into launcher icons for Android, Windows and Linux.
//
//   flutter test tool/gen_icons_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/ui/logo.dart';

Future<Uint8List> _png(int px, {bool background = true, double inset = 0}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  LogoPainter(background: background, inset: inset).paint(canvas, Size.square(px.toDouble()));
  final img = await rec.endRecording().toImage(px, px);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// ICO container with PNG-compressed entries (Windows Vista and later).
Uint8List _ico(List<(int, Uint8List)> images) {
  final out = BytesBuilder();
  final header = ByteData(6)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, images.length, Endian.little);
  out.add(header.buffer.asUint8List());
  var offset = 6 + 16 * images.length;
  for (final (size, png) in images) {
    final e = ByteData(16)
      ..setUint8(0, size >= 256 ? 0 : size)
      ..setUint8(1, size >= 256 ? 0 : size)
      ..setUint16(4, 1, Endian.little)
      ..setUint16(6, 32, Endian.little)
      ..setUint32(8, png.length, Endian.little)
      ..setUint32(12, offset, Endian.little);
    out.add(e.buffer.asUint8List());
    offset += png.length;
  }
  for (final (_, png) in images) {
    out.add(png);
  }
  return out.toBytes();
}

void main() {
  testWidgets('generate launcher icons', (tester) async {
    await tester.runAsync(() async {
      // Android legacy icons (rounded tile) and adaptive foreground layers.
      const densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};
      for (final e in densities.entries) {
        final dir = Directory('android/app/src/main/res/mipmap-${e.key}')..createSync(recursive: true);
        File('${dir.path}/ic_launcher.png').writeAsBytesSync(await _png((48 * e.value).round()));
        File('${dir.path}/ic_launcher_foreground.png')
            .writeAsBytesSync(await _png((108 * e.value).round(), background: false, inset: 0.2));
      }
      final anydpi = Directory('android/app/src/main/res/mipmap-anydpi-v26')..createSync(recursive: true);
      File('${anydpi.path}/ic_launcher.xml').writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''');
      final values = Directory('android/app/src/main/res/values')..createSync(recursive: true);
      File('${values.path}/ic_launcher_background.xml').writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#1B1E24</color>
</resources>
''');

      // Windows executable icon.
      final sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256];
      File('windows/runner/resources/app_icon.ico')
          .writeAsBytesSync(_ico([for (final s in sizes) (s, await _png(s))]));

      // Linux window icon, bundled as an asset.
      Directory('assets/icon').createSync(recursive: true);
      File('assets/icon/app_icon.png').writeAsBytesSync(await _png(256));
      File('assets/icon/app_icon_1024.png').writeAsBytesSync(await _png(1024));
    });
  });
}
