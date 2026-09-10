class Project {
  final int id;
  final String name;
  final String? description;
  final String? userName;
  final String? partnerName;
  final String? dateStart;
  final String? dateEnd;
  final int taskCount;

  /// El constructor normal (usado también al reconstruir el proyecto desde
  /// la base de datos local) limpia automáticamente los campos de texto:
  /// si vienen vacíos o son el string literal "false" (que es lo que Odoo
  /// devuelve para campos de texto vacíos, y que en algún punto de la
  /// sincronización se guarda como texto en vez de quedar en null), se
  /// tratan como si no hubiera valor.
  Project({
    required this.id,
    required this.name,
    String? description,
    String? userName,
    String? partnerName,
    String? dateStart,
    String? dateEnd,
    this.taskCount = 0,
  })  : description = _clean(description),
        userName = _clean(userName),
        partnerName = _clean(partnerName),
        dateStart = _clean(dateStart),
        dateEnd = _clean(dateEnd);

  /// Trata null, cadena vacía y el string "false" (en cualquier
  /// mayúsculas/minúsculas) como "sin valor".
  static String? _clean(dynamic value) {
    if (value == null || value == false) return null;
    final s = value.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'false') return null;
    return s;
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    // user_id y partner_id pueden venir como [id, "nombre"] o como false
    final userId = json['user_id'];
    final partnerId = json['partner_id'];

    return Project(
      id: json['id'] as int? ?? 0,
      name: json['name']?.toString() ?? '',
      description: _clean(json['description']),
      userName: userId is List && userId.length > 1 ? userId[1].toString() : null,
      partnerName: partnerId is List && partnerId.length > 1 ? partnerId[1].toString() : null,
      dateStart: _clean(json['date_start']),
      dateEnd: _clean(json['date']),
      taskCount: json['task_count'] as int? ?? 0,
    );
  }
}
