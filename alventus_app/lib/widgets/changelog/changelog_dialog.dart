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

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _ChangelogDialog(entries: entries),
  );

  await ChangelogService.markAllSeen();
}

class _ChangelogDialog extends StatelessWidget {
  final List<ChangelogEntry> entries;

  const _ChangelogDialog({required this.entries});

  @override
  Widget build(BuildContext context) {
    // No se puede cerrar tocando fuera ni con el botón "atrás": el
    // usuario tiene que leerlo y pulsar el botón "Leído" a propósito.
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Leído'),
          ),
        ],
      ),
    );
  }
}
