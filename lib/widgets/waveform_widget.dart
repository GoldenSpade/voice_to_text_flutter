import 'package:flutter/material.dart';

class WaveformWidget extends StatelessWidget {
  final List<double> data;
  final Color color;
  final double height;

  const WaveformWidget({
    super.key,
    required this.data,
    required this.color,
    this.height = 64,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _WaveformPainter(data: data, color: color),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  static const _barCount = 40;
  static const _gap = 3.0;
  static const _minBarHeightFraction = 0.06;
  static const _cornerRadius = 2.5;

  _WaveformPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = (size.width - _gap * (_barCount - 1)) / _barCount;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < _barCount; i++) {
      final dataIndex = data.length - _barCount + i;
      final amplitude =
          (dataIndex >= 0 && dataIndex < data.length) ? data[dataIndex] : 0.0;

      final opacity = 0.2 + 0.8 * (i / (_barCount - 1));
      paint.color = color.withOpacity(opacity);

      final barHeight =
          _minBarHeightFraction * size.height + amplitude * (1.0 - _minBarHeightFraction) * size.height;
      final x = i * (barWidth + _gap);
      final y = (size.height - barHeight) / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(_cornerRadius),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.data != data || old.color != color;
}
