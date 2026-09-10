class RouteFile {
  final int id;
  final String fileName;
  final String? description;
  final int sequence;

  RouteFile({
    required this.id,
    required this.fileName,
    this.description,
    this.sequence = 0,
  });

  factory RouteFile.fromJson(Map<String, dynamic> json) {
    return RouteFile(
      id: json['id'] as int,
      fileName: (json['file_name'] as String?)?.trim().isNotEmpty == true
          ? json['file_name'] as String
          : 'archivo_sin_nombre',
      description: (json['description'] == false) ? null : json['description'] as String?,
      sequence: json['sequence'] as int? ?? 0,
    );
  }

  /// Extensión en minúsculas sin el punto, p.ej. "gpx", "kmz". Vacío si no
  /// tiene extensión reconocible.
  String get extension {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == fileName.length - 1) return '';
    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  /// True si el nombre del archivo tiene pinta de ser un track/ruta GPS
  /// reconocible por apps como Wikiloc, Komoot, etc.
  bool get isRouteTrackFormat =>
      const {'gpx', 'kml', 'kmz', 'tcx', 'geojson'}.contains(extension);
}
