import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/splash_screen.dart';
import 'services/sync_service.dart';

void main() {
  // Inicializar el servicio de sincronización
  SyncService().init();

  runApp(const MyApp());
}

/// Navigator global: permite mostrar el diálogo de "hay una versión
/// nueva" (ver update_checker.dart) esté la app donde esté en ese
/// momento (splash, login u home), sin depender del context de una
/// pantalla concreta que puede haber dejado de existir para cuando el
/// servidor responde.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Alventus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      // Español de España: además de traducir los diálogos del sistema
      // (selector de fecha/hora, etc.), hace que el calendario empiece
      // la semana en lunes en vez de domingo.
      locale: const Locale('es', 'ES'),
      supportedLocales: const [Locale('es', 'ES')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SplashScreen(),
    );
  }
}