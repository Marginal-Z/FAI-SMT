/// Interface zoom. On Android the automatic factor follows the display, so a
/// large tablet gets larger controls and a small screen still fits the full
/// layout; desktop stays at 100 % unless the user picks a size.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Sizes offered in Settings besides automatic.
const uiScaleSteps = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5];

/// Automatic factor for a window of [logical] size (logical pixels).
double autoUiScale(Size logical) {
  if (!Platform.isAndroid) return 1;
  final short = logical.shortestSide;
  // Phones: keep the designed size, a little smaller on narrow screens.
  if (short < 600) return (short / 420).clamp(0.85, 1.1);
  // Tablets: the layout is designed for 1280 × 800 (landscape) and
  // 800 × 1280 (portrait); scale so it fills the display the same way.
  final landscape = logical.width >= logical.height;
  final w = landscape ? 1280.0 : 800.0, h = landscape ? 800.0 : 1280.0;
  return math.min(logical.width / w, logical.height / h).clamp(0.75, 1.6);
}

/// Lays [child] out in a smaller or larger logical space and scales it to
/// fill the available area. [setting] 0 means automatic.
class UiScale extends StatelessWidget {
  const UiScale({super.key, required this.setting, required this.child});

  final double setting;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final available = box.biggest;
        final k = setting > 0 ? setting : autoUiScale(available);
        if ((k - 1).abs() < 0.01 || !available.isFinite) return child;
        final mq = MediaQuery.of(context);
        final logical = available / k;
        return FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: logical,
            child: MediaQuery(
              data: mq.copyWith(
                size: mq.size / k,
                devicePixelRatio: mq.devicePixelRatio * k,
                padding: mq.padding / k,
                viewPadding: mq.viewPadding / k,
                viewInsets: mq.viewInsets / k,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
