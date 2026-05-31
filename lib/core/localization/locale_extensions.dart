import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/gen/translations.g.dart';

extension AppLocaleX on AppLocale {
  // Persian keeps Shabnam (Geist lacks Persian glyphs); every other locale
  // uses Geist as the default UI font.
  String get preferredFontFamily => this == AppLocale.fa ? FontFamily.shabnam : FontFamily.geist;

  String get localeName => switch (flutterLocale.toString()) {
    "ar" => "العربية",
    "en" => "English",
    "es" => "Spanish",
    "fa" => "فارسی",
    "fr" => "Français",
    "id" => "Indonesian",
    "pt_BR" => "Portuguese (Brazil)",
    "ru" => "Русский",
    "tr" => "Türkçe",
    "zh" || "zh_CN" => "中文 (中国)",
    "zh_TW" => "中文 (台湾)",
    _ => "Unknown",
  };
}
