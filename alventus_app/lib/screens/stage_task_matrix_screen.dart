import 'package:flutter/material.dart';
import '../services/odoo_service.dart';
import '../services/local_database_service.dart';
import '../services/sync_service.dart';
import '../models/project.dart';

/// Muestra una rejilla con las etapas del viaje en columnas (4 visibles a
/// la vez, con scroll horizontal para ver el resto) y, dentro de cada
/// columna, las tareas de esa etapa (con scroll vertical para ver las
/// que no quepan). El scroll vertical mueve todas las columnas a la vez,
/// y la fila de cabecera (el día) se queda fija arriba.
class StageTaskMatrixScreen extends StatefulWidget {
  final Project project;

  const StageTaskMatrixScreen({super.key, required this.project});

  @override
  State<StageTaskMatrixScreen> createState() => _StageTaskMatrixScreenState();
}

class _StageColumn {
  final String headerLine1; // "Día 3" (o el nombre completo si no encaja el patrón)
  final String? headerLine2; // fecha en dd-mm-yyyy, o el resto del texto original
  final String? headerLine3; // día de la semana, si se pudo calcular
  final List<String> taskNames;
  final DateTime? sortDate;

  _StageColumn({
    required this.headerLine1,
    this.headerLine2,
    this.headerLine3,
    required this.taskNames,
    this.sortDate,
  });
}

const _weekdayNames = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];

class _StageTaskMatrixScreenState extends State<StageTaskMatrixScreen> {
  final OdooService _odooService = OdooService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final SyncService _syncService = SyncService();

  // Dos controladores en vez de uno compartido: compartir un único
  // ScrollController entre dos widgets de scroll NO sincroniza el
  // arrastre del usuario (solo mueve el que realmente se toca), así que
  // hace falta sincronizarlos a mano con listeners.
  final ScrollController _headerController = ScrollController();
  final ScrollController _bodyController = ScrollController();
  bool _isSyncingScroll = false;

  List<_StageColumn> _columns = [];
  bool _isLoading = true;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _headerController.addListener(() => _syncScroll(_headerController, _bodyController));
    _bodyController.addListener(() => _syncScroll(_bodyController, _headerController));
  }

  void _syncScroll(ScrollController source, ScrollController target) {
    if (_isSyncingScroll) return;
    if (!target.hasClients) return;
    if (target.offset == source.offset) return;

    _isSyncingScroll = true;
    target.jumpTo(source.offset);
    _isSyncingScroll = false;
  }

  @override
  void dispose() {
    _headerController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  /// Descompone el nombre de una etapa (p.ej. "Día 3 - 25/09/2026") en:
  /// línea 1 = "Día 3", línea 2 = fecha en dd-mm-yyyy (o el resto del
  /// texto si no es una fecha, como en "Día 0 - Antes de salir"), y
  /// línea 3 = el día de la semana, si se pudo calcular.
  _StageColumn _parseStageName(String stageName, List<String> taskNames) {
    final match = RegExp(r'^(Día\s*\d+)\s*-\s*(.+)$').firstMatch(stageName.trim());

    if (match == null) {
      return _StageColumn(headerLine1: stageName, taskNames: taskNames);
    }

    final line1 = match.group(1)!.trim();
    final rest = match.group(2)!.trim();

    final dateMatch = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(rest);
    if (dateMatch == null) {
      // No es una fecha (p.ej. "Antes de salir"): se deja tal cual.
      return _StageColumn(headerLine1: line1, headerLine2: rest, taskNames: taskNames);
    }

    final day = dateMatch.group(1)!;
    final month = dateMatch.group(2)!;
    final year = dateMatch.group(3)!;
    final line2 = '$day-$month-$year';

    String? line3;
    DateTime? sortDate;
    try {
      sortDate = DateTime(int.parse(year), int.parse(month), int.parse(day));
      line3 = _weekdayNames[(sortDate.weekday - 1) % 7];
    } catch (_) {}

    return _StageColumn(
      headerLine1: line1,
      headerLine2: line2,
      headerLine3: line3,
      taskNames: taskNames,
      sortDate: sortDate,
    );
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final hasConnection = await _syncService.checkConnectivity();
    if (!mounted) return;

    if (!hasConnection) {
      // Sin conexión no se pueden consultar las etapas reales; se recurre
      // al agrupado por tareas locales como red de seguridad (las etapas
      // vacías no se verán hasta que haya conexión).
      final rows = await _localDb.getTasks(widget.project.id);
      if (!mounted) return;
      setState(() {
        _isOffline = true;
        _columns = _buildColumnsFromLocalTasksOnly(rows);
        _isLoading = false;
      });
      return;
    }

    await _syncService.syncTasks(widget.project.id);

    final stagesResult = await _odooService.fetchProjectStages(widget.project.id);
    final rows = await _localDb.getTasks(widget.project.id);

    if (!mounted) return;

    if (stagesResult['success'] != true) {
      setState(() {
        _isOffline = false;
        _columns = _buildColumnsFromLocalTasksOnly(rows);
        _isLoading = false;
      });
      return;
    }

    final realStages = (stagesResult['result'] as List<dynamic>).cast<Map<String, dynamic>>();
    final tasksByStageName = _groupTasksByStageName(rows);

    final columns = realStages.map((s) {
      final name = s['name']?.toString() ?? '';
      final tasks = List<Map<String, dynamic>>.from(tasksByStageName[name] ?? []);
      tasks.sort((a, b) {
        final seqA = a['sequence'] as int? ?? 0;
        final seqB = b['sequence'] as int? ?? 0;
        if (seqA != seqB) return seqA.compareTo(seqB);
        return (a['id'] as int).compareTo(b['id'] as int);
      });

      return _parseStageName(name, tasks.map((t) => t['name'] as String? ?? '').toList());
    }).toList();

    // Las tareas "Sin etapa" no son una etapa real de Odoo, así que no
    // salen en fetchProjectStages: se añaden aparte si existen.
    final tasksWithoutStage = tasksByStageName['Sin etapa'];
    if (tasksWithoutStage != null && tasksWithoutStage.isNotEmpty) {
      columns.add(_parseStageName(
        'Sin etapa',
        tasksWithoutStage.map((t) => t['name'] as String? ?? '').toList(),
      ));
    }

    _sortColumns(columns);

    setState(() {
      _isOffline = false;
      _columns = columns;
      _isLoading = false;
    });
  }

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

  /// Respaldo para el modo offline: agrupa solo a partir de las tareas
  /// locales (las etapas vacías no se pueden ver sin conexión).
  List<_StageColumn> _buildColumnsFromLocalTasksOnly(List<Map<String, dynamic>> rows) {
    final grouped = _groupTasksByStageName(rows);
    final columns = grouped.entries.map((entry) {
      final tasks = List<Map<String, dynamic>>.from(entry.value);
      tasks.sort((a, b) {
        final seqA = a['sequence'] as int? ?? 0;
        final seqB = b['sequence'] as int? ?? 0;
        if (seqA != seqB) return seqA.compareTo(seqB);
        return (a['id'] as int).compareTo(b['id'] as int);
      });
      return _parseStageName(entry.key, tasks.map((t) => t['name'] as String? ?? '').toList());
    }).toList();

    _sortColumns(columns);
    return columns;
  }

  void _sortColumns(List<_StageColumn> columns) {
    columns.sort((a, b) {
      final aIsZero = RegExp(r'^Día\s*0$').hasMatch(a.headerLine1.trim());
      final bIsZero = RegExp(r'^Día\s*0$').hasMatch(b.headerLine1.trim());
      if (aIsZero && !bIsZero) return -1;
      if (bIsZero && !aIsZero) return 1;
      if (aIsZero && bIsZero) return 0;

      if (a.sortDate == null && b.sortDate == null) return a.headerLine1.compareTo(b.headerLine1);
      if (a.sortDate == null) return 1;
      if (b.sortDate == null) return -1;
      return a.sortDate!.compareTo(b.sortDate!);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Etapas y tareas'),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _columns.isEmpty
              ? const Center(child: Text('Este viaje no tiene etapas todavía'))
              : _buildGrid(context),
    );
  }

  Widget _buildGrid(BuildContext context) {
    // 7 columnas en horizontal, 4 en vertical.
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final visibleColumns = isLandscape ? 7 : 4;
    final columnWidth = MediaQuery.of(context).size.width / visibleColumns;

    return Column(
      children: [
        // Cabecera con el día de cada etapa, fija arriba (no se desplaza
        // verticalmente), pero sí en horizontal junto al cuerpo.
        SingleChildScrollView(
          controller: _headerController,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _columns.map((col) {
              return Container(
                width: columnWidth,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  border: Border(
                    right: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      col.headerLine1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    if (col.headerLine2 != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        col.headerLine2!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                    if (col.headerLine3 != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        col.headerLine3!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ),

        // Cuerpo: scroll vertical por fuera (mueve todas las columnas a la
        // vez) y scroll horizontal por dentro compartiendo el mismo
        // controlador que la cabecera.
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              controller: _bodyController,
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _columns.map((col) {
                  return Container(
                    width: columnWidth,
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: col.taskNames.map((name) {
                        return Container(
                          margin: const EdgeInsets.all(4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          // Sin límite de líneas: la tarjeta crece lo que
                          // haga falta para mostrar el nombre completo.
                          child: Text(name, style: const TextStyle(fontSize: 13)),
                        );
                      }).toList(),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
