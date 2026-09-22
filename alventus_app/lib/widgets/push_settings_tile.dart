import 'package:flutter/material.dart';

import '../services/usage_log_service.dart';
import '../utils/push_notifications.dart';
import '../utils/app_messages.dart';

/// Sección "Avisos en el teléfono" del diálogo de avisos de la pantalla de
/// inicio: activar/desactivar las notificaciones de las tareas con hora de
/// inicio y mandar un aviso de prueba. Ver lib/utils/push_notifications.dart.
class PushSettingsTile extends StatefulWidget {
  const PushSettingsTile({super.key});

  @override
  State<PushSettingsTile> createState() => _PushSettingsTileState();
}

class _PushSettingsTileState extends State<PushSettingsTile> {
  String get _mensajeSinCobertura => Msg.of('sin_cobertura');

  PushStatus? _status;
  String? _publicKey;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final status = await PushNotifications.status();
    // La clave del servidor se carga ya, al abrir el diálogo: al pulsar
    // "Activar" tiene que estar lista, sin esperas (ver enableFromTap).
    String? key = _publicKey;
    if (status == PushStatus.notEnabled && key == null) {
      key = await PushNotifications.loadPublicKey();
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      _publicKey = key;
    });
  }

  void _show(String? text, {bool error = false}) {
    setState(() {
      _message = text;
      _messageIsError = error;
    });
  }

  // OJO: nada de await antes de enableFromTap (ver su comentario).
  void _onEnablePressed() {
    final key = _publicKey;
    if (key == null) {
      _show(_mensajeSinCobertura, error: true);
      return;
    }
    UsageLog.action('Activa los avisos en el teléfono');
    final pending = PushNotifications.enableFromTap(key);
    setState(() {
      _busy = true;
      _message = null;
    });
    pending.then((problem) async {
      if (!mounted) return;
      setState(() => _busy = false);
      if (problem == null) {
        _show('Avisos activados. Te llegarán aunque la app esté cerrada.');
      } else {
        _show(problem, error: true);
      }
      await _refresh();
    });
  }

  Future<void> _onDisablePressed() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    UsageLog.action('Desactiva los avisos en el teléfono');
    await PushNotifications.disable();
    if (!mounted) return;
    setState(() => _busy = false);
    _show('Avisos desactivados en este teléfono.');
    await _refresh();
  }

  Future<void> _onTestPressed() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    UsageLog.action('Prueba los avisos en el teléfono');
    final problem = await PushNotifications.sendTest();
    if (!mounted) return;
    setState(() => _busy = false);
    if (problem == null) {
      _show('Aviso de prueba enviado: debería llegarte en unos segundos.');
    } else {
      _show(problem, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final children = <Widget>[
      const Text(
        'Avisos en el teléfono',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      const SizedBox(height: 4),
      const Text(
        'Para las tareas con hora de inicio: te llega un aviso a la hora '
        'que elijas en cada tarea, aunque la app esté cerrada.',
        style: TextStyle(fontSize: 13),
      ),
      const SizedBox(height: 8),
    ];

    if (status == null) {
      children.add(const Center(child: CircularProgressIndicator()));
    } else {
      switch (status) {
        case PushStatus.unsupported:
          children.add(Text(
            Msg.of('este_navegador_no_puede_recibir_avisos'),
            style: const TextStyle(color: Colors.orange),
          ));
        case PushStatus.iosNeedsInstall:
          children.add(Text(
            Msg.of('en_el_iphone_los_avisos_solo_funcionan'),
            style: const TextStyle(color: Colors.orange),
          ));
        case PushStatus.denied:
          children.add(Text(
            Msg.of('has_bloqueado_los_avisos_para_recibirlos_permitelo'),
            style: const TextStyle(color: Colors.orange),
          ));
        case PushStatus.notEnabled:
          children.add(FilledButton.icon(
            onPressed: _busy ? null : _onEnablePressed,
            icon: const Icon(Icons.notifications_active),
            label: const Text('Activar avisos'),
          ));
        case PushStatus.enabled:
          children.addAll([
            const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 6),
                Expanded(child: Text('Avisos activados en este teléfono')),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _onTestPressed,
                  child: const Text('Probar'),
                ),
                TextButton(
                  onPressed: _busy ? null : _onDisablePressed,
                  child: const Text('Desactivar'),
                ),
              ],
            ),
          ]);
      }
    }

    if (_busy) {
      children.add(const Padding(
        padding: EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(),
      ));
    }
    if (_message != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          _message!,
          style: TextStyle(color: _messageIsError ? Colors.red : Colors.green.shade700),
        ),
      ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}
