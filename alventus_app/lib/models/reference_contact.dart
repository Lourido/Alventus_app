class ReferenceContact {
  final int id;
  final String name;
  final String? email;
  final String? phone;
  final String? street;
  final String? street2;
  final String? zip;
  final String? city;
  final int? countryId;
  final String? countryName;
  final String? comment;

  ReferenceContact({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.street,
    this.street2,
    this.zip,
    this.city,
    this.countryId,
    this.countryName,
    this.comment,
  });

  static String? _str(dynamic value) {
    if (value == null || value == false) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Vale tanto para lo que llega de Odoo (country_id = [id, nombre]) como
  /// para una fila de la base local (country_id y country_name sueltos).
  factory ReferenceContact.fromJson(Map<String, dynamic> json) {
    final country = json['country_id'];
    int? countryId;
    String? countryName = _str(json['country_name']);
    if (country is List && country.length > 1) {
      countryId = country[0] as int?;
      countryName = _str(country[1]);
    } else if (country is int) {
      countryId = country;
    }
    return ReferenceContact(
      id: json['id'] as int,
      name: _str(json['name']) ?? 'Sin nombre',
      email: _str(json['email']),
      phone: _str(json['phone']),
      street: _str(json['street']),
      street2: _str(json['street2']),
      zip: _str(json['zip']),
      city: _str(json['city']),
      countryId: countryId,
      countryName: countryName,
      comment: _str(json['comment']),
    );
  }

  /// Dirección en una línea: "Calle Mayor 1, 2ºB, 28001 Madrid, España".
  /// null si no tiene ningún dato de dirección.
  String? get addressLine {
    final cityPart = [zip, city].whereType<String>().join(' ');
    final parts = [
      street,
      street2,
      if (cityPart.isNotEmpty) cityPart,
      countryName,
    ].whereType<String>().where((p) => p.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// Clave para comparar teléfonos escritos de formas distintas: solo las
  /// cifras, sin el prefijo internacional (00 o +) y, si es largo, sus
  /// últimas 9 cifras ("+34 600 11 22 33", "0034600112233" y "600112233"
  /// dan lo mismo). '' si no hay teléfono (o es demasiado corto para
  /// compararlo). Es la MISMA regla que usa Odoo al comprobar que no se
  /// repiten teléfonos en un viaje (_alventus_phone_key en
  /// models/project_project.py del módulo): si se cambia aquí, cambiarla
  /// también allí.
  static String normalizePhoneKey(String? phone) {
    var digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.length > 9) digits = digits.substring(digits.length - 9);
    return digits.length >= 6 ? digits : '';
  }
}
