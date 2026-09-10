import 'package:flutter/material.dart';
import '../services/local_database_service.dart';
import '../services/sync_service.dart';
import '../models/project.dart';
import 'project_overview_screen.dart';

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  //final OdooService _odooService = OdooService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final SyncService _syncService = SyncService();

  List<Project> _projects = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isOffline = false;

  // Mapa para almacenar el contador de tareas por proyecto
 // final Map<int, int> _taskCounts = {};

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

    // Verificar si hay conexión
    final hasConnection = await _syncService.checkConnectivity();

    if (!mounted) return;

    if (hasConnection) {
      // Hay conexión: intentar sincronizar con Odoo
      await _syncService.syncProjects();

      // Sincroniza también las tareas de cada viaje, para que el resumen
      // de "X días" y el rango de fechas se vea siempre actualizado sin
      // depender de haber entrado antes en el detalle de cada viaje uno
      // por uno (por ejemplo, tras recrear la base de datos de Odoo, o
      // simplemente la primera vez que se abre la app).
      final syncedProjects = await _localDb.getProjects();
      for (final row in syncedProjects) {
        final projectId = row['id'] as int;
        await _syncService.syncTasks(projectId);
      }
    }

    // Cargar proyectos desde la base de datos local
    // (ya sea porque se sincronizaron o porque son los últimos que había)
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

    // Cargar el contador de tareas para cada proyecto
    // _loadTaskCounts(_projects);
  }

  // Cargar el número de tareas de cada proyecto desde la base de datos local
 /*Future<void> _loadTaskCounts(List<Project> projects) async {
    for (final project in projects) {
      // Intentar contar desde la base de datos local primero
      final tasks = await _localDb.getTasks(project.id);

      if (!mounted) return;

      setState(() {
        _taskCounts[project.id] = tasks.length;
      });

      // Si hay conexión, también actualizar el contador desde Odoo
      if (_syncService.isOnline) {
        final result = await _odooService.countTasks(project.id);

        if (!mounted) return;

        if (result['success'] == true) {
          setState(() {
            _taskCounts[project.id] = result['result'] as int;
          });
        }
      }
    }
  } */

  // Calcula el número de días y el rango de fechas directamente a partir
  // de los campos del propio proyecto (dateStart/dateEnd), sin depender
  // de las tareas ya sincronizadas localmente. No es asíncrono: ya
  // tenemos estos datos en memoria en el objeto Project.
  _ProjectInfo _getProjectInfo(Project project) {
    final start = project.dateStart;
    final end = project.dateEnd;

    if (start == null || end == null) {
      return _ProjectInfo(dayCount: 0, dateRange: '');
    }

    try {
      final startDate = DateTime.parse(start);
      final endDate = DateTime.parse(end);
      final dayCount = endDate.difference(startDate).inDays + 1;

      String fmt(DateTime d) =>
          '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

      final startStr = fmt(startDate);
      final endStr = fmt(endDate);
      final dateRange = startStr == endStr ? startStr : '$startStr - $endStr';

      return _ProjectInfo(dayCount: dayCount, dateRange: dateRange);
    } catch (_) {
      return _ProjectInfo(dayCount: 0, dateRange: '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Viajes'),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('No hay viajes disponibles'),
            if (_isOffline)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Modo offline: mostrando datos guardados',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProjects,
      child: ListView.builder(
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
              subtitle: Builder(
                builder: (context) {
                  final info = _getProjectInfo(project);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (info.dayCount > 0)
                        Text('${info.dayCount} ${info.dayCount == 1 ? 'día' : 'días'}'),
                      if (info.dateRange.isNotEmpty)
                        Text(
                          info.dateRange,
                          style: const TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  );
                },
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProjectOverviewScreen(project: project),
                  ),
                ).then((_) {
                  // Al volver de la pantalla del viaje, recargamos por si
                  // algo cambió allí (nombre, tareas, etc.), para no
                  // depender de que le toque sincronizar por su cuenta.
                  if (mounted) _loadProjects();
                });
              },
            ),
          );
        },
      ),
    );
  }
}
class _ProjectInfo {
  final int dayCount;
  final String dateRange;

  _ProjectInfo({required this.dayCount, required this.dateRange});
}
