import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path/path.dart';

class LocalDatabaseService {
  // Singleton
  LocalDatabaseService._internal();
  static final LocalDatabaseService _instance = LocalDatabaseService._internal();
  factory LocalDatabaseService() => _instance;

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path;
    if (kIsWeb) {
      // En el navegador no existe un directorio de datos nativo: sqflite
      // guarda la base de datos en IndexedDB a través de este backend,
      // usando el nombre como clave (sin join con getDatabasesPath, que
      // no está disponible en web).
      databaseFactory = databaseFactoryFfiWeb;
      path = 'alventus.db';
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, 'alventus.db');
    }

    return await openDatabase(
      path,
      version: 8,
      onCreate: _createTables,
      onUpgrade: _upgradeTables,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    // Tabla de proyectos
    await db.execute('''
      CREATE TABLE IF NOT EXISTS projects (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        user_name TEXT,
        partner_name TEXT,
        date_start TEXT,
        date_end TEXT,
        task_count INTEGER DEFAULT 0,
        day_count INTEGER DEFAULT 0,
        last_sync TEXT
      )
    ''');

    // Tabla de tareas
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tasks (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        project_id INTEGER NOT NULL,
        stage_name TEXT,
        deadline TEXT,
        priority TEXT DEFAULT '0',
        fecha_desde TEXT,
        fecha_hasta TEXT,
        sequence INTEGER DEFAULT 0,
        last_sync TEXT,
        FOREIGN KEY (project_id) REFERENCES projects (id)
      )
    ''');

    // Tabla de adjuntos (solo metadata, no el contenido)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attachments (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        mime_type TEXT,
        file_size INTEGER,
        create_date TEXT,
        task_id INTEGER NOT NULL,
        local_path TEXT,
        last_sync TEXT,
        FOREIGN KEY (task_id) REFERENCES tasks (id)
      )
    ''');

    // Tabla de contactos de referencia (sí se guardan todos los campos,
    // no solo metadata, porque son datos de texto ligeros y se pueden
    // ver por completo sin conexión).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reference_contacts (
        id INTEGER PRIMARY KEY,
        project_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        city TEXT,
        comment TEXT,
        last_sync TEXT,
        FOREIGN KEY (project_id) REFERENCES projects (id)
      )
    ''');

    // Tabla de archivos de ruta (solo metadata; el contenido del archivo
    // en sí solo se descarga bajo demanda, con conexión).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS route_files (
        id INTEGER PRIMARY KEY,
        project_id INTEGER NOT NULL,
        file_name TEXT NOT NULL,
        description TEXT,
        sequence INTEGER DEFAULT 0,
        local_path TEXT,
        last_sync TEXT,
        FOREIGN KEY (project_id) REFERENCES projects (id)
      )
    ''');

    // Tabla de documentos del proyecto (fichas, seguros, PDFs...), solo
    // metadata.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS project_documents (
        id INTEGER PRIMARY KEY,
        project_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        mime_type TEXT,
        file_size INTEGER,
        create_date TEXT,
        local_path TEXT,
        last_sync TEXT,
        FOREIGN KEY (project_id) REFERENCES projects (id)
      )
    ''');

    // Tabla de documentos de etapa (día del viaje), solo metadata.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stage_attachments (
        id INTEGER PRIMARY KEY,
        stage_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        mime_type TEXT,
        file_size INTEGER,
        create_date TEXT,
        local_path TEXT,
        last_sync TEXT
      )
    ''');

    // Tabla de fotos del grupo, solo metadata.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS project_photos (
        id INTEGER PRIMARY KEY,
        project_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        create_date TEXT,
        local_path TEXT,
        last_sync TEXT,
        FOREIGN KEY (project_id) REFERENCES projects (id)
      )
    ''');

    // Tabla de cambios pendientes de sincronizar
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_changes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        model TEXT NOT NULL,
        record_id INTEGER,
        action TEXT NOT NULL,
        data TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        status TEXT DEFAULT 'pending'
      )
    ''');

    // Papelera: documentos, archivos de ruta y contactos que el usuario
    // borra quedan aquí guardados (con su contenido, si lo tienen) antes
    // de borrarse de verdad en Odoo, por si se quieren recuperar luego.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trash_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        project_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        extra_data TEXT,
        deleted_at TEXT
      )
    ''');
  }

  Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {
    print('🔧 Actualizando base de datos de versión $oldVersion a $newVersion');

    if (oldVersion < 3) {
      try {
        await db.execute(
          'ALTER TABLE attachments ADD COLUMN local_path TEXT',
        );
        print('✅ Columna local_path añadida a attachments');
      } catch (e) {
        print('⚠️ No se pudo añadir local_path (puede que ya exista): $e');
      }
    }

    if (oldVersion < 4) {
      try {
        await db.execute(
          'ALTER TABLE tasks ADD COLUMN sequence INTEGER DEFAULT 0',
        );
        print('✅ Columna sequence añadida a tasks');
      } catch (e) {
        print('⚠️ No se pudo añadir sequence (puede que ya exista): $e');
      }
    }

    if (oldVersion < 5) {
      try {
        await db.execute(
          'ALTER TABLE projects ADD COLUMN day_count INTEGER DEFAULT 0',
        );
        print('✅ Columna day_count añadida a projects');
      } catch (e) {
        print('⚠️ No se pudo añadir day_count (puede que ya exista): $e');
      }
    }

    if (oldVersion < 6) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS reference_contacts (
            id INTEGER PRIMARY KEY,
            project_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            phone TEXT,
            email TEXT,
            city TEXT,
            comment TEXT,
            last_sync TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS route_files (
            id INTEGER PRIMARY KEY,
            project_id INTEGER NOT NULL,
            file_name TEXT NOT NULL,
            description TEXT,
            sequence INTEGER DEFAULT 0,
            local_path TEXT,
            last_sync TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS project_documents (
            id INTEGER PRIMARY KEY,
            project_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            mime_type TEXT,
            file_size INTEGER,
            create_date TEXT,
            local_path TEXT,
            last_sync TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS project_photos (
            id INTEGER PRIMARY KEY,
            project_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            create_date TEXT,
            local_path TEXT,
            last_sync TEXT
          )
        ''');
        print('✅ Tablas de contactos/rutas/documentos/fotos añadidas');
      } catch (e) {
        print('⚠️ No se pudieron añadir las tablas nuevas (puede que ya existan): $e');
      }
    }

    if (oldVersion < 7) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS trash_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            project_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            extra_data TEXT,
            deleted_at TEXT
          )
        ''');
        print('✅ Tabla de papelera (trash_items) añadida');
      } catch (e) {
        print('⚠️ No se pudo añadir trash_items (puede que ya exista): $e');
      }
    }

    if (oldVersion < 8) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS stage_attachments (
            id INTEGER PRIMARY KEY,
            stage_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            mime_type TEXT,
            file_size INTEGER,
            create_date TEXT,
            local_path TEXT,
            last_sync TEXT
          )
        ''');
        print('✅ Tabla de adjuntos de etapa (stage_attachments) añadida');
      } catch (e) {
        print('⚠️ No se pudo añadir stage_attachments (puede que ya exista): $e');
      }
    }
  }

  // ============ PROYECTOS ============

  Future<void> saveProjects(List<Map<String, dynamic>> projects) async {
    final db = await database;
    final batch = db.batch();

    for (final project in projects) {
      batch.insert(
        'projects',
        {
          'id': project['id'],
          'name': project['name'] ?? '',
          'description': project['description'],
          'user_name': project['user_name'],
          'partner_name': project['partner_name'],
          'date_start': project['date_start'],
          'date_end': project['date_end'],
          'task_count': project['task_count'] ?? 0,
          'day_count': project['day_count'] ?? 0,
          'last_sync': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);

    // Borra de la copia local los proyectos que ya no existan en Odoo
    // (por ejemplo, los que se hayan borrado desde la web), para que la
    // app no siga mostrándolos como si siguieran ahí.
    final incomingIds = projects.map((p) => p['id'] as int).toList();

    if (incomingIds.isEmpty) {
      // Si Odoo no devuelve ningún proyecto, es que no queda ninguno.
      await db.delete('projects');
      await db.delete('tasks');
      return;
    }

    final placeholders = List.filled(incomingIds.length, '?').join(',');

    final staleProjects = await db.query(
      'projects',
      columns: ['id'],
      where: 'id NOT IN ($placeholders)',
      whereArgs: incomingIds,
    );
    final staleIds = staleProjects.map((row) => row['id'] as int).toList();

    if (staleIds.isNotEmpty) {
      await db.delete(
        'projects',
        where: 'id NOT IN ($placeholders)',
        whereArgs: incomingIds,
      );

      final taskPlaceholders = List.filled(staleIds.length, '?').join(',');
      await db.delete(
        'tasks',
        where: 'project_id IN ($taskPlaceholders)',
        whereArgs: staleIds,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getProjects() async {
    final db = await database;
    return await db.query('projects', orderBy: 'name ASC, date_start ASC');
  }

  // ============ TAREAS ============

  Future<void> saveTasks(List<Map<String, dynamic>> tasks, {int? projectId}) async {
    final db = await database;

    // Si se indica el proyecto, borra de la copia local las tareas de ESE
    // proyecto que ya no vengan en la lista nueva (incluido el caso de
    // que ya no quede ninguna tarea, si se borraron todas en Odoo).
    if (projectId != null) {
      final incomingIds = tasks.map((t) => t['id'] as int).toList();

      if (incomingIds.isEmpty) {
        await db.delete('tasks', where: 'project_id = ?', whereArgs: [projectId]);
      } else {
        final placeholders = List.filled(incomingIds.length, '?').join(',');
        await db.delete(
          'tasks',
          where: 'project_id = ? AND id NOT IN ($placeholders)',
          whereArgs: [projectId, ...incomingIds],
        );
      }
    }

    final batch = db.batch();

    for (final task in tasks) {
      batch.insert(
        'tasks',
        {
          'id': task['id'],
          'name': task['name'] ?? '',
          'description': task['description'],
          'project_id': task['project_id'],
          'stage_name': task['stage_name'],
          'deadline': task['deadline'],
          'priority': task['priority'] ?? '0',
          'fecha_desde': task['fecha_desde'],
          'fecha_hasta': task['fecha_hasta'],
          'sequence': task['sequence'] ?? 0,
          'last_sync': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getTasks(int projectId) async {
    final db = await database;
    return await db.query(
      'tasks',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'fecha_desde ASC',
    );
  }

  Future<void> deleteTask(int taskId) async {
    final db = await database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [taskId]);
  }

  Future<void> updateTask(int taskId, Map<String, dynamic> data) async {
    final db = await database;
    await db.update(
      'tasks',
      data,
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  // ============ ADJUNTOS ============

  Future<void> saveAttachments(List<Map<String, dynamic>> attachments, {int? taskId}) async {
    final db = await database;

    // Si se proporciona taskId, borrar adjuntos previos de esa tarea que NO sean offline pendientes
    if (taskId != null) {
      await db.delete(
        'attachments',
        where: 'task_id = ? AND local_path IS NULL',
        whereArgs: [taskId],
      );
    }

    final batch = db.batch();

    for (final attachment in attachments) {
      batch.insert(
        'attachments',
        {
          'id': attachment['id'],
          'name': attachment['name'] ?? '',
          'mime_type': attachment['mime_type'],
          'file_size': attachment['file_size'],
          'create_date': attachment['create_date'],
          'task_id': attachment['task_id'],
          'last_sync': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getAttachments(int taskId) async {
    final db = await database;
    return await db.query(
      'attachments',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'create_date DESC',
    );
  }

  Future<void> deleteAttachment(int attachmentId) async {
    final db = await database;
    await db.delete('attachments', where: 'id = ?', whereArgs: [attachmentId]);
  }

  // ============ CAMBIOS PENDIENTES ============

  Future<void> addPendingChange({
    required String model,
    required String action,
    int? recordId,
    Map<String, dynamic>? data,
  }) async {
    final db = await database;
    await db.insert(
      'pending_changes',
      {
        'model': model,
        'record_id': recordId,
        'action': action,
        'data': data != null ? mapToJson(data) : null,
        'created_at': DateTime.now().toIso8601String(),
        'status': 'pending',
      },
    );
  }

  Future<List<Map<String, dynamic>>> getPendingChanges() async {
    final db = await database;
    return await db.query(
      'pending_changes',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> markChangeSynced(int changeId) async {
    final db = await database;
    await db.update(
      'pending_changes',
      {'status': 'synced'},
      where: 'id = ?',
      whereArgs: [changeId],
    );
  }

  Future<void> markChangeFailed(int changeId) async {
    final db = await database;
    await db.update(
      'pending_changes',
      {'status': 'failed'},
      where: 'id = ?',
      whereArgs: [changeId],
    );
  }

  // Helper para convertir Map a JSON string
  String mapToJson(Map<String, dynamic> map) {
    return jsonEncode(map);
  }
  // ============ ADJUNTOS OFFLINE ============

  /// Guarda la metadata de un adjunto offline
  Future<void> saveOfflineAttachment({
    required int taskId,
    required String fileName,
    required String filePath,
    String? mimeType,
    int? fileSize,
  }) async {
    final db = await database;
    // Generar un ID temporal negativo para adjuntos offline
    final tempId = -DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      'attachments',
      {
        'id': tempId,
        'name': fileName,
        'mime_type': mimeType,
        'file_size': fileSize,
        'create_date': DateTime.now().toIso8601String(),
        'task_id': taskId,
        'local_path': filePath, // Ruta local del archivo
        'last_sync': null, // No se ha sincronizado aún
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Añadir a la cola de cambios pendientes
    await addPendingChange(
      model: 'ir.attachment',
      action: 'upload',
      recordId: tempId,
      data: {
        'task_id': taskId.toString(),
        'file_name': fileName,
        'file_path': filePath,
      },
    );
  }

  /// Obtiene los adjuntos pendientes de subir
  Future<List<Map<String, dynamic>>> getPendingAttachments() async {
    final db = await database;
    return await db.query(
      'attachments',
      where: 'last_sync IS NULL AND local_path IS NOT NULL',
    );
  }

  // ============ CONTACTOS DE REFERENCIA ============

  Future<void> saveReferenceContacts(List<Map<String, dynamic>> contacts, {int? projectId}) async {
    final db = await database;

    if (projectId != null) {
      // Igual que con tareas: borra los que ya no vengan de Odoo, pero
      // respeta los que estén pendientes de sincronizar (id negativo,
      // creados offline y aún no subidos).
      final incomingIds = contacts.map((c) => c['id'] as int).toList();
      if (incomingIds.isEmpty) {
        await db.delete(
          'reference_contacts',
          where: 'project_id = ? AND id > 0',
          whereArgs: [projectId],
        );
      } else {
        final placeholders = List.filled(incomingIds.length, '?').join(',');
        await db.delete(
          'reference_contacts',
          where: 'project_id = ? AND id > 0 AND id NOT IN ($placeholders)',
          whereArgs: [projectId, ...incomingIds],
        );
      }
    }

    final batch = db.batch();
    for (final c in contacts) {
      batch.insert(
        'reference_contacts',
        {
          'id': c['id'],
          'project_id': c['project_id'],
          'name': c['name'] ?? '',
          'phone': c['phone'],
          'email': c['email'],
          'city': c['city'],
          'comment': c['comment'],
          'last_sync': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getReferenceContacts(int projectId) async {
    final db = await database;
    return await db.query(
      'reference_contacts',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'name ASC',
    );
  }

  Future<void> deleteReferenceContactLocal(int id) async {
    final db = await database;
    await db.delete('reference_contacts', where: 'id = ?', whereArgs: [id]);
  }

  /// Guarda un contacto de referencia creado sin conexión, y lo encola
  /// para crearlo y enlazarlo en Odoo cuando vuelva la señal.
  Future<void> saveOfflineReferenceContact({
    required int projectId,
    required String name,
    String? phone,
    String? email,
  }) async {
    final db = await database;
    final tempId = -DateTime.now().millisecondsSinceEpoch;

    await db.insert('reference_contacts', {
      'id': tempId,
      'project_id': projectId,
      'name': name,
      'phone': phone,
      'email': email,
      'city': null,
      'comment': null,
      'last_sync': null,
    });

    await addPendingChange(
      model: 'reference_contact',
      action: 'create',
      recordId: tempId,
      data: {
        'project_id': projectId.toString(),
        'name': name,
        'phone': phone ?? '',
        'email': email ?? '',
      },
    );
  }

  // ============ ARCHIVOS DE RUTA ============

  Future<void> saveRouteFiles(List<Map<String, dynamic>> files, {int? projectId}) async {
    final db = await database;

    if (projectId != null) {
      final incomingIds = files.map((f) => f['id'] as int).toList();
      if (incomingIds.isEmpty) {
        await db.delete(
          'route_files',
          where: 'project_id = ? AND id > 0',
          whereArgs: [projectId],
        );
      } else {
        final placeholders = List.filled(incomingIds.length, '?').join(',');
        await db.delete(
          'route_files',
          where: 'project_id = ? AND id > 0 AND id NOT IN ($placeholders)',
          whereArgs: [projectId, ...incomingIds],
        );
      }
    }

    final batch = db.batch();
    for (final f in files) {
      batch.insert(
        'route_files',
        {
          'id': f['id'],
          'project_id': f['project_id'],
          'file_name': f['file_name'] ?? '',
          'description': f['description'],
          'sequence': f['sequence'] ?? 0,
          'last_sync': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getRouteFiles(int projectId) async {
    final db = await database;
    return await db.query(
      'route_files',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'sequence ASC',
    );
  }

  Future<void> deleteRouteFileLocal(int id) async {
    final db = await database;
    await db.delete('route_files', where: 'id = ?', whereArgs: [id]);
  }

  /// Guarda un archivo de ruta subido sin conexión (el archivo en sí se
  /// copia a [filePath], una ruta persistente), y lo encola para subirlo
  /// de verdad cuando vuelva la señal.
  Future<void> saveOfflineRouteFile({
    required int projectId,
    required String fileName,
    required String filePath,
    String? description,
  }) async {
    final db = await database;
    final tempId = -DateTime.now().millisecondsSinceEpoch;

    await db.insert('route_files', {
      'id': tempId,
      'project_id': projectId,
      'file_name': fileName,
      'description': description,
      'sequence': 0,
      'local_path': filePath,
      'last_sync': null,
    });

    await addPendingChange(
      model: 'route_file',
      action: 'upload',
      recordId: tempId,
      data: {
        'project_id': projectId.toString(),
        'file_name': fileName,
        'file_path': filePath,
        'description': description ?? '',
      },
    );
  }

  // ============ DOCUMENTOS DEL PROYECTO ============

  Future<void> saveProjectDocuments(List<Map<String, dynamic>> docs, {int? projectId}) async {
    final db = await database;

    if (projectId != null) {
      final incomingIds = docs.map((d) => d['id'] as int).toList();
      if (incomingIds.isEmpty) {
        await db.delete(
          'project_documents',
          where: 'project_id = ? AND id > 0',
          whereArgs: [projectId],
        );
      } else {
        final placeholders = List.filled(incomingIds.length, '?').join(',');
        await db.delete(
          'project_documents',
          where: 'project_id = ? AND id > 0 AND id NOT IN ($placeholders)',
          whereArgs: [projectId, ...incomingIds],
        );
      }
    }

    final batch = db.batch();
    for (final d in docs) {
      batch.insert(
        'project_documents',
        {
          'id': d['id'],
          'project_id': d['project_id'],
          'name': d['name'] ?? '',
          'mime_type': d['mime_type'],
          'file_size': d['file_size'],
          'create_date': d['create_date'],
          'last_sync': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getProjectDocuments(int projectId) async {
    final db = await database;
    return await db.query(
      'project_documents',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'create_date DESC',
    );
  }

  Future<void> deleteProjectDocumentLocal(int id) async {
    final db = await database;
    await db.delete('project_documents', where: 'id = ?', whereArgs: [id]);
  }

  /// Guarda un documento subido sin conexión, y lo encola para subirlo de
  /// verdad cuando vuelva la señal.
  Future<void> saveOfflineProjectDocument({
    required int projectId,
    required String fileName,
    required String filePath,
    String? mimeType,
    int? fileSize,
  }) async {
    final db = await database;
    final tempId = -DateTime.now().millisecondsSinceEpoch;

    await db.insert('project_documents', {
      'id': tempId,
      'project_id': projectId,
      'name': fileName,
      'mime_type': mimeType,
      'file_size': fileSize,
      'create_date': DateTime.now().toIso8601String(),
      'local_path': filePath,
      'last_sync': null,
    });

    await addPendingChange(
      model: 'ir.attachment.project',
      action: 'upload',
      recordId: tempId,
      data: {
        'project_id': projectId.toString(),
        'file_name': fileName,
        'file_path': filePath,
      },
    );
  }

  // ============ ADJUNTOS DE ETAPA ============

  Future<void> saveStageAttachments(List<Map<String, dynamic>> docs, {int? stageId}) async {
    final db = await database;

    if (stageId != null) {
      final incomingIds = docs.map((d) => d['id'] as int).toList();
      if (incomingIds.isEmpty) {
        await db.delete(
          'stage_attachments',
          where: 'stage_id = ? AND id > 0',
          whereArgs: [stageId],
        );
      } else {
        final placeholders = List.filled(incomingIds.length, '?').join(',');
        await db.delete(
          'stage_attachments',
          where: 'stage_id = ? AND id > 0 AND id NOT IN ($placeholders)',
          whereArgs: [stageId, ...incomingIds],
        );
      }
    }

    final batch = db.batch();
    for (final d in docs) {
      batch.insert(
        'stage_attachments',
        {
          'id': d['id'],
          'stage_id': d['stage_id'],
          'name': d['name'] ?? '',
          'mime_type': d['mime_type'],
          'file_size': d['file_size'],
          'create_date': d['create_date'],
          'last_sync': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getStageAttachments(int stageId) async {
    final db = await database;
    return await db.query(
      'stage_attachments',
      where: 'stage_id = ?',
      whereArgs: [stageId],
      orderBy: 'create_date DESC',
    );
  }

  Future<void> deleteStageAttachmentLocal(int id) async {
    final db = await database;
    await db.delete('stage_attachments', where: 'id = ?', whereArgs: [id]);
  }

  /// Guarda un adjunto de etapa subido sin conexión, y lo encola para
  /// subirlo de verdad cuando vuelva la señal.
  Future<void> saveOfflineStageAttachment({
    required int stageId,
    required String fileName,
    required String filePath,
    String? mimeType,
    int? fileSize,
  }) async {
    final db = await database;
    final tempId = -DateTime.now().millisecondsSinceEpoch;

    await db.insert('stage_attachments', {
      'id': tempId,
      'stage_id': stageId,
      'name': fileName,
      'mime_type': mimeType,
      'file_size': fileSize,
      'create_date': DateTime.now().toIso8601String(),
      'local_path': filePath,
      'last_sync': null,
    });

    await addPendingChange(
      model: 'ir.attachment.stage',
      action: 'upload',
      recordId: tempId,
      data: {
        'stage_id': stageId.toString(),
        'file_name': fileName,
        'file_path': filePath,
      },
    );
  }

  // ============ FOTOS DEL GRUPO ============

  Future<void> saveProjectPhotos(List<Map<String, dynamic>> photos, {int? projectId}) async {
    final db = await database;

    if (projectId != null) {
      final incomingIds = photos.map((p) => p['id'] as int).toList();
      if (incomingIds.isEmpty) {
        await db.delete(
          'project_photos',
          where: 'project_id = ? AND id > 0',
          whereArgs: [projectId],
        );
      } else {
        final placeholders = List.filled(incomingIds.length, '?').join(',');
        await db.delete(
          'project_photos',
          where: 'project_id = ? AND id > 0 AND id NOT IN ($placeholders)',
          whereArgs: [projectId, ...incomingIds],
        );
      }
    }

    final batch = db.batch();
    for (final p in photos) {
      batch.insert(
        'project_photos',
        {
          'id': p['id'],
          'project_id': p['project_id'],
          'name': p['name'] ?? '',
          'create_date': p['create_date'],
          'last_sync': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getProjectPhotos(int projectId) async {
    final db = await database;
    return await db.query(
      'project_photos',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'create_date DESC',
    );
  }

  Future<void> deleteProjectPhotoLocal(int id) async {
    final db = await database;
    await db.delete('project_photos', where: 'id = ?', whereArgs: [id]);
  }

  /// Guarda una foto subida sin conexión, y la encola para subirla de
  /// verdad cuando vuelva la señal.
  Future<void> saveOfflineProjectPhoto({
    required int projectId,
    required String fileName,
    required String filePath,
  }) async {
    final db = await database;
    final tempId = -DateTime.now().millisecondsSinceEpoch;

    await db.insert('project_photos', {
      'id': tempId,
      'project_id': projectId,
      'name': fileName,
      'create_date': DateTime.now().toIso8601String(),
      'local_path': filePath,
      'last_sync': null,
    });

    await addPendingChange(
      model: 'project.photo',
      action: 'upload',
      recordId: tempId,
      data: {
        'project_id': projectId.toString(),
        'file_name': fileName,
        'file_path': filePath,
      },
    );
  }

  // ============ PAPELERA ============

  /// Guarda una copia de un elemento borrado (documento, archivo de ruta
  /// o contacto) antes de borrarlo de verdad en Odoo, para poder
  /// restaurarlo más tarde. [extraData] guarda lo necesario para poder
  /// recrearlo según su tipo:
  /// - 'document': {'base64': ..., 'mime_type': ...}
  /// - 'route_file': {'base64': ..., 'description': ...}
  /// - 'contact': {'partner_id': ..., 'phone': ..., 'email': ...}
  Future<void> addTrashItem({
    required String type,
    required int projectId,
    required String name,
    required Map<String, dynamic> extraData,
  }) async {
    final db = await database;
    await db.insert('trash_items', {
      'type': type,
      'project_id': projectId,
      'name': name,
      'extra_data': jsonEncode(extraData),
      'deleted_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getTrashItems(int projectId) async {
    final db = await database;
    return await db.query(
      'trash_items',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'deleted_at DESC',
    );
  }

  Future<void> deleteTrashItemPermanently(int trashId) async {
    final db = await database;
    await db.delete('trash_items', where: 'id = ?', whereArgs: [trashId]);
  }

  /// Borra de la papelera (para siempre) todo lo que lleve más de un mes
  /// ahí. Se llama automáticamente al abrir la papelera y al arrancar la
  /// sincronización, así que no hace falta que el usuario haga nada.
  Future<void> purgeOldTrashItems() async {
    final db = await database;
    final cutoff = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
    final deletedCount = await db.delete(
      'trash_items',
      where: 'deleted_at < ?',
      whereArgs: [cutoff],
    );
    if (deletedCount > 0) {
      print('🗑️ Papelera: $deletedCount elemento(s) con más de 30 días borrados definitivamente');
    }
  }
}