import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/api_config.dart';
import '../services/empresa_service.dart';
import '../theme/app_colors.dart';
import 'editar_empresa_perfil_page.dart';

class EmpresaPerfilPage extends StatefulWidget {
  const EmpresaPerfilPage({super.key});

  @override
  State<EmpresaPerfilPage> createState() => _EmpresaPerfilPageState();
}

class _EmpresaPerfilPageState extends State<EmpresaPerfilPage> {
  String nome = 'Empresa';
  String email = '';
  String? fotoUrl;
  List<dynamic> entregadores = [];
  bool carregando = true;

  final ImagePicker picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    carregarEmpresa();
  }

  Future<void> carregarEmpresa() async {
    final empresaEmail = await EmpresaService.empresaLogada();
    final empresaNome = await EmpresaService.nomeEmpresa();
    final empresaFoto = await EmpresaService.fotoEmpresa();
    final listaEntregadores = await EmpresaService.buscarEntregadores();

    if (!mounted) return;

    setState(() {
      email = empresaEmail ?? '';
      nome = empresaNome ?? 'Empresa';

      fotoUrl = empresaFoto == null || empresaFoto.isEmpty
          ? null
          : ApiConfig.urlArquivo(empresaFoto);

      entregadores = listaEntregadores;
      carregando = false;
    });
  }

  Future<void> escolherFoto(ImageSource source) async {
    final imagem = await picker.pickImage(source: source, imageQuality: 70);

    if (imagem == null) return;

    final foto = await EmpresaService.atualizarFotoEmpresa(imagem.path);

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
                    'Logo da empresa',
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
    final atualizado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditarEmpresaPerfilPage(nome: nome, email: email),
      ),
    );

    if (atualizado == true) {
      await carregarEmpresa();
    }
  }

  Widget avatarEmpresa() {
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
                        Icons.business,
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

  Widget cardEntregador(dynamic entregador) {
    final theme = Theme.of(context);

    final nomeEntregador = entregador['nome'] ?? 'Entregador';

    final emailEntregador = entregador['email'] ?? 'E-mail não informado';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
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
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.14),
          child: const Icon(Icons.person, color: AppColors.primary),
        ),
        title: Text(
          nomeEntregador.toString(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          emailEntregador.toString(),
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil da Empresa'), centerTitle: true),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: carregarEmpresa,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  avatarEmpresa(),

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

                  const SizedBox(height: 6),

                  Center(
                    child: Text(
                      email.isEmpty ? 'E-mail não informado' : email,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  cardInfo(
                    icon: Icons.business,
                    titulo: 'Nome da empresa',
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
                    titulo: 'Logo da empresa',
                    valor: 'Toque para adicionar ou alterar logo',
                    color: AppColors.success,
                    onTap: abrirOpcoesFoto,
                  ),

                  cardInfo(
                    icon: Icons.groups,
                    titulo: 'Entregadores vinculados',
                    valor: '${entregadores.length} entregador(es)',
                    color: Colors.orange,
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
                      label: const Text('Alterar Logo'),
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

                  const SizedBox(height: 24),

                  Text(
                    'Entregadores',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),

                  const SizedBox(height: 12),

                  if (entregadores.isEmpty)
                    cardInfo(
                      icon: Icons.person_off,
                      titulo: 'Nenhum entregador vinculado',
                      valor: 'Vincule um entregador para ele aparecer aqui.',
                      color: Colors.orange,
                    )
                  else
                    ...entregadores.map(cardEntregador),
                ],
              ),
            ),
    );
  }
}
