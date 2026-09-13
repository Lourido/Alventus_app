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
  ChangelogEntry(
    version: 4,
    date: '12 de septiembre de 2026',
    changes: [
      'En iPhone ya se pueden ver y descargar bien los archivos (fotos, PDFs, etc.).',
      'Nuevo botón para borrar una tarea suelta dentro de una etapa.',
      'El email de "sugerencias" de la pantalla de inicio se ve ahora más destacado.',
      'Arreglado el orden de las etapas cuando se reordenan directamente en Odoo.',
      'Al mover una etapa arriba o abajo, su descripción se mueve ahora junto con las tareas.',
    ],
  ),
  ChangelogEntry(
    version: 5,
    date: '13 de septiembre de 2026',
    changes: [
      'El aviso de "Novedades" ya no se cierra solo: hay que pulsar "Entendido" para cerrarlo.',
      'En Android, el icono de la app ya es el de Alventus (antes salía el icono genérico).',
      'Si te quedas sin cobertura mientras tienes la app abierta, puedes seguir usándola con los datos guardados en el teléfono.',
      'El aviso de "sin conexión" ahora deja claro que no hay conexión, en vez de decir que sí la hay.',
    ],
  ),
  ChangelogEntry(
    version: 6,
    date: '13 de septiembre de 2026 (tarde)',
    changes: [
      'En modo avión ya se pueden mover las etapas y editar su descripción: el cambio se guarda en el teléfono y se manda a Odoo solo cuando vuelve la cobertura.',
      'La app ya se da cuenta de verdad de cuándo te quedas sin cobertura (antes, en el móvil, daba por hecho que siempre había conexión).',
      'Cada etapa se ve ahora en tres líneas: nombre con su día, descripción, y debajo los botones de bajar, borrar y subir.',
      'Las etapas y sus descripciones se guardan en el teléfono, así que sin conexión se siguen viendo completas.',
      'Este aviso de "Novedades" ya solo se da por leído cuando pulsas "Entendido".',
    ],
  ),
  ChangelogEntry(
    version: 7,
    date: '13 de septiembre de 2026 (noche)',
    changes: [
      'Sin cobertura ya no sale ningún aviso rojo de error al guardar: el cambio se guarda en el teléfono y se avisa en naranja de que se subirá al servidor cuando vuelva la conexión.',
      'Ahora también se pueden hacer sin cobertura estas dos cosas, que antes se bloqueaban: cambiar la hora de una tarea y reordenar las tareas de una etapa.',
    ],
  ),
  ChangelogEntry(
    version: 8,
    date: '13 de septiembre de 2026 (última)',
    changes: [
      'Arreglado el dictado por voz en Android: se pedía siempre el español de España aunque el teléfono no lo tuviera instalado con ese nombre exacto, y entonces el micrófono se activaba y se cerraba sin escuchar nada. Ahora se usa el idioma que el teléfono sí tenga, y si algo falla se explica el motivo.',
      'Sin cobertura, la app ya se entera de verdad en todas las pantallas, no solo en algunas: por eso antes seguía intentando hablar con el servidor y fallaba casi todo.',
      'Lo que de verdad necesita cobertura (borrar o añadir una etapa, compartir o duplicar un viaje, adjuntar archivos) lo dice ahora con un mensaje claro en vez de dar un error.',
    ],
  ),
  ChangelogEntry(
    version: 9,
    date: '13 de septiembre de 2026 (noche, 2)',
    changes: [
      'Ahora la app guarda en el teléfono a qué etapa pertenece cada tarea. Sin ese dato, al quedarse sin cobertura las etapas perdían su identidad y no se podía editar ni mover nada; era la razón de fondo de que sin cobertura no funcionara casi nada.',
      'Las etapas del viaje (con su descripción y su orden) se guardan ya al entrar en el viaje, no solo al abrir la pantalla de etapas, así que sirven aunque nunca hayas entrado en ella con cobertura.',
      'Al pulsar el micrófono, la app avisa de que hay que volver a pulsarlo para que deje de escuchar.',
      'Si el dictado no reconoce nada, se explica que en Android necesita cobertura salvo que descargues el idioma para usarlo sin conexión.',
    ],
  ),
];
