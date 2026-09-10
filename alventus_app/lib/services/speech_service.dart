import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

/// Envoltorio único (singleton) sobre speech_to_text.
///
/// Se usa un único motor de reconocimiento compartido por toda la app
/// porque el sistema operativo solo permite una sesión de escucha activa
/// a la vez. Cualquier [MicTextField] que empiece a escuchar detendrá
/// automáticamente al que estuviera activo antes.
class SpeechService {
  SpeechService._internal();
  static final SpeechService instance = SpeechService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initialized = false;
  bool _hasPrimedListening = false;
  bool get isListening => _speech.isListening;

  /// Identificador del campo que está escuchando actualmente (o null).
  Object? _activeListenerId;

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onStatus: (_) {},
      onError: (SpeechRecognitionError e) {},
      debugLogging: false,
    );
    return _initialized;
  }

  /// Inicializa el motor de reconocimiento (y pide el permiso de micrófono
  /// si hace falta) sin empezar a escuchar todavía, y además hace un ciclo
  /// real y breve de "escucha de prueba" (solo la primera vez en toda la
  /// sesión de la app).
  ///
  /// Esto es necesario porque solo llamar a `initialize()` de antemano no
  /// basta: hay un fallo conocido del motor nativo de Android donde,
  /// aunque `initialize()` ya haya terminado, la PRIMERA sesión real de
  /// `listen()` a veces se anuncia con el sonido de "empezar a
  /// escuchar", se corta enseguida con el sonido de "fin" y no captura
  /// nada — el motor interno del sistema todavía no estaba listo del
  /// todo. Haciendo aquí, de antemano, un ciclo de escucha muy corto y
  /// descartando su resultado, ese "primer arranque" ya no lo sufre el
  /// usuario en su primera pulsación real del micrófono.
  Future<void> warmUp() async {
    final available = await _ensureInitialized();
    if (!available || _hasPrimedListening || _speech.isListening) return;

    _hasPrimedListening = true;

    try {
      await _speech.listen(
        onResult: (_) {},
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          cancelOnError: true,
          partialResults: false,
        ),
        pauseFor: const Duration(milliseconds: 400),
        listenFor: const Duration(milliseconds: 400),
      );

      await Future.delayed(const Duration(milliseconds: 350));

      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (_) {
      // Si el precalentamiento falla, no pasa nada grave: en el peor
      // caso, el usuario solo tendría que pulsar el micrófono una vez
      // más la primera vez, como pasaba antes de este arreglo.
    }
  }

  /// Empieza a escuchar para el campo identificado por [listenerId].
  ///
  /// [onPartial] recibe el texto reconocido cada vez que cambia (incluye
  /// resultados provisionales y el resultado final).
  /// [onDone] se llama cuando el reconocimiento termina (silencio, error,
  /// tiempo agotado o detención manual).
  Future<bool> startListening({
    required Object listenerId,
    required void Function(String text, bool isFinal) onPartial,
    required void Function() onDone,
    String? localeId,
  }) async {
    final available = await _ensureInitialized();
    if (!available) return false;

    // Si otro campo estaba escuchando, se detiene primero.
    if (_speech.isListening) {
      await _speech.stop();
    }

    _activeListenerId = listenerId;

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        if (_activeListenerId != listenerId) return; // ya no es el activo
        onPartial(result.recognizedWords, result.finalResult);
        if (result.finalResult) {
          _activeListenerId = null;
          onDone();
        }
      },
      localeId: localeId,
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        cancelOnError: true,
        partialResults: true,
        // Solo tiene efecto en iOS 16+; en Android se ignora sin problema.
        autoPunctuation: true,
      ),
      pauseFor: const Duration(seconds: 4),
      listenFor: const Duration(minutes: 2),
    );

    return true;
  }

  Future<void> stopListening(Object listenerId) async {
    if (_activeListenerId == listenerId) {
      _activeListenerId = null;
      await _speech.stop();
    }
  }

  bool isActiveListener(Object listenerId) => _activeListenerId == listenerId;
}
