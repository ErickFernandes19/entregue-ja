import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

class EmpresaService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static Future<String?> obterTokenEmpresa() async {
    return _secureStorage.read(key: 'empresa_jwt_token');
  }

  static Future<Map<String, String>> headersAutenticados() async {
    final token = await obterTokenEmpresa();

    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, String>> headersImagem() async {
    final token = await obterTokenEmpresa();

    return {
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static MediaType tipoImagem(String nomeArquivo) {
    final nome = nomeArquivo.toLowerCase();

    if (nome.endsWith('.png')) {
      return MediaType('image', 'png');
    }

    if (nome.endsWith('.webp')) {
      return MediaType('image', 'webp');
    }

    return MediaType('image', 'jpeg');
  }

  static String urlFotoEmpresa(String? referencia) {
    if (referencia == null || referencia.trim().isEmpty) {
      return '';
    }

    final valor = referencia.trim();

    if (valor.startsWith('http://') || valor.startsWith('https://')) {
      return valor;
    }

    return ApiConfig.urlArquivo(valor);
  }

  static Future<Uint8List?> buscarBytesFotoEmpresa(String? referencia) async {
    try {
      final url = urlFotoEmpresa(referencia);

      if (url.isEmpty) {
        return null;
      }

      final response = await http.get(
        Uri.parse(url),
        headers: await headersImagem(),
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }

      print(
        'Erro ao carregar foto empresa. '
        'Status: ${response.statusCode}',
      );

      return null;
    } catch (e) {
      print('Erro ao buscar imagem da empresa: $e');
      return null;
    }
  }

  static Future<void> salvarReferenciaFotoEmpresa(String? referencia) async {
    final prefs = await SharedPreferences.getInstance();

    if (referencia == null || referencia.trim().isEmpty) {
      await prefs.remove('empresa_foto');
      return;
    }

    await prefs.setString('empresa_foto', referencia.trim());
  }

  static Future<Map<String, dynamic>?> login(String email, String senha) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.empresas}/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'senha': senha}),
      );

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body));

        final token = data['token']?.toString();

        if (token == null || token.isEmpty) {
          print('Login da empresa sem token JWT.');
          return null;
        }

        await _secureStorage.write(key: 'empresa_jwt_token', value: token);

        await salvarReferenciaFotoEmpresa(data['foto']?.toString());

        print('Login da empresa realizado e token armazenado.');

        return data;
      }

      print('Erro login empresa. Status: ${response.statusCode}');

      return null;
    } catch (e) {
      print('Erro login empresa: $e');
      return null;
    }
  }

  static Future<void> salvarDadosEmpresa({
    required String email,
    required String nome,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('empresa_logada', email);
    await prefs.setString('empresa_nome', nome);
  }

  static Future<String?> nomeEmpresa() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('empresa_nome');
  }

  static Future<void> salvarEmpresa(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('empresa_logada', email);
  }

  static Future<String?> empresaLogada() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('empresa_logada');
  }

  static Future<void> logoutEmpresa() async {
    await _secureStorage.delete(key: 'empresa_jwt_token');

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('empresa_logada');
    await prefs.remove('empresa_nome');
    await prefs.remove('empresa_foto');
  }

  static Future<bool> vincularEntregador(String entregadorEmail) async {
    try {
      final empresaEmail = await empresaLogada();

      if (empresaEmail == null) return false;

      final response = await http.put(
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(empresaEmail)}/'
          'entregadores/'
          '${Uri.encodeComponent(entregadorEmail)}/solicitar',
        ),
        headers: await headersAutenticados(),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erro ao solicitar vínculo: $e');
      return false;
    }
  }

  static Future<List<dynamic>> buscarEntregadoresPendentes() async {
    try {
      final email = await empresaLogada();

      if (email == null) return [];

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(email)}/'
          'entregadores-pendentes',
        ),
        headers: await headersAutenticados(),
      );

      if (response.statusCode == 200) {
        return List<dynamic>.from(jsonDecode(response.body));
      }

      return [];
    } catch (e) {
      print('Erro ao buscar vínculos pendentes: $e');
      return [];
    }
  }

  static Future<List<dynamic>> buscarEntregadores() async {
    try {
      final email = await empresaLogada();

      if (email == null) return [];

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(email)}/entregadores',
        ),
        headers: await headersAutenticados(),
      );

      if (response.statusCode == 200) {
        return List<dynamic>.from(jsonDecode(response.body));
      }

      return [];
    } catch (e) {
      print('Erro ao buscar entregadores: $e');
      return [];
    }
  }

  static Future<bool> cancelarSolicitacaoVinculo(String entregadorEmail) async {
    try {
      final empresaEmail = await empresaLogada();

      if (empresaEmail == null) return false;

      final response = await http.put(
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(empresaEmail)}/'
          'entregadores/'
          '${Uri.encodeComponent(entregadorEmail)}/'
          'cancelar-solicitacao',
        ),
        headers: await headersAutenticados(),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erro ao cancelar solicitação de vínculo: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> atualizarPerfilEmpresa({
    required String nome,
    required String email,
  }) async {
    try {
      final emailAtual = await empresaLogada();

      if (emailAtual == null || emailAtual.isEmpty) {
        return null;
      }

      final response = await http.put(
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(emailAtual)}/perfil',
        ),
        headers: await headersAutenticados(),
        body: jsonEncode({'nome': nome, 'email': email}),
      );

      print(
        'Atualizar perfil empresa status: '
        '${response.statusCode}',
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = Map<String, dynamic>.from(jsonDecode(response.body));

      final novoNome = data['nome']?.toString();
      final novoEmail = data['email']?.toString();

      if (novoNome == null || novoEmail == null) {
        return null;
      }

      await salvarDadosEmpresa(email: novoEmail, nome: novoNome);

      await salvarReferenciaFotoEmpresa(data['foto']?.toString());

      return data;
    } catch (e) {
      print('Erro ao atualizar perfil da empresa: $e');
      return null;
    }
  }

  static Future<int> totalEntregadores() async {
    try {
      final email = await empresaLogada();

      if (email == null) return 0;

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(email)}/'
          'entregadores/total',
        ),
        headers: await headersAutenticados(),
      );

      if (response.statusCode == 200) {
        final dados = Map<String, dynamic>.from(jsonDecode(response.body));

        final total = dados['total'];

        if (total is num) {
          return total.toInt();
        }

        return int.tryParse(total?.toString() ?? '') ?? 0;
      }

      return 0;
    } catch (e) {
      print('Erro ao buscar total de entregadores: $e');
      return 0;
    }
  }

  static Future<bool> desvincularEntregador(String entregadorEmail) async {
    try {
      final empresaEmail = await empresaLogada();

      if (empresaEmail == null) return false;

      final response = await http.put(
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(empresaEmail)}/'
          'desvincular/'
          '${Uri.encodeComponent(entregadorEmail)}',
        ),
        headers: await headersAutenticados(),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erro ao desvincular: $e');
      return false;
    }
  }

  static Future<String?> atualizarFotoEmpresa(String caminhoArquivo) async {
    try {
      final email = await empresaLogada();

      if (email == null || email.isEmpty) {
        return null;
      }

      final token = await obterTokenEmpresa();

      if (token == null || token.isEmpty) {
        print('Token da empresa não encontrado.');
        return null;
      }

      final request = http.MultipartRequest(
        'PUT',
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(email)}/foto',
        ),
      );

      request.headers['Authorization'] = 'Bearer $token';

      request.files.add(
        await http.MultipartFile.fromPath(
          'foto',
          caminhoArquivo,
          contentType: tipoImagem(caminhoArquivo),
        ),
      );

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(body));

        final foto = data['foto']?.toString();

        if (foto == null || foto.isEmpty) {
          return null;
        }

        await salvarReferenciaFotoEmpresa(foto);

        return foto;
      }

      print(
        'Erro foto empresa status: '
        '${response.statusCode}. '
        'Resposta: $body',
      );

      return null;
    } catch (e) {
      print('Erro ao enviar foto da empresa: $e');
      return null;
    }
  }

  static Future<String?> atualizarFotoEmpresaBytes({
    required Uint8List bytes,
    required String nomeArquivo,
  }) async {
    try {
      final email = await empresaLogada();
      final token = await obterTokenEmpresa();

      if (email == null ||
          email.isEmpty ||
          token == null ||
          token.isEmpty ||
          bytes.isEmpty) {
        return null;
      }

      final request = http.MultipartRequest(
        'PUT',
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(email)}/foto',
        ),
      );

      request.headers['Authorization'] = 'Bearer $token';

      request.files.add(
        http.MultipartFile.fromBytes(
          'foto',
          bytes,
          filename: nomeArquivo,
          contentType: tipoImagem(nomeArquivo),
        ),
      );

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(body));

        final foto = data['foto']?.toString();

        if (foto == null || foto.isEmpty) {
          return null;
        }

        await salvarReferenciaFotoEmpresa(foto);

        return foto;
      }

      print(
        'Erro ao enviar foto por bytes. '
        'Status: ${response.statusCode}. '
        'Resposta: $body',
      );

      return null;
    } catch (e) {
      print('Erro ao enviar foto por bytes: $e');
      return null;
    }
  }

  static Future<String?> fotoEmpresa() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('empresa_foto');
  }

  static Future<bool> cadastrar(String nome, String email, String senha) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.empresas}/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'nome': nome, 'email': email, 'senha': senha}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erro cadastro empresa: $e');
      return false;
    }
  }
}
