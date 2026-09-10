import 'package:flutter/material.dart';
import '../services/odoo_service.dart';
import '../services/local_database_service.dart';
import '../services/sync_service.dart';
import '../models/project.dart';
import '../models/task.dart';
import 'task_detail_screen.dart';
import 'package:alventus_app/widgets/speech/mic_text_field.dart';

class ProjectDetailScreen extends StatefulWidget {
  final Project project;

  const ProjectDetailScreen({super.key, required this.project});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  final OdooService _odooService = OdooService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final SyncService _syncService = SyncService();

  List<Task> _tasks = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Verificar si hay conexión
    final hasConnection = await _syncService.checkConnectivity();

    if (!mounted) return;

    setState(() {
      _isOffline = !hasConnection;
    });

    if (hasConnection) {
      // Hay conexión: sincronizar tareas con Odoo
      await _syncService.syncTasks(widget.project.id);
    }

    // Cargar tareas desde la base de datos local
    final localTasks = await _localDb.getTasks(widget.project.id);

    if (!mounted) return;

    setState(() {
      _tasks = localTasks.map((row) {
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
      }).toList();
      _isLoading = false;
    });
  }

  // Mostrar diálogo para crear una nueva tarea
  void _showCreateTaskDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Nueva tarea'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MicTextField(
                controller: nameController,
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

                final hasConnection = await _syncService.checkConnectivity();

                if (hasConnection) {
                  // Hay conexión: crear directamente en Odoo
                  final result = await _odooService.createTask(
                    projectId: widget.project.id,
                    name: name,
                    description: descController.text.trim().isNotEmpty
                        ? descController.text.trim()
                        : null,
                  );

                  if (!mounted) return;

                  if (result['success'] == true) {
                    // Sincronizar para actualizar la base de datos local
                    await _syncService.syncTasks(widget.project.id);
                    _loadTasks();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(result['error'] ?? 'Error al crear tarea'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } else {
                  // No hay conexión: guardar localmente y añadir a pendientes
                  await _saveTaskLocally(name, descController.text.trim());
                }
              },
              child: const Text('Crear'),
            ),
          ],
        );
      },
    );
  }

  // Guardar tarea localmente cuando no hay conexión
  Future<void> _saveTaskLocally(String name, String? description) async {
    // Generar un ID temporal negativo para la tarea offline
    final tempId = -DateTime.now().millisecondsSinceEpoch;

    // Guardar en la base de datos local
    await _localDb.saveTasks([
      {
        'id': tempId,
        'name': name,
        'description': description,
        'project_id': widget.project.id,
        'stage_name': null,
        'deadline': null,
        'priority': '0',
        'fecha_desde': null,
        'fecha_hasta': null,
      },
    ]);

    // Añadir a la cola de cambios pendientes
    await _localDb.addPendingChange(
      model: 'project.task',
      action: 'create',
      recordId: tempId,
      data: {
        'project_id': widget.project.id.toString(),
        'name': name,
        'description': description ?? '',
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

  // Confirmar antes de borrar una tarea
  void _confirmDeleteTask(Task task) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Borrar tarea'),
          content: Text('¿Seguro que quieres borrar la tarea "${task.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(dialogContext);

                final hasConnection = await _syncService.checkConnectivity();

                if (hasConnection) {
                  // Hay conexión: borrar directamente en Odoo
                  final result = await _odooService.deleteTask(task.id);

                  if (!mounted) return;

                  if (result['success'] == true) {
                    // Borrar de la base de datos local
                    await _localDb.deleteTask(task.id);
                    _loadTasks();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(result['error'] ?? 'Error al borrar tarea'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } else {
                  // No hay conexión: borrar localmente y añadir a pendientes
                  await _localDb.deleteTask(task.id);
                  await _localDb.addPendingChange(
                    model: 'project.task',
                    action: 'delete',
                    recordId: task.id,
                  );

                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tarea borrada localmente. Se sincronizará cuando haya conexión.'),
                      backgroundColor: Colors.orange,
                    ),
                  );

                  _loadTasks();
                }
              },
              child: const Text('Borrar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.name),
        actions: [
          // Indicador de estado de conexión
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Icon(
              _isOffline ? Icons.cloud_off : Icons.cloud_done,
              color: _isOffline ? Colors.orange : Colors.green,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateTaskDialog,
        icon: const Icon(Icons.add),
        label: const Text('Nueva tarea'),
      ),
      body: _buildBody(),
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
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadTasks,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Este viaje no tiene tareas todavía'),
            if (_isOffline)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Modo offline',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView.builder(
        itemCount: _tasks.length,
        itemBuilder: (context, index) {
          final task = _tasks[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: ListTile(
              leading: Icon(
                task.fechaDesde != null ? Icons.event : Icons.radio_button_unchecked,
                color: task.fechaDesde != null ? Colors.blue : Colors.grey,
              ),
              title: Text(task.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (task.fechaDesde != null)
                    Text(
                      '${task.fechaFormateada} • ${task.horaInicio}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.blue,
                      ),
                    ),
                  if (task.stageName != null) Text('Etapa: ${task.stageName}'),
                  if (task.deadline != null) Text('Fecha límite: ${task.deadline}'),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TaskDetailScreen(task: task),
                  ),
                );
              },
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') {
                    _confirmDeleteTask(task);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Borrar'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}