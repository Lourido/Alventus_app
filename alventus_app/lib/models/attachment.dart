class Attachment {
  final int id;
  final String name;
  final String? mimeType;
  final int? fileSize;
  final String? createDate;

  Attachment({
    required this.id,
    required this.name,
    this.mimeType,
    this.fileSize,
    this.createDate,
  });

  static String? _getString(dynamic value) {
    if (value == null || value == false) return null;
    return value.toString();
  }

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['id'] as int? ?? 0,
      name: json['name']?.toString() ?? '',
      mimeType: _getString(json['mimetype']),
      fileSize: json['file_size'] as int?,
      createDate: _getString(json['create_date']),
    );
  }

  // Formatear el tamaño del archivo para mostrar
  String get formattedSize {
    if (fileSize == null) return '';
    if (fileSize! < 1024) return '$fileSize B';
    if (fileSize! < 1024 * 1024) return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}