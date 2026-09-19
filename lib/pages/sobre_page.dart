import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class SobrePage extends StatelessWidget {
  const SobrePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Sobre o App'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 10),

          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary,
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.local_shipping,
                color: Colors.white,
                size: 52,
              ),
            ),
          ),

          const SizedBox(height: 18),

          Text(
            'Entregue Já',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'Sua rota, suas entregas, tudo organizado.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 30),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withOpacity(0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(
                    theme.brightness == Brightness.dark ? 0.16 : 0.04,
                  ),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppColors.primary.withOpacity(0.14),
                      child: const Icon(
                        Icons.info_outline,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Sobre',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                Text(
                  'O Entregue Já é um aplicativo desenvolvido para ajudar '
                  'entregadores a organizarem suas entregas de forma simples '
                  'e eficiente.',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 14),

                Text(
                  'O aplicativo permite organizar entregas, escanear QR Codes, '
                  'ler etiquetas, traçar rotas e acompanhar o status de cada '
                  'entrega.',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withOpacity(0.35),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.success.withOpacity(0.14),
                  child: const Icon(
                    Icons.verified_outlined,
                    color: AppColors.success,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Versão do aplicativo',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '1.0.0',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          Text(
            'Entregue Já © 2026',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
