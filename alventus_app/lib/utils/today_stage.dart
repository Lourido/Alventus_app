import '../services/local_database_service.dart';

/// Busca, en un viaje, la etapa que corresponde al día de hoy. Devuelve
/// su nombre exacto (el que usa StageTasksScreen), o null si ninguna es de
/// hoy.
///
/// Se usa en dos sitios que tienen que decidir lo mismo: al arrancar la
/// app (para abrir el viaje de hoy, ver splash_screen.dart) y al abrir un
/// viaje (para saltar a la etapa de hoy, ver project_overview_screen.dart).
///
/// Por qué así: antes se calculaba contando días desde la fecha de inicio
/// del viaje en Odoo ("hoy es el día 3, busca 'Día 3'"). Pero esa fecha de
/// inicio no siempre cuadra exactamente con las fechas de las etapas (al
/// duplicar un viaje, al cambiarle las fechas en Odoo...), y entonces se
/// iba a otra etapa, o a ninguna. Ahora manda la FECHA DE LA PROPIA ETAPA,
/// que es la que ve el usuario. Por orden:
///
///  1. La fecha que lleva el nombre de la etapa ("Día 3 - 21/09/2026").
///  2. Si ninguna la lleva, la fecha de alguna de sus tareas.
///  3. Y solo como último recurso (etapas sin fecha en el nombre), contando
///     días desde el inicio del viaje, si no ha terminado (y nunca para ir
///     al "Día 0", que es el de antes de salir).
///
/// Trabaja con lo guardado en el teléfono, así que funciona sin
/// cobertura. Si se le pasan [stageNames] (por ejemplo, recién traídos de
/// Odoo), usa esos en vez de los guardados.
Future<String?> findTodayStageName({
  required int projectId,
  String? tripStartIso,
  String? tripEndIso,
  List<String>? stageNames,
  DateTime? now,
}) async {
  final localDb = LocalDatabaseService();
  final today = _utcDay(now ?? DateTime.now());

  final tasks = await localDb.getTasks(projectId);

  var names = stageNames ?? const <String>[];
  if (names.isEmpty) {
    final cached = await localDb.getStages(projectId);
    names = cached
        .map((s) => s['name']?.toString().trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
  }
  if (names.isEmpty) {
    // Ni siquiera hay etapas guardadas: se sacan de las propias tareas.
    names = tasks
        .map((t) => (t['stage_name'] as String?)?.trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
  }
  if (names.isEmpty) return null;

  // 1. La fecha del nombre de la etapa.
  for (final name in names) {
    final date = _dateInName(name);
    if (date != null && date == today) return name;
  }

  // 2. La fecha de alguna de sus tareas.
  for (final name in names) {
    for (final task in tasks) {
      if ((task['stage_name'] as String?)?.trim() != name.trim()) continue;
      final date = _utcDayFrom(task['fecha_desde']);
      if (date != null && date == today) return name;
    }
  }

  // 3. Contando días desde el inicio del viaje. Solo si las etapas NO
  // llevan fecha en el nombre (si la llevan, ya se ha visto arriba que
  // ninguna es de hoy) y si el viaje no ha terminado ya.
  final namesHaveDates = names.any((n) => _dateInName(n) != null);
  final start = _utcDayFrom(tripStartIso);
  final end = _utcDayFrom(tripEndIso);
  final finished = end != null && today.isAfter(end);
  if (start != null && !namesHaveDates && !finished) {
    final dayNumber = today.difference(start).inDays + 1;
    if (dayNumber >= 1) {
      final pattern = RegExp('^Día\\s*$dayNumber(\\D|\$)');
      for (final name in names) {
        if (pattern.hasMatch(name.trim())) return name;
      }
    }
  }

  return null;
}

/// El día (sin hora) en UTC. Se trabaja en UTC a propósito para las
/// cuentas de días: en hora local, el día del cambio de hora solo tiene
/// 23 horas y una resta de fechas se quedaría un día corta.
DateTime _utcDay(DateTime d) => DateTime.utc(d.year, d.month, d.day);

DateTime? _utcDayFrom(dynamic value) {
  if (value == null || value == false) return null;
  final s = value.toString().trim();
  if (s.isEmpty || s.toLowerCase() == 'false') return null;
  try {
    return _utcDay(DateTime.parse(s));
  } catch (_) {
    return null;
  }
}

/// La fecha "dd/mm/aaaa" que lleva el nombre de la etapa, si la lleva.
DateTime? _dateInName(String name) {
  final match = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(name);
  if (match == null) return null;
  try {
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    final date = DateTime.utc(year, month, day);
    // Descarta fechas imposibles (31/02...), que DateTime "arreglaría"
    // pasándolas al mes siguiente.
    if (date.day != day || date.month != month) return null;
    return date;
  } catch (_) {
    return null;
  }
}
