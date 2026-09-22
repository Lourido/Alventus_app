import 'dart:convert';
import 'dart:js_interop';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/odoo_service.dart';
import 'app_messages.dart';

/// Avisos en el teléfono (notificaciones push) para las tareas con hora de
/// inicio. Solo en la versión web (PWA).
///
/// Piezas:
///  - web/push.js: pide permiso al usuario y crea la "suscripción" del
///    teléfono (funciones alventusPush* de abajo).
///  - Odoo, modelo alventus.push.subscription (models/push_notification.py
///    del módulo): guarda las suscripciones y MANDA los avisos cuando llega
///    la hora de cada tarea, aunque la app esté cerrada.
///  - web/offline_sw.js: recibe los avisos y los enseña.
///
/// Si algún día esto no compila: revisar que los nombres de @JS(...)
/// coinciden EXACTAMENTE con las funciones que web/push.js deja en window.

@JS('alventusPushStatus')
external JSString _pushStatus();

@JS('alventusPushEnable')
external JSPromise<JSString> _pushEnable(JSString publicKey);

@JS('alventusPushCurrent')
external JSPromise<JSString> _pushCurrent();

@JS('alventusPushDisable')
external JSPromise<JSString> _pushDisable();

const _model = 'alventus.push.subscription';
const _prefsKeyVapid = 'push_vapid_public_key';

/// Estado de los avisos en este teléfono.
enum PushStatus {
  /// Este navegador no puede recibir avisos.
  unsupported,

  /// iPhone con la app abierta desde Safari: hay que añadirla a la
  /// pantalla de inicio primero.
  iosNeedsInstall,

  /// El usuario bloqueó los avisos (se desbloquean en los ajustes del
  /// teléfono, no desde la app).
  denied,

  /// Aún no se han activado.
  notEnabled,

  /// Activados.
  enabled,
}

class PushNotifications {
  PushNotifications._();

  static final OdooService _odoo = OdooService();

  /// Qué dice el navegador, sin preguntar nada al usuario.
  static Future<PushStatus> status() async {
    String raw;
    try {
      raw = _pushStatus().toDart;
    } catch (_) {
      return PushStatus.unsupported; // push.js aún no cargado (copia vieja)
    }
    switch (raw) {
      case 'ios-needs-install':
        return PushStatus.iosNeedsInstall;
      case 'denied':
        return PushStatus.denied;
      case 'granted':
        final current = await _currentSubscription();
        return current == null ? PushStatus.notEnabled : PushStatus.enabled;
      case 'default':
        return PushStatus.notEnabled;
      default:
        return PushStatus.unsupported;
    }
  }

  /// Clave pública del servidor, necesaria para activar los avisos. Se pide
  /// a Odoo y se guarda en el teléfono; hay que tenerla ANTES de que el
  /// usuario pulse "Activar" (ver [enableFromTap]). null si no hay
  /// cobertura y tampoco estaba guardada.
  static Future<String?> loadPublicKey() async {
    final prefs = await SharedPreferences.getInstance();
    final result = await _odoo.executeKw(model: _model, method: 'app_public_key', args: []);
    if (result['success'] == true && result['result'] is String) {
      final key = result['result'] as String;
      await prefs.setString(_prefsKeyVapid, key);
      return key;
    }
    return prefs.getString(_prefsKeyVapid);
  }

  /// Activa los avisos. Tiene que llamarse DIRECTAMENTE desde el onPressed
  /// del botón, sin ningún await antes: el iPhone solo deja pedir permiso
  /// en el mismo instante del toque. Por eso la clave se pasa ya cargada.
  ///
  /// Devuelve null si ha ido bien, o el texto del problema para enseñarlo.
  static Future<String?> enableFromTap(String publicKey) async {
    // Se lanza la petición a JS ya, en el mismo toque (el await va después).
    final Future<String> pending = _callEnable(publicKey);
    final raw = await pending;

    if (raw == 'denied') {
      return 'Has bloqueado los avisos. Para recibirlos, permítelos para '
          'Alventus en los ajustes del teléfono.';
    }
    if (raw == 'default') {
      return 'No se han activado los avisos.';
    }
    if (raw.startsWith('error')) {
      return 'No se han podido activar los avisos: ${raw.substring(raw.indexOf(':') + 1).trim()}';
    }

    final ok = await _registerOnServer(raw);
    if (!ok) {
      return Msg.of('sin_cobertura');
    }
    return null;
  }

  static Future<String> _callEnable(String publicKey) async {
    try {
      return (await _pushEnable(publicKey.toJS).toDart).toDart;
    } catch (e) {
      return 'error: $e';
    }
  }

  /// Desactiva los avisos en este teléfono (y lo borra en Odoo).
  static Future<void> disable() async {
    String endpoint = '';
    try {
      endpoint = (await _pushDisable().toDart).toDart;
    } catch (_) {}
    if (endpoint.isNotEmpty) {
      await _odoo.executeKw(model: _model, method: 'app_unregister', args: [endpoint]);
    }
  }

  /// Al cerrar sesión: este teléfono deja de recibir los avisos de ese
  /// usuario (se borra en Odoo). La suscripción del navegador se queda, y
  /// si entra otro usuario se le asigna a él al abrir la app.
  static Future<void> unregisterOnLogout() async {
    final current = await _currentSubscription();
    final endpoint = current?['endpoint'];
    if (endpoint is String && endpoint.isNotEmpty) {
      await _odoo.executeKw(model: _model, method: 'app_unregister', args: [endpoint]);
    }
  }

  /// Al abrir la app: si los avisos están activados, se vuelve a mandar la
  /// suscripción a Odoo. Así se mantienen al día la zona horaria (si se
  /// viaja a otro país, los avisos llegan a la hora de allí) y el usuario
  /// (si en este teléfono ha entrado otra persona). Sin cobertura no pasa
  /// nada: se hará la próxima vez.
  static Future<void> refreshRegistration() async {
    try {
      final current = await _currentSubscription();
      if (current == null) return;
      await _registerOnServer(jsonEncode(current));
    } catch (_) {}
  }

  /// Manda un aviso de prueba a este teléfono. Devuelve null si Odoo lo ha
  /// mandado, o el texto del problema.
  static Future<String?> sendTest() async {
    final current = await _currentSubscription();
    final endpoint = current?['endpoint'];
    if (endpoint is! String || endpoint.isEmpty) {
      return 'Los avisos no están activados en este teléfono.';
    }
    // Por si acaso, se vuelve a registrar antes (p. ej. si se borró en Odoo).
    if (!await _registerOnServer(jsonEncode(current))) {
      return Msg.of('sin_cobertura');
    }
    final result = await _odoo.executeKw(model: _model, method: 'app_send_test', args: [endpoint]);
    if (result['success'] != true) {
      return Msg.of('sin_cobertura');
    }
    final data = result['result'];
    if (data is Map && (data['sent'] as int? ?? 0) > 0) return null;
    final errors = data is Map ? data['errors'] : null;
    final detail = errors is List && errors.isNotEmpty ? ' (${errors.first})' : '';
    return 'El servidor no ha podido mandar el aviso$detail.';
  }

  static Future<Map<String, dynamic>?> _currentSubscription() async {
    try {
      final raw = (await _pushCurrent().toDart).toDart;
      if (raw.isEmpty) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _registerOnServer(String subscriptionJson) async {
    try {
      final data = jsonDecode(subscriptionJson) as Map<String, dynamic>;
      final result = await _odoo.executeKw(
        model: _model,
        method: 'app_register',
        args: [
          data['endpoint'],
          data['p256dh'],
          data['auth'],
          data['timezone'] ?? '',
          data['device'] ?? '',
        ],
      );
      return result['success'] == true;
    } catch (_) {
      return false;
    }
  }
}
