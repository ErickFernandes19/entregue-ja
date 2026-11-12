import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../pages/cadastrar_entrega_manual_page.dart';
import '../pages/cadastrar_entrega_page.dart';
import '../pages/configuracoes_page.dart';
import '../pages/detalhes_entrega_entregador_page.dart';
import '../pages/detalhes_entrega_page.dart';
import '../pages/editar_entrega_page.dart';
import '../pages/editar_empresa_perfil_page.dart';
import '../pages/editar_perfil_page.dart';
import '../pages/empresa_configuracoes_page.dart';
import '../pages/empresa_entregas_page.dart';
import '../pages/empresa_home_page.dart';
import '../pages/empresa_login_page.dart';
import '../pages/empresa_notificacoes_page.dart';
import '../pages/empresa_perfil_page.dart';
import '../pages/empresa_register_page.dart';
import '../pages/entregas_page.dart';
import '../pages/finalizar_entrega_page.dart';
import '../pages/home_page.dart';
import '../pages/login_page.dart';
import '../pages/mapa_page.dart';
import '../pages/meus_entregadores_page.dart';
import '../pages/notificacoes_page.dart';
import '../pages/ocr_page.dart';
import '../pages/perfil_page.dart';
import '../pages/perfil_entregador_empresa_page.dart';
import '../pages/recuperar_senha_empresa_page.dart';
import '../pages/recuperar_senha_page.dart';
import '../pages/register_page.dart';
import '../pages/relatorio_page.dart';
import '../pages/scanner_page.dart';
import '../pages/selection_page.dart';
import '../pages/sobre_page.dart';
import '../pages/suporte_page.dart';
import '../pages/veiculo_configuracoes_page.dart';
import '../pages/verificar_empresa_cadastro_page.dart';
import '../pages/verificar_cadastro_page.dart';
import '../pages/vincular_entregador_page.dart';
import '../services/auth_service.dart';
import '../services/empresa_service.dart';

class AppRouter {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/',
    redirect: (context, state) async {
      final caminho = state.matchedLocation;
      final usuario = await AuthService.usuarioLogado();
      final empresa = await EmpresaService.empresaLogada();
      final entregadorLogado = usuario != null;
      final empresaLogada = empresa != null;

      if (caminho == '/') {
        if (entregadorLogado) return '/entregador/inicio';
        if (empresaLogada) return '/empresa/inicio';
        return '/selecionar';
      }

      final rotaProtegidaEntregador =
          caminho == '/entregador/inicio' ||
          caminho == '/entregador/notificacoes' ||
          caminho == '/entregador/configuracoes' ||
          caminho.startsWith('/entregador/configuracoes/') ||
          caminho == '/entregador/suporte' ||
          caminho == '/entregador/sobre' ||
          caminho == '/entregador/perfil' ||
          caminho.startsWith('/entregador/perfil/') ||
          caminho == '/entregador/mapa' ||
          caminho == '/entregador/entregas' ||
          caminho.startsWith('/entregador/entregas/') ||
          caminho == '/entregador/relatorios';

      if (rotaProtegidaEntregador && !entregadorLogado) {
        return '/entregador/login';
      }

      final rotaProtegidaEmpresa =
          caminho == '/empresa/inicio' ||
          caminho == '/empresa/notificacoes' ||
          caminho == '/empresa/cadastrar-entrega' ||
          caminho == '/empresa/entregas' ||
          caminho.startsWith('/empresa/entregas/') ||
          caminho == '/empresa/vincular-entregador' ||
          caminho == '/empresa/configuracoes' ||
          caminho == '/empresa/perfil' ||
          caminho.startsWith('/empresa/perfil/') ||
          caminho == '/empresa/entregadores' ||
          caminho.startsWith('/empresa/entregadores/') ||
          caminho == '/empresa/suporte' ||
          caminho == '/empresa/sobre';

      if (rotaProtegidaEmpresa && !empresaLogada) {
        return '/empresa/login';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SelectionPage()),
      GoRoute(
        path: '/selecionar',
        builder: (context, state) => const SelectionPage(),
      ),
      GoRoute(
        path: '/entregador/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/entregador/cadastro',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/entregador/verificar-cadastro',
        builder: (context, state) {
          final email = state.extra;
          if (email is! String || email.isEmpty) {
            return const RegisterPage();
          }
          return VerificarCadastroPage(email: email);
        },
      ),
      GoRoute(
        path: '/entregador/recuperar-senha',
        builder: (context, state) => RecuperarSenhaPage(
          emailInicial: state.extra is String ? state.extra as String : '',
        ),
      ),
      GoRoute(
        path: '/empresa/login',
        builder: (context, state) => const EmpresaLoginPage(),
      ),
      GoRoute(
        path: '/empresa/cadastro',
        builder: (context, state) => const EmpresaRegisterPage(),
      ),
      GoRoute(
        path: '/empresa/verificar-cadastro',
        builder: (context, state) {
          final email = state.extra;
          if (email is! String || email.isEmpty) {
            return const EmpresaRegisterPage();
          }
          return VerificarEmpresaCadastroPage(email: email);
        },
      ),
      GoRoute(
        path: '/empresa/recuperar-senha',
        builder: (context, state) => RecuperarSenhaEmpresaPage(
          emailInicial: state.extra is String ? state.extra as String : '',
        ),
      ),
      GoRoute(
        path: '/entregador/inicio',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/entregador/notificacoes',
        builder: (context, state) => const NotificacoesPage(),
      ),
      GoRoute(
        path: '/entregador/configuracoes',
        builder: (context, state) => const ConfiguracoesPage(),
      ),
      GoRoute(
        path: '/entregador/configuracoes/veiculo',
        builder: (context, state) => const VeiculoConfiguracoesPage(),
      ),
      GoRoute(
        path: '/entregador/suporte',
        builder: (context, state) => const SuportePage(),
      ),
      GoRoute(
        path: '/entregador/sobre',
        builder: (context, state) => const SobrePage(),
      ),
      GoRoute(
        path: '/entregador/perfil',
        builder: (context, state) => const PerfilPage(),
      ),
      GoRoute(
        path: '/entregador/perfil/editar',
        builder: (context, state) {
          final dados = state.extra;
          if (dados is! Map<String, dynamic> ||
              dados['nome'] is! String ||
              dados['email'] is! String) {
            return const PerfilPage();
          }
          return EditarPerfilPage(
            nome: dados['nome'] as String,
            email: dados['email'] as String,
          );
        },
      ),
      GoRoute(
        path: '/entregador/mapa',
        builder: (context, state) => const MapaPage(),
      ),
      GoRoute(
        path: '/entregador/entregas',
        builder: (context, state) => const EntregasPage(),
      ),
      GoRoute(
        path: '/entregador/entregas/cadastro-manual',
        builder: (context, state) => const CadastrarEntregaManualPage(),
      ),
      GoRoute(
        path: '/entregador/entregas/scanner',
        builder: (context, state) => const ScannerPage(),
      ),
      GoRoute(
        path: '/entregador/entregas/ocr',
        builder: (context, state) => const OcrPage(),
      ),
      GoRoute(
        path: '/entregador/entregas/detalhes',
        builder: (context, state) {
          final dados = state.extra;
          if (dados is! Map<String, dynamic>) {
            return const EntregasPage();
          }
          return DetalhesEntregaEntregadorPage(entrega: dados);
        },
      ),
      GoRoute(
        path: '/entregador/entregas/finalizar',
        builder: (context, state) {
          final dados = state.extra;
          if (dados is! Map<String, dynamic> ||
              dados['entregaId'] is! int ||
              dados['cliente'] is! String ||
              dados['endereco'] is! String) {
            return const EntregasPage();
          }
          return FinalizarEntregaPage(
            entregaId: dados['entregaId'] as int,
            cliente: dados['cliente'] as String,
            endereco: dados['endereco'] as String,
          );
        },
      ),
      GoRoute(
        path: '/entregador/relatorios',
        builder: (context, state) => const RelatorioPage(),
      ),
      GoRoute(
        path: '/empresa/inicio',
        builder: (context, state) => const EmpresaHomePage(),
      ),
      GoRoute(
        path: '/empresa/notificacoes',
        builder: (context, state) => const EmpresaNotificacoesPage(),
      ),
      GoRoute(
        path: '/empresa/cadastrar-entrega',
        builder: (context, state) => const CadastrarEntregaPage(),
      ),
      GoRoute(
        path: '/empresa/entregas',
        builder: (context, state) => const EmpresaEntregasPage(),
      ),
      GoRoute(
        path: '/empresa/entregas/detalhes',
        builder: (context, state) {
          final dados = state.extra;
          if (dados is! Map<String, dynamic>) {
            return const EmpresaEntregasPage();
          }
          return DetalhesEntregaPage(entrega: dados);
        },
      ),
      GoRoute(
        path: '/empresa/entregas/editar',
        builder: (context, state) {
          final dados = state.extra;
          if (dados is! Map<String, dynamic>) {
            return const EmpresaEntregasPage();
          }
          return EditarEntregaPage(entrega: dados);
        },
      ),
      GoRoute(
        path: '/empresa/vincular-entregador',
        builder: (context, state) => const VincularEntregadorPage(),
      ),
      GoRoute(
        path: '/empresa/configuracoes',
        builder: (context, state) => const EmpresaConfiguracoesPage(),
      ),
      GoRoute(
        path: '/empresa/perfil',
        builder: (context, state) => const EmpresaPerfilPage(),
      ),
      GoRoute(
        path: '/empresa/perfil/editar',
        builder: (context, state) {
          final dados = state.extra;
          if (dados is! Map<String, dynamic> ||
              dados['nome'] is! String ||
              dados['email'] is! String) {
            return const EmpresaPerfilPage();
          }
          return EditarEmpresaPerfilPage(
            nome: dados['nome'] as String,
            email: dados['email'] as String,
          );
        },
      ),
      GoRoute(
        path: '/empresa/entregadores',
        builder: (context, state) => const MeusEntregadoresPage(),
      ),
      GoRoute(
        path: '/empresa/entregadores/perfil',
        builder: (context, state) {
          final dados = state.extra;
          if (dados is! Map<String, dynamic>) {
            return const MeusEntregadoresPage();
          }
          return PerfilEntregadorEmpresaPage(entregador: dados);
        },
      ),
      GoRoute(
        path: '/empresa/entregadores/entregas',
        builder: (context, state) {
          final dados = state.extra;
          if (dados is! Map<String, dynamic> ||
              dados['entregadorEmail'] is! String ||
              dados['entregadorNome'] is! String) {
            return const MeusEntregadoresPage();
          }
          return EmpresaEntregasPage(
            entregadorEmail: dados['entregadorEmail'] as String,
            entregadorNome: dados['entregadorNome'] as String,
          );
        },
      ),
      GoRoute(
        path: '/empresa/suporte',
        builder: (context, state) => const SuportePage(),
      ),
      GoRoute(
        path: '/empresa/sobre',
        builder: (context, state) => const SobrePage(),
      ),
    ],
  );
}
