import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/web_file_opener.dart';
import '../services/odoo_service.dart';
import '../services/sync_service.dart';
import '../services/local_database_service.dart';
import '../models/project.dart';
import '../models/route_file.dart';
import '../models/reference_contact.dart';
import 'stages_screen.dart';
import 'stage_task_matrix_screen.dart';
import 'stage_tasks_screen.dart';
import 'trash_screen.dart';

/// Pantalla de aterrizaje al entrar en un viaje: datos generales del
/// proyecto, contactos de referencia, archivos de ruta (GPX/KML/KMZ) y
/// documentos (PDFs, fichas, seguros...). Desde aquí se accede al detalle
/// de etapas y tareas ([StagesScreen]).
class ProjectOverviewScreen extends StatefulWidget {
  final Project project;

  const ProjectOverviewScreen({super.key, required this.project});

  @override
  State<ProjectOverviewScreen> createState() => _ProjectOverviewScreenState();
}

class _ProjectOverviewScreenState extends State<ProjectOverviewScreen> {
  final OdooService _odooService = OdooService();
  final SyncService _syncService = SyncService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = true;
  bool _isOffline = false;
  String? _errorMessage;

  List<ReferenceContact> _contacts = [];
  List<RouteFile> _routeFiles = [];
  List<Map<String, dynamic>> _documents = [];
  List<Map<String, dynamic>> _photos = [];

  // Nombre mostrado en pantalla; empieza igual que widget.project.name pero
  // se actualiza localmente al renombrar, sin depender de recargar toda
  // la pantalla.
  late String _displayName = widget.project.name;

  // Fechas mostradas en pantalla; se refrescan en cada _loadAll() para
  // que el número de días se actualice tras añadir/quitar etapas (que
  // cambian date_start/date en Odoo), en vez de quedarse con el valor
  // que tenía el Project al abrir esta pantalla.
  String? _dateStart;
  String? _dateEnd;

  @override
  void initState() {
    super.initState();
    _dateStart = widget.project.dateStart;
    _dateEnd = widget.project.dateEnd;
    _loadAll().then((_) {
      _refreshTripSummary();
      _maybeJumpToTodayStage();
    });
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final hasConnection = await _syncService.checkConnectivity();

      if (hasConnection) {
        // Con conexión: sincroniza todo con Odoo (guarda en la base local
        // de paso) antes de leer, para tener los datos más frescos.
        await Future.wait([
          _syncService.syncReferenceContacts(widget.project.id),
          _syncService.syncRouteFiles(widget.project.id),
          _syncService.syncProjectDocuments(widget.project.id),
          _syncService.syncProjectPhotos(widget.project.id),
          _odooService.executeKw(
            model: 'project.project',
            method: 'read',
            args: [
              [widget.project.id],
              ['date_start', 'date'],
            ],
          ).then((datesResult) {
            if (datesResult['success'] == true) {
              final records = datesResult['result'] as List<dynamic>;
              if (records.isNotEmpty) {
                final rec = records[0] as Map<String, dynamic>;
                final rawStart = rec['date_start'];
                final rawEnd = rec['date'];
                _dateStart = (rawStart == false || rawStart == null) ? null : rawStart.toString();
                _dateEnd = (rawEnd == false || rawEnd == null) ? null : rawEnd.toString();
              }
            }
          }),
        ]);
      }

      // Sin conexión o con ella, siempre se lee de la base de datos local:
      // así la pantalla se ve igual en ambos casos, y los elementos
      // creados sin conexión (con id temporal negativo) también aparecen.
      final contactRows = await _localDb.getReferenceContacts(widget.project.id);
      final routeRows = await _localDb.getRouteFiles(widget.project.id);
      final documentRows = await _localDb.getProjectDocuments(widget.project.id);
      final photoRows = await _localDb.getProjectPhotos(widget.project.id);

      if (!mounted) return;

      setState(() {
        _isOffline = !hasConnection;
        _contacts = contactRows.map((row) => ReferenceContact.fromJson(row)).toList();
        _routeFiles = routeRows.map((row) => RouteFile.fromJson(row)).toList();
        _documents = documentRows;
        _photos = photoRows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error al cargar los datos del viaje: $e';
        _isLoading = false;
      });
    }
  }

  /// Si hoy es uno de los días del viaje, navega directamente a la etapa
  /// de ese día. La primera vez que se abre este viaje en el día de hoy,
  /// muestra además un mensaje de bienvenida ("¡Aúpa! ¡Buen viaje!").
  Future<void> _maybeJumpToTodayStage() async {
    final prefs = await SharedPreferences.getInstance();
    final notificationsEnabled = prefs.getBool('trip_notifications_enabled') ?? true;
    if (!notificationsEnabled) return;

    final startStr = _dateStart;
    final endStr = _dateEnd;
    if (startStr == null || endStr == null) return;

    DateTime start, end;
    try {
      start = DateTime.parse(startStr);
      end = DateTime.parse(endStr);
    } catch (_) {
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);

    // Caso 1: hoy es uno de los días del propio viaje.
    if (!today.isBefore(startDay) && !today.isAfter(endDay)) {
      final dayNumber = today.difference(startDay).inDays + 1;
      final stageName = 'Día $dayNumber - '
          '${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}';

      // Mensaje de bienvenida solo la primera vez que se abre hoy (se
      // recuerda con una clave por viaje + fecha de hoy).
      final todayKey = '${today.year}-${today.month}-${today.day}';
      final greetedKey = 'trip_greeted_${widget.project.id}_$todayKey';
      final alreadyGreeted = prefs.getBool(greetedKey) ?? false;

      if (!mounted) return;

      if (!alreadyGreeted) {
        await prefs.setBool(greetedKey, true);
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            content: const Text(
              '¡Aúpa! ¡Buen viaje!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            actions: [
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('¡Vamos!'),
                ),
              ),
            ],
          ),
        );
      }

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StageTasksScreen(
            project: widget.project,
            stageName: stageName,
          ),
        ),
      ).then((_) {
        if (mounted) _refreshTripSummary();
      });
      return;
    }

    // Caso 2: faltan 7 días o menos para empezar el viaje. Solo se avisa
    // una vez por viaje (no una vez al día, como el caso anterior).
    final daysUntilStart = startDay.difference(today).inDays;
    if (daysUntilStart > 0 && daysUntilStart <= 7) {
      final soonGreetedKey = 'trip_soon_greeted_${widget.project.id}';
      final alreadyGreetedSoon = prefs.getBool(soonGreetedKey) ?? false;
      if (alreadyGreetedSoon) return;

      await prefs.setBool(soonGreetedKey, true);

      // Busca el nombre real de la etapa "Día 0" (puede llevar texto
      // extra, como "Día 0 - Antes de salir").
      final stagesResult = await _odooService.fetchProjectStages(widget.project.id);
      String? dayZeroName;
      if (stagesResult['success'] == true) {
        final stages = (stagesResult['result'] as List<dynamic>).cast<Map<String, dynamic>>();
        for (final s in stages) {
          final name = s['name']?.toString() ?? '';
          if (RegExp(r'^Día\s*0(\D|$)').hasMatch(name.trim())) {
            dayZeroName = name;
            break;
          }
        }
      }

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: const Text(
            '¡Aúpa! Te queda poco para salir. ¡Mucha suerte!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          actions: [
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('¡Gracias!'),
              ),
            ),
          ],
        ),
      );

      if (!mounted || dayZeroName == null) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StageTasksScreen(
            project: widget.project,
            stageName: dayZeroName!,
          ),
        ),
      ).then((_) {
        if (mounted) _refreshTripSummary();
      });
    }
  }

  // ---------------------------------------------------------------------
  // NOMBRE DEL VIAJE
  // ---------------------------------------------------------------------

  Future<void> _showRenameDialog() async {
    final controller = TextEditingController(text: _displayName);

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Renombrar viaje'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nombre del viaje',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isEmpty) return;
                Navigator.pop(dialogContext, trimmed);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (newName == null || newName == _displayName) return;

    final result = await _odooService.updateProjectName(
      projectId: widget.project.id,
      newName: newName,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      setState(() => _displayName = newName);
      // Sincroniza ya la copia local, para que la lista de viajes muestre
      // el nombre nuevo en cuanto se vuelva a ella, sin esperar a que le
      // toque sincronizar por su cuenta.
      await _syncService.syncProjects();
      if (!mounted) return;
      _showSnackBar('Viaje renombrado correctamente');
    } else {
      _showSnackBar('No se pudo renombrar el viaje', isError: true);
    }
  }



  Future<void> _showAddContactOptions() async {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              // La importación desde la agenda del teléfono usa
              // flutter_contacts, que no funciona en el navegador: en web
              // solo se ofrece la creación manual.
              if (!kIsWeb) ...[
                ListTile(
                  leading: const Icon(Icons.contact_phone),
                  title: const Text('Importar UN contacto del teléfono'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickFromPhoneContacts();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.groups),
                  title: const Text('Importar VARIOS contactos del teléfono'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickMultipleFromPhoneContacts();
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.person_add),
                title: const Text('Crear contacto manualmente'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showCreateContactDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Abre una lista propia (con casillas) de todos los contactos del
  /// teléfono, ya que el selector nativo de flutter_contacts solo permite
  /// elegir uno a la vez. Con los que se marquen, se crean y enlazan
  /// todos de golpe.
  Future<void> _pickMultipleFromPhoneContacts() async {
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) {
      if (mounted) {
        _showSnackBar('Necesitas conceder permiso de contactos del teléfono', isError: true);
      }
      return;
    }

    if (!mounted) return;

    final allContacts = await FlutterContacts.getContacts(withProperties: true);
    allContacts.sort((a, b) => a.displayName.compareTo(b.displayName));

    if (!mounted) return;

    // Contactos del teléfono que coincidan (por teléfono/email/nombre) con
    // alguno ya vinculado a este viaje, para marcarlos como duplicados.
    final alreadyLinkedPhoneContactIds = allContacts
        .where((deviceContact) => _contacts.any(
              (linked) => _isSameContact(deviceContact, linked),
            ))
        .map((c) => c.id)
        .toSet();

    final selected = await showDialog<List<Contact>>(
      context: context,
      builder: (dialogContext) {
        // Empieza sin nada marcado: con la agenda completa del teléfono,
        // lo normal es elegir solo unos pocos, no partir de "todos
        // seleccionados" y tener que desmarcar uno por uno.
        final selectedIds = <String>{};
        String filter = '';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final visibleContacts = filter.isEmpty
                ? allContacts
                : allContacts
                    .where((c) => c.displayName.toLowerCase().contains(filter.toLowerCase()))
                    .toList();

            return AlertDialog(
              title: const Text('Elegir contactos'),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Buscar...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) => setDialogState(() => filter = value),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: visibleContacts.length,
                        itemBuilder: (context, index) {
                          final contact = visibleContacts[index];
                          final isSelected = selectedIds.contains(contact.id);
                          final isDuplicate = alreadyLinkedPhoneContactIds.contains(contact.id);

                          return CheckboxListTile(
                            // Si ya está vinculado a este viaje, no se puede volver
                            // a marcar (antes solo se avisaba en naranja pero se
                            // dejaba seleccionar igual, y se podía importar duplicado).
                            value: isDuplicate ? false : isSelected,
                            activeColor: Theme.of(context).colorScheme.primary,
                            checkColor: Colors.white,
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 1.5,
                            ),
                            title: Text(
                              contact.displayName,
                              style: isDuplicate
                                  ? TextStyle(color: Theme.of(context).disabledColor)
                                  : null,
                            ),
                            subtitle: Text(
                              isDuplicate
                                  ? 'Ya está en este viaje'
                                  : (contact.phones.isNotEmpty
                                      ? contact.phones.first.number
                                      : (contact.emails.isNotEmpty ? contact.emails.first.address : '')),
                              style: isDuplicate
                                  ? const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)
                                  : null,
                            ),
                            onChanged: isDuplicate
                                ? null
                                : (checked) {
                                    setDialogState(() {
                                      if (checked == true) {
                                        selectedIds.add(contact.id);
                                      } else {
                                        selectedIds.remove(contact.id);
                                      }
                                    });
                                  },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: selectedIds.isEmpty
                      ? null
                      : () {
                          final chosen =
                              allContacts.where((c) => selectedIds.contains(c.id)).toList();
                          Navigator.pop(dialogContext, chosen);
                        },
                  child: Text('Importar (${selectedIds.length})'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected == null || selected.isEmpty || !mounted) return;

    final hasConnection = await _syncService.checkConnectivity();

    if (!hasConnection) {
      for (final contact in selected) {
        final name = contact.displayName.trim().isNotEmpty ? contact.displayName.trim() : 'Sin nombre';
        final phone = contact.phones.isNotEmpty ? contact.phones.first.number : null;
        final email = contact.emails.isNotEmpty ? contact.emails.first.address : null;

        await _localDb.saveOfflineReferenceContact(
          projectId: widget.project.id,
          name: name,
          phone: phone,
          email: email,
        );
      }

      if (!mounted) return;
      _showSnackBar(
        '${selected.length} contacto(s) guardados sin conexión. Se sincronizarán cuando haya señal.',
      );
      _loadAll();
      return;
    }

    _showSnackBar('Importando ${selected.length} contacto(s)...');

    int okCount = 0;
    for (final contact in selected) {
      final name = contact.displayName.trim().isNotEmpty ? contact.displayName.trim() : 'Sin nombre';
      final phone = contact.phones.isNotEmpty ? contact.phones.first.number : null;
      final email = contact.emails.isNotEmpty ? contact.emails.first.address : null;

      final result = await _odooService.createAndLinkReferenceContact(
        projectId: widget.project.id,
        name: name,
        phone: phone,
        email: email,
      );
      if (result['success'] == true) okCount++;
    }

    if (!mounted) return;

    _showSnackBar('$okCount de ${selected.length} contacto(s) importados');
    _loadAll();
  }

  /// Abre el selector nativo de contactos del teléfono, y con el contacto
  /// elegido crea (y enlaza) un nuevo contacto de referencia en Odoo.
  Future<void> _pickFromPhoneContacts() async {
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) {
      if (mounted) {
        _showSnackBar('Necesitas conceder permiso de contactos del teléfono', isError: true);
      }
      return;
    }

    final picked = await FlutterContacts.openExternalPick();
    if (picked == null) return; // el usuario canceló el selector

    // openExternalPick() solo trae id + nombre; hay que pedir el resto de
    // datos (teléfono, email) por separado.
    final full = await FlutterContacts.getContact(picked.id, withProperties: true);

    if (!mounted) return;

    if (full == null) {
      _showSnackBar('No se pudo leer el contacto seleccionado', isError: true);
      return;
    }

    // Evita añadir dos veces el mismo contacto a este viaje (antes no se
    // comprobaba nada aquí y se podía importar el mismo contacto repetidas veces).
    if (_contacts.any((linked) => _isSameContact(full, linked))) {
      _showSnackBar('${full.displayName.trim()} ya está en este viaje', isError: true);
      return;
    }

    final name = full.displayName.trim().isNotEmpty ? full.displayName.trim() : 'Sin nombre';
    final phone = full.phones.isNotEmpty ? full.phones.first.number : null;
    final email = full.emails.isNotEmpty ? full.emails.first.address : null;

    final hasConnection = await _syncService.checkConnectivity();

    if (!hasConnection) {
      await _localDb.saveOfflineReferenceContact(
        projectId: widget.project.id,
        name: name,
        phone: phone,
        email: email,
      );
      if (!mounted) return;
      _showSnackBar('Contacto guardado sin conexión. Se sincronizará cuando haya señal.');
      _loadAll();
      return;
    }

    final result = await _odooService.createAndLinkReferenceContact(
      projectId: widget.project.id,
      name: name,
      phone: phone,
      email: email,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      _loadAll();
    } else {
      _showSnackBar(result['error']?.toString() ?? 'No se pudo añadir el contacto', isError: true);
    }
  }

  /// Descarga UN contacto de referencia de Odoo a la agenda del teléfono,
  /// comprobando antes si ya existe (por teléfono o email) para no duplicar.
  Future<void> _downloadContactToPhone(ReferenceContact contact) async {
    final granted = await _requestContactsWritePermission();
    if (!granted) return;

    final deviceContacts = await FlutterContacts.getContacts(withProperties: true);

    if (_contactAlreadyOnDevice(deviceContacts, contact)) {
      if (mounted) _showSnackBar('${contact.name} ya está en tus contactos');
      return;
    }

    try {
      await _insertDeviceContact(contact);
      if (mounted) _showSnackBar('${contact.name} guardado en tus contactos');
    } catch (e) {
      if (mounted) _showSnackBar('No se pudo guardar el contacto: $e', isError: true);
    }
  }

  /// Descarga TODOS los contactos de referencia a la agenda del teléfono
  /// de una vez, saltando los que ya existan.
  Future<void> _downloadAllContactsToPhone() async {
    if (_contacts.isEmpty) {
      _showSnackBar('No hay contactos para descargar');
      return;
    }

    final granted = await _requestContactsWritePermission();
    if (!granted) return;

    _showSnackBar('Descargando ${_contacts.length} contacto(s)...');

    final deviceContacts = await FlutterContacts.getContacts(withProperties: true);

    int added = 0;
    int skipped = 0;

    for (final contact in _contacts) {
      if (_contactAlreadyOnDevice(deviceContacts, contact)) {
        skipped++;
        continue;
      }

      try {
        final inserted = await _insertDeviceContact(contact);
        // Se añade a la lista en memoria para que, si dos contactos de
        // referencia comparten teléfono/email, el segundo no se duplique.
        deviceContacts.add(inserted);
        added++;
      } catch (_) {
        // Si uno falla, seguimos con el resto en vez de abortar todo.
      }
    }

    if (!mounted) return;
    _showSnackBar('$added contacto(s) guardados, $skipped ya existían');
  }

  Future<bool> _requestContactsWritePermission() async {
    // Aquí sí hace falta permiso de escritura (readonly: false), a
    // diferencia de la importación, que solo necesitaba lectura.
    final granted = await FlutterContacts.requestPermission(readonly: false);
    if (!granted && mounted) {
      _showSnackBar('Necesitas conceder permiso de contactos del teléfono', isError: true);
    }
    return granted;
  }

  Future<Contact> _insertDeviceContact(ReferenceContact contact) async {
    final newContact = Contact()..name.first = contact.name;

    if (contact.phone != null && contact.phone!.isNotEmpty) {
      newContact.phones = [Phone(contact.phone!)];
    }
    if (contact.email != null && contact.email!.isNotEmpty) {
      newContact.emails = [Email(contact.email!)];
    }

    return newContact.insert();
  }

  /// Normaliza un teléfono dejando solo dígitos y el "+" inicial, para
  /// poder comparar números escritos con formatos distintos.
  String _normalizePhone(String phone) => phone.replaceAll(RegExp(r'[^0-9+]'), '');

  /// Comprueba si un contacto de referencia ya existe en la lista de
  /// contactos del teléfono, comparando por teléfono o email. Si el
  /// contacto no tiene ninguno de los dos, se compara por nombre exacto
  /// como última opción.
  bool _contactAlreadyOnDevice(List<Contact> deviceContacts, ReferenceContact contact) {
    final targetPhone = contact.phone != null ? _normalizePhone(contact.phone!) : null;
    final targetEmail = contact.email?.toLowerCase().trim();

    for (final deviceContact in deviceContacts) {
      if (targetPhone != null && targetPhone.isNotEmpty) {
        final matches = deviceContact.phones.any((p) => _normalizePhone(p.number) == targetPhone);
        if (matches) return true;
      }
      if (targetEmail != null && targetEmail.isNotEmpty) {
        final matches = deviceContact.emails.any((e) => e.address.toLowerCase().trim() == targetEmail);
        if (matches) return true;
      }
    }

    // Si no tiene teléfono ni email, comparamos por nombre exacto para no
    // dejar de detectar duplicados obvios.
    if ((targetPhone == null || targetPhone.isEmpty) && (targetEmail == null || targetEmail.isEmpty)) {
      return deviceContacts.any(
        (dc) => dc.displayName.trim().toLowerCase() == contact.name.trim().toLowerCase(),
      );
    }

    return false;
  }

  /// Comprueba si un contacto del teléfono coincide (por teléfono, email
  /// o nombre) con un contacto de referencia ya vinculado a este viaje.
  bool _isSameContact(Contact deviceContact, ReferenceContact linkedContact) {
    final linkedPhone = linkedContact.phone != null ? _normalizePhone(linkedContact.phone!) : null;
    final linkedEmail = linkedContact.email?.toLowerCase().trim();

    if (linkedPhone != null && linkedPhone.isNotEmpty) {
      final matches = deviceContact.phones.any((p) => _normalizePhone(p.number) == linkedPhone);
      if (matches) return true;
    }
    if (linkedEmail != null && linkedEmail.isNotEmpty) {
      final matches = deviceContact.emails.any((e) => e.address.toLowerCase().trim() == linkedEmail);
      if (matches) return true;
    }
    if ((linkedPhone == null || linkedPhone.isEmpty) && (linkedEmail == null || linkedEmail.isEmpty)) {
      return deviceContact.displayName.trim().toLowerCase() == linkedContact.name.trim().toLowerCase();
    }

    return false;
  }

  Future<void> _showCreateContactDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Nuevo contacto de referencia'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Teléfono (opcional)', border: OutlineInputBorder()),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email (opcional)', border: OutlineInputBorder()),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Crear'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;

    final phone = phoneController.text.trim();
    final email = emailController.text.trim();

    final hasConnection = await _syncService.checkConnectivity();

    if (!hasConnection) {
      await _localDb.saveOfflineReferenceContact(
        projectId: widget.project.id,
        name: name,
        phone: phone.isNotEmpty ? phone : null,
        email: email.isNotEmpty ? email : null,
      );
      if (!mounted) return;
      _showSnackBar('Contacto guardado sin conexión. Se sincronizará cuando haya señal.');
      _loadAll();
      return;
    }

    final result = await _odooService.createAndLinkReferenceContact(
      projectId: widget.project.id,
      name: name,
      phone: phone,
      email: email,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      _loadAll();
    } else {
      _showSnackBar(result['error']?.toString() ?? 'Error al crear el contacto', isError: true);
    }
  }

  Future<void> _confirmRemoveContact(ReferenceContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quitar contacto'),
        content: Text('¿Quitar a "${contact.name}" de los contactos de referencia de este viaje?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Guarda en la papelera antes de desvincular, para poder recuperarlo.
    // Como quitar un contacto no lo borra de Odoo (solo desvincula), no
    // hace falta guardar nada del propio contacto: basta con su id para
    // poder volver a vincularlo.
    await _localDb.addTrashItem(
      type: 'contact',
      projectId: widget.project.id,
      name: contact.name,
      extraData: {'partner_id': contact.id},
    );

    final result = await _odooService.unlinkReferenceContact(
      projectId: widget.project.id,
      partnerId: contact.id,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      _loadAll();
    } else {
      _showSnackBar('No se pudo quitar el contacto', isError: true);
    }
  }

  // ---------------------------------------------------------------------
  // REPASO ANTES DE SUBIR (detecta duplicados por nombre + extensión)
  // ---------------------------------------------------------------------

  /// Muestra una lista propia (con casillas de buen contraste) de los
  /// archivos elegidos por el selector nativo del sistema, marcando los
  /// que coincidan en nombre con uno ya subido aquí (para no duplicar sin
  /// querer). El usuario puede desmarcar/marcar libremente antes de subir.
  /// Devuelve solo los que queden marcados al pulsar "Subir", o null si
  /// se cancela.
  Future<List<PlatformFile>?> _showFilesReviewDialog({
    required List<PlatformFile> pickedFiles,
    required Set<String> existingNamesLowercase,
  }) async {
    final selected = <String>{
      for (final f in pickedFiles)
        if (!existingNamesLowercase.contains(f.name.toLowerCase())) f.name,
    };

    return showDialog<List<PlatformFile>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Confirmar archivos'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: pickedFiles.length,
                  itemBuilder: (context, index) {
                    final f = pickedFiles[index];
                    final isDuplicate = existingNamesLowercase.contains(f.name.toLowerCase());
                    final isChecked = selected.contains(f.name);

                    return CheckboxListTile(
                      value: isChecked,
                      activeColor: Theme.of(context).colorScheme.primary,
                      checkColor: Colors.white,
                      side: BorderSide(color: Theme.of(context).colorScheme.onSurface, width: 1.5),
                      title: Text(f.name),
                      subtitle: isDuplicate
                          ? const Text(
                              'Ya existe aquí con este nombre',
                              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                            )
                          : null,
                      onChanged: (checked) {
                        setDialogState(() {
                          if (checked == true) {
                            selected.add(f.name);
                          } else {
                            selected.remove(f.name);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () {
                          final chosen = pickedFiles.where((f) => selected.contains(f.name)).toList();
                          Navigator.pop(dialogContext, chosen);
                        },
                  child: const Text('Subir'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // ARCHIVOS DE RUTA
  // ---------------------------------------------------------------------

  Future<void> _pickAndUploadRouteFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx', 'kml', 'kmz', 'tcx', 'geojson'],
      allowMultiple: true,
      // En web no hay ruta de archivo real: hacen falta los bytes sí o
      // sí. Pedirlos siempre (también en móvil/escritorio) evita tener
      // dos caminos distintos según la plataforma.
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    // El selector nativo de algunos Android no filtra bien extensiones
    // poco comunes como .gpx, así que lo comprobamos nosotros también,
    // archivo por archivo (los que no cumplan se descartan del lote).
    const allowedExtensions = {'gpx', 'kml', 'kmz', 'tcx', 'geojson'};

    final validFiles = result.files.where((f) {
      if (f.bytes == null) return false;
      final dotIndex = f.name.lastIndexOf('.');
      final extension = dotIndex == -1 ? '' : f.name.substring(dotIndex + 1).toLowerCase();
      return allowedExtensions.contains(extension);
    }).toList();

    final skippedCount = result.files.length - validFiles.length;

    if (validFiles.isEmpty) {
      _showSnackBar(
        'Ningún archivo válido (solo .gpx, .kml, .kmz, .tcx, .geojson)',
        isError: true,
      );
      return;
    }

    if (!mounted) return;

    final existingNames = _routeFiles.map((r) => r.fileName.toLowerCase()).toSet();
    final confirmedFiles = await _showFilesReviewDialog(
      pickedFiles: validFiles,
      existingNamesLowercase: existingNames,
    );

    if (confirmedFiles == null || confirmedFiles.isEmpty || !mounted) return;

    final hasConnection = await _syncService.checkConnectivity();

    // Guardar para subir más tarde sin conexión necesita una ruta de
    // archivo real en el disco: en el navegador (web) no existe eso, así
    // que ahí hace falta conexión para subir en el momento.
    if (!hasConnection) {
      if (kIsWeb) {
        _showSnackBar(
          'Sin conexión: en el navegador hace falta conexión para subir archivos',
          isError: true,
        );
        return;
      }
      for (final pickedFile in confirmedFiles) {
        await _localDb.saveOfflineRouteFile(
          projectId: widget.project.id,
          fileName: pickedFile.name,
          filePath: pickedFile.path!,
        );
      }
      if (!mounted) return;
      final skippedMsg = skippedCount > 0 ? ' ($skippedCount descartado(s) por tipo no válido)' : '';
      _showSnackBar(
        '${confirmedFiles.length} archivo(s) guardados sin conexión$skippedMsg. Se subirán cuando haya señal.',
      );
      _loadAll();
      return;
    }

    _showSnackBar('Subiendo ${confirmedFiles.length} archivo(s) de ruta...');

    int okCount = 0;
    for (final pickedFile in confirmedFiles) {
      final uploadResult = await _odooService.uploadRouteFile(
        projectId: widget.project.id,
        fileName: pickedFile.name,
        bytes: pickedFile.bytes!,
      );
      if (uploadResult['success'] == true) okCount++;
    }

    if (!mounted) return;

    final skippedMsg = skippedCount > 0 ? ' ($skippedCount descartado(s) por tipo no válido)' : '';
    _showSnackBar('$okCount de ${confirmedFiles.length} archivo(s) de ruta subidos$skippedMsg');

    _loadAll();
  }

  /// Descarga el archivo de ruta al almacenamiento del teléfono y lo abre
  /// con la app que el usuario elija (Wikiloc, Komoot, Google Maps...).
  Future<void> _downloadAndOpenRouteFile(RouteFile routeFile) async {
    _showSnackBar('Descargando ${routeFile.fileName}...');

    final result = await _odooService.downloadRouteFileData(routeFile.id);

    if (!mounted) return;

    if (result['success'] != true) {
      _showSnackBar('No se pudo descargar el archivo', isError: true);
      return;
    }

    final records = result['result'] as List<dynamic>;
    if (records.isEmpty) {
      _showSnackBar('Archivo no encontrado', isError: true);
      return;
    }

    final base64Data = (records[0] as Map<String, dynamic>)['file_data'] as String?;
    if (base64Data == null) {
      _showSnackBar('El archivo está vacío', isError: true);
      return;
    }

    try {
      final bytes = base64Decode(base64Data);

      if (kIsWeb) {
        final opened = await openBytesOnWeb(bytes, routeFile.fileName);
        if (!opened && mounted) {
          _showSnackBar('No se pudo abrir el archivo', isError: true);
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/${routeFile.fileName}';
      final localFile = File(filePath);
      await localFile.writeAsBytes(bytes);

      await OpenFilex.open(filePath);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('No se pudo abrir el archivo: $e', isError: true);
    }
  }

  /// Descarga los bytes de un archivo de ruta sin escribirlos todavía.
  Future<Uint8List?> _fetchRouteFileBytes(int routeFileId) async {
    final result = await _odooService.downloadRouteFileData(routeFileId);
    if (result['success'] != true) return null;

    final records = result['result'] as List<dynamic>;
    if (records.isEmpty) return null;

    final base64Data = (records[0] as Map<String, dynamic>)['file_data'] as String?;
    if (base64Data == null) return null;

    return base64Decode(base64Data);
  }

  /// Guarda un archivo de ruta directamente en el almacenamiento del
  /// teléfono (diálogo nativo de "Guardar como"), en vez de abrirlo con
  /// otra app.
  Future<void> _saveRouteFileToDevice(RouteFile routeFile) async {
    _showSnackBar('Descargando ${routeFile.fileName}...');

    final bytes = await _fetchRouteFileBytes(routeFile.id);

    if (!mounted) return;

    if (bytes == null) {
      _showSnackBar('No se pudo descargar el archivo', isError: true);
      return;
    }

    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar ${routeFile.fileName}',
      fileName: routeFile.fileName,
      bytes: bytes,
    );

    if (!mounted) return;

    if (savedPath != null) {
      _showSnackBar('Archivo de ruta guardado correctamente');
    }
  }

  /// Determina el tipo MIME correcto según la extensión, para que Android
  /// muestre en el selector las apps de navegación/rutas adecuadas
  /// (Wikiloc, OrganicMaps, Komoot...) en vez de adivinar mal y sugerir
  /// apps que no tienen nada que ver, como Contactos.
  String? _mimeTypeForRouteFile(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    final extension = dotIndex == -1 ? '' : fileName.substring(dotIndex + 1).toLowerCase();

    switch (extension) {
      case 'gpx':
        return 'application/gpx+xml';
      case 'kml':
        return 'application/vnd.google-earth.kml+xml';
      case 'kmz':
        return 'application/vnd.google-earth.kmz';
      case 'tcx':
        return 'application/vnd.garmin.tcx+xml';
      case 'geojson':
        return 'application/geo+json';
      default:
        return null;
    }
  }

  /// Descarga TODOS los archivos de ruta del viaje de una vez y abre el
  /// selector de "Compartir" con todos ellos juntos. Desde ahí se puede
  /// elegir importarlos directamente en cualquier app de navegación
  /// instalada que acepte GPX/KML (Wikiloc, OrganicMaps, Komoot...), o
  /// guardarlos con "Guardar en Archivos"/Drive si se prefiere.
  Future<void> _shareAllRouteFiles() async {
    if (_routeFiles.isEmpty) {
      _showSnackBar('No hay archivos de ruta para descargar');
      return;
    }

    bool cancelled = false;

    // Diálogo de progreso con botón de cancelar, para poder echarse atrás
    // mientras se descargan los archivos.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        content: Row(
          children: const [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Descargando archivos de ruta...')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.pop(dialogContext);
            },
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    // Se construyen los XFile directamente desde los bytes descargados
    // (sin pasar por un archivo temporal en disco), porque así funciona
    // igual en Android/iOS y en el navegador.
    final tempFiles = <XFile>[];

    for (final routeFile in _routeFiles) {
      if (cancelled) break;

      final bytes = await _fetchRouteFileBytes(routeFile.id);
      if (bytes == null || cancelled) continue;

      tempFiles.add(XFile.fromData(
        bytes,
        name: routeFile.fileName,
        mimeType: _mimeTypeForRouteFile(routeFile.fileName),
      ));
    }

    // Si no se canceló, el diálogo de progreso sigue abierto: se cierra.
    // Si se canceló, ya se cerró él solo al pulsar el botón.
    if (!cancelled && mounted) {
      Navigator.pop(context);
    }

    if (cancelled || !mounted) return;

    if (tempFiles.isEmpty) {
      _showSnackBar('No se pudo descargar ningún archivo de ruta', isError: true);
      return;
    }

    await SharePlus.instance.share(ShareParams(files: tempFiles));
  }

  Future<void> _confirmDeleteRouteFile(RouteFile routeFile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrar archivo de ruta'),
        content: Text('¿Seguro que quieres borrar "${routeFile.fileName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Descarga el contenido antes de borrar, para poder restaurarlo desde
    // la papelera más tarde.
    final downloadResult = await _odooService.downloadRouteFileData(routeFile.id);
    if (downloadResult['success'] == true) {
      final records = downloadResult['result'] as List<dynamic>;
      if (records.isNotEmpty) {
        final rec = records[0] as Map<String, dynamic>;
        final base64Data = rec['file_data'] as String?;
        if (base64Data != null) {
          await _localDb.addTrashItem(
            type: 'route_file',
            projectId: widget.project.id,
            name: routeFile.fileName,
            extraData: {'base64': base64Data, 'description': routeFile.description},
          );
        }
      }
    }

    final result = await _odooService.deleteRouteFile(routeFile.id);

    if (!mounted) return;

    if (result['success'] == true) {
      _loadAll();
    } else {
      _showSnackBar('No se pudo borrar el archivo', isError: true);
    }
  }

  // ---------------------------------------------------------------------
  // FOTOS DEL GRUPO
  // ---------------------------------------------------------------------

  void _showAddPhotoOptions() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Tomar foto'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndUploadPhoto(fromCamera: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Elegir de la galería (varias)'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndUploadPhoto(fromCamera: false);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadPhoto({required bool fromCamera}) async {
    List<XFile> images;

    if (fromCamera) {
      final photo = await _imagePicker.pickImage(source: ImageSource.camera);
      if (photo == null) return;
      images = [photo];
    } else {
      images = await _imagePicker.pickMultiImage();
      if (images.isEmpty) return;
    }

    if (!mounted) return;

    final hasConnection = await _syncService.checkConnectivity();

    if (!hasConnection) {
      if (kIsWeb) {
        _showSnackBar(
          'Sin conexión: en el navegador hace falta conexión para subir fotos',
          isError: true,
        );
        return;
      }
      for (final image in images) {
        await _localDb.saveOfflineProjectPhoto(
          projectId: widget.project.id,
          fileName: image.name,
          filePath: image.path,
        );
      }
      if (!mounted) return;
      _showSnackBar(
        '${images.length} foto(s) guardadas sin conexión. Se subirán cuando haya señal.',
      );
      _loadAll();
      return;
    }

    _showSnackBar('Subiendo ${images.length} foto(s)...');

    int okCount = 0;
    for (final image in images) {
      final result = await _odooService.uploadProjectPhoto(
        projectId: widget.project.id,
        fileName: image.name,
        bytes: await image.readAsBytes(),
      );
      if (result['success'] == true) okCount++;
    }

    if (!mounted) return;
    _showSnackBar('$okCount de ${images.length} foto(s) subidas');
    _loadAll();
  }

  Future<void> _downloadAndOpenPhoto(Map<String, dynamic> photo) async {
    final photoId = photo['id'] as int;
    final fileName = photo['name']?.toString() ?? 'foto.jpg';

    _showSnackBar('Descargando $fileName...');

    final result = await _odooService.downloadProjectPhotoData(photoId);

    if (!mounted) return;

    if (result['success'] != true) {
      _showSnackBar('No se pudo descargar la foto', isError: true);
      return;
    }

    final records = result['result'] as List<dynamic>;
    if (records.isEmpty) {
      _showSnackBar('Foto no encontrada', isError: true);
      return;
    }

    final base64Data = (records[0] as Map<String, dynamic>)['image'] as String?;
    if (base64Data == null) {
      _showSnackBar('La foto está vacía', isError: true);
      return;
    }

    try {
      final bytes = base64Decode(base64Data);

      if (kIsWeb) {
        final opened = await openBytesOnWeb(bytes, fileName);
        if (!opened && mounted) {
          _showSnackBar('No se pudo abrir la foto', isError: true);
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/$fileName';
      final localFile = File(filePath);
      await localFile.writeAsBytes(bytes);

      await OpenFilex.open(filePath);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('No se pudo abrir la foto: $e', isError: true);
    }
  }

  Future<void> _confirmDeletePhoto(Map<String, dynamic> photo) async {
    final photoId = photo['id'] as int;
    final fileName = photo['name']?.toString() ?? 'esta foto';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrar foto'),
        content: Text('¿Seguro que quieres borrar "$fileName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await _odooService.deleteProjectPhoto(photoId);

    if (!mounted) return;

    if (result['success'] == true) {
      _loadAll();
    } else {
      _showSnackBar('No se pudo borrar la foto', isError: true);
    }
  }

  // ---------------------------------------------------------------------
  // DOCUMENTOS (PDFs, fichas, seguros...)
  // ---------------------------------------------------------------------

  Future<void> _pickAndUploadDocument() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final validFiles = result.files.where((f) => f.bytes != null).toList();
    if (validFiles.isEmpty) return;

    if (!mounted) return;

    final existingNames = _documents
        .map((d) => (d['name']?.toString() ?? '').toLowerCase())
        .toSet();

    final confirmedFiles = await _showFilesReviewDialog(
      pickedFiles: validFiles,
      existingNamesLowercase: existingNames,
    );

    if (confirmedFiles == null || confirmedFiles.isEmpty || !mounted) return;

    final hasConnection = await _syncService.checkConnectivity();

    if (!hasConnection) {
      if (kIsWeb) {
        _showSnackBar(
          'Sin conexión: en el navegador hace falta conexión para subir archivos',
          isError: true,
        );
        return;
      }
      for (final pickedFile in confirmedFiles) {
        await _localDb.saveOfflineProjectDocument(
          projectId: widget.project.id,
          fileName: pickedFile.name,
          filePath: pickedFile.path!,
          fileSize: pickedFile.size,
        );
      }
      if (!mounted) return;
      _showSnackBar(
        '${confirmedFiles.length} documento(s) guardados sin conexión. Se subirán cuando haya señal.',
      );
      _loadAll();
      return;
    }

    _showSnackBar('Subiendo ${confirmedFiles.length} documento(s)...');

    int okCount = 0;
    for (final pickedFile in confirmedFiles) {
      final uploadResult = await _odooService.uploadProjectAttachment(
        projectId: widget.project.id,
        fileName: pickedFile.name,
        bytes: pickedFile.bytes!,
      );
      if (uploadResult['success'] == true) okCount++;
    }

    if (!mounted) return;

    if (okCount == confirmedFiles.length) {
      _showSnackBar('$okCount documento(s) subido(s) correctamente');
    } else {
      _showSnackBar(
        '$okCount de ${confirmedFiles.length} documento(s) subidos (algunos fallaron)',
        isError: okCount == 0,
      );
    }

    _loadAll();
  }

  Future<void> _downloadAndOpenDocument(Map<String, dynamic> attachment) async {
    final attachmentId = attachment['id'] as int;
    final fileName = attachment['name']?.toString() ?? 'documento';

    _showSnackBar('Descargando $fileName...');

    final result = await _odooService.downloadAttachment(attachmentId);

    if (!mounted) return;

    if (result['success'] != true) {
      _showSnackBar('No se pudo descargar el documento', isError: true);
      return;
    }

    final records = result['result'] as List<dynamic>;
    if (records.isEmpty) {
      _showSnackBar('Documento no encontrado', isError: true);
      return;
    }

    final base64Data = (records[0] as Map<String, dynamic>)['datas'] as String?;
    if (base64Data == null) {
      _showSnackBar('El documento está vacío', isError: true);
      return;
    }

    try {
      final bytes = base64Decode(base64Data);

      if (kIsWeb) {
        final opened = await openBytesOnWeb(bytes, fileName);
        if (!opened && mounted) {
          _showSnackBar('No se pudo abrir el documento', isError: true);
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/$fileName';
      final localFile = File(filePath);
      await localFile.writeAsBytes(bytes);

      await OpenFilex.open(filePath);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('No se pudo abrir el documento: $e', isError: true);
    }
  }

  /// Descarga los bytes de un adjunto (documento o archivo de ruta) sin
  /// escribirlos todavía en ningún sitio.
  Future<Uint8List?> _fetchAttachmentBytes(int attachmentId) async {
    final result = await _odooService.downloadAttachment(attachmentId);
    if (result['success'] != true) return null;

    final records = result['result'] as List<dynamic>;
    if (records.isEmpty) return null;

    final base64Data = (records[0] as Map<String, dynamic>)['datas'] as String?;
    if (base64Data == null) return null;

    return base64Decode(base64Data);
  }

  /// Descarga un documento y lo guarda de verdad en el almacenamiento del
  /// teléfono, usando el diálogo nativo de "Guardar como" de Android (a
  /// través de file_picker). A diferencia de escribir el archivo nosotros
  /// mismos con `File(...).writeAsBytes()`, este método delega la escritura
  /// real al sistema operativo, que es la única forma fiable de escribir en
  /// una carpeta elegida por el usuario en Android moderno.
  Future<void> _saveDocumentToDevice(Map<String, dynamic> attachment) async {
    final attachmentId = attachment['id'] as int;
    final fileName = attachment['name']?.toString() ?? 'documento';

    _showSnackBar('Descargando $fileName...');

    final bytes = await _fetchAttachmentBytes(attachmentId);

    if (!mounted) return;

    if (bytes == null) {
      _showSnackBar('No se pudo descargar el documento', isError: true);
      return;
    }

    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar $fileName',
      fileName: fileName,
      bytes: bytes,
    );

    if (!mounted) return;

    // Si savedPath es null, el usuario canceló el diálogo: no es un error.
    if (savedPath != null) {
      _showSnackBar('Documento guardado correctamente');
    }
  }

  /// Descarga y guarda TODOS los documentos, uno detrás de otro. Android no
  /// permite escribir varios archivos de golpe en una carpeta elegida por
  /// el usuario sin confirmación: por eso aparecerá un diálogo de guardado
  /// por cada documento (es una limitación de seguridad del propio Android,
  /// no de la app). La primera vez puedes elegir la carpeta del viaje y
  /// las siguientes veces Android suele recordarla.
  Future<void> _saveAllDocumentsToDevice() async {
    if (_documents.isEmpty) {
      _showSnackBar('No hay documentos para descargar');
      return;
    }

    _showSnackBar(
      'Se abrirá un diálogo de guardado por cada documento (${_documents.length} en total)',
    );

    int savedCount = 0;
    for (final doc in _documents) {
      final attachmentId = doc['id'] as int;
      final fileName = doc['name']?.toString() ?? 'documento_$attachmentId';

      final bytes = await _fetchAttachmentBytes(attachmentId);
      if (bytes == null) continue;

      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar $fileName',
        fileName: fileName,
        bytes: bytes,
      );

      if (savedPath != null) savedCount++;
    }

    if (!mounted) return;
    _showSnackBar('$savedCount de ${_documents.length} documento(s) guardados');
  }

  Future<void> _confirmDeleteDocument(Map<String, dynamic> attachment) async {
    final attachmentId = attachment['id'] as int;
    final fileName = attachment['name']?.toString() ?? 'este documento';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrar documento'),
        content: Text('¿Seguro que quieres borrar "$fileName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Descarga el contenido antes de borrar, para poder restaurarlo desde
    // la papelera más tarde.
    final downloadResult = await _odooService.downloadAttachment(attachmentId);
    if (downloadResult['success'] == true) {
      final records = downloadResult['result'] as List<dynamic>;
      if (records.isNotEmpty) {
        final rec = records[0] as Map<String, dynamic>;
        final base64Data = rec['datas'] as String?;
        if (base64Data != null) {
          await _localDb.addTrashItem(
            type: 'document',
            projectId: widget.project.id,
            name: fileName,
            extraData: {'base64': base64Data},
          );
        }
      }
    }

    final result = await _odooService.deleteAttachment(attachmentId);

    if (!mounted) return;

    if (result['success'] == true) {
      _loadAll();
    } else {
      _showSnackBar('No se pudo borrar el documento', isError: true);
    }
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_displayName),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Papelera',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TrashScreen(project: widget.project),
                ),
              ).then((_) {
                // Restaurar algo desde la papelera debe verse reflejado
                // sin tener que salir y volver a entrar a mano.
                if (mounted) _loadAll();
              });
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Icon(
              _isOffline ? Icons.cloud_off : Icons.cloud_done,
              color: _isOffline ? Colors.orange : Colors.green,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.checklist),
        label: const Text('Etapas'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StagesScreen(project: widget.project),
            ),
          ).then((_) {
            // Añadir/borrar etapas cambia el número de días: al volver,
            // recargamos para que se actualice.
            if (mounted) {
              _loadAll();
              _refreshTripSummary();
            }
          });
        },
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildGeneralInfoSection(),
                      const SizedBox(height: 24),
                      _buildDocumentsSection(),
                      const SizedBox(height: 24),
                      _buildRouteFilesSection(),
                      const SizedBox(height: 24),
                      _buildContactsSection(),
                      const SizedBox(height: 24),
                      _buildPhotosSection(),
                      // Espacio para que el FAB no tape el último elemento.
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 60, color: Colors.red),
          const SizedBox(height: 16),
          Text(_errorMessage!, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _loadAll, child: const Text('Reintentar')),
        ],
      ),
    );
  }

  /// Convierte una fecha en formato de Odoo (yyyy-mm-dd, con o sin hora)
  /// a dd-mm-yyyy para mostrarla. Si no se puede interpretar, devuelve el
  /// texto original tal cual.
  String _formatDdMmYyyy(String? isoDate) {
    if (isoDate == null) return '—';
    try {
      final datePart = isoDate.split(' ').first;
      final parts = datePart.split('-');
      if (parts.length == 3) {
        return '${parts[2]}-${parts[1]}-${parts[0]}';
      }
    } catch (_) {}
    return isoDate;
  }

  /// Número de días real del viaje: se cuenta a partir de las etapas
  /// reales "Día N" (la más alta, sin contar "Día 0"), igual que hace
  /// SyncService.syncProjects() para la lista de viajes. Así ambas
  /// pantallas coinciden, y no depende de que date_start/date del propio
  /// proyecto estén bien actualizados.
  int? _dayCount;

  /// Formatea una fecha en formato ISO (yyyy-MM-dd, como llega de Odoo) a
  /// dd-mm-yyyy para mostrarla. Si no se puede interpretar, devuelve el
  /// texto original tal cual.
  String _formatDateDisplay(String? isoDate) {
    if (isoDate == null) return '—';
    try {
      final date = DateTime.parse(isoDate);
      return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
    } catch (_) {
      return isoDate;
    }
  }

  /// Consulta las etapas reales del viaje y recalcula, a partir de ellas,
  /// tanto el número de días (la etapa "Día N" con el número más alto,
  /// sin contar "Día 0") como el rango de fechas mostrado (fecha mínima y
  /// máxima entre todas las etapas con fecha en el nombre, del tipo
  /// "Día N - dd/mm/yyyy"). Se recalculan juntos y desde la misma fuente
  /// porque el número de días y el rango de fechas del proyecto en Odoo
  /// (date_start/date) NO se actualizan solos al añadir/quitar etapas;
  /// las etapas son la única fuente fiable. Si ninguna etapa trae fecha
  /// en el nombre, se deja el rango que ya hubiera (el leído de
  /// project.date_start/date en _loadAll(), como respaldo).
  Future<void> _refreshTripSummary() async {
    final stagesResult = await _odooService.fetchProjectStages(widget.project.id);
    if (stagesResult['success'] != true) return;

    final stages = (stagesResult['result'] as List<dynamic>).cast<Map<String, dynamic>>();
    final dayPattern = RegExp(r'^Día\s*(\d+)');
    final datePattern = RegExp(r'(\d{2})/(\d{2})/(\d{4})');

    int maxDay = 0;
    DateTime? minDate;
    DateTime? maxDate;

    for (final s in stages) {
      final name = s['name']?.toString().trim() ?? '';

      final dayMatch = dayPattern.firstMatch(name);
      if (dayMatch != null) {
        final dayNum = int.tryParse(dayMatch.group(1)!) ?? 0;
        if (dayNum > 0 && dayNum > maxDay) maxDay = dayNum;
      }

      final dateMatch = datePattern.firstMatch(name);
      if (dateMatch != null) {
        try {
          final d = DateTime(
            int.parse(dateMatch.group(3)!),
            int.parse(dateMatch.group(2)!),
            int.parse(dateMatch.group(1)!),
          );
          if (minDate == null || d.isBefore(minDate!)) minDate = d;
          if (maxDate == null || d.isAfter(maxDate!)) maxDate = d;
        } catch (_) {}
      }
    }

    if (!mounted) return;
    setState(() {
      _dayCount = maxDay > 0 ? maxDay : null;
      if (minDate != null) _dateStart = _isoDate(minDate!);
      if (maxDate != null) _dateEnd = _isoDate(maxDate!);
    });
  }

  /// Formatea una fecha como yyyy-MM-dd (el mismo formato ISO en el que
  /// llegan date_start/date desde Odoo), para que _formatDateDisplay()
  /// pueda seguir interpretándola igual que antes.
  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _buildGeneralInfoSection() {
    final p = widget.project;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(_displayName, style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: 'Renombrar viaje',
                  onPressed: _showRenameDialog,
                ),
              ],
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StageTaskMatrixScreen(project: widget.project),
                  ),
                );
              },
              icon: const Icon(Icons.grid_view, size: 18),
              label: const Text('Ver etapas y tareas del viaje'),
            ),
            if (p.description != null) ...[
              const SizedBox(height: 8),
              Text(p.description!),
            ],
            const SizedBox(height: 12),
            if (_dateStart != null || _dateEnd != null)
              Row(
                children: [
                  const Icon(Icons.date_range, size: 18, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${_formatDateDisplay(_dateStart)}  →  ${_formatDateDisplay(_dateEnd)}')),
                  if (_dayCount != null)
                    Text(
                      '$_dayCount ${_dayCount == 1 ? 'día' : 'días'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            if (p.userName != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 18, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text('Responsable: ${p.userName}'),
                  ],
                ),
              ),
            if (p.partnerName != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.business, size: 18, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text('Cliente: ${p.partnerName}'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsSection() {
    return _buildSectionCard(
      title: 'Contactos de referencia',
      icon: Icons.contacts,
      onAdd: _showAddContactOptions,
      isEmpty: _contacts.isEmpty,
      emptyLabel: 'No hay contactos de referencia todavía.',
      // Descargar a la agenda del teléfono tampoco tiene sentido en el
      // navegador.
      extraHeaderActions: kIsWeb
          ? const []
          : [
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Descargar todos a mis contactos',
                onPressed: _downloadAllContactsToPhone,
              ),
            ],
      children: _contacts.map((contact) {
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(contact.name),
          subtitle: Text([
            if (contact.phone != null) contact.phone!,
            if (contact.email != null) contact.email!,
          ].join(' · ')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!kIsWeb)
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.blue),
                  tooltip: 'Guardar en mis contactos',
                  onPressed: () => _downloadContactToPhone(contact),
                ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                tooltip: 'Quitar de este viaje',
                onPressed: () => _confirmRemoveContact(contact),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRouteFilesSection() {
    return _buildSectionCard(
      title: 'Archivos de ruta',
      icon: Icons.route,
      onAdd: _pickAndUploadRouteFile,
      isEmpty: _routeFiles.isEmpty,
      emptyLabel: 'No hay archivos de ruta todavía (GPX, KML, KMZ...).',
      extraHeaderActions: [
        IconButton(
          icon: const Icon(Icons.ios_share),
          tooltip: 'Descargar todas / importar en app de navegación',
          onPressed: _shareAllRouteFiles,
        ),
      ],
      children: _routeFiles.map((routeFile) {
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.route, color: Colors.green),
          title: Text(routeFile.fileName),
          subtitle: routeFile.description != null ? Text(routeFile.description!) : null,
          onTap: () => _downloadAndOpenRouteFile(routeFile),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'open') _downloadAndOpenRouteFile(routeFile);
              if (value == 'save') _saveRouteFileToDevice(routeFile);
              if (value == 'delete') _confirmDeleteRouteFile(routeFile);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'open', child: Text('Abrir con app de navegación')),
              const PopupMenuItem(value: 'save', child: Text('Guardar en el teléfono')),
              const PopupMenuItem(value: 'delete', child: Text('Borrar')),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDocumentsSection() {
    return _buildSectionCard(
      title: 'Documentos (ficha, seguro...)',
      icon: Icons.picture_as_pdf,
      onAdd: _pickAndUploadDocument,
      isEmpty: _documents.isEmpty,
      emptyLabel: 'No hay documentos todavía.',
      extraHeaderActions: [
        IconButton(
          icon: const Icon(Icons.save_alt),
          tooltip: 'Guardar todos en el teléfono',
          onPressed: _saveAllDocumentsToDevice,
        ),
      ],
      children: _documents.map((doc) {
        final name = doc['name']?.toString() ?? 'Documento';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.insert_drive_file, color: Colors.indigo),
          title: Text(name),
          onTap: () => _downloadAndOpenDocument(doc),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'open') _downloadAndOpenDocument(doc);
              if (value == 'save') _saveDocumentToDevice(doc);
              if (value == 'delete') _confirmDeleteDocument(doc);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'open', child: Text('Descargar y abrir')),
              const PopupMenuItem(value: 'save', child: Text('Guardar en el teléfono')),
              const PopupMenuItem(value: 'delete', child: Text('Borrar')),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPhotosSection() {
    return _buildSectionCard(
      title: 'Fotos del grupo',
      icon: Icons.photo_camera,
      onAdd: _showAddPhotoOptions,
      isEmpty: _photos.isEmpty,
      emptyLabel: 'No hay fotos todavía.',
      children: _photos.map((photo) {
        final name = photo['name']?.toString() ?? 'Foto';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.photo, color: Colors.purple),
          title: Text(name),
          onTap: () => _downloadAndOpenPhoto(photo),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'open') _downloadAndOpenPhoto(photo);
              if (value == 'delete') _confirmDeletePhoto(photo);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'open', child: Text('Descargar y abrir')),
              const PopupMenuItem(value: 'delete', child: Text('Borrar')),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required VoidCallback onAdd,
    required bool isEmpty,
    required String emptyLabel,
    required List<Widget> children,
    List<Widget> extraHeaderActions = const [],
  }) {
    // Esquema de color: blanco/negro si no hay nada dentro, azul pastel
    // con letras blancas si tiene algún elemento.
    final hasContent = !isEmpty;
    final backgroundColor = hasContent ? const Color(0xFFA7C7E7) : Colors.white;
    final foregroundColor = hasContent ? Colors.white : Colors.black87;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        // Desplegable: el contenido solo se ve si se abre a propósito.
        initiallyExpanded: false,
        backgroundColor: backgroundColor,
        collapsedBackgroundColor: backgroundColor,
        iconColor: foregroundColor,
        collapsedIconColor: foregroundColor,
        textColor: foregroundColor,
        collapsedTextColor: foregroundColor,
        title: Row(
          children: [
            Icon(icon, color: foregroundColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontWeight: FontWeight.bold, color: foregroundColor),
              ),
            ),
            ...extraHeaderActions,
            IconButton(
              icon: Icon(Icons.add, color: foregroundColor),
              onPressed: onAdd,
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: isEmpty
                ? Text(emptyLabel, style: TextStyle(color: Theme.of(context).hintColor))
                : Column(children: children),
          ),
        ],
      ),
    );
  }
}
