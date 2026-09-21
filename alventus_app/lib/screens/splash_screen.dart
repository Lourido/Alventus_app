import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../models/project.dart';
import '../services/local_database_service.dart';
import '../services/odoo_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../utils/today_stage.dart';
import '../widgets/update/update_checker.dart';
import '../widgets/changelog/changelog_dialog.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'project_overview_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  final OdooService _odooService = OdooService();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    print('🔍 SplashScreen: initState ejecutado');

    // Crear animación de aparición del logo
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    // Iniciar la animación
    _animationController.forward();

    // Esperar a que el primer frame se renderice antes de verificar la sesión
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('🔍 SplashScreen: Primer frame renderizado');
      _checkSession();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkSession() async {
    print('🔍 _checkSession: Iniciando...');

    // Mostrar el logo durante 3 segundos para que se vea bien
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    // Verificar si hay conexión
    print('🔍 _checkSession: Verificando conectividad...');
    final hasConnection = await SyncService().checkConnectivity();
    print('🔍 _checkSession: Conexión = $hasConnection');

    if (!mounted) return;

    if (hasConnection) {
      print('🔍 _checkSession: Hay conexión, intentando auto-login...');
      final result = await _odooService.tryAutoLogin();
      print('🔍 _checkSession: Resultado auto-login = $result');

      if (!mounted) return;

      if (result['success'] == true) {
        print('🔍 _checkSession: Navegando a HomeScreen');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(
                uid: result['uid'],
                userName: result['username'] as String? ?? 'Usuario',),
          ),
        );
        _scheduleAppNotices(openTodayTrip: true);
        SyncService().fullSync();
      } else {
        print('🔍 _checkSession: Navegando a LoginScreen');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const LoginScreen(),
          ),
        );
        _scheduleAppNotices();
      }
    } else {
      print('🔍 _checkSession: No hay conexión, verificando credenciales locales...');
      final storageService = StorageService();
      final savedUid = await storageService.getUid();
      final savedPassword = await storageService.getPassword();
      print('🔍 _checkSession: savedUid = $savedUid, savedPassword = ${savedPassword != null ? "***" : "null"}');

      if (!mounted) return;

      if (savedUid != null && savedPassword != null) {
        print('🔍 _checkSession: Entrando en modo offline con UID $savedUid');

        // Obtener el nombre del usuario guardado
        final savedUserName = await storageService.getUserName();

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(
                uid: savedUid,
                userName: savedUserName ?? 'Usuario',
            ),
          ),
        );
        _scheduleAppNotices(openTodayTrip: true);
      } else {
        print('🔍 _checkSession: No hay credenciales guardadas, yendo a LoginScreen');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const LoginScreen(),
          ),
        );
        _scheduleAppNotices();
      }
    }
  }

  /// Comprueba (a) si hay una versión nueva de la app para descargar
  /// (solo tiene efecto en Android) y (b) si hay novedades sin ver desde
  /// la última vez que se abrió (todas las plataformas), y las muestra
  /// encima de lo que haya en pantalla en ese momento.
  ///
  /// Importante: se llama SIEMPRE después de que el propio
  /// Navigator.pushReplacement hacia HomeScreen/LoginScreen ya se haya
  /// hecho, nunca antes ni en paralelo con un timer independiente. Si se
  /// llamara antes (como hacía este método en una versión anterior, con
  /// su propio delay de 2 segundos corriendo a la vez que este método
  /// esperaba 3 segundos para navegar), el diálogo de Novedades podía
  /// quedar como la ruta más alta de la pila justo cuando el
  /// Navigator.pushReplacement de más abajo se disparaba -- y
  /// pushReplacement sustituye la ruta que esté arriba del todo en ese
  /// momento, no necesariamente la de la propia SplashScreen. Resultado
  /// real observado: el aviso de Novedades se cerraba solo al cabo de
  /// aproximadamente un segundo, sin que el usuario lo hubiera cerrado
  /// ni tocado nada. Llamando a esto después de navegar, ya no hay
  /// ningún pushReplacement pendiente que pueda "tragarse" el diálogo.
  ///
  /// Si [openTodayTrip] es true (solo cuando se ha entrado a la pantalla
  /// de inicio, no al login), al final se abre directamente el viaje que
  /// se esté haciendo hoy, si lo hay. Va lo ÚLTIMO a propósito: después
  /// de los avisos, para no abrir una pantalla por encima de un diálogo
  /// (que es justo el tipo de choque que hacía desaparecer el de
  /// Novedades).
  void _scheduleAppNotices({bool openTodayTrip = false}) {
    unawaited(Future(() async {
      // Pequeña espera para que la pantalla de destino (login u home) ya
      // esté totalmente montada antes de mostrar cualquier aviso encima.
      await Future.delayed(const Duration(milliseconds: 400));
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) {
        await checkAndPromptUpdate(ctx);
      }
      // Se comprueba después del aviso de actualización (si lo hay) y
      // no antes, para no mostrar dos diálogos encima uno del otro.
      final ctx2 = rootNavigatorKey.currentContext;
      if (ctx2 != null) {
        await checkAndShowChangelog(ctx2);
      }
      if (openTodayTrip) {
        await _openTripHappeningToday();
      }
    }));
  }

  /// Si hoy es uno de los días de algún viaje, lo abre directamente.
  ///
  /// La pantalla del viaje ya sabe, al abrirse, saludar ("¡Buen viaje!")
  /// y saltar a la etapa de hoy con sus tareas (ver
  /// _maybeJumpToTodayStage en project_overview_screen.dart); aquí solo
  /// falta llegar hasta ella sin que el usuario tenga que buscar el viaje.
  ///
  /// Se hace con los datos guardados en el teléfono, así que funciona
  /// igual sin cobertura. Respeta el interruptor de "Avisos de viaje" de
  /// la pantalla de inicio: si está apagado, no se abre nada solo.
  Future<void> _openTripHappeningToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('trip_notifications_enabled') ?? true;
      if (!enabled) return;

      final rows = await LocalDatabaseService().getProjects();

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      Map<String, dynamic>? todayTrip;
      DateTime? todayTripStart;
      var todayTripHasStage = false;

      for (final row in rows) {
        final id = row['id'];
        if (id is! int) continue;
        final start = _parseDay(row['date_start']);
        final end = _parseDay(row['date_end']);

        // Primero se mira si alguna ETAPA de este viaje es de hoy (por la
        // fecha de la etapa, que es lo fiable). Si no, vale también que
        // hoy caiga entre las fechas de inicio y fin del viaje.
        final hasStage = await findTodayStageName(
              projectId: id,
              tripStartIso: row['date_start']?.toString(),
              tripEndIso: row['date_end']?.toString(),
            ) !=
            null;
        final inRange = start != null &&
            end != null &&
            !today.isBefore(start) &&
            !today.isAfter(end);
        if (!hasStage && !inRange) continue;

        // Manda el viaje que tiene una etapa hoy; entre iguales, el que
        // empezó más tarde (el más "actual").
        final better = todayTrip == null ||
            (hasStage && !todayTripHasStage) ||
            (hasStage == todayTripHasStage &&
                start != null &&
                (todayTripStart == null || start.isAfter(todayTripStart)));
        if (better) {
          todayTrip = row;
          todayTripStart = start;
          todayTripHasStage = hasStage;
        }
      }

      if (todayTrip == null) return;

      final project = Project(
        id: todayTrip['id'] as int,
        name: todayTrip['name'] as String? ?? '',
        description: todayTrip['description'] as String?,
        userName: todayTrip['user_name'] as String?,
        partnerName: todayTrip['partner_name'] as String?,
        dateStart: todayTrip['date_start'] as String?,
        dateEnd: todayTrip['date_end'] as String?,
        taskCount: todayTrip['task_count'] as int? ?? 0,
      );

      rootNavigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => ProjectOverviewScreen(
            project: project,
            openTodayStage: true,
          ),
        ),
      );
    } catch (e) {
      // Esto es una comodidad, no algo imprescindible: si falla, el
      // usuario se queda en la pantalla de inicio como siempre.
      print('⚠️ No se pudo abrir el viaje de hoy: $e');
    }
  }

  /// Convierte una fecha guardada ("2026-09-21" o con hora) en el día,
  /// sin horas; null si no hay fecha o no se entiende.
  static DateTime? _parseDay(dynamic value) {
    if (value == null || value == false) return null;
    final s = value.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'false') return null;
    try {
      final d = DateTime.parse(s);
      return DateTime(d.year, d.month, d.day);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo desenfocado para evitar el flash en blanco al arrancar
          Image.asset(
            'assets/splash_background.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: Colors.white);
            },
          ),
          Center(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo real de Alventus
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/logo_alventus.png',
                        width: 200,
                        height: 200,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          print('❌ Error al cargar el logo: $error');
                          // Si hay error al cargar la imagen, mostrar un icono
                          return Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.business,
                              size: 100,
                              color: Colors.blue,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Nombre de la empresa
                    const Text(
                      'Alventus',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A3A5C),
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Subtítulo
                    const Text(
                      'Viajes',
                      style: TextStyle(
                        fontSize: 22,
                        color: Colors.grey,
                        letterSpacing: 4,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(height: 60),
                    // Indicador de carga
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Color(0xFF1A3A5C),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
          ),
        ],
      ),
    );
  }
}
