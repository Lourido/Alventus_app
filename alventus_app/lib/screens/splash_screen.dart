import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';
import '../services/odoo_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../widgets/update/update_checker.dart';
import 'login_screen.dart';
import 'home_screen.dart';

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

    // Comprueba en segundo plano si hay una versión nueva de la app
    // (solo tiene efecto en Android). No se espera a que termine, para
    // no retrasar el arranque: el aviso aparece cuando responda el
    // servidor, sobre lo que sea que haya en pantalla en ese momento
    // (login u home), gracias al navigator global.
    unawaited(Future(() async {
      await Future.delayed(const Duration(seconds: 2));
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) {
        await checkAndPromptUpdate(ctx);
      }
    }));

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
        SyncService().fullSync();
      } else {
        print('🔍 _checkSession: Navegando a LoginScreen');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const LoginScreen(),
          ),
        );
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
      } else {
        print('🔍 _checkSession: No hay credenciales guardadas, yendo a LoginScreen');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const LoginScreen(),
          ),
        );
      }
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