class Partner {
  final int id;
  final String name;
  final String? email;
  final String? phone;
  final String? city;
  final String? comment;

  Partner({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.city,
    this.comment,
  });

  /// Método auxiliar para convertir valores que pueden ser:
  /// - null
  /// - false (Odoo devuelve false cuando un campo está vacío)
  /// - un String real
  static String? _getString(dynamic value) {
    if (value == null || value == false) return null;
    return value.toString();
  }

  // Convierte un JSON de Odoo en un objeto Partner
  factory Partner.fromJson(Map<String, dynamic> json) {
    return Partner(
      id: json['id'] as int? ?? 0,
      name: json['name']?.toString() ?? '',
      email: _getString(json['email']),
      phone: _getString(json['phone']),
      city: _getString(json['city']),
      comment: _getString(json['comment']),
    );
  }
}