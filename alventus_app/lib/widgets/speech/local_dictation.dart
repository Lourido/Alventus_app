import 'dart:js_interop';

/// Puente con el dictado por voz local (WebAssembly) definido en
/// web/dictation.js. Solo tiene sentido en Flutter Web -- quien decide
/// CUÁNDO usar esto en vez del dictado normal es MicTextField, no este
/// archivo.
///
/// Si algún día esto no compila: revisar primero que el nombre de cada
/// función aquí (el texto entre comillas de @JS(...)) coincide EXACTAMENTE
/// con el nombre de la función expuesta en `window` desde dictation.js.

@JS('dictationIsSupported')
external bool _dictationIsSupported();

@JS('dictationIsLoaded')
external bool _dictationIsLoaded();

@JS('dictationRequestMicPermission')
external JSPromise<JSBoolean> _dictationRequestMicPermission();

@JS('dictationLoad')
external JSPromise<JSBoolean> _dictationLoad();

@JS('dictationStart')
external JSPromise<JSBoolean> _dictationStart();

@JS('dictationStop')
external JSPromise<JSString> _dictationStop();

@JS('dictationCancel')
external void _dictationCancel();

/// Envoltorio en Dart, con manejo de errores, de las funciones de arriba.
class LocalDictation {
  /// true si el navegador tiene lo necesario (getUserMedia +
  /// MediaRecorder) para intentar el dictado local. No garantiza que
  /// vaya a funcionar bien, solo que merece la pena intentarlo.
  static bool get isSupported {
    try {
      return _dictationIsSupported();
    } catch (_) {
      return false;
    }
  }

  static bool get isModelLoaded {
    try {
      return _dictationIsLoaded();
    } catch (_) {
      return false;
    }
  }

  /// Pide permiso de micrófono sin grabar nada todavía (solo abre y
  /// cierra el micrófono al momento). Se llama antes de descargar el
  /// modelo -- ver el comentario en dictationRequestMicPermission de
  /// web/dictation.js para el porqué.
  static Future<bool> requestMicPermission() async {
    try {
      final result = await _dictationRequestMicPermission().toDart;
      return result.toDart;
    } catch (_) {
      return false;
    }
  }

  /// Descarga y prepara el modelo de dictado (puede tardar bastante la
  /// primera vez, ~150 MB). Llamarlo varias veces seguidas es seguro:
  /// no vuelve a descargar si ya está cargado o cargándose.
  static Future<bool> loadModel() async {
    try {
      final result = await _dictationLoad().toDart;
      return result.toDart;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> start() async {
    try {
      final result = await _dictationStart().toDart;
      return result.toDart;
    } catch (_) {
      return false;
    }
  }

  /// Para la grabación y devuelve el texto transcrito ('' si no se
  /// reconoció nada o algo falló).
  static Future<String> stop() async {
    try {
      final result = await _dictationStop().toDart;
      return result.toDart;
    } catch (_) {
      return '';
    }
  }

  /// Corta el micrófono sin intentar transcribir nada (p. ej. si el
  /// usuario cancela a medio grabar).
  static void cancel() {
    try {
      _dictationCancel();
    } catch (_) {
      // Nada que hacer si ni siquiera esto funciona.
    }
  }
}
