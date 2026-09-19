class ApiConfig {
  static const String baseUrl = 'http://177.39.176.239:8080';

  static const String auth = '$baseUrl/auth';
  static const String empresas = '$baseUrl/empresas';
  static const String entregas = '$baseUrl/entregas';

  static String urlArquivo(String? caminho) {
    if (caminho == null || caminho.trim().isEmpty) {
      return '';
    }

    if (caminho.startsWith('http://') || caminho.startsWith('https://')) {
      return caminho;
    }

    if (caminho.startsWith('/')) {
      return '$baseUrl$caminho';
    }

    return '$baseUrl/$caminho';
  }
}
