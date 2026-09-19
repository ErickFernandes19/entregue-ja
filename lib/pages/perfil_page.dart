import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'editar_perfil_page.dart';

class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key});

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  String nome = 'Entregador';
  String email = '';
  String? fotoUrl;
  Map<String, dynamic>? empresaVinculada;

  final ImagePicker picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    carregarDadosUsuario();
  }

  Future<void> carregarDadosUsuario() async {
    final perfil = await AuthService.buscarPerfil();
    final empresa = await AuthService.buscarEmpresaVinculada();

    if (!mounted) return;

    final foto = perfil?['foto']?.toString() ?? '';

    setState(() {
      nome = perfil?['nome'] ?? 'Entregador';
      email = perfil?['email'] ?? '';
      fotoUrl = foto.isEmpty ? null : ApiConfig.urlArquivo(foto);
      empresaVinculada = empresa;
    });
  }

  Future<void> escolherFoto(ImageSource source) async {
    final imagem = await picker.pickImage(source: source, imageQuality: 70);

    if (imagem == null) return;

    final foto = await AuthService.atualizarFotoPerfil(imagem.path);

    if (!mounted) return;

    if (foto == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Erro ao atualizar foto')));

      return;
    }

    setState(() {
      fotoUrl = ApiConfig.urlArquivo(foto);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Foto atualizada com sucesso')),
    );
  }

  Future<void> abrirOpcoesFoto() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final theme = Theme.of(context);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              children: [
                ListTile(
                  title: Text(
                    'Foto de perfil',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Escolha uma opção',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withOpacity(0.15),
                    child: const Icon(
                      Icons.photo_camera,
                      color: AppColors.primary,
                    ),
                  ),
                  title: Text(
                    'Tirar foto',
                    style: TextStyle(color: theme.colorScheme.onSurface),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    escolherFoto(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withOpacity(0.15),
                    child: const Icon(
                      Icons.photo_library,
                      color: AppColors.primary,
                    ),
                  ),
                  title: Text(
                    'Escolher da galeria',
                    style: TextStyle(color: theme.colorScheme.onSurface),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    escolherFoto(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> editarPerfil() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditarPerfilPage(nome: nome, email: email),
      ),
    );

    await carregarDadosUsuario();
  }

  Widget avatarPerfil() {
    final theme = Theme.of(context);

    return Center(
      child: GestureDetector(
        onTap: abrirOpcoesFoto,
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(
                      theme.brightness == Brightness.dark ? 0.30 : 0.16,
                    ),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 62,
                backgroundColor: theme.cardColor,
                backgroundImage: fotoUrl == null
                    ? null
                    : NetworkImage(fotoUrl!),
                child: fotoUrl == null
                    ? const Icon(
                        Icons.person,
                        color: AppColors.primary,
                        size: 64,
                      )
                    : null,
              ),
            ),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: theme.cardColor, width: 3),
              ),
              child: const Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget cardInfo({
    required IconData icon,
    required String titulo,
    required String valor,
    required Color color,
    VoidCallback? onTap,
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
        onTap: onTap,
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
        trailing: onTap == null
            ? null
            : Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
      ),
    );
  }

  Widget cardEmpresaVinculada() {
    final vinculado = empresaVinculada?['vinculado'] == true;

    if (!vinculado) {
      return cardInfo(
        icon: Icons.business,
        titulo: 'Empresa vinculada',
        valor: 'Nenhuma empresa vinculada no momento',
        color: AppColors.warning,
      );
    }

    final nomeEmpresa = empresaVinculada?['nome'] ?? 'Empresa';
    final emailEmpresa = empresaVinculada?['email'] ?? '';

    return cardInfo(
      icon: Icons.business,
      titulo: nomeEmpresa.toString(),
      valor: emailEmpresa.toString().isEmpty
          ? 'Empresa vinculada'
          : emailEmpresa.toString(),
      color: AppColors.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Meu Perfil'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          avatarPerfil(),

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

          if (email.isNotEmpty) ...[
            const SizedBox(height: 6),

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
          ],

          const SizedBox(height: 28),

          cardEmpresaVinculada(),

          cardInfo(
            icon: Icons.person,
            titulo: 'Nome',
            valor: nome,
            color: AppColors.primary,
          ),

          cardInfo(
            icon: Icons.email,
            titulo: 'E-mail',
            valor: email,
            color: Colors.deepPurple,
          ),

          cardInfo(
            icon: Icons.photo_camera,
            titulo: 'Foto de perfil',
            valor: 'Toque para adicionar ou alterar foto',
            color: AppColors.success,
            onTap: abrirOpcoesFoto,
          ),

          const SizedBox(height: 8),

          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: editarPerfil,
              icon: const Icon(Icons.edit),
              label: const Text('Editar Perfil'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: abrirOpcoesFoto,
              icon: const Icon(Icons.photo_camera),
              label: const Text('Alterar Foto'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.brightness == Brightness.dark
                    ? AppColors.primaryLight
                    : AppColors.primary,
                side: BorderSide(
                  color: theme.brightness == Brightness.dark
                      ? AppColors.primaryLight
                      : AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
