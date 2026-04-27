import 'package:flutter/material.dart';
import 'package:health_widgets/domain.dart';

class MultiPhaseSleepPainter extends CustomPainter {
  final List<SleepDay> data;
  MultiPhaseSleepPainter(this.data);

  // Вспомогательная функция для форматирования времени (например, 7h 20m)
  String _formatHours(double hours) {
    int h = hours.toInt();
    int m = ((hours - h) * 60).round();
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }

  // Вспомогательная функция для формата dd.mm
  String _formatDate(DateTime date) {
    String day = date.day.toString().padLeft(2, '0');
    String month = date.month.toString().padLeft(2, '0');
    return '$day.$month';
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    // Находим максимум для масштабирования
    double maxVal = data.map((e) => e.total).reduce((a, b) => a > b ? a : b);
    if (maxVal < 8.0) maxVal = 8.0;

    // Оставляем 30px сверху для общего времени и 20px снизу для даты
    double chartHeight = size.height - 50;
    double spacing = 1.6;
    double barWidth = size.width / (data.length * spacing);

    final paintDeep = Paint()..color = const Color(0xFF1A237E);
    final paintLight = Paint()..color = const Color(0xFF3F51B5);
    final paintREM = Paint()..color = const Color(0xFF9FA8DA);

    for (int i = 0; i < data.length; i++) {
      double x = i * barWidth * spacing + (barWidth * (spacing - 1) / 2);
      if (data[i].total <= 0) {
        // Отрисуем хотя бы дату для пустых дней
        _drawText(canvas, _formatDate(data[i].date), x, size.height - 15, barWidth, isDate: true);
        continue;
      }

      double totalHeight = (data[i].total / maxVal) * chartHeight;
      double currentY = size.height - 20; // Начало отрисовки (над датой)

      // 1. Deep (снизу)
      _drawSegment(
        canvas,
        x,
        currentY,
        barWidth,
        totalHeight,
        data[i].deep,
        data[i].total,
        paintDeep,
        isBottom: true,
      );
      currentY -= totalHeight * (data[i].deep / data[i].total);

      // 2. Light (середина)
      _drawSegment(canvas, x, currentY, barWidth, totalHeight, data[i].light, data[i].total, paintLight);
      currentY -= totalHeight * (data[i].light / data[i].total);

      // 3. REM (верх)
      _drawSegment(
        canvas,
        x,
        currentY,
        barWidth,
        totalHeight,
        data[i].rem,
        data[i].total,
        paintREM,
        isTop: true,
      );
      double topOfBar = currentY - (totalHeight * (data[i].rem / data[i].total));

      // --- ТЕКСТ: Общее время (над столбиком) ---
      _drawText(canvas, _formatHours(data[i].total), x, topOfBar - 18, barWidth, isBold: true);

      // --- ТЕКСТ: Дата dd.mm (под столбиком) ---
      _drawText(canvas, _formatDate(data[i].date), x, size.height - 15, barWidth, isDate: true);
    }
  }

  // Универсальный метод отрисовки текста
  void _drawText(
    Canvas canvas,
    String text,
    double x,
    double y,
    double width, {
    bool isBold = false,
    bool isDate = false,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: isDate ? Colors.white54 : Colors.white,
          fontSize: isDate ? 9 : 10,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: width + 10);

    textPainter.paint(canvas, Offset(x + (width - textPainter.width) / 2, y));
  }

  void _drawSegment(
    Canvas canvas,
    double x,
    double y,
    double width,
    double totalHeight,
    double phaseValue,
    double totalValue,
    Paint paint, {
    bool isTop = false,
    bool isBottom = false,
  }) {
    double h = totalHeight * (phaseValue / totalValue);
    if (h <= 0) return;

    Rect rect = Rect.fromLTWH(x, y - h, width, h);

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        rect,
        topLeft: isTop ? const Radius.circular(4) : Radius.zero,
        topRight: isTop ? const Radius.circular(4) : Radius.zero,
        bottomLeft: isBottom ? const Radius.circular(4) : Radius.zero,
        bottomRight: isBottom ? const Radius.circular(4) : Radius.zero,
      ),
      paint,
    );

    // Подпись внутри фазы (если влезет по высоте)
    if (h > 15) {
      final tp = TextPainter(
        text: TextSpan(
          text: _formatHours(phaseValue),
          style: const TextStyle(color: Colors.white, fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);

      tp.paint(canvas, Offset(x + (width - tp.width) / 2, y - h + (h - tp.height) / 2));
    }
  }

  @override
  bool shouldRepaint(covariant MultiPhaseSleepPainter oldDelegate) => oldDelegate.data != data;
}
