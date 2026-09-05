import 'package:flutter/material.dart';
import 'package:hiddify/core/model/constants.dart';

class AnimatedText extends Text {
  const AnimatedText(
    super.data, {
    super.key,
    super.style,
    this.duration = kAnimationDuration,
    this.size = true,
    this.slide = true,
  });

  final Duration duration;
  final bool size;
  final bool slide;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      transitionBuilder: (child, animation) {
        // Wrapped in a local rather than reassigning `child`: the two
        // transitions are optional and each wraps the previous one, so the
        // accumulator genuinely varies while the parameter should not.
        Widget transition = FadeTransition(opacity: animation, child: child);
        if (size) {
          transition = SizeTransition(
            axis: Axis.horizontal,
            fixedCrossAxisSizeFactor: 1,
            sizeFactor: Tween<double>(begin: 0.88, end: 1).animate(animation),
            child: transition,
          );
        }
        if (slide) {
          transition = SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.0, -0.2), end: Offset.zero).animate(animation),
            child: transition,
          );
        }
        return transition;
      },
      child: Text(data!, key: ValueKey<String>(data!), style: style),
    );
  }
}
