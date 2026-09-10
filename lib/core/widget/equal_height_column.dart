import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A column whose rows all take the height of the tallest one, with a
/// hairline painted between neighbours.
///
/// A settings group mixes rows with a subtitle and rows without, and left to
/// themselves they come out at two heights, which reads as untidy. There is
/// no built-in for "as tall as the tallest sibling" in a column (that is what
/// `IntrinsicHeight` does for a row), so this measures every row's intrinsic
/// height at the column's width, then lays each one out at the maximum.
///
/// A row whose intrinsic height is zero (a widget that has hidden itself with
/// `SizedBox.shrink`) is skipped: no height, no separator.
class EqualHeightColumn extends MultiChildRenderObjectWidget {
  const EqualHeightColumn({
    super.key,
    required List<Widget> rows,
    required this.separatorColor,
    this.separatorIndent = 0,
  }) : super(children: rows);

  final Color separatorColor;
  final double separatorIndent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEqualHeightColumn(separatorColor: separatorColor, separatorIndent: separatorIndent);

  @override
  void updateRenderObject(BuildContext context, _RenderEqualHeightColumn renderObject) {
    renderObject
      ..separatorColor = separatorColor
      ..separatorIndent = separatorIndent;
  }
}

class _RowParentData extends ContainerBoxParentData<RenderBox> {
  bool visible = true;
}

class _RenderEqualHeightColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _RowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _RowParentData> {
  _RenderEqualHeightColumn({required Color separatorColor, required double separatorIndent})
    : _separatorColor = separatorColor,
      _separatorIndent = separatorIndent;

  static const double separatorThickness = 1;

  Color _separatorColor;
  Color get separatorColor => _separatorColor;
  set separatorColor(Color value) {
    if (value == _separatorColor) return;
    _separatorColor = value;
    markNeedsPaint();
  }

  double _separatorIndent;
  double get separatorIndent => _separatorIndent;
  set separatorIndent(double value) {
    if (value == _separatorIndent) return;
    _separatorIndent = value;
    markNeedsPaint();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _RowParentData) child.parentData = _RowParentData();
  }

  /// Tallest row at [width], and how many rows are visible.
  (double, int) _measure(double width) {
    var rowHeight = 0.0;
    var visible = 0;
    var child = firstChild;
    while (child != null) {
      final height = child.getMaxIntrinsicHeight(width);
      if (height > 0) {
        rowHeight = math.max(rowHeight, height);
        visible++;
      }
      child = childAfter(child);
    }
    return (rowHeight, visible);
  }

  double _totalHeight(double width) {
    final (rowHeight, visible) = _measure(width);
    if (visible == 0) return 0;
    return visible * rowHeight + (visible - 1) * separatorThickness;
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    assert(width.isFinite, 'EqualHeightColumn needs a bounded width');
    final (rowHeight, _) = _measure(width);

    var y = 0.0;
    var placed = 0;
    var child = firstChild;
    while (child != null) {
      final parentData = child.parentData! as _RowParentData;
      final visible = child.getMaxIntrinsicHeight(width) > 0;
      parentData.visible = visible;
      if (visible) {
        if (placed > 0) y += separatorThickness;
        child.layout(BoxConstraints.tightFor(width: width, height: rowHeight));
        parentData.offset = Offset(0, y);
        y += rowHeight;
        placed++;
      } else {
        child.layout(BoxConstraints.tightFor(width: width, height: 0));
        parentData.offset = Offset(0, y);
      }
      child = childAfter(child);
    }
    size = constraints.constrain(Size(width, y));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(Size(constraints.maxWidth, _totalHeight(constraints.maxWidth)));

  @override
  double computeMinIntrinsicHeight(double width) => _totalHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _totalHeight(width);

  @override
  double computeMinIntrinsicWidth(double height) {
    var result = 0.0;
    var child = firstChild;
    while (child != null) {
      result = math.max(result, child.getMinIntrinsicWidth(height));
      child = childAfter(child);
    }
    return result;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var result = 0.0;
    var child = firstChild;
    while (child != null) {
      result = math.max(result, child.getMaxIntrinsicWidth(height));
      child = childAfter(child);
    }
    return result;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
    final paint = Paint()..color = _separatorColor;
    var placed = 0;
    var child = firstChild;
    while (child != null) {
      final parentData = child.parentData! as _RowParentData;
      if (parentData.visible) {
        if (placed > 0) {
          final top = offset.dy + parentData.offset.dy - separatorThickness;
          context.canvas.drawRect(
            Rect.fromLTWH(offset.dx + _separatorIndent, top, size.width - _separatorIndent, separatorThickness),
            paint,
          );
        }
        placed++;
      }
      child = childAfter(child);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
