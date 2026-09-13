import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:alventus_app/widgets/speech/mic_text_field.dart';
import '../services/odoo_service.dart';
import '../services/local_database_service.dart';
import '../services/sync_service.dart';
import '../models/project.dart';
import '../utils/html_text.dart';
import 'stage_tasks_screen.dart';

/// Muestra las etapas (días) de un viaje. La lista de etapas sale
/// directamente de Odoo (project.task.type), no de las tareas locales,
/// para que las etapas vacías (recién creadas, o que se queden vacías
/// tras un intercambio) también se vean. Las tareas locales solo se usan
/// para contar cuántas tiene cada una.
///
/// Permite reordenar (intercambiando el contenido de dos etapas, sin
/// tocar sus nombres/fechas), borrar una etapa entera, y añadir una
/// etapa nueva al final.
class StagesScreen extends StatefulWidget {
  final Project project;

  const StagesScreen({super.key, required this.project});

  @override
  State<StagesScreen> createState() => _StagesScreenState();
}

/// Reconoce el patrón "Día N - dd/mm/aaaa" que genera el asistente de
/// creación de viajes, para poder extraer el número de día y la fecha.
final RegExp _numberedStagePattern = RegExp(r'^Día\s*(\d+)\s*-\s*(\d{2})/(\d{2})/(\d{4})$');

class _NumberedStage {
  final int dayNumber;
  final DateTime date;
  _NumberedStage({required this.dayNumber, required this.date});
}

_NumberedStage? _parseNumberedStage(String stageName) {
  final match = _numberedStagePattern.firstMatch(stageName.trim());
  if (match == null) return null;
  try {
    final dayNumber = int.parse(match.group(1)!);
    final day = int.parse(match.group(2)!);
    final month = int.parse(match.group(3)!);
    final year = int.parse(match.group(4)!);
    return _NumberedStage(dayNumber: dayNumber, date: DateTime(year, month, day));
  } catch (_) {
    return null;
  }
}

String _formatStageName(int dayNumber, DateTime date) {
  final d = date.day.toString().padLeft(2, '0');
  final m = date.month.toString().padLeft(2, '0');
  final y = date.year.toString();
  return 'Día $dayNumber - $d/$m/$y';
}

class _StageGroup {
  final int? stageId; // null solo para el pseudo-grupo "Sin etapa"
  final String stageName;
  final int taskCount;
  final List<int> taskIds;
  final DateTime? sortDate;
  final String? dateLabel;
  final String? description;
  // Orden real de Odoo (campo "sequence" de project.task.type). Solo se
  // conoce cuando la etapa viene de una consulta en vivo a Odoo (no en
  // el respaldo offline, que solo agrupa tareas locales); se usa como
  // criterio de orden preferente -- ver _sortStages.
  final int? sequence;

  _StageGroup({
    required this.stageId,
    required this.stageName,
    required this.taskCount,
    required this.taskIds,
    this.sortDate,
    this.dateLabel,
    this.description,
    this.sequence,
  });
}

class _StagesScreenState extends State<StagesScreen> {
  final OdooService _odooService = OdooService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final SyncService _syncService = SyncService();

  List<_StageGroup> _stages = [];
  bool _isLoading = true;
  bool _isOffline = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStages();
  }

  /// Agrupa las tareas locales por nombre de etapa (clave = nombre, o
  /// "Sin etapa" si no tienen ninguna asignada).
  Map<String, List<Map<String, dynamic>>> _groupTasksByStageName(
    List<Map<String, dynamic>> rows,
  ) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final row in rows) {
      final stageName = (row['stage_name'] as String?)?.trim();
      final key = (stageName == null || stageName.isEmpty) ? 'Sin etapa' : stageName;
      grouped.putIfAbsent(key, () => []).add(row);
    }
    return grouped;
  }

  DateTime? _minDateOf(List<Map<String, dynamic>> tasks) {
    DateTime? minDate;
    for (final t in tasks) {
      final fechaDesde = t['fecha_desde'] as String?;
      if (fechaDesde != null && fechaDesde.isNotEmpty) {
        try {
          final d = DateTime.parse(fechaDesde);
          if (minDate == null || d.isBefore(minDate)) minDate = d;
        } catch (_) {}
      }
    }
    return minDate;
  }

  Future<void> _loadStages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final hasConnection = await _syncService.checkConnectivity();
    if (!mounted) return;

    if (!hasConnection) {
      // Sin conexión se usan las etapas guardadas en el teléfono la
      // última vez que hubo conexión (con su id y su descripción), y las
      // tareas locales solo para contar cuántas tiene cada una.
      final rows = await _localDb.getTasks(widget.project.id);
      final cached = await _localDb.getStages(widget.project.id);
      if (!mounted) return;
      setState(() {
        _isOffline = true;
        _stages = _mergeWithCurrent(_buildGroupsOffline(cached, rows));
        _isLoading = false;
      });
      return;
    }

    final tasksSynced = await _syncService.syncTasks(widget.project.id);

    final stagesResult = await _odooService.fetchProjectStages(widget.project.id);
    final rows = await _localDb.getTasks(widget.project.id);

    if (!mounted) return;

    if (stagesResult['success'] != true) {
      // Si no se ha podido traer la lista de etapas de Odoo, se usan las
      // que quedaron guardadas en el teléfono la última vez (con su id y
      // su descripción). Es el caso normal en modo avión, porque en web
      // la comprobación de conexión de más arriba es optimista a
      // propósito y solo el intento real contra Odoo lo descubre.
      final cached = await _localDb.getStages(widget.project.id);
      if (!mounted) return;
      setState(() {
        _isOffline = true;
        _stages = _mergeWithCurrent(_buildGroupsOffline(cached, rows));
        _isLoading = false;
      });
      _warnSyncFailed();
      return;
    }

    final realStages = (stagesResult['result'] as List<dynamic>).cast<Map<String, dynamic>>();
    final tasksByStageName = _groupTasksByStageName(rows);

    final stageGroups = realStages.map((s) {
      final name = s['name']?.toString() ?? '';
      final tasks = tasksByStageName[name] ?? [];

      final parsed = _parseNumberedStage(name);
      final minDate = _minDateOf(tasks) ?? parsed?.date;
      final dateLabel = minDate != null
          ? '${minDate.day.toString().padLeft(2, '0')}/${minDate.month.toString().padLeft(2, '0')}/${minDate.year}'
          : null;
      // Odoo devuelve `false` (no null ni "") cuando el campo Text está
      // vacío, así que hay que comprobarlo explícitamente. stripHtmlToPlainText
      // también quita etiquetas <p>/<br>... por si el campo llegara a
      // guardarse alguna vez con HTML en vez de texto plano.
      final descriptionRaw = s['description'];
      final description = descriptionRaw is String ? stripHtmlToPlainText(descriptionRaw) : null;

      return _StageGroup(
        stageId: s['id'] as int?,
        stageName: name,
        taskCount: tasks.length,
        taskIds: tasks.map((t) => t['id'] as int).toList(),
        sortDate: minDate,
        dateLabel: dateLabel,
        description: description,
        sequence: s['sequence'] as int?,
      );
    }).toList();

    // Las tareas "Sin etapa" no son una etapa real de Odoo, así que no
    // salen en fetchProjectStages: se añaden aparte si existen.
    final tasksWithoutStage = tasksByStageName['Sin etapa'];
    if (tasksWithoutStage != null && tasksWithoutStage.isNotEmpty) {
      stageGroups.add(_StageGroup(
        stageId: null,
        stageName: 'Sin etapa',
        taskCount: tasksWithoutStage.length,
        taskIds: tasksWithoutStage.map((t) => t['id'] as int).toList(),
      ));
    }

    _sortStages(stageGroups);

    // Se guardan en el teléfono para poder seguir viéndolas (y
    // moviéndolas/editándolas) cuando no haya conexión.
    try {
      await _localDb.saveStages(
        widget.project.id,
        stageGroups
            .where((g) => g.stageId != null)
            .map((g) => {
                  'id': g.stageId,
                  'name': g.stageName,
                  'description': g.description,
                  'sequence': g.sequence ?? 0,
                })
            .toList(),
      );
    } catch (e) {
      // Que no se puedan guardar las etapas no debe impedir verlas: sin
      // este try, un fallo aquí dejaba la pantalla cargando para siempre.
      print('⚠️ No se pudieron guardar las etapas en el teléfono: $e');
    }

    if (!mounted) return;

    setState(() {
      _isOffline = false;
      _stages = stageGroups;
      _isLoading = false;
    });

    if (!tasksSynced) _warnSyncFailed();
  }

  /// Avisa de que había conexión pero no se ha podido actualizar del todo
  /// con Odoo (así que puede que se esté viendo información guardada).
  void _warnSyncFailed() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('NO hay conexión. Estás viendo los datos guardados en el teléfono la última vez que usaste la app con conexión.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  /// Arma la lista de etapas sin conexión, a partir de las etapas
  /// guardadas en el teléfono (que sí traen id, descripción y orden) más
  /// las tareas locales para contar cuántas tiene cada una.
  ///
  /// Si todavía no hubiera ninguna etapa guardada (por ejemplo, en una
  /// instalación nueva que nunca ha llegado a abrir este viaje con
  /// conexión), se recurre al respaldo de siempre: agrupar solo por el
  /// nombre de etapa que lleva cada tarea, sin id ni descripción.
  List<_StageGroup> _buildGroupsOffline(
    List<Map<String, dynamic>> cachedStages,
    List<Map<String, dynamic>> rows,
  ) {
    if (cachedStages.isEmpty) return _buildGroupsFromLocalTasksOnly(rows);

    final tasksByStageName = _groupTasksByStageName(rows);
    final knownNames = <String>{};

    final groups = cachedStages.map((s) {
      final name = s['name']?.toString() ?? '';
      knownNames.add(name);
      final tasks = tasksByStageName[name] ?? [];
      final parsed = _parseNumberedStage(name);
      final minDate = _minDateOf(tasks) ?? parsed?.date;
      final dateLabel = minDate != null
          ? '${minDate.day.toString().padLeft(2, '0')}/${minDate.month.toString().padLeft(2, '0')}/${minDate.year}'
          : null;
      final description = s['description']?.toString();

      return _StageGroup(
        stageId: s['id'] as int?,
        stageName: name,
        taskCount: tasks.length,
        taskIds: tasks.map((t) => t['id'] as int).toList(),
        sortDate: minDate,
        dateLabel: dateLabel,
        description: (description != null && description.isNotEmpty) ? description : null,
        sequence: s['sequence'] as int?,
      );
    }).toList();

    // Tareas cuyo nombre de etapa no está entre las guardadas (por
    // ejemplo "Sin etapa", o una etapa creada en Odoo después de la
    // última vez que hubo conexión): se añaden aparte, como antes.
    for (final entry in tasksByStageName.entries) {
      if (knownNames.contains(entry.key)) continue;
      final tasks = entry.value;
      final parsed = _parseNumberedStage(entry.key);
      final minDate = _minDateOf(tasks) ?? parsed?.date;
      final dateLabel = minDate != null
          ? '${minDate.day.toString().padLeft(2, '0')}/${minDate.month.toString().padLeft(2, '0')}/${minDate.year}'
          : null;
      groups.add(_StageGroup(
        stageId: entry.key == 'Sin etapa' ? null : _stageIdFromTasks(tasks),
        stageName: entry.key,
        taskCount: tasks.length,
        taskIds: tasks.map((t) => t['id'] as int).toList(),
        sortDate: minDate,
        dateLabel: dateLabel,
      ));
    }

    _sortStages(groups);
    return groups;
  }

  /// Completa los grupos recién armados con lo que ya hubiera en
  /// pantalla: si al perder la cobertura un grupo se queda sin id o sin
  /// descripción, pero esa misma etapa ya se estaba viendo con ellos, se
  /// conservan. Así una recarga sin cobertura nunca deja la pantalla peor
  /// de lo que ya estaba.
  List<_StageGroup> _mergeWithCurrent(List<_StageGroup> groups) {
    if (_stages.isEmpty) return groups;

    final previous = {for (final s in _stages) s.stageName: s};

    return groups.map((g) {
      final old = previous[g.stageName];
      if (old == null) return g;
      if (g.stageId != null && g.description != null) return g;

      return _StageGroup(
        stageId: g.stageId ?? old.stageId,
        stageName: g.stageName,
        taskCount: g.taskCount,
        taskIds: g.taskIds,
        sortDate: g.sortDate ?? old.sortDate,
        dateLabel: g.dateLabel ?? old.dateLabel,
        description: g.description ?? old.description,
        sequence: g.sequence ?? old.sequence,
      );
    }).toList();
  }

  /// Saca el id de etapa a partir de las tareas de esa etapa: cada tarea
  /// guarda el id de su etapa en Odoo (columna stage_id), así que sin
  /// cobertura se puede recuperar de ahí.
  int? _stageIdFromTasks(List<Map<String, dynamic>> tasks) {
    for (final t in tasks) {
      final id = t['stage_id'];
      if (id is int) return id;
      if (id != null) {
        final parsed = int.tryParse(id.toString());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  /// Respaldo para el modo offline: agrupa solo a partir de las tareas
  /// locales (las etapas vacías no se pueden ver sin conexión).
  List<_StageGroup> _buildGroupsFromLocalTasksOnly(List<Map<String, dynamic>> rows) {
    final grouped = _groupTasksByStageName(rows);
    final groups = grouped.entries.map((entry) {
      final tasks = entry.value;
      final parsed = _parseNumberedStage(entry.key);
      final minDate = _minDateOf(tasks) ?? parsed?.date;
      final dateLabel = minDate != null
          ? '${minDate.day.toString().padLeft(2, '0')}/${minDate.month.toString().padLeft(2, '0')}/${minDate.year}'
          : null;

      return _StageGroup(
        stageId: entry.key == 'Sin etapa' ? null : _stageIdFromTasks(tasks),
        stageName: entry.key,
        taskCount: tasks.length,
        taskIds: tasks.map((t) => t['id'] as int).toList(),
        sortDate: minDate,
        dateLabel: dateLabel,
      );
    }).toList();

    _sortStages(groups);
    return groups;
  }

  /// Reconoce específicamente la etapa "Día 0" (con o sin fecha, con o
  /// sin el resto del texto como "Antes de salir"), para que se pueda
  /// forzar siempre a la primera posición.
  bool _isDayZero(String stageName) {
    return RegExp(r'^Día\s*0(\D|$)').hasMatch(stageName.trim());
  }

  void _sortStages(List<_StageGroup> groups) {
    groups.sort((a, b) {
      final aIsZero = _isDayZero(a.stageName);
      final bIsZero = _isDayZero(b.stageName);
      if (aIsZero && !bIsZero) return -1;
      if (bIsZero && !aIsZero) return 1;
      if (aIsZero && bIsZero) return 0;

      // Si las dos etapas tienen secuencia real de Odoo, esa es la que
      // manda: es el mismo orden que se ve en la propia web de Odoo
      // (project.task.type se pide ya ordenada por "sequence asc"), y
      // no depende de qué fecha tengan las tareas de cada una -- así
      // que si el usuario reordena las etapas desde Odoo directamente
      // (sin tocar nombres/fechas), la app lo respeta igual.
      if (a.sequence != null && b.sequence != null) {
        return a.sequence!.compareTo(b.sequence!);
      }

      if (a.sortDate == null && b.sortDate == null) return a.stageName.compareTo(b.stageName);
      if (a.sortDate == null) return 1;
      if (b.sortDate == null) return -1;
      return a.sortDate!.compareTo(b.sortDate!);
    });
  }

  Future<bool> _requireConnection() async {
    final hasConnection = await _syncService.checkConnectivity();
    if (!hasConnection && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lo siento. Tendrás que esperar a que tengas cobertura para hacerlo.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return hasConnection;
  }

  /// Abre un diálogo para ver/editar la descripción de una etapa, y la
  /// guarda en Odoo. Se puede ver y editar siempre, tenga o no
  /// descripción ya puesta.
  Future<void> _editStageDescription(_StageGroup stage) async {
    if (stage.stageId == null) return; // "Sin etapa" no es una etapa real

    final controller = TextEditingController(text: stage.description ?? '');

    final newDescription = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Descripción de "${stage.stageName}"'),
        content: MicTextField(
          controller: controller,
          maxLines: 4,
          minLines: 1,
          decoration: const InputDecoration(
            hintText: 'Escribe una descripción para esta etapa...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (newDescription == null) return; // cancelado
    if (newDescription == (stage.description ?? '')) return; // sin cambios

    final hasConnection = await _syncService.hasRealNetwork();

    if (hasConnection) {
      final result = await _odooService.updateStageDescription(
        stageId: stage.stageId!,
        description: newDescription,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        await _loadStages();
        return;
      }

      // Si el fallo NO es por falta de conexión (un error de Odoo de
      // verdad), se avisa y no se toca nada más.
      if (result['offline'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error']?.toString() ?? 'No se pudo guardar la descripción'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Ha fallado porque no se ha podido llegar al servidor: se
      // continúa abajo y se guarda en el teléfono, igual que si no
      // hubiera habido conexión desde el principio. Esto es lo que hace
      // que funcione en el iPhone, donde el navegador dice que sí hay
      // conexión aunque el teléfono esté en modo avión.
    }

    // Sin conexión: se encola para sincronizar luego y se refleja ya en
    // pantalla (no se puede recargar de Odoo estando offline).
    await _localDb.addPendingChange(
      model: 'project.task.type',
      action: 'update',
      recordId: stage.stageId!,
      data: {'description': newDescription},
    );
    await _localDb.updateStageDescriptionLocal(stage.stageId!, newDescription);

    if (!mounted) return;

    setState(() {
      _stages = _stages.map((s) {
        if (s.stageId != stage.stageId) return s;
        return _StageGroup(
          stageId: s.stageId,
          stageName: s.stageName,
          taskCount: s.taskCount,
          taskIds: s.taskIds,
          sortDate: s.sortDate,
          dateLabel: s.dateLabel,
          description: newDescription,
          sequence: s.sequence,
        );
      }).toList();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cambios guardados en el teléfono. Cuando haya conexión se subirán al servidor.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 1. REORDENAR: arrastrando una etapa, se intercambia el contenido
  // (tareas) con las etapas que va cruzando por el camino, sin tocar
  // ningún nombre ni fecha, que se quedan tal cual en su sitio.
  // ---------------------------------------------------------------------

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    await _moveStageContent(oldIndex, newIndex);
  }

  Future<void> _moveStageContent(int oldIndex, int newIndex) async {
    final step = newIndex > oldIndex ? 1 : -1;
    for (var i = oldIndex; i != newIndex + step; i += step) {
      if (_stages[i].stageId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sin cobertura no consigo identificar esta etapa. Abre este viaje una vez con cobertura y vuelve a intentarlo.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    // A diferencia de otras acciones de esta pantalla, mover una etapa NO
    // se bloquea sin conexión: si no hay red, se guarda ya en el teléfono
    // (tareas + descripciones) y se encola para sincronizar con Odoo en
    // cuanto vuelva la cobertura -- igual que ya se hace en la edición de
    // tareas (ver sync_service.dart).
    // Puede cambiar sobre la marcha: si a mitad del movimiento se ve que
    // no se llega al servidor, se pasa a guardar en el teléfono.
    var hasConnection = await _syncService.hasRealNetwork();

    setState(() => _isLoading = true);

    // Los ids de tarea que se van moviendo no cambian por el camino;
    // solo cambia a qué etapa están asignados. Vamos desplazándolos un
    // paso cada vez, como si se pulsara la flecha varias veces seguidas.
    // La DESCRIPCIÓN de la etapa viaja solidaria con las tareas (se
    // intercambia exactamente igual que ellas); el NOMBRE de la etapa,
    // en cambio, se queda fijo en su sitio -- no se toca aquí.
    final movingIds = List<int>.from(_stages[oldIndex].taskIds);
    final movingDescription = _stages[oldIndex].description ?? '';
    var current = oldIndex;
    bool allOk = true;

    // Copia mutable de _stages que se va actualizando paso a paso, para
    // poder reflejarla directamente en pantalla cuando no hay conexión
    // (sin pasar por _loadStages(), que sin conexión reconstruiría los
    // grupos desde cero solo con las tareas locales y perdería el
    // resultado que se acaba de aplicar aquí).
    final updatedStages = List<_StageGroup>.from(_stages);

    while (current != newIndex) {
      final next = current + step;
      final displacedIds = List<int>.from(_stages[next].taskIds);
      final displacedDescription = _stages[next].description ?? '';

      if (hasConnection) {
        final resultMove = await _odooService.reassignTasksStage(
          taskIds: movingIds,
          newStageId: _stages[next].stageId!,
        );
        final resultDisplace = await _odooService.reassignTasksStage(
          taskIds: displacedIds,
          newStageId: _stages[current].stageId!,
        );
        final resultDescMove = await _odooService.updateStageDescription(
          stageId: _stages[next].stageId!,
          description: movingDescription,
        );
        final resultDescDisplace = await _odooService.updateStageDescription(
          stageId: _stages[current].stageId!,
          description: displacedDescription,
        );
        // ¿Ha fallado alguna por no poder llegar al servidor? Entonces
        // no hay conexión de verdad, se pasa a modo sin conexión y este
        // mismo paso se guarda ya en el teléfono (las anotaciones que se
        // encolan fijan el valor final, así que no importa que alguna de
        // las llamadas de arriba sí hubiera llegado a hacerse).
        if (resultMove['offline'] == true ||
            resultDisplace['offline'] == true ||
            resultDescMove['offline'] == true ||
            resultDescDisplace['offline'] == true) {
          hasConnection = false;
        } else if (resultMove['success'] != true ||
            resultDisplace['success'] != true ||
            resultDescMove['success'] != true ||
            resultDescDisplace['success'] != true) {
          allOk = false;
        }
      }

      if (!hasConnection) {
        for (final id in movingIds) {
          await _localDb.updateTask(id, {'stage_name': _stages[next].stageName});
          await _localDb.addPendingChange(
            model: 'project.task',
            action: 'update',
            recordId: id,
            data: {'stage_id': _stages[next].stageId},
          );
        }
        for (final id in displacedIds) {
          await _localDb.updateTask(id, {'stage_name': _stages[current].stageName});
          await _localDb.addPendingChange(
            model: 'project.task',
            action: 'update',
            recordId: id,
            data: {'stage_id': _stages[current].stageId},
          );
        }
        await _localDb.addPendingChange(
          model: 'project.task.type',
          action: 'update',
          recordId: _stages[next].stageId,
          data: {'description': movingDescription},
        );
        await _localDb.addPendingChange(
          model: 'project.task.type',
          action: 'update',
          recordId: _stages[current].stageId,
          data: {'description': displacedDescription},
        );
        await _localDb.updateStageDescriptionLocal(_stages[next].stageId!, movingDescription);
        await _localDb.updateStageDescriptionLocal(_stages[current].stageId!, displacedDescription);
      }

      updatedStages[next] = _StageGroup(
        stageId: _stages[next].stageId,
        stageName: _stages[next].stageName,
        taskCount: movingIds.length,
        taskIds: movingIds,
        sortDate: _stages[next].sortDate,
        dateLabel: _stages[next].dateLabel,
        description: movingDescription,
        sequence: _stages[next].sequence,
      );
      updatedStages[current] = _StageGroup(
        stageId: _stages[current].stageId,
        stageName: _stages[current].stageName,
        taskCount: displacedIds.length,
        taskIds: displacedIds,
        sortDate: _stages[current].sortDate,
        dateLabel: _stages[current].dateLabel,
        description: displacedDescription,
        sequence: _stages[current].sequence,
      );

      current = next;
    }

    if (!hasConnection) {
      if (!mounted) return;
      setState(() {
        _stages = updatedStages;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cambios guardados en el teléfono. Cuando haya conexión se subirán al servidor.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await _syncService.syncTasks(widget.project.id);

    if (!mounted) return;

    if (!allOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alguna tarea no se pudo mover correctamente'),
          backgroundColor: Colors.red,
        ),
      );
    }

    await _loadStages();
  }

  // ---------------------------------------------------------------------
  // 2. BORRAR ETAPA
  // ---------------------------------------------------------------------

  Future<void> _confirmDeleteStage(_StageGroup stage) async {
    if (stage.stageId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esto no es una etapa real, no se puede borrar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrar etapa'),
        content: Text(
          '¿Seguro que quieres borrar "${stage.stageName}"?\n\n'
          'Se borrarán sus ${stage.taskCount} tarea(s), las etapas '
          'siguientes se renumerarán un día hacia atrás, y el viaje '
          'durará un día menos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!await _requireConnection()) return;

    setState(() => _isLoading = true);

    // 1. Quitar (borrar) todas las tareas de esta etapa.
    final deleteTasksResult = await _odooService.deleteTasks(stage.taskIds);

    // 2. Borrar la propia etapa.
    final deleteStageResult = await _odooService.deleteStage(stage.stageId!);

    bool renameFailed = false;

    // 3. Si la etapa borrada tenía un día/fecha reconocible, renumerar
    // hacia atrás las etapas siguientes (las que tengan fecha posterior).
    final deletedParsed = _parseNumberedStage(stage.stageName);
    if (deletedParsed != null) {
      final subsequentStages = _stages.where((s) {
        if (s.stageId == null || s.stageId == stage.stageId) return false;
        final parsed = _parseNumberedStage(s.stageName);
        return parsed != null && parsed.date.isAfter(deletedParsed.date);
      }).toList();

      subsequentStages.sort((a, b) => a.sortDate!.compareTo(b.sortDate!));

      for (final s in subsequentStages) {
        final parsed = _parseNumberedStage(s.stageName)!;
        final newDayNumber = parsed.dayNumber - 1;
        final newDate = parsed.date.subtract(const Duration(days: 1));

        final renameResult = await _odooService.renameStage(
          stageId: s.stageId!,
          newName: _formatStageName(newDayNumber, newDate),
        );
        if (renameResult['success'] != true) renameFailed = true;
      }

      // 4. El viaje dura un día menos: retrasa la fecha de fin un día.
      final currentEnd = widget.project.dateEnd;
      if (currentEnd != null) {
        try {
          final endDate = DateTime.parse(currentEnd);
          await _odooService.updateProjectEndDate(
            projectId: widget.project.id,
            newEndDate: endDate.subtract(const Duration(days: 1)),
          );
        } catch (_) {}
      }
    }

    await _syncService.syncTasks(widget.project.id);
    await _syncService.syncProjects();

    if (!mounted) return;

    if (deleteTasksResult['success'] != true || deleteStageResult['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hubo un problema al borrar (revisa la etapa en Odoo)'),
          backgroundColor: Colors.red,
        ),
      );
    } else if (renameFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Etapa borrada, pero alguna etapa siguiente no se pudo renumerar'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    await _loadStages();
  }

  // ---------------------------------------------------------------------
  // 3. AÑADIR ETAPA
  // ---------------------------------------------------------------------

  Future<void> _addStage() async {
    if (!await _requireConnection()) return;

    setState(() => _isLoading = true);

    final stagesResult = await _odooService.fetchProjectStages(widget.project.id);
    if (stagesResult['success'] != true) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron obtener las etapas'), backgroundColor: Colors.red),
      );
      return;
    }

    final realStages = (stagesResult['result'] as List<dynamic>).cast<Map<String, dynamic>>();

    int maxDayNumber = 0;
    DateTime? maxDate;
    int maxSequence = 0;

    for (final s in realStages) {
      final seq = s['sequence'] as int? ?? 0;
      if (seq > maxSequence) maxSequence = seq;

      final parsed = _parseNumberedStage(s['name']?.toString() ?? '');
      if (parsed != null) {
        if (parsed.dayNumber > maxDayNumber) maxDayNumber = parsed.dayNumber;
        if (maxDate == null || parsed.date.isAfter(maxDate)) maxDate = parsed.date;
      }
    }

    final newDayNumber = maxDayNumber + 1;
    DateTime newDate;
    if (maxDate != null) {
      newDate = maxDate.add(const Duration(days: 1));
    } else if (widget.project.dateStart != null) {
      try {
        newDate = DateTime.parse(widget.project.dateStart!);
      } catch (_) {
        newDate = DateTime.now();
      }
    } else {
      newDate = DateTime.now();
    }

    final newName = _formatStageName(newDayNumber, newDate);

    final createResult = await _odooService.createStageForProject(
      projectId: widget.project.id,
      name: newName,
      sequence: maxSequence + 1,
    );

    if (createResult['success'] == true) {
      // El viaje dura un día más: adelanta la fecha de fin un día.
      final currentEnd = widget.project.dateEnd;
      if (currentEnd != null) {
        try {
          final endDate = DateTime.parse(currentEnd);
          await _odooService.updateProjectEndDate(
            projectId: widget.project.id,
            newEndDate: endDate.add(const Duration(days: 1)),
          );
        } catch (_) {}
      }
      await _syncService.syncProjects();
    }

    if (!mounted) return;

    if (createResult['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Etapa "$newName" añadida'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(createResult['error']?.toString() ?? 'No se pudo añadir la etapa'),
          backgroundColor: Colors.red,
        ),
      );
    }

    await _loadStages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Etapas'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Icon(
              _isOffline ? Icons.cloud_off : Icons.cloud_done,
              color: _isOffline ? Colors.orange : Colors.green,
            ),
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _addStage,
        icon: const Icon(Icons.add),
        label: const Text('Añadir etapa'),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _loadStages, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    if (_stages.isEmpty) {
      return const Center(child: Text('Este viaje no tiene etapas todavía'));
    }

    final Widget list = kIsWeb
        ? ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: _stages.length,
            itemBuilder: (context, index) {
              final stage = _stages[index];
              // En web el arrastre no es fiable en móviles (el navegador
              // se queda con el toque para hacer scroll), así que aquí se
              // usan botones de subir/bajar en su lugar.
              return _buildStageCard(
                index,
                trailing: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down),
                      tooltip: 'Bajar',
                      style: IconButton.styleFrom(
                        shape: const CircleBorder(),
                        side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.2),
                      ),
                      onPressed: index == _stages.length - 1 ? null : () => _moveStageContent(index, index + 1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Borrar etapa',
                      onPressed: () => _confirmDeleteStage(stage),
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_up),
                      tooltip: 'Subir',
                      style: IconButton.styleFrom(
                        shape: const CircleBorder(),
                        side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.2),
                      ),
                      onPressed: index == 0 ? null : () => _moveStageContent(index, index - 1),
                    ),
                  ],
                ),
              );
            },
          )
        : ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            buildDefaultDragHandles: false,
            onReorder: _onReorder,
            itemCount: _stages.length,
            itemBuilder: (context, index) {
              final stage = _stages[index];
              return _buildStageCard(
                index,
                key: ValueKey(stage.stageId ?? -1),
                // Arrastrando este icono se reordena (se intercambia
                // contenido con las etapas intermedias); el botón de
                // borrar se mantiene aparte.
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Borrar etapa',
                      onPressed: () => _confirmDeleteStage(stage),
                    ),
                    ReorderableDelayedDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Tooltip(
                          message: 'Mantén pulsado y arrastra para reordenar',
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );

    return RefreshIndicator(
      onRefresh: _loadStages,
      child: list,
    );
  }

  /// Construye la tarjeta de una etapa (icono, nombre, descripción
  /// editable y el gesto para entrar a sus tareas). El [trailing] lo
  /// decide quien la use: en web son botones de subir/bajar/borrar, y
  /// en la app nativa es el icono de arrastrar + borrar.
  Widget _buildStageCard(int index, {required Widget trailing, Key? key}) {
    final stage = _stages[index];
    // Primera línea: nombre de la etapa, y su fecha entre paréntesis
    // cuando se conoce (viene de la fecha más temprana entre sus
    // tareas, o del propio nombre si va numerado con fecha).
    final title = stage.dateLabel != null
        ? '${stage.stageName} (Día ${stage.dateLabel})'
        : stage.stageName;

    void openStageTasks() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StageTasksScreen(
            project: widget.project,
            stageName: stage.stageName,
            stageDescription: stage.description,
          ),
        ),
      ).then((_) {
        // Añadir/borrar tareas cambia el contador de tareas de la etapa
        // que se ve en esta lista: al volver, se recarga para que se
        // actualice.
        if (mounted) _loadStages();
      });
    }

    return Card(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Línea 1: nombre de la etapa (Día dd/mm/yyyy). Tocar aquí
          // (o la línea 2) abre las tareas de la etapa.
          InkWell(
            onTap: openStageTasks,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const CircleAvatar(child: Icon(Icons.event)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Línea 2: descripción de la etapa. Se ve y se puede editar
          // siempre (tenga texto o no), tocando esta zona en concreto.
          if (stage.stageId != null)
            InkWell(
              onTap: () => _editStageDescription(stage),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        (stage.description != null && stage.description!.isNotEmpty)
                            ? stage.description!
                            : 'Sin descripción · toca para añadir',
                        style: (stage.description != null && stage.description!.isNotEmpty)
                            ? const TextStyle(fontSize: 16)
                            : TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic, fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.edit, size: 16, color: Colors.grey[500]),
                  ],
                ),
              ),
            )
          else
            InkWell(
              onTap: openStageTasks,
              child: const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(height: 4),
              ),
            ),
          const Divider(height: 1),
          // Línea 3: los botones de la etapa (bajar / borrar / subir en
          // la variante web, o borrar + arrastrar en la app nativa).
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: trailing,
          ),
        ],
      ),
    );
  }
}
