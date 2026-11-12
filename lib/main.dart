import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_router.dart';
import 'pages/empresa_home_page.dart';
import 'pages/home_page.dart';
import 'pages/selection_page.dart';
import 'providers/entregas_provider.dart';
import 'providers/theme_provider.dart';
import 'services/auth_service.dart';
import 'services/empresa_service.dart';
import 'theme/app_theme.dart';

final FlutterLocalNotificationsPlugin notificacoesLocais =
    FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> navigatorKey = AppRouter.navigatorKey;

const String canalNotificacoesPadrao = 'entregue_ja_padrao';

bool notificacoesConfiguradas = false;
String? tipoContaAberturaPendente;
String? contaIdAberturaPendente;
bool telaInicialCarregada = false;
bool navegacaoNotificacaoEmAndamento = false;

void registrarAberturaInicial(String? tipoConta, {String? contaId}) {
  tipoContaAberturaPendente = tipoConta ?? '';
  contaIdAberturaPendente = contaId;
  if (telaInicialCarregada) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendente = tipoContaAberturaPendente;
      if (pendente == null) return;
      final idPendente = contaIdAberturaPendente;
      tipoContaAberturaPendente = null;
      contaIdAberturaPendente = null;
      abrirNotificacoes(tipoConta: pendente, contaId: idPendente);
    });
  }
}

StreamSubscription<RemoteMessage>? assinaturaMensagens;
StreamSubscription<RemoteMessage>? assinaturaAbertura;

@pragma('vm:entry-point')
Future<void> tratarMensagemEmSegundoPlano(RemoteMessage mensagem) async {
  await Firebase.initializeApp();
}

Future<void> criarCanaisNotificacao() async {
  final android = notificacoesLocais
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  if (android == null) return;

  for (final som in [true, false]) {
    for (final vibracao in [true, false]) {
      final canalId =
          'entregue_ja_${som ? 'som' : 'silencioso'}_${vibracao ? 'vibracao' : 'sem_vibracao'}';

      await android.createNotificationChannel(
        AndroidNotificationChannel(
          canalId,
          'Entregue Já - ${som ? 'Com som' : 'Silencioso'}'
          '${vibracao ? ' e vibração' : ' sem vibração'}',
          description: 'Avisos de entregas e vínculos',
          importance: Importance.high,
          playSound: som,
          enableVibration: vibracao,
        ),
      );
    }
  }

  await android.createNotificationChannel(
    const AndroidNotificationChannel(
      canalNotificacoesPadrao,
      'Notificações Entregue Já',
      description: 'Avisos de entregas e vínculos',
      importance: Importance.high,
    ),
  );
}

String? idContaDoJwt(String? jwt) {
  if (jwt == null || jwt.isEmpty) return null;
  try {
    final partes = jwt.split('.');
    if (partes.length != 3) return null;
    final dados = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))),
    );
    if (dados is! Map) return null;
    final id = int.tryParse(dados['sub']?.toString() ?? '');
    return id != null && id > 0 ? id.toString() : null;
  } catch (_) {
    return null;
  }
}

Future<bool> destinatarioAutenticado(String? tipoConta, String? contaId) async {
  final tipo = tipoConta?.toUpperCase();
  final id = int.tryParse(contaId ?? '');
  if ((tipo != 'EMPRESA' && tipo != 'ENTREGADOR') || id == null || id <= 0) {
    return false;
  }

  if (tipo == 'EMPRESA') {
    if (await EmpresaService.empresaLogada() == null) return false;
    return idContaDoJwt(await EmpresaService.obterTokenEmpresa()) ==
        id.toString();
  }

  if (await AuthService.usuarioLogado() == null) return false;
  return idContaDoJwt(await AuthService.obterToken()) == id.toString();
}

Future<bool> notificacaoPermitida(
  RemoteMessage mensagem,
  bool contaEmpresa,
  SharedPreferences preferencias,
) async {
  final tipo = mensagem.data['tipo']?.toString().toUpperCase() ?? '';

  String? chaveCategoria;

  if (contaEmpresa) {
    switch (tipo) {
      case 'ENTREGA_CONCLUIDA':
        chaveCategoria = 'empresa_entrega_concluida';
        break;
      case 'ENTREGA_CANCELADA':
        chaveCategoria = 'empresa_entrega_cancelada';
        break;
      case 'ENTREGA_NAO_REALIZADA':
        chaveCategoria = 'empresa_entrega_nao_realizada';
        break;
      case 'VINCULO_ACEITO':
        chaveCategoria = 'empresa_novo_entregador';
        break;
      case 'VINCULO_RECUSADO':
      case 'SOLICITACAO_VINCULO':
        chaveCategoria = 'empresa_solicitacoes';
        break;
      case 'SOLICITACAO_CANCELADA':
        chaveCategoria = 'empresa_solicitacoes';
        break;
      case 'VINCULO_ENCERRADO':
      case 'CONVITE_VINCULO':
      case 'VINCULO_PENDENTE':
        chaveCategoria = null;
        break;
    }
  } else {
    switch (tipo) {
      case 'NOVA_ENTREGA':
      case 'ENTREGA_ATRIBUIDA':
        chaveCategoria = 'notif_novas_entregas';
        break;
      case 'ENTREGA_CANCELADA':
      case 'ENTREGA_CONCLUIDA':
      case 'ENTREGA_NAO_REALIZADA':
        chaveCategoria = 'notif_status_entregas';
        break;
      case 'SOLICITACAO_VINCULO':
      case 'VINCULO_ACEITO':
      case 'VINCULO_RECUSADO':
      case 'CONVITE_VINCULO':
      case 'VINCULO_PENDENTE':
      case 'VINCULO_ENCERRADO':
      case 'SOLICITACAO_CANCELADA':
        chaveCategoria = 'notif_vinculos';
        break;
    }
  }

  if (chaveCategoria == null) return true;

  return preferencias.getBool(chaveCategoria) ?? true;
}

Future<void> exibirNotificacao(RemoteMessage mensagem) async {
  try {
    final tipoConta = mensagem.data['tipoConta']?.toString().toUpperCase();
    final contaId = mensagem.data['contaId']?.toString();
    if (!await destinatarioAutenticado(tipoConta, contaId)) return;
    final contaEmpresa = tipoConta == 'EMPRESA';

    final preferencias = await SharedPreferences.getInstance();

    final permitido = await notificacaoPermitida(
      mensagem,
      contaEmpresa,
      preferencias,
    );

    if (!permitido) return;

    final som =
        preferencias.getBool(contaEmpresa ? 'empresa_sons' : 'notif_sons') ??
        true;

    final vibracao =
        preferencias.getBool(
          contaEmpresa ? 'empresa_vibracao' : 'notif_vibracao',
        ) ??
        true;

    final titulo =
        mensagem.notification?.title ?? mensagem.data['titulo']?.toString();

    final texto =
        mensagem.notification?.body ?? mensagem.data['mensagem']?.toString();

    if (titulo == null && texto == null) return;

    final canalId =
        'entregue_ja_${som ? 'som' : 'silencioso'}_${vibracao ? 'vibracao' : 'sem_vibracao'}';

    final payload = jsonEncode({
      'tipo': mensagem.data['tipo'],
      'tipoConta': mensagem.data['tipoConta'],
      'contaId': mensagem.data['contaId'],
      'entregaId': mensagem.data['entregaId'],
    });

    final id =
        mensagem.messageId?.hashCode ??
        DateTime.now().millisecondsSinceEpoch.remainder(2147483647);

    await notificacoesLocais.show(
      id & 0x7fffffff,
      titulo,
      texto,
      NotificationDetails(
        android: AndroidNotificationDetails(
          canalId,
          'Notificações Entregue Já',
          channelDescription: 'Avisos de entregas e vínculos',
          importance: Importance.high,
          priority: Priority.high,
          playSound: som,
          enableVibration: vibracao,
        ),
      ),
      payload: payload,
    );
  } catch (erro) {
    debugPrint('Erro ao exibir notificação: $erro');
  }
}

void abrirNotificacoes({String? tipoConta, String? contaId}) {
  if (!telaInicialCarregada) {
    tipoContaAberturaPendente = tipoConta ?? '';
    contaIdAberturaPendente = contaId;
    return;
  }

  if (navegacaoNotificacaoEmAndamento) return;
  navegacaoNotificacaoEmAndamento = true;

  () async {
    try {
      if (!await destinatarioAutenticado(tipoConta, contaId)) return;

      if (tipoConta?.toUpperCase() == 'EMPRESA') {
        AppRouter.router.go('/empresa/inicio');
        AppRouter.router.push('/empresa/notificacoes');
      } else if (tipoConta?.toUpperCase() == 'ENTREGADOR') {
        AppRouter.router.go('/entregador/inicio');
        AppRouter.router.push('/entregador/notificacoes');
      }
    } catch (erro) {
      debugPrint('Erro ao abrir notificações: $erro');
    } finally {
      navegacaoNotificacaoEmAndamento = false;
    }
  }();
}

void tratarAberturaMensagem(RemoteMessage mensagem) {
  abrirNotificacoes(
    tipoConta: mensagem.data['tipoConta']?.toString(),
    contaId: mensagem.data['contaId']?.toString(),
  );
}

Future<void> configurarNotificacoes() async {
  if (notificacoesConfiguradas) return;

  notificacoesConfiguradas = true;

  try {
    const inicializacaoAndroid = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    await notificacoesLocais.initialize(
      const InitializationSettings(android: inicializacaoAndroid),
      onDidReceiveNotificationResponse: (resposta) {
        String? tipoConta;
        String? contaId;

        if (resposta.payload != null) {
          try {
            final dados = jsonDecode(resposta.payload!);

            if (dados is Map) {
              tipoConta = dados['tipoConta']?.toString().toUpperCase();
              contaId = dados['contaId']?.toString();
            }
          } catch (erro) {
            debugPrint('Erro ao interpretar notificação: $erro');
          }
        }

        abrirNotificacoes(tipoConta: tipoConta, contaId: contaId);
      },
    );

    await criarCanaisNotificacao();

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await assinaturaMensagens?.cancel();

    assinaturaMensagens = FirebaseMessaging.onMessage.listen((mensagem) {
      unawaited(exibirNotificacao(mensagem));
    });

    await assinaturaAbertura?.cancel();

    assinaturaAbertura = FirebaseMessaging.onMessageOpenedApp.listen(
      tratarAberturaMensagem,
    );
  } catch (erro) {
    notificacoesConfiguradas = false;
    rethrow;
  }
}

Future<void> verificarNotificacaoInicial() async {
  try {
    final mensagem = await FirebaseMessaging.instance.getInitialMessage();

    if (mensagem != null) {
      registrarAberturaInicial(
        mensagem.data['tipoConta']?.toString().toUpperCase(),
        contaId: mensagem.data['contaId']?.toString(),
      );
    }

    final detalhes = await notificacoesLocais.getNotificationAppLaunchDetails();

    if (mensagem == null && detalhes?.didNotificationLaunchApp == true) {
      final payload = detalhes?.notificationResponse?.payload;

      String? tipoConta;
      String? contaId;

      if (payload != null) {
        try {
          final dados = jsonDecode(payload);

          if (dados is Map) {
            tipoConta = dados['tipoConta']?.toString().toUpperCase();
            contaId = dados['contaId']?.toString();
          }
        } catch (erro) {
          debugPrint('Erro ao recuperar notificação: $erro');
        }
      }

      if (tipoContaAberturaPendente == null) {
        registrarAberturaInicial(tipoConta, contaId: contaId);
      }
    }
  } catch (erro) {
    debugPrint('Erro ao verificar notificação inicial: $erro');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Firebase.initializeApp();

      FirebaseMessaging.onBackgroundMessage(tratarMensagemEmSegundoPlano);

      await configurarNotificacoes();
    } catch (erro) {
      debugPrint('Erro ao inicializar Firebase: $erro');
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => EntregasProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MeuApp(),
    ),
  );

  if (!kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      Firebase.apps.isNotEmpty) {
    unawaited(verificarNotificacaoInicial());
  }
}

class MeuApp extends StatefulWidget {
  const MeuApp({super.key});

  @override
  State<MeuApp> createState() => _MeuAppState();
}

class _MeuAppState extends State<MeuApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      telaInicialCarregada = true;
      unawaited(_inicializarSessao());

      if (tipoContaAberturaPendente != null) {
        final tipoConta = tipoContaAberturaPendente;
        final contaId = contaIdAberturaPendente;
        tipoContaAberturaPendente = null;
        contaIdAberturaPendente = null;
        abrirNotificacoes(tipoConta: tipoConta, contaId: contaId);
      }
    });
  }

  Future<void> _inicializarSessao() async {
    try {
      final usuario = await AuthService.usuarioLogado();
      if (usuario != null) {
        await AuthService.inicializarRegistroFcm();
        return;
      }

      final empresa = await EmpresaService.empresaLogada();
      if (empresa != null) {
        await EmpresaService.inicializarRegistroFcm();
      }
    } catch (erro) {
      debugPrint('Erro ao inicializar sessão: $erro');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Entregue Já',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      routerConfig: AppRouter.router,
    );
  }
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  Future<Widget> verificarLogin() async {
    final usuario = await AuthService.usuarioLogado();
    final empresa = await EmpresaService.empresaLogada();

    if (usuario != null) {
      unawaited(AuthService.inicializarRegistroFcm());
      return const HomePage();
    }

    if (empresa != null) {
      unawaited(EmpresaService.inicializarRegistroFcm());
      return const EmpresaHomePage();
    }

    return const SelectionPage();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: verificarLogin(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        telaInicialCarregada = true;
        if (tipoContaAberturaPendente != null) {
          final tipoConta = tipoContaAberturaPendente;
          final contaId = contaIdAberturaPendente;
          tipoContaAberturaPendente = null;
          contaIdAberturaPendente = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            abrirNotificacoes(tipoConta: tipoConta, contaId: contaId);
          });
        }

        return snapshot.data!;
      },
    );
  }
}
