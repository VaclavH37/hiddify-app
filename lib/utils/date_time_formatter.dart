import 'package:intl/intl.dart';

extension DateTimeFormatter on DateTime {
  String format() {
    return DateFormat.yMMMd().add_Hm().format(this);
  }

  /// Date only, e.g. "Jun 20, 2026" — used for the plan-expiry line.
  String formatDate() {
    return DateFormat.yMMMd().format(this);
  }
}
