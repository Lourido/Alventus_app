import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/odoo_service.dart';
import '../services/local_database_service.dart';
import '../services/sync_service.dart';
import '../models/project.dart';

class ShareTripScreen extends StatefulWidget {
  const ShareTripScreen({super.key});

  @override
  State<ShareTripScreen> createState() => _ShareTripScreenState();
}

class _ShareTripScreenState extends State<ShareTripScreen> {
  final OdooService _odooService = OdooService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final SyncService _syncService = SyncService();

  List<Project> _projects = [];
  List<Map<String, dynamic>> _guides = [];

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final hasConnection = await _syncService.checkConnectivity();

    if (!hasConnection) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Se necesita conexión a internet para compartir un viaje.';
      });
      return;
    }

    await _syncService.syncProjects();
    final localProjects = await _localDb.getProjects();

    final guidesResult = await _odooService.fetchGuideUsers();

    if (!mounted) return;

    if (guidesResult['success'] != true) {
      setState(() {
        _isLoading = false;
        _errorMessage = guidesResult['error']?.toString() ??
            'No se pudo cargar la lista de guías';
      });
      return;
    }

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
      _guides = (guidesResult['result'] as List<dynamic>).cast<Map<String, dynamic>>();
      _isLoading = false;
    });
  }

  // Diálogo para elegir guía, nombre y fecha de inicio del viaje compartido
  void _showShareDialog(Project project) async {
    if (_guides.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay usuarios en el grupo "Guías" con quien compartir'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    DateTime? selectedDate;
    Map<String, dynamic>? selectedGuide;
    final nameController = TextEditingController(text: project.name);

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canConfirm = selectedDate != null &&
                selectedGuide != null &&
                nameController.text.trim().isNotEmpty;

            return AlertDialog(
              title: Text('Compartir "${project.name}"'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('¿Con qué guía quieres compartir este viaje?'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<Map<String, dynamic>>(
                      initialValue: selectedGuide,
                      decoration: const InputDecoration(
                        labelText: 'Guía',
                        border: OutlineInputBorder(),
                      ),
                      items: _guides.map((guide) {
                        return DropdownMenuItem(
                          value: guide,
                          child: Text(guide['name']?.toString() ?? ''),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedGuide = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del viaje compartido',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 16),
                    const Text('Fecha de inicio del viaje compartido:'),
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
                          setDialogState(() => selectedDate = picked);
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
                  onPressed: canConfirm
                      ? () {
                          Navigator.pop(dialogContext);
                          _shareProject(
                            project: project,
                            guide: selectedGuide!,
                            startDate: selectedDate!,
                            newName: nameController.text.trim(),
                          );
                        }
                      : null,
                  child: const Text('Compartir'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _shareProject({
    required Project project,
    required Map<String, dynamic> guide,
    required DateTime startDate,
    required String newName,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Compartiendo viaje...'),
          ],
        ),
      ),
    );

    // 1. Duplicar el viaje (misma acción que "Crear viaje / A partir de otro viaje")
    final copyResult = await _odooService.copyProject(
      sourceProjectId: project.id,
      sourceProjectName: project.name,
      newStartDate: startDate,
      newName: newName,
    );

    if (copyResult['success'] != true) {
      if (!mounted) return;
      Navigator.pop(context); // cerrar indicador
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(copyResult['error']?.toString() ?? 'Error al compartir el viaje'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final newProjectId = copyResult['project_id'] as int;

    // 2. Asignar al guía elegido como gestor del proyecto, para que le
    // aparezca a él al entrar en la app.
    final managerResult = await _odooService.updateProjectManager(
      projectId: newProjectId,
      userId: guide['id'] as int,
    );

    // 3. Sincronizar tareas y proyectos localmente.
    await _syncService.syncTasks(newProjectId);
    await _syncService.syncProjects();

    if (!mounted) return;
    Navigator.pop(context); // cerrar indicador

    if (managerResult['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El viaje se copió, pero no se pudo asignar el guía como gestor'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _showSuccessDialog(guideName: guide['name']?.toString() ?? 'el guía', tripName: newName);
  }

  void _showSuccessDialog({required String guideName, required String tripName}) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Viaje compartido'),
        content: Text('El viaje "$tripName" ya está disponible para $guideName.'
            '\n\n¿Quieres avisarle por WhatsApp?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pop(context); // volver a la pantalla anterior
            },
            child: const Text('No, gracias'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _openWhatsApp(guideName: guideName, tripName: tripName);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Avisar por WhatsApp'),
          ),
        ],
      ),
    );
  }

  Future<void> _openWhatsApp({required String guideName, required String tripName}) async {
    final message =
        'Hola $guideName, ya tienes disponible el viaje "$tripName" en la app.';
    final uri = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(message)}');

    final canOpen = await canLaunchUrl(uri);

    if (!mounted) return;

    if (canOpen) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WhatsApp no está instalado en este teléfono'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compartir viaje')),
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
              ElevatedButton(onPressed: _loadData, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    if (_projects.isEmpty) {
      return const Center(child: Text('No hay viajes disponibles para compartir'));
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
            trailing: const Icon(Icons.share),
            onTap: () => _showShareDialog(project),
          ),
        );
      },
    );
  }
}
