/// Interface zoom. On Android the automatic factor only evens out screen
/// density; the layout itself adapts to the width (phone, tablet portrait,
/// tablet landscape) instead of shrinking the desktop layout. Desktop stays
/// at 100 % unless the user picks a size.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';

/// Sizes offered in Settings besides automatic.
const uiScaleSteps = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5];

/// Automatic factor for a window of [logical] size (logical pixels).
double autoUiScale(Size logical) {
  if (!Platform.isAndroid) return 1;
  final short = logical.shortestSide;
  // Phones: the designed size, a little smaller on very narrow screens.
  if (short < 600) return (short / 400).clamp(0.9, 1.1);
  // Tablets: their own layout at their own size, slightly larger controls
  // on big displays.
  return (short / 800).clamp(1.0, 1.3);
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
