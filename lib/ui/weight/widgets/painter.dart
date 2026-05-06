import 'package:flutter/material.dart';
import 'package:health_widgets/domain/weight.dart';

class WeightPainter extends CustomPainter {
  final List<WeightDay> data;

  WeightPainter(this.data);

  // Форматирование даты dd.mm
  String _formatDate(DateTime date) {
    String day = date.day.toString().padLeft(2, '0');
    String month = date.month.toString().padLeft(2, '0');
    return '$day.$month';
  }

  // Форматирование веса (убираем .0 если целое)
  String _formatWeight(double weight) {
    if (weight == weight.toInt()) {
      return '${weight.toInt()}kg';
    }
    return '${weight.toStringAsFixed(1)}kg';
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    // Находим минимум и максимум для масштабирования
    double minWeight = data.map((e) => e.weight).reduce((a, b) => a < b ? a : b);
    double maxWeight = data.map((e) => e.weight).reduce((a, b) => a > b ? a : b);
    
    // Добавляем небольшой отступ сверху и снизу
    double range = maxWeight - minWeight;
    if (range < 1.0) range = 1.0; // Минимальный диапазон
    minWeight -= range * 0.1;
    maxWeight += range * 0.1;

    // Отступы: 30px сверху (для среднего), 20px снизу (для даты)
    double chartHeight = size.height - 50;

    // Ширина линии и отступы
    double spacing = 1.6;
    double pointSpacing = size.width / (data.length * spacing);

    // Цвета
    final linePaint = Paint()
      ..color = const Color(0xFF4CAF50)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()..color = const Color(0xFF4CAF50);

    final fillPaint = Paint()
      ..color = const Color(0xFF4CAF50).withOpacity(0.2)
      ..style = PaintingStyle.fill;

    // --- Рисуем средний вес в самом верху ---
    final avgWeight = data.map((e) => e.weight).reduce((a, b) => a + b) / data.length;
    _drawText(
      canvas,
      'Avg: ${avgWeight.toStringAsFixed(1)} kg',
      0,
      5,
      size.width,
      isBold: false,
      isSmall: true,
      alignRight: true,
    );

    // Рисуем линию среднего значения (пунктирную)
    double avgY = size.height - 20 - ((avgWeight - minWeight) / (maxWeight - minWeight)) * chartHeight;
    final avgLinePaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    
    // Пунктирная линия
    final path = Path();
    path.moveTo(0, avgY);
    path.lineTo(size.width, avgY);
    
    // Рисуем пунктир вручную
    double dashWidth = 5, dashSpace = 5;
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, avgY), Offset(startX + dashWidth, avgY), avgLinePaint);
      startX += dashWidth + dashSpace;
    }

    // Строим путь для линии графика
    final graphPath = Path();
    final fillPath = Path();

    for (int i = 0; i < data.length; i++) {
      double x = i * pointSpacing * spacing + (pointSpacing * (spacing - 1) / 2) + pointSpacing / 2;
      double y = size.height - 20 - ((data[i].weight - minWeight) / (maxWeight - minWeight)) * chartHeight;

      if (i == 0) {
        graphPath.moveTo(x, y);
        fillPath.moveTo(x, size.height - 20);
        fillPath.lineTo(x, y);
      } else {
        graphPath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Завершаем путь для заливки
    if (data.isNotEmpty) {
      double lastX = (data.length - 1) * pointSpacing * spacing + (pointSpacing * (spacing - 1) / 2) + pointSpacing / 2;
      fillPath.lineTo(lastX, size.height - 20);
      fillPath.close();
    }

    // Рисуем заливку
    canvas.drawPath(fillPath, fillPaint);

    // Рисуем линию
    canvas.drawPath(graphPath, linePaint);

    // Рисуем точки и подписи
    for (int i = 0; i < data.length; i++) {
      double x = i * pointSpacing * spacing + (pointSpacing * (spacing - 1) / 2) + pointSpacing / 2;
      double y = size.height - 20 - ((data[i].weight - minWeight) / (maxWeight - minWeight)) * chartHeight;

      // Точка
      canvas.drawCircle(Offset(x, y), 4, pointPaint);

      // Подпись веса над точкой
      _drawText(canvas, _formatWeight(data[i].weight), x - 15, y - 20, 30, isBold: true, isSmall: true);

      // Дата под графиком
      _drawText(canvas, _formatDate(data[i].date), x, size.height - 15, pointSpacing, isDate: true);
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    double x,
    double y,
    double width, {
    bool isBold = false,
    bool isDate = false,
    bool isSmall = false,
    bool alignRight = false,
  }) {
    final textStyle = TextStyle(
      color: isDate ? Colors.white54 : Colors.white,
      fontSize: isDate ? 9 : (isSmall ? 9 : 10),
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
    );

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: width + 10);

    double offsetX = x + (width - textPainter.width) / 2;
    if (alignRight) {
      offsetX = x + width - textPainter.width;
    }

    textPainter.paint(canvas, Offset(offsetX, y));
  }

  @override
  bool shouldRepaint(covariant WeightPainter oldDelegate) => oldDelegate.data != data;
}
