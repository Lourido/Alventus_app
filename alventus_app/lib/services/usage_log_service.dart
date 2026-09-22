import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:shared_preferences/shared_preferences.dart';

import 'local_database_service.dart';
import 'odoo_service.dart';

/// Registro de uso de la app: quién la usa, con qué teléfono, desde qué
/// hora y qué va haciendo (pantallas que abre y acciones que hace).
///
/// Se guarda en Odoo, en los modelos `alventus.app.session` y
/// `alventus.app.event` (ver models/app_usage.py del módulo), y se consulta
/// en Viajes > Registro de uso de la app. Solo lo ve Administración.
///
/// Cómo funciona, para que no moleste al usuario ni gaste datos:
///  - cada cosa que se apunta se guarda PRIMERO en el teléfono (tabla
///    usage_events de la base local), así que apuntar no espera a la red;
///  - cada poco (o cuando se acumulan unas cuantas) se suben todas juntas,
///    con la hora real de cada una;
///  - sin cobertura se quedan esperando y suben cuando vuelva; si el
///    teléfono se queda sin espacio o algo falla, se descartan las más
///    viejas: esto NUNCA debe estropear el uso normal de la app.
///
/// Uso desde las pantallas:
///   UsageLog.screen('Viaje', detail: project.name);
///   UsageLog.action('Crea una tarea', detail: nombre);
class UsageLog {
  UsageLog._();
  static final UsageLog _instance = UsageLog._();

  static const _model = 'alventus.app.session';
  static const _prefsSessionId = 'usage_session_id';

  // Cuántos eventos se suben de una vez y cada cuánto se intenta.
  static const _loteMaximo = 100;
  static const _cada = Duration(seconds: 45);

  // Tope de eventos guardados en el teléfono esperando a subir (varios días
  // sin cobertura): a partir de ahí se tiran los más viejos.
  static const _maximoEnEspera = 2000;

  final LocalDatabaseService _localDb = LocalDatabaseService();
  final OdooService _odoo = OdooService();

  bool _started = false;
  bool _sending = false;
  int? _sessionId;
  String? _sessionStartUtc;
  Timer? _timer;

  /// Empieza a registrar (una vez por arranque de la app, ya con la sesión
  /// del usuario iniciada). No espera a la red: la sesión se abre en Odoo
  /// en la primera subida.
  static Future<void> startSession() => _instance._startSession();

  /// Apunta que el usuario ha abierto una pantalla.
  static void screen(String name, {String? detail}) =>
      _instance._add('screen', name, detail);

  /// Apunta que el usuario ha hecho algo (crear, editar, borrar, subir...).
  static void action(String name, {String? detail}) =>
      _instance._add('action', name, detail);

  /// Apunta un error que le ha salido al usuario (el servidor contesta mal,
  /// algo falla en la app...). Así se puede ver en Odoo qué problemas se
  /// encuentra la gente sin tener que preguntarles.
  static void error(String name, {String? detail}) =>
      _instance._add('error', name, detail);

  /// Sube ya lo que haya pendiente (al cerrar sesión, por ejemplo).
  static Future<void> flushNow() => _instance._flush();

  /// Al cerrar sesión: sube lo pendiente y olvida la sesión, para que lo
  /// siguiente se apunte a nombre de quien entre después.
  static Future<void> endSession() async {
    await _instance._flush();
    _instance._timer?.cancel();
    _instance._timer = null;
    _instance._started = false;
    _instance._sessionId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsSessionId);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------

  Future<void> _startSession() async {
    if (_started) return;
    _started = true;
    _sessionId = null;
    _sessionStartUtc = _ahoraUtc();
    try {
      final prefs = await SharedPreferences.getInstance();
      // Cada arranque de la app es una sesión nueva: se olvida la anterior.
      await prefs.remove(_prefsSessionId);
    } catch (_) {}
    _timer?.cancel();
    _timer = Timer.periodic(_cada, (_) => _flush());
    _add('action', 'Abre la app');
  }

  void _add(String kind, String name, [String? detail]) {
    // Nunca debe hacer esperar a la pantalla que lo llama ni fallar.
    () async {
      try {
        // Mientras se están subiendo, no se apunta nada nuevo: si la
        // subida falla, apuntar ESE error crearía otro evento, y otro...
        if (!_started || _sending) return;
        await _localDb.addUsageEvent(
          ts: _ahoraUtc(),
          kind: kind,
          action: name,
          detail: detail,
          offline: !OdooService.serverReachable,
        );
        await _localDb.trimUsageEvents(_maximoEnEspera);
      } catch (_) {}
    }();
  }

  Future<void> _flush() async {
    if (_sending || !_started) return;
    _sending = true;
    try {
      final rows = await _localDb.getUsageEvents(_loteMaximo);
      if (rows.isEmpty) return;

      if (_sessionId == null) {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getInt(_prefsSessionId);
        if (saved != null) {
          _sessionId = saved;
        } else {
          final result = await _odoo.executeKw(
            model: _model,
            method: 'app_start_session',
            args: [
              _deviceType(),
              _deviceDetail(),
              _timezone(),
              _sessionStartUtc ?? _ahoraUtc(),
            ],
          );
          if (result['success'] != true || result['result'] is! int) return;
          _sessionId = result['result'] as int;
          await prefs.setInt(_prefsSessionId, _sessionId!);
        }
      }

      final events = [
        for (final row in rows)
          {
            't': row['ts'],
            'kind': row['kind'],
            'action': row['action'],
            'detail': row['detail'] ?? '',
            'offline': (row['offline'] as int? ?? 0) == 1,
          },
      ];

      final result = await _odoo.executeKw(
        model: _model,
        method: 'app_log',
        args: [_sessionId, events],
      );

      if (result['success'] == true) {
        await _localDb.deleteUsageEvents(
          [for (final row in rows) row['id'] as int],
        );
      } else if (result['offline'] != true) {
        // Error del servidor (por ejemplo, el módulo aún sin actualizar):
        // se tiran estos eventos para no quedarse atascado reintentando
        // siempre los mismos. El registro es una ayuda, no algo crítico.
        await _localDb.deleteUsageEvents(
          [for (final row in rows) row['id'] as int],
        );
      }
    } catch (_) {
      // Sin cobertura o cualquier otro problema: se quedan esperando.
    } finally {
      _sending = false;
    }
  }

  static String _ahoraUtc() {
    final n = DateTime.now().toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

  static String _deviceType() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return 'other';
    }
  }

  static String _deviceDetail() {
    final sistema = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'iPhone/iPad',
      TargetPlatform.android => 'Android',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      _ => 'Otro',
    };
    return kIsWeb ? '$sistema (navegador/PWA)' : '$sistema (app instalada)';
  }

  /// Zona horaria tal como la ve el teléfono ("CEST +02:00"): sirve para
  /// entender las horas de quien está de viaje en otro país.
  static String _timezone() {
    final ahora = DateTime.now();
    final desfase = ahora.timeZoneOffset;
    final signo = desfase.isNegative ? '-' : '+';
    final horas = desfase.abs().inHours.toString().padLeft(2, '0');
    final minutos = (desfase.abs().inMinutes % 60).toString().padLeft(2, '0');
    return '${ahora.timeZoneName} $signo$horas:$minutos';
  }
}
