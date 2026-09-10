import 'package:flutter/material.dart';
import '../../services/update_service.dart';

/// Comprueba en segundo plano si hay una versión nueva de la app y, si
/// la hay, muestra un diálogo para descargarla e instalarla. Pensado
/// para llamarse una vez al arrancar la app (ver splash_screen.dart);
/// en iOS no hace nada, [UpdateService.checkForUpdate] siempre devuelve
/// null ahí.
Future<void> checkAndPromptUpdate(BuildContext context) async {
  final info = await UpdateService.instance.checkForUpdate();
  if (info == null) return;
  if (!context.mounted) return;

  await showDialog(
    context: context,
    // Si la actualización es obligatoria, no se puede cerrar tocando
    // fuera ni con "Más tarde": hay que actualizar para seguir.
    barrierDismissible: !info.mandatory,
    builder: (dialogContext) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  Future<void> _startUpdate() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });

    final filePath = await UpdateService.instance.downloadApk(
      widget.info.apkUrl,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );

    if (!mounted) return;

    if (filePath == null) {
      setState(() {
        _downloading = false;
        _error = 'No se pudo descargar la actualización. Comprueba tu conexión e inténtalo de nuevo.';
      });
      return;
    }

    await UpdateService.instance.installApk(filePath);

    // A partir de aquí toma el relevo el instalador del sistema (tanto
    // si el usuario acaba instalando como si lo cancela ahí), así que
    // cerramos este diálogo.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final versionLabel = widget.info.versionName.isNotEmpty ? ' (${widget.info.versionName})' : '';

    return PopScope(
      canPop: !widget.info.mandatory,
      child: AlertDialog(
        title: Text('Nueva versión disponible$versionLabel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.info.notes != null && widget.info.notes!.trim().isNotEmpty) ...[
              Text(widget.info.notes!.trim()),
              const SizedBox(height: 16),
            ],
            if (_downloading) ...[
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              const SizedBox(height: 8),
              Text('${(_progress * 100).toStringAsFixed(0)}%'),
            ] else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else
              const Text('¿Quieres descargarla e instalarla ahora?'),
          ],
        ),
        actions: _downloading
            ? const []
            : [
                if (!widget.info.mandatory)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Más tarde'),
                  ),
                ElevatedButton(
                  onPressed: _startUpdate,
                  child: Text(_error == null ? 'Actualizar ahora' : 'Reintentar'),
                ),
              ],
      ),
    );
  }
}
