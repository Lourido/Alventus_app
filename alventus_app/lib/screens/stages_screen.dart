import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:alventus_app/widgets/speech/mic_text_field.dart';
import '../services/odoo_service.dart';
import '../services/local_database_service.dart';
import '../services/sync_service.dart';
import '../models/project.dart';
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

  _StageGroup({
    required this.stageId,
    required this.stageName,
    required this.taskCount,
    required this.taskIds,
    this.sortDate,
    this.dateLabel,
    this.description,
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
      // Sin conexión no podemos consultar las etapas reales de Odoo (no
      // se guardan en la base local); mostramos lo que haya en caché de
      // tareas, agrupado como antes (las etapas vacías no se verán hasta
      // que haya conexión, pero es lo máximo que se puede hacer offline).
      final rows = await _localDb.getTasks(widget.project.id);
      if (!mounted) return;
      setState(() {
        _isOffline = true;
        _stages = _buildGroupsFromLocalTasksOnly(rows);
        _isLoading = false;
      });
      return;
    }

    final tasksSynced = await _syncService.syncTasks(widget.project.id);

    final stagesResult = await _odooService.fetchProjectStages(widget.project.id);
    final rows = await _localDb.getTasks(widget.project.id);

    if (!mounted) return;

    if (stagesResult['success'] != true) {
      // Si falla la consulta de etapas reales, se recurre al agrupado
      // local como red de seguridad (mismo comportamiento de antes), pero
      // se avisa: hay conexión y aun así no se ha podido traer de Odoo.
      setState(() {
        _isOffline = false;
        _stages = _buildGroupsFromLocalTasksOnly(rows);
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
      // vacío, así que hay que comprobarlo explícitamente.
      final descriptionRaw = s['description'];
      final description = (descriptionRaw is String && descriptionRaw.trim().isNotEmpty)
          ? descriptionRaw.trim()
          : null;

      return _StageGroup(
        stageId: s['id'] as int?,
        stageName: name,
        taskCount: tasks.length,
        taskIds: tasks.map((t) => t['id'] as int).toList(),
        sortDate: minDate,
        dateLabel: dateLabel,
        description: description,
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
        content: Text('Hay conexión, pero no se ha podido actualizar todo con Odoo. Puede que estés viendo datos guardados.'),
        backgroundColor: Colors.orange,
      ),
    );
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
        stageId: null, // no resoluble sin conexión
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
          content: Text('Se necesita conexión a internet para esta acción'),
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

    if (!await _requireConnection()) return;

    final result = await _odooService.updateStageDescription(
      stageId: stage.stageId!,
      description: newDescription,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      await _loadStages();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error']?.toString() ?? 'No se pudo guardar la descripción'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
            content: Text('No se pueden mover tareas sin etapa asignada'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    if (!await _requireConnection()) return;

    setState(() => _isLoading = true);

    // Los ids de tarea que se van moviendo no cambian por el camino;
    // solo cambia a qué etapa están asignados. Vamos desplazándolos un
    // paso cada vez, como si se pulsara la flecha varias veces seguidas.
    final movingIds = List<int>.from(_stages[oldIndex].taskIds);
    var current = oldIndex;
    bool allOk = true;

    while (current != newIndex) {
      final next = current + step;
      final displacedIds = List<int>.from(_stages[next].taskIds);

      final resultMove = await _odooService.reassignTasksStage(
        taskIds: movingIds,
        newStageId: _stages[next].stageId!,
      );
      final resultDisplace = await _odooService.reassignTasksStage(
        taskIds: displacedIds,
        newStageId: _stages[current].stageId!,
      );
      if (resultMove['success'] != true || resultDisplace['success'] != true) {
        allOk = false;
      }

      current = next;
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_up),
                      tooltip: 'Subir',
                      style: IconButton.styleFrom(
                        shape: const CircleBorder(),
                        side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.2),
                      ),
                      onPressed: index == 0 ? null : () => _moveStageContent(index, index - 1),
                    ),
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
    return Card(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.event)),
        title: Text(stage.stageName, style: const TextStyle(fontWeight: FontWeight.bold)),
        // La descripción se ve y se puede editar siempre (tenga
        // texto o no), tocando esta zona en concreto -- el resto
        // del Card sigue abriendo las tareas de la etapa al tocarlo.
        subtitle: stage.stageId == null
            ? null
            : InkWell(
                onTap: () => _editStageDescription(stage),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          (stage.description != null && stage.description!.isNotEmpty)
                              ? stage.description!
                              : 'Sin descripción · toca para añadir',
                          style: (stage.description != null && stage.description!.isNotEmpty)
                              ? null
                              : TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.edit, size: 16, color: Colors.grey[500]),
                    ],
                  ),
                ),
              ),
        onTap: () {
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
            // Añadir/borrar tareas cambia el contador de tareas de
            // la etapa que se ve en esta lista: al volver, se
            // recarga para que se actualice.
            if (mounted) _loadStages();
          });
        },
        trailing: trailing,
      ),
    );
  }
}
