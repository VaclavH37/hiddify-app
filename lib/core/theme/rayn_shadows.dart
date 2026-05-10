import 'package:flutter/material.dart';

/// Rayn VPN design tokens — shared shadow stacks.
class RaynShadows {
  const RaynShadows._();

  static const List<BoxShadow> ambient = [
    BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> goldGlow = [
    BoxShadow(color: Color(0x33E8A317), blurRadius: 32, spreadRadius: 2),
  ];
}
