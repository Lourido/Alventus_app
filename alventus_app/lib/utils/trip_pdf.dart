import 'dart:js_interop';

/// Puente con el generador de PDF del viaje, definido en web/trip_pdf.js.
/// Solo existe en la versión web (PWA): quien decide si mostrar el botón
/// de generar PDF es la pantalla (con kIsWeb), no este archivo.
///
/// Si algún día esto no compila: revisar primero que el texto entre
/// comillas de @JS(...) coincide EXACTAMENTE con el nombre de la función
/// que web/trip_pdf.js deja en `window` (window.buildTripPdf).
///
/// Mismo patrón que lib/widgets/speech/local_dictation.dart y
/// lib/utils/web_file_opener.dart, que ya compilan y funcionan: una
/// función @JS() suelta, con tipos simples (textos y una promesa).

@JS('buildTripPdf')
external JSPromise<JSString> _buildTripPdf(JSString json, JSString fileName);

/// Genera el PDF con los datos de [json] (ver el formato en
/// web/trip_pdf.js) y lo descarga en el teléfono con el nombre
/// [fileName].
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
