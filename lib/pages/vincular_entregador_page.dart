import 'package:flutter/material.dart';

import '../services/empresa_service.dart';
import '../theme/app_colors.dart';

class VincularEntregadorPage extends StatefulWidget {
  const VincularEntregadorPage({super.key});

  @override
  State<VincularEntregadorPage> createState() => _VincularEntregadorPageState();
}

class _VincularEntregadorPageState extends State<VincularEntregadorPage> {
  final emailController = TextEditingController();

  bool carregando = false;
  bool carregandoPendentes = true;

  List<dynamic> pendentes = [];

  @override
  void initState() {
    super.initState();
    carregarPendentes();
  }

  Future<void> carregarPendentes() async {
    final resultado = await EmpresaService.buscarEntregadoresPendentes();

    if (!mounted) return;

    setState(() {
      pendentes = resultado;
      carregandoPendentes = false;
    });
  }

  Future<void> cancelarSolicitacao(String entregadorEmail) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancelar solicitação'),
          content: const Text(
            'Deseja realmente cancelar a solicitação de vínculo com este entregador?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Voltar'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context, true);
              },
              icon: const Icon(Icons.close),
              label: const Text('Cancelar solicitação'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    final sucesso = await EmpresaService.cancelarSolicitacaoVinculo(
      entregadorEmail,
    );

    if (!mounted) return;

    if (sucesso) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitação cancelada com sucesso')),
      );

      await carregarPendentes();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível cancelar a solicitação'),
        ),
      );
    }
  }

  Future<void> vincularEntregador() async {
    final entregadorEmail = emailController.text.trim();

    if (entregadorEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite o e-mail do entregador')),
      );

      return;
    }

    setState(() {
      carregando = true;
    });

    final sucesso = await EmpresaService.vincularEntregador(entregadorEmail);

    if (!mounted) return;

    setState(() {
      carregando = false;
    });

    if (sucesso) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitação enviada ao entregador')),
      );

      emailController.clear();

      await carregarPendentes();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar a solicitação')),
      );
    }
  }

  Widget cardPendente(Map<String, dynamic> entregador) {
    final theme = Theme.of(context);

    final nome = entregador['nome']?.toString() ?? 'Entregador';
    final email = entregador['email']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.warning.withOpacity(0.25)),
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
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: AppColors.warning.withOpacity(0.14),
                child: const Icon(Icons.schedule, color: AppColors.warning),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        email,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Aguardando resposta',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: email.isEmpty
                  ? null
                  : () async {
                      await cancelarSolicitacao(email);
                    },
              icon: const Icon(Icons.close),
              label: const Text('Cancelar solicitação'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vincular Entregador'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: carregarPendentes,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(
                      theme.brightness == Brightness.dark ? 0.16 : 0.05,
                    ),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enviar solicitação',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Informe o e-mail do entregador que deseja vincular à empresa.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                    decoration: const InputDecoration(
                      labelText: 'E-mail do entregador',
                      hintText: 'exemplo@email.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: carregando ? null : vincularEntregador,
                      icon: carregando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.person_add),
                      label: Text(
                        carregando ? 'Enviando...' : 'Enviar solicitação',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Vínculos pendentes',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (pendentes.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      pendentes.length.toString(),
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (carregandoPendentes)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (pendentes.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withOpacity(0.35),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.person_search_outlined,
                      size: 46,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Nenhum vínculo pendente',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'As solicitações enviadas aparecerão aqui.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...pendentes.map(
                (item) => cardPendente(Map<String, dynamic>.from(item)),
              ),
          ],
        ),
      ),
    );
  }
}
