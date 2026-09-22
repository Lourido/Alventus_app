import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/odoo_service.dart';

/// Mensajes que la app enseña al usuario (avisos y errores), para poder
/// cambiarlos DESDE ODOO sin tocar la app ni volver a compilarla.
///
/// Cómo funciona:
///  - cada mensaje tiene un código ('sin_cobertura'...) y un texto por
///    defecto, que es el que está escrito aquí abajo;
///  - en Odoo, en Viajes > Mensajes de la app (modelo `alventus.app.message`,
///    ver models/app_message.py del módulo), se puede escribir otro texto
///    para cualquiera de ellos;
///  - al abrir la app se traen los textos personalizados y se guardan en el
///    teléfono, así que siguen valiendo sin cobertura;
///  - si un mensaje no está personalizado (o no hay forma de preguntar a
///    Odoo), se usa el texto por defecto de aquí.
///
/// Para usar un mensaje: `Msg.of('sin_cobertura')`.
///
/// Para añadir uno nuevo: ponerlo en [defaults] con su código, usarlo en la
/// pantalla con `Msg.of(...)`, y añadir su ficha en data/app_messages.xml
/// del módulo de Odoo (si no, funcionará igual, pero no se podrá cambiar
/// desde Odoo).
class Msg {
  Msg._();

  static const _prefsKey = 'app_messages_custom';

  /// Textos por defecto (los de toda la vida). NO borrar códigos: si un
  /// mensaje deja de usarse, basta con dejar de llamarlo.
  static const Map<String, String> defaults = {
    'el_servidor_no_ha_podido_mandar_el':
        'El servidor no ha podido mandar el aviso{detalle}.',
    'en_el_iphone_los_avisos_solo_funcionan':
        'En el iPhone, los avisos solo funcionan con la app añadida a la pantalla de inicio: en Safari, pulsa Compartir y luego "Añadir a pantalla de inicio", y abre la app desde ese icono.',
    'este_navegador_no_puede_recibir_avisos':
        'Este navegador no puede recibir avisos.',
    'has_bloqueado_los_avisos_para_recibirlos_permitelo':
        'Has bloqueado los avisos. Para recibirlos, permítelos para Alventus en los ajustes del teléfono.',
    'los_avisos_no_estan_activados_en_este':
        'Los avisos no están activados en este teléfono.',
    'no_se_han_activado_los_avisos':
        'No se han activado los avisos.',
    'no_se_han_podido_activar_los_avisos':
        'No se han podido activar los avisos: {detalle}',
    'el_viaje_se_copio_pero_no_se':
        'El viaje se copió, pero no se pudo asignar el guía como gestor',
    'error_al_compartir_el_viaje':
        'Error al compartir el viaje',
    'no_hay_usuarios_en_el_grupo_guias':
        'No hay usuarios en el grupo "Guías" con quien compartir',
    'no_se_pudo_abrir_whatsapp':
        'No se pudo abrir WhatsApp',
    'error_al_copiar_el_viaje':
        'Error al copiar el viaje',
    'archivo_guardado_en_tu_telefono_lo_subire':
        'Archivo guardado en tu teléfono. Lo subiré cuando haya conexión.',
    'el_archivo_esta_vacio':
        'El archivo está vacío',
    'error_al_actualizar':
        'Error al actualizar',
    'hora_guardada_pero_el_aviso_no_falta':
        'Hora guardada, pero el aviso no: falta actualizar el módulo de Alventus en el servidor de Odoo.',
    'pon_una_hora_distinta_de_las_00':
        'Pon una hora distinta de las 00:00 (por ejemplo, 00:05).',
    'tarea_sin_nombre':
        'Vamos,vamos, ... donde se ha visto ... dale un nombre.',
    'ya_lo_siento_no_puedo_descargar_el':
        'Ya lo siento. No puedo descargar el archivo',
    'cachis_error_al_abrir_el_archivo':
        '¡Cachis! Error al abrir el archivo: {detalle}',
    'cachis_error_al_borrar_adjunto':
        '¡Cachis! Error al borrar adjunto',
    'cachis_error_al_descargar_el_archivo':
        '¡Cachis! Error al descargar el archivo',
    'cachis_error_al_guardar_archivo_localmente':
        '¡Cachis! Error al guardar archivo localmente: {detalle}',
    'cachis_error_al_seleccionar_archivo':
        '¡Cachis! Error al seleccionar archivo: {detalle}',
    'cachis_error_al_seleccionar_imagen':
        '¡Cachis! Error al seleccionar imagen: {detalle}',
    'cachis_error_al_subir_archivo':
        '¡Cachis! Error al subir archivo',
    'cachis_no_puedo_abrir_el_archivo':
        '¡Cachis! No puedo abrir el archivo',
    'cachis_no_puedo_abrir_el_archivo_2':
        '¡Cachis! No puedo abrir el archivo: {detalle}',
    'error_al_borrar_tarea':
        'Error al borrar tarea',
    'error_al_crear_tarea':
        'Error al crear tarea',
    'tarea_borrada_localmente_se_sincronizara_cuando_ha':
        'Tarea borrada localmente. Se sincronizará cuando haya conexión.',
    'tarea_guardada_localmente_se_sincronizara_cuando_h':
        'Tarea guardada localmente. Se sincronizará cuando haya conexión.',
    'no_se_pudo_acceder_al_microfono':
        'No se pudo acceder al micrófono.',
    'no_se_pudo_descargar_el_modelo_de':
        'No se pudo descargar el modelo de dictado. Comprueba tu conexión e inténtalo de nuevo.',
    'cachissssss_que_no_me_coincide':
        'Cachissssss que no me coincide ... ',
    'no_te_tengo_guardado_sera_porque_es':
        'No te tengo guardado. Será porque es la primera vez que entras aquí. Vuelve cuando haya conexión.',
    'alguna_tarea_no_se_pudo_mover_correctamente':
        'Alguna tarea no se pudo mover correctamente',
    'esto_no_es_una_etapa_real_no':
        'Esto no es una etapa real, no se puede borrar',
    'etapa_borrada_pero_alguna_etapa_siguiente_no':
        'Etapa borrada, pero alguna etapa siguiente no se pudo renumerar',
    'hubo_un_problema_al_borrar_revisa_la':
        'Hubo un problema al borrar (revisa la etapa en Odoo)',
    'no_se_pudieron_obtener_las_etapas':
        'No se pudieron obtener las etapas',
    'no_se_pudo_anadir_la_etapa':
        'No se pudo añadir la etapa',
    'no_se_pudo_guardar_la_descripcion':
        'No se pudo guardar la descripción',
    'sin_cobertura_no_consigo_identificar_esta_etapa':
        'Sin cobertura no consigo identificar esta etapa. Abre este viaje una vez con cobertura y vuelve a intentarlo.',
    'cierra_la_app_del_todo_y_vuelve':
        'Cierra la app del todo y vuelve a abrirla con cobertura. Después ya podrás generar el PDF.',
    'falta_terminar_de_actualizar_la_app':
        'Falta terminar de actualizar la app',
    'no_se_ha_podido_generar_el_pdf':
        'No se ha podido generar el PDF: {detalle}',
    'no_se_ha_podido_guardar_el_pdf':
        'No se ha podido guardar el PDF: {detalle}',
    'error_al_crear_el_viaje':
        'Error al crear el viaje: {detalle}',
    'selecciona_la_fecha_de_inicio':
        'Selecciona la fecha de inicio',
    'no_se_pudo_restaurar':
        'No se pudo restaurar',
    'error_al_quitar_el_viaje':
        'Error al quitar el viaje',
    'error_al_recuperar_el_viaje':
        'Error al recuperar el viaje',
    'error_al_crear_la_tarea':
        'Error al crear la tarea',
    'la_hora_desde_no_puede_ser_posterior':
        'La hora "desde" no puede ser posterior a la hora "hasta" ya guardada',
    'la_hora_hasta_no_puede_ser_anterior':
        'La hora "hasta" no puede ser anterior a la hora "desde" ya guardada',
    'no_se_pudo_abrir_el_archivo':
        'No se pudo abrir el archivo',
    'no_se_pudo_abrir_el_archivo_2':
        'No se pudo abrir el archivo: {detalle}',
    'no_se_pudo_borrar_el_adjunto':
        'No se pudo borrar el adjunto',
    'no_se_pudo_cambiar_la_hora':
        'No se pudo cambiar la hora',
    'no_se_pudo_descargar_el_archivo':
        'No se pudo descargar el archivo',
    'archivo_s_subido_s_correctamente':
        '{detalle} archivo(s) subido(s) correctamente',
    'guardado_en_telefono':
        'Cambios guardados en el teléfono. Cuando haya conexión se subirán al servidor.',
    'sin_cobertura':
        'Lo siento. Tendrás que esperar a que tengas cobertura para hacerlo.',
    'viendo_datos_guardados':
        'NO hay conexión. Estás viendo los datos guardados en el teléfono la última vez que usaste la app con conexión.',
    'archivo_no_encontrado':
        'Archivo no encontrado',
    'contacto_guardado':
        'Contacto guardado',
    'documento_no_encontrado':
        'Documento no encontrado',
    'el_documento_esta_vacio':
        'El documento está vacío',
    'error_al_cargar_los_datos_del_viaje':
        'Error al cargar los datos del viaje: {detalle}',
    'foto_no_encontrada':
        'Foto no encontrada',
    'la_foto_esta_vacia':
        'La foto está vacía',
    'lo_sentimos_en_el_iphone_safari_no':
        'Lo sentimos: en el iPhone, Safari no permite que ninguna página web (incluida esta) lea los contactos guardados en el teléfono. Es una limitación del propio Safari, no de esta app, y no depende de nosotros arreglarlo.\n\nPuedes crear el contacto a mano, o copiar el nombre/teléfono desde la app Contactos del iPhone y pegarlo aquí.',
    'necesitas_conceder_permiso_de_contactos_del_telefo':
        'Necesitas conceder permiso de contactos del teléfono',
    'ningun_archivo_valido_solo_gpx_kml_kmz':
        'Ningún archivo válido (solo .gpx, .kml, .kmz, .tcx, .geojson)',
    'no_se_pudieron_abrir_los_contactos':
        'No se pudieron abrir los contactos',
    'no_se_pudo_abrir_el_contacto':
        'No se pudo abrir el contacto',
    'no_se_pudo_abrir_el_documento':
        'No se pudo abrir el documento',
    'no_se_pudo_abrir_el_documento_2':
        'No se pudo abrir el documento: {detalle}',
    'no_se_pudo_abrir_la_foto':
        'No se pudo abrir la foto',
    'no_se_pudo_abrir_la_foto_2':
        'No se pudo abrir la foto: {detalle}',
    'no_se_pudo_borrar_el_archivo':
        'No se pudo borrar el archivo',
    'no_se_pudo_borrar_el_documento':
        'No se pudo borrar el documento',
    'no_se_pudo_borrar_la_foto':
        'No se pudo borrar la foto',
    'no_se_pudo_descargar_el_documento':
        'No se pudo descargar el documento',
    'no_se_pudo_descargar_la_foto':
        'No se pudo descargar la foto',
    'no_se_pudo_descargar_ningun_archivo_de':
        'No se pudo descargar ningún archivo de ruta',
    'no_se_pudo_guardar_el_contacto':
        'No se pudo guardar el contacto: {detalle}',
    'no_se_pudo_leer_el_contacto_seleccionado':
        'No se pudo leer el contacto seleccionado',
    'no_se_pudo_quitar_el_contacto':
        'No se pudo quitar el contacto',
    'no_se_pudo_renombrar_el_viaje':
        'No se pudo renombrar el viaje',
    'no_se_puede_leer_la_agenda_del':
        'No se puede leer la agenda del iPhone',
    'sin_conexion_en_el_navegador_hace_falta':
        'Sin conexión: en el navegador hace falta conexión para subir archivos',
    'viaje_renombrado_correctamente':
        'Viaje renombrado correctamente',
    'guardado_en_tus_contactos':
        '{detalle} guardado en tus contactos',
    'ya_esta_en_este_viaje':
        '{detalle} ya está en este viaje',
  };


  static Map<String, String> _custom = const {};

  /// El texto a enseñar: el personalizado en Odoo si lo hay, y si no el de
  /// por defecto. Nunca devuelve null ni lanza.
  ///
  /// [vars]: para los mensajes que llevan un hueco entre llaves, como
  /// "No se pudo abrir el archivo: {detalle}". Si el texto personalizado no
  /// lleva el hueco, simplemente no se rellena (el mensaje sale sin el
  /// detalle técnico, que es algo que se puede querer a propósito).
  static String of(String code, [Map<String, String>? vars]) {
    final custom = _custom[code];
    var texto = (custom != null && custom.trim().isNotEmpty)
        ? custom.trim()
        : (defaults[code] ?? '');
    if (vars != null) {
      vars.forEach((clave, valor) {
        texto = texto.replaceAll('{$clave}', valor);
      });
    }
    return texto;
  }

  /// Carga los textos personalizados guardados en el teléfono. Se llama al
  /// arrancar la app, antes de pintar nada (ver main.dart).
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved == null) return;
      final data = jsonDecode(saved) as Map<String, dynamic>;
      _custom = {
        for (final entry in data.entries) entry.key: entry.value.toString(),
      };
    } catch (_) {
      // Si algo falla, se usan los textos por defecto: nunca debe impedir
      // que la app arranque.
    }
  }

  /// Se trae de Odoo los textos personalizados y los guarda en el teléfono.
  /// Sin cobertura no pasa nada: se sigue con los que hubiera.
  static Future<void> refresh() async {
    try {
      final result = await OdooService().executeKw(
        model: 'alventus.app.message',
        method: 'app_messages',
        args: [],
      );
      if (result['success'] != true || result['result'] is! Map) return;
      final data = (result['result'] as Map).map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      );
      _custom = data;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(data));
    } catch (_) {}
  }
}
