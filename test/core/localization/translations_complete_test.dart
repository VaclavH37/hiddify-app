import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every language carries every English string, with the same placeholders.
///
/// slang falls back to English for a missing key, so a gap shows no error: the
/// IP routing warning (2026-10-16) went out in English in all ten other
/// languages until it was translated. A placeholder that is dropped or renamed
/// in one language would fail the same silent way, with the adapter's name
/// missing from the sentence.
void main() {
  final dir = Directory('assets/translations');
  Map<String, String> flatten(Object? node, [String prefix = '']) => switch (node) {
    final Map<String, dynamic> map => {
      for (final entry in map.entries) ...flatten(entry.value, prefix.isEmpty ? entry.key : '$prefix.${entry.key}'),
    },
    final List<dynamic> list => {for (var i = 0; i < list.length; i++) ...flatten(list[i], '$prefix[$i]')},
    _ => {prefix: '$node'},
  };

  Map<String, String> load(String locale) =>
      flatten(jsonDecode(File('${dir.path}/$locale.i18n.json').readAsStringSync()));

  // `${name}` or `$name`, but not an escaped `\$` (a literal dollar sign).
  final placeholder = RegExp(r'(?<!\\)\$\{?(\w+)\}?');
  Set<String> placeholders(String text) => placeholder.allMatches(text).map((m) => m.group(1)!).toSet();

  final english = load('en');
  final locales =
      dir
          .listSync()
          .map((file) => file.uri.pathSegments.last)
          .where((name) => name.endsWith('.i18n.json') && name != 'en.i18n.json')
          .map((name) => name.substring(0, name.length - '.i18n.json'.length))
          .toList()
        ..sort();

  test('there are languages besides English to check', () {
    expect(locales, isNotEmpty);
  });

  for (final locale in locales) {
    group(locale, () {
      final translated = load(locale);

      test('has every English string', () {
        final missing = english.keys.where((key) => !translated.containsKey(key)).toList();
        expect(missing, isEmpty, reason: '$locale is missing ${missing.length} strings; slang shows English for them');
      });

      test('has no strings English does not', () {
        final extra = translated.keys.where((key) => !english.containsKey(key)).toList();
        expect(extra, isEmpty, reason: 'stale or misplaced keys in $locale');
      });

      test('keeps every placeholder', () {
        final broken = [
          for (final key in english.keys)
            if (translated.containsKey(key) && !_sameSet(placeholders(english[key]!), placeholders(translated[key]!)))
              '$key: en ${placeholders(english[key]!)} vs $locale ${placeholders(translated[key]!)}',
        ];
        expect(broken, isEmpty);
      });
    });
  }
}

bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);
