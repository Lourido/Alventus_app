import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/odoo_service.dart';

/// Mensajes que la app enseña al usuario (avisos y errores), para poder
/// cambiarlos DESDE ODOO sin tocar la app ni volver a compilarla.
///
/// Cómo funciona:
///  - cada mensaje tiene un código ('sin_cobertura'...) y un texto por
///    defecto, que es el que está escrito aquí abajo;
///  - en Odoo, en Viajes > Mensajes de la app (modelo `alventus.app.message`,
///    ver models/app_message.py del módulo), se puede escribir otro texto
///    para cualquiera de ellos;
///  - al abrir la app se traen los textos personalizados y se guardan en el
///    teléfono, así que siguen valiendo sin cobertura;
///  - si un mensaje no está personalizado (o no hay forma de preguntar a
///    Odoo), se usa el texto por defecto de aquí.
///
/// Para usar un mensaje: `Msg.of('sin_cobertura')`.
///
/// Para añadir uno nuevo: ponerlo en [defaults] con su código, usarlo en la
/// pantalla con `Msg.of(...)`, y añadir su ficha en data/app_messages.xml
/// del módulo de Odoo (si no, funcionará igual, pero no se podrá cambiar
/// desde Odoo).
class Msg {
  Msg._();

  static const _prefsKey = 'app_messages_custom';

  /// Textos por defecto (los de toda la vida). NO borrar códigos: si un
  /// mensaje deja de usarse, basta con dejar de llamarlo.
  static const Map<String, String> defaults = {
    'sin_cobertura':
        'Lo siento. Tendrás que esperar a que tengas cobertura para hacerlo.',
    'guardado_en_telefono':
        'Cambios guardados en el teléfono. Cuando haya conexión se subirán al servidor.',
    'viendo_datos_guardados':
        'NO hay conexión. Estás viendo los datos guardados en el teléfono la última vez que usaste la app con conexión.',
    'tarea_sin_nombre': 'Vamos,vamos, ... donde se ha visto ... dale un nombre.',
  };

  static Map<String, String> _custom = const {};

  /// El texto a enseñar: el personalizado en Odoo si lo hay, y si no el de
  /// por defecto. Nunca devuelve null ni lanza.
  static String of(String code) {
    final custom = _custom[code];
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    return defaults[code] ?? '';
  }

  /// Carga los textos personalizados guardados en el teléfono. Se llama al
  /// arrancar la app, antes de pintar nada (ver main.dart).
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved == null) return;
      final data = jsonDecode(saved) as Map<String, dynamic>;
      _custom = {
        for (final entry in data.entries) entry.key: entry.value.toString(),
      };
    } catch (_) {
      // Si algo falla, se usan los textos por defecto: nunca debe impedir
      // que la app arranque.
    }
  }

  /// Se trae de Odoo los textos personalizados y los guarda en el teléfono.
  /// Sin cobertura no pasa nada: se sigue con los que hubiera.
  static Future<void> refresh() async {
    try {
      final result = await OdooService().executeKw(
        model: 'alventus.app.message',
        method: 'app_messages',
        args: [],
      );
      if (result['success'] != true || result['result'] is! Map) return;
      final data = (result['result'] as Map).map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      );
      _custom = data;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(data));
    } catch (_) {}
  }
}
