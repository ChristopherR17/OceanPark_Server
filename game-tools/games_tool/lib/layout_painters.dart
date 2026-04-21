part of 'layout.dart';

class _AnimationRigFramePreviewPainter extends CustomPainter {
  const _AnimationRigFramePreviewPainter({
    required this.image,
    required this.frameWidth,
    required this.frameHeight,
    required this.columns,
    required this.frameIndex,
    this.drawCheckerboard = true,
  });

  final ui.Image image;
  final double frameWidth;
  final double frameHeight;
  final int columns;
  final int frameIndex;
  final bool drawCheckerboard;

  @override
  void paint(Canvas canvas, Size size) {
    if (drawCheckerboard) {
      final Paint bgA = Paint()..color = const Color(0xFFE8E8E8);
      final Paint bgB = Paint()..color = const Color(0xFFD8D8D8);
      const double checker = 8.0;
      for (double y = 0; y < size.height; y += checker) {
        for (double x = 0; x < size.width; x += checker) {
          final bool even =
              ((x / checker).floor() + (y / checker).floor()) % 2 == 0;
          canvas.drawRect(
            Rect.fromLTWH(x, y, checker, checker),
            even ? bgA : bgB,
          );
        }
      }
    }

    if (frameWidth <= 0 || frameHeight <= 0 || columns <= 0) {
      return;
    }
    final int row = frameIndex ~/ columns;
    final int col = frameIndex % columns;
    final Rect src = Rect.fromLTWH(
      col * frameWidth,
      row * frameHeight,
      frameWidth,
      frameHeight,
    );
    if (src.right > image.width || src.bottom > image.height) {
      return;
    }
    final double fitScale =
        (size.width / frameWidth) < (size.height / frameHeight)
            ? (size.width / frameWidth)
            : (size.height / frameHeight);
    final double drawWidth = frameWidth * fitScale;
    final double drawHeight = frameHeight * fitScale;
    final Rect dst = Rect.fromLTWH(
      (size.width - drawWidth) / 2,
      (size.height - drawHeight) / 2,
      drawWidth,
      drawHeight,
    );
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(covariant _AnimationRigFramePreviewPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.frameWidth != frameWidth ||
        oldDelegate.frameHeight != frameHeight ||
        oldDelegate.columns != columns ||
        oldDelegate.frameIndex != frameIndex ||
        oldDelegate.drawCheckerboard != drawCheckerboard;
  }
}

class _LayersMarqueePainter extends CustomPainter {
  const _LayersMarqueePainter({required this.rect});

  final Rect? rect;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect? selectionRect = rect;
    if (selectionRect == null ||
        selectionRect.width <= 0 ||
        selectionRect.height <= 0) {
      return;
    }

    final Paint fillPaint = Paint()
      ..color = const Color(0x552196F3)
      ..style = PaintingStyle.fill;
    canvas.drawRect(selectionRect, fillPaint);

    final Paint borderPaint = Paint()
      ..color = const Color(0xFF2196F3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    _drawDashedLine(
      canvas,
      selectionRect.topLeft,
      selectionRect.topRight,
      borderPaint,
    );
    _drawDashedLine(
      canvas,
      selectionRect.topRight,
      selectionRect.bottomRight,
      borderPaint,
    );
    _drawDashedLine(
      canvas,
      selectionRect.bottomRight,
      selectionRect.bottomLeft,
      borderPaint,
    );
    _drawDashedLine(
      canvas,
      selectionRect.bottomLeft,
      selectionRect.topLeft,
      borderPaint,
    );
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    const double dashLength = 6;
    const double gapLength = 4;
    final Offset delta = end - start;
    final double totalLength = delta.distance;
    if (totalLength == 0) {
      return;
    }
    final Offset direction = delta / totalLength;
    double distance = 0;
    while (distance < totalLength) {
      final double nextDistance = (distance + dashLength).clamp(0, totalLength);
      canvas.drawLine(
        start + direction * distance,
        start + direction * nextDistance,
        paint,
      );
      distance += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _LayersMarqueePainter oldDelegate) {
    return oldDelegate.rect != rect;
  }
}
