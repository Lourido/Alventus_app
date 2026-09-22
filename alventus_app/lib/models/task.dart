import '../utils/html_text.dart';

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

  /// Cuánto antes de la hora de inicio llega el aviso al teléfono, en
  /// minutos: '0' (a la hora), '15', '30' o '60'. Campo aviso_antelacion
  /// de Odoo.
  final String avisoAntelacion;

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
    String? avisoAntelacion,
  }) : avisoAntelacion = normalizeAviso(avisoAntelacion);

  /// Valores válidos del aviso; cualquier otra cosa (vacío, false de Odoo,
  /// null...) se toma como '0' (a la hora de inicio).
  static const avisoOptions = ['0', '15', '30', '60'];

  static String normalizeAviso(dynamic value) {
    final s = value?.toString() ?? '';
    return avisoOptions.contains(s) ? s : '0';
  }

  /// Hora de inicio de un valor de fecha_desde ("2026-09-23 10:00:00"), o
  /// null si no tiene. Las 00:00 se toman como "sin hora", igual que en el
  /// servidor (una fecha sin hora puesta queda a medianoche, y no se quiere
  /// avisar de madrugada por eso).
  static ({int hour, int minute})? startTimeOf(String? fechaDesde) {
    if (fechaDesde == null || fechaDesde.isEmpty || fechaDesde == 'false') return null;
    try {
      final dt = DateTime.parse(fechaDesde);
      if (dt.hour == 0 && dt.minute == 0) return null;
      return (hour: dt.hour, minute: dt.minute);
    } catch (_) {
      return null;
    }
  }

  /// "10:00", o null si la tarea no tiene hora de inicio.
  static String? startTimeLabel(String? fechaDesde) {
    final t = startTimeOf(fechaDesde);
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  /// Texto corto del aviso ("15 min antes"...), para la lista de tareas.
  static String avisoShortLabel(String aviso) {
    switch (aviso) {
      case '15':
        return 'aviso 15 min antes';
      case '30':
        return 'aviso 30 min antes';
      case '60':
        return 'aviso 1 h antes';
      default:
        return 'aviso a la hora';
    }
  }

  static String? _getString(dynamic value) {
    if (value == null || value == false) return null;
    return value.toString();
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    final stageId = json['stage_id'];

    return Task(
      id: json['id'] as int? ?? 0,
      name: json['name']?.toString() ?? '',
      description: stripHtmlToPlainText(_getString(json['description'])),
      projectId: json['project_id'] is List ? json['project_id'][0] as int : 0,
      stageName: stageId is List && stageId.length > 1 ? stageId[1].toString() : null,
      deadline: _getString(json['date_deadline']),
      priority: json['priority']?.toString() ?? '0',
      fechaDesde: _getString(json['fecha_desde']),
      fechaHasta: _getString(json['fecha_hasta']),
      avisoAntelacion: _getString(json['aviso_antelacion']),
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