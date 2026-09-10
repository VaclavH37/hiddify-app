import 'package:circle_flags/circle_flags.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A country flag as a circle, sized to fit a row; a globe when the country
/// is not known. Country only: the organisation badge that used to sit on its
/// corner named the exit's hosting provider, which is the fleet's business
/// rather than the user's.
class IPCountryFlag extends ConsumerWidget {
  const IPCountryFlag({required this.countryCode, this.size = 16, this.padding = EdgeInsets.zero, super.key});

  final String? countryCode;
  final double size;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final code = countryCode;
    return Semantics(
      label: t.pages.proxies.ipInfo.country,
      child: Padding(
        padding: padding,
        child: code == null || code.isEmpty ? Icon(Icons.public_rounded, size: size) : CircleFlag(code, size: size),
      ),
    );
  }
}
