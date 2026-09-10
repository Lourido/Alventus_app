import 'package:flutter/material.dart';
import '../services/odoo_service.dart';
import '../services/local_database_service.dart';
import '../services/sync_service.dart';
import '../models/project.dart';

class RemoveTripScreen extends StatefulWidget {
  const RemoveTripScreen({super.key});

  @override
  State<RemoveTripScreen> createState() => _RemoveTripScreenState();
}

class _RemoveTripScreenState extends State<RemoveTripScreen> {
  final OdooService _odooService = OdooService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final SyncService _syncService = SyncService();

  List<Project> _projects = [];
  bool _isLoading = true;
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

    if (!hasConnection) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Se necesita conexión a internet para quitar un viaje.';
      });
      return;
    }

    await _syncService.syncProjects();
    final localProjects = await _localDb.getProjects();

    if (!mounted) return;

    setState(() {
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

  Future<void> _confirmRemove(Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quitar viaje'),
        content: Text(
          '¿Seguro que quieres quitar el viaje "${project.name}"?\n\n'
          'No se borrará de Odoo: se marcará como quitado y podrás '
          'recuperarlo más tarde desde "Recuperar viaje".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Quitando viaje...'),
          ],
        ),
      ),
    );

    final result = await _odooService.markProjectAsRemoved(projectId: project.id);

    // Sincroniza la copia local para reflejar el cambio de responsable.
    await _syncService.syncProjects();

    if (!mounted) return;
    Navigator.pop(context); // cerrar indicador

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Viaje "${project.name}" quitado correctamente'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context); // volver a la pantalla anterior
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error']?.toString() ?? 'Error al quitar el viaje'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quitar viaje')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
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
              ElevatedButton(onPressed: _loadProjects, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    if (_projects.isEmpty) {
      return const Center(child: Text('No hay viajes disponibles'));
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
            title: Text(project.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: project.dateStart != null ? Text('Inicio: ${project.dateStart}') : null,
            trailing: const Icon(Icons.delete_outline, color: Colors.red),
            onTap: () => _confirmRemove(project),
          ),
        );
      },
    );
  }
}
