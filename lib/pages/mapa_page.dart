import 'dart:async';

import 'package:flutter/material.dart';

import 'package:geolocator/geolocator.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:provider/provider.dart';

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

  StreamSubscription<Position>? _positionSubscription;

  LatLng posicaoAtual = const LatLng(-23.5505, -46.6333);

  Set<Marker> markers = {};

  Set<Polyline> polylines = {};

  bool carregandoMapa = true;

  bool rotaIniciada = false;

  double distanciaRotaKm = 0;

  int duracaoRotaMinutos = 0;

  DateTime? _ultimaAtualizacaoRota;

  dynamic proximaEntrega;
  LatLng? coordenadaProximaEntrega;
  double distanciaProximaEntregaKm = 0;
  int duracaoProximaEntregaMinutos = 0;
  String instrucaoNavegacao = '';
  String manobraNavegacao = '';
  double distanciaProximaManobraMetros = 0;
  List<Map<String, dynamic>> passosNavegacao = [];
  Timer? _timerSincronizacao;
  bool _sincronizandoEntregas = false;
  bool _calculandoRota = false;
  String _assinaturaEntregas = '';

  static const String estiloMapaEscuro = '''

[

  {

    "elementType": "geometry",

    "stylers": [{"color": "#212121"}]

  },

  {

    "elementType": "labels.icon",

    "stylers": [{"visibility": "off"}]

  },

  {

    "elementType": "labels.text.fill",

    "stylers": [{"color": "#757575"}]

  },

  {

    "elementType": "labels.text.stroke",

    "stylers": [{"color": "#212121"}]

  },

  {

    "featureType": "administrative",

    "elementType": "geometry",

    "stylers": [{"color": "#757575"}]

  },

  {

    "featureType": "administrative.country",

    "elementType": "labels.text.fill",

    "stylers": [{"color": "#9e9e9e"}]

  },

  {

    "featureType": "administrative.land_parcel",

    "stylers": [{"visibility": "off"}]

  },

  {

    "featureType": "administrative.locality",

    "elementType": "labels.text.fill",

    "stylers": [{"color": "#bdbdbd"}]

  },

  {

    "featureType": "poi",

    "elementType": "labels.text.fill",

    "stylers": [{"color": "#757575"}]

  },

  {

    "featureType": "poi.park",

    "elementType": "geometry",

    "stylers": [{"color": "#181818"}]

  },

  {

    "featureType": "poi.park",

    "elementType": "labels.text.fill",

    "stylers": [{"color": "#616161"}]

  },

  {

    "featureType": "road",

    "elementType": "geometry.fill",

    "stylers": [{"color": "#2c2c2c"}]

  },

  {

    "featureType": "road",

    "elementType": "labels.text.fill",

    "stylers": [{"color": "#8a8a8a"}]

  },

  {

    "featureType": "road.arterial",

    "elementType": "geometry",

    "stylers": [{"color": "#373737"}]

  },

  {

    "featureType": "road.highway",

    "elementType": "geometry",

    "stylers": [{"color": "#3c3c3c"}]

  },

  {

    "featureType": "road.highway.controlled_access",

    "elementType": "geometry",

    "stylers": [{"color": "#4e4e4e"}]

  },

  {

    "featureType": "road.local",

    "elementType": "labels.text.fill",

    "stylers": [{"color": "#616161"}]

  },

  {

    "featureType": "transit",

    "elementType": "labels.text.fill",

    "stylers": [{"color": "#757575"}]

  },

  {

    "featureType": "water",

    "elementType": "geometry",

    "stylers": [{"color": "#000000"}]

  },

  {

    "featureType": "water",

    "elementType": "labels.text.fill",

    "stylers": [{"color": "#3d3d3d"}]

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

  @override
  void dispose() {
    _timerSincronizacao?.cancel();
    _positionSubscription?.cancel();

    mapController?.dispose();

    super.dispose();
  }

  bool entregaAtivaParaRota(dynamic entrega) {
    final status = entrega.status.toString().trim().toUpperCase();

    return status == 'PENDENTE' || status == 'EM_ROTA';
  }

  bool possuiCoordenadas(dynamic entrega) {
    if (entrega.latitude == null || entrega.longitude == null) {
      return false;
    }

    final latitude = (entrega.latitude as num).toDouble();

    final longitude = (entrega.longitude as num).toDouble();

    return latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180 &&
        !(latitude == 0 && longitude == 0);
  }

  Future<void> aplicarEstiloMapa() async {
    final controller = mapController;

    if (controller == null) return;

    await controller.setMapStyle(null);
  }

  Future<bool> verificarPermissaoLocalizacao() async {
    final servicoAtivo = await Geolocator.isLocationServiceEnabled();

    if (!servicoAtivo) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ative a localização do celular para utilizar a rota.',
            ),
          ),
        );
      }

      return false;
    }

    LocationPermission permissao = await Geolocator.checkPermission();

    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
    }

    if (permissao == LocationPermission.denied ||
        permissao == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<void> carregarMapaCompleto() async {
    if (mounted) {
      setState(() {
        carregandoMapa = true;

        markers.clear();

        polylines.clear();

        distanciaRotaKm = 0;

        duracaoRotaMinutos = 0;
      });
    }

    try {
      final entregasProvider = Provider.of<EntregasProvider>(
        context,

        listen: false,
      );

      await entregasProvider.carregarEntregasDoBackend();

      if (!mounted) return;

      rotaIniciada = entregasProvider.entregas.any(
        (e) => e.status.toString().trim().toUpperCase() == 'EM_ROTA',
      );

      await buscarLocalizacaoAtual();

      if (!mounted) return;

      await carregarMarkers();

      if (!mounted) return;

      await carregarRota();

      if (!mounted) return;

      _assinaturaEntregas = assinaturaEntregasAtivas();
      if (rotaIniciada) {
        await iniciarMonitoramentoLocalizacao();
      }
    } catch (e) {
      debugPrint('Erro ao carregar mapa: $e');
    } finally {
      if (mounted) {
        setState(() {
          carregandoMapa = false;
        });
      }
    }
  }

  Future<void> buscarLocalizacaoAtual() async {
    try {
      final permitido = await verificarPermissaoLocalizacao();

      if (!permitido) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;

      setState(() {
        posicaoAtual = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      debugPrint('Erro ao buscar localização: $e');
    }
  }

  Future<void> iniciarMonitoramentoLocalizacao() async {
    final permitido = await verificarPermissaoLocalizacao();

    if (!permitido) return;

    await _positionSubscription?.cancel();
    _timerSincronizacao?.cancel();
    _timerSincronizacao = Timer.periodic(
      const Duration(seconds: 12),
      (_) => sincronizarEntregasEmRota(),
    );

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,

      distanceFilter: 5,
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
          (Position position) async {
            if (!mounted || !rotaIniciada) return;

            final novaPosicao = LatLng(position.latitude, position.longitude);

            setState(() {
              posicaoAtual = novaPosicao;

              final novosMarkers = Set<Marker>.from(markers);

              novosMarkers.removeWhere(
                (marker) => marker.markerId.value == 'entregador',
              );

              novosMarkers.add(
                Marker(
                  markerId: const MarkerId('entregador'),

                  position: novaPosicao,

                  infoWindow: const InfoWindow(title: 'Você está aqui'),

                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure,
                  ),
                ),
              );

              markers = novosMarkers;
            });
            atualizarInstrucaoNavegacao();

            await mapController?.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: novaPosicao,

                  zoom: 17,

                  bearing: position.heading >= 0 ? position.heading : 0,

                  tilt: 45,
                ),
              ),
            );

            final agora = DateTime.now();

            if (_ultimaAtualizacaoRota == null ||
                agora.difference(_ultimaAtualizacaoRota!).inSeconds >= 20) {
              _ultimaAtualizacaoRota = agora;

              await carregarRota(ajustarCamera: false);
            }
          },

          onError: (erro) {
            debugPrint('Erro no GPS em tempo real: $erro');
          },
        );
  }

  String assinaturaEntregasAtivas() {
    final provider = Provider.of<EntregasProvider>(context, listen: false);
    final ids =
        provider.entregas
            .where(entregaAtivaParaRota)
            .map((e) => '${e.id}:${e.status}')
            .toList()
          ..sort();
    return ids.join('|');
  }

  Future<void> sincronizarEntregasEmRota() async {
    if (!mounted || !rotaIniciada || _sincronizandoEntregas) return;
    _sincronizandoEntregas = true;
    try {
      final provider = Provider.of<EntregasProvider>(context, listen: false);
      await provider.carregarEntregasDoBackend();
      if (!mounted) return;
      final assinaturaAtual = assinaturaEntregasAtivas();
      if (assinaturaAtual == _assinaturaEntregas) return;
      _assinaturaEntregas = assinaturaAtual;
      if (assinaturaAtual.isEmpty) {
        _timerSincronizacao?.cancel();
        await _positionSubscription?.cancel();
        if (!mounted) return;
        setState(() {
          rotaIniciada = false;
          proximaEntrega = null;
          coordenadaProximaEntrega = null;
          distanciaProximaEntregaKm = 0;
          duracaoProximaEntregaMinutos = 0;
          instrucaoNavegacao = '';
          passosNavegacao = [];
          polylines.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Todas as entregas da rota foram finalizadas.'),
          ),
        );
        await carregarMarkers();
        return;
      }
      await carregarMarkers();
      await carregarRota(ajustarCamera: false);
    } catch (e) {
      debugPrint('Erro ao sincronizar entregas: $e');
    } finally {
      _sincronizandoEntregas = false;
    }
  }

  LatLng? coordenadaDeLocalizacao(dynamic location) {
    if (location is! Map) return null;
    final latLng = location['latLng'];
    if (latLng is! Map) return null;
    final latitude = latLng['latitude'];
    final longitude = latLng['longitude'];
    if (latitude is! num || longitude is! num) return null;
    return LatLng(latitude.toDouble(), longitude.toDouble());
  }

  void atualizarInstrucaoNavegacao() {
    if (!mounted || !rotaIniciada || passosNavegacao.isEmpty) return;
    int indiceMaisProximo = -1;
    double menorDistancia = double.infinity;
    for (int i = 0; i < passosNavegacao.length; i++) {
      final step = passosNavegacao[i];
      final polyline = step['polyline']?.toString() ?? '';
      final pontos = polyline.isNotEmpty
          ? decodificarPolyline(polyline)
          : <LatLng>[];
      if (pontos.isEmpty) {
        final inicio = coordenadaDeLocalizacao(step['startLocation']);
        final fim = coordenadaDeLocalizacao(step['endLocation']);
        if (inicio != null) pontos.add(inicio);
        if (fim != null) pontos.add(fim);
      }
      for (final ponto in pontos) {
        final distancia = Geolocator.distanceBetween(
          posicaoAtual.latitude,
          posicaoAtual.longitude,
          ponto.latitude,
          ponto.longitude,
        );
        if (distancia < menorDistancia) {
          menorDistancia = distancia;
          indiceMaisProximo = i;
        }
      }
    }
    if (indiceMaisProximo < 0 || menorDistancia > 150) return;
    final passo = passosNavegacao[indiceMaisProximo];
    final fim = coordenadaDeLocalizacao(passo['endLocation']);
    final distancia = fim == null
        ? 0.0
        : Geolocator.distanceBetween(
            posicaoAtual.latitude,
            posicaoAtual.longitude,
            fim.latitude,
            fim.longitude,
          );
    final instrucao = passo['instruction']?.toString() ?? '';
    final manobra = passo['maneuver']?.toString() ?? '';
    if (instrucao == instrucaoNavegacao &&
        (distancia - distanciaProximaManobraMetros).abs() < 10)
      return;
    setState(() {
      instrucaoNavegacao = instrucao;
      manobraNavegacao = manobra;
      distanciaProximaManobraMetros = distancia;
    });
  }

  Future<void> marcarEntregasComoEmRota() async {
    final entregasProvider = Provider.of<EntregasProvider>(
      context,

      listen: false,
    );

    final entregasPendentes = entregasProvider.entregas
        .where(
          (entrega) =>
              entrega.id != null &&
              entrega.status.toString().trim().toUpperCase() == 'PENDENTE',
        )
        .toList();

    for (final entrega in entregasPendentes) {
      await ApiService.marcarEntregaEmRota(entrega.id!);
    }

    await entregasProvider.carregarEntregasDoBackend();
  }

  Future<LatLng?> obterCoordenadaEntrega(dynamic entrega) async {
    if (possuiCoordenadas(entrega)) {
      return LatLng(
        (entrega.latitude as num).toDouble(),

        (entrega.longitude as num).toDouble(),
      );
    }

    final endereco = entrega.endereco.toString().trim();

    if (endereco.isEmpty) return null;

    final coordenadas = await GeocodingService.buscarCoordenadas(endereco);

    if (coordenadas == null) {
      debugPrint('Não foi possível localizar: $endereco');

      return null;
    }

    return LatLng(coordenadas['lat']!, coordenadas['lng']!);
  }

  Future<List<PontoEntrega>> buscarPontosPendentes() async {
    final entregasProvider = Provider.of<EntregasProvider>(
      context,
      listen: false,
    );

    final entregasAtivas = entregasProvider.entregas
        .where(entregaAtivaParaRota)
        .toList();

    final List<PontoEntrega> pontos = [];
    final Set<String> processados = {};

    for (final entrega in entregasAtivas) {
      final latLng = await obterCoordenadaEntrega(entrega);

      if (latLng == null) continue;

      final chave =
          '${latLng.latitude.toStringAsFixed(6)},'
          '${latLng.longitude.toStringAsFixed(6)}';

      if (!processados.add(chave)) continue;

      pontos.add(
        PontoEntrega(
          coordenada: '${latLng.latitude},${latLng.longitude}',
          latLng: latLng,
          entrega: entrega,
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

    final entregasAtivas = entregasProvider.entregas
        .where(entregaAtivaParaRota)
        .toList();

    final Set<Marker> novosMarkers = {};

    novosMarkers.add(
      Marker(
        markerId: const MarkerId('entregador'),

        position: posicaoAtual,

        infoWindow: const InfoWindow(title: 'Você está aqui'),

        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
    );

    final Set<String> processados = {};

    for (int i = 0; i < entregasAtivas.length; i++) {
      final entrega = entregasAtivas[i];

      final posicaoEntrega = await obterCoordenadaEntrega(entrega);

      if (posicaoEntrega == null) continue;

      final chave =
          '${posicaoEntrega.latitude.toStringAsFixed(6)},'
          '${posicaoEntrega.longitude.toStringAsFixed(6)}';

      if (!processados.add(chave)) continue;

      final status = entrega.status.toString().trim().toUpperCase();

      final complemento = entrega.complemento.toString().trim();

      novosMarkers.add(
        Marker(
          markerId: MarkerId('entrega_${entrega.id ?? i}'),

          position: posicaoEntrega,

          infoWindow: InfoWindow(
            title: entrega.cliente,

            snippet: complemento.isNotEmpty
                ? '${entrega.endereco} - $complemento'
                : entrega.endereco,
          ),

          icon: BitmapDescriptor.defaultMarkerWithHue(
            status == 'EM_ROTA'
                ? BitmapDescriptor.hueOrange
                : BitmapDescriptor.hueRed,
          ),
        ),
      );
    }

    if (!mounted) return;

    setState(() {
      markers = novosMarkers;
    });
  }

  Future<void> carregarRota({bool ajustarCamera = true}) async {
    if (_calculandoRota) return;
    _calculandoRota = true;
    try {
      final pontos = await buscarPontosPendentes();

      if (pontos.isEmpty) {
        if (!mounted) return;

        setState(() {
          polylines.clear();
          distanciaRotaKm = 0;
          duracaoRotaMinutos = 0;
          proximaEntrega = null;
          coordenadaProximaEntrega = null;
          distanciaProximaEntregaKm = 0;
          duracaoProximaEntregaMinutos = 0;
          instrucaoNavegacao = '';
          passosNavegacao = [];
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
        debugPrint('Rota retornada sem polyline.');
        return;
      }

      final coordenadasRota = decodificarPolyline(polyline.toString());

      final ordemOtimizada = rota['optimizedIntermediateWaypointIndex'];
      final List<PontoEntrega> pontosOrdenados = [];

      if (pontos.length == 1) {
        pontosOrdenados.add(pontos.first);
      } else {
        if (ordemOtimizada is List) {
          for (final indice in ordemOtimizada) {
            if (indice is int && indice >= 0 && indice < pontos.length - 1) {
              pontosOrdenados.add(pontos[indice]);
            }
          }
        }

        final intermediariosAdicionados = pontosOrdenados
            .map((e) => e.coordenada)
            .toSet();

        for (int i = 0; i < pontos.length - 1; i++) {
          if (!intermediariosAdicionados.contains(pontos[i].coordenada)) {
            pontosOrdenados.add(pontos[i]);
          }
        }

        pontosOrdenados.add(pontos.last);
      }

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

      final legs = rota['legs'];
      final primeiraLeg = legs is List && legs.isNotEmpty && legs.first is Map
          ? Map<String, dynamic>.from(legs.first as Map)
          : <String, dynamic>{};
      final distanciaPrimeiraLeg = primeiraLeg['distanceMeters'];
      final duracaoPrimeiraLeg = primeiraLeg['duration']?.toString() ?? '0s';
      final steps = primeiraLeg['steps'];
      final novosPassos = steps is List
          ? steps
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;

      setState(() {
        distanciaProximaEntregaKm = distanciaPrimeiraLeg is num
            ? distanciaPrimeiraLeg.toDouble() / 1000
            : distanceMeters / 1000;
        duracaoProximaEntregaMinutos =
            (converterDuracaoParaSegundos(
                      primeiraLeg.isNotEmpty
                          ? duracaoPrimeiraLeg
                          : rota['duration']?.toString() ?? '0s',
                    ) /
                    60)
                .ceil();
        passosNavegacao = novosPassos;
        if (novosPassos.isEmpty) {
          instrucaoNavegacao = '';
        }
        distanciaRotaKm = distanceMeters / 1000;
        duracaoRotaMinutos = (segundos / 60).ceil();

        if (pontosOrdenados.isNotEmpty) {
          proximaEntrega = pontosOrdenados.first.entrega;
          coordenadaProximaEntrega = pontosOrdenados.first.latLng;
        } else {
          proximaEntrega = null;
          coordenadaProximaEntrega = null;
        }

        polylines = {
          Polyline(
            polylineId: const PolylineId('rota_completa'),
            points: coordenadasRota,
            width: 6,
            color: AppColors.primary,
          ),
        };
      });

      atualizarInstrucaoNavegacao();
      if (ajustarCamera && !rotaIniciada) {
        await ajustarCameraNaRota(coordenadasRota);
      }
    } catch (e) {
      debugPrint('Erro ao carregar rota: $e');
    } finally {
      _calculandoRota = false;
    }
  }

  int converterDuracaoParaSegundos(String duration) {
    try {
      return double.parse(duration.replaceAll('s', '')).round();
    } catch (_) {
      return 0;
    }
  }

  Future<void> ajustarCameraNaRota(List<LatLng> pontos) async {
    if (pontos.isEmpty || mapController == null) return;

    double minLat = pontos.first.latitude;

    double maxLat = pontos.first.latitude;

    double minLng = pontos.first.longitude;

    double maxLng = pontos.first.longitude;

    for (final ponto in pontos) {
      if (ponto.latitude < minLat) minLat = ponto.latitude;

      if (ponto.latitude > maxLat) maxLat = ponto.latitude;

      if (ponto.longitude < minLng) minLng = ponto.longitude;

      if (ponto.longitude > maxLng) maxLng = ponto.longitude;
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

  Future<void> iniciarRota() async {
    final entregasProvider = Provider.of<EntregasProvider>(
      context,

      listen: false,
    );

    setState(() {
      carregandoMapa = true;
    });

    try {
      await entregasProvider.carregarEntregasDoBackend();

      if (!mounted) return;

      final entregasAtivas = entregasProvider.entregas
          .where(entregaAtivaParaRota)
          .toList();

      if (entregasAtivas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhuma entrega pendente para iniciar rota'),
          ),
        );

        return;
      }

      final permitido = await verificarPermissaoLocalizacao();

      if (!permitido) return;

      await buscarLocalizacaoAtual();

      if (!mounted) return;

      final pontos = await buscarPontosPendentes();

      if (pontos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhuma localização válida encontrada'),
          ),
        );

        return;
      }

      await marcarEntregasComoEmRota();

      if (!mounted) return;

      setState(() {
        rotaIniciada = true;
      });

      await carregarMarkers();

      if (!mounted) return;

      await carregarRota(ajustarCamera: false);

      if (!mounted) return;

      _assinaturaEntregas = assinaturaEntregasAtivas();
      await iniciarMonitoramentoLocalizacao();

      if (!mounted) return;

      await mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: posicaoAtual, zoom: 17, tilt: 45),
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rota iniciada com sucesso'),

          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      debugPrint('Erro ao iniciar rota: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível iniciar a rota'),

          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          carregandoMapa = false;
        });
      }
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

      final dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);

      lat += dlat;

      shift = 0;

      result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;

        result |= (b & 0x1f) << shift;

        shift += 5;
      } while (b >= 0x20);

      final dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);

      lng += dlng;

      pontos.add(LatLng(lat / 100000, lng / 100000));
    }

    return pontos;
  }

  Widget cardSuperior() {
    final theme = Theme.of(context);

    final entregasProvider = Provider.of<EntregasProvider>(context);

    final alturaBarraStatus = MediaQuery.paddingOf(context).top;

    final total = entregasProvider.entregas.where(entregaAtivaParaRota).length;

    final pendentes = entregasProvider.entregas
        .where((e) => e.status.toString().trim().toUpperCase() == 'PENDENTE')
        .length;

    final emRota = entregasProvider.entregas
        .where((e) => e.status.toString().trim().toUpperCase() == 'EM_ROTA')
        .length;

    if (rotaIniciada) {
      return Positioned(
        top: alturaBarraStatus + 12,
        left: 70,
        right: 16,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.95),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.16),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (instrucaoNavegacao.isNotEmpty) ...[
                Row(
                  children: [
                    Icon(
                      manobraNavegacao.contains('LEFT')
                          ? Icons.turn_left
                          : manobraNavegacao.contains('RIGHT')
                          ? Icons.turn_right
                          : Icons.navigation,
                      color: AppColors.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        instrucaoNavegacao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      distanciaProximaManobraMetros >= 1000
                          ? '${(distanciaProximaManobraMetros / 1000).toStringAsFixed(1)} km'
                          : '${distanciaProximaManobraMetros.round()} m',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.14),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.navigation,
                      color: AppColors.success,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Próxima entrega',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          proximaEntrega != null
                              ? proximaEntrega.cliente.toString()
                              : 'Calculando...',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        if (proximaEntrega != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            proximaEntrega.endereco.toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 3),
                        Text(
                          '${distanciaProximaEntregaKm.toStringAsFixed(1)} km'
                          ' • $duracaoProximaEntregaMinutos min até a entrega',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Positioned(
      top: alturaBarraStatus + 18,
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
                        '$total ativas • '
                        '$pendentes pendentes • '
                        '$emRota em rota',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: carregandoMapa ? null : atualizarMapa,
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

    final ativas = entregasProvider.entregas.where(entregaAtivaParaRota).length;

    if (rotaIniciada) {
      return Positioned(
        left: 18,

        right: 18,

        bottom: 24,

        child: Container(
          height: 58,

          padding: const EdgeInsets.symmetric(horizontal: 16),

          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.95),

            borderRadius: BorderRadius.circular(20),

            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.16),

                blurRadius: 14,

                offset: const Offset(0, 5),
              ),
            ],
          ),

          child: Row(
            children: [
              const Icon(Icons.navigation, color: AppColors.success),

              const SizedBox(width: 10),

              Expanded(
                child: Text(
                  'Rota em andamento',

                  style: TextStyle(
                    fontWeight: FontWeight.bold,

                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),

              IconButton(
                onPressed: () {
                  mapController?.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(target: posicaoAtual, zoom: 17, tilt: 45),
                    ),
                  );
                },

                icon: const Icon(Icons.my_location),

                color: AppColors.primary,
              ),
            ],
          ),
        ),
      );
    }

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
                ativas == 0
                    ? 'Nenhuma entrega ativa'
                    : '$ativas entrega(s) pronta(s) para rota',

                style: TextStyle(
                  fontWeight: FontWeight.bold,

                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),

            const SizedBox(width: 8),

            ElevatedButton(
              onPressed: ativas == 0 || carregandoMapa ? null : iniciarRota,

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

      bottom: rotaIniciada ? 96 : 118,

      child: FloatingActionButton(
        heroTag: 'centralizar',

        mini: true,

        backgroundColor: theme.cardColor,

        foregroundColor: AppColors.primary,

        onPressed: () {
          mapController?.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: posicaoAtual,

                zoom: rotaIniciada ? 17 : 15,

                tilt: rotaIniciada ? 45 : 0,
              ),
            ),
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
          padding: EdgeInsets.only(left: 16, top: rotaIniciada ? 12 : 120),

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
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,

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

            compassEnabled: true,

            trafficEnabled: true,

            buildingsEnabled: true,

            onMapCreated: (controller) async {
              mapController = controller;

              await aplicarEstiloMapa();

              if (rotaIniciada) {
                await controller.animateCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(target: posicaoAtual, zoom: 17, tilt: 45),
                  ),
                );
              }
            },
          ),

          cardSuperior(),

          cardInferior(),

          botaoCentralizar(),

          botaoVoltar(),
        ],
      ),
    );
  }
}

class PontoEntrega {
  final String coordenada;
  final LatLng latLng;
  final dynamic entrega;

  PontoEntrega({
    required this.coordenada,
    required this.latLng,
    required this.entrega,
  });
}
