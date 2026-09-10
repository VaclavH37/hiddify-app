import 'package:circle_flags/circle_flags.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A country flag sized to fit a row; a globe when the country is not known.
/// A circle by default (the location card); [rounded] draws it as a
/// rounded-corner square instead, which is how the picker's list reads it.
/// Country only: the organisation badge that used to sit on its corner named
/// the exit's hosting provider, which is the fleet's business rather than the
/// user's.
class IPCountryFlag extends ConsumerWidget {
  const IPCountryFlag({
    required this.countryCode,
    this.size = 16,
    this.padding = EdgeInsets.zero,
    this.rounded = false,
    super.key,
  });

  final String? countryCode;
  final double size;
  final EdgeInsetsGeometry padding;

  /// A rounded-corner square rather than a circle.
  final bool rounded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final code = countryCode;
    return Semantics(
      label: t.pages.proxies.ipInfo.country,
      child: Padding(
        padding: padding,
        child: code == null || code.isEmpty
            ? Icon(Icons.public_rounded, size: size)
            : CircleFlag(
                code,
                size: size,
                // Explicit in both branches: a null shape is "do not clip", not
                // "the package's circle".
                shape: rounded
                    ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(size * 0.22))
                    : const CircleBorder(),
              ),
      ),
    );
  }
}
