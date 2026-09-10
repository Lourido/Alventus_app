class Task {
  final int id;
  final String name;
  final String? description;
  final int projectId;
  final String? stageName;
  final String? deadline;
  final String priority;
  final String? fechaDesde;
  final String? fechaHasta;

  Task({
    required this.id,
    required this.name,
    this.description,
    required this.projectId,
    this.stageName,
    this.deadline,
    this.priority = '0',
    this.fechaDesde,
    this.fechaHasta,
  });

  static String? _getString(dynamic value) {
    if (value == null || value == false) return null;
    return value.toString();
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    final stageId = json['stage_id'];

    return Task(
      id: json['id'] as int? ?? 0,
      name: json['name']?.toString() ?? '',
      description: _getString(json['description']),
      projectId: json['project_id'] is List ? json['project_id'][0] as int : 0,
      stageName: stageId is List && stageId.length > 1 ? stageId[1].toString() : null,
      deadline: _getString(json['date_deadline']),
      priority: json['priority']?.toString() ?? '0',
      fechaDesde: _getString(json['fecha_desde']),
      fechaHasta: _getString(json['fecha_hasta']),
    );
  }

  /// Devuelve la hora de inicio formateada (ej: "09:30")
  String get horaInicio {
    if (fechaDesde == null) return '';
    try {
      // El formato que viene de Odoo es "2024-01-01 09:30:00"
      final timePart = fechaDesde!.split(' ');
      if (timePart.length > 1) {
        final hora = timePart[1].substring(0, 5); // "09:30"
        return hora;
      }
    } catch (_) {}
    return '';
  }

  /// Devuelve la fecha formateada (ej: "01/01/2024")
  String get fechaFormateada {
    if (fechaDesde == null) return '';
    try {
      final datePart = fechaDesde!.split(' ')[0]; // "2024-01-01"
      final parts = datePart.split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}/${parts[0]}';
      }
    } catch (_) {}
    return '';
  }
}