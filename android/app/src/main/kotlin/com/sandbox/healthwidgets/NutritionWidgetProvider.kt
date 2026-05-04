package com.sandbox.healthwidgets

import com.sandbox.healthwidgets.R
import android.appwidget.AppWidgetManager
import android.content.Context
import android.graphics.BitmapFactory
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File


class NutritionWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: android.content.SharedPreferences) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.sleep_widget_layout)

            // Получаем путь к картинке, который мы сохранили во Flutter
            val imagePath = widgetData.getString("nutrition_chart_path", null)
            
            if (imagePath != null) {
                val file = File(imagePath)
                if (file.exists()) {
                    val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                    views.setImageViewBitmap(R.id.widget_image, bitmap)
                }
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}