import 'package:flutter/material.dart';
import 'package:health_widgets/domain/nutrition.dart';

class NutritionPainter extends CustomPainter {
  final List<NutritionDay> data;

  NutritionPainter(this.data);

  // Форматирование даты dd.mm
  String _formatDate(DateTime date) {
    String day = date.day.toString().padLeft(2, '0');
    String month = date.month.toString().padLeft(2, '0');
    return '$day.$month';
  }

  // Форматирование граммов (убираем .0 если целое)
  String _formatGrams(double grams) {
    if (grams == grams.toInt()) {
      return '${grams.toInt()}g';
    }
    return '${grams.toStringAsFixed(1)}g';
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    // 1. Находим максимум по сумме граммов (Б+Ж+У) для масштабирования высоты
    double maxGrams = data.map((e) => e.totalGrams).reduce((a, b) => a > b ? a : b);
    // Минимальный порог, чтобы пустые дни не схлопывались совсем, если нужно
    if (maxGrams < 100.0) maxGrams = 100.0;

    // Рассчитываем среднее, если не передано снаружи
    final avgData = [...data]..removeWhere((e) => e.date.day == DateTime.now().day);
    double avgCal = (avgData.isNotEmpty
        ? avgData.map((e) => e.calories).reduce((a, b) => a + b) / avgData.length
        : 0);

    // Отступы: 30px сверху (для среднего и ккал), 20px снизу (для даты)
    double chartHeight = size.height - 50;

    // Ширина столбца и отступы (как в сне)
    double spacing = 1.6;
    double barWidth = size.width / (data.length * spacing);

    // Цвета макронутриентов (в стиле графика сна)
    // Белки -> Deep (Темно-синий)
    final paintProtein = Paint()..color = const Color(0xFF4A5DCB);
    // Жиры -> Light (Синий)
    final paintFat = Paint()..color = const Color(0xFFF9C620);
    // Углеводы -> REM (Светло-синий/Лавандовый)
    final paintCarbs = Paint()..color = const Color(0xFF8E423E);

    // --- Рисуем среднее количество ккал в самом верху (опционально) ---
    // Лучше выносить это в Widget tree, но если нужно на канвасе:
    _drawText(
      canvas,
      'Avg: ${avgCal.toInt()} kcal',
      0,
      5,
      size.width,
      isBold: false,
      isSmall: true,
      alignRight: true,
    );

    for (int i = 0; i < data.length; i++) {
      double x = i * barWidth * spacing + (barWidth * (spacing - 1) / 2);

      // Если данных за день нет (0 грамм), рисуем только дату
      if (data[i].totalGrams <= 0) {
        _drawText(canvas, _formatDate(data[i].date), x, size.height - 15, barWidth, isDate: true);
        continue;
      }

      // Высота столбца пропорциональна общему весу БЖУ
      double totalHeight = (data[i].totalGrams / maxGrams) * chartHeight;
      double currentY = size.height - 20; // Начинаем рисовать снизу вверх

      // Порядок отрисовки стека (снизу вверх):
      // Обычно: Белки (низ), Жиры (середина), Углеводы (верх) - или как вам удобно.
      // Здесь сделаем: Белки -> Жиры -> Углеводы

      // 1. Белки (снизу)
      _drawSegment(
        canvas,
        x,
        currentY,
        barWidth,
        totalHeight,
        data[i].protein,
        data[i].totalGrams,
        paintProtein,
        isBottom: true,
      );
      currentY -= totalHeight * (data[i].protein / data[i].totalGrams);

      // 2. Жиры (середина)
      _drawSegment(canvas, x, currentY, barWidth, totalHeight, data[i].fat, data[i].totalGrams, paintFat);
      currentY -= totalHeight * (data[i].fat / data[i].totalGrams);

      // 3. Углеводы (верх)
      _drawSegment(
        canvas,
        x,
        currentY,
        barWidth,
        totalHeight,
        data[i].carbs,
        data[i].totalGrams,
        paintCarbs,
        isTop: true,
      );

      // Координата верха столбца для подписи ккал
      double topOfBar = currentY - (totalHeight * (data[i].carbs / data[i].totalGrams));

      // --- ТЕКСТ: Ккал за день (над столбиком) ---
      _drawText(canvas, '${data[i].calories.toInt()}\nkcal', x, topOfBar - 28, barWidth, isBold: true);

      // --- ТЕКСТ: Дата (под столбиком) ---
      _drawText(canvas, _formatDate(data[i].date), x, size.height - 15, barWidth, isDate: true);
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
      fontSize: isDate ? 9 : (isSmall ? 10 : 10),
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

  void _drawSegment(
    Canvas canvas,
    double x,
    double y,
    double width,
    double totalHeight,
    double nutrientValue, // граммы
    double totalValue, // общие граммы
    Paint paint, {
    bool isTop = false,
    bool isBottom = false,
  }) {
    if (nutrientValue <= 0) return;

    double h = totalHeight * (nutrientValue / totalValue);
    // Минимальная высота, чтобы текст влез или просто был виден сегмент
    if (h < 1) h = 1;

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

    // Подпись граммов внутри сегмента
    // Рисуем, если высота сегмента достаточна (> 12px)
    if (h > 12) {
      final tp = TextPainter(
        text: TextSpan(
          text: _formatGrams(nutrientValue),
          style: const TextStyle(color: Colors.white, fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);

      // Центрируем текст внутри сегмента
      tp.paint(canvas, Offset(x + (width - tp.width) / 2, y - h + (h - tp.height) / 2));
    }
  }

  @override
  bool shouldRepaint(covariant NutritionPainter oldDelegate) => oldDelegate.data != data;
}
