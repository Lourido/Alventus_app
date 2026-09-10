import 'dart:convert';
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';

/// Abre en una pestaña nueva del navegador unos bytes ya descargados.
///
/// Es la alternativa, solo para Flutter Web, al flujo nativo de
/// "guardar en un archivo temporal + open_filex" que se usa en
/// Android/iOS: en el navegador no existe el concepto de "abrir con la
/// app del sistema", así que en su lugar se construye una URL de datos
/// (data:) con el contenido en base64 y se le pide al navegador que la
/// abra; según el tipo de archivo, el navegador la mostrará (PDF,
/// imágenes...) o la descargará (Word, Excel, zip...).
///
/// Devuelve true si el navegador aceptó abrir la URL.
Future<bool> openBytesOnWeb(Uint8List bytes, String fileName) async {
  final mimeType = _guessMimeType(fileName);
  final base64Data = base64Encode(bytes);
  final uri = Uri.parse('data:$mimeType;base64,$base64Data');
  return launchUrl(uri, mode: LaunchMode.platformDefault);
}

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
