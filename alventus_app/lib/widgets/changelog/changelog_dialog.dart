import 'package:flutter/material.dart';
import '../../changelog.dart';
import '../../services/changelog_service.dart';

/// Comprueba si hay novedades que el usuario todavía no ha visto en
/// este dispositivo y, si las hay, se las enseña en un diálogo. Pensado
/// para llamarse una vez al entrar en la app (ver splash_screen.dart).
Future<void> checkAndShowChangelog(BuildContext context) async {
  final entries = await ChangelogService.getUnseenEntries();
  if (entries.isEmpty) return;
  if (!context.mounted) return;

  // Solo se dan por vistas las novedades si el usuario ha pulsado de
  // verdad el botón "Entendido" (que es quien devuelve true). Antes se
  // marcaban como vistas en cuanto el diálogo se cerraba por cualquier
  // motivo -- y si otra cosa lo cerraba por su cuenta (pasó con la
  // navegación de la pantalla de carga), las novedades se quedaban
  // marcadas como leídas sin que nadie las hubiera llegado a leer, y ya
  // no se volvían a enseñar nunca.
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _ChangelogDialog(entries: entries),
  );

  if (confirmed == true) {
    await ChangelogService.markAllSeen();
  }
}

class _ChangelogDialog extends StatelessWidget {
  final List<ChangelogEntry> entries;

  const _ChangelogDialog({required this.entries});

  @override
  Widget build(BuildContext context) {
    // No se puede cerrar tocando fuera ni con el botón "atrás": el
    // usuario tiene que leerlo y pulsar el botón "Entendido" a propósito.
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Novedades'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in entries) ...[
                  Text(
                    entry.date,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  for (final change in entry.changes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  '),
                          Expanded(child: Text(change)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
}
