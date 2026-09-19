import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppWidgets {
  static Widget titulo(String texto) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.bold,
        color: AppColors.text,
      ),
    );
  }

  static Widget subtitulo(String texto) {
    return Text(
      texto,
      style: const TextStyle(fontSize: 15, color: AppColors.subtitle),
    );
  }

  static Widget espacamento() {
    return const SizedBox(height: 20);
  }
}
