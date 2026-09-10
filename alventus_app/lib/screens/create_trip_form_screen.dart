import 'package:flutter/material.dart';
import '../services/odoo_service.dart';
import '../models/project.dart';
import 'package:alventus_app/widgets/speech/mic_text_field.dart';
import 'stages_screen.dart';

enum CreateTripMode { fromCalendar, fromScratch }

class CreateTripFormScreen extends StatefulWidget {
  final CreateTripMode mode;

  const CreateTripFormScreen({super.key, required this.mode});

  @override
  State<CreateTripFormScreen> createState() => _CreateTripFormScreenState();
}

class _CreateTripFormScreenState extends State<CreateTripFormScreen> {
  final OdooService _odooService = OdooService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _numDaysController = TextEditingController(text: '1');

  DateTime? _dateFrom;
  DateTime? _dateTo;
  bool _isCreating = false;

  bool get _isFromScratch => widget.mode == CreateTripMode.fromScratch;

  String get _title {
    return widget.mode == CreateTripMode.fromCalendar
        ? 'Traer del calendario'
        : 'Crear desde cero';
  }

  String get _nameLabel {
    return widget.mode == CreateTripMode.fromCalendar
        ? 'Nombre del calendario'
        : 'Nombre del viaje';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numDaysController.dispose();
    super.dispose();
  }

  Future<void> _selectDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );

    if (picked != null) {
      setState(() {
        if (isFrom) {
          _dateFrom = picked;
        } else {
          _dateTo = picked;
        }
      });
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Seleccionar fecha';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatDateTimeForOdoo(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} 09:00:00';
  }

  Future<void> _createTrip() async {
    if (!_formKey.currentState!.validate()) return;

    if (_dateFrom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona la fecha de inicio'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isCreating = true;
    });

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
            Text('Creando viaje...'),
          ],
        ),
      ),
    );

    try {
      Project? newProject;

      if (_isFromScratch) {
        newProject = await _createTripFromScratch();
      } else {
        await _createTripFromCalendar();
      }

      if (!mounted) return;
      Navigator.pop(context); // Cerrar indicador

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Viaje "${_nameController.text.trim()}" creado correctamente'),
          backgroundColor: Colors.green,
        ),
      );

      if (_isFromScratch && newProject != null) {
        // Ir directamente a la pantalla de Etapas del viaje recién
        // creado, donde están los botones de reordenar/añadir/borrar
        // etapa, en vez de solo volver a la pantalla anterior.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => StagesScreen(project: newProject!)),
        );
      } else {
        // Modo "Traer del calendario": comportamiento anterior, sin
        // cambios (vuelve a la pantalla anterior).
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Cerrar indicador

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al crear el viaje: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  /// Modo "Desde cero": ejecuta el asistente de Odoo
  /// project.create.with.tasks.wizard, que crea el proyecto y una etapa
  /// por cada día automáticamente. Devuelve un [Project] con los datos
  /// del viaje recién creado, para poder navegar directamente a su
  /// pantalla de Etapas.
  Future<Project> _createTripFromScratch() async {
    final numDays = int.parse(_numDaysController.text.trim());
    final name = _nameController.text.trim();

    final result = await _odooService.createProjectWithTasksWizard(
      name: name,
      startDate: _dateFrom!,
      numDays: numDays,
    );

    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Error al crear el viaje');
    }

    final projectId = result['project_id'] as int;

    // El wizard fija date_start = fecha de inicio y date = fecha de
    // inicio + (num_days - 1), así que lo replicamos aquí para no tener
    // que volver a consultar Odoo justo después de crearlo.
    String isoDate(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final endDate = _dateFrom!.add(Duration(days: numDays - 1));

    return Project(
      id: projectId,
      name: name,
      dateStart: isoDate(_dateFrom!),
      dateEnd: isoDate(endDate),
    );
  }

  /// Modo "Traer del calendario": mantiene la lógica manual anterior
  /// (crea el proyecto y una única etapa/tarea "Antes de salir").
  Future<void> _createTripFromCalendar() async {
    final projectResult = await _odooService.createProject(
      name: _nameController.text.trim(),
      dateStart: _formatDateTimeForOdoo(_dateFrom!),
      dateEnd: _dateTo != null ? _formatDateTimeForOdoo(_dateTo!) : null,
    );

    if (projectResult['success'] != true) {
      throw Exception(projectResult['error'] ?? 'Error al crear el proyecto');
    }

    final projectId = projectResult['project_id'] as int;

    final stageResult = await _odooService.createStage(
      name: 'Día 0',
      sequence: 0,
    );

    int? stageId;
    if (stageResult['success'] == true) {
      stageId = stageResult['stage_id'] as int;
    }

    final oneWeekBefore = _dateFrom!.subtract(const Duration(days: 7));
    final taskFechaDesde = _formatDateTimeForOdoo(oneWeekBefore);
    final taskFechaHasta = _formatDateTimeForOdoo(oneWeekBefore);

    await _odooService.createTaskWithDates(
      projectId: projectId,
      name: 'Antes de salir',
      stageId: stageId,
      fechaDesde: taskFechaDesde,
      fechaHasta: taskFechaHasta,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Campo de nombre
                MicTextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: _nameLabel,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.label),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Introduce un nombre';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Fecha de inicio (se usa en ambos modos)
                InkWell(
                  onTap: () => _selectDate(isFrom: true),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: _isFromScratch ? 'Fecha de inicio' : 'Fecha desde',
                      border: const OutlineInputBorder(),
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    child: Text(_formatDate(_dateFrom)),
                  ),
                ),
                const SizedBox(height: 16),

                if (_isFromScratch) ...[
                  // Modo "Desde cero": número de días (el wizard calcula
                  // la fecha final y crea una etapa por cada día).
                  TextFormField(
                    controller: _numDaysController,
                    decoration: const InputDecoration(
                      labelText: 'Número de días',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_view_day),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final n = int.tryParse(value?.trim() ?? '');
                      if (n == null || n <= 0) {
                        return 'Introduce un número de días válido';
                      }
                      return null;
                    },
                  ),
                ] else ...[
                  // Modo "Traer del calendario": fecha hasta, como antes.
                  InkWell(
                    onTap: () => _selectDate(isFrom: false),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha hasta',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(_formatDate(_dateTo)),
                    ),
                  ),
                ],
                const SizedBox(height: 32),

                // Botón crear
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isCreating ? null : _createTrip,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A3A5C),
                      foregroundColor: Colors.white,
                    ),
                    child: _isCreating
                        ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Text(
                      'Crear viaje',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
