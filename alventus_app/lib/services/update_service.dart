// -*- coding: utf-8 -*-
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

/// Datos de la versión más reciente publicada en el servidor.
class UpdateInfo {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String? notes;
  final bool mandatory;

  UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    this.notes,
    this.mandatory = false,
  });
}

/// Comprueba si hay una versión de la app más nueva que la instalada,
/// la descarga y lanza el instalador del sistema.
///
/// Solo tiene sentido en Android: la app no se distribuye por Play
/// Store, así que no hay otra forma de actualizarla. En iOS
/// [checkForUpdate] no hace nada (siempre devuelve null).
///
/// El manifiesto de la última versión es un archivo JSON estático
/// alojado en una carpeta del propio servidor Odoo (se sube a mano
/// cada vez que se publica una versión nueva, junto con el .apk), con
/// esta forma:
/// {
///   "versionCode": 3,
///   "versionName": "1.2.0",
///   "apkUrl": "https://alventus.duckdns.org/alf_proyecto_alventus/static/updates/alventus-1.2.0.apk",
///   "notes": "Adjuntos por etapa, botón de nueva tarea movible...",
///   "mandatory": false
/// }
///
/// "versionCode" tiene que ser el mismo número que el "+N" final del
/// campo `version:` de pubspec.yaml (p.ej. version: 1.2.0+3 → 3), y
/// tiene que subirse siempre a más que el de la versión anterior.
class UpdateService {
  UpdateService._internal();
  static final UpdateService instance = UpdateService._internal();

  static const String versionUrl =
      'https://alventus.duckdns.org/alf_proyecto_alventus/static/updates/latest.json';

  final Dio _dio = Dio();

  /// Devuelve la info de la actualización disponible, o null si ya se
  /// tiene la última versión (o si falla la comprobación: se falla en
  /// silencio para no molestar al usuario cada vez que abre la app sin
  /// conexión, o si el servidor está caído).
  Future<UpdateInfo?> checkForUpdate() async {
    // En la web no tiene sentido: una PWA se actualiza sola al recargar,
    // no hay APK que instalar. Comprobamos kIsWeb ANTES de tocar
    // Platform.isAndroid porque en web dart:io.Platform no representa un
    // sistema operativo real y algunas de sus propiedades lanzan
    // UnsupportedError; el cortocircuito de "||" evita llegar a evaluarlo.
    if (kIsWeb || !Platform.isAndroid) return null;

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        versionUrl,
        options: Options(
          responseType: ResponseType.json,
          // Evita que quede cacheada una respuesta antigua por el camino.
          headers: {'Cache-Control': 'no-cache'},
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );

      final data = response.data;
      if (data == null) return null;

      final remoteVersionCode = int.tryParse(data['versionCode'].toString()) ?? 0;
      if (remoteVersionCode <= 0) return null;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;

      if (remoteVersionCode <= currentVersionCode) return null;

      final apkUrl = data['apkUrl']?.toString();
      if (apkUrl == null || apkUrl.isEmpty) return null;

      return UpdateInfo(
        versionCode: remoteVersionCode,
        versionName: data['versionName']?.toString() ?? '',
        apkUrl: apkUrl,
        notes: data['notes']?.toString(),
        mandatory: data['mandatory'] == true,
      );
    } catch (e) {
      // Sin conexión, servidor caído, JSON mal formado... nunca debe
      // interrumpir el arranque de la app.
      return null;
    }
  }

  /// Descarga el APK indicado, informando del progreso (0.0 a 1.0).
  /// Devuelve la ruta local del archivo descargado, o null si falla.
  Future<String?> downloadApk(
    String url, {
    required void Function(double progress) onProgress,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/alventus_update.apk';

      await _dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress(received / total);
        },
      );

      return filePath;
    } catch (e) {
      return null;
    }
  }

  /// Lanza el instalador del sistema con el APK ya descargado. La
  /// primera vez, Android pedirá permiso para "instalar apps
  /// desconocidas" desde Alventus si no se había concedido antes.
  Future<void> installApk(String filePath) async {
    await OpenFilex.open(filePath);
  }
}
