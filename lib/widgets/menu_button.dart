import 'package:flutter/material.dart';

class MenuButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Color textColor;
  final Color iconColor;
  final VoidCallback onTap;

  const MenuButton({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    this.textColor = Colors.black,
    this.iconColor = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),

      onTap: onTap,

      child: Container(
        height: 150,

        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
        ),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Icon(icon, size: 48, color: iconColor),

            const SizedBox(height: 12),

            Text(
              title,

              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
