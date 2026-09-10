import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/odoo_service.dart';
import '../services/local_database_service.dart';
import '../services/sync_service.dart';
import '../models/project.dart';

/// Papelera: documentos, archivos de ruta y contactos que se han borrado
/// desde la pantalla del viaje, con opción de restaurarlos.
///
/// Los documentos y archivos de ruta se restauran creando uno NUEVO en
/// Odoo con el mismo contenido (con un id distinto al original, ya que
/// el original se borró de verdad); los contactos se restauran
/// simplemente volviendo a vincularlos, ya que quitar un contacto nunca
/// lo borra de Odoo.
class TrashScreen extends StatefulWidget {
  final Project project;

  const TrashScreen({super.key, required this.project});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final OdooService _odooService = OdooService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final SyncService _syncService = SyncService();

  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  final Set<int> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    await _localDb.purgeOldTrashItems();
    final rows = await _localDb.getTrashItems(widget.project.id);
    if (!mounted) return;
    setState(() {
      _items = rows;
      _isLoading = false;
    });
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'document':
        return Icons.description;
      case 'route_file':
        return Icons.route;
      case 'contact':
        return Icons.person;
      default:
        return Icons.delete;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'document':
        return 'Documento';
      case 'route_file':
        return 'Archivo de ruta';
      case 'contact':
        return 'Contacto';
      default:
        return type;
    }
  }

  Future<void> _restore(Map<String, dynamic> item) async {
    final trashId = item['id'] as int;
    final type = item['type'] as String;
    final name = item['name'] as String;
    final extraData = jsonDecode(item['extra_data'] as String) as Map<String, dynamic>;

    final hasConnection = await _syncService.checkConnectivity();
    if (!hasConnection) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se necesita conexión a internet para restaurar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _busyIds.add(trashId));

    Map<String, dynamic> result;

    try {
      switch (type) {
        case 'contact':
          final partnerId = extraData['partner_id'] as int;
          result = await _odooService.linkReferenceContact(
            projectId: widget.project.id,
            partnerId: partnerId,
          );
          break;

        case 'document':
        case 'route_file':
          // Los bytes ya vienen en base64 desde la papelera: se pasan
          // directamente a Odoo, sin pasar por un archivo temporal (que
          // además no funcionaría en el navegador).
          final base64Data = extraData['base64'] as String;
          final bytes = base64Decode(base64Data);

          if (type == 'document') {
            result = await _odooService.uploadProjectAttachment(
              projectId: widget.project.id,
              fileName: name,
              bytes: bytes,
            );
          } else {
            result = await _odooService.uploadRouteFile(
              projectId: widget.project.id,
              fileName: name,
              bytes: bytes,
              description: extraData['description'] as String?,
            );
          }
          break;

        default:
          result = {'success': false, 'error': 'Tipo desconocido'};
      }
    } catch (e) {
      result = {'success': false, 'error': 'Error al restaurar: $e'};
    }

    if (!mounted) return;

    setState(() => _busyIds.remove(trashId));

    if (result['success'] == true) {
      await _localDb.deleteTrashItemPermanently(trashId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$name" restaurado'), backgroundColor: Colors.green),
      );
      _loadItems();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error']?.toString() ?? 'No se pudo restaurar'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteForever(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vaciar elemento'),
        content: Text(
          '¿Borrar definitivamente "${item['name']}" de la papelera? '
          'Ya no se podrá restaurar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Borrar definitivamente'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _localDb.deleteTrashItemPermanently(item['id'] as int);
    if (!mounted) return;
    _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Papelera')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('La papelera está vacía'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final trashId = item['id'] as int;
                    final isBusy = _busyIds.contains(trashId);

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: Icon(_iconFor(item['type'] as String), color: Colors.grey),
                        title: Text(item['name']?.toString() ?? ''),
                        subtitle: Text(_typeLabel(item['type'] as String)),
                        trailing: isBusy
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.restore, color: Colors.green),
                                    tooltip: 'Restaurar',
                                    onPressed: () => _restore(item),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                                    tooltip: 'Borrar definitivamente',
                                    onPressed: () => _deleteForever(item),
                                  ),
                                ],
                              ),
                      ),
                    );
                  },
                ),
    );
  }
}
