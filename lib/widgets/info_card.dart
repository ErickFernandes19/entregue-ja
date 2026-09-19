import 'package:flutter/material.dart';

class InfoCard extends StatelessWidget {
  final String title;
  final String value;

  const InfoCard({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),

      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,

        children: [
          Text(title, style: const TextStyle(fontSize: 18)),

          const SizedBox(height: 12),

          Text(
            value,

            style: const TextStyle(
              fontSize: 32,
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
