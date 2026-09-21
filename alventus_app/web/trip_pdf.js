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
// lib/utils/trip_pdf.dart —, que genera el PDF y lo deja preparado aquí,
// y después a saveTripPdf() (elegir carpeta) o downloadTripPdf(). Los
// bytes no pasan por Dart: con documentos grandes, mover varios megas de
// un lado a otro para nada solo gastaría memoria del teléfono. Ver el
// final del archivo para el porqué de los dos pasos.
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
  // Líneas del índice por página: con 17 pt por línea y 6 pt de aire antes
  // de cada etapa, 28 caben siempre, incluso en el peor caso (todo etapas):
  // 28 * 23 = 644 pt de los ~660 que quedan bajo el título.
  var LINEAS_POR_PAGINA_INDICE = 28;

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

  // Los archivos de ruta (GPX, KML...) no van en el PDF: no se pueden
  // leer impresos y el usuario los tiene aparte, en "Archivos de ruta".
  // La app ya no los manda; esto es solo por si acaso.
  var EXTENSIONES_DE_RUTA = ['gpx', 'kml', 'kmz', 'tcx', 'fit', 'geojson'];
  function sinRutas(documentos) {
    return documentos.filter(function (d) {
      return d && EXTENSIONES_DE_RUTA.indexOf(extensionDe(d.name)) < 0;
    });
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
    if (datos.includeDocuments) {
      var numDocs = sinRutas(datos.generalDocuments || datos.documents || []).length +
        (datos.stages || []).reduce(function (n, e) { return n + sinRutas(e.documents || []).length; }, 0);
      escritor.texto(numDocs === 0
        ? 'Este viaje no tiene documentos.'
        : (numDocs === 1 ? '1 documento incluido' : numDocs + ' documentos incluidos'),
        { tam: 10, color: rgb(0.5, 0.5, 0.5) });
    }
    if (datos.generatedAt) {
      escritor.texto('Generado el ' + datos.generatedAt, { tam: 10, color: rgb(0.5, 0.5, 0.5) });
    }

    // --- Qué documentos van y dónde -------------------------------------
    // Los documentos generales del viaje (los de "Datos generales") van
    // ANTES de las etapas; los de cada etapa, al final de SU etapa. Cada
    // documento empieza siempre en una página nueva. Los archivos de ruta
    // (GPX, KML...) no se incluyen nunca.
    var incluir = !!datos.includeDocuments;
    var etapas = datos.stages || [];
    var generales = incluir ? sinRutas(datos.generalDocuments || datos.documents || []) : [];
    var docsDeEtapa = etapas.map(function (e) {
      return incluir ? sinRutas(e.documents || []) : [];
    });
    var hayDocumentos = generales.length > 0 ||
      docsDeEtapa.some(function (l) { return l.length > 0; });

    // --- Índice (solo con documentos) -----------------------------------
    // Se reservan aquí sus páginas y se rellenan al final, cuando ya se
    // sabe en qué página empieza cada cosa.
    var indice = [];
    var paginasIndice = [];
    if (hayDocumentos) {
      var lineasIndice = (generales.length > 0 ? 1 + generales.length : 0) + etapas.length +
        docsDeEtapa.reduce(function (n, l) { return n + l.length; }, 0);
      var numPaginasIndice = Math.max(1, Math.ceil(lineasIndice / LINEAS_POR_PAGINA_INDICE));
      for (var r = 0; r < numPaginasIndice; r++) {
        escritor.paginaNueva();
        paginasIndice.push(doc.getPageCount() - 1);
      }
    }

    // --- Documentos generales del viaje ---------------------------------
    if (generales.length > 0) {
      indice.push({ texto: 'Documentos del viaje', nivel: 0, pagina: doc.getPageCount() + 1 });
      for (var g = 0; g < generales.length; g++) {
        indice.push({ texto: generales[g].name || 'Documento', nivel: 1, pagina: doc.getPageCount() + 1 });
        await incluirDocumento(doc, generales[g], fuentes, limpiar, rgb, cabecera, paginasPropias);
      }
    }

    // --- Etapas: cada una empieza en página nueva ----------------------
    for (var s = 0; s < etapas.length; s++) {
      var etapa = etapas[s];
      escritor.paginaNueva();
      indice.push({ texto: etapa.title || 'Etapa', nivel: 0, pagina: doc.getPageCount() });
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

      // Documentos de esta etapa, al final de la etapa.
      var propios = docsDeEtapa[s];
      if (propios.length > 0) {
        escritor.espacio(6);
        escritor.texto('Documentos de esta etapa (en las páginas siguientes):', {
          cursiva: true, tam: 10, color: rgb(0.45, 0.45, 0.45),
        });
        for (var k = 0; k < propios.length; k++) {
          escritor.texto('- ' + (propios[k].name || 'Documento'), {
            tam: 10, sangria: 10, color: rgb(0.45, 0.45, 0.45),
          });
        }
      }
      for (var d = 0; d < propios.length; d++) {
        indice.push({ texto: propios[d].name || 'Documento', nivel: 1, pagina: doc.getPageCount() + 1 });
        await incluirDocumento(doc, propios[d], fuentes, limpiar, rgb, cabecera, paginasPropias);
      }
    }

    if (paginasIndice.length > 0) {
      escribirIndice(doc, paginasIndice, indice, fuentes, limpiar, rgb);
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

  // Índice: cada etapa (en negrita) con sus documentos debajo, y delante
  // los documentos generales del viaje. Si no cabe en una página, sigue en
  // las siguientes (ya reservadas; ver LINEAS_POR_PAGINA_INDICE).
  function escribirIndice(doc, paginasIndice, entradas, fuentes, limpiar, rgb) {
    for (var p = 0; p < paginasIndice.length; p++) {
      var pagina = doc.getPage(paginasIndice[p]);
      var y = ARRIBA - 18;
      pagina.drawText(p === 0 ? 'Índice' : 'Índice (continuación)', {
        x: MARGEN, y: y, size: 18, font: fuentes.negrita,
      });
      y -= 30;
      var desde = p * LINEAS_POR_PAGINA_INDICE;
      var hasta = Math.min(entradas.length, desde + LINEAS_POR_PAGINA_INDICE);
      for (var i = desde; i < hasta; i++) {
        var e = entradas[i];
        var fuente = e.nivel === 0 ? fuentes.negrita : fuentes.normal;
        var sangria = e.nivel === 0 ? 0 : 16;
        var numero = 'pág. ' + e.pagina;
        var anchoNumero = fuentes.normal.widthOfTextAtSize(numero, 11);
        var nombre = limpiar(e.texto);
        var max = ANCHO_UTIL - sangria - anchoNumero - 16;
        while (nombre.length > 1 && fuente.widthOfTextAtSize(nombre, 11) > max) {
          nombre = nombre.slice(0, -2) + '…';
          nombre = nombre.replace(/……$/, '…');
        }
        if (e.nivel === 0 && i > desde) y -= 6; // aire antes de cada etapa
        pagina.drawText(nombre, { x: MARGEN + sangria, y: y, size: 11, font: fuente });
        pagina.drawText(numero, {
          x: ANCHO - MARGEN - anchoNumero,
          y: y,
          size: 11,
          font: fuentes.normal,
          color: rgb(0.4, 0.4, 0.4),
        });
        y -= 17;
      }
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

  // ---------------------------------------------------------------------
  // Entrada desde Dart y guardado
  // ---------------------------------------------------------------------
  //
  // Va en DOS pasos para que el usuario pueda elegir la carpeta:
  //
  //  1. buildTripPdf(json, nombre) genera el PDF y lo deja preparado aquí
  //     (no lo descarga). Puede tardar: descarga documentos, etc.
  //  2. Luego la app pregunta dónde guardarlo, y el botón llama a
  //     saveTripPdf() o downloadTripPdf().
  //
  // Por qué así: elegir carpeta (showSaveFilePicker) o abrir el menú de
  // compartir del iPhone ("Guardar en Archivos", navigator.share) solo lo
  // permite el navegador justo al tocar un botón. Si se hiciera al final
  // de la generación, ya habría pasado el "toque" y el navegador lo
  // bloquearía. Por eso saveTripPdf pide la carpeta ANTES de su primer
  // await: tiene que ocurrir dentro del propio toque.

  var preparado = null; // { bytes: Uint8Array, nombre: String }

  // Versión de este archivo. La app la comprueba antes de generar: si el
  // navegador tuviera aún una copia vieja, avisa en vez de sacar un PDF
  // incompleto. Subirla (y la de lib/utils/trip_pdf.dart) si cambia el
  // formato de los datos.
  window.tripPdfApiVersion = function () { return 2; };

  window.buildTripPdf = async function (json, nombreArchivo) {
    try {
      preparado = null;
      var datos = JSON.parse(json);
      var doc = await generar(datos);
      var bytes = await doc.save();
      preparado = { bytes: bytes, nombre: nombreArchivo || 'viaje.pdf' };
      return 'ok';
    } catch (e) {
      console.error('buildTripPdf:', e);
      return 'error: ' + ((e && e.message) || String(e));
    }
  };

  function descargar() {
    var blob = new Blob([preparado.bytes], { type: 'application/pdf' });
    var url = URL.createObjectURL(blob);
    var enlace = document.createElement('a');
    enlace.href = url;
    enlace.download = preparado.nombre;
    enlace.rel = 'noopener';
    document.body.appendChild(enlace);
    enlace.click();
    document.body.removeChild(enlace);
    setTimeout(function () { URL.revokeObjectURL(url); }, 60000);
    return 'downloaded';
  }

  function esCancelacion(e) {
    return e && (e.name === 'AbortError');
  }

  // Guardar eligiendo carpeta. Devuelve 'saved' (guardado en la carpeta
  // elegida), 'shared' (se ha usado el menú de compartir: en iPhone,
  // "Guardar en Archivos"), 'downloaded' (este navegador no deja elegir
  // carpeta: va a Descargas), 'cancelled' o 'error: <motivo>'.
  window.saveTripPdf = async function () {
    if (!preparado) return 'error: no hay ningún PDF preparado';
    try {
      // a) Ordenadores y Android con Chrome/Edge modernos: el diálogo de
      //    "Guardar como" del sistema, con elección de carpeta.
      if (typeof window.showSaveFilePicker === 'function') {
        var pedirCarpeta;
        try {
          pedirCarpeta = window.showSaveFilePicker({
            suggestedName: preparado.nombre,
            types: [{ description: 'PDF', accept: { 'application/pdf': ['.pdf'] } }],
          });
        } catch (e) {
          pedirCarpeta = null; // no lo permite aquí: se prueba lo siguiente
        }
        if (pedirCarpeta) {
          try {
            var destino = await pedirCarpeta;
            var escritura = await destino.createWritable();
            await escritura.write(preparado.bytes);
            await escritura.close();
            return 'saved';
          } catch (e) {
            if (esCancelacion(e)) return 'cancelled';
            // No ha dejado (permisos, carpeta protegida...): descarga normal.
            console.warn('showSaveFilePicker:', e);
            return descargar();
          }
        }
      }

      // b) iPhone (y muchos Android): el menú de compartir, que tiene
      //    "Guardar en Archivos" para elegir la carpeta.
      var archivo = null;
      try {
        archivo = new File([preparado.bytes], preparado.nombre, { type: 'application/pdf' });
      } catch (e) {
        archivo = null;
      }
      if (archivo && navigator.canShare && navigator.share &&
          navigator.canShare({ files: [archivo] })) {
        var compartir = navigator.share({ files: [archivo], title: preparado.nombre });
        try {
          await compartir;
          return 'shared';
        } catch (e) {
          if (esCancelacion(e)) return 'cancelled';
          console.warn('navigator.share:', e);
          return descargar();
        }
      }

      // c) Si no hay nada de lo anterior, descarga normal.
      return descargar();
    } catch (e) {
      console.error('saveTripPdf:', e);
      return 'error: ' + ((e && e.message) || String(e));
    }
  };

  // Descarga directa a la carpeta de descargas, sin preguntar.
  window.downloadTripPdf = function () {
    if (!preparado) return 'error: no hay ningún PDF preparado';
    try {
      return descargar();
    } catch (e) {
      console.error('downloadTripPdf:', e);
      return 'error: ' + ((e && e.message) || String(e));
    }
  };

  // Olvida el PDF preparado (libera la memoria del teléfono).
  window.discardTripPdf = function () {
    preparado = null;
  };
})();
