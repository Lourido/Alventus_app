import 'dart:js_interop';

/// Dice si el navegador cree que hay conexión de red ahora mismo (ver
/// `appIsOnline` en web/file_saver.js).
///
/// Solo tiene sentido llamarlo cuando la app corre en web (kIsWeb); en
/// Android/iOS nativo se usa el plugin de conectividad de siempre. Si
/// por lo que sea la función de JavaScript no estuviera disponible, se
/// responde "sí hay conexión", que es como se comportaba la app antes
/// de existir esto.
bool browserSaysOnline() {
  try {
    return _appIsOnline();
  } catch (_) {
    return true;
  }
}

@JS('appIsOnline')
external bool _appIsOnline();
