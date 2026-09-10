import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/web_file_opener.dart';
import '../services/odoo_service.dart';
import '../services/local_database_service.dart';
import '../services/sync_service.dart';
import '../models/project.dart';
import '../models/task.dart';















































import 'package:alventus_app/widgets/speech/mic_text_field.dart';
import 'task_detail_screen.dart';

/// Muestra las tareas de una etapa (día) concreta de un viaje, permite
/// crear tareas nuevas asignadas a esa etapa, y reordenarlas manualmente.
class StageTasksScreen extends StatefulWidget {
  final Project project;
  final String stageName;
  final String? stageDescription;

  const StageTasksScreen({
    super.key,
    required this.project,
    required this.stageName,
    this.stageDescription,
  });

  @override
  State<StageTasksScreen> createState() => _StageTasksScreenState();
}

/// Compara dos horas: true si [to] es igual o posterior a [from] (o si
/// alguna de las dos todavía no está definida, en cuyo caso no hay nada
/// que validar aún).
bool _isValidTimeRange(TimeOfDay? from, TimeOfDay? to) {
  if (from == null || to == null) return true;
  final fromMinutes = from.hour * 60 + from.minute;
  final toMinutes = to.hour * 60 + to.minute;
  return toMinutes >= fromMinutes;
}

class _StageTasksScreenState extends State<StageTasksScreen> {
  final OdooService _odooService = OdooService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final SyncService _syncService = SyncService();

  // Guardamos las filas "en bruto" (no solo el modelo Task) porque
  // necesitamos el campo sequence para poder reordenar, y el modelo Task
  // no lo incluye.
  List<Map<String, dynamic>> _taskRows = [];
  bool _isLoading = true;
  bool _isOffline = false;

  // Adjuntos de la etapa (día), mostrados fijos al fondo de la pantalla.
  List<Map<String, dynamic>> _stageAttachments = [];
  int? _stageId;

  // Posición del botón flotante "Nueva tarea": el usuario lo puede
  // arrastrar para que no le tape tareas o adjuntos, y se recuerda entre
  // aperturas de la app.
  Offset? _fabOffset;

  /// Fecha de la etapa extraída de su propio nombre (los nombres de etapa
  /// siguen el formato "Día N - dd/mm/aaaa" que genera el asistente de
  /// creación de viajes en Odoo).
  String? get _stageDateFromName {
    final match = RegExp(r'(\d{2}/\d{2}/\d{4})').firstMatch(widget.stageName);
    return match?.group(1);
  }

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _loadFabOffset();
  }

  static const _fabOffsetDxKey = 'stage_tasks_fab_dx';
  static const _fabOffsetDyKey = 'stage_tasks_fab_dy';

  Future<void> _loadFabOffset() async {
    final prefs = await SharedPreferences.getInstance();
    final dx = prefs.getDouble(_fabOffsetDxKey);
    final dy = prefs.getDouble(_fabOffsetDyKey);
    if (dx == null || dy == null) return;
    if (!mounted) return;
    setState(() {
      _fabOffset = Offset(dx, dy);
    });
  }

  Future<void> _saveFabOffset(Offset offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fabOffsetDxKey, offset.dx);
    await prefs.setDouble(_fabOffsetDyKey, offset.dy);
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
    });

    final hasConnection = await _syncService.checkConnectivity();
    if (!mounted) return;

    var tasksSynced = true;
    if (hasConnection) {
      tasksSynced = await _syncService.syncTasks(widget.project.id);
    }

    final rows = await _localDb.getTasks(widget.project.id);
    if (!mounted) return;

    final filtered = rows.where((row) {
      final stageName = (row['stage_name'] as String?)?.trim();
      final key = (stageName == null || stageName.isEmpty) ? 'Sin etapa' : stageName;
      return key == widget.stageName;
    }).toList();

    // Ordena por "sequence" (el campo real de Odoo para el orden manual).
    filtered.sort((a, b) {
      final seqA = a['sequence'] as int? ?? 0;
      final seqB = b['sequence'] as int? ?? 0;
      if (seqA != seqB) return seqA.compareTo(seqB);
      return (a['id'] as int).compareTo(b['id'] as int);
    });

    // Resuelve (si hay conexión) el id real de la etapa en Odoo, para
    // poder sincronizar y mostrar sus adjuntos. "Sin etapa" es un
    // pseudo-grupo sin id real, así que no tiene adjuntos.
    int? resolvedStageId = _stageId;
    if (widget.stageName != 'Sin etapa' && hasConnection) {
      resolvedStageId = await _odooService.resolveStageId(
        projectId: widget.project.id,
        stageName: widget.stageName,
      );
    }
    if (!mounted) return;

    List<Map<String, dynamic>> stageAttachments = _stageAttachments;
    if (resolvedStageId != null) {
      if (hasConnection) {
        await _syncService.syncStageAttachments(resolvedStageId);
        if (!mounted) return;
      }
      stageAttachments = await _localDb.getStageAttachments(resolvedStageId);
      if (!mounted) return;
    }

    setState(() {
      _isOffline = !hasConnection;
      _taskRows = filtered;
      _stageId = resolvedStageId;
      _stageAttachments = stageAttachments;
      _isLoading = false;
    });

    if (hasConnection && !tasksSynced && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hay conexión, pero no se ha podido actualizar con Odoo. Puede que estés viendo datos guardados.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Task _taskFromRow(Map<String, dynamic> row) {
    return Task(
      id: row['id'] as int,
      name: row['name'] as String? ?? '',
      description: row['description'] as String?,
      projectId: row['project_id'] as int,
      stageName: row['stage_name'] as String?,
      deadline: row['deadline'] as String?,
      priority: row['priority'] as String? ?? '0',
      fechaDesde: row['fecha_desde'] as String?,
      fechaHasta: row['fecha_hasta'] as String?,
    );
  }

  /// Construye la etiqueta de fecha a mostrar: la fecha de la etapa (misma
  /// para todas las tareas del día), más la hora de la tarea si la tuviera.
  String? _dateLabelForRow(Map<String, dynamic> row) {
    String? timePart;
    final fechaDesde = row['fecha_desde'] as String?;
    if (fechaDesde != null && fechaDesde.isNotEmpty) {
      try {
        final dt = DateTime.parse(fechaDesde);
        if (dt.hour != 0 || dt.minute != 0) {
          timePart = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        }
      } catch (_) {}
    }

    final stageDate = _stageDateFromName;
    if (stageDate == null && timePart == null) return null;
    if (stageDate == null) return timePart;
    return timePart != null ? '$stageDate $timePart' : stageDate;
  }

  // ---------------------------------------------------------------------
  // REORDENAR TAREAS (arrastrando)
  // ---------------------------------------------------------------------

  Future<void> _onReorderTasks(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    await _moveTaskTo(oldIndex, newIndex);
  }

  /// Mueve la tarea de [oldIndex] a [newIndex] (posición final exacta,
  /// no un desplazamiento relativo) y renumera todas según el nuevo
  /// orden. La usan tanto el arrastre (app nativa) como los botones de
  /// subir/bajar (web).
  Future<void> _moveTaskTo(int oldIndex, int newIndex) async {
    final hasConnection = await _syncService.checkConnectivity();
    if (!hasConnection) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se necesita conexión a internet para reordenar tareas'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Se recoloca la tarea en su nueva posición y se renumeran todas
    // según el nuevo orden en pantalla (más simple y fiable que ir
    // intercambiando de una en una).
    final reordered = List<Map<String, dynamic>>.from(_taskRows);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    setState(() {
      _taskRows = reordered;
      _isLoading = true;
    });

    for (var i = 0; i < reordered.length; i++) {
      await _odooService.updateTaskSequence(taskId: reordered[i]['id'] as int, sequence: i * 10);
    }

    await _syncService.syncTasks(widget.project.id);

    if (!mounted) return;
    await _loadTasks();
  }

  // ---------------------------------------------------------------------
  // CREAR TAREA
  // ---------------------------------------------------------------------

  void _showCreateTaskDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    // Las horas desde/hasta ya no se piden aquí: se ocultan también en la
    // creación, igual que en la lista de tareas (siguen existiendo como
    // campos opcionales por si algún día hicieran falta, pero no se
    // muestran ni se rellenan desde este diálogo).
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Nueva tarea'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MicTextField(
                      controller: nameController,
                      // Igual que en el detalle de tarea: permite salto de
                      // línea con el "intro" del teclado en nombres largos.
                      maxLines: null,
                      minLines: 1,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de la tarea',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    MicTextField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: 'Descripción (opcional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;

                    Navigator.pop(dialogContext);
                    await _createTask(name, descController.text.trim());
                  },
                  child: const Text('Crear'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Combina la fecha de esta etapa (extraída de su nombre) con una hora
  /// concreta, en el formato "yyyy-MM-dd HH:mm:ss" que espera Odoo.
  String? _combineStageDateWithTime(TimeOfDay? time) {
    if (time == null) return null;

    final stageDateStr = _stageDateFromName; // "dd/mm/yyyy"
    DateTime baseDate;
    if (stageDateStr != null) {
      final parts = stageDateStr.split('/');
      baseDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
    } else {
      baseDate = DateTime.now();
    }

    final combined = DateTime(baseDate.year, baseDate.month, baseDate.day, time.hour, time.minute);
    return '${combined.year.toString().padLeft(4, '0')}-${combined.month.toString().padLeft(2, '0')}-'
        '${combined.day.toString().padLeft(2, '0')} ${combined.hour.toString().padLeft(2, '0')}:'
        '${combined.minute.toString().padLeft(2, '0')}:00';
  }

  /// Crea la tarea asignada a esta etapa (por nombre). Si hay conexión,
  /// se crea directamente en Odoo; si no, se guarda localmente y se
  /// encola para sincronizar más tarde (la etapa se resuelve por nombre
  /// en el momento de sincronizar, ver [OdooService.createTaskInStage]).
  Future<void> _createTask(
    String name,
    String description, [
    TimeOfDay? timeFrom,
    TimeOfDay? timeTo,
  ]) async {
    final fechaDesde = _combineStageDateWithTime(timeFrom);
    final fechaHasta = _combineStageDateWithTime(timeTo);

    final hasConnection = await _syncService.checkConnectivity();

    if (hasConnection) {
      final result = await _odooService.createTaskInStage(
        projectId: widget.project.id,
        name: name,
        description: description.isNotEmpty ? description : null,
        stageId: _stageId,
        stageName: widget.stageName,
        fechaDesde: fechaDesde,
        fechaHasta: fechaHasta,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        await _syncService.syncTasks(widget.project.id);
        if (!mounted) return;
        _loadTasks();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error']?.toString() ?? 'Error al crear la tarea'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else {
      // Sin conexión: se guarda localmente con el nombre de esta etapa
      // para que se vea ya en la lista, y se encola para sincronizar.
      final tempId = -DateTime.now().millisecondsSinceEpoch;

      await _localDb.saveTasks([
        {
          'id': tempId,
          'name': name,
          'description': description.isNotEmpty ? description : null,
          'project_id': widget.project.id,
          'stage_name': widget.stageName,
          'deadline': null,
          'priority': '0',
          'fecha_desde': fechaDesde,
          'fecha_hasta': fechaHasta,
          'sequence': 0,
        },
      ]);

      await _localDb.addPendingChange(
        model: 'project.task',
        action: 'create',
        recordId: tempId,
        data: {
          'project_id': widget.project.id.toString(),
          'name': name,
          'description': description,
          'stage_name': widget.stageName,
          // Id de la etapa que ya se conocía en este momento (si lo hay):
          // al sincronizar se prueba primero por id, que sobrevive a que
          // renombren la etapa en Odoo mientras la tarea seguía en cola.
          if (_stageId != null) 'stage_id': _stageId.toString(),
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tarea guardada localmente. Se sincronizará cuando haya conexión.'),
          backgroundColor: Colors.orange,
        ),
      );

      _loadTasks();
    }
  }

  /// Edita la hora (desde o hasta) de una tarea directamente desde la
  /// lista, sin tener que entrar a su detalle. La fecha se toma de la
  /// etapa (no hace falta pedirla, ya se conoce).
  Future<void> _editTaskTime(Map<String, dynamic> row, {required bool isFrom}) async {
    final fieldValue = (isFrom ? row['fecha_desde'] : row['fecha_hasta']) as String?;
    TimeOfDay? currentTime;
    if (fieldValue != null && fieldValue.isNotEmpty) {
      try {
        final dt = DateTime.parse(fieldValue);
        currentTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
      } catch (_) {}
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: currentTime ?? TimeOfDay.now(),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (picked == null) return;

    // Comprueba coherencia contra el valor ACTUAL del otro campo (el que
    // no se está editando ahora mismo).
    final otherFieldValue = (isFrom ? row['fecha_hasta'] : row['fecha_desde']) as String?;
    TimeOfDay? otherTime;
    if (otherFieldValue != null && otherFieldValue.isNotEmpty) {
      try {
        final dt = DateTime.parse(otherFieldValue);
        otherTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
      } catch (_) {}
    }

    final isValid = isFrom ? _isValidTimeRange(picked, otherTime) : _isValidTimeRange(otherTime, picked);

    if (!isValid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFrom
                ? 'La hora "desde" no puede ser posterior a la hora "hasta" ya guardada'
                : 'La hora "hasta" no puede ser anterior a la hora "desde" ya guardada',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final newValue = _combineStageDateWithTime(picked);
    if (newValue == null) return;

    final hasConnection = await _syncService.checkConnectivity();
    if (!hasConnection) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se necesita conexión a internet para cambiar la hora'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final taskId = row['id'] as int;
    final result = await _odooService.updateTask(
      taskId: taskId,
      fechaDesde: isFrom ? newValue : null,
      fechaHasta: isFrom ? null : newValue,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      await _syncService.syncTasks(widget.project.id);
      if (!mounted) return;
      _loadTasks();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error']?.toString() ?? 'No se pudo cambiar la hora'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _timeChipLabel(Map<String, dynamic> row, {required bool isFrom}) {
    final fieldValue = (isFrom ? row['fecha_desde'] : row['fecha_hasta']) as String?;
    if (fieldValue == null || fieldValue.isEmpty) {
      return isFrom ? 'Desde: --:--' : 'Hasta: --:--';
    }
    try {
      final dt = DateTime.parse(fieldValue);
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return isFrom ? 'Desde: $h:$m' : 'Hasta: $h:$m';
    } catch (_) {
      return isFrom ? 'Desde: --:--' : 'Hasta: --:--';
    }
  }

  // ---------------------------------------------------------------------
  // ADJUNTOS DE LA ETAPA
  // ---------------------------------------------------------------------

  Future<void> _pickStageAttachment() async {
    if (_stageId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se puede adjuntar todavía: hace falta conexión la primera vez'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final stageId = _stageId!;

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final validFiles = result.files.where((f) => f.bytes != null).toList();
    if (validFiles.isEmpty) return;

    if (!mounted) return;

    final existingNames = _stageAttachments
        .map((d) => (d['name']?.toString() ?? '').toLowerCase())
        .toSet();

    final confirmedFiles = await _showFilesReviewDialog(
      pickedFiles: validFiles,
      existingNamesLowercase: existingNames,
    );

    if (confirmedFiles == null || confirmedFiles.isEmpty || !mounted) return;

    final hasConnection = await _syncService.checkConnectivity();

    if (!hasConnection) {
      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sin conexión: en el navegador hace falta conexión para subir archivos'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      for (final pickedFile in confirmedFiles) {
        await _localDb.saveOfflineStageAttachment(
          stageId: stageId,
          fileName: pickedFile.name,
          filePath: pickedFile.path!,
          fileSize: pickedFile.size,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${confirmedFiles.length} archivo(s) guardado(s) sin conexión. Se subirán cuando haya señal.',
          ),
        ),
      );
      _loadTasks();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Subiendo ${confirmedFiles.length} archivo(s)...')),
    );

    int okCount = 0;
    for (final pickedFile in confirmedFiles) {
      final uploadResult = await _odooService.uploadStageAttachment(
        stageId: stageId,
        fileName: pickedFile.name,
        bytes: pickedFile.bytes!,
      );
      if (uploadResult['success'] == true) okCount++;
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          okCount == confirmedFiles.length
              ? '$okCount archivo(s) subido(s) correctamente'
              : '$okCount de ${confirmedFiles.length} archivo(s) subidos (algunos fallaron)',
        ),
        backgroundColor: okCount == 0 ? Colors.red : null,
      ),
    );

    _loadTasks();
  }

  Future<List<PlatformFile>?> _showFilesReviewDialog({
    required List<PlatformFile> pickedFiles,
    required Set<String> existingNamesLowercase,
  }) async {
    final selected = <String>{
      for (final f in pickedFiles)
        if (!existingNamesLowercase.contains(f.name.toLowerCase())) f.name,
    };

    return showDialog<List<PlatformFile>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Confirmar archivos'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: pickedFiles.length,
                  itemBuilder: (context, index) {
                    final f = pickedFiles[index];
                    final isDuplicate = existingNamesLowercase.contains(f.name.toLowerCase());
                    final isChecked = selected.contains(f.name);

                    return CheckboxListTile(
                      value: isChecked,
                      activeColor: Theme.of(context).colorScheme.primary,
                      checkColor: Colors.white,
                      side: BorderSide(color: Theme.of(context).colorScheme.onSurface, width: 1.5),
                      title: Text(f.name),
                      subtitle: isDuplicate
                          ? const Text(
                              'Ya existe aquí con este nombre',
                              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                            )
                          : null,
                      onChanged: (checked) {
                        setDialogState(() {
                          if (checked == true) {
                            selected.add(f.name);
                          } else {
                            selected.remove(f.name);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () {
                          final chosen = pickedFiles.where((f) => selected.contains(f.name)).toList();
                          Navigator.pop(dialogContext, chosen);
                        },
                  child: const Text('Subir'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _downloadAndOpenStageAttachment(Map<String, dynamic> attachment) async {
    final attachmentId = attachment['id'] as int;
    final fileName = attachment['name']?.toString() ?? 'archivo';

    if (attachmentId < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este archivo todavía no se ha subido, espera a que haya conexión'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Descargando $fileName...')),
    );

    final result = await _odooService.downloadAttachment(attachmentId);

    if (!mounted) return;

    if (result['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo descargar el archivo'), backgroundColor: Colors.red),
      );
      return;
    }

    final records = result['result'] as List<dynamic>;
    if (records.isEmpty) return;

    final base64Data = (records[0] as Map<String, dynamic>)['datas'] as String?;
    if (base64Data == null) return;

    try {
      final bytes = base64Decode(base64Data);

      if (kIsWeb) {
        final opened = await openBytesOnWeb(bytes, fileName);
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo abrir el archivo'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/$fileName';
      final localFile = File(filePath);
      await localFile.writeAsBytes(bytes);

      await OpenFilex.open(filePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir el archivo: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _confirmDeleteStageAttachment(Map<String, dynamic> attachment) async {
    final attachmentId = attachment['id'] as int;
    final fileName = attachment['name']?.toString() ?? 'este archivo';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrar adjunto'),
        content: Text('¿Seguro que quieres borrar "$fileName"?'),
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

    if (attachmentId < 0) {
      // Adjunto aún sin subir (pendiente sin conexión): se borra solo en
      // local.
      await _localDb.deleteStageAttachmentLocal(attachmentId);
      _loadTasks();
      return;
    }

    final result = await _odooService.deleteAttachment(attachmentId);

    if (!mounted) return;

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adjunto borrado'), backgroundColor: Colors.green),
      );
      _loadTasks();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo borrar el adjunto'), backgroundColor: Colors.red),
      );
    }
  }

  /// Fila fija, siempre visible, con los adjuntos de la etapa: es la
  /// última línea de la pantalla, no forma parte del scroll de tareas.
  Widget _buildAttachmentsFooter() {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file),
              tooltip: 'Adjuntar archivo a esta etapa',
              onPressed: _pickStageAttachment,
            ),
            Expanded(
              child: _stageAttachments.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Sin archivos adjuntos en esta etapa',
                        style: TextStyle(color: Theme.of(context).disabledColor),
                      ),
                    )
                  : SizedBox(
                      height: 40,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _stageAttachments.length,
                        itemBuilder: (context, index) {
                          final doc = _stageAttachments[index];
                          final name = doc['name']?.toString() ?? 'Archivo';
                          final pending = (doc['id'] as int) < 0;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InputChip(
                              avatar: Icon(
                                pending ? Icons.cloud_upload_outlined : Icons.insert_drive_file,
                                size: 16,
                              ),
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 140),
                                child: Text(name, overflow: TextOverflow.ellipsis),
                              ),
                              onPressed: () => _downloadAndOpenStageAttachment(doc),
                              onDeleted: () => _confirmDeleteStageAttachment(doc),
                              deleteIcon: const Icon(Icons.close, size: 16),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.stageName),
            Text(
              (widget.stageDescription != null && widget.stageDescription!.trim().isNotEmpty)
                  ? widget.stageDescription!.trim()
                  : 'Sin descripción',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
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
      body: Column(
        children: [
          Expanded(child: _buildBodyWithDraggableFab()),
          _buildAttachmentsFooter(),
        ],
      ),
    );
  }

  // Tamaño aproximado del botón "Nueva tarea", para poder mantenerlo
  // dentro de los límites de la pantalla al arrastrarlo o al calcular su
  // posición inicial.
  static const double _fabWidthEstimate = 168;
  static const double _fabHeightEstimate = 56;
  static const double _fabMargin = 16;

  /// La lista de tareas con el botón "Nueva tarea" flotando encima, en
  /// vez de fijo abajo a la derecha: el usuario lo puede arrastrar a
  /// cualquier punto de esta zona para que deje de taparle una tarea, y
  /// la posición elegida se recuerda. Se mantiene fuera de la franja de
  /// adjuntos (que va debajo, fija) para no poder taparla.
  Widget _buildBodyWithDraggableFab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDx = (constraints.maxWidth - _fabWidthEstimate - _fabMargin)
            .clamp(_fabMargin, double.infinity);
        final maxDy = (constraints.maxHeight - _fabHeightEstimate - _fabMargin)
            .clamp(_fabMargin, double.infinity);

        final currentOffset = _fabOffset ?? Offset(maxDx, maxDy);
        final clampedOffset = Offset(
          currentOffset.dx.clamp(_fabMargin, maxDx),
          currentOffset.dy.clamp(_fabMargin, maxDy),
        );

        return Stack(
          children: [
            _buildBody(),
            Positioned(
              left: clampedOffset.dx,
              top: clampedOffset.dy,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _showCreateTaskDialog,
                onPanUpdate: (details) {
                  setState(() {
                    _fabOffset = Offset(
                      (clampedOffset.dx + details.delta.dx).clamp(_fabMargin, maxDx),
                      (clampedOffset.dy + details.delta.dy).clamp(_fabMargin, maxDy),
                    );
                  });
                },
                onPanEnd: (_) {
                  if (_fabOffset != null) _saveFabOffset(_fabOffset!);
                },
                child: Material(
                  color: Theme.of(context).colorScheme.primary,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, color: Theme.of(context).colorScheme.onPrimary),
                        const SizedBox(width: 8),
                        Text(
                          'Nueva tarea',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_taskRows.isEmpty) {
      return const Center(child: Text('Esta etapa no tiene tareas todavía'));
    }

    final Widget list = kIsWeb
        ? ListView.builder(
            itemCount: _taskRows.length,
            itemBuilder: (context, index) {
              // En web el arrastre no es fiable en móviles (el navegador
              // se queda con el toque para hacer scroll), así que aquí
              // se usan botones de subir/bajar en su lugar.
              return _buildTaskCard(
                index,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_up),
                      tooltip: 'Subir',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        shape: const CircleBorder(),
                        side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.2),
                      ),
                      onPressed: index == 0 ? null : () => _moveTaskTo(index, index - 1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down),
                      tooltip: 'Bajar',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        shape: const CircleBorder(),
                        side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.2),
                      ),
                      onPressed: index == _taskRows.length - 1 ? null : () => _moveTaskTo(index, index + 1),
                    ),
                  ],
                ),
              );
            },
          )
        : ReorderableListView.builder(
            buildDefaultDragHandles: false,
            onReorder: _onReorderTasks,
            itemCount: _taskRows.length,
            itemBuilder: (context, index) {
              final row = _taskRows[index];
              return _buildTaskCard(
                index,
                key: ValueKey(row['id']),
                trailing: ReorderableDelayedDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Tooltip(
                      message: 'Mantén pulsado y arrastra para reordenar',
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ),
              );
            },
          );

    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: list,
    );
  }

  /// Construye la tarjeta de una tarea. El [trailing] lo decide quien la
  /// use: en web son botones de subir/bajar, y en la app nativa es el
  /// icono de arrastrar.
  Widget _buildTaskCard(int index, {required Widget trailing, Key? key}) {
    final row = _taskRows[index];
    final task = _taskFromRow(row);

    return Card(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        // Sin icono a la izquierda: así el nombre de la tarea
        // aprovecha todo el ancho del recuadro.
        title: Text(task.name),
        trailing: trailing,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TaskDetailScreen(task: task),
            ),
          ).then((_) {
            // Al volver de editar la tarea, recargamos para que el
            // cambio se vea reflejado aquí sin tener que salir y
            // volver a entrar a mano.
            if (mounted) _loadTasks();
          });
        },
      ),
    );
  }
}
