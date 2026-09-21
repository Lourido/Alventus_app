import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/odoo_service.dart';
import '../services/local_database_service.dart';
import '../services/sync_service.dart';
import '../models/project.dart';
import '../utils/trip_pdf.dart';

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
  // Nombre completo de la etapa tal y como está en Odoo (p. ej.
  // "Día 3 - 25/09/2026"). Hace falta para el PDF: con él se buscan la
  // descripción de la etapa y sus tareas completas.
  final String stageName;
  final String headerLine1; // "Día 3" (o el nombre completo si no encaja el patrón)
  final String? headerLine2; // fecha en dd-mm-yyyy, o el resto del texto original
  final String? headerLine3; // día de la semana, si se pudo calcular
  final List<String> taskNames;
  final DateTime? sortDate;

  _StageColumn({
    required this.stageName,
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
      return _StageColumn(stageName: stageName, headerLine1: stageName, taskNames: taskNames);
    }

    final line1 = match.group(1)!.trim();
    final rest = match.group(2)!.trim();

    final dateMatch = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(rest);
    if (dateMatch == null) {
      // No es una fecha (p.ej. "Antes de salir"): se deja tal cual.
      return _StageColumn(stageName: stageName, headerLine1: line1, headerLine2: rest, taskNames: taskNames);
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
      stageName: stageName,
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

  // ---------------------------------------------------------------------
  // GENERAR PDF
  // ---------------------------------------------------------------------

  static const _mensajeSinCobertura =
      'Lo siento. Tendrás que esperar a que tengas cobertura para hacerlo.';

  Future<void> _onGeneratePdfPressed() async {
    final includeDocuments = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Generar PDF'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Etapas y tareas únicamente', style: TextStyle(fontSize: 16)),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Etapas, tareas y documentos', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );

    if (includeDocuments == null || !mounted) return;

    // Con documentos hace falta cobertura (hay que descargarlos de Odoo):
    // se comprueba ya, hablando de verdad con el servidor, para avisar en
    // el momento en vez de después de un rato esperando.
    if (includeDocuments) {
      final canReach = await _odooService.canReachServer();
      if (!mounted) return;
      if (!canReach) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_mensajeSinCobertura), backgroundColor: Colors.orange),
        );
        return;
      }
    }

    await _generatePdf(includeDocuments: includeDocuments);
  }

  Future<void> _generatePdf({required bool includeDocuments}) async {
    final progress = ValueNotifier<String>('Preparando el PDF...');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: progress,
                  builder: (context, value, _) => Text(value),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    String result;
    try {
      final data = await _collectPdfData(includeDocuments: includeDocuments, progress: progress);
      progress.value = 'Generando el PDF...';
      result = await buildTripPdfOnWeb(jsonEncode(data), _pdfFileName(includeDocuments));
    } catch (e) {
      result = 'error: $e';
    }

    if (!mounted) return;
    // Cerrar el indicador de progreso. (El ValueNotifier no se libera a
    // mano a propósito: el diálogo aún lo está escuchando mientras se
    // anima al cerrarse, y liberarlo ahí daría un error. Al no quedar
    // nadie usándolo, se recoge solo.)
    Navigator.of(context, rootNavigator: true).pop();

    if (result != 'ok') {
      final motivo = result.startsWith('error:') ? result.substring(6).trim() : result;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se ha podido generar el PDF: $motivo'), backgroundColor: Colors.red),
      );
      return;
    }

    await _askWhereToSavePdf();
  }

  /// El PDF ya está generado: se pregunta dónde guardarlo. Si el usuario
  /// cancela el selector de carpeta, se le vuelve a preguntar (el PDF
  /// sigue preparado), hasta que lo guarde o pulse "Cancelar".
  Future<void> _askWhereToSavePdf() async {
    while (mounted) {
      // El guardado se LANZA dentro del propio onPressed (sin await
      // antes): es lo único que permite el navegador para abrir el
      // selector de carpeta o el menú de compartir (ver
      // lib/utils/trip_pdf.dart). Aquí solo se espera su resultado.
      Future<String>? saving;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('El PDF está listo'),
          content: const Text(
            'Pulsa «Guardar en…» para elegir la carpeta donde guardarlo.\n\n'
            'En el iPhone, en el menú que aparece, elige «Guardar en Archivos» '
            'y después la carpeta.\n\n'
            '«Descargar» lo guarda directamente en la carpeta de descargas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                saving = downloadTripPdfOnWeb();
                Navigator.pop(dialogContext);
              },
              child: const Text('Descargar'),
            ),
            FilledButton(
              onPressed: () {
                saving = saveTripPdfOnWeb();
                Navigator.pop(dialogContext);
              },
              child: const Text('Guardar en…'),
            ),
          ],
        ),
      );

      final pending = saving;
      if (pending == null) {
        discardTripPdfOnWeb();
        return;
      }

      final outcome = await pending;
      if (!mounted) return;

      if (outcome == 'cancelled') continue; // se vuelve a preguntar

      discardTripPdfOnWeb();
      if (outcome.startsWith('error')) {
        final motivo = outcome.substring(outcome.indexOf(':') + 1).trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se ha podido guardar el PDF: $motivo'), backgroundColor: Colors.red),
        );
      } else {
        final mensaje = switch (outcome) {
          'saved' => 'PDF guardado',
          'downloaded' => 'PDF guardado en la carpeta de descargas',
          _ => 'Hecho',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensaje), backgroundColor: Colors.green),
        );
      }
      return;
    }
  }

  /// Reúne todo lo que va en el PDF, en el formato que espera
  /// web/trip_pdf.js. Etapas y tareas salen de lo guardado en el teléfono
  /// (por eso esa opción funciona sin cobertura), y en el MISMO orden en
  /// que se ven en esta pantalla.
  Future<Map<String, dynamic>> _collectPdfData({
    required bool includeDocuments,
    required ValueNotifier<String> progress,
  }) async {
    final projectId = widget.project.id;

    final cachedStages = await _localDb.getStages(projectId);
    final descriptionByStage = <String, String>{
      for (final s in cachedStages)
        (s['name']?.toString() ?? ''): (s['description']?.toString() ?? ''),
    };

    final taskRows = await _localDb.getTasks(projectId);
    final tasksByStage = _groupTasksByStageName(taskRows);

    // Con documentos: nombres de los archivos de ruta, que NO van en el
    // PDF aunque alguien los haya subido también como documento, y el id
    // de cada etapa en Odoo, para traer sus documentos.
    final routeNames = <String>{};
    final stageIdByName = <String, int>{};
    if (includeDocuments) {
      for (final r in await _localDb.getRouteFiles(projectId)) {
        final n = r['file_name']?.toString().trim().toLowerCase();
        if (n != null && n.isNotEmpty) routeNames.add(n);
      }
      final stagesResult = await _odooService.fetchProjectStages(projectId);
      if (stagesResult['success'] == true) {
        for (final st in (stagesResult['result'] as List<dynamic>).cast<Map<String, dynamic>>()) {
          final id = st['id'];
          final name = st['name']?.toString();
          if (id is int && name != null) stageIdByName[name] = id;
        }
      }
    }

    bool isRouteFile(String name) {
      final lower = name.trim().toLowerCase();
      final ext = lower.contains('.') ? lower.substring(lower.lastIndexOf('.') + 1) : '';
      return _routeExtensions.contains(ext) || routeNames.contains(lower);
    }

    // Documentos generales del viaje (los de "Datos generales").
    final generalRows = <Map<String, dynamic>>[];
    // Documentos de cada etapa, por nombre de etapa.
    final stageRows = <String, List<Map<String, dynamic>>>{};
    if (includeDocuments) {
      progress.value = 'Buscando los documentos...';
      generalRows.addAll((await _localDb.getProjectDocuments(projectId))
          .where((d) => (d['id'] as int? ?? 0) > 0) // los pendientes aún no están en Odoo
          .where((d) => !isRouteFile(d['name']?.toString() ?? '')));

      for (final column in _columns) {
        final stageId = stageIdByName[column.stageName];
        if (stageId == null) continue;
        final result = await _odooService.fetchStageAttachments(stageId);
        if (result['success'] != true) continue;
        final rows = (result['result'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .where((d) => !isRouteFile(d['name']?.toString() ?? ''))
            .toList()
          // En el orden en que se subieron (Odoo los da del más nuevo al
          // más antiguo).
          ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
        if (rows.isNotEmpty) stageRows[column.stageName] = rows;
      }
    }

    final totalDocs = generalRows.length +
        stageRows.values.fold<int>(0, (n, l) => n + l.length);
    var downloaded = 0;

    Future<Map<String, dynamic>> download(Map<String, dynamic> row, String? mimeType) async {
      downloaded++;
      progress.value = 'Descargando documentos ($downloaded de $totalDocs)...';
      String? base64Data;
      final result = await _odooService.downloadAttachment(row['id'] as int);
      if (result['success'] == true) {
        final records = result['result'] as List<dynamic>;
        if (records.isNotEmpty) {
          final datas = (records[0] as Map<String, dynamic>)['datas'];
          if (datas is String && datas.isNotEmpty) base64Data = datas;
        }
      }
      // Si uno no se ha podido descargar, se sigue igual: en el PDF sale
      // una página que lo dice, en vez de fallar todo por un documento.
      return {
        'name': row['name']?.toString() ?? 'Documento',
        'mimeType': mimeType,
        'base64': base64Data,
      };
    }

    final generalDocuments = <Map<String, dynamic>>[];
    for (final row in generalRows) {
      generalDocuments.add(await download(row, row['mime_type']?.toString()));
    }

    final stages = <Map<String, dynamic>>[];
    for (final column in _columns) {
      final tasks = List<Map<String, dynamic>>.from(tasksByStage[column.stageName] ?? []);
      tasks.sort((a, b) {
        final seqA = a['sequence'] as int? ?? 0;
        final seqB = b['sequence'] as int? ?? 0;
        if (seqA != seqB) return seqA.compareTo(seqB);
        return (a['id'] as int).compareTo(b['id'] as int);
      });

      final stageDocuments = <Map<String, dynamic>>[];
      for (final row in stageRows[column.stageName] ?? const <Map<String, dynamic>>[]) {
        final mime = row['mimetype'];
        stageDocuments.add(await download(row, mime is String ? mime : null));
      }

      stages.add({
        'title': column.stageName,
        'subtitle': column.headerLine3,
        'description': descriptionByStage[column.stageName],
        'tasks': [
          for (final t in tasks)
            {
              'time': _pdfTimeRange(t['fecha_desde'], t['fecha_hasta']),
              'name': t['name']?.toString() ?? '',
              'description': t['description']?.toString(),
            },
        ],
        'documents': stageDocuments,
      });
    }

    return {
      'tripName': widget.project.name,
      'subtitle': _pdfTripDates(),
      'generatedAt': _pdfNow(),
      'includeDocuments': includeDocuments,
      'generalDocuments': generalDocuments,
      'stages': stages,
    };
  }

  /// Extensiones de los archivos de ruta, que no se incluyen en el PDF.
  static const _routeExtensions = {'gpx', 'kml', 'kmz', 'tcx', 'fit', 'geojson'};

  /// "09:00 - 11:00", o solo una de las dos horas si falta la otra. Se
  /// muestran igual que en la pantalla de la etapa (la hora tal cual está
  /// guardada), para que el PDF y la app digan siempre lo mismo.
  static String _pdfTimeRange(dynamic from, dynamic to) {
    final a = _pdfHour(from);
    final b = _pdfHour(to);
    if (a != null && b != null) return '$a - $b';
    if (a != null) return 'Desde $a';
    if (b != null) return 'Hasta $b';
    return '';
  }

  static String? _pdfHour(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    try {
      final dt = DateTime.parse(value);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }

  String? _pdfTripDates() {
    String? fmt(String? iso) {
      if (iso == null) return null;
      try {
        final d = DateTime.parse(iso);
        return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      } catch (_) {
        return null;
      }
    }

    final start = fmt(widget.project.dateStart);
    final end = fmt(widget.project.dateEnd);
    if (start != null && end != null) return 'Del $start al $end';
    if (start != null) return 'Desde el $start';
    return null;
  }

  static String _pdfNow() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(n.day)}/${two(n.month)}/${n.year} ${two(n.hour)}:${two(n.minute)}';
  }

  /// Nombre del archivo: "Viaje - <nombre>.pdf", sin caracteres que
  /// algunos sistemas no admiten en un nombre de archivo.
  String _pdfFileName(bool includeDocuments) {
    final clean = widget.project.name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final base = clean.isEmpty ? 'Viaje' : 'Viaje - $clean';
    return includeDocuments ? '$base (con documentos).pdf' : '$base.pdf';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Etapas y tareas'),
        actions: [
          // Solo en la versión web: el PDF se genera con web/trip_pdf.js,
          // que no existe en la app nativa.
          if (kIsWeb)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Generar PDF',
              onPressed: (_isLoading || _columns.isEmpty) ? null : _onGeneratePdfPressed,
            ),
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
