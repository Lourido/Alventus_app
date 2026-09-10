/// Convierte HTML sencillo (el que guarda el editor de texto enriquecido
/// de Odoo en campos como la descripción de una tarea: `<p>`, `<br>`,
/// `<strong>`, `<ul>`/`<li>`...) a texto plano legible, para que esas
/// etiquetas nunca se vean tal cual en los campos de texto de la app.
///
/// A diferencia de un "strip" a lo bruto, conserva los saltos de línea
/// entre párrafos/elementos de lista (en vez de aplastarlos todos en un
/// único espacio), para que el texto siga siendo legible.
///
/// Se aplica en el punto donde los datos entran a la app (al guardar en
/// la base de datos local lo que se trae de Odoo, y al construir los
/// modelos Task/Project directamente desde una respuesta de Odoo), así
/// que no hace falta acordarse de llamarlo en cada pantalla que muestra
/// una descripción: una vez limpio ahí, se queda limpio en todas partes
/// (incluidos los registros que ya llevaban etiquetas guardadas de antes,
/// en cuanto les toque volver a sincronizar).
///
/// Devuelve `null` si [raw] es `null`, vacío, o queda vacío tras limpiar
/// las etiquetas (para no guardar/mostrar una cadena vacía como si fuera
/// un valor real).
String? stripHtmlToPlainText(String? raw) {
  if (raw == null) return null;

  var text = raw;

  // Ya es texto plano (sin etiquetas): nada que hacer, evita procesar de
  // más el caso normal (la mayoría de campos NO llevan HTML).
  if (!text.contains('<')) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  // Saltos de línea explícitos.
  text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

  // Fin de párrafo / elemento de lista / división / titular: salto de
  // línea doble, para que se note la separación entre bloques.
  text = text.replaceAll(
    RegExp(r'</(p|div|li|h[1-6])\s*>', caseSensitive: false),
    '\n\n',
  );

  // El resto de etiquetas (<p>, <strong>, <em>, <ul>, <span style="...">,
  // etc.) se quitan sin más: no aportan nada útil en texto plano.
  text = text.replaceAll(RegExp(r'<[^>]*>'), '');

  // Entidades HTML más comunes.
  text = text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");

  // Colapsa espacios repetidos, recorta cada línea, y deja como máximo
  // una línea en blanco seguida entre párrafos.
  text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  text = text.split('\n').map((line) => line.trim()).join('\n');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  final result = text.trim();
  return result.isEmpty ? null : result;
}
