import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/splash_screen.dart';
import 'services/sync_service.dart';
import 'services/usage_log_service.dart';
import 'utils/app_messages.dart';

void main() async {
  // Hay que inicializar el "puente" con Android/iOS ANTES de usar nada
  // que hable con el sistema (la base de datos local y el detector de
  // conexión lo hacen). Sin esto, esas llamadas fallan en el arranque
  // con "defaultBinaryMessenger was accessed before the binding was
  // initialized"; y como pasaba antes de runApp, la app se quedaba sin
  // pintar nada: pantalla en blanco y sin más explicación.
  WidgetsFlutterBinding.ensureInitialized();

  // Textos de los avisos y errores que se pueden personalizar desde Odoo
  // (ver utils/app_messages.dart). Se cargan los que hubiera guardados en
  // el teléfono; si falla, se usan los de siempre.
  await Msg.load();

  // Si algo falla dentro de la app, queda apuntado en el registro de uso
  // (Viajes > Registro de uso de la app, en Odoo) además de salir por la
  // consola como siempre.
  final errorAnterior = FlutterError.onError;
  FlutterError.onError = (details) {
    try {
      UsageLog.error(
        'Fallo en la app',
        detail: details.exceptionAsString(),
      );
    } catch (_) {}
    errorAnterior?.call(details);
  };

  // Primero se pinta la app y después se arranca la sincronización, y
  // además protegida: pase lo que pase al inicializarla, la pantalla
  // tiene que salir igualmente. Es preferible entrar en la app con la
  // sincronización renqueando que no poder entrar.
  runApp(const MyApp());

  try {
    SyncService().init();
  } catch (e) {
    print('⚠️ No se pudo inicializar la sincronización: $e');
  }
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