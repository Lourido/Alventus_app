import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../utils/web_file_opener.dart';
import '../services/odoo_service.dart';
import '../models/task.dart';
import '../models/attachment.dart';
import '../services/local_database_service.dart';
import '../services/sync_service.dart';
import '../utils/push_notifications.dart';
import 'package:alventus_app/widgets/speech/mic_text_field.dart';
import '../services/usage_log_service.dart';
import '../utils/app_messages.dart';

class TaskDetailScreen extends StatefulWidget {
  final Task task;

  const TaskDetailScreen({super.key, required this.task});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  final OdooService _odooService = OdooService();
  final ImagePicker _imagePicker = ImagePicker();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final SyncService _syncService = SyncService();

  late Task _task;
  List<Attachment> _attachments = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  // Controladores para edición
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    UsageLog.screen('Abre una tarea', detail: widget.task.name);
    _nameController = TextEditingController(text: _task.name);
    _descriptionController = TextEditingController(text: _task.description ?? '');
    _loadTaskData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadTaskData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Verificar si hay conexión
    final hasConnection = await _syncService.checkConnectivity();

    if (!mounted) return;

    if (hasConnection) {
      // Hay conexión: cargar datos actualizados de Odoo
      final taskResult = await _odooService.fetchTask(_task.id);
      if (!mounted) return;

      if (taskResult['success'] == true) {
        final List<dynamic> records = taskResult['result'] as List<dynamic>;
        if (records.isNotEmpty) {
          _task = Task.fromJson(records[0] as Map<String, dynamic>);
          _nameController.text = _task.name;
          _descriptionController.text = _task.description ?? '';
        }
      }

      // Sincronizar adjuntos desde Odoo a la base de datos local
      await _syncService.syncAttachments(_task.id);
    }

    // Cargar adjuntos desde la base de datos local
    // (ya sea porque se sincronizaron o porque son los últimos guardados)
    final localAttachments = await _localDb.getAttachments(_task.id);

    if (!mounted) return;

    setState(() {
      _attachments = localAttachments.map((row) {
        return Attachment(
          id: row['id'] as int,
          name: row['name'] as String? ?? '',
          mimeType: row['mime_type'] as String?,
          fileSize: row['file_size'] as int?,
          createDate: row['create_date'] as String?,
        );
      }).toList();
      _isLoading = false;
    });
  }

  // Guardar cambios de la tarea
  Future<void> _saveTask() async {
    UsageLog.action('Guarda una tarea', detail: _task.name);
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Msg.of('tarea_sin_nombre')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    // Puede cambiar sobre la marcha: si al intentar guardar se ve que no
    // se llega al servidor, se guarda en el teléfono. Hace falta mirarlo
    // así porque en el iPhone el navegador dice que hay conexión aunque
    // el teléfono esté en modo avión.
    var hasConnection = await _syncService.hasRealNetwork();

    if (!mounted) return;

    if (hasConnection) {
      // Hay conexión: actualizar directamente en Odoo
      final result = await _odooService.updateTask(
        taskId: _task.id,
        name: name,
        description: description,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        // IMPORTANTE: También actualizar la base de datos local
        await _localDb.updateTask(_task.id, {
          'name': name,
          'description': description,
        });

        if (!mounted) return;

        setState(() {
          _isSaving = false;
          _task = Task(
            id: _task.id,
            name: name,
            description: description,
            projectId: _task.projectId,
            stageName: _task.stageName,
            deadline: _task.deadline,
            priority: _task.priority,
            fechaDesde: _task.fechaDesde,
            fechaHasta: _task.fechaHasta,
            avisoAntelacion: _task.avisoAntelacion,
          );
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tarea actualizada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (result['offline'] == true) {
        // No se ha podido llegar al servidor: se guarda en el teléfono,
        // como si no hubiera habido conexión desde el principio.
        hasConnection = false;
      } else {
        setState(() {
          _isSaving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? 'Error al actualizar'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    if (!hasConnection) {
      // No hay conexión: guardar localmente y añadir a pendientes
      await _localDb.updateTask(_task.id, {
        'name': name,
        'description': description,
      });

      await _localDb.addPendingChange(
        model: 'project.task',
        action: 'update',
        recordId: _task.id,
        data: {
          'name': name,
          'description': description,
        },
      );

      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _task = Task(
          id: _task.id,
          name: name,
          description: description,
          projectId: _task.projectId,
          stageName: _task.stageName,
          deadline: _task.deadline,
          priority: _task.priority,
          fechaDesde: _task.fechaDesde,
          fechaHasta: _task.fechaHasta,
          avisoAntelacion: _task.avisoAntelacion,
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Msg.of('guardado_en_telefono')),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------
  // HORA DE INICIO Y AVISO EN EL TELÉFONO
  // ---------------------------------------------------------------------
  //
  // La hora de inicio es el campo fecha_desde de Odoo (fecha y hora), del
  // que solo interesa la hora: el día es el de la etapa. Si la tarea tiene
  // hora, Odoo manda un aviso a los teléfonos del viaje a esa hora (o el
  // rato antes que se elija aquí). Ver lib/utils/push_notifications.dart.
  // Se guarda al momento, sin esperar al botón "Guardar".

  static const _avisoLabels = {
    '0': 'Aviso a la hora de inicio',
    '15': 'Aviso 15 minutos antes',
    '30': 'Aviso 30 minutos antes',
    '60': 'Aviso 1 hora antes',
    'no': 'Sin aviso (solo la hora)',
  };

  /// Día de la tarea: el de la etapa ("Día 3 - 23/09/2026"); si la etapa no
  /// lleva fecha, el que ya tuviera la tarea; y si tampoco, hoy.
  DateTime _taskDay() {
    final match = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(_task.stageName ?? '');
    if (match != null) {
      try {
        return DateTime(int.parse(match.group(3)!), int.parse(match.group(2)!), int.parse(match.group(1)!));
      } catch (_) {}
    }
    final current = _task.fechaDesde;
    if (current != null && current.isNotEmpty && current != 'false') {
      try {
        final dt = DateTime.parse(current);
        return DateTime(dt.year, dt.month, dt.day);
      } catch (_) {}
    }
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String _formatForOdoo(DateTime day, TimeOfDay time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${day.year.toString().padLeft(4, '0')}-${two(day.month)}-${two(day.day)} '
        '${two(time.hour)}:${two(time.minute)}:00';
  }

  Future<void> _pickStartTime() async {
    UsageLog.action('Pone la hora de inicio de una tarea', detail: _task.name);
    final current = Task.startTimeOf(_task.fechaDesde);
    final picked = await showTimePicker(
      context: context,
      initialTime: current != null
          ? TimeOfDay(hour: current.hour, minute: current.minute)
          : const TimeOfDay(hour: 9, minute: 0),
      initialEntryMode: TimePickerEntryMode.input,
      helpText: 'Hora de inicio',
      // Siempre en formato 24 horas (13:00, no 1:00 PM): con el de 12
      // horas no se distinguían las 12:00 de las 00:00.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    if (picked.hour == 0 && picked.minute == 0) {
      // Las 00:00 se toman como "sin hora" (ver Task.startTimeOf).
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pon una hora distinta de las 00:00 (por ejemplo, 00:05).'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final hadTime = current != null;
    await _saveStartTime(_formatForOdoo(_taskDay(), picked), _task.avisoAntelacion);
    if (!hadTime) await _remindToEnablePush();
  }

  Future<void> _clearStartTime() async {
    await _saveStartTime(null, _task.avisoAntelacion);
  }

  Future<void> _changeAviso(String? aviso) async {
    if (aviso == null || aviso == _task.avisoAntelacion) return;
    await _saveStartTime(_task.fechaDesde, aviso);
  }

  /// Si se acaba de poner una hora y este teléfono no tiene los avisos
  /// activados, se le dice dónde activarlos.
  Future<void> _remindToEnablePush() async {
    if (!kIsWeb) return;
    final status = await PushNotifications.status();
    if (!mounted || status == PushStatus.enabled) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Para que te llegue el aviso a este teléfono, actívalos en la '
          'campana de la pantalla de inicio.',
        ),
        duration: Duration(seconds: 6),
      ),
    );
  }

  Task _taskWithStart(String? fechaDesde, String aviso) {
    return Task(
      id: _task.id,
      name: _task.name,
      description: _task.description,
      projectId: _task.projectId,
      stageName: _task.stageName,
      deadline: _task.deadline,
      priority: _task.priority,
      fechaDesde: fechaDesde,
      fechaHasta: _task.fechaHasta,
      avisoAntelacion: aviso,
    );
  }

  /// Guarda la hora de inicio ([fechaDesde] null = quitarla) y el aviso.
  /// Con cobertura va directo a Odoo; sin ella, se guarda en el teléfono y
  /// se sube después, como el resto de cambios.
  Future<void> _saveStartTime(String? fechaDesde, String aviso) async {
    final previous = _task;
    setState(() => _task = _taskWithStart(fechaDesde, aviso));

    final localValues = {'fecha_desde': fechaDesde, 'aviso_antelacion': aviso};

    var hasConnection = await _syncService.hasRealNetwork();
    if (hasConnection) {
      final result = await _odooService.updateTaskStartTime(
        taskId: _task.id,
        fechaDesde: fechaDesde,
        aviso: aviso,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        if (result['avisoNotSaved'] == true) {
          // Odoo aún no conoce el campo del aviso: el módulo no se ha
          // actualizado en el servidor. La hora sí se ha guardado.
          await _localDb.updateTask(_task.id, {'fecha_desde': fechaDesde});
          if (!mounted) return;
          setState(() => _task = _taskWithStart(fechaDesde, previous.avisoAntelacion));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Hora guardada, pero el aviso no: falta actualizar el módulo '
                'de Alventus en el servidor de Odoo.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 6),
            ),
          );
          return;
        }
        await _localDb.updateTask(_task.id, localValues);
        return;
      }
      if (result['offline'] == true) {
        hasConnection = false;
      } else {
        setState(() => _task = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se ha podido guardar la hora: ${result['error'] ?? ''}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Sin conexión: al teléfono, y a la cola para subirlo luego.
    await _localDb.updateTask(_task.id, localValues);
    await _localDb.addPendingChange(
      model: 'project.task',
      action: 'update',
      recordId: _task.id,
      data: {'fecha_desde': fechaDesde ?? '', 'aviso_antelacion': aviso},
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Msg.of('guardado_en_telefono')),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Widget _buildStartTimeCard() {
    final label = Task.startTimeLabel(_task.fechaDesde);
    if (label == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.schedule),
          title: const Text('Hora de inicio'),
          subtitle: const Text('Sin hora. Ponle una para recibir un aviso en el teléfono.'),
          trailing: const Icon(Icons.add_alarm),
          onTap: _pickStartTime,
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: _pickStartTime,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Hora de inicio: $label',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Cambiar la hora',
                  onPressed: _pickStartTime,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Quitar la hora (y el aviso)',
                  onPressed: _clearStartTime,
                ),
              ],
            ),
            Row(
              children: [
                Icon(
                  _task.avisoAntelacion == 'no'
                      ? Icons.notifications_off
                      : Icons.notifications_active,
                  size: 20,
                  color: Colors.grey,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: DropdownButton<String>(
                    value: _task.avisoAntelacion,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final entry in _avisoLabels.entries)
                        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                    ],
                    onChanged: _changeAviso,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Se llama al intentar salir de la pantalla (botón atrás, gesto del
  /// sistema, flecha del AppBar...). Si el nombre o la descripción se
  /// han editado y no se han guardado todavía (no se pulsó "Guardar"),
  /// los guarda automáticamente antes de dejar salir, para que ningún
  /// cambio se pierda ni se quede sin reflejar en Odoo/la lista.
  Future<void> _saveAndPop() async {
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    final hasUnsavedChanges = name != _task.name || description != (_task.description ?? '');

    if (hasUnsavedChanges && name.isNotEmpty && !_isSaving) {
      await _saveTask();
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  // Mostrar opciones para adjuntar archivos
  void _showAttachOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Toma la foto ahora'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Elige una del album del teléfono'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: const Text('Adjuntar archivo (PDF, documentos...)'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFile();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Seleccionar imagen (cámara: una sola; galería: varias a la vez)
  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final List<XFile> images = await _imagePicker.pickMultiImage();
        if (images.isEmpty) return;

        for (final image in images) {
          if (!mounted) return;
          await _uploadFile(await image.readAsBytes(), image.name);
        }
      } else {
        // La cámara solo puede tomar una foto por acción.
        final XFile? image = await _imagePicker.pickImage(source: source);
        if (image == null) return;

        await _uploadFile(await image.readAsBytes(), image.name);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Cachis! Error al seleccionar imagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Seleccionar archivo genérico (PDF, documentos, etc.), uno o varios
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final validFiles = result.files.where((f) => f.bytes != null).toList();
      if (validFiles.isEmpty) return;

      if (!mounted) return;

      final existingNames = _attachments.map((a) => a.name.toLowerCase()).toSet();
      final confirmedFiles = await _showFilesReviewDialog(
        pickedFiles: validFiles,
        existingNamesLowercase: existingNames,
      );

      if (confirmedFiles == null || confirmedFiles.isEmpty) return;

      for (final file in confirmedFiles) {
        if (!mounted) return;
        await _uploadFile(file.bytes!, file.name);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Cachis! Error al seleccionar archivo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Muestra una lista propia (con casillas de buen contraste) de los
  /// archivos elegidos, marcando los que coincidan en nombre con un
  /// adjunto que ya tenga esta tarea, para no duplicar sin querer.
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
                              'Ya existe aquí',
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

  // Subir archivo a Odoo (o guardarlo localmente si no hay conexión)
  Future<void> _uploadFile(Uint8List bytes, String fileName) async {
    UsageLog.action('Adjunta un archivo a una tarea', detail: fileName);
    // Mostrar indicador de carga
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    final hasConnection = await _syncService.checkConnectivity();

    if (!mounted) return;

    if (hasConnection) {
      // Hay conexión: subir directamente a Odoo
      final result = await _odooService.uploadAttachment(
        taskId: _task.id,
        fileName: fileName,
        bytes: bytes,
      );

      if (!mounted) return;
      Navigator.pop(context); // Cerrar indicador

      if (result['success'] == true) {
        // Sincronizar adjuntos para actualizar la base de datos local
        await _syncService.syncAttachments(_task.id);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Archivo adjuntado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        _loadTaskData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? '¡Cachis! Error al subir archivo'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else if (kIsWeb) {
      // En el navegador no hay disco local donde guardar la cola de
      // subidas pendientes: sin conexión, simplemente no se puede
      // adjuntar todavía.
      if (!mounted) return;
      Navigator.pop(context); // Cerrar indicador
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Msg.of('sin_cobertura')),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      // No hay conexión: guardar localmente
      print('📴 _uploadFile: Sin conexión, guardando archivo en tu teléfono...');

      try {
        // Copiar el archivo al almacenamiento de la app
        final appDir = await getApplicationDocumentsDirectory();
        final attachmentsDir = Directory('${appDir.path}/attachments');

        if (!await attachmentsDir.exists()) {
          await attachmentsDir.create(recursive: true);
        }

        // Generar un nombre único para el archivo local
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final localFileName = '${timestamp}_$fileName';
        final localFilePath = '${attachmentsDir.path}/$localFileName';

        // Escribir los bytes ya recibidos al almacenamiento de la app
        await File(localFilePath).writeAsBytes(bytes);
        print('📴 _uploadFile: Archivo copiado a $localFilePath');

        // Guardar metadata en la base de datos local
        await _localDb.saveOfflineAttachment(
          taskId: _task.id,
          fileName: fileName,
          filePath: localFilePath,
          fileSize: bytes.length,
        );

        print('📴 _uploadFile: Datos guardados en tu teléfono');

        if (!mounted) return;
        Navigator.pop(context); // Cerrar indicador

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Archivo guardado en tu teléfono. Lo subiré cuando haya conexión.'),
            backgroundColor: Colors.orange,
          ),
        );
        _loadTaskData();
      } catch (e) {
        print('❌ _uploadFile: Error al guardar archivo localmente: $e');

        if (!mounted) return;
        Navigator.pop(context); // Cerrar indicador

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Cachis! Error al guardar archivo localmente: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Borrar un adjunto
  Future<void> _deleteAttachment(Attachment attachment) async {
    UsageLog.action('Borra un adjunto de una tarea', detail: attachment.name);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar adjunto'),
        content: Text('¿Seguro que quieres borrar "${attachment.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final result = await _odooService.deleteAttachment(attachment.id);

    if (!mounted) return;

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adjunto borrado'),
          backgroundColor: Colors.green,
        ),
      );
      _loadTaskData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? '¡Cachis! Error al borrar adjunto'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Abrir/descargar un adjunto
  Future<void> _openAttachment(Attachment attachment) async {
    UsageLog.action('Abre un adjunto de una tarea', detail: attachment.name);
    // Mostrar indicador de carga
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Descargar el archivo desde Odoo
      final result = await _odooService.downloadAttachment(attachment.id);

      if (!mounted) return;

      if (result['success'] == true) {
        final List<dynamic> records = result['result'] as List<dynamic>;
        if (records.isEmpty) {
          if (mounted) {
            Navigator.pop(context); // Cerrar indicador
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Ya lo siento. No puedo descargar el archivo'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        final record = records[0] as Map<String, dynamic>;
        final String? base64Data = record['datas'] as String?;

        if (base64Data == null || base64Data.isEmpty) {
          if (mounted) {
            Navigator.pop(context); // Cerrar indicador
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('El archivo está vacío'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        // Decodificar base64
        final bytes = base64Decode(base64Data);

        if (kIsWeb) {
          Navigator.pop(context); // Cerrar indicador
          final opened = await openBytesOnWeb(bytes, attachment.name);
          if (!opened && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('¡Cachis! No puedo abrir el archivo'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        // Obtener directorio temporal
        final tempDir = await getTemporaryDirectory();

        if (!mounted) return;

        final filePath = '${tempDir.path}/${attachment.name}';

        // Escribir el archivo en el almacenamiento temporal
        final file = File(filePath);
        await file.writeAsBytes(bytes);

        if (!mounted) return;

        Navigator.pop(context); // Cerrar indicador

        // Abrir el archivo con la aplicación correspondiente
        final openResult = await OpenFilex.open(filePath);

        if (!mounted) return;

        if (openResult.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('¡Cachis! No puedo abrir el archivo: ${openResult.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        if (mounted) {
          Navigator.pop(context); // Cerrar indicador
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? '¡Cachis! Error al descargar el archivo'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Cerrar indicador
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Cachis! Error al abrir el archivo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // canPop en false intercepta el intento de salir (atrás del
      // sistema, gesto, flecha del AppBar) para poder guardar primero
      // si hace falta; _saveAndPop hace el pop real después.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _saveAndPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Detalle de tarea'),
        ),
        body: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildContent(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _isSaving ? null : _saveTask,
          icon: _isSaving
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Icon(Icons.save),
          label: const Text('Guardar'),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadTaskData,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Etapa: banner de una sola línea, arriba del todo (fuera del
        // scroll, siempre visible).
        if (_task.stageName != null)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.flag, size: 18, color: Theme.of(context).colorScheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Etapa → ${_task.stageName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Nombre de la tarea: fijo, fuera del scroll, para que nunca
        // quede oculto bajo el banner de la etapa si la descripción es
        // larga y hay que desplazarse para leerla.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: MicTextField(
            controller: _nameController,
            // Antes era de una sola línea y el "intro" del teclado no
            // dejaba hacer un salto de línea en nombres largos. Ahora
            // crece hacia abajo según haga falta.
            maxLines: null,
            minLines: 1,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              labelText: 'Nombre de la tarea',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.title),
            ),
          ),
        ),

        // Descripción (con más espacio), fecha límite y adjuntos: en
        // scroll aparte, ya que esto sí puede ser largo.
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hora de inicio (y aviso en el teléfono): arriba, a la
                // vista, antes de la descripción (que puede ser larga).
                _buildStartTimeCard(),
                const SizedBox(height: 12),

                // Descripción: más espacio por defecto que antes, y los
                // botones de escuchar/dictar van arriba del campo (no
                // incrustados dentro) para no quitarle espacio al texto.
                // Se quita también el icono de la izquierda (era solo
                // decorativo, no hacía falta para poder editar).
                MicTextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 14,
                  minLines: 10,
                  iconsAbove: true,
                  iconsAboveLeadingOffset: 22,
                ),
                const SizedBox(height: 16),

                if (_task.deadline != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.calendar_today),
                      title: const Text('Fecha límite'),
                      subtitle: Text(_task.deadline!),
                    ),
                  ),

                const SizedBox(height: 24),

                // Archivos adjuntos: última sección del scroll, así queda
                // "abajo del todo" del contenido sin pelearse con el
                // teclado ni forzar alturas fijas. El botón de adjuntar
                // vive aquí, a la izquierda del título, en vez de arriba
                // del todo en el AppBar.
                if (_attachments.isEmpty)
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.attach_file),
                        tooltip: 'Adjuntar archivo',
                        onPressed: _showAttachOptions,
                      ),
                      const Text(
                        'Archivos adjuntos',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.attach_file),
                        tooltip: 'Adjuntar archivo',
                        onPressed: _showAttachOptions,
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFA7C7E7), // azul pastel
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Archivos adjuntos',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),

                if (_attachments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No hay archivos adjuntos',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _attachments.length,
                    itemBuilder: (context, index) {
                      final attachment = _attachments[index];
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            attachment.mimeType?.startsWith('image/') == true
                                ? Icons.image
                                : attachment.mimeType == 'application/pdf'
                                ? Icons.picture_as_pdf
                                : Icons.insert_drive_file,
                            color: Colors.blue,
                          ),
                          title: Text(attachment.name),
                          subtitle: Text(
                            '${attachment.formattedSize} • ${attachment.createDate ?? ""}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteAttachment(attachment),
                          ),
                          onTap: () => _openAttachment(attachment),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}