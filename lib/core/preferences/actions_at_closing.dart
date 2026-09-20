import 'package:hiddify/gen/translations.g.dart';

enum ActionsAtClosing {
  ask,
  hide,
  exit;

  /// The same words the closing dialog uses, so a remembered choice reads in
  /// Settings the way it read when it was made.
  String present(TranslationsEn t) => switch (this) {
    ask => t.dialogs.windowClosing.askEachTime,
    hide => t.dialogs.windowClosing.keepRunning,
    exit => t.common.exit,
  };
}
