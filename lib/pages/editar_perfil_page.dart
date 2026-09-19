import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class EditarPerfilPage extends StatefulWidget {
  final String nome;
  final String email;

  const EditarPerfilPage({super.key, required this.nome, required this.email});

  @override
  State<EditarPerfilPage> createState() => _EditarPerfilPageState();
}

class _EditarPerfilPageState extends State<EditarPerfilPage> {
  late TextEditingController nomeController;
  late TextEditingController emailController;

  bool salvando = false;

  @override
  void initState() {
    super.initState();

    nomeController = TextEditingController(text: widget.nome);

    emailController = TextEditingController(text: widget.email);
  }

  Future<void> salvar() async {
    if (salvando) return;

    final nome = nomeController.text.trim();

    final email = emailController.text.trim();

    if (nome.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preencha nome e e-mail')));

      return;
    }

    if (!email.contains('@') || !email.contains('.')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Informe um e-mail válido')));

      return;
    }

    setState(() {
      salvando = true;
    });

    final resultado = await AuthService.atualizarPerfil(
      nome: nome,
      email: email,
    );

    if (!mounted) return;

    setState(() {
      salvando = false;
    });

    if (resultado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível atualizar o perfil')),
      );

      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Perfil atualizado com sucesso'),
        backgroundColor: AppColors.success,
      ),
    );

    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    nomeController.dispose();
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Editar Perfil'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
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
                    theme.brightness == Brightness.dark ? 0.20 : 0.05,
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
                      backgroundColor: AppColors.primary.withOpacity(0.12),
                      child: const Icon(
                        Icons.person_outline,
                        color: AppColors.primary,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Text(
                        'Informações pessoais',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                TextField(
                  controller: nomeController,
                  enabled: !salvando,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),

                const SizedBox(height: 18),

                TextField(
                  controller: emailController,
                  enabled: !salvando,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: salvando ? null : salvar,
              icon: salvando
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(
                salvando ? 'Salvando...' : 'Salvar',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
