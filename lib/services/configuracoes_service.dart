import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

class ConfiguracoesService {
  static Future<String?> _usuario() async {
    return await AuthService.usuarioLogado();
  }

  static Future<void> salvarConfiguracoes({
    required String veiculo,
    required String capacidade,
    required String consumoMedio,
    required String precoCombustivel,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final email = await _usuario();

    if (email == null) return;

    await prefs.setString('veiculo_$email', veiculo);

    await prefs.setString('capacidade_entregas_$email', capacidade);

    await prefs.setString('consumo_medio_$email', consumoMedio);

    await prefs.setString('preco_combustivel_$email', precoCombustivel);
  }

  static Future<String?> buscarVeiculo() async {
    final prefs = await SharedPreferences.getInstance();

    final email = await _usuario();

    if (email == null) return null;

    return prefs.getString('veiculo_$email');
  }

  static Future<String?> buscarCapacidade() async {
    final prefs = await SharedPreferences.getInstance();

    final email = await _usuario();

    if (email == null) return null;

    return prefs.getString('capacidade_entregas_$email');
  }

  static Future<String?> buscarConsumoMedio() async {
    final prefs = await SharedPreferences.getInstance();

    final email = await _usuario();

    if (email == null) return null;

    return prefs.getString('consumo_medio_$email');
  }

  static Future<String?> buscarPrecoCombustivel() async {
    final prefs = await SharedPreferences.getInstance();

    final email = await _usuario();

    if (email == null) return null;

    return prefs.getString('preco_combustivel_$email');
  }
}
