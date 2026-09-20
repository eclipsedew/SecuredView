import 'package:flutter/material.dart';

class SecuredViewLogo extends StatelessWidget {
  final double size;
  const SecuredViewLogo({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: const _LogoPainter(),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final strokeW = w * 0.083; // ~2px at 24px
    final corner = w * 0.23;   // corner arm length
    final cx = w / 2;
    final cy = h / 2;

    final paint = Paint()
      ..color = const Color(0xFF0E1417) // --ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.square;

    // Top-left corner: ┌
    canvas.drawLine(Offset(0, corner), Offset(0, 0), paint);
    canvas.drawLine(Offset(0, 0), Offset(corner, 0), paint);

    // Top-right corner: ┐
    canvas.drawLine(Offset(w - corner, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, corner), paint);

    // Bottom-right corner: ┘
    canvas.drawLine(Offset(w, h - corner), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w - corner, h), paint);

    // Bottom-left corner: └
    canvas.drawLine(Offset(corner, h), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(0, h - corner), paint);

    // Center blue circle — matches website exactly
    final circlePaint = Paint()
      ..color = const Color(0xFF163F8F) // --blue
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), w * 0.133, circlePaint); // 3.2/24 ratio
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
