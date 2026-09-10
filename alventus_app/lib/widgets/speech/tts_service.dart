import 'package:flutter_tts/flutter_tts.dart';

/// Envoltorio único (singleton) sobre flutter_tts.
///
/// Al igual que [SpeechService] para el dictado, se usa un único motor de
/// texto-a-voz compartido: si un campo empieza a leerse en voz alta mientras
/// otro estaba sonando, el anterior se detiene automáticamente.
class TtsService {
  TtsService._internal();
  static final TtsService instance = TtsService._internal();

  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;
  Object? _activeSpeakerId;

  bool get isSpeaking => _activeSpeakerId != null;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    // 0.5 es una velocidad de lectura pausada y clara; ajustable si hace
    // falta más adelante.
    await _tts.setSpeechRate(0.5);
    _initialized = true;
  }

  /// Lee [text] en voz alta para el campo identificado por [speakerId].
  ///
  /// Antes de leer, se eliminan etiquetas HTML/XML (p.ej. `<p>`, `</p>`,
  /// `<br>`) y se decodifican entidades comunes (`&nbsp;`, `&amp;`...), por
  /// si el campo guarda contenido en formato "rich text" de Odoo.
  ///
  /// [onDone] se llama cuando termina de leer (de forma natural o porque se
  /// detuvo manualmente / se interrumpió por otra lectura).
  Future<bool> speak({
    required Object speakerId,
    required String text,
    required void Function() onDone,
    String? localeId,
  }) async {
    final cleanText = _stripMarkup(text);
    if (cleanText.trim().isEmpty) return false;

    await _ensureInitialized();

    if (localeId != null && localeId.isNotEmpty) {
      // flutter_tts espera 'es-ES', no 'es_ES'.
      await _tts.setLanguage(localeId.replaceAll('_', '-'));
    }

    // Si otro campo estaba leyéndose, se detiene primero.
    if (_activeSpeakerId != null) {
      await _tts.stop();
    }
    _activeSpeakerId = speakerId;

    _tts.setCompletionHandler(() {
      if (_activeSpeakerId == speakerId) {
        _activeSpeakerId = null;
        onDone();
      }
    });
    _tts.setCancelHandler(() {
      if (_activeSpeakerId == speakerId) {
        _activeSpeakerId = null;
        onDone();
      }
    });
    _tts.setErrorHandler((dynamic message) {
      if (_activeSpeakerId == speakerId) {
        _activeSpeakerId = null;
        onDone();
      }
    });

    await _tts.speak(cleanText);
    return true;
  }

  /// Quita etiquetas HTML/XML (`<p>`, `</p>`, `<br/>`...) y decodifica
  /// entidades comunes, para que el lector no las pronuncie literalmente.
  static String _stripMarkup(String text) {
    var result = text.replaceAll(RegExp(r'<[^>]*>'), ' ');

    result = result
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");

    // Colapsa espacios/tabulaciones múltiples que hayan quedado tras
    // quitar las etiquetas.
    result = result.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();

    return result;
  }

  Future<void> stop(Object speakerId) async {
    if (_activeSpeakerId == speakerId) {
      _activeSpeakerId = null;
      await _tts.stop();
    }
  }

  bool isActiveSpeaker(Object speakerId) => _activeSpeakerId == speakerId;
}
