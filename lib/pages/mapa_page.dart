import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/entregas_provider.dart';
import '../services/api_service.dart';
import '../services/directions_service.dart';
import '../services/geocoding_service.dart';
import '../theme/app_colors.dart';

class MapaPage extends StatefulWidget {
  const MapaPage({super.key});

  @override
  State<MapaPage> createState() => _MapaPageState();
}

class _MapaPageState extends State<MapaPage> {
  GoogleMapController? mapController;

  LatLng posicaoAtual = const LatLng(-23.5505, -46.6333);

  final Set<Marker> markers = {};
  Set<Polyline> polylines = {};

  bool carregandoMapa = true;

  double distanciaRotaKm = 0;
  int duracaoRotaMinutos = 0;

  static const String estiloMapaEscuro = '''
[
  {
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#212121"
      }
    ]
  },
  {
    "elementType": "labels.icon",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#757575"
      }
    ]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [
      {
        "color": "#212121"
      }
    ]
  },
  {
    "featureType": "administrative",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#757575"
      }
    ]
  },
  {
    "featureType": "administrative.country",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#9e9e9e"
      }
    ]
  },
  {
    "featureType": "administrative.land_parcel",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "administrative.locality",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#bdbdbd"
      }
    ]
  },
  {
    "featureType": "poi",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#757575"
      }
    ]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#181818"
      }
    ]
  },
  {
    "featureType": "poi.park",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#616161"
      }
    ]
  },
  {
    "featureType": "poi.park",
    "elementType": "labels.text.stroke",
    "stylers": [
      {
        "color": "#1b1b1b"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "geometry.fill",
    "stylers": [
      {
        "color": "#2c2c2c"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#8a8a8a"
      }
    ]
  },
  {
    "featureType": "road.arterial",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#373737"
      }
    ]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#3c3c3c"
      }
    ]
  },
  {
    "featureType": "road.highway.controlled_access",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#4e4e4e"
      }
    ]
  },
  {
    "featureType": "road.local",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#616161"
      }
    ]
  },
  {
    "featureType": "transit",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#757575"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#000000"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#3d3d3d"
      }
    ]
  }
]
''';

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      await carregarMapaCompleto();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (mapController != null) {
      aplicarEstiloMapa();
    }
  }

  Future<void> aplicarEstiloMapa() async {
    final controller = mapController;

    if (controller == null) return;

    final escuro = Theme.of(context).brightness == Brightness.dark;

    await controller.setMapStyle(escuro ? estiloMapaEscuro : null);
  }

  Future<void> carregarMapaCompleto() async {
    if (mounted) {
      setState(() {
        carregandoMapa = true;
      });
    }

    await buscarLocalizacaoAtual();
    await carregarMarkers();
    await carregarRota();

    if (!mounted) return;

    setState(() {
      carregandoMapa = false;
    });
  }

  Future<void> marcarEntregasComoEmRota() async {
    final entregasProvider = Provider.of<EntregasProvider>(
      context,
      listen: false,
    );

    final entregasPendentes = entregasProvider.entregas
        .where((entrega) => entrega.id != null && !entrega.entregue)
        .toList();

    for (final entrega in entregasPendentes) {
      await ApiService.marcarEntregaEmRota(entrega.id!);
    }

    await entregasProvider.carregarEntregasDoBackend();
  }

  Future<void> buscarLocalizacaoAtual() async {
    try {
      final servicoAtivo = await Geolocator.isLocationServiceEnabled();

      if (!servicoAtivo) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ative a localização do celular para visualizar sua posição.',
            ),
          ),
        );

        return;
      }

      LocationPermission permissao = await Geolocator.checkPermission();

      if (permissao == LocationPermission.denied) {
        permissao = await Geolocator.requestPermission();

        if (permissao == LocationPermission.denied) {
          return;
        }
      }

      if (permissao == LocationPermission.deniedForever) {
        return;
      }

      final Position position = await Geolocator.getCurrentPosition();

      posicaoAtual = LatLng(position.latitude, position.longitude);

      mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(posicaoAtual, 15),
      );
    } catch (e) {
      debugPrint('Erro ao buscar localização: $e');
    }
  }

  Future<List<PontoEntrega>> buscarPontosPendentes() async {
    final entregasProvider = Provider.of<EntregasProvider>(
      context,
      listen: false,
    );

    final entregasPendentes = entregasProvider.entregas
        .where((entrega) => !entrega.entregue)
        .toList();

    final List<PontoEntrega> pontos = [];

    for (final entrega in entregasPendentes) {
      final coordenadas = await GeocodingService.buscarCoordenadas(
        entrega.endereco,
      );

      if (coordenadas == null) {
        debugPrint('Não foi possível localizar: ${entrega.endereco}');

        continue;
      }

      final latLng = LatLng(coordenadas['lat']!, coordenadas['lng']!);

      pontos.add(
        PontoEntrega(
          coordenada: '${latLng.latitude},${latLng.longitude}',
          latLng: latLng,
        ),
      );
    }

    return pontos;
  }

  Future<void> carregarMarkers() async {
    final entregasProvider = Provider.of<EntregasProvider>(
      context,
      listen: false,
    );

    final entregas = entregasProvider.entregas;

    final Set<Marker> novosMarkers = {};

    novosMarkers.add(
      Marker(
        markerId: const MarkerId('entregador'),
        position: posicaoAtual,
        infoWindow: const InfoWindow(title: 'Você está aqui'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
    );

    for (int i = 0; i < entregas.length; i++) {
      final coordenadas = await GeocodingService.buscarCoordenadas(
        entregas[i].endereco,
      );

      if (coordenadas == null) {
        continue;
      }

      novosMarkers.add(
        Marker(
          markerId: MarkerId('entrega_${entregas[i].id ?? i}'),
          position: LatLng(coordenadas['lat']!, coordenadas['lng']!),
          infoWindow: InfoWindow(
            title: entregas[i].cliente,
            snippet: entregas[i].endereco,
          ),
          icon: entregas[i].entregue
              ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
              : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }

    if (!mounted) return;

    setState(() {
      markers
        ..clear()
        ..addAll(novosMarkers);
    });
  }

  Future<void> carregarRota() async {
    try {
      final pontos = await buscarPontosPendentes();

      if (pontos.isEmpty) {
        if (!mounted) return;

        setState(() {
          polylines.clear();
          distanciaRotaKm = 0;
          duracaoRotaMinutos = 0;
        });

        return;
      }

      final origem = '${posicaoAtual.latitude},${posicaoAtual.longitude}';

      final destino = pontos.last.coordenada;

      final waypoints = pontos.length > 1
          ? pontos
                .sublist(0, pontos.length - 1)
                .map((ponto) => ponto.coordenada)
                .toList()
          : <String>[];

      final rota = await DirectionsService.buscarRota(
        origem,
        destino,
        waypoints,
      );

      if (rota == null) {
        debugPrint('API de rotas não retornou uma rota.');

        return;
      }

      final polyline = rota['overview_polyline']?['points'];

      if (polyline == null || polyline.toString().isEmpty) {
        return;
      }

      final List<LatLng> coordenadasRota = decodificarPolyline(
        polyline.toString(),
      );

      double distanceMeters = 0;

      int segundos = 0;

      if (rota['distanceMeters'] != null) {
        distanceMeters = (rota['distanceMeters'] as num).toDouble();

        final duration = rota['duration']?.toString() ?? '0s';

        segundos = converterDuracaoParaSegundos(duration);
      } else if (rota['legs'] is List) {
        final legs = rota['legs'] as List;

        for (final leg in legs) {
          final distancia = leg['distance']?['value'];

          final duracao = leg['duration']?['value'];

          if (distancia is num) {
            distanceMeters += distancia.toDouble();
          }

          if (duracao is num) {
            segundos += duracao.toInt();
          }
        }
      }

      if (!mounted) return;

      setState(() {
        distanciaRotaKm = distanceMeters / 1000;

        duracaoRotaMinutos = (segundos / 60).ceil();

        polylines = {
          Polyline(
            polylineId: const PolylineId('rota_completa'),
            points: coordenadasRota,
            width: 6,
            color: AppColors.primary,
          ),
        };
      });

      await ajustarCameraNaRota(coordenadasRota);
    } catch (e) {
      debugPrint('Erro ao carregar rota: $e');
    }
  }

  int converterDuracaoParaSegundos(String duration) {
    try {
      return double.parse(duration.replaceAll('s', '')).round();
    } catch (e) {
      return 0;
    }
  }

  Future<void> ajustarCameraNaRota(List<LatLng> pontos) async {
    if (pontos.isEmpty || mapController == null) {
      return;
    }

    double minLat = pontos.first.latitude;

    double maxLat = pontos.first.latitude;

    double minLng = pontos.first.longitude;

    double maxLng = pontos.first.longitude;

    for (final ponto in pontos) {
      if (ponto.latitude < minLat) {
        minLat = ponto.latitude;
      }

      if (ponto.latitude > maxLat) {
        maxLat = ponto.latitude;
      }

      if (ponto.longitude < minLng) {
        minLng = ponto.longitude;
      }

      if (ponto.longitude > maxLng) {
        maxLng = ponto.longitude;
      }
    }

    if (minLat == maxLat && minLng == maxLng) {
      await mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(pontos.first, 15),
      );

      return;
    }

    await mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  Future<void> atualizarMapa() async {
    await carregarMapaCompleto();
  }

  Future<void> iniciarRotaGoogleMaps() async {
    final entregasProvider = Provider.of<EntregasProvider>(
      context,
      listen: false,
    );

    final entregasPendentes = entregasProvider.entregas
        .where((entrega) => !entrega.entregue)
        .toList();

    if (entregasPendentes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma entrega pendente para iniciar rota'),
        ),
      );

      return;
    }

    await marcarEntregasComoEmRota();

    final destinos = entregasPendentes
        .map((entrega) => entrega.endereco)
        .toList();

    final destinoFinal = destinos.last;

    final waypoints = destinos.length > 1
        ? destinos.sublist(0, destinos.length - 1).join('|')
        : '';

    final parametros = <String, String>{
      'api': '1',
      'origin': '${posicaoAtual.latitude},${posicaoAtual.longitude}',
      'destination': destinoFinal,
      'travelmode': 'driving',
    };

    if (waypoints.isNotEmpty) {
      parametros['waypoints'] = waypoints;
    }

    final uri = Uri.https('www.google.com', '/maps/dir/', parametros);

    final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!abriu && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o Google Maps')),
      );
    }
  }

  List<LatLng> decodificarPolyline(String encoded) {
    final List<LatLng> pontos = [];

    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int b;
      int shift = 0;
      int result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;

        result |= (b & 0x1f) << shift;

        shift += 5;
      } while (b >= 0x20);

      final int dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);

      lat += dlat;

      shift = 0;
      result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;

        result |= (b & 0x1f) << shift;

        shift += 5;
      } while (b >= 0x20);

      final int dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);

      lng += dlng;

      pontos.add(LatLng(lat / 100000, lng / 100000));
    }

    return pontos;
  }

  Widget cardSuperior() {
    final theme = Theme.of(context);

    final entregasProvider = Provider.of<EntregasProvider>(context);

    final total = entregasProvider.entregas.length;

    final pendentes = entregasProvider.entregas
        .where((e) => !e.entregue)
        .length;

    final entregues = entregasProvider.entregas.where((e) => e.entregue).length;

    return Positioned(
      top: 18,
      left: 18,
      right: 18,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                theme.brightness == Brightness.dark ? 0.30 : 0.12,
              ),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withOpacity(0.14),
                  child: const Icon(Icons.map, color: AppColors.primary),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mapa da rota',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        '$total entregas • '
                        '$pendentes pendentes • '
                        '$entregues entregues',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                IconButton(
                  onPressed: atualizarMapa,
                  icon: const Icon(Icons.refresh),
                  color: AppColors.primary,
                ),
              ],
            ),

            if (distanciaRotaKm > 0) ...[
              const SizedBox(height: 12),

              Divider(height: 1, color: theme.colorScheme.outlineVariant),

              const SizedBox(height: 12),

              Row(
                children: [
                  const Icon(Icons.route, size: 18, color: AppColors.primary),

                  const SizedBox(width: 6),

                  Text(
                    '${distanciaRotaKm.toStringAsFixed(1)} km',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),

                  const SizedBox(width: 18),

                  const Icon(
                    Icons.schedule,
                    size: 18,
                    color: AppColors.primary,
                  ),

                  const SizedBox(width: 6),

                  Text(
                    '$duracaoRotaMinutos min',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget cardInferior() {
    final theme = Theme.of(context);

    final entregasProvider = Provider.of<EntregasProvider>(context);

    final pendentes = entregasProvider.entregas
        .where((e) => !e.entregue)
        .length;

    return Positioned(
      left: 18,
      right: 18,
      bottom: 26,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                theme.brightness == Brightness.dark ? 0.32 : 0.14,
              ),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.success.withOpacity(0.14),
              child: const Icon(Icons.navigation, color: AppColors.success),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Text(
                pendentes == 0
                    ? 'Nenhuma entrega pendente'
                    : '$pendentes entrega(s) pronta(s) para rota',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),

            const SizedBox(width: 8),

            ElevatedButton(
              onPressed: pendentes == 0 ? null : iniciarRotaGoogleMaps,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Iniciar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget botaoCentralizar() {
    final theme = Theme.of(context);

    return Positioned(
      right: 18,
      bottom: 118,
      child: FloatingActionButton(
        heroTag: 'centralizar',
        mini: true,
        backgroundColor: theme.cardColor,
        foregroundColor: AppColors.primary,
        onPressed: () {
          mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(posicaoAtual, 15),
          );
        },
        child: const Icon(Icons.my_location),
      ),
    );
  }

  Widget botaoVoltar() {
    final theme = Theme.of(context);

    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 18, top: 120),
          child: FloatingActionButton(
            heroTag: 'voltar',
            mini: true,
            backgroundColor: theme.cardColor,
            foregroundColor: AppColors.primary,
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Icon(Icons.arrow_back),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: posicaoAtual,
              zoom: 14,
            ),
            markers: markers,
            polylines: polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            trafficEnabled: true,
            onMapCreated: (controller) {
              mapController = controller;

              aplicarEstiloMapa();
            },
          ),

          botaoVoltar(),

          SafeArea(child: cardSuperior()),

          cardInferior(),

          botaoCentralizar(),

          if (carregandoMapa)
            Container(
              color: Colors.black.withOpacity(
                theme.brightness == Brightness.dark ? 0.25 : 0.10,
              ),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class PontoEntrega {
  final String coordenada;
  final LatLng latLng;

  PontoEntrega({required this.coordenada, required this.latLng});
}
