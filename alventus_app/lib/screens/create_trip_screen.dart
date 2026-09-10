import 'package:flutter/material.dart';
import 'select_trip_to_copy_screen.dart';
import 'create_trip_form_screen.dart';

class CreateTripScreen extends StatelessWidget {
  const CreateTripScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear Viaje'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '¿Cómo quieres crear el viaje?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A3A5C),
                ),
              ),
              const SizedBox(height: 48),

              // Botón 1: A partir de otro viaje
              _buildButton(
                context: context,
                label: 'A partir de otro viaje',
                icon: Icons.copy,
                color: const Color(0xFF1A3A5C),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SelectTripToCopyScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Botón 2: Desde cero
              _buildButton(
                context: context,
                label: 'Desde cero',
                icon: Icons.add_circle_outline,
                color: Colors.orange.shade700,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CreateTripFormScreen(
                        mode: CreateTripMode.fromScratch,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Botón 3: Crearlo desde el calendario
              _buildButton(
                context: context,
                label: 'Traer uno del calendario',
                icon: Icons.calendar_month,
                color: Colors.green.shade700,
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Próximamente'),
                      content: const Text(
                        'Todavía no implementado. Por favor, mándame un email '
                        'para incluirlo en la próxima actualización de la app. '
                        'Muchas gracias.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Entendido'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

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
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}