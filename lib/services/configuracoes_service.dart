import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'auth_service.dart';

class ConfiguracoesService {
  static Future<String> _usuario() async {
    final email = await AuthService.usuarioLogado();

    if (email == null || email.trim().isEmpty) {
      throw const ApiException(
        'Sua sessão expirou. Faça login novamente.',
        statusCode: 401,
      );
    }

    return email;
  }

  static Future<void> salvarConfiguracoes({
    required String veiculo,
    required String capacidade,
    required String consumoMedio,
    required String precoCombustivel,
  }) async {
    try {
      final email = await _usuario();
      final prefs = await SharedPreferences.getInstance();
      final configuracoes = <String, String>{
        'veiculo_$email': veiculo,
        'capacidade_entregas_$email': capacidade,
        'consumo_medio_$email': consumoMedio,
        'preco_combustivel_$email': precoCombustivel,
      };

      for (final configuracao in configuracoes.entries) {
        final salvo = await prefs.setString(
          configuracao.key,
          configuracao.value,
        );

        if (!salvo) {
          throw const ApiException(
            'Não foi possível concluir o salvamento no aparelho. '
            'Alguns dados podem ter sido salvos. Tente salvar novamente.',
          );
        }
      }
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        'Não foi possível concluir o salvamento no aparelho. '
        'Alguns dados podem ter sido salvos. Tente salvar novamente.',
      );
    }
  }

  static Future<String?> _buscar(String chave) async {
    try {
      final email = await _usuario();
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('${chave}_$email');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        'Não foi possível carregar as configurações do aparelho. '
        'Tente novamente.',
      );
    }
  }

  static Future<String?> buscarVeiculo() => _buscar('veiculo');

  static Future<String?> buscarCapacidade() => _buscar('capacidade_entregas');

  static Future<String?> buscarConsumoMedio() => _buscar('consumo_medio');

  static Future<String?> buscarPrecoCombustivel() =>
      _buscar('preco_combustivel');
}
