import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/empresa_service.dart';
import '../theme/app_colors.dart';

class MeusEntregadoresPage extends StatefulWidget {
  const MeusEntregadoresPage({super.key});

  @override
  State<MeusEntregadoresPage> createState() => _MeusEntregadoresPageState();
}

class _MeusEntregadoresPageState extends State<MeusEntregadoresPage> {
  List<dynamic> entregadores = [];
  bool carregando = true;

  @override
  void initState() {
    super.initState();
    carregarEntregadores();
  }

  Future<void> carregarEntregadores() async {
    final resultado = await EmpresaService.buscarEntregadores();

    if (!mounted) return;

    setState(() {
      entregadores = resultado;
      carregando = false;
    });
  }

  String formatarData(String? data) {
    if (data == null || data.isEmpty) {
      return 'Data não informada';
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

  Widget cardEntregador(dynamic entregador) {
    final theme = Theme.of(context);

    final nome = entregador['nome'] ?? 'Entregador';
    final email = entregador['email'] ?? 'E-mail não informado';
    final dataVinculo = entregador['dataVinculo']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              theme.brightness == Brightness.dark ? 0.16 : 0.04,
            ),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        onTap: () async {
          final atualizado = await context.push<bool>(
            '/empresa/entregadores/perfil',
            extra: Map<String, dynamic>.from(entregador),
          );

          if (!mounted) return;

          if (atualizado == true) {
            await carregarEntregadores();
          }
        },
        leading: CircleAvatar(
          radius: 23,
          backgroundColor: AppColors.primary.withOpacity(0.14),
          child: const Icon(Icons.person, color: AppColors.primary),
        ),
        title: Text(
          nome.toString(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '$email\n'
            'Vinculado em: ${formatarData(dataVinculo)}',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
        isThreeLine: true,
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Meus Entregadores'), centerTitle: true),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: carregarEntregadores,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.20),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.primary.withOpacity(0.14),
                          child: const Icon(
                            Icons.groups,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Total de entregadores',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          '${entregadores.length}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (entregadores.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withOpacity(
                            0.35,
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.person_off,
                            size: 46,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Nenhum entregador vinculado',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Quando um entregador aceitar o vínculo, ele aparecerá aqui.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...entregadores.map(cardEntregador),
                ],
              ),
            ),
    );
  }
}
