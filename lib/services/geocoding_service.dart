import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/google_api_config.dart';

class GeocodingService {
  static Future<Map<String, double>?> buscarCoordenadas(String endereco) async {
    try {
      if (endereco.trim().isEmpty) {
        return null;
      }

      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': endereco.trim(),
        'region': 'br',
        'language': 'pt-BR',
        'key': GoogleApiConfig.apiKey,
      });

      print('Buscando coordenadas: $endereco');

      final response = await http.get(uri);

      print('Google Geocoding status HTTP: ${response.statusCode}');

      if (response.statusCode != 200) {
        print('Erro HTTP Google Geocoding: ${response.body}');
        return null;
      }

      final Map<String, dynamic> data = jsonDecode(response.body);

      final status = data['status'];

      if (status != 'OK') {
        print('Google Geocoding status: $status');

        if (data['error_message'] != null) {
          print('Google Geocoding erro: ${data['error_message']}');
        }

        return null;
      }

      final resultados = data['results'];

      if (resultados == null || resultados.isEmpty) {
        print('Nenhuma coordenada encontrada para: $endereco');
        return null;
      }

      final location = resultados[0]['geometry']['location'];

      final latitude = (location['lat'] as num).toDouble();
      final longitude = (location['lng'] as num).toDouble();

      print('Coordenadas encontradas: $latitude, $longitude');

      return {'lat': latitude, 'lng': longitude};
    } catch (e) {
      print('Erro Google Geocoding: $e');
      return null;
    }
  }
}
