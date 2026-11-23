import 'package:flutter/widgets.dart';

/// [AnimatedSwitcher.layoutBuilder] without its duplicate-key crash.
///
/// The switcher's default transition keys each child's fade by the child's own
/// key, so a child that comes back while its earlier self is still fading out
/// (A, then B, then A again within the duration) sits in the stack twice under
/// one key, and the tree fails with "Duplicate keys found": an assertion in
/// debug builds, undefined layout in release. Here the earlier copy goes at
/// once instead; the returning child takes its place.
AnimatedSwitcherLayoutBuilder uniqueKeysLayout([AlignmentGeometry alignment = Alignment.center]) =>
    (current, previous) {
      final keys = <Key?>{current?.key};
      final kept = [
        for (final child in previous.reversed)
          if (child.key == null || keys.add(child.key)) child,
      ];
      return Stack(alignment: alignment, children: [...kept.reversed, if (current != null) current]);
    };
