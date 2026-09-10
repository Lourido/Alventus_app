class ReferenceContact {
  final int id;
  final String name;
  final String? email;
  final String? phone;
  final String? city;
  final String? comment;

  ReferenceContact({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.city,
    this.comment,
  });

  static String? _str(dynamic value) {
    if (value == null || value == false) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  factory ReferenceContact.fromJson(Map<String, dynamic> json) {
    return ReferenceContact(
      id: json['id'] as int,
      name: _str(json['name']) ?? 'Sin nombre',
      email: _str(json['email']),
      phone: _str(json['phone']),
      city: _str(json['city']),
      comment: _str(json['comment']),
    );
  }
}
