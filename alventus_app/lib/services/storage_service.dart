import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  // Claves para almacenar las credenciales
  static const String _keyUid = 'odoo_uid';
  static const String _keyDb = 'odoo_database';
  static const String _keyLogin = 'odoo_login';
  static const String _keyPassword = 'odoo_password';
  static const String _keyUserName = 'odoo_username';

  /// Guarda las credenciales después de un login exitoso
  Future<void> saveCredentials({
    required int uid,
    required String db,
    required String login,
    required String password,
  }) async {
    print('💾 StorageService: Guardando credenciales...');
    print('💾 StorageService: UID = $uid, Login = $login, DB = $db');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyUid, uid);
    await prefs.setString(_keyDb, db);
    await prefs.setString(_keyLogin, login);
    await prefs.setString(_keyPassword, password);

    // Verificar que se guardaron
    final savedUid = prefs.getInt(_keyUid);
    print('💾 StorageService: Verificación - UID guardado = $savedUid');
    print('💾 StorageService: Credenciales guardadas correctamente');
  }

  /// Alias para compatibilidad con OdooService
  Future<void> saveSession({
    required int uid,
    String? db,
    String? login,
    String? username,
    required String password,
  }) async {
    final effectiveLogin = login ?? username;

    print('💾 StorageService: Guardando sesión (alias)...');
    print('💾 StorageService: UID = $uid, Login = $effectiveLogin, DB = $db');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyUid, uid);

    if (db != null) {
      await prefs.setString(_keyDb, db);
    }

    if (effectiveLogin != null) {
      await prefs.setString(_keyLogin, effectiveLogin);
    }

    await prefs.setString(_keyPassword, password);

    // Verificar que se guardaron
    final savedUid = prefs.getInt(_keyUid);
    print('💾 StorageService: Verificación - UID guardado = $savedUid');
    print('💾 StorageService: Sesión guardada correctamente');
  }

  /// Obtiene la contraseña guardada
  Future<String?> getPassword() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final password = prefs.getString(_keyPassword);
      print('🔍 StorageService: Leyendo contraseña = ${password != null ? "***" : "null"}');
      return password;
    } catch (e) {
      print('❌ StorageService: Error al leer contraseña: $e');
      return null;
    }
  }

  /// Obtiene el login guardado
  Future<String?> getLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final login = prefs.getString(_keyLogin);
      print('🔍 StorageService: Leyendo login = $login');
      return login;
    } catch (e) {
      print('❌ StorageService: Error al leer login: $e');
      return null;
    }
  }

  /// Obtiene la base de datos guardada
  Future<String?> getDatabase() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final db = prefs.getString(_keyDb);
      print('🔍 StorageService: Leyendo base de datos = $db');
      return db;
    } catch (e) {
      print('❌ StorageService: Error al leer base de datos: $e');
      return null;
    }
  }

  /// Obtiene el UID guardado
  Future<int?> getUid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getInt(_keyUid);
      print('🔍 StorageService: Leyendo UID = $uid');
      return uid;
    } catch (e) {
      print('❌ StorageService: Error al leer UID: $e');
      return null;
    }
  }

  /// Obtiene toda la sesión como un Map
  Future<Map<String, dynamic>?> getSession() async {
    try {
      final uid = await getUid();
      final db = await getDatabase();
      final login = await getLogin();
      final password = await getPassword();

      if (uid == null || password == null) {
        print('🔍 StorageService: Sesión incompleta (uid=$uid, password=${password != null ? "***" : "null"})');
        return null;
      }

      print('🔍 StorageService: Sesión completa obtenida (uid=$uid)');
      return {
        'uid': uid,
        'db': db,
        'login': login,
        'username': login,
        'password': password,
      };
    } catch (e) {
      print('❌ StorageService: Error al obtener sesión: $e');
      return null;
    }
  }

  /// Borra todas las credenciales (logout)
  Future<void> clearCredentials() async {
    try {
      print('💾 StorageService: Borrando credenciales...');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyUid);
      await prefs.remove(_keyDb);
      await prefs.remove(_keyLogin);
      await prefs.remove(_keyPassword);
      await prefs.remove(_keyUserName);
      print('💾 StorageService: Credenciales borradas');
    } catch (e) {
      print('❌ StorageService: Error al borrar credenciales: $e');
    }
  }

  /// Alias para compatibilidad con OdooService
  Future<void> clearSession() async {
    await clearCredentials();
  }
  /// Guarda el nombre del usuario
  Future<void> saveUserName(String userName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUserName, userName);
      print('💾 StorageService: Nombre de usuario guardado = $userName');
    } catch (e) {
      print('❌ StorageService: Error al guardar nombre de usuario: $e');
    }
  }

  /// Obtiene el nombre del usuario guardado
  Future<String?> getUserName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userName = prefs.getString(_keyUserName);
      print('🔍 StorageService: Leyendo nombre de usuario = $userName');
      return userName;
    } catch (e) {
      print('❌ StorageService: Error al leer nombre de usuario: $e');
      return null;
    }
  }
}