import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/google_api_config.dart';

class DirectionsService {
  static const String routesUrl =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  static Future<Map<String, dynamic>?> buscarRota(
    String origem,
    String destino,
    List<String> waypoints,
  ) async {
    try {
      final origemLatLng = _converterCoordenada(origem);
      final destinoLatLng = _converterCoordenada(destino);

      if (origemLatLng == null || destinoLatLng == null) {
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

      final response = await http.post(
        Uri.parse(routesUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': GoogleApiConfig.apiKey,
          'X-Goog-FieldMask':
              'routes.duration,'
              'routes.staticDuration,'
              'routes.distanceMeters,'
              'routes.polyline.encodedPolyline,'
              'routes.optimizedIntermediateWaypointIndex,'
              'routes.travelAdvisory.speedReadingIntervals',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        print('Erro Routes API: ${response.statusCode}');
        print(response.body);
        return null;
      }

      final data = jsonDecode(response.body);
      final routes = data['routes'];

      if (routes == null || routes.isEmpty) {
        return null;
      }

      final route = routes[0];

      final encodedPolyline = route['polyline']?['encodedPolyline']?.toString();

      if (encodedPolyline == null || encodedPolyline.isEmpty) {
        return null;
      }

      return {
        'overview_polyline': {'points': encodedPolyline},
        'distanceMeters': route['distanceMeters'] ?? 0,
        'duration': route['duration'] ?? '0s',
        'staticDuration': route['staticDuration'] ?? '0s',
        'optimizedIntermediateWaypointIndex':
            route['optimizedIntermediateWaypointIndex'] ?? [],
        'speedReadingIntervals':
            route['travelAdvisory']?['speedReadingIntervals'] ?? [],
      };
    } catch (e) {
      print('Erro ao buscar rota: $e');
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

      return {'latitude': latitude, 'longitude': longitude};
    } catch (e) {
      return null;
    }
  }
}
