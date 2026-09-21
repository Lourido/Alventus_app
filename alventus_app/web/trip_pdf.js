// Genera el PDF de un viaje: sus etapas con sus tareas y, si se pide,
// también el contenido de los documentos del viaje.
//
// Se hace aquí, en JavaScript y con pdf-lib (web/pdf-lib.min.js, licencia
// MIT), por dos motivos:
//
//  1. pdf-lib sabe COPIAR TAL CUAL las páginas de otro PDF dentro del
//     nuevo. Así, un documento PDF del viaje (un billete, una reserva...)
//     aparece en el PDF generado con su contenido real, a calidad completa
//     y con el texto seleccionable, no convertido en una foto. Los
//     paquetes de PDF para Dart no saben hacer esto sin pasar por un
//     servidor.
//  2. Todo ocurre en el propio teléfono: "Etapas y tareas" se puede
//     generar sin cobertura, con los datos guardados.
//
// Desde Dart se llama a buildTripPdf(json, nombreDeArchivo) — ver
// lib/utils/trip_pdf.dart — y aquí se genera el PDF y se descarga con
// saveBytesAsFile (web/file_saver.js), sin devolver los bytes a Dart: con
// documentos grandes, pasar varios megas de un lado a otro para nada
// solo gastaría memoria del teléfono.
//
// pdf-lib no se carga al abrir la app (son ~500 KB que casi nunca hacen
// falta), sino la primera vez que se genera un PDF. El service worker lo
// tiene en su lista de precarga, así que funciona también sin cobertura.

(function () {
  'use strict';

  var PDF_LIB_URL = 'pdf-lib.min.js';
  var cargando = null;

  function cargarPdfLib() {
    if (window.PDFLib) return Promise.resolve(window.PDFLib);
    if (cargando) return cargando;
    cargando = new Promise(function (resolve, reject) {
      var script = document.createElement('script');
      script.src = PDF_LIB_URL;
      script.onload = function () {
        if (window.PDFLib) {
          resolve(window.PDFLib);
        } else {
          cargando = null;
          reject(new Error('pdf-lib no se ha cargado'));
        }
      };
      script.onerror = function () {
        cargando = null;
        reject(new Error('No se ha podido cargar pdf-lib'));
      };
      document.head.appendChild(script);
    });
    return cargando;
  }

  // ---------------------------------------------------------------------
  // Medidas (en puntos: 1 pt = 1/72 de pulgada). Página A4.
  // ---------------------------------------------------------------------
  var ANCHO = 595.28;
  var ALTO = 841.89;
  var MARGEN = 50;
  var ANCHO_UTIL = ANCHO - 2 * MARGEN;
  var ARRIBA = ALTO - MARGEN - 18; // deja sitio a la cabecera
  var ABAJO = MARGEN + 12; // deja sitio al pie

  // ---------------------------------------------------------------------
  // Texto
  // ---------------------------------------------------------------------

  // Las fuentes estándar de PDF (Helvetica) solo saben dibujar los
  // caracteres de la codificación WinAnsi: todo el español (tildes, ñ,
  // ¿, ¡, €...) sí, pero no emojis ni otros alfabetos. Con un carácter
  // que no conoce, pdf-lib no lo omite: lanza un error y el PDF entero
  // falla. Por eso se limpia antes todo el texto: lo que no se puede
  // dibujar se sustituye por su letra sin adornos si la tiene (ş -> s) o
  // se quita.
  function crearLimpiador(fuente) {
    var permitidos = new Set(fuente.getCharacterSet());
    return function limpiar(texto) {
      if (texto === null || texto === undefined) return '';
      var s = String(texto)
        .replace(/\r\n?/g, '\n')
        .replace(/\t/g, '    ')
        // Símbolos habituales que la fuente no tiene, a su equivalente en
        // texto (mejor "->" que que la flecha desaparezca sin más).
        .replace(/[\u2192\u21D2\u27A1]/g, '->')
        .replace(/[\u2190\u21D0\u2B05]/g, '<-')
        .replace(/[\u2194\u21D4]/g, '<->')
        .replace(/[\u2713\u2714\u2705]/g, 'OK')
        .replace(/[\u2717\u2718\u274C]/g, 'X');
      var salida = '';
      for (var ch of s) {
        var cp = ch.codePointAt(0);
        if (ch === '\n' || permitidos.has(cp)) {
          salida += ch;
          continue;
        }
        var base = ch.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
        var sustituto = '';
        for (var b of base) {
          if (permitidos.has(b.codePointAt(0))) sustituto += b;
        }
        salida += sustituto;
      }
      return salida;
    };
  }

  // Parte un texto en líneas que quepan en [ancho], respetando los
  // saltos de línea que ya traiga y cortando por palabras (o, si una
  // palabra sola no cabe, por letras).
  function partirEnLineas(texto, fuente, tam, ancho) {
    var lineas = [];
    var parrafos = texto.split('\n');
    for (var p = 0; p < parrafos.length; p++) {
      var palabras = parrafos[p].split(/ +/).filter(function (w) { return w.length > 0; });
      if (palabras.length === 0) {
        lineas.push('');
        continue;
      }
      var actual = '';
      for (var i = 0; i < palabras.length; i++) {
        var palabra = palabras[i];
        var prueba = actual ? actual + ' ' + palabra : palabra;
        if (fuente.widthOfTextAtSize(prueba, tam) <= ancho) {
          actual = prueba;
          continue;
        }
        if (actual) lineas.push(actual);
        // La palabra sola tampoco cabe: se trocea por letras.
        if (fuente.widthOfTextAtSize(palabra, tam) > ancho) {
          var trozo = '';
          for (var ch of palabra) {
            if (fuente.widthOfTextAtSize(trozo + ch, tam) > ancho && trozo) {
              lineas.push(trozo);
              trozo = ch;
            } else {
              trozo += ch;
            }
          }
          actual = trozo;
        } else {
          actual = palabra;
        }
      }
      lineas.push(actual);
    }
    return lineas;
  }

  // ---------------------------------------------------------------------
  // Escritor: va poniendo texto hacia abajo y abre página nueva cuando no
  // cabe más.
  // ---------------------------------------------------------------------
  function crearEscritor(doc, fuentes, limpiar, rgb, cabecera, paginasPropias) {
    var pagina = null;
    var y = 0;

    function paginaNueva() {
      pagina = doc.addPage([ANCHO, ALTO]);
      paginasPropias.add(doc.getPageCount() - 1);
      y = ARRIBA;
      if (cabecera) {
        pagina.drawText(cabecera, {
          x: MARGEN,
          y: ALTO - MARGEN + 4,
          size: 9,
          font: fuentes.normal,
          color: rgb(0.45, 0.45, 0.45),
        });
        pagina.drawLine({
          start: { x: MARGEN, y: ALTO - MARGEN - 2 },
          end: { x: ANCHO - MARGEN, y: ALTO - MARGEN - 2 },
          thickness: 0.5,
          color: rgb(0.8, 0.8, 0.8),
        });
      }
    }

    function asegurarSitio(alto) {
      if (!pagina || y - alto < ABAJO) paginaNueva();
    }

    // Escribe un bloque de texto con salto de línea automático.
    function texto(contenido, opciones) {
      var o = opciones || {};
      var fuente = o.negrita ? fuentes.negrita : (o.cursiva ? fuentes.cursiva : fuentes.normal);
      var tam = o.tam || 11;
      var sangria = o.sangria || 0;
      var interlineado = tam * 1.3;
      var color = o.color || rgb(0.1, 0.1, 0.1);
      var lineas = partirEnLineas(limpiar(contenido), fuente, tam, ANCHO_UTIL - sangria);
      for (var i = 0; i < lineas.length; i++) {
        asegurarSitio(interlineado);
        y -= tam;
        if (lineas[i]) {
          pagina.drawText(lineas[i], { x: MARGEN + sangria, y: y, size: tam, font: fuente, color: color });
        }
        y -= interlineado - tam;
      }
    }

    function espacio(pt) {
      y -= pt;
    }

    function linea() {
      asegurarSitio(10);
      y -= 4;
      pagina.drawLine({
        start: { x: MARGEN, y: y },
        end: { x: ANCHO - MARGEN, y: y },
        thickness: 0.7,
        color: rgb(0.75, 0.75, 0.75),
      });
      y -= 8;
    }

    return {
      paginaNueva: paginaNueva,
      texto: texto,
      espacio: espacio,
      linea: linea,
    };
  }

  function extensionDe(nombre) {
    var m = /\.([a-z0-9]+)$/i.exec(nombre || '');
    return m ? m[1].toLowerCase() : '';
  }

  function tipoDeDocumento(doc) {
    var mime = (doc.mimeType || '').toLowerCase();
    var ext = extensionDe(doc.name);
    if (mime === 'application/pdf' || ext === 'pdf') return 'pdf';
    if (mime === 'image/jpeg' || mime === 'image/jpg' || ext === 'jpg' || ext === 'jpeg') return 'jpg';
    if (mime === 'image/png' || ext === 'png') return 'png';
    return 'otro';
  }

  // ---------------------------------------------------------------------
  // Generación
  // ---------------------------------------------------------------------
  async function generar(datos) {
    var PDFLib = await cargarPdfLib();
    var PDFDocument = PDFLib.PDFDocument;
    var StandardFonts = PDFLib.StandardFonts;
    var rgb = PDFLib.rgb;

    var doc = await PDFDocument.create();
    doc.setTitle(datos.tripName || 'Viaje');
    doc.setCreator('Alventus');
    doc.setProducer('Alventus');

    var fuentes = {
      normal: await doc.embedFont(StandardFonts.Helvetica),
      negrita: await doc.embedFont(StandardFonts.HelveticaBold),
      cursiva: await doc.embedFont(StandardFonts.HelveticaOblique),
    };
    var limpiar = crearLimpiador(fuentes.normal);

    // Páginas hechas aquí (las que llevan pie con número). Las páginas
    // copiadas de los documentos se dejan tal cual, sin escribir encima,
    // para no tapar nada de su contenido.
    var paginasPropias = new Set();

    // Cabecera de cada página: el nombre del viaje, recortado a una línea
    // por si es muy largo.
    var cabecera = partirEnLineas(limpiar(datos.tripName || ''), fuentes.normal, 9, ANCHO_UTIL)[0] || '';
    var escritor = crearEscritor(doc, fuentes, limpiar, rgb, cabecera, paginasPropias);

    // --- Portada -------------------------------------------------------
    escritor.paginaNueva();
    escritor.espacio(120);
    escritor.texto(datos.tripName || 'Viaje', { negrita: true, tam: 26 });
    escritor.espacio(6);
    if (datos.subtitle) escritor.texto(datos.subtitle, { tam: 14, color: rgb(0.3, 0.3, 0.3) });
    escritor.espacio(24);
    var contenido = datos.includeDocuments ? 'Etapas, tareas y documentos' : 'Etapas y tareas';
    escritor.texto(contenido, { tam: 12, color: rgb(0.3, 0.3, 0.3) });
    if (datos.generatedAt) {
      escritor.texto('Generado el ' + datos.generatedAt, { tam: 10, color: rgb(0.5, 0.5, 0.5) });
    }

    // --- Etapas: cada una empieza en página nueva ----------------------
    var etapas = datos.stages || [];
    for (var s = 0; s < etapas.length; s++) {
      var etapa = etapas[s];
      escritor.paginaNueva();
      escritor.texto(etapa.title || 'Etapa', { negrita: true, tam: 18 });
      if (etapa.subtitle) {
        escritor.texto(etapa.subtitle, { tam: 11, color: rgb(0.4, 0.4, 0.4) });
      }
      if (etapa.description) {
        escritor.espacio(6);
        escritor.texto(etapa.description, { tam: 12 });
      }
      escritor.linea();

      var tareas = etapa.tasks || [];
      if (tareas.length === 0) {
        escritor.texto('Sin tareas', { cursiva: true, tam: 11, color: rgb(0.5, 0.5, 0.5) });
      }
      for (var t = 0; t < tareas.length; t++) {
        var tarea = tareas[t];
        var titulo = tarea.time ? tarea.time + '   ' + (tarea.name || '') : (tarea.name || '');
        escritor.texto(titulo, { negrita: true, tam: 12 });
        if (tarea.description) {
          escritor.texto(tarea.description, { tam: 11, sangria: 14, color: rgb(0.25, 0.25, 0.25) });
        }
        escritor.espacio(8);
      }
    }

    // --- Documentos: cada uno empieza en página nueva -------------------
    var documentos = datos.includeDocuments ? (datos.documents || []) : [];
    if (documentos.length > 0) {
      // Índice: se rellena al final, cuando ya se sabe en qué página
      // empieza cada documento.
      escritor.paginaNueva();
      var paginaIndice = doc.getPageCount() - 1;
      var inicios = [];

      for (var d = 0; d < documentos.length; d++) {
        var documento = documentos[d];
        inicios.push(doc.getPageCount() + 1); // número de página (desde 1)
        await incluirDocumento(doc, documento, fuentes, limpiar, rgb, cabecera, paginasPropias);
      }

      escribirIndice(doc.getPage(paginaIndice), documentos, inicios, fuentes, limpiar, rgb);
    }

    // --- Pie con número de página, solo en las páginas propias ----------
    var total = doc.getPageCount();
    paginasPropias.forEach(function (indice) {
      var pagina = doc.getPage(indice);
      var pie = 'Página ' + (indice + 1) + ' de ' + total;
      var ancho = fuentes.normal.widthOfTextAtSize(pie, 9);
      pagina.drawText(pie, {
        x: ANCHO - MARGEN - ancho,
        y: MARGEN - 18,
        size: 9,
        font: fuentes.normal,
        color: rgb(0.5, 0.5, 0.5),
      });
    });

    return doc;
  }

  function escribirIndice(pagina, documentos, inicios, fuentes, limpiar, rgb) {
    var y = ARRIBA - 18;
    pagina.drawText('Documentos del viaje', { x: MARGEN, y: y, size: 18, font: fuentes.negrita });
    y -= 30;
    for (var i = 0; i < documentos.length; i++) {
      if (y < ABAJO + 12) break; // listas enormes: lo que no quepa, no se indexa
      var numero = 'pág. ' + inicios[i];
      var anchoNumero = fuentes.normal.widthOfTextAtSize(numero, 11);
      var nombre = limpiar(documentos[i].name || 'Documento');
      var max = ANCHO_UTIL - anchoNumero - 16;
      while (nombre.length > 1 && fuentes.normal.widthOfTextAtSize(nombre, 11) > max) {
        nombre = nombre.slice(0, -2) + '…';
        nombre = nombre.replace(/……$/, '…');
      }
      pagina.drawText((i + 1) + '. ' + nombre, { x: MARGEN, y: y, size: 11, font: fuentes.normal });
      pagina.drawText(numero, {
        x: ANCHO - MARGEN - anchoNumero,
        y: y,
        size: 11,
        font: fuentes.normal,
        color: rgb(0.4, 0.4, 0.4),
      });
      y -= 18;
    }
  }

  // Página de aviso para lo que no se puede incluir (un formato que no se
  // puede meter en un PDF, un PDF protegido o dañado...). Así el hueco del
  // documento se ve y se sabe por qué no está, en vez de desaparecer.
  function paginaDeAviso(doc, documento, motivo, fuentes, limpiar, rgb, cabecera, paginasPropias) {
    var escritor = crearEscritor(doc, fuentes, limpiar, rgb, cabecera, paginasPropias);
    escritor.paginaNueva();
    escritor.texto(documento.name || 'Documento', { negrita: true, tam: 16 });
    escritor.espacio(10);
    escritor.texto(motivo, { tam: 12, color: rgb(0.35, 0.35, 0.35) });
    escritor.espacio(6);
    escritor.texto('Puedes abrirlo desde la app, en los documentos del viaje.', {
      tam: 11,
      color: rgb(0.5, 0.5, 0.5),
    });
  }

  // Regla de oro: un documento que falle (dañado, raro, lo que sea) no
  // puede estropear el PDF entero. Si algo sale mal a mitad, se quitan
  // las páginas que hubiera llegado a añadir y en su lugar se pone una
  // página de aviso; el resto de documentos sigue adelante.
  //
  // Caso real que lo motivó, visto en las pruebas: un PDF dañado que
  // pdf-lib acepta al abrirlo (es muy tolerante) pero que luego revienta
  // al pedirle sus páginas, fuera de cualquier comprobación previa.
  async function incluirDocumento(doc, documento, fuentes, limpiar, rgb, cabecera, paginasPropias) {
    var paginasAntes = doc.getPageCount();
    try {
      await incluirDocumentoSinProteger(doc, documento, fuentes, limpiar, rgb, cabecera, paginasPropias);
    } catch (e) {
      console.warn('No se ha podido incluir "' + documento.name + '":', e);
      while (doc.getPageCount() > paginasAntes) {
        var ultima = doc.getPageCount() - 1;
        doc.removePage(ultima);
        paginasPropias.delete(ultima);
      }
      paginaDeAviso(doc, documento, 'Este documento está dañado y no se ha podido incluir.',
        fuentes, limpiar, rgb, cabecera, paginasPropias);
    }
  }

  async function incluirDocumentoSinProteger(doc, documento, fuentes, limpiar, rgb, cabecera, paginasPropias) {
    var tipo = tipoDeDocumento(documento);

    if (!documento.base64) {
      paginaDeAviso(doc, documento, 'No se ha podido descargar este documento.',
        fuentes, limpiar, rgb, cabecera, paginasPropias);
      return;
    }

    if (tipo === 'pdf') {
      var origen;
      try {
        origen = await window.PDFLib.PDFDocument.load(documento.base64, {
          ignoreEncryption: true,
          updateMetadata: false,
        });
      } catch (e) {
        paginaDeAviso(doc, documento, 'Este PDF está dañado y no se ha podido leer.',
          fuentes, limpiar, rgb, cabecera, paginasPropias);
        return;
      }
      // pdf-lib no sabe descifrar PDFs protegidos con contraseña: si se
      // copiaran igualmente, saldrían páginas en blanco o con basura.
      if (origen.isEncrypted) {
        paginaDeAviso(doc, documento, 'Este PDF está protegido y no se puede incluir aquí.',
          fuentes, limpiar, rgb, cabecera, paginasPropias);
        return;
      }
      var paginas = await doc.copyPages(origen, origen.getPageIndices());
      if (paginas.length === 0) {
        paginaDeAviso(doc, documento, 'Este PDF no tiene páginas.',
          fuentes, limpiar, rgb, cabecera, paginasPropias);
        return;
      }
      for (var i = 0; i < paginas.length; i++) doc.addPage(paginas[i]);
      return;
    }

    if (tipo === 'jpg' || tipo === 'png') {
      var imagen;
      try {
        imagen = tipo === 'jpg'
          ? await doc.embedJpg(documento.base64)
          : await doc.embedPng(documento.base64);
      } catch (e) {
        paginaDeAviso(doc, documento, 'Esta imagen está dañada y no se ha podido leer.',
          fuentes, limpiar, rgb, cabecera, paginasPropias);
        return;
      }
      var pagina = doc.addPage([ANCHO, ALTO]);
      paginasPropias.add(doc.getPageCount() - 1);
      var titulo = limpiar(documento.name || 'Imagen');
      pagina.drawText(titulo, { x: MARGEN, y: ALTO - MARGEN - 10, size: 12, font: fuentes.negrita });
      var altoDisponible = ALTO - 2 * MARGEN - 40;
      var escala = Math.min(ANCHO_UTIL / imagen.width, altoDisponible / imagen.height, 1);
      var w = imagen.width * escala;
      var h = imagen.height * escala;
      pagina.drawImage(imagen, {
        x: MARGEN + (ANCHO_UTIL - w) / 2,
        y: ALTO - MARGEN - 30 - h,
        width: w,
        height: h,
      });
      return;
    }

    var ext = extensionDe(documento.name);
    paginaDeAviso(doc, documento,
      'Este tipo de archivo' + (ext ? ' (.' + ext + ')' : '') +
        ' no se puede meter dentro de un PDF, así que aquí solo aparece su nombre.',
      fuentes, limpiar, rgb, cabecera, paginasPropias);
  }

  // Punto de entrada desde Dart. Devuelve 'ok' o 'error: <motivo>'
  // (nunca lanza: así el lado de Dart solo tiene que mirar el texto).
  window.buildTripPdf = async function (json, nombreArchivo) {
    try {
      var datos = JSON.parse(json);
      var doc = await generar(datos);
      var base64 = await doc.saveAsBase64();
      if (typeof window.saveBytesAsFile !== 'function') {
        return 'error: no está disponible la descarga de archivos';
      }
      var ok = window.saveBytesAsFile(base64, 'application/pdf', nombreArchivo || 'viaje.pdf');
      return ok ? 'ok' : 'error: el navegador no ha permitido descargar el PDF';
    } catch (e) {
      console.error('buildTripPdf:', e);
      return 'error: ' + ((e && e.message) || String(e));
    }
  };
})();
