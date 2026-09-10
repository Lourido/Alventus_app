import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../config/odoo_config.dart';
import 'storage_service.dart';

class OdooService {
  // Singleton: todas las pantallas usan la misma instancia
  OdooService._internal() {
    _dio.options.baseUrl = OdooConfig.baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.headers = {
      'Content-Type': 'application/json',
    };
  }

  static final OdooService _instance = OdooService._internal();

  factory OdooService() => _instance;

  final Dio _dio = Dio();
  final StorageService _storage = StorageService();

  // Datos de la sesión actual
  int? _uid;
  String? _username;

  int? get uid => _uid;
  String? get username => _username;
  bool get isAuthenticated => _uid != null;

  /// Autentica al usuario en Odoo
  Future<Map<String, dynamic>> authenticate({
    required String login,
    required String password,
    bool saveSession = true,
  }) async {
    try {
      final response = await _dio.post(
        OdooConfig.jsonRpcEndpoint,
        data: {
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'common',
            'method': 'authenticate',
            'args': [
              OdooConfig.database,
              login,
              password,
              {},
            ],
          },
          'id': 1,
        },
      );

      if (response.statusCode == 200) {
        final result = response.data['result'];

        if (result != null && result != false && result is int) {
          _uid = result;
          _username = login;

          // Guardar sesión si se solicita
          if (saveSession) {
            await _storage.saveSession(
              username: login,
              password: password,
              uid: result,
            );
          }

          return {
            'success': true,
            'uid': result,
            'username': login,
          };
        } else {
          return {
            'success': false,
            'error': 'Usuario o contraseña incorrectos',
          };
        }
      } else {
        return {
          'success': false,
          'error': 'Error del servidor: ${response.statusCode}',
        };
      }
    } on DioException catch (e) {
      String errorMessage;

      if (e.type == DioExceptionType.connectionTimeout) {
        errorMessage = 'Tiempo de espera agotado. Verifica tu conexión.';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMessage = 'No se puede conectar con el servidor.';
      } else if (e.response != null) {
        errorMessage = 'Error del servidor: ${e.response?.statusCode}';
      } else {
        errorMessage = 'Error de conexión: ${e.message}';
      }

      return {
        'success': false,
        'error': errorMessage,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Error inesperado: $e',
      };
    }
  }

  /// Obtiene el nombre real del usuario desde Odoo
  Future<String?> fetchUserName(int uid) async {
    try {
      final result = await executeKw(
        model: 'res.users',
        method: 'read',
        args: [
          [uid],
          ['name'],
        ],
      );

      if (result['success'] == true) {
        final List<dynamic> records = result['result'] as List<dynamic>;
        if (records.isNotEmpty) {
          final record = records[0] as Map<String, dynamic>;
          return record['name']?.toString();
        }
      }
      return null;
    } catch (e) {
      print('❌ Error al obtener nombre de usuario: $e');
      return null;
    }
  }

  /// Intenta autenticar con credenciales guardadas (auto-login)
  Future<Map<String, dynamic>> tryAutoLogin() async {
    try {
      final storage = StorageService();
      final session = await storage.getSession();

      if (session == null) {
        print('⚠️ tryAutoLogin: No hay sesión guardada o el storage falló');
        return {
          'success': false,
          'error': 'No hay sesión guardada',
        };
      }

      final uid = session['uid'];
      final password = session['password'];

      if (uid == null || password == null) {
        print('⚠️ tryAutoLogin: Sesión incompleta');
        return {
          'success': false,
          'error': 'Sesión incompleta',
        };
      }

      _uid = uid as int;

      // Obtener el nombre guardado
      var userName = await storage.getUserName();

      // Si no hay nombre guardado o es "Usuario", intentar obtenerlo desde Odoo
      if (userName == null || userName.isEmpty || userName == 'Usuario') {
        try {
          final realName = await fetchUserName(uid);
          if (realName != null && realName.isNotEmpty) {
            userName = realName;
            await storage.saveUserName(realName);
            print('✅ Nombre de usuario obtenido de Odoo: $realName');
          }
        } catch (e) {
          // Si falla (por ejemplo, sin conexión), simplemente no actualiza el nombre
          print('⚠️ No se pudo obtener nombre de Odoo (posible sin conexión): $e');
        }
      }

      return {
        'success': true,
        'uid': uid,
        'username': userName ?? 'Usuario',
      };
    } catch (e) {
      print('❌ tryAutoLogin: Excepción: $e');
      return {
        'success': false,
        'error': 'Error al intentar auto-login: $e',
      };
    }
  }

  /// Cierra la sesión y borra las credenciales
  Future<void> logout() async {
    _uid = null;
    _username = null;
    await _storage.clearSession();
  }
  /// Recupera la contraseña guardada (necesaria para llamadas RPC)
  Future<String?> _getPassword() async {
    final session = await _storage.getSession();
    return session?['password'];
  }

  /// Método genérico para ejecutar cualquier llamada RPC a Odoo
  Future<Map<String, dynamic>> executeKw({
    required String model,
    required String method,
    required List<dynamic> args,
    Map<String, dynamic> kwargs = const {},
  }) async {
    if (_uid == null) {
      print('❌ executeKw: No hay sesión activa (_uid es null)');
      return {
        'success': false,
        'error': 'No hay sesión activa',
      };
    }

    final password = await _getPassword();
    if (password == null) {
      print('❌ executeKw: No se encontró la contraseña guardada');
      return {
        'success': false,
        'error': 'No se encontró la contraseña guardada',
      };
    }

    // LOG: mostrar qué vamos a enviar
    print('🔍 executeKw - Enviando petición:');
    print('   UID: $_uid');
    print('   Modelo: $model');
    print('   Método: $method');
    print('   Args: $args');
    print('   Kwargs: $kwargs');

    try {
      final requestData = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'service': 'object',
          'method': 'execute_kw',
          'args': [
            OdooConfig.database,
            _uid,
            password,
            model,
            method,
            args,
            kwargs,
          ],
        },
        'id': 2,
      };

      final response = await _dio.post(
        OdooConfig.jsonRpcEndpoint,
        data: requestData,
      );

      print('🔍 executeKw - Respuesta recibida (status ${response.statusCode}):');
      print('   ${response.data}');

      if (response.statusCode == 200) {
        if (response.data.containsKey('error')) {
          final errorObj = response.data['error'] as Map;
          final errorData = errorObj['data'] as Map?;

          // Odoo mete el mensaje de negocio concreto (p.ej. de un
          // raise UserError("...")) en error.data.message. El campo
          // error.message de más arriba suele ser genérico ("Odoo Server
          // Error") y no dice nada útil.
          final specificMessage = errorData?['message']?.toString();
          final genericMessage = errorObj['message']?.toString() ?? 'Error en Odoo';
          final exceptionName = errorData?['name']?.toString() ?? '';

          final displayMessage = (specificMessage != null && specificMessage.trim().isNotEmpty)
              ? specificMessage
              : genericMessage;

          // Se imprime el mensaje concreto ANTES del traceback completo,
          // para que no se pierda entre líneas si el traceback es largo.
          print('❌ executeKw - Error de Odoo ($exceptionName):');
          print('   Mensaje: $displayMessage');
          print('   Traceback completo: ${errorData?['debug'] ?? ''}');

          return {
            'success': false,
            'error': displayMessage,
          };
        }

        return {
          'success': true,
          'result': response.data['result'],
        };
      } else {
        print('❌ executeKw - Status code no 200: ${response.statusCode}');
        return {
          'success': false,
          'error': 'Error del servidor: ${response.statusCode}',
        };
      }
    } on DioException catch (e) {
      print('❌ executeKw - DioException: ${e.message}');
      print('   Response: ${e.response?.data}');
      return {
        'success': false,
        'error': 'Error de conexión: ${e.message}',
      };
    } catch (e) {
      print('❌ executeKw - Excepción: $e');
      return {
        'success': false,
        'error': 'Error inesperado: $e',
      };
    }
  }

  /// Obtiene la lista de contactos/clientes
  Future<Map<String, dynamic>> fetchPartners({int limit = 50}) async {
    return executeKw(
      model: 'res.partner',
      method: 'search_read',
      args: [
        [
          ['is_company', '=', false], // Solo personas, no empresas
        ],
      ],
      kwargs: {
        'fields': ['name', 'email', 'phone', 'city', 'comment'],
        'limit': limit,
        'order': 'name asc',
      },
    );
  }
  /// Obtiene la lista de proyectos
  /// Obtiene la lista de proyectos.
  ///
  /// [invisible]: si es `false` (lo habitual), solo trae los viajes NO
  /// quitados. Si es `true`, trae solo los quitados (para la pantalla de
  /// "Recuperar viaje"). Si se deja en `null`, trae todos sin filtrar.
  /// Obtiene la lista de proyectos.
  ///
  /// [invisible]: si es `false` (lo habitual), solo trae los viajes NO
  /// quitados. Si es `true`, trae solo los quitados (para la pantalla de
  /// "Recuperar viaje"). Si se deja en `null`, trae todos sin filtrar.
  /// [userId]: si se indica, solo trae los viajes cuyo responsable
  /// (user_id) sea ese usuario.
  Future<Map<String, dynamic>> fetchProjects({int limit = 50, bool? invisible, int? userId}) async {
    final domain = <dynamic>[];
    if (invisible != null) {
      domain.add(['invisible', '=', invisible]);
    }
    if (userId != null) {
      domain.add(['user_id', '=', userId]);
    }

    return executeKw(
      model: 'project.project',
      method: 'search_read',
      args: [domain],
      kwargs: {
        'fields': ['name', 'description', 'user_id', 'partner_id', 'date_start', 'date', 'invisible'],
        'limit': limit,
        'order': 'name asc',
      },
    );
  }

  /// Cuenta las tareas de un proyecto específico
  Future<Map<String, dynamic>> countTasks(int projectId) async {
    return executeKw(
      model: 'project.task',
      method: 'search_count',
      args: [
        [
          ['project_id', '=', projectId],
        ],
      ],
    );
  }

  /// Obtiene las tareas de un proyecto específico
  Future<Map<String, dynamic>> fetchTasks(int projectId, {int limit = 100}) async {
    return executeKw(
      model: 'project.task',
      method: 'search_read',
      args: [
        [
          ['project_id', '=', projectId],
        ],
      ],
      kwargs: {
        'fields': ['name', 'description', 'project_id', 'stage_id', 'date_deadline', 'priority', 'fecha_desde', 'fecha_hasta', 'sequence'],
        'limit': limit,
        'order': 'fecha_desde asc',
      },
    );
  }

  /// Cambia el orden (campo sequence) de una tarea, para poder
  /// reorganizarlas manualmente dentro de una etapa.
  Future<Map<String, dynamic>> updateTaskSequence({
    required int taskId,
    required int sequence,
  }) async {
    return executeKw(
      model: 'project.task',
      method: 'write',
      args: [
        [taskId],
        {'sequence': sequence},
      ],
    );
  }

  /// Crea una nueva tarea en un proyecto
  Future<Map<String, dynamic>> createTask({
    required int projectId,
    required String name,
    String? description,
    String? deadline,
    int? stageId,
  }) async {
    final Map<String, dynamic> values = {
      'project_id': projectId,
      'name': name,
    };

    if (description != null && description.isNotEmpty) {
      values['description'] = description;
    }
    if (deadline != null && deadline.isNotEmpty) {
      values['date_deadline'] = deadline;
    }
    if (stageId != null) {
      values['stage_id'] = stageId;
    }

    return executeKw(
      model: 'project.task',
      method: 'create',
      args: [values],
    );
  }

  /// Actualiza una tarea existente
  Future<Map<String, dynamic>> updateTask({
    required int taskId,
    String? name,
    String? description,
    String? deadline,
    String? priority,
    String? fechaDesde,
    String? fechaHasta,
  }) async {
    final Map<String, dynamic> values = {};

    if (name != null) values['name'] = name;
    if (description != null) values['description'] = description;
    if (deadline != null) values['date_deadline'] = deadline;
    if (priority != null) values['priority'] = priority;
    if (fechaDesde != null) values['fecha_desde'] = fechaDesde;
    if (fechaHasta != null) values['fecha_hasta'] = fechaHasta;

    if (values.isEmpty) {
      return {'success': false, 'error': 'No hay cambios para guardar'};
    }

    return executeKw(
      model: 'project.task',
      method: 'write',
      args: [
        [taskId],
        values,
      ],
    );
  }

  /// Borra una tarea
  Future<Map<String, dynamic>> deleteTask(int taskId) async {
    return executeKw(
      model: 'project.task',
      method: 'unlink',
      args: [
        [taskId],
      ],
    );
  }
  /// Obtiene una tarea específica por su ID
  Future<Map<String, dynamic>> fetchTask(int taskId) async {
    return executeKw(
      model: 'project.task',
      method: 'search_read',
      args: [
        [['id', '=', taskId]],
      ],
      kwargs: {
        'fields': ['name', 'description', 'project_id', 'stage_id', 'date_deadline', 'priority'],
        'limit': 1,
      },
    );
  }
  /// Obtiene los adjuntos de una tarea
  Future<Map<String, dynamic>> fetchTaskAttachments(int taskId) async {
    return executeKw(
      model: 'ir.attachment',
      method: 'search_read',
      args: [
        [
          ['res_model', '=', 'project.task'],
          ['res_id', '=', taskId],
        ],
      ],
      kwargs: {
        'fields': ['name', 'mimetype', 'file_size', 'create_date'],
        'order': 'create_date desc',
      },
    );
  }

  /// Sube un archivo adjunto a una tarea
  Future<Map<String, dynamic>> uploadAttachment({
    required int taskId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      // Codificar los bytes ya recibidos en base64
      final base64Data = base64Encode(bytes);

      return await executeKw(
        model: 'ir.attachment',
        method: 'create',
        args: [
          {
            'name': fileName,
            'res_model': 'project.task',
            'res_id': taskId,
            'datas': base64Data,
          },
        ],
      );
    } catch (e) {
      return {
        'success': false,
        'error': 'Error al subir el archivo: $e',
      };
    }
  }

  /// Borra un archivo adjunto
  Future<Map<String, dynamic>> deleteAttachment(int attachmentId) async {
    return executeKw(
      model: 'ir.attachment',
      method: 'unlink',
      args: [
        [attachmentId],
      ],
    );
  }
  /// Descarga el contenido de un adjunto (devuelve base64)
  Future<Map<String, dynamic>> downloadAttachment(int attachmentId) async {
    return executeKw(
      model: 'ir.attachment',
      method: 'read',
      args: [
        [attachmentId],
        ['datas'],
      ],
    );
  }
  /// Crea un nuevo proyecto (viaje)
  Future<Map<String, dynamic>> createProject({
    required String name,
    String? dateStart,
    String? dateEnd,
  }) async {
    try {
      final args = <String, dynamic>{
        'name': name,
      };

      if (dateStart != null) args['date_start'] = dateStart;
      if (dateEnd != null) args['date'] = dateEnd;

      final result = await executeKw(
        model: 'project.project',
        method: 'create',
        args: [args],
      );

      if (result['success'] == true) {
        print('✅ Proyecto creado: id=${result['result']}, name=$name');
        return {
          'success': true,
          'project_id': result['result'],
        };
      }

      return {'success': false, 'error': result['error']};
    } catch (e) {
      print('❌ Error al crear proyecto: $e');
      return {'success': false, 'error': 'Error al crear proyecto: $e'};
    }
  }

  /// Crea una etapa (stage) para un proyecto
  Future<Map<String, dynamic>> createStage({
    required String name,
    required int sequence,
  }) async {
    try {
      final result = await executeKw(
        model: 'project.task.type',
        method: 'create',
        args: [{
          'name': name,
          'sequence': sequence,
        }],
      );

      if (result['success'] == true) {
        print('✅ Etapa creada: id=${result['result']}, name=$name');
        return {
          'success': true,
          'stage_id': result['result'],
        };
      }

      return {'success': false, 'error': result['error']};
    } catch (e) {
      print('❌ Error al crear etapa: $e');
      return {'success': false, 'error': 'Error al crear etapa: $e'};
    }
  }

  /// Crea una tarea con fechas específicas
  Future<Map<String, dynamic>> createTaskWithDates({
    required int projectId,
    required String name,
    int? stageId,
    String? fechaDesde,
    String? fechaHasta,
    String? description,
  }) async {
    try {
      final args = <String, dynamic>{
        'project_id': projectId,
        'name': name,
      };

      if (stageId != null) args['stage_id'] = stageId;
      if (fechaDesde != null) args['fecha_desde'] = fechaDesde;
      if (fechaHasta != null) args['fecha_hasta'] = fechaHasta;
      if (description != null) args['description'] = description;

      final result = await executeKw(
        model: 'project.task',
        method: 'create',
        args: [args],
      );

      if (result['success'] == true) {
        print('✅ Tarea creada: id=${result['result']}, name=$name');
        return {
          'success': true,
          'task_id': result['result'],
        };
      }

      return {'success': false, 'error': result['error']};
    } catch (e) {
      print('❌ Error al crear tarea: $e');
      return {'success': false, 'error': 'Error al crear tarea: $e'};
    }
  }

  /// Obtiene todas las tareas de un proyecto con sus fechas
  Future<Map<String, dynamic>> fetchAllTasksForCopy(int projectId) async {
    try {
      final result = await executeKw(
        model: 'project.task',
        method: 'search_read',
        args: [
          [
            ['project_id', '=', projectId],
          ],
        ],
        kwargs: {
          'fields': ['name', 'description', 'stage_id', 'fecha_desde', 'fecha_hasta', 'priority', 'date_deadline'],
          'limit': 500,
        },
      );

      return result;
    } catch (e) {
      print('❌ Error al obtener tareas para copiar: $e');
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  /// Duplica un viaje ejecutando el asistente de Odoo
  /// project.duplicate.wizard (acción "Duplicar" del módulo de proyectos),
  /// que se encarga de: crear el nuevo proyecto, ajustar fechas de etapas
  /// y tareas según el desplazamiento de días, copiar adjuntos de tareas
  /// y del proyecto, copiar archivos de ruta y copiar los contactos de
  /// referencia — todo del lado de Odoo, en una sola operación.
  Future<Map<String, dynamic>> copyProject({
    required int sourceProjectId,
    required String sourceProjectName,
    required DateTime newStartDate,
    String? newName,
  }) async {
    try {
      final newProjectName = (newName != null && newName.trim().isNotEmpty)
          ? newName.trim()
          : '$sourceProjectName (copia)';

      print('🔄 Duplicando proyecto $sourceProjectId mediante project.duplicate.wizard...');

      // 1. Crear el registro del wizard con los datos elegidos por el usuario.
      final createWizardResult = await executeKw(
        model: 'project.duplicate.wizard',
        method: 'create',
        args: [
          {
            'project_id': sourceProjectId,
            'new_start_date': _formatDateOnly(newStartDate),
            'new_name': newProjectName,
          },
        ],
      );

      if (createWizardResult['success'] != true) {
        return {'success': false, 'error': createWizardResult['error']};
      }

      final wizardId = createWizardResult['result'] as int;

      // 2. Ejecutar la acción de duplicado del wizard.
      final actionResult = await executeKw(
        model: 'project.duplicate.wizard',
        method: 'action_duplicate',
        args: [
          [wizardId],
        ],
      );

      if (actionResult['success'] != true) {
        return {'success': false, 'error': actionResult['error']};
      }

      // action_duplicate() devuelve una acción de ventana (act_window) con
      // el id del proyecto nuevo en 'res_id'.
      final actionData = actionResult['result'];
      int? newProjectId;
      if (actionData is Map) {
        final resId = actionData['res_id'];
        if (resId is int) newProjectId = resId;
      }

      if (newProjectId == null) {
        return {
          'success': false,
          'error': 'No se pudo determinar el proyecto duplicado (respuesta inesperada del wizard)',
        };
      }

      print('✅ Proyecto duplicado correctamente: nuevo id=$newProjectId');
      return {
        'success': true,
        'project_id': newProjectId,
        'project_name': newProjectName,
      };
    } catch (e) {
      print('❌ Error al duplicar el proyecto: $e');
      return {'success': false, 'error': 'Error al duplicar el proyecto: $e'};
    }
  }

  /// Formatea un DateTime al formato de Odoo
  String _formatDateTime(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:00';
  }

  /// Formatea una fecha (sin hora) al formato que espera un campo Date de
  /// Odoo: YYYY-MM-DD.
  String _formatDateOnly(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  // ===========================================================================
  // CONTACTOS DE REFERENCIA DEL PROYECTO (project.project.reference_contact_ids)
  // ===========================================================================

  /// Obtiene los contactos de referencia ya enlazados a un proyecto.
  ///
  /// Al ser un campo Many2many, primero hay que leer los ids enlazados en
  /// el proyecto, y luego pedir los datos de esos contactos a res.partner.
  Future<Map<String, dynamic>> fetchProjectReferenceContacts(int projectId) async {
    try {
      final projectResult = await executeKw(
        model: 'project.project',
        method: 'read',
        args: [
          [projectId],
          ['reference_contact_ids'],
        ],
      );

      if (projectResult['success'] != true) return projectResult;

      final records = projectResult['result'] as List<dynamic>;
      if (records.isEmpty) {
        return {'success': true, 'result': <dynamic>[]};
      }

      final contactIds = (records[0] as Map<String, dynamic>)['reference_contact_ids'] as List<dynamic>;
      if (contactIds.isEmpty) {
        return {'success': true, 'result': <dynamic>[]};
      }

      return await executeKw(
        model: 'res.partner',
        method: 'search_read',
        args: [
          [
            ['id', 'in', contactIds],
          ],
        ],
        kwargs: {
          'fields': ['name', 'email', 'phone', 'city', 'comment'],
          'order': 'name asc',
        },
      );
    } catch (e) {
      print('❌ Error al obtener contactos de referencia: $e');
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  /// Enlaza un contacto existente de res.partner al proyecto como
  /// contacto de referencia (no lo crea, solo añade el enlace).
  Future<Map<String, dynamic>> linkReferenceContact({
    required int projectId,
    required int partnerId,
  }) async {
    return executeKw(
      model: 'project.project',
      method: 'write',
      args: [
        [projectId],
        {
          'reference_contact_ids': [
            [4, partnerId, 0], // comando Odoo: (4, id) = enlazar existente
          ],
        },
      ],
    );
  }

  /// Quita el enlace de un contacto de referencia del proyecto. No borra
  /// el contacto de res.partner, solo el enlace con este proyecto.
  Future<Map<String, dynamic>> unlinkReferenceContact({
    required int projectId,
    required int partnerId,
  }) async {
    return executeKw(
      model: 'project.project',
      method: 'write',
      args: [
        [projectId],
        {
          'reference_contact_ids': [
            [3, partnerId, 0], // comando Odoo: (3, id) = quitar enlace
          ],
        },
      ],
    );
  }

  /// Crea un contacto nuevo en res.partner y lo enlaza directamente al
  /// proyecto como contacto de referencia, en una sola llamada.
  Future<Map<String, dynamic>> createAndLinkReferenceContact({
    required int projectId,
    required String name,
    String? phone,
    String? email,
    String? comment,
  }) async {
    try {
      final values = <String, dynamic>{'name': name};
      if (phone != null && phone.isNotEmpty) values['phone'] = phone;
      if (email != null && email.isNotEmpty) values['email'] = email;
      if (comment != null && comment.isNotEmpty) values['comment'] = comment;

      final createResult = await executeKw(
        model: 'res.partner',
        method: 'create',
        args: [values],
      );

      if (createResult['success'] != true) return createResult;

      final newPartnerId = createResult['result'] as int;

      final linkResult = await linkReferenceContact(
        projectId: projectId,
        partnerId: newPartnerId,
      );

      if (linkResult['success'] != true) return linkResult;

      return {'success': true, 'partner_id': newPartnerId};
    } catch (e) {
      print('❌ Error al crear y enlazar contacto: $e');
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  // ===========================================================================
  // ARCHIVOS DE RUTA DEL PROYECTO (project.route.file)
  // ===========================================================================

  /// Obtiene los archivos de ruta de un proyecto (sin el contenido binario,
  /// solo metadatos: nombre, descripción, orden).
  Future<Map<String, dynamic>> fetchProjectRouteFiles(int projectId) async {
    return executeKw(
      model: 'project.route.file',
      method: 'search_read',
      args: [
        [
          ['project_id', '=', projectId],
        ],
      ],
      kwargs: {
        'fields': ['file_name', 'description', 'sequence'],
        'order': 'sequence asc, id asc',
      },
    );
  }

  /// Descarga el contenido binario (base64) de un archivo de ruta concreto.
  Future<Map<String, dynamic>> downloadRouteFileData(int routeFileId) async {
    return executeKw(
      model: 'project.route.file',
      method: 'read',
      args: [
        [routeFileId],
        ['file_data', 'file_name'],
      ],
    );
  }

  /// Sube un nuevo archivo de ruta (GPX, KML, KMZ...) a un proyecto.
  Future<Map<String, dynamic>> uploadRouteFile({
    required int projectId,
    required String fileName,
    required Uint8List bytes,
    String? description,
  }) async {
    try {
      final base64Data = base64Encode(bytes);

      final values = <String, dynamic>{
        'project_id': projectId,
        'file_name': fileName,
        'file_data': base64Data,
      };
      if (description != null && description.isNotEmpty) {
        values['description'] = description;
      }

      return await executeKw(
        model: 'project.route.file',
        method: 'create',
        args: [values],
      );
    } catch (e) {
      print('❌ Error al subir archivo de ruta: $e');
      return {'success': false, 'error': 'Error al subir el archivo: $e'};
    }
  }

  /// Borra un archivo de ruta.
  Future<Map<String, dynamic>> deleteRouteFile(int routeFileId) async {
    return executeKw(
      model: 'project.route.file',
      method: 'unlink',
      args: [
        [routeFileId],
      ],
    );
  }

  // ===========================================================================
  // DOCUMENTOS DEL PROYECTO (adjuntos genéricos ir.attachment, p.ej. PDFs)
  // ===========================================================================

  /// Obtiene los adjuntos genéricos del proyecto (fichas, seguros, PDFs...),
  /// igual que [fetchTaskAttachments] pero a nivel de proyecto en vez de
  /// tarea.
  Future<Map<String, dynamic>> fetchProjectAttachments(int projectId) async {
    return executeKw(
      model: 'ir.attachment',
      method: 'search_read',
      args: [
        [
          ['res_model', '=', 'project.project'],
          ['res_id', '=', projectId],
        ],
      ],
      kwargs: {
        'fields': ['name', 'mimetype', 'file_size', 'create_date'],
        'order': 'create_date desc',
      },
    );
  }

  /// Sube un documento genérico (p.ej. un PDF) al proyecto.
  Future<Map<String, dynamic>> uploadProjectAttachment({
    required int projectId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      final base64Data = base64Encode(bytes);

      return await executeKw(
        model: 'ir.attachment',
        method: 'create',
        args: [
          {
            'name': fileName,
            'res_model': 'project.project',
            'res_id': projectId,
            'datas': base64Data,
          },
        ],
      );
    } catch (e) {
      return {
        'success': false,
        'error': 'Error al subir el archivo: $e',
      };
    }
  }

  // ===========================================================================
  // ADJUNTOS DE ETAPA (día del viaje, project.task.type)
  // ===========================================================================

  /// Obtiene los adjuntos genéricos de una etapa, igual que
  /// [fetchTaskAttachments]/[fetchProjectAttachments] pero a nivel de
  /// etapa (project.task.type) en vez de tarea o proyecto.
  Future<Map<String, dynamic>> fetchStageAttachments(int stageId) async {
    return executeKw(
      model: 'ir.attachment',
      method: 'search_read',
      args: [
        [
          ['res_model', '=', 'project.task.type'],
          ['res_id', '=', stageId],
        ],
      ],
      kwargs: {
        'fields': ['name', 'mimetype', 'file_size', 'create_date'],
        'order': 'create_date desc',
      },
    );
  }

  /// Sube un archivo adjunto a una etapa.
  Future<Map<String, dynamic>> uploadStageAttachment({
    required int stageId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      final base64Data = base64Encode(bytes);

      return await executeKw(
        model: 'ir.attachment',
        method: 'create',
        args: [
          {
            'name': fileName,
            'res_model': 'project.task.type',
            'res_id': stageId,
            'datas': base64Data,
          },
        ],
      );
    } catch (e) {
      return {
        'success': false,
        'error': 'Error al subir el archivo: $e',
      };
    }
  }

  /// Resuelve el id real en Odoo de una etapa a partir de su nombre (la
  /// app solo guarda el nombre localmente). Devuelve null si no hay
  /// conexión o si no se encuentra.
  Future<int?> resolveStageId({
    required int projectId,
    required String stageName,
  }) async {
    final stagesResult = await fetchProjectStages(projectId);
    if (stagesResult['success'] == true) {
      final stages = (stagesResult['result'] as List<dynamic>).cast<Map<String, dynamic>>();
      for (final stage in stages) {
        if ((stage['name']?.toString() ?? '') == stageName) {
          return stage['id'] as int?;
        }
      }
    }
    return null;
  }

  /// Cambia el nombre de un viaje/proyecto.
  Future<Map<String, dynamic>> updateProjectName({
    required int projectId,
    required String newName,
  }) async {
    return executeKw(
      model: 'project.project',
      method: 'write',
      args: [
        [projectId],
        {'name': newName},
      ],
    );
  }

  /// Obtiene los usuarios de Odoo que pertenecen al grupo de seguridad
  /// "Guías" (búsqueda flexible por si el nombre exacto varía con o sin
  /// tilde), para poder compartir un viaje con uno de ellos.
  Future<Map<String, dynamic>> fetchGuideUsers() async {
    try {
      final groupsResult = await executeKw(
        model: 'res.groups',
        method: 'search_read',
        args: [
          [
            ['name', 'ilike', 'Guia'],
          ],
        ],
        kwargs: {
          'fields': ['id', 'name'],
        },
      );

      if (groupsResult['success'] != true) return groupsResult;

      final groups = (groupsResult['result'] as List<dynamic>).cast<Map<String, dynamic>>();
      if (groups.isEmpty) {
        return {
          'success': false,
          'error': 'No se encontró ningún grupo de seguridad "Guías" en Odoo',
        };
      }

      final groupIds = groups.map((g) => g['id'] as int).toList();

      return await executeKw(
        model: 'res.users',
        method: 'search_read',
        args: [
          [
            ['groups_id', 'in', groupIds],
          ],
        ],
        kwargs: {
          'fields': ['name', 'login', 'email'],
          'order': 'name asc',
        },
      );
    } catch (e) {
      print('❌ Error al obtener usuarios guías: $e');
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  /// Cambia el gestor del proyecto (campo user_id de project.project), es
  /// decir, quién lo verá como responsable al entrar en la app.
  Future<Map<String, dynamic>> updateProjectManager({
    required int projectId,
    required int userId,
  }) async {
    return executeKw(
      model: 'project.project',
      method: 'write',
      args: [
        [projectId],
        {'user_id': userId},
      ],
      kwargs: {
        // Igual que hace project.duplicate.wizard: desactiva el
        // seguimiento/notificaciones por correo al cambiar el gestor,
        // para que no falle si no hay un servidor de correo saliente
        // configurado en Odoo.
        'context': {
          'tracking_disable': true,
          'mail_notify_force_send': false,
          'mail_create_nosubscribe': true,
          'mail_create_nolog': true,
        },
      },
    );
  }

  /// "Quita" un viaje sin borrarlo de verdad de Odoo: le reasigna como
  /// responsable al usuario Admin_Borrado, que se usa como papelera. La
  /// visibilidad de estos viajes (que dejen de verse en listados, informes,
  /// etc.) se gestiona con reglas del lado de Odoo, no aquí.
  /// "Quita" un viaje sin borrarlo de Odoo: marca el campo `invisible` a
  /// true. Se puede deshacer con [restoreProject] (pantalla "Recuperar
  /// viaje").
  Future<Map<String, dynamic>> markProjectAsRemoved({required int projectId}) async {
    return executeKw(
      model: 'project.project',
      method: 'write',
      args: [
        [projectId],
        {'invisible': true},
      ],
      kwargs: {
        'context': {
          'tracking_disable': true,
          'mail_notify_force_send': false,
          'mail_create_nosubscribe': true,
          'mail_create_nolog': true,
        },
      },
    );
  }

  /// Recupera un viaje previamente quitado: marca `invisible` a false.
  Future<Map<String, dynamic>> restoreProject({required int projectId}) async {
    return executeKw(
      model: 'project.project',
      method: 'write',
      args: [
        [projectId],
        {'invisible': false},
      ],
      kwargs: {
        'context': {
          'tracking_disable': true,
          'mail_notify_force_send': false,
          'mail_create_nosubscribe': true,
          'mail_create_nolog': true,
        },
      },
    );
  }

  /// Crea un viaje nuevo ejecutando el asistente de Odoo
  /// project.create.with.tasks.wizard: crea el proyecto y una etapa por
  /// cada día del viaje (más la etapa "Día 0 - Antes de salir"), todo
  /// del lado de Odoo.
  Future<Map<String, dynamic>> createProjectWithTasksWizard({
    required String name,
    required DateTime startDate,
    required int numDays,
  }) async {
    try {
      // 1. Crear el registro del wizard con los datos del formulario.
      final createWizardResult = await executeKw(
        model: 'project.create.with.tasks.wizard',
        method: 'create',
        args: [
          {
            'name': name,
            'start_date': _formatDateOnly(startDate),
            'num_days': numDays,
          },
        ],
      );

      if (createWizardResult['success'] != true) return createWizardResult;

      final wizardId = createWizardResult['result'] as int;

      // 2. Ejecutar la acción de creación del wizard.
      final actionResult = await executeKw(
        model: 'project.create.with.tasks.wizard',
        method: 'action_create',
        args: [
          [wizardId],
        ],
      );

      if (actionResult['success'] != true) return actionResult;

      // action_create() devuelve una acción de ventana (act_window) con
      // el id del proyecto nuevo en 'res_id'.
      final actionData = actionResult['result'];
      int? newProjectId;
      if (actionData is Map) {
        final resId = actionData['res_id'];
        if (resId is int) newProjectId = resId;
      }

      if (newProjectId == null) {
        return {
          'success': false,
          'error': 'No se pudo determinar el viaje creado (respuesta inesperada del wizard)',
        };
      }

      print('✅ Viaje creado con el wizard: nuevo id=$newProjectId');
      return {
        'success': true,
        'project_id': newProjectId,
        'project_name': name,
      };
    } catch (e) {
      print('❌ Error al crear el viaje con el wizard: $e');
      return {'success': false, 'error': 'Error al crear el viaje: $e'};
    }
  }

  /// Obtiene las etapas (días) reales de un proyecto en Odoo, con su id
  /// numérico (necesario para poder asignar tareas a una etapa concreta).
  Future<Map<String, dynamic>> fetchProjectStages(int projectId) async {
    return executeKw(
      model: 'project.task.type',
      method: 'search_read',
      args: [
        [
          ['project_ids', '=', projectId],
        ],
      ],
      kwargs: {
        'fields': ['name', 'sequence', 'description'],
        'order': 'sequence asc',
      },
    );
  }

  /// Crea una tarea asignándola a la etapa indicada por su NOMBRE (no por
  /// id), resolviendo primero cuál es el id real de esa etapa en Odoo.
  /// Se usa así (por nombre) en vez de pedir directamente el id porque la
  /// app solo tiene guardado el nombre de la etapa localmente (para poder
  /// funcionar también sin conexión); el id real se resuelve aquí, en el
  /// momento de hablar con Odoo, tanto si la tarea se crea al momento
  /// como si se crea offline y se sincroniza más tarde.
  Future<Map<String, dynamic>> createTaskInStage({
    required int projectId,
    required String name,
    String? description,
    String? deadline,
    String? stageName,
    String? fechaDesde,
    String? fechaHasta,
  }) async {
    int? stageId;

    if (stageName != null && stageName.isNotEmpty && stageName != 'Sin etapa') {
      final stagesResult = await fetchProjectStages(projectId);
      if (stagesResult['success'] == true) {
        final stages = (stagesResult['result'] as List<dynamic>).cast<Map<String, dynamic>>();
        for (final stage in stages) {
          if ((stage['name']?.toString() ?? '') == stageName) {
            stageId = stage['id'] as int?;
            break;
          }
        }
      }
    }

    if (fechaDesde != null || fechaHasta != null) {
      return createTaskWithDates(
        projectId: projectId,
        name: name,
        description: description,
        stageId: stageId,
        fechaDesde: fechaDesde,
        fechaHasta: fechaHasta,
      );
    }

    return createTask(
      projectId: projectId,
      name: name,
      description: description,
      deadline: deadline,
      stageId: stageId,
    );
  }

  /// Reasigna un conjunto de tareas a otra etapa (cambia su stage_id a
  /// todas de golpe). Se usa para intercambiar el contenido de dos
  /// etapas: se llama dos veces, una por cada dirección.
  Future<Map<String, dynamic>> reassignTasksStage({
    required List<int> taskIds,
    required int newStageId,
  }) async {
    if (taskIds.isEmpty) return {'success': true};
    return executeKw(
      model: 'project.task',
      method: 'write',
      args: [taskIds, {'stage_id': newStageId}],
    );
  }

  /// Borra un conjunto de tareas de golpe.
  Future<Map<String, dynamic>> deleteTasks(List<int> taskIds) async {
    if (taskIds.isEmpty) return {'success': true};
    return executeKw(
      model: 'project.task',
      method: 'unlink',
      args: [taskIds],
    );
  }

  /// Borra una etapa (project.task.type).
  Future<Map<String, dynamic>> deleteStage(int stageId) async {
    return executeKw(
      model: 'project.task.type',
      method: 'unlink',
      args: [
        [stageId],
      ],
    );
  }

  /// Cambia el nombre de una etapa.
  Future<Map<String, dynamic>> renameStage({
    required int stageId,
    required String newName,
  }) async {
    return executeKw(
      model: 'project.task.type',
      method: 'write',
      args: [
        [stageId],
        {'name': newName},
      ],
    );
  }

  /// Actualiza la descripción de una etapa.
  Future<Map<String, dynamic>> updateStageDescription({
    required int stageId,
    required String description,
  }) async {
    return executeKw(
      model: 'project.task.type',
      method: 'write',
      args: [
        [stageId],
        {'description': description},
      ],
    );
  }

  /// Crea una nueva etapa y la enlaza a un proyecto.
  Future<Map<String, dynamic>> createStageForProject({
    required int projectId,
    required String name,
    int sequence = 0,
  }) async {
    return executeKw(
      model: 'project.task.type',
      method: 'create',
      args: [
        {
          'name': name,
          'project_ids': [
            [4, projectId, 0],
          ],
          'sequence': sequence,
        },
      ],
    );
  }

  /// Actualiza la fecha de fin (campo "date") de un proyecto, para
  /// reflejar que el viaje se ha alargado o acortado un día.
  Future<Map<String, dynamic>> updateProjectEndDate({
    required int projectId,
    required DateTime newEndDate,
  }) async {
    return executeKw(
      model: 'project.project',
      method: 'write',
      args: [
        [projectId],
        {'date': _formatDateOnly(newEndDate)},
      ],
    );
  }

  // ===========================================================================
  // FOTOS DE GRUPO DEL VIAJE (project.photo)
  // ===========================================================================

  /// Obtiene las fotos de grupo de un proyecto (solo metadatos, sin el
  /// contenido binario).
  Future<Map<String, dynamic>> fetchProjectPhotos(int projectId) async {
    return executeKw(
      model: 'project.photo',
      method: 'search_read',
      args: [
        [
          ['project_id', '=', projectId],
        ],
      ],
      kwargs: {
        'fields': ['name', 'create_date'],
        'order': 'create_date desc',
      },
    );
  }

  /// Descarga el contenido binario (base64) de una foto de grupo concreta.
  Future<Map<String, dynamic>> downloadProjectPhotoData(int photoId) async {
    return executeKw(
      model: 'project.photo',
      method: 'read',
      args: [
        [photoId],
        ['image', 'name'],
      ],
    );
  }

  /// Sube una foto de grupo nueva. En vez de replicar el asistente
  /// project.photo.upload.wizard (que en la interfaz web enlaza primero
  /// adjuntos temporales al propio wizard antes de confirmar), se crea
  /// directamente el registro project.photo — es el mismo resultado final
  /// que produce el wizard al pulsar "Subir", pero en una sola llamada.
  Future<Map<String, dynamic>> uploadProjectPhoto({
    required int projectId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      final base64Data = base64Encode(bytes);

      return await executeKw(
        model: 'project.photo',
        method: 'create',
        args: [
          {
            'project_id': projectId,
            'name': fileName,
            'image': base64Data,
          },
        ],
      );
    } catch (e) {
      return {'success': false, 'error': 'Error al subir la foto: $e'};
    }
  }

  /// Borra una foto de grupo.
  Future<Map<String, dynamic>> deleteProjectPhoto(int photoId) async {
    return executeKw(
      model: 'project.photo',
      method: 'unlink',
      args: [
        [photoId],
      ],
    );
  }

  /// Obtiene las etapas de VARIOS proyectos de golpe (una sola consulta),
  /// solo con nombre e ids de proyecto a los que pertenece cada una. Se
  /// usa para calcular el número de días real de cada viaje (contando
  /// sus etapas "Día N"), en vez de depender de las fechas date_start/date
  /// del proyecto, que pueden quedarse desactualizadas.
  Future<Map<String, dynamic>> fetchStagesForProjects(List<int> projectIds) async {
    if (projectIds.isEmpty) return {'success': true, 'result': <dynamic>[]};

    return executeKw(
      model: 'project.task.type',
      method: 'search_read',
      args: [
        [
          ['project_ids', 'in', projectIds],
        ],
      ],
      kwargs: {
        'fields': ['name', 'project_ids'],
      },
    );
  }
}