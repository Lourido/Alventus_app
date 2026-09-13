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

const CACHE_NAME = 'alventus-offline-v2';

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
  'sqlite3.wasm',
  'sqflite_sw.js',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'icons/Icon-maskable-192.png',
  'icons/Icon-maskable-512.png',
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE_NAME);
      await Promise.all(
        PRECACHE_URLS.map(async (url) => {
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
        const networkResponse = await fetch(request);
        if (networkResponse && networkResponse.ok) {
          const cache = await caches.open(CACHE_NAME);
          cache.put(request, networkResponse.clone());
        }
        return networkResponse;
      } catch (err) {
        const cached = await caches.match(request);
        if (cached) return cached;
        throw err;
      }
    })()
  );
});