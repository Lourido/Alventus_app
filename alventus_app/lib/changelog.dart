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
  ChangelogEntry(
    version: 10,
    date: '13 de septiembre de 2026 (final)',
    changes: [
      'Arreglada la pantalla en blanco al abrir la app en Android.',
      'Y arreglado de raíz lo de guardar sin cobertura: en el iPhone, con la app instalada en la pantalla de inicio, el navegador dice que SÍ hay conexión aunque estés en modo avión, y por eso la app lo intentaba contra el servidor y daba error en rojo. Ahora ya no se fía de eso: si al guardar no consigue llegar al servidor, guarda el cambio en el teléfono y lo sube solo cuando vuelve la cobertura.',
    ],
  ),
  ChangelogEntry(
    version: 11,
    date: '13 de septiembre de 2026 (cierre)',
    changes: [
      'Los cambios hechos sin cobertura ya no se pierden al recuperarla. Antes, si la app intentaba subirlos mientras seguía sin cobertura de verdad, daba el intento por fallido y los descartaba; al volver la cobertura ya no quedaba nada que subir y lo que bajaba del servidor pisaba tu cambio.',
      'Ahora un cambio solo se descarta si el servidor lo rechaza de verdad: si no se llega a él, se queda en la cola esperando. Y lo que baja del servidor nunca pisa un cambio tuyo que siga pendiente de subir.',
    ],
  ),
  ChangelogEntry(
    version: 12,
    date: '14 de septiembre de 2026',
    changes: [
      'El icono de cobertura ya dice la verdad: antes se fiaba de lo que decía el teléfono, que en el iPhone asegura que hay conexión aunque estés en modo avión. Ahora se basa en si se ha conseguido hablar con el servidor de verdad.',
      'Al crear un viaje sin cobertura, el aviso sale al elegir cómo crearlo, no después de rellenar todo el formulario, y es el mensaje de siempre en vez de un error de conexión.',
      'En la pantalla de etapas, arriba pone ahora "Etapas - nombre del viaje".',
      'La app tarda menos en darse por vencida cuando no hay servidor, así que se queda menos rato parecida a colgada.',
    ],
  ),
  ChangelogEntry(
    version: 13,
    date: '16 de septiembre de 2026',
    changes: [
      'Arreglada la pantalla en blanco al volver a la app sin cobertura. El motor con el que la app dibuja se descargaba de un servidor de Google cada vez que arrancaba, y sin cobertura no había manera de conseguirlo. Ahora se usa la copia que ya viene dentro de la propia app y se guarda en el teléfono.',
      'Con la app abierta no se notaba, porque ese motor ya estaba cargado; solo salía cuando el iPhone la descargaba de memoria al dejarla en segundo plano y al volver tenía que arrancarla de nuevo.',
    ],
  ),
  ChangelogEntry(
    version: 14,
    date: '21 de septiembre de 2026',
    changes: [
      'Nuevo botón "Generar PDF" en "Ver etapas y tareas del viaje", con dos opciones: solo etapas y tareas, o también los documentos del viaje. Cada etapa y cada documento empiezan en una página nueva, y los documentos PDF se incluyen con su contenido completo. "Etapas y tareas" funciona también sin cobertura.',
      'Al subir fotos de grupo, la app avisa de las que ya están en el viaje o de las que has elegido dos veces, aunque tengan otro nombre: se comparan por su contenido, no por el nombre del archivo.',
      'Dentro de una etapa, puedes pasar a la anterior o a la siguiente deslizando el dedo a derecha o izquierda.',
      'Si hoy es un día de viaje, al abrir la app se va directamente a la etapa de hoy con sus tareas.',
    ],
  ),
  ChangelogEntry(
    version: 15,
    date: '21 de septiembre de 2026',
    changes: [
      'Al generar un PDF puedes elegir en qué carpeta guardarlo con "Guardar en…". En el iPhone, elige "Guardar en Archivos" y luego la carpeta.',
      'En el PDF con documentos, los documentos generales del viaje salen antes de las etapas, y los de cada etapa al final de su etapa, cada uno en una página nueva. Al principio hay un índice con la página de cada cosa.',
      'Los archivos de ruta (GPX, KML...) ya no se incluyen en el PDF.',
      'Corregido: en un día de viaje, la app abría el viaje pero no entraba en la etapa de ese día. Ahora la etapa se busca por su propia fecha, y funciona también sin cobertura.',
    ],
  ),
  ChangelogEntry(
    version: 16,
    date: '22 de septiembre de 2026',
    changes: [
      'Avisos en el teléfono: si una tarea tiene hora de inicio, te llega un aviso a esa hora, aunque la app esté cerrada. Actívalos en la campana de la pantalla de inicio (en el iPhone, con la app añadida a la pantalla de inicio).',
      'Dentro de cada tarea puedes poner su hora de inicio y elegir cuándo avisar: a la hora, 15 o 30 minutos antes, o 1 hora antes.',
      'En la lista de tareas de una etapa se ve la hora de inicio de las tareas que la tienen.',
    ],
  ),
];
