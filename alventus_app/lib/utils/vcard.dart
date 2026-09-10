import '../models/reference_contact.dart';

/// Construye el contenido de un archivo vCard (.vcf) a partir de uno o
/// varios contactos.
///
/// Es la alternativa, en la versión web, a escribir directamente en la
/// agenda del teléfono con flutter_contacts (que solo funciona en
/// Android/iOS nativo, no en el navegador): en vez de eso, se genera
/// este archivo y se le ofrece al navegador para abrir/descargar (ver
/// web_file_opener.dart). Tanto iOS/Safari como Android/Chrome saben
/// abrir un .vcf y ofrecen añadirlo a la agenda del teléfono -- incluso
/// uno con varios contactos dentro a la vez.
String buildVCard(List<ReferenceContact> contacts) {
  final buffer = StringBuffer();
  for (final contact in contacts) {
    buffer.write('BEGIN:VCARD\r\n');
    buffer.write('VERSION:3.0\r\n');
    buffer.write('FN:${_escape(contact.name)}\r\n');
    buffer.write('N:${_escape(contact.name)};;;;\r\n');
    if (contact.phone != null && contact.phone!.isNotEmpty) {
      buffer.write('TEL;TYPE=CELL:${_escape(contact.phone!)}\r\n');
    }
    if (contact.email != null && contact.email!.isNotEmpty) {
      buffer.write('EMAIL:${_escape(contact.email!)}\r\n');
    }
    if (contact.city != null && contact.city!.isNotEmpty) {
      buffer.write('ADR;TYPE=HOME:;;;${_escape(contact.city!)};;;\r\n');
    }
    if (contact.comment != null && contact.comment!.isNotEmpty) {
      buffer.write('NOTE:${_escape(contact.comment!)}\r\n');
    }
    buffer.write('END:VCARD\r\n');
  }
  return buffer.toString();
}

/// Escapa los caracteres especiales del formato vCard (coma, punto y
/// coma, barra invertida y saltos de línea).
String _escape(String value) {
  return value
      .replaceAll('\\', '\\\\')
      .replaceAll(',', '\\,')
      .replaceAll(';', '\\;')
      .replaceAll('\n', '\\n');
}
