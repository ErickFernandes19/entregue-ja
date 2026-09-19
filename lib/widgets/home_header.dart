import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class HomeHeader extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final VoidCallback onPerfil;
  final VoidCallback onConfiguracoes;

  const HomeHeader({
    super.key,
    required this.titulo,
    required this.subtitulo,
    required this.onPerfil,
    required this.onConfiguracoes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 45, 20, 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF3048C7), Color(0xFF5472F2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onConfiguracoes,
            icon: const Icon(Icons.settings, color: Colors.white),
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitulo,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ],
            ),
          ),

          GestureDetector(
            onTap: onPerfil,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(40),
              ),
              child: const CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, color: AppColors.primary, size: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
