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
  bool get isListening => _speech.isListening;

  /// Último motivo por el que el motor de voz ha fallado, tal cual lo da
  /// el sistema.
  ///
  /// Antes estos errores se descartaban en silencio (el `onError` estaba
  /// vacío), así que cuando el micrófono no escuchaba no había ninguna
  /// forma de saber por qué. Ahora se guarda aquí para poder enseñárselo
  /// al usuario.
  String? lastError;

  /// Idioma que se acabó usando de verdad (null = el del sistema).
  String? lastLocaleUsed;

  /// Idiomas de dictado que tiene instalados este teléfono.
  List<String> _availableLocaleIds = const [];

  /// Identificador del campo que está escuchando actualmente (o null).
  Object? _activeListenerId;

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;

    try {
      _initialized = await _speech.initialize(
        onStatus: (_) {},
        onError: (SpeechRecognitionError e) {
          lastError = e.errorMsg;
        },
        debugLogging: false,
      );
    } catch (e) {
      lastError = e.toString();
      _initialized = false;
    }

    if (!_initialized) {
      lastError ??= 'el teléfono no tiene dictado por voz disponible';
      return false;
    }

    // Se apunta qué idiomas tiene instalados de verdad este teléfono,
    // para no pedirle luego uno que no tenga (ver _resolveLocaleId).
    try {
      final locales = await _speech.locales();
      _availableLocaleIds = locales.map((l) => l.localeId).toList();
    } catch (_) {
      _availableLocaleIds = const [];
    }

    return _initialized;
  }

  /// Elige un identificador de idioma que este teléfono sí pueda
  /// entender: el que se pide si lo tiene instalado; si no, otro del
  /// mismo idioma (por ejemplo es_MX si no está es_ES); y si no hay
  /// ninguno, null, que significa "usa el idioma del sistema".
  ///
  /// Esto es lo que hacía que en Android el micrófono no llegara a
  /// escuchar nunca: se pedía siempre "es_ES" a ciegas y, en los
  /// teléfonos que no lo tienen instalado con ese nombre exacto, el
  /// motor arrancaba y se cerraba al instante sin reconocer nada y sin
  /// dar ningún error visible. En iPhone no pasaba porque allí el
  /// dictado va por otro camino distinto.
  String? _resolveLocaleId(String? wanted) {
    if (wanted == null || _availableLocaleIds.isEmpty) return wanted;

    if (_availableLocaleIds.contains(wanted)) return wanted;

    final normalized = wanted.replaceAll('-', '_');
    for (final id in _availableLocaleIds) {
      if (id.replaceAll('-', '_') == normalized) return id;
    }

    final language = normalized.split('_').first.toLowerCase();
    for (final id in _availableLocaleIds) {
      if (id.replaceAll('-', '_').toLowerCase().startsWith('${language}_')) {
        return id;
      }
    }

    return null;
  }

  /// Inicializa el motor de reconocimiento (y pide el permiso de micrófono
  /// si hace falta) sin empezar a escuchar todavía.
  ///
  /// Llamar a esto en cuanto se muestra la pantalla (en vez de esperar a
  /// que el usuario pulse el micrófono por primera vez) evita un fallo
  /// conocido del motor nativo: si `initialize()` se llama justo antes de
  /// `listen()`, la primera sesión de escucha a veces no captura nada
  /// porque el motor aún no ha terminado de "calentar" por dentro.
  Future<void> warmUp() => _ensureInitialized();

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
    lastError = null;

    final available = await _ensureInitialized();
    if (!available) return false;

    // Si otro campo estaba escuchando, se detiene primero.
    if (_speech.isListening) {
      await _speech.stop();
    }

    _activeListenerId = listenerId;

    final resolvedLocale = _resolveLocaleId(localeId);
    lastLocaleUsed = resolvedLocale;

    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          if (_activeListenerId != listenerId) return; // ya no es el activo
          onPartial(result.recognizedWords, result.finalResult);
          if (result.finalResult) {
            _activeListenerId = null;
            onDone();
          }
        },
        localeId: resolvedLocale,
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
    } catch (e) {
      lastError = e.toString();
      _activeListenerId = null;
      return false;
    }

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
