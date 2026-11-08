import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';
import 'empresa_service.dart' as empresa_service;

class DirectionsService {
  static Future<Map<String, String>> _headersAutenticados() async {
    final tokenEntregador = await AuthService.obterToken();

    if (tokenEntregador != null && tokenEntregador.isNotEmpty) {
      return AuthService.headersAutenticados();
    }

    return empresa_service.EmpresaService.headersAutenticados();
  }

  static Future<Map<String, dynamic>?> buscarRota(
    String origem,
    String destino,
    List<String> waypoints,
  ) async {
    try {
      final origemLatLng = _converterCoordenada(origem);
      final destinoLatLng = _converterCoordenada(destino);

      if (origemLatLng == null || destinoLatLng == null) {
        debugPrint('Origem ou destino inválido.');
        return null;
      }

      final intermediarios = <Map<String, dynamic>>[];

      for (final waypoint in waypoints) {
        final coordenada = _converterCoordenada(waypoint);

        if (coordenada != null) {
          intermediarios.add({
            'location': {
              'latLng': {
                'latitude': coordenada['latitude'],
                'longitude': coordenada['longitude'],
              },
            },
          });
        }
      }

      final body = <String, dynamic>{
        'origin': {
          'location': {
            'latLng': {
              'latitude': origemLatLng['latitude'],
              'longitude': origemLatLng['longitude'],
            },
          },
        },
        'destination': {
          'location': {
            'latLng': {
              'latitude': destinoLatLng['latitude'],
              'longitude': destinoLatLng['longitude'],
            },
          },
        },
        'travelMode': 'DRIVE',
        'routingPreference': 'TRAFFIC_AWARE',
        'computeAlternativeRoutes': false,
        'languageCode': 'pt-BR',
        'units': 'METRIC',
      };

      if (intermediarios.isNotEmpty) {
        body['intermediates'] = intermediarios;
        body['optimizeWaypointOrder'] = true;
      }

      final url = '${ApiConfig.baseUrl}/rotas/calcular';
      final headers = await _headersAutenticados();

      debugPrint('Buscando rota pelo backend...');
      debugPrint('URL: $url');

      final response = await http
          .post(
            Uri.parse(url),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('Status rota backend: ${response.statusCode}');

      if (response.statusCode == 401) {
        debugPrint('Sessão inválida ou token JWT expirado.');
        return null;
      }

      if (response.statusCode == 403) {
        debugPrint('Usuário sem permissão para calcular rotas.');
        return null;
      }

      if (response.statusCode != 200) {
        debugPrint('Erro ao calcular rota: ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body);

      if (data is! Map<String, dynamic>) {
        debugPrint('Resposta inválida do backend de rotas.');
        return null;
      }

      final routes = data['routes'];

      if (routes is! List || routes.isEmpty) {
        debugPrint('Backend não retornou nenhuma rota.');
        return null;
      }

      if (routes.first is! Map) {
        debugPrint('Formato de rota inválido.');
        return null;
      }

      final route = Map<String, dynamic>.from(routes.first as Map);

      final polylineData = route['polyline'];

      final encodedPolyline = polylineData is Map
          ? polylineData['encodedPolyline']?.toString()
          : null;

      if (encodedPolyline == null || encodedPolyline.isEmpty) {
        debugPrint('Rota retornada sem polyline.');
        return null;
      }

      final legs = <Map<String, dynamic>>[];

      final legsResponse = route['legs'];

      if (legsResponse is List) {
        for (final legResponse in legsResponse) {
          if (legResponse is! Map) continue;

          final leg = Map<String, dynamic>.from(legResponse);
          final steps = <Map<String, dynamic>>[];

          final stepsResponse = leg['steps'];

          if (stepsResponse is List) {
            for (final stepResponse in stepsResponse) {
              if (stepResponse is! Map) continue;

              final step = Map<String, dynamic>.from(stepResponse);

              final navigationInstruction = step['navigationInstruction'];

              final instruction = navigationInstruction is Map
                  ? navigationInstruction['instructions']?.toString() ?? ''
                  : '';

              final maneuver = navigationInstruction is Map
                  ? navigationInstruction['maneuver']?.toString() ?? ''
                  : '';

              final stepPolyline = step['polyline'];

              steps.add({
                'distanceMeters': step['distanceMeters'] ?? 0,
                'staticDuration': step['staticDuration'] ?? '0s',
                'instruction': instruction,
                'maneuver': maneuver,
                'startLocation': step['startLocation'],
                'endLocation': step['endLocation'],
                'polyline': stepPolyline is Map
                    ? stepPolyline['encodedPolyline']?.toString() ?? ''
                    : '',
              });
            }
          }

          legs.add({
            'distanceMeters': leg['distanceMeters'] ?? 0,
            'duration': leg['duration'] ?? '0s',
            'staticDuration': leg['staticDuration'] ?? '0s',
            'startLocation': leg['startLocation'],
            'endLocation': leg['endLocation'],
            'steps': steps,
          });
        }
      }

      final optimizedIndices = <int>[];

      final indicesResponse = route['optimizedIntermediateWaypointIndex'];

      if (indicesResponse is List) {
        for (final index in indicesResponse) {
          if (index is num) {
            optimizedIndices.add(index.toInt());
          }
        }
      }

      debugPrint('Rota calculada com sucesso.');
      debugPrint('Polyline recebida: ${encodedPolyline.length} caracteres.');
      debugPrint('Distância: ${route['distanceMeters']} metros.');
      debugPrint('Trechos da rota: ${legs.length}.');

      return {
        'overview_polyline': {'points': encodedPolyline},
        'distanceMeters': route['distanceMeters'] ?? 0,
        'duration': route['duration'] ?? '0s',
        'staticDuration': route['staticDuration'] ?? '0s',
        'optimizedIntermediateWaypointIndex': optimizedIndices,
        'legs': legs,
      };
    } catch (e) {
      debugPrint('Erro ao buscar rota pelo backend: $e');
      return null;
    }
  }

  static Map<String, double>? _converterCoordenada(String coordenada) {
    try {
      final partes = coordenada.split(',');

      if (partes.length != 2) {
        return null;
      }

      final latitude = double.tryParse(partes[0].trim());
      final longitude = double.tryParse(partes[1].trim());

      if (latitude == null || longitude == null) {
        return null;
      }

      if (latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180) {
        return null;
      }

      return {'latitude': latitude, 'longitude': longitude};
    } catch (_) {
      return null;
    }
  }
}
