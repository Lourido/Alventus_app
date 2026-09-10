import 'package:shared_preferences/shared_preferences.dart';
import '../changelog.dart';

/// Controla qué entradas de [kChangelog] ya se le han enseñado al
/// usuario en este dispositivo, para avisarle solo de las nuevas la
/// próxima vez que abra la app.
class ChangelogService {
  static const _prefKey = 'changelog_last_seen_version';

  /// Entradas que el usuario todavía no ha visto en este dispositivo.
  ///
  /// La primera vez que se llama (no hay nada guardado todavía --
  /// típicamente porque la app se acaba de actualizar con esta función,
  /// o porque es una instalación nueva) no devuelve nada, y deja
  /// guardado como "visto" todo lo que haya en [kChangelog] en ese
  /// momento. Así no se le muestra de golpe a nadie todo el historial
  /// antiguo: solo lo que se añada de aquí en adelante.
  static Future<List<ChangelogEntry>> getUnseenEntries() async {
    if (kChangelog.isEmpty) return [];

    final prefs = await SharedPreferences.getInstance();
    final lastSeen = prefs.getInt(_prefKey);

    if (lastSeen == null) {
      await prefs.setInt(_prefKey, _maxVersion());
      return [];
    }

    return kChangelog.where((e) => e.version > lastSeen).toList();
  }

  static Future<void> markAllSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, _maxVersion());
  }

  static int _maxVersion() =>
      kChangelog.map((e) => e.version).reduce((a, b) => a > b ? a : b);
}
