/// UI access to the translated texts with runtime language switching.
library;

import 'package:flutter/widgets.dart';

import 'texts.dart';

export 'texts.dart';

class Strings extends Texts {
  Strings(super.lang);

  static Strings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StringsScope>()!.strings;
}

class StringsScope extends InheritedWidget {
  const StringsScope({super.key, required this.strings, required super.child});

  final Strings strings;

  @override
  bool updateShouldNotify(StringsScope old) => old.strings.lang != strings.lang;
}
