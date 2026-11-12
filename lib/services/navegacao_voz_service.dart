import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class NavegacaoVozService {
  final FlutterTts _tts = FlutterTts();

  bool _ativo = true;
  bool _configurado = false;
  String? _ultimaInstrucao;

  bool get ativo => _ativo;

  Future<void> configurar() async {
    if (_configurado) return;

    await _tts.setLanguage('pt-BR');
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(false);

    _configurado = true;
  }

  Future<void> falar(String mensagem) async {
    if (!_ativo || mensagem.trim().isEmpty) return;

    try {
      await configurar();
      await _tts.stop();
      await _tts.speak(mensagem);
    } catch (e) {
      debugPrint('Erro na navegação por voz: $e');
    }
  }

  Future<void> falarInstrucao(String instrucao) async {
    final texto = instrucao.trim();

    if (!_ativo || texto.isEmpty) return;
    if (_ultimaInstrucao == texto) return;

    _ultimaInstrucao = texto;
    await falar(texto);
  }

  Future<void> alertarChegada() async {
    await falar(
      'Você está chegando ao destino. Confira o endereço da entrega.',
    );
  }

  Future<void> alertarRecalculo() async {
    await falar('Recalculando rota.');
  }

  Future<void> alterarSom() async {
    _ativo = !_ativo;

    if (!_ativo) {
      await _tts.stop();
    }
  }

  void limparInstrucao() {
    _ultimaInstrucao = null;
  }

  Future<void> parar() async {
    await _tts.stop();
  }
}
