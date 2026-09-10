import 'package:flutter/material.dart';
import '../services/odoo_service.dart';
import '../services/sync_service.dart';
import '../models/project.dart';

/// Lista los viajes marcados como "quitados" (invisible=true) y permite
/// recuperarlos (invisible=false). Consulta directamente a Odoo, ya que
/// la base de datos local solo guarda los viajes visibles.
class RecoverTripScreen extends StatefulWidget {
  const RecoverTripScreen({super.key});

  @override
  State<RecoverTripScreen> createState() => _RecoverTripScreenState();
}

class _RecoverTripScreenState extends State<RecoverTripScreen> {
  final OdooService _odooService = OdooService();
  final SyncService _syncService = SyncService();

  List<Project> _removedProjects = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRemovedProjects();
  }

  Future<void> _loadRemovedProjects() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final hasConnection = await _syncService.checkConnectivity();

    if (!hasConnection) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Se necesita conexión a internet para ver los viajes quitados.';
      });
      return;
    }

    final result = await _odooService.fetchProjects(
      limit: 1000,
      invisible: true,
      userId: _odooService.uid,
    );

    if (!mounted) return;

    if (result['success'] != true) {
      setState(() {
        _isLoading = false;
        _errorMessage = result['error']?.toString() ?? 'No se pudieron cargar los viajes quitados';
      });
      return;
    }

    final records = (result['result'] as List<dynamic>).cast<Map<String, dynamic>>();

    setState(() {
      _removedProjects = records.map((json) => Project.fromJson(json)).toList();
      _isLoading = false;
    });
  }

  Future<void> _confirmRestore(Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recuperar viaje'),
        content: Text('¿Quieres recuperar el viaje "${project.name}"? Volverá a verse en el resto de la app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Recuperar'),
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
            Text('Recuperando viaje...'),
          ],
        ),
      ),
    );

    final result = await _odooService.restoreProject(projectId: project.id);

    // Sincroniza la copia local para que el viaje recuperado vuelva a
    // aparecer en el resto de pantallas.
    await _syncService.syncProjects();

    if (!mounted) return;
    Navigator.pop(context); // cerrar indicador

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Viaje "${project.name}" recuperado correctamente'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _removedProjects.removeWhere((p) => p.id == project.id);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error']?.toString() ?? 'Error al recuperar el viaje'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar viaje')),
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
              ElevatedButton(onPressed: _loadRemovedProjects, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    if (_removedProjects.isEmpty) {
      return const Center(child: Text('No hay viajes quitados para recuperar'));
    }

    return ListView.builder(
      itemCount: _removedProjects.length,
      itemBuilder: (context, index) {
        final project = _removedProjects[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFFFDAC1),
              child: Text(
                project.name.isNotEmpty ? project.name[0].toUpperCase() : '?',
                style: const TextStyle(color: Color(0xFF33475B)),
              ),
            ),
            title: Text(project.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: project.dateStart != null ? Text('Inicio: ${project.dateStart}') : null,
            trailing: const Icon(Icons.restore, color: Colors.green),
            onTap: () => _confirmRestore(project),
          ),
        );
      },
    );
  }
}
