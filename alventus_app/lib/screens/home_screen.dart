import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sync_service.dart';
import '../services/odoo_service.dart';
import 'login_screen.dart';
import 'project_list_screen.dart';
import 'create_trip_screen.dart';
import 'share_trip_screen.dart';
import 'remove_trip_screen.dart';
import 'recover_trip_screen.dart';

class HomeScreen extends StatelessWidget {
  final int uid;
  final String userName;

  const HomeScreen({super.key, required this.uid, this.userName = 'Usuario'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alventus & Años Luz'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Avisos de viaje',
            onPressed: () => _showNotificationSettingsDialog(context),
          ),
          // Indicador de estado de conexión
          StreamBuilder<bool>(
            stream: _getConnectivityStream(),
            initialData: SyncService().isOnline,
            builder: (context, snapshot) {
              final isOnline = snapshot.data ?? true;
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Icon(
                  isOnline ? Icons.cloud_done : Icons.cloud_off,
                  color: isOnline ? Colors.green : Colors.orange,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo desenfocado (igual que la pantalla de bienvenida/splash)
          Image.asset(
            'assets/splash_background.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: Colors.white);
            },
          ),
          SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Saludo con el nombre del usuario
                const Text(
                  '¡Aúpa pues!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A3A5C),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  userName,
                  textAlign: TextAlign.center,
                  // Blanco (el gris no se lee bien sobre el fondo con
                  // imagen) y con una tipografía que simula escritura a
                  // mano, para darle un toque más personal al saludo.
                  style: GoogleFonts.caveat(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    shadows: const [
                      Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1)),
                    ],
                  ),
                ),
                const SizedBox(height: 48),

                // Botón 1: Guiar Viaje
                _buildButton(
                  context: context,
                  label: 'guiar viaje / editar',
                  icon: Icons.map,
                  color: const Color(0xFFA7C7E7),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProjectListScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Botón 2: Crear viaje
                _buildButton(
                  context: context,
                  label: 'crear viaje',
                  icon: Icons.add_circle_outline,
                  color: const Color(0xFFB5EAD7),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateTripScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Botón 3: Compartir viaje
                _buildButton(
                  context: context,
                  label: 'compartir viaje',
                  icon: Icons.share,
                  color: const Color(0xFFC7CEEA),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ShareTripScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Botón 4: Quitar viaje
                _buildButton(
                  context: context,
                  label: 'quitar viaje',
                  icon: Icons.delete_outline,
                  color: const Color(0xFFFFB7B2),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RemoveTripScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Botón 5: Recuperar viaje
                _buildButton(
                  context: context,
                  label: 'recuperar viaje',
                  icon: Icons.restore,
                  color: const Color(0xFFFFDAC1),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RecoverTripScreen(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 32),

                // Información de contacto (debajo del último botón)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade600,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _ContactLine(label: 'diseño', value: 'alfonso lourido'),
                      SizedBox(height: 6),
                      _ContactLine(label: 'quejas', value: 'yo_paso@con_cariño.es'),
                      SizedBox(height: 6),
                      _ContactLine(label: 'sugerencias', value: 'lourido2003@yahoo.es', isEmailLink: true),
                      SizedBox(height: 6),
                      _ContactLine(label: 'versión', value: '0.0.0'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
        ],
      ),
    );
  }

  // Helper para construir botones con estilo consistente
  Widget _buildButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          // Con fondos pastel (claros), el texto blanco pierde contraste;
          // se usa un tono oscuro para que siga siendo legible.
          foregroundColor: const Color(0xFF33475B),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  // Stream para escuchar cambios de conectividad
  Stream<bool> _getConnectivityStream() async* {
    while (true) {
      await Future.delayed(const Duration(seconds: 2));
      yield SyncService().isOnline;
    }
  }

  /// Muestra un diálogo con un interruptor para activar/desactivar los
  /// avisos que aparecen al abrir un viaje (el de "queda poco para
  /// salir" y el de "hoy toca esta etapa"). Se guarda en el propio
  /// teléfono con shared_preferences.
  Future<void> _showNotificationSettingsDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('trip_notifications_enabled') ?? true;

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        var currentValue = enabled;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Avisos de viaje'),
              content: SwitchListTile(
                title: const Text('Avisar al abrir un viaje'),
                subtitle: const Text(
                  'Muestra un mensaje y va directo a la etapa del día cuando '
                  'toca, y avisa cuando falta poco para salir.',
                ),
                value: currentValue,
                onChanged: (value) {
                  setDialogState(() => currentValue = value);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await prefs.setBool('trip_notifications_enabled', currentValue);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Pide confirmación y, si el usuario acepta, cierra la sesión: borra
  /// las credenciales guardadas (modo offline incluido) y vuelve a la
  /// pantalla de login, para que la próxima vez haya que volver a
  /// escribir usuario y contraseña.
  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          '¿Seguro que quieres cerrar sesión? La próxima vez que abras la '
          'app tendrás que volver a iniciar sesión con tu usuario y '
          'contraseña.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await OdooService().logout();

    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }
}

class _ContactLine extends StatelessWidget {
  final String label;
  final String value;
  // Si es true, [value] es una dirección de email: al tocarla se abre la
  // app de correo del dispositivo con esa dirección ya puesta en "Para".
  final bool isEmailLink;

  const _ContactLine({
    required this.label,
    required this.value,
    this.isEmailLink = false,
  });

  Future<void> _openMailApp(BuildContext context) async {
    final uri = Uri(scheme: 'mailto', path: value);
    final opened = await launchUrl(uri);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir el correo. Escríbenos a $value')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final valueText = Text(
      value,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        color: Colors.white,
        fontSize: 13,
        decoration: isEmailLink ? TextDecoration.underline : TextDecoration.none,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$label:',
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: isEmailLink
                ? InkWell(
                    onTap: () => _openMailApp(context),
                    child: valueText,
                  )
                : valueText,
          ),
        ),
      ],
    );
  }
}