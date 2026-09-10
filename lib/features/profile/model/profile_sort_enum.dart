import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';

enum ProfilesSort {
  lastUpdate,
  name;

  String present(TranslationsEn t) {
    return switch (this) {
      lastUpdate => t.dialogs.sortProfiles.sort.name,
      name => t.dialogs.sortProfiles.sort.lastUpdate,
    };
  }

  IconData get icon => switch (this) {
    lastUpdate => Icons.history_rounded,
    name => Icons.sort_by_alpha_rounded,
  };
}

enum SortMode { ascending, descending }
