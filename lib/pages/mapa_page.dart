import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:geolocator/geolocator.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:provider/provider.dart';

import '../providers/entregas_provider.dart';

import '../services/api_service.dart';

import '../services/directions_service.dart';

import '../services/geocoding_service.dart';
import '../services/navegacao_voz_service.dart';

import '../theme/app_colors.dart';

class MapaPage extends StatefulWidget {
  const MapaPage({super.key});

  @override
  State<MapaPage> createState() => _MapaPageState();
}

class _MapaPageState extends State<MapaPage> with WidgetsBindingObserver {
  GoogleMapController? mapController;
  bool _acompanharLocalizacao = true;
  bool _cameraAutomaticaEmAndamento = false;
  BitmapDescriptor? _iconeMoto;
  double _direcaoMoto = 0;
  bool _direcaoDefinida = false;
  LatLng? _ultimaPosicaoDirecao;
  static const double _velocidadeMinimaDirecao = 1.5;
  final NavegacaoVozService _navegacaoVoz = NavegacaoVozService();

  StreamSubscription<Position>? _positionSubscription;
  static const Duration _intervaloEnvioLocalizacao = Duration(seconds: 12);
  DateTime? _ultimoEnvioLocalizacao;
  bool _enviandoLocalizacao = false;

  LatLng posicaoAtual = const LatLng(-23.5505, -46.6333);

  Set<Marker> markers = {};

  Set<Polyline> polylines = {};
  List<LatLng> _pontosRotaCompleta = [];

  bool carregandoMapa = true;

  bool rotaIniciada = false;

  double distanciaRotaKm = 0;

  int duracaoRotaMinutos = 0;

  DateTime? _ultimaAtualizacaoRota;
  DateTime? _ultimaAtualizacaoCamera;
  static const Duration _intervaloMinimoCamera = Duration(milliseconds: 800);
  double _distanciaInicialRotaMetros = 0;
  int _duracaoInicialRotaSegundos = 0;
  double _distanciaInicialPrimeiraEntregaMetros = 0;
  int _duracaoInicialPrimeiraEntregaSegundos = 0;
  double _progressoMaximoRotaMetros = 0;

  static const double _raioChegadaMetros = 50;
  static const int _leiturasParaConfirmarChegada = 2;
  int _leiturasPertoDestino = 0;
  String? _destinoMonitorado;
  String? _destinoAvisado;

  int _leiturasForaDaRota = 0;
  static const double _limiteDesvioMetros = 50;
  static const int _leiturasParaConfirmarDesvio = 2;
  static const Duration _intervaloMinimoRecalculo = Duration(seconds: 30);

  dynamic proximaEntrega;
  LatLng? coordenadaProximaEntrega;
  double distanciaProximaEntregaKm = 0;
  int duracaoProximaEntregaMinutos = 0;
  String instrucaoNavegacao = '';
  String manobraNavegacao = '';
  double distanciaProximaManobraMetros = 0;
  List<Map<String, dynamic>> passosNavegacao = [];
  String? _ultimaManobraAnunciada;
  int _ultimoAvisoDistancia = -1;
  Timer? _timerSincronizacao;
  bool _sincronizandoEntregas = false;
  bool _sincronizacaoPendente = false;
  bool _calculandoRota = false;
  bool _abrindoFinalizacao = false;
  String _assinaturaEntregas = '';
  String? _destinoOtimizado;
  String? _chavePontosOtimizados;
  final Set<String> _idsEntregasDaRota = {};
  final Map<String, LatLng?> _coordenadasPorEndereco = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    Future.microtask(() async {
      await _criarIconeMoto();
      await carregarMapaCompleto();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerSincronizacao?.cancel();
    _positionSubscription?.cancel();
    _sincronizacaoPendente = false;

    mapController?.dispose();
    unawaited(_navegacaoVoz.parar());

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && rotaIniciada) {
      unawaited(_atualizarPosicaoAoRetornar());
    }
  }

  Future<void> _atualizarPosicaoAoRetornar() async {
    try {
      final gps = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 12));
      if (!mounted ||
          !rotaIniciada ||
          !gps.latitude.isFinite ||
          !gps.longitude.isFinite) {
        return;
      }
      final posicao = LatLng(gps.latitude, gps.longitude);
      if (gps.accuracy.isFinite && gps.accuracy <= 35) {
        unawaited(_enviarLocalizacaoDasEntregas(posicao, forcar: true));
      }
      _atualizarDirecao(gps, posicao);
      setState(() {
        posicaoAtual = posicao;
        markers = Set<Marker>.from(markers)
          ..removeWhere((m) => m.markerId.value == 'entregador')
          ..add(_marcadorEntregador(posicao));
      });
      if (gps.accuracy.isFinite && gps.accuracy <= 35 && !_calculandoRota) {
        atualizarDistanciasRestantes(posicao);
      }
      if (_acompanharLocalizacao) {
        unawaited(_acompanharCamera(posicao, _direcaoMoto));
      }
    } catch (e) {
      debugPrint('Não foi possível atualizar a localização ao retornar: $e');
    }
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

  Future<void> _criarIconeMoto() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 48.0;
    canvas.scale(size / 128);
    final sombra = Paint()..color = const Color(0x44000000);
    canvas.drawCircle(const Offset(64, 68), 52, sombra);
    canvas.drawCircle(
      const Offset(64, 64),
      49,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      const Offset(64, 64),
      43,
      Paint()..color = const Color(0xFF1769AA),
    );
    final roda = Paint()..color = const Color(0xFF172333);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(54, 25, 20, 25),
        const Radius.circular(9),
      ),
      roda,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(54, 79, 20, 24),
        const Radius.circular(9),
      ),
      roda,
    );
    final corpo = Path()
      ..moveTo(64, 28)
      ..lineTo(79, 56)
      ..lineTo(76, 83)
      ..quadraticBezierTo(64, 93, 52, 83)
      ..lineTo(49, 56)
      ..close();
    canvas.drawPath(corpo, Paint()..color = const Color(0xFFEAF5FF));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(55, 52, 18, 27),
        const Radius.circular(8),
      ),
      Paint()..color = const Color(0xFF183A57),
    );
    canvas.drawLine(
      const Offset(44, 48),
      const Offset(84, 48),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (!mounted || bytes == null) return;
    setState(() {
      _iconeMoto = BitmapDescriptor.bytes(bytes.buffer.asUint8List());
    });
  }

  double _normalizarDirecao(double valor) => (valor % 360 + 360) % 360;

  void _atualizarDirecao(Position gps, LatLng novaPosicao) {
    if (!gps.accuracy.isFinite || gps.accuracy > 35) return;
    double? novaDirecao;
    if (gps.speed.isFinite &&
        gps.speed >= _velocidadeMinimaDirecao &&
        gps.heading.isFinite &&
        gps.heading >= 0 &&
        gps.heading < 360) {
      novaDirecao = gps.heading;
    } else if (gps.speed.isFinite &&
        gps.speed >= _velocidadeMinimaDirecao &&
        _ultimaPosicaoDirecao != null) {
      final anterior = _ultimaPosicaoDirecao!;
      final distancia = Geolocator.distanceBetween(
        anterior.latitude,
        anterior.longitude,
        novaPosicao.latitude,
        novaPosicao.longitude,
      );
      if (distancia >= 8) {
        novaDirecao = Geolocator.bearingBetween(
          anterior.latitude,
          anterior.longitude,
          novaPosicao.latitude,
          novaPosicao.longitude,
        );
      }
    }
    _ultimaPosicaoDirecao = novaPosicao;
    if (novaDirecao == null) return;
    final destino = _normalizarDirecao(novaDirecao);
    if (!_direcaoDefinida) {
      _direcaoMoto = destino;
      _direcaoDefinida = true;
      return;
    }
    final diferenca = (destino - _direcaoMoto + 540) % 360 - 180;
    if (diferenca.abs() < 4) return;
    _direcaoMoto = _normalizarDirecao(_direcaoMoto + diferenca * 0.4);
  }

  Marker _marcadorEntregador(LatLng posicao) => Marker(
    markerId: const MarkerId('entregador'),
    position: posicao,
    infoWindow: const InfoWindow(title: 'Você está aqui'),
    icon:
        _iconeMoto ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    flat: _iconeMoto != null,
    anchor: const Offset(0.5, 0.5),
    rotation: _direcaoMoto,
    zIndexInt: 100,
  );

  void _recentralizarMapa() {
    setState(() => _acompanharLocalizacao = true);
    _ultimaAtualizacaoCamera = null;
    unawaited(_acompanharCamera(posicaoAtual, _direcaoMoto));
  }

  Future<void> carregarMapaCompleto() async {
    if (mounted) {
      setState(() {
        carregandoMapa = true;

        markers.clear();

        polylines.clear();
        _pontosRotaCompleta = [];

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

      _coordenadasPorEndereco.clear();
      rotaIniciada = entregasProvider.entregas.any(
        (e) => e.status.toString().trim().toUpperCase() == 'EM_ROTA',
      );
      if (rotaIniciada) {
        if (_idsEntregasDaRota.isEmpty) {
          _registrarEntregasDaRota(entregasProvider);
        }
      } else {
        _idsEntregasDaRota.clear();
      }

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

      final novaPosicao = LatLng(position.latitude, position.longitude);

      setState(() {
        posicaoAtual = novaPosicao;
      });

      if (!rotaIniciada || _acompanharLocalizacao) {
        await mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(novaPosicao, 15),
        );
      }
    } catch (e) {
      debugPrint('Erro ao buscar localização: $e');
    }
  }

  Future<void> iniciarMonitoramentoLocalizacao() async {
    final permitido = await verificarPermissaoLocalizacao();

    if (!permitido || !mounted || !rotaIniciada) return;

    await _positionSubscription?.cancel();
    if (!mounted || !rotaIniciada) return;
    _ultimaAtualizacaoCamera = null;
    _ultimoEnvioLocalizacao = null;
    _leiturasForaDaRota = 0;
    _ultimaAtualizacaoRota = null;
    _ultimaManobraAnunciada = null;
    _ultimoAvisoDistancia = -1;
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
          (Position position) {
            if (!mounted || !rotaIniciada) return;

            if (!position.latitude.isFinite ||
                !position.longitude.isFinite ||
                position.latitude < -90 ||
                position.latitude > 90 ||
                position.longitude < -180 ||
                position.longitude > 180) {
              return;
            }

            final novaPosicao = LatLng(position.latitude, position.longitude);
            if (position.accuracy.isFinite && position.accuracy <= 35) {
              unawaited(_enviarLocalizacaoDasEntregas(novaPosicao));
            }
            _atualizarDirecao(position, novaPosicao);

            setState(() {
              posicaoAtual = novaPosicao;

              final novosMarkers = Set<Marker>.from(markers);

              novosMarkers.removeWhere(
                (marker) => marker.markerId.value == 'entregador',
              );

              novosMarkers.add(_marcadorEntregador(novaPosicao));

              markers = novosMarkers;
            });
            atualizarInstrucaoNavegacao();
            if (position.accuracy <= 35 && !_calculandoRota) {
              atualizarDistanciasRestantes(novaPosicao);
            }

            verificarChegadaAoDestino(position, novaPosicao);

            final agoraCamera = DateTime.now();
            if (_ultimaAtualizacaoCamera == null ||
                agoraCamera.difference(_ultimaAtualizacaoCamera!) >=
                    _intervaloMinimoCamera) {
              _ultimaAtualizacaoCamera = agoraCamera;
              unawaited(_acompanharCamera(novaPosicao, _direcaoMoto));
            }

            if (!position.accuracy.isFinite ||
                position.accuracy > 35 ||
                polylines.isEmpty) {
              _leiturasForaDaRota = 0;
              return;
            }

            final distanciaDaRota = distanciaDaRotaEmMetros(novaPosicao);

            if (distanciaDaRota <= _limiteDesvioMetros) {
              _leiturasForaDaRota = 0;
              return;
            }

            _leiturasForaDaRota++;

            if (_leiturasForaDaRota < _leiturasParaConfirmarDesvio ||
                _calculandoRota) {
              return;
            }

            final agora = DateTime.now();

            if (_ultimaAtualizacaoRota != null &&
                agora.difference(_ultimaAtualizacaoRota!) <
                    _intervaloMinimoRecalculo) {
              return;
            }

            _ultimaAtualizacaoRota = agora;
            _leiturasForaDaRota = 0;
            unawaited(_navegacaoVoz.alertarRecalculo());
            debugPrint(
              'Desvio confirmado: ${distanciaDaRota.toStringAsFixed(0)} m da rota. Recalculando...',
            );
            unawaited(
              carregarRota(ajustarCamera: false, compararDestinos: false),
            );
          },

          onError: (erro) {
            debugPrint('Erro no GPS em tempo real: $erro');
          },
        );
  }

  Future<void> _enviarLocalizacaoDasEntregas(
    LatLng posicao, {
    bool forcar = false,
  }) async {
    if (!mounted || !rotaIniciada || _enviandoLocalizacao) return;
    final agora = DateTime.now();
    if (!forcar &&
        _ultimoEnvioLocalizacao != null &&
        agora.difference(_ultimoEnvioLocalizacao!) <
            _intervaloEnvioLocalizacao) {
      return;
    }

    final provider = Provider.of<EntregasProvider>(context, listen: false);
    final ids = provider.entregas
        .where(
          (entrega) =>
              entrega.id != null &&
              entrega.status.toString().trim().toUpperCase() == 'EM_ROTA',
        )
        .map((entrega) => entrega.id as int)
        .toSet();
    if (ids.isEmpty) return;

    _enviandoLocalizacao = true;
    _ultimoEnvioLocalizacao = agora;
    try {
      for (final id in ids) {
        if (!mounted || !rotaIniciada) break;
        await ApiService.enviarLocalizacaoEntregador(
          id: id,
          latitude: posicao.latitude,
          longitude: posicao.longitude,
        );
      }
    } finally {
      _enviandoLocalizacao = false;
    }
  }

  Future<void> _acompanharCamera(LatLng posicao, double heading) async {
    final controller = mapController;
    if (!mounted ||
        !rotaIniciada ||
        controller == null ||
        !_acompanharLocalizacao) {
      return;
    }

    if (_cameraAutomaticaEmAndamento) return;
    try {
      _cameraAutomaticaEmAndamento = true;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: posicao,
            zoom: 17,
            bearing: _direcaoDefinida ? heading : 0,
            tilt: 45,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Não foi possível atualizar a câmera do mapa: $e');
    } finally {
      _cameraAutomaticaEmAndamento = false;
    }
  }

  void _registrarEntregasDaRota(EntregasProvider provider) {
    _idsEntregasDaRota
      ..clear()
      ..addAll(
        provider.entregas
            .where(entregaAtivaParaRota)
            .where((e) => e.id != null)
            .map((e) => e.id.toString()),
      );
  }

  String assinaturaEntregasAtivas() {
    final provider = Provider.of<EntregasProvider>(context, listen: false);
    final ids =
        provider.entregas
            .where(entregaAtivaParaRota)
            .map(
              (e) =>
                  '${e.id}:${e.status}:${e.endereco}:${e.latitude}:${e.longitude}',
            )
            .toList()
          ..sort();
    return ids.join('|');
  }

  Future<void> sincronizarEntregasEmRota({bool forcar = false}) async {
    if (!mounted || !rotaIniciada) return;
    if (_sincronizandoEntregas) {
      if (forcar) _sincronizacaoPendente = true;
      return;
    }
    _sincronizandoEntregas = true;
    try {
      final provider = Provider.of<EntregasProvider>(context, listen: false);
      await provider.carregarEntregasDoBackend();
      if (!mounted) return;
      final assinaturaAtual = assinaturaEntregasAtivas();
      if (assinaturaAtual == _assinaturaEntregas) return;
      _assinaturaEntregas = assinaturaAtual;
      _coordenadasPorEndereco.clear();
      _destinoOtimizado = null;
      _chavePontosOtimizados = null;
      _leiturasForaDaRota = 0;
      _leiturasPertoDestino = 0;
      _destinoMonitorado = null;
      if (assinaturaAtual.isEmpty) {
        _timerSincronizacao?.cancel();
        await _positionSubscription?.cancel();
        _ultimaAtualizacaoCamera = null;
        if (!mounted) return;
        setState(() {
          rotaIniciada = false;
          _destinoAvisado = null;
          _progressoMaximoRotaMetros = 0;
          _distanciaInicialRotaMetros = 0;
          _duracaoInicialRotaSegundos = 0;
          _distanciaInicialPrimeiraEntregaMetros = 0;
          _duracaoInicialPrimeiraEntregaSegundos = 0;
          distanciaRotaKm = 0;
          duracaoRotaMinutos = 0;
          proximaEntrega = null;
          coordenadaProximaEntrega = null;
          distanciaProximaEntregaKm = 0;
          duracaoProximaEntregaMinutos = 0;
          instrucaoNavegacao = '';
          passosNavegacao = [];
          polylines.clear();
          _pontosRotaCompleta = [];
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
      if (_calculandoRota) {
        _assinaturaEntregas = '';
      } else {
        await carregarRota(ajustarCamera: false);
      }
    } catch (e) {
      debugPrint('Erro ao sincronizar entregas: $e');
    } finally {
      _sincronizandoEntregas = false;
      if (_sincronizacaoPendente) {
        _sincronizacaoPendente = false;
        if (mounted && rotaIniciada) {
          unawaited(sincronizarEntregasEmRota());
        }
      }
    }
  }

  Future<void> _finalizarEntregaSelecionada(dynamic entrega) async {
    if (!mounted || _abrindoFinalizacao) return;
    final int? id = entrega.id;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrega sem ID para finalização.')),
      );
      return;
    }
    setState(() => _abrindoFinalizacao = true);
    try {
      final resultado = await context.push<bool>(
        '/entregador/entregas/finalizar',
        extra: {
          'entregaId': id,
          'cliente': entrega.cliente.toString(),
          'endereco': entrega.endereco.toString(),
        },
      );
      if (!mounted) return;
      if (resultado == true) {
        if (rotaIniciada) {
          await sincronizarEntregasEmRota(forcar: true);
        } else {
          await carregarMapaCompleto();
        }
      }
    } catch (e) {
      debugPrint('Erro ao abrir finalização pelo mapa: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir a finalização.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _abrindoFinalizacao = false);
    }
  }

  Future<void> finalizarProximaEntregaPeloMapa() async {
    if (proximaEntrega == null) return;
    final pontos = await buscarPontosPendentes();
    if (!mounted) return;
    for (final ponto in pontos) {
      if (ponto.entregas.any((e) => e.id == proximaEntrega.id)) {
        await _mostrarEntregasDaParada(ponto.entregas);
        return;
      }
    }
    await _finalizarEntregaSelecionada(proximaEntrega);
  }

  Future<void> _mostrarEntregasDaParada(List<dynamic> entregas) async {
    if (!mounted || entregas.isEmpty) return;
    final endereco = entregas.first.endereco.toString();
    final selecionada = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Entregas nesta parada (${entregas.length})',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(endereco),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: entregas.length,
                  itemBuilder: (context, index) {
                    final entrega = entregas[index];
                    final complemento =
                        entrega.complemento?.toString().trim() ?? '';
                    return ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(entrega.cliente.toString()),
                      subtitle: Text(
                        'Entrega #${entrega.id ?? '-'}'
                        '${complemento.isNotEmpty ? ' • $complemento' : ''}'
                        ' • ${entrega.status}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(sheetContext, entrega),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selecionada == null) return;
    await _finalizarEntregaSelecionada(selecionada);
  }

  String _chaveEndereco(dynamic entrega) {
    var endereco = entrega.endereco.toString().trim().toLowerCase();
    const origem = 'áàâãäéèêëíìîïóòôõöúùûüç';
    const destino = 'aaaaaeeeeiiiiooooouuuuc';
    for (var i = 0; i < origem.length; i++) {
      endereco = endereco.replaceAll(origem[i], destino[i]);
    }
    return endereco
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
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

  void anunciarInstrucaoNavegacao() {
    if (!mounted || !rotaIniciada || instrucaoNavegacao.trim().isEmpty) return;

    final distancia = distanciaProximaManobraMetros;
    if (!distancia.isFinite || distancia < 0 || distancia > 500) return;

    final identificador = '$manobraNavegacao|$instrucaoNavegacao';
    if (_ultimaManobraAnunciada != identificador) {
      _ultimaManobraAnunciada = identificador;
      _ultimoAvisoDistancia = -1;
    }

    final int aviso;
    if (distancia <= 50) {
      aviso = 0;
    } else if (distancia <= 100) {
      aviso = 100;
    } else if (distancia <= 200) {
      aviso = 200;
    } else {
      aviso = 500;
    }

    if (_ultimoAvisoDistancia != -1 && aviso >= _ultimoAvisoDistancia) return;
    _ultimoAvisoDistancia = aviso;

    final instrucao = instrucaoNavegacao
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (instrucao.isEmpty) return;

    final mensagem = aviso == 0 ? instrucao : 'Em $aviso metros, $instrucao';
    unawaited(_navegacaoVoz.falar(mensagem));
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
        (distancia - distanciaProximaManobraMetros).abs() < 10) {
      anunciarInstrucaoNavegacao();
      return;
    }
    setState(() {
      instrucaoNavegacao = instrucao;
      manobraNavegacao = manobra;
      distanciaProximaManobraMetros = distancia;
    });
    anunciarInstrucaoNavegacao();
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
    final endereco = entrega.endereco.toString().trim();
    if (endereco.isEmpty) {
      if (!possuiCoordenadas(entrega)) return null;
      return LatLng(
        (entrega.latitude as num).toDouble(),
        (entrega.longitude as num).toDouble(),
      );
    }

    final chave = _chaveEndereco(entrega);
    if (_coordenadasPorEndereco.containsKey(chave)) {
      return _coordenadasPorEndereco[chave];
    }

    try {
      final coordenadas = await GeocodingService.buscarCoordenadas(endereco);
      final latitude = coordenadas?['lat'];
      final longitude = coordenadas?['lng'];
      if (latitude != null &&
          longitude != null &&
          latitude.isFinite &&
          longitude.isFinite &&
          latitude >= -90 &&
          latitude <= 90 &&
          longitude >= -180 &&
          longitude <= 180 &&
          !(latitude == 0 && longitude == 0)) {
        final ponto = LatLng(latitude, longitude);
        _coordenadasPorEndereco[chave] = ponto;
        return ponto;
      }
    } catch (e) {
      debugPrint('Erro ao localizar endereço atualizado $endereco: $e');
    }

    debugPrint(
      'Endereço não localizado; coordenadas antigas ignoradas: $endereco',
    );
    return null;
  }

  Future<List<PontoEntrega>> buscarPontosPendentes() async {
    final provider = Provider.of<EntregasProvider>(context, listen: false);
    final pontosPorEndereco = <String, PontoEntrega>{};
    for (final entrega in provider.entregas.where(entregaAtivaParaRota)) {
      final chave = _chaveEndereco(entrega);
      if (chave.isEmpty) continue;
      final existente = pontosPorEndereco[chave];
      if (existente != null) {
        existente.entregas.add(entrega);
        continue;
      }
      final coordenada = await obterCoordenadaEntrega(entrega);
      if (coordenada == null) continue;
      pontosPorEndereco[chave] = PontoEntrega(
        coordenada: '${coordenada.latitude},${coordenada.longitude}',
        latLng: coordenada,
        entrega: entrega,
        entregas: [entrega],
      );
    }
    return pontosPorEndereco.values.toList();
  }

  Future<void> carregarMarkers() async {
    final pontos = await buscarPontosPendentes();
    final novosMarkers = <Marker>{_marcadorEntregador(posicaoAtual)};
    for (var i = 0; i < pontos.length; i++) {
      final ponto = pontos[i];
      final entregas = ponto.entregas;
      final emRota = entregas.any(
        (e) => e.status.toString().trim().toUpperCase() == 'EM_ROTA',
      );
      novosMarkers.add(
        Marker(
          markerId: MarkerId('parada_${i}_${ponto.entrega.id ?? i}'),
          position: ponto.latLng,
          infoWindow: InfoWindow(
            title: entregas.length == 1
                ? ponto.entrega.cliente.toString()
                : '${entregas.length} entregas nesta parada',
            snippet: ponto.entrega.endereco.toString(),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            emRota ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueRed,
          ),
        ),
      );
    }
    if (!mounted) return;
    setState(() => markers = novosMarkers);
  }

  Future<void> carregarRota({
    bool ajustarCamera = true,
    bool compararDestinos = true,
  }) async {
    if (_calculandoRota) return;
    _calculandoRota = true;
    try {
      final pontos = await buscarPontosPendentes();

      if (!mounted) return;

      if (pontos.isEmpty) {
        if (!mounted) return;

        setState(() {
          polylines.clear();
          _pontosRotaCompleta = [];
          _progressoMaximoRotaMetros = 0;
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
      final chavePontos = (pontos.map((p) => p.coordenada).toList()..sort())
          .join('|');

      final candidatos = List<PontoEntrega>.from(pontos)
        ..sort((a, b) {
          final distanciaA = Geolocator.distanceBetween(
            posicaoAtual.latitude,
            posicaoAtual.longitude,
            a.latLng.latitude,
            a.latLng.longitude,
          );
          final distanciaB = Geolocator.distanceBetween(
            posicaoAtual.latitude,
            posicaoAtual.longitude,
            b.latLng.latitude,
            b.latLng.longitude,
          );
          return distanciaB.compareTo(distanciaA);
        });

      final reutilizarDestino =
          !compararDestinos &&
          _chavePontosOtimizados == chavePontos &&
          _destinoOtimizado != null &&
          pontos.any((p) => p.coordenada == _destinoOtimizado);

      final finais = reutilizarDestino
          ? candidatos.where((p) => p.coordenada == _destinoOtimizado).toList()
          : candidatos.take(min(3, candidatos.length)).toList();

      Map<String, dynamic>? rota;
      List<PontoEntrega> pontosOrdenados = [];
      PontoEntrega? melhorFinal;
      int? menorDuracao;
      double? menorDistancia;

      for (final finalCandidato in finais) {
        final intermediarios = pontos
            .where((p) => p.coordenada != finalCandidato.coordenada)
            .toList();
        final resultado = await DirectionsService.buscarRota(
          origem,
          finalCandidato.coordenada,
          intermediarios.map((p) => p.coordenada).toList(),
        );
        if (!mounted) return;
        if (resultado == null) continue;

        final ordem = resultado['optimizedIntermediateWaypointIndex'];
        final ordenados = <PontoEntrega>[];
        if (intermediarios.isNotEmpty) {
          if (ordem is! List || ordem.length != intermediarios.length) {
            debugPrint('Ordem otimizada ausente ou incompleta.');
            continue;
          }
          final indices = <int>{};
          var valida = true;
          for (final indice in ordem) {
            if (indice is! int ||
                indice < 0 ||
                indice >= intermediarios.length ||
                !indices.add(indice)) {
              valida = false;
              break;
            }
            ordenados.add(intermediarios[indice]);
          }
          if (!valida) continue;
        }
        ordenados.add(finalCandidato);

        final duracao = converterDuracaoParaSegundos(
          resultado['duration']?.toString() ?? '',
        );
        final distancia = (resultado['distanceMeters'] as num?)?.toDouble();
        if (duracao <= 0 || distancia == null || distancia < 0) continue;
        if (menorDuracao == null ||
            duracao < menorDuracao ||
            (duracao == menorDuracao &&
                (menorDistancia == null || distancia < menorDistancia))) {
          menorDuracao = duracao;
          menorDistancia = distancia;
          melhorFinal = finalCandidato;
          rota = resultado;
          pontosOrdenados = ordenados;
        }
      }

      final rotaConfirmada = rota;
      if (rotaConfirmada == null || melhorFinal == null) {
        debugPrint('Nenhuma sequência otimizada válida foi retornada.');
        return;
      }
      _destinoOtimizado = melhorFinal.coordenada;
      _chavePontosOtimizados = chavePontos;
      debugPrint(
        'Rota otimizada: ${pontosOrdenados.map((p) => p.entrega.id).join(' -> ')}',
      );

      final polyline = rotaConfirmada['overview_polyline']?['points'];

      if (polyline == null || polyline.toString().isEmpty) {
        debugPrint('Rota retornada sem polyline.');
        return;
      }

      final encoded = polyline.toString();

      debugPrint(
        'Primeiros caracteres: ${encoded.substring(0, min(15, encoded.length))}',
      );

      debugPrint(
        'Códigos dos caracteres: ${encoded.codeUnits.take(15).toList()}',
      );

      debugPrint(
        'Início da polyline: ${polyline.toString().substring(0, polyline.toString().length > 50 ? 50 : polyline.toString().length)}',
      );

      final coordenadasRota = decodificarPolyline(encoded);

      debugPrint('Quantidade de pontos da rota: ${coordenadasRota.length}');

      if (coordenadasRota.isNotEmpty) {
        debugPrint('Primeiro ponto da rota: ${coordenadasRota.first}');
        debugPrint('Último ponto da rota: ${coordenadasRota.last}');
      }

      debugPrint('Posição atual: $posicaoAtual');

      double distanceMeters = 0;
      int segundos = 0;

      if (rotaConfirmada['distanceMeters'] != null) {
        distanceMeters = (rotaConfirmada['distanceMeters'] as num).toDouble();

        final duration = rotaConfirmada['duration']?.toString() ?? '0s';
        segundos = converterDuracaoParaSegundos(duration);
      } else if (rotaConfirmada['legs'] is List) {
        final legs = rotaConfirmada['legs'] as List;

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

      final legs = rotaConfirmada['legs'];
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
                          : rotaConfirmada['duration']?.toString() ?? '0s',
                    ) /
                    60)
                .ceil();
        passosNavegacao = novosPassos;
        if (novosPassos.isEmpty) {
          instrucaoNavegacao = '';
        }
        _distanciaInicialRotaMetros = distanceMeters;
        _duracaoInicialRotaSegundos = segundos;
        _distanciaInicialPrimeiraEntregaMetros = distanciaPrimeiraLeg is num
            ? distanciaPrimeiraLeg.toDouble()
            : distanceMeters;
        _duracaoInicialPrimeiraEntregaSegundos = converterDuracaoParaSegundos(
          primeiraLeg.isNotEmpty
              ? duracaoPrimeiraLeg
              : rotaConfirmada['duration']?.toString() ?? '0s',
        );
        _progressoMaximoRotaMetros = 0;
        _pontosRotaCompleta = List<LatLng>.from(coordenadasRota);
        _ultimaManobraAnunciada = null;
        _ultimoAvisoDistancia = -1;
        _navegacaoVoz.limparInstrucao();
        distanciaRotaKm = distanceMeters / 1000;
        duracaoRotaMinutos = (segundos / 60).ceil();

        if (pontosOrdenados.isNotEmpty) {
          proximaEntrega = pontosOrdenados.first.entrega;
          coordenadaProximaEntrega = pontosOrdenados.first.latLng;
        } else {
          proximaEntrega = null;
          coordenadaProximaEntrega = null;
        }

        _leiturasForaDaRota = 0;
        polylines = {
          Polyline(
            polylineId: const PolylineId('rota_completa'),
            points: coordenadasRota,
            width: 6,
            color: AppColors.primary,
          ),
        };
      });

      if (rotaIniciada) atualizarDistanciasRestantes(posicaoAtual);
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

  void verificarChegadaAoDestino(Position gps, LatLng posicao) {
    if (!mounted ||
        !rotaIniciada ||
        coordenadaProximaEntrega == null ||
        proximaEntrega == null) {
      _leiturasPertoDestino = 0;
      _destinoMonitorado = null;
      return;
    }

    final destino = coordenadaProximaEntrega!;
    final chaveDestino =
        '${proximaEntrega.id}:${destino.latitude},${destino.longitude}';
    if (_destinoMonitorado != chaveDestino) {
      _destinoMonitorado = chaveDestino;
      _leiturasPertoDestino = 0;
    }
    if (_destinoAvisado == chaveDestino) return;

    if (!gps.accuracy.isFinite || gps.accuracy > 35) {
      _leiturasPertoDestino = 0;
      return;
    }

    final distancia = Geolocator.distanceBetween(
      posicao.latitude,
      posicao.longitude,
      destino.latitude,
      destino.longitude,
    );
    if (distancia > _raioChegadaMetros) {
      _leiturasPertoDestino = 0;
      return;
    }

    _leiturasPertoDestino++;
    if (_leiturasPertoDestino < _leiturasParaConfirmarChegada) return;

    _destinoAvisado = chaveDestino;
    _leiturasPertoDestino = 0;
    unawaited(_navegacaoVoz.alertarChegada());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Voce chegou perto da proxima entrega! Confira o endereco antes de finalizar.',
        ),
        duration: Duration(seconds: 6),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void atualizarDistanciasRestantes(LatLng posicao) {
    if (!mounted || !rotaIniciada || _pontosRotaCompleta.isEmpty) return;
    final pontos = _pontosRotaCompleta;
    if (pontos.length < 2 || _distanciaInicialRotaMetros <= 0) return;

    final progresso = _progressoNaPolyline(posicao, pontos);
    if (progresso == null || progresso.distanciaAteLinha > 50) return;

    _progressoMaximoRotaMetros = max(
      _progressoMaximoRotaMetros,
      progresso.percorrido,
    );
    final proporcaoRestante = (1 - _progressoMaximoRotaMetros / progresso.total)
        .clamp(0.0, 1.0);

    double proporcaoPrimeiraEntrega = proporcaoRestante;
    if (coordenadaProximaEntrega != null) {
      final pontoEntrega = _progressoNaPolyline(
        coordenadaProximaEntrega!,
        pontos,
      );
      if (pontoEntrega != null && pontoEntrega.percorrido > 1) {
        proporcaoPrimeiraEntrega =
            (1 - _progressoMaximoRotaMetros / pontoEntrega.percorrido).clamp(
              0.0,
              1.0,
            );
      }
    }

    setState(() {
      polylines = {
        Polyline(
          polylineId: const PolylineId('rota_completa'),
          points: _pontosRestantesNaRota(pontos, _progressoMaximoRotaMetros),
          width: 6,
          color: AppColors.primary,
        ),
      };
      distanciaRotaKm = _distanciaInicialRotaMetros * proporcaoRestante / 1000;
      duracaoRotaMinutos =
          (_duracaoInicialRotaSegundos * proporcaoRestante / 60).ceil();
      distanciaProximaEntregaKm =
          _distanciaInicialPrimeiraEntregaMetros *
          proporcaoPrimeiraEntrega /
          1000;
      duracaoProximaEntregaMinutos =
          (_duracaoInicialPrimeiraEntregaSegundos *
                  proporcaoPrimeiraEntrega /
                  60)
              .ceil();
    });
  }

  List<LatLng> _pontosRestantesNaRota(
    List<LatLng> pontos,
    double metrosPercorridos,
  ) {
    if (pontos.length < 2 || metrosPercorridos <= 0) return pontos;
    var acumulado = 0.0;
    for (var i = 0; i < pontos.length - 1; i++) {
      final inicio = pontos[i];
      final fim = pontos[i + 1];
      final comprimento = Geolocator.distanceBetween(
        inicio.latitude,
        inicio.longitude,
        fim.latitude,
        fim.longitude,
      );
      if (comprimento <= 0) continue;
      if (acumulado + comprimento >= metrosPercorridos) {
        final t = ((metrosPercorridos - acumulado) / comprimento).clamp(
          0.0,
          1.0,
        );
        final pontoAtual = LatLng(
          inicio.latitude + (fim.latitude - inicio.latitude) * t,
          inicio.longitude + (fim.longitude - inicio.longitude) * t,
        );
        return [pontoAtual, ...pontos.skip(i + 1)];
      }
      acumulado += comprimento;
    }
    return [pontos.last];
  }

  _ProgressoPolyline? _progressoNaPolyline(
    LatLng posicao,
    List<LatLng> pontos,
  ) {
    if (pontos.length < 2) return null;
    const raioTerra = 6371000.0;
    const rad = pi / 180;
    final fatorX = cos(posicao.latitude * rad) * raioTerra * rad;
    const fatorY = raioTerra * rad;
    final px = posicao.longitude * fatorX;
    final py = posicao.latitude * fatorY;
    var acumulado = 0.0;
    var menorDistancia = double.infinity;
    var melhorProgresso = 0.0;

    for (var i = 0; i < pontos.length - 1; i++) {
      final ax = pontos[i].longitude * fatorX;
      final ay = pontos[i].latitude * fatorY;
      final bx = pontos[i + 1].longitude * fatorX;
      final by = pontos[i + 1].latitude * fatorY;
      final dx = bx - ax;
      final dy = by - ay;
      final comprimentoQuadrado = dx * dx + dy * dy;
      final comprimento = sqrt(comprimentoQuadrado);
      if (comprimento == 0) continue;
      final t = (((px - ax) * dx + (py - ay) * dy) / comprimentoQuadrado).clamp(
        0.0,
        1.0,
      );
      final distancia = sqrt(
        pow(px - (ax + t * dx), 2) + pow(py - (ay + t * dy), 2),
      );
      if (distancia < menorDistancia) {
        menorDistancia = distancia;
        melhorProgresso = acumulado + t * comprimento;
      }
      acumulado += comprimento;
    }
    if (acumulado <= 0) return null;
    return _ProgressoPolyline(
      percorrido: melhorProgresso,
      total: acumulado,
      distanciaAteLinha: menorDistancia,
    );
  }

  double distanciaDaRotaEmMetros(LatLng posicao) {
    if (_pontosRotaCompleta.isEmpty) return double.infinity;

    final pontos = _pontosRotaCompleta;
    if (pontos.isEmpty) return double.infinity;

    if (pontos.length == 1) {
      return Geolocator.distanceBetween(
        posicao.latitude,
        posicao.longitude,
        pontos.first.latitude,
        pontos.first.longitude,
      );
    }

    double menorDistancia = double.infinity;

    for (int i = 0; i < pontos.length - 1; i++) {
      final distancia = distanciaPontoSegmento(
        posicao,
        pontos[i],
        pontos[i + 1],
      );

      if (distancia < menorDistancia) {
        menorDistancia = distancia;
      }
    }

    return menorDistancia;
  }

  double distanciaPontoSegmento(LatLng ponto, LatLng inicio, LatLng fim) {
    const raioTerra = 6371000.0;
    const grausParaRadianos = pi / 180;
    final fatorLongitude = cos(ponto.latitude * grausParaRadianos);

    double converterX(double longitude) =>
        longitude * grausParaRadianos * raioTerra * fatorLongitude;

    double converterY(double latitude) =>
        latitude * grausParaRadianos * raioTerra;

    final px = converterX(ponto.longitude);
    final py = converterY(ponto.latitude);
    final ax = converterX(inicio.longitude);
    final ay = converterY(inicio.latitude);
    final bx = converterX(fim.longitude);
    final by = converterY(fim.latitude);

    final dx = bx - ax;
    final dy = by - ay;
    final comprimentoQuadrado = dx * dx + dy * dy;

    if (comprimentoQuadrado == 0) {
      return sqrt(pow(px - ax, 2) + pow(py - ay, 2));
    }

    final proporcao = (((px - ax) * dx + (py - ay) * dy) / comprimentoQuadrado)
        .clamp(0.0, 1.0);

    final cx = ax + proporcao * dx;
    final cy = ay + proporcao * dy;

    return sqrt(pow(px - cx, 2) + pow(py - cy, 2));
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

      if (!mounted) return;

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

      _registrarEntregasDaRota(entregasProvider);
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
          CameraPosition(
            target: posicaoAtual,
            zoom: 17,
            tilt: 45,
            bearing: _direcaoMoto,
          ),
        ),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rota iniciada com sucesso'),

          backgroundColor: AppColors.success,
        ),
      );
      unawaited(_navegacaoVoz.falar('Rota iniciada. Boa viagem!'));
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

    int lerValor() {
      int resultado = 0;
      int multiplicador = 1;
      int valor;

      do {
        if (index >= encoded.length) {
          throw const FormatException('Polyline incompleta');
        }

        valor = encoded.codeUnitAt(index++) - 63;

        resultado += (valor % 32) * multiplicador;
        multiplicador *= 32;
      } while (valor >= 32);

      if (resultado.isOdd) {
        return -((resultado + 1) ~/ 2);
      }

      return resultado ~/ 2;
    }

    while (index < encoded.length) {
      lat += lerValor();
      lng += lerValor();

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

    final entregasDaSessao = entregasProvider.entregas
        .where(
          (e) => e.id != null && _idsEntregasDaRota.contains(e.id.toString()),
        )
        .toList();
    final totalDaSessao = _idsEntregasDaRota.length;
    final concluidas = entregasDaSessao
        .where((e) => e.status.toString().trim().toUpperCase() == 'ENTREGUE')
        .length;
    final restantes = entregasDaSessao.where(entregaAtivaParaRota).length;
    final progresso = totalDaSessao == 0
        ? 0.0
        : (concluidas / totalDaSessao).clamp(0.0, 1.0);

    if (rotaIniciada) {
      return Positioned(
        top: alturaBarraStatus + 12,
        left: 70,
        right: 16,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.cardColor.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
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
                      color: AppColors.success.withValues(alpha: 0.14),
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
              if (totalDaSessao > 0) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$concluidas concluída(s) • $restantes restante(s)',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      '${(progresso * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progresso,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.outlineVariant,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.success,
                    ),
                  ),
                ),
              ],
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
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.30 : 0.12,
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
                  backgroundColor: AppColors.primary.withValues(alpha: 0.14),
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
            color: theme.cardColor.withValues(alpha: 0.95),

            borderRadius: BorderRadius.circular(20),

            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),

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

              TextButton.icon(
                onPressed: proximaEntrega == null || _abrindoFinalizacao
                    ? null
                    : finalizarProximaEntregaPeloMapa,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Finalizar'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
              ),

              IconButton(
                onPressed: () {
                  _recentralizarMapa();
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
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),

          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.32 : 0.14,
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

              backgroundColor: AppColors.success.withValues(alpha: 0.14),

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
          _recentralizarMapa();
        },

        child: Icon(
          _acompanharLocalizacao ? Icons.my_location : Icons.location_searching,
        ),
      ),
    );
  }

  Widget botaoSom() {
    if (!rotaIniciada) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Positioned(
      right: 18,
      bottom: 154,
      child: FloatingActionButton(
        heroTag: 'som_navegacao',
        mini: true,
        backgroundColor: theme.cardColor,
        foregroundColor: AppColors.primary,
        onPressed: () async {
          await _navegacaoVoz.alterarSom();
          if (!mounted) return;
          setState(() {});
          if (_navegacaoVoz.ativo) {
            unawaited(_navegacaoVoz.falar('Navegação por voz ativada.'));
          }
        },
        child: Icon(_navegacaoVoz.ativo ? Icons.volume_up : Icons.volume_off),
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
              context.pop();
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

            onCameraMoveStarted: () {
              if (rotaIniciada &&
                  !_cameraAutomaticaEmAndamento &&
                  _acompanharLocalizacao) {
                setState(() => _acompanharLocalizacao = false);
              }
            },

            markers: markers,

            polylines: polylines,

            myLocationEnabled: false,

            myLocationButtonEnabled: false,

            zoomControlsEnabled: false,

            compassEnabled: true,

            trafficEnabled: true,

            buildingsEnabled: true,

            onMapCreated: (controller) async {
              mapController = controller;

              if (!mounted) return;

              await controller.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(
                    target: posicaoAtual,
                    zoom: rotaIniciada ? 17 : 15,
                    tilt: rotaIniciada ? 45 : 0,
                  ),
                ),
              );
              if (polylines.isNotEmpty && !rotaIniciada) {
                final pontosRota = polylines.first.points;

                if (pontosRota.isNotEmpty) {
                  await ajustarCameraNaRota(pontosRota);
                }
              }
            },
          ),

          cardSuperior(),

          cardInferior(),

          botaoCentralizar(),

          botaoSom(),

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
  final List<dynamic> entregas;

  PontoEntrega({
    required this.coordenada,
    required this.latLng,
    required this.entrega,
    required this.entregas,
  });
}

class _ProgressoPolyline {
  final double percorrido;
  final double total;
  final double distanciaAteLinha;

  const _ProgressoPolyline({
    required this.percorrido,
    required this.total,
    required this.distanciaAteLinha,
  });
}
