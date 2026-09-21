import 'dart:js_interop';

/// Puente con el generador de PDF del viaje, definido en web/trip_pdf.js.
/// Solo existe en la versión web (PWA): quien decide si mostrar el botón
/// de generar PDF es la pantalla (con kIsWeb), no este archivo.
///
/// Si algún día esto no compila: revisar primero que el texto entre
/// comillas de @JS(...) coincide EXACTAMENTE con el nombre de la función
/// que web/trip_pdf.js deja en `window` (window.buildTripPdf, etc.).
///
/// Mismo patrón que lib/widgets/speech/local_dictation.dart y
/// lib/utils/web_file_opener.dart, que ya compilan y funcionan: funciones
/// @JS() sueltas, con tipos simples (textos y promesas).
///
/// Va en dos pasos: primero se GENERA (buildTripPdfOnWeb, que puede
/// tardar) y luego se GUARDA (saveTripPdfOnWeb / downloadTripPdfOnWeb).
/// Guardar tiene que llamarse directamente desde el onPressed de un botón,
/// sin ningún await antes: elegir carpeta o abrir el menú de compartir
/// solo lo permite el navegador en el mismo instante del toque.

@JS('tripPdfApiVersion')
external JSNumber _tripPdfApiVersion();

/// Versión de web/trip_pdf.js que necesita esta app. Si el navegador
/// tiene cargada una copia más vieja (guardada de antes de desplegar), el
/// PDF saldría mal (p. ej. sin documentos): la pantalla lo comprueba antes
/// con [tripPdfScriptIsUpToDate] y pide cerrar y abrir la app.
const int kTripPdfApiVersion = 2;

/// true si el trip_pdf.js cargado es el que espera esta app. Nunca lanza.
bool tripPdfScriptIsUpToDate() {
  try {
    return _tripPdfApiVersion().toDartInt >= kTripPdfApiVersion;
  } catch (_) {
    return false; // copia vieja: aún no tenía tripPdfApiVersion
  }
}

@JS('buildTripPdf')
external JSPromise<JSString> _buildTripPdf(JSString json, JSString fileName);

@JS('saveTripPdf')
external JSPromise<JSString> _saveTripPdf();

@JS('downloadTripPdf')
external JSString _downloadTripPdf();

@JS('discardTripPdf')
external void _discardTripPdf();

/// Genera el PDF con los datos de [json] (ver el formato en
/// web/trip_pdf.js) y lo deja preparado para guardarlo con el nombre
/// [fileName]. No lo guarda todavía.
///
/// Devuelve 'ok' si ha ido bien, o un texto que empieza por 'error:' con
/// el motivo. Nunca lanza una excepción.
Future<String> buildTripPdfOnWeb(String json, String fileName) async {
  try {
    final result = await _buildTripPdf(json.toJS, fileName.toJS).toDart;
    return result.toDart;
  } catch (e) {
    return 'error: $e';
  }
}

/// Guarda el PDF preparado dejando elegir la carpeta. Devuelve 'saved',
/// 'shared' (menú de compartir; en iPhone, "Guardar en Archivos"),
/// 'downloaded', 'cancelled' o 'error: ...'. Nunca lanza.
///
/// OJO: llamar SIN await previo dentro del onPressed (ver arriba).
Future<String> saveTripPdfOnWeb() async {
  try {
    final result = await _saveTripPdf().toDart;
    return result.toDart;
  } catch (e) {
    return 'error: $e';
  }
}

/// Descarga el PDF preparado a la carpeta de descargas. Devuelve
/// 'downloaded' o 'error: ...'. Nunca lanza.
Future<String> downloadTripPdfOnWeb() async {
  try {
    return _downloadTripPdf().toDart;
  } catch (e) {
    return 'error: $e';
  }
}

/// Olvida el PDF preparado (libera memoria). Nunca lanza.
void discardTripPdfOnWeb() {
  try {
    _discardTripPdf();
  } catch (_) {}
}
