'use strict';

// Service worker "de verdad" para que la app funcione sin conexión
// (modo avión / sin cobertura).
//
// Por qué hace falta este archivo: desde hace unas cuantas versiones,
// Flutter ya NO genera un service worker que guarde nada en caché --
// el "flutter_service_worker.js" que genera el propio `flutter build
// web` se desregistra solo nada más activarse (es un archivo vacío a
// propósito, ver flutter.dev/to/web-service-worker-faq). Además, en
// nginx configuramos a propósito "Cache-Control: no-cache,
// must-revalidate" en index.html/main.dart.js/etc. para que la app se
// actualizara sola tras cada despliegue (ver pwa-status.md, sección de
// caché) -- pero eso significa que, SIN ese repaso con el servidor
// (que en modo avión no puede completarse nunca), el navegador no
// tiene permiso para usar su copia guardada y la carga falla del
// todo. Entre las dos cosas, la app no tenía ninguna forma de
// arrancar sin conexión.
//
// Estrategia: "red primero, caché de reserva". Con conexión, se pide
// siempre la versión más reciente al servidor (para no perder el
// arreglo de "la app se queda desactualizada"); cada respuesta buena
// se guarda también en una caché propia. Sin conexión, si la petición
// a la red falla, se sirve la última copia buena que hubiera guardada.
//
// IMPORTANTE (v2): con solo lo de arriba no basta. Esta app es de una
// sola página (SPA): una vez arrancada, moverse por las pantallas NO
// vuelve a pedir index.html/main.dart.js/etc. al servidor, así que si
// nadie ha "pasado" antes por el service worker pidiendo esos
// archivos, nunca llegan a guardarse en caché -- y en una instalación
// nueva, el registro del service worker se hace a propósito después
// del evento "load" de la página (para no retrasar el primer
// arranque), con lo que la primera carga de todos los archivos
// esenciales ocurre ANTES de que este service worker exista siquiera.
// Resultado real observado: el usuario abre la app recién instalada,
// navega con conexión sin problema, pero al probar el modo avión
// después sale una pantalla en blanco -- porque, pese a haber usado
// la app "en línea", nada se había guardado todavía en la caché.
//
// Por eso, en el evento "install" precargamos a propósito (con
// fetch() directo desde aquí, sin depender de que la página los pida)
// los archivos imprescindibles para arrancar: el propio index.html,
// el motor de Flutter (main.dart.js, flutter_bootstrap.js), nuestros
// scripts (dictation.js, file_saver.js), el manifest/iconos de la PWA,
// y los archivos de la base de datos local (sqlite3.wasm,
// sqflite_sw.js) -- sin esto último la app arrancaría pero la base de
// datos local (sqflite_common_ffi_web) no podría inicializarse sin
// conexión. Que falle la precarga de alguno de ellos (por ejemplo, si
// el nombre cambiara en un futuro build) no debe impedir que el
// service worker se instale igualmente -- por eso cada descarga va en
// su propio try/catch.
//
// Solo se cachean peticiones GET al propio sitio (mismo origen); las
// llamadas a Odoo (JSON-RPC, que además son POST) y cualquier recurso
// de otro dominio (por ejemplo el modelo de dictado, cargado desde un
// CDN, o CanvasKit desde gstatic.com) se dejan pasar tal cual, sin
// tocarlas aquí -- ver pwa-status.md para el porqué de este último
// caso concreto.

const CACHE_NAME = 'alventus-offline-v5';

// Rutas relativas a la carpeta donde vive este propio archivo (que es
// la misma carpeta donde se despliega toda la app), para que funcionen
// igual sin importar bajo qué ruta del servidor esté publicada la PWA.
const PRECACHE_URLS = [
  './',
  'index.html',
  'main.dart.js',
  'flutter_bootstrap.js',
  'manifest.json',
  'favicon.png',
  'dictation.js',
  'file_saver.js',
  // Generador del PDF del viaje y la librería que usa. Se precargan para
  // que "Generar PDF > Etapas y tareas" funcione también sin cobertura.
  'trip_pdf.js',
  'pdf-lib.min.js',
  'sqlite3.wasm',
  'sqflite_sw.js',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'icons/Icon-maskable-192.png',
  'icons/Icon-maskable-512.png',
  // Recursos que Flutter pide nada más arrancar. Si faltan, la app sale
  // con los iconos y el logo rotos. Se guardaban solos, pero solo a
  // partir de la SEGUNDA vez que se abría la app con conexión (este
  // service worker se registra al final de la carga, así que la primera
  // vez ni se entera de que se piden). Precargándolos, basta con la
  // primera. Que alguno no exista en un build futuro no rompe nada: cada
  // descarga va en su propio try/catch.
  'assets/FontManifest.json',
  'assets/AssetManifest.bin.json',
  'assets/AssetManifest.json',
  'assets/NOTICES',
  'assets/fonts/MaterialIcons-Regular.otf',
  'assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
  'assets/assets/logo_alventus.png',
  'assets/assets/splash_background.png',
];

// El motor gráfico de Flutter (CanvasKit). Sin esto la app no dibuja
// NADA, así que es tan imprescindible como main.dart.js. Solo se puede
// guardar porque ahora se carga de aquí y no de www.gstatic.com (ver el
// comentario del index.html); mientras venía de fuera, este service
// worker no podía tocarlo, y por eso al arrancar sin cobertura salía la
// pantalla en blanco.
//
// Hay dos versiones y NO son intercambiables: los navegadores basados en
// Chromium (Chrome, Edge y, por tanto, Android) usan la de la subcarpeta
// "chromium", y los demás (Safari, iPhone) la normal. Se guarda solo la
// que vaya a usar este navegador, para no descargar de más: son varios
// megas cada una.
//
// Si el navegador no se reconociera bien y se guardara la que no es, la
// app no se queda rota para siempre: la segunda vez que se abra con
// conexión, este service worker ya está activo, ve la petición de la
// buena y la guarda.
const ES_CHROMIUM = /Chrom(e|ium)|Edg\/|OPR\//.test(
  (self.navigator && self.navigator.userAgent) || ''
);

const CANVASKIT_URLS = ES_CHROMIUM
  ? ['canvaskit/chromium/canvaskit.js', 'canvaskit/chromium/canvaskit.wasm']
  : ['canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm'];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE_NAME);
      await Promise.all(
        PRECACHE_URLS.concat(CANVASKIT_URLS).map(async (url) => {
          try {
            const response = await fetch(url, { cache: 'no-store' });
            if (response && response.ok) {
              await cache.put(url, response);
            }
          } catch (err) {
            // No pasa nada si uno solo falla (por ejemplo, sin
            // conexión durante la propia instalación): el resto se
            // sigue guardando y el service worker se instala igual.
          }
        })
      );
    })()
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      // Limpia cachés de versiones anteriores de este mismo service
      // worker (por ejemplo "alventus-offline-v1"), para no dejar
      // copias viejas acumulándose sin usarse.
      const names = await caches.keys();
      await Promise.all(
        names
          .filter((name) => name !== CACHE_NAME)
          .map((name) => caches.delete(name))
      );
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;

  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  event.respondWith(
    (async () => {
      try {
        // "no-cache": pregunta SIEMPRE al servidor si el archivo ha
        // cambiado (si no, contesta "sin cambios" y apenas gasta datos).
        // Sin esto, fetch() usaba la copia de la caché normal del
        // navegador, y como Odoo marca sus archivos estáticos para
        // guardarse una semana, tras desplegar seguía usando días el
        // trip_pdf.js viejo (el PDF salía sin documentos). Las
        // navegaciones (abrir la app) se dejan tal cual: el navegador ya
        // las revalida y no admiten cambiar este ajuste.
        let networkRequest = request;
        if (request.mode !== 'navigate') {
          try {
            networkRequest = new Request(request, { cache: 'no-cache' });
          } catch (e) {
            networkRequest = request;
          }
        }
        const networkResponse = await fetch(networkRequest);
        if (networkResponse && networkResponse.ok) {
          const cache = await caches.open(CACHE_NAME);
          cache.put(request, networkResponse.clone());
        }
        return networkResponse;
      } catch (err) {
        // Sin red: se busca en la caché. "ignoreSearch" hace que valga
        // la copia guardada aunque la dirección traiga algún "?..." al
        // final que no estuviera cuando se guardó (pasa, por ejemplo,
        // cuando algo añade un parámetro para evitar la caché); sin eso
        // la copia buena estaba ahí pero no se encontraba.
        const cached = await caches.match(request, { ignoreSearch: true });
        if (cached) return cached;

        // Si lo que se pedía era la página en sí (abrir la app), se
        // devuelve el index.html guardado, venga la dirección como
        // venga. Es lo que permite que la app arranque sin cobertura
        // cuando el teléfono la ha descargado de memoria estando en
        // segundo plano.
        if (request.mode === 'navigate') {
          const index =
            (await caches.match('index.html', { ignoreSearch: true })) ||
            (await caches.match('./', { ignoreSearch: true }));
          if (index) return index;
        }

        throw err;
      }
    })()
  );
});