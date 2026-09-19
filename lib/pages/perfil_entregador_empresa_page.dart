import 'package:flutter/material.dart';

import '../services/empresa_service.dart';
import '../theme/app_colors.dart';
import 'empresa_entregas_page.dart';

class PerfilEntregadorEmpresaPage extends StatelessWidget {
  final Map<String, dynamic> entregador;

  const PerfilEntregadorEmpresaPage({super.key, required this.entregador});

  Future<void> desvincularEntregador(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Desvincular entregador'),
          content: Text(
            'Deseja realmente desvincular '
            '${entregador["nome"] ?? "este entregador"} '
            'da empresa?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Desvincular'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) {
      return;
    }

    final sucesso = await EmpresaService.desvincularEntregador(
      entregador["email"],
    );

    if (!context.mounted) return;

    if (sucesso) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entregador desvinculado com sucesso')),
      );

      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao desvincular entregador')),
      );
    }
  }

  String formatarData(String? data) {
    if (data == null || data.isEmpty) {
      return 'Não informada';
    }

    try {
      final date = DateTime.parse(data);

      final dia = date.day.toString().padLeft(2, '0');

      final mes = date.month.toString().padLeft(2, '0');

      final ano = date.year.toString();

      final hora = date.hour.toString().padLeft(2, '0');

      final minuto = date.minute.toString().padLeft(2, '0');

      return '$dia/$mes/$ano às $hora:$minuto';
    } catch (e) {
      return data;
    }
  }

  Widget cardInfo({
    required BuildContext context,
    required IconData icon,
    required String titulo,
    required String valor,
    required Color color,
  }) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(
          titulo,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          valor.isEmpty ? 'Não informado' : valor,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final nome = entregador["nome"]?.toString() ?? "Entregador";

    final email = entregador["email"]?.toString() ?? "";

    final veiculo = entregador["veiculo"]?.toString().trim() ?? "";

    final capacidade = entregador["capacidadeCarga"]?.toString().trim() ?? "";

    final dataVinculo = entregador["dataVinculo"]?.toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil do Entregador'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(
                      theme.brightness == Brightness.dark ? 0.28 : 0.14,
                    ),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 60,
                backgroundColor: theme.cardColor,
                child: const Icon(
                  Icons.person,
                  color: AppColors.primary,
                  size: 60,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          Center(
            child: Text(
              nome,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),

          const SizedBox(height: 8),

          Center(
            child: Text(
              email,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          const SizedBox(height: 25),

          cardInfo(
            context: context,
            icon: Icons.email,
            titulo: 'E-mail',
            valor: email,
            color: Colors.deepPurple,
          ),

          cardInfo(
            context: context,
            icon: Icons.directions_car,
            titulo: 'Veículo',
            valor: veiculo.isEmpty ? 'Não informado' : veiculo,
            color: AppColors.primary,
          ),

          cardInfo(
            context: context,
            icon: Icons.inventory_2,
            titulo: 'Capacidade de carga',
            valor: capacidade.isEmpty ? 'Não informada' : '$capacidade kg',
            color: Colors.orange,
          ),

          cardInfo(
            context: context,
            icon: Icons.calendar_today,
            titulo: 'Vinculado desde',
            valor: formatarData(dataVinculo),
            color: AppColors.success,
          ),

          const SizedBox(height: 14),

          SizedBox(
            height: 55,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.list_alt),
              label: const Text('Ver Entregas'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final email = entregador['email']?.toString() ?? '';

                final nome = entregador['nome']?.toString() ?? 'Entregador';

                if (email.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('E-mail do entregador não disponível'),
                    ),
                  );

                  return;
                }

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EmpresaEntregasPage(
                      entregadorEmail: email,
                      entregadorNome: nome,
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            height: 55,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.link_off),
              label: const Text('Desvincular Entregador'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                desvincularEntregador(context);
              },
            ),
          ),
        ],
      ),
    );
  }
}
