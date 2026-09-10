import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

/// Descarga en Flutter Web unos bytes ya obtenidos, usando un Blob real
/// y un enlace `<a download>` (ver web/file_saver.js).
///
/// Sustituye al mecanismo anterior, basado en una URL de datos (`data:`)
/// abierta con `url_launcher`, que en iPhone/Safari fallaba en dos casos
/// frecuentes: archivos grandes (Safari limita el tamaño de las URLs de
/// datos abiertas en pestaña nueva) y cuando pasaba algo de tiempo entre
/// el toque del usuario y la apertura -- por ejemplo, mientras se
/// descargaba el archivo de Odoo -- caso en el que Safari bloqueaba la
/// apertura en silencio, como si fuera un pop-up no solicitado. El Blob
/// + `<a download>` no tiene ninguno de los dos problemas.
///
/// Devuelve true si el navegador aceptó la descarga.
Future<bool> openBytesOnWeb(Uint8List bytes, String fileName) async {
  final mimeType = _guessMimeType(fileName);
  final base64Data = base64Encode(bytes);
  try {
    return _saveBytesAsFile(base64Data.toJS, mimeType.toJS, fileName.toJS);
  } catch (_) {
    return false;
  }
}

@JS('saveBytesAsFile')
external bool _saveBytesAsFile(JSString base64Data, JSString mimeType, JSString fileName);

String _guessMimeType(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  final ext = dotIndex == -1 ? '' : fileName.substring(dotIndex + 1).toLowerCase();
  switch (ext) {
    case 'pdf':
      return 'application/pdf';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'ppt':
      return 'application/vnd.ms-powerpoint';
    case 'pptx':
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    case 'txt':
      return 'text/plain';
    case 'csv':
      return 'text/csv';
    case 'zip':
      return 'application/zip';
    case 'vcf':
      return 'text/vcard';
    case 'gpx':
      return 'application/gpx+xml';
    case 'kml':
      return 'application/vnd.google-earth.kml+xml';
    case 'kmz':
      return 'application/vnd.google-earth.kmz';
    case 'mp4':
      return 'video/mp4';
    default:
      return 'application/octet-stream';
  }
}
