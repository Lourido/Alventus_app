/// Historial de cambios de cara al usuario ("qué hay de nuevo"), para
/// mostrarse en un aviso la primera vez que se abre la app tras un
/// despliegue que incluya alguna entrada nueva.
///
/// Cómo añadir una entrada nueva cuando hagamos un cambio visible para
/// el usuario:
/// 1. Añadir un [ChangelogEntry] al final de [kChangelog], con
///    [version] uno más que el último que haya (es un contador interno
///    de este archivo, no tiene por qué coincidir con la versión de
///    pubspec.yaml).
/// 2. Escribir los cambios en una frase corta y en el lenguaje del
///    usuario (nada de nombres de archivos, pantallas o términos
///    técnicos).
/// 3. Desplegar como siempre: a cada usuario le aparecerá el aviso
///    solo una vez, la próxima vez que abra la app (ver
///    lib/services/changelog_service.dart para el porqué de esto).
class ChangelogEntry {
  final int version;
  final String date; // texto libre, p. ej. "10 de septiembre de 2026"
  final List<String> changes;

  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.changes,
  });
}

const List<ChangelogEntry> kChangelog = [
  ChangelogEntry(
    version: 1,
    date: '10 de septiembre de 2026',
    changes: [
      'El nombre del viaje se mantiene sincronizado con Odoo.',
      'Nueva opción para cerrar sesión desde la pantalla de inicio.',
      'Los textos ya no muestran etiquetas como <p> o <br>.',
      'Aviso cuando el dictado por voz no reconoce nada en Safari/iPhone.',
      'Dentro de una etapa: se puede pasar a la etapa siguiente o anterior sin volver atrás, y la descripción se ve al mismo tamaño que el nombre.',
      'El email de "sugerencias" de la pantalla de inicio se puede tocar para escribir directamente.',
      'Arreglado el aviso de "WhatsApp no instalado" al compartir un viaje.',
    ],
  ),
  ChangelogEntry(
    version: 2,
    date: '10 de septiembre de 2026',
    changes: [
      'Cuando la app tiene novedades, aparece un aviso como este al abrirla.',
      'En iPhone, el micrófono de dictado se ve desactivado con una explicación (es un problema de Safari, no de la app), en vez de no funcionar sin más.',
      'Los contactos de referencia se pueden descargar al teléfono también desde el navegador.',
      'Al intentar importar contactos del iPhone, se explica por qué no es posible en vez de no hacer nada.',
      'En la lista de etapas, el nombre y la descripción de cada una se ven ahora con el mismo tamaño de letra.',
    ],
  ),
  ChangelogEntry(
    version: 3,
    date: '10 de septiembre de 2026',
    changes: [
      'En iPhone, el dictado por voz ya funciona: la primera vez pide descargar un modelo (una sola vez) y a partir de ahí funciona también sin conexión, sin que el audio salga nunca del teléfono.',
    ],
  ),
];
