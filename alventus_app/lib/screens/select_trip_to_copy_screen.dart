import 'package:flutter/material.dart';
import '../services/odoo_service.dart';
import '../services/local_database_service.dart';
import '../services/sync_service.dart';
import '../models/project.dart';
import 'project_overview_screen.dart';

class SelectTripToCopyScreen extends StatefulWidget {
  const SelectTripToCopyScreen({super.key});

  @override
  State<SelectTripToCopyScreen> createState() => _SelectTripToCopyScreenState();
}

class _SelectTripToCopyScreenState extends State<SelectTripToCopyScreen> {
  final OdooService _odooService = OdooService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final SyncService _syncService = SyncService();

  List<Project> _projects = [];
  bool _isLoading = true;
  bool _isOffline = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final hasConnection = await _syncService.checkConnectivity();

    if (!mounted) return;

    if (hasConnection) {
      await _syncService.syncProjects();
    }

    final localProjects = await _localDb.getProjects();

    if (!mounted) return;

    setState(() {
      _isOffline = !hasConnection;
      _projects = localProjects.map((row) {
        return Project(
          id: row['id'] as int,
          name: row['name'] as String? ?? '',
          description: row['description'] as String?,
          userName: row['user_name'] as String?,
          partnerName: row['partner_name'] as String?,
          dateStart: row['date_start'] as String?,
          dateEnd: row['date_end'] as String?,
          taskCount: row['task_count'] as int? ?? 0,
        );
      }).toList();
      _isLoading = false;
    });
  }

  // Mostrar diálogo para elegir el nombre y la fecha de inicio del nuevo viaje
  void _showStartDateDialog(Project project) async {
    final hasConnection = await _syncService.checkConnectivity();
    if (!hasConnection) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se necesita conexión a internet para duplicar un viaje'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    DateTime? selectedDate;
    final nameController = TextEditingController(text: '${project.name} (copia)');

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Copiar "${project.name}"'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del nuevo viaje',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Selecciona la fecha de inicio del nuevo viaje:'),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now().add(const Duration(days: 1)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 730)),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            selectedDate = picked;
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fecha de inicio',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          selectedDate != null
                              ? '${selectedDate!.day.toString().padLeft(2, '0')}/${selectedDate!.month.toString().padLeft(2, '0')}/${selectedDate!.year}'
                              : 'Seleccionar fecha',
                        ),
                      ),
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
                  onPressed: selectedDate == null || nameController.text.trim().isEmpty
                      ? null
                      : () {
                    Navigator.pop(dialogContext);
                    _copyProject(project, selectedDate!, nameController.text.trim());
                  },
                  child: const Text('Copiar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Copiar el proyecto
  Future<void> _copyProject(Project project, DateTime startDate, String newName) async {
    // Mostrar indicador de carga
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Copiando viaje...'),
          ],
        ),
      ),
    );

    final result = await _odooService.copyProject(
      sourceProjectId: project.id,
      sourceProjectName: project.name,
      newStartDate: startDate,
      newName: newName,
    );

    // Si la copia fue bien, sincronizamos ya las tareas del viaje nuevo y
    // también la lista de proyectos: es syncProjects() quien calcula y
    // guarda localmente el rango de fechas y el número de días reales, a
    // partir de las etapas ya desplazadas a la fecha de inicio elegida.
    // Sin esto, el viaje nuevo se vería con fechas y días en blanco hasta
    // la próxima sincronización general (por ejemplo, al reabrir la
    // lista de viajes).
    Project? newProject;
    if (result['success'] == true) {
      final newProjectId = result['project_id'] as int?;
      if (newProjectId != null) {
        await _syncService.syncTasks(newProjectId);
        await _syncService.syncProjects();

        final rows = await _localDb.getProjects();
        Map<String, dynamic>? row;
        for (final r in rows) {
          if (r['id'] == newProjectId) {
            row = r;
            break;
          }
        }
        if (row != null) {
          newProject = Project(
            id: row['id'] as int,
            name: row['name'] as String? ?? '',
            description: row['description'] as String?,
            userName: row['user_name'] as String?,
            partnerName: row['partner_name'] as String?,
            dateStart: row['date_start'] as String?,
            dateEnd: row['date_end'] as String?,
            taskCount: row['task_count'] as int? ?? 0,
          );
        }
      }
    }

    if (!mounted) return;
    Navigator.pop(context); // Cerrar indicador

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Viaje "${result['project_name']}" creado correctamente'),
          backgroundColor: Colors.green,
        ),
      );

      if (newProject != null) {
        // Ir directamente a la pantalla del viaje recién copiado (como ya
        // se hace al crear uno "desde cero"), con las fechas y el número
        // de días ya recalculados a partir de sus etapas, en vez de solo
        // volver a la pantalla anterior.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => ProjectOverviewScreen(project: newProject!)),
        );
      } else {
        // Respaldo por si algo falló al releer el proyecto recién creado:
        // comportamiento anterior, volver a la pantalla anterior.
        Navigator.pop(context);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Error al copiar el viaje'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Elegir viaje a copiar'),
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
              onPressed: _loadProjects,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_projects.isEmpty) {
      return const Center(
        child: Text('No hay viajes disponibles para copiar'),
      );
    }

    return ListView.builder(
      itemCount: _projects.length,
      itemBuilder: (context, index) {
        final project = _projects[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF1A3A5C),
              child: Text(
                project.name.isNotEmpty ? project.name[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(
              project.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: project.dateStart != null
                ? Text('Inicio: ${project.dateStart}')
                : null,
            trailing: const Icon(Icons.copy),
            onTap: () => _showStartDateDialog(project),
          ),
        );
      },
    );
  }
}
