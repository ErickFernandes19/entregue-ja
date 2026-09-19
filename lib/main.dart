import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/empresa_home_page.dart';
import 'pages/home_page.dart';
import 'pages/selection_page.dart';
import 'providers/entregas_provider.dart';
import 'providers/theme_provider.dart';
import 'services/auth_service.dart';
import 'services/empresa_service.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => EntregasProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MeuApp(),
    ),
  );
}

class MeuApp extends StatelessWidget {
  const MeuApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Entregue Já',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      home: const SplashPage(),
    );
  }
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  Future<Widget> verificarLogin() async {
    final usuario = await AuthService.usuarioLogado();
    final empresa = await EmpresaService.empresaLogada();

    if (usuario != null) {
      return const HomePage();
    }

    if (empresa != null) {
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

        return snapshot.data!;
      },
    );
  }
}
