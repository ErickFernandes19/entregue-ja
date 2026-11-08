class ApiConfig {
  static const String _urlLocal = 'http://192.168.1.107:8080';

  static const String _urlConfigurada = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _urlLocal,
  );

  static String get baseUrl {
    final url = _urlConfigurada.trim();

    if (url.endsWith('/')) {
      return url.substring(0, url.length - 1);
    }

    return url;
  }

  static String get auth => '$baseUrl/auth';

  static String get empresas => '$baseUrl/empresas';

  static String get entregas => '$baseUrl/entregas';

  static String urlArquivo(String? caminho) {
    if (caminho == null || caminho.trim().isEmpty) {
      return '';
    }

    final arquivo = caminho.trim();

    if (arquivo.startsWith('http://') || arquivo.startsWith('https://')) {
      return arquivo;
    }

    if (arquivo.startsWith('/')) {
      return '$baseUrl$arquivo';
    }

    return '$baseUrl/$arquivo';
  }
}
