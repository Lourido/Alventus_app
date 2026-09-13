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
// Importante: la primera vez que se instala la app hace falta tener
// conexión al menos una vez (si no, no hay nada guardado todavía que
// poder usar sin conexión). A partir de esa primera vez, ya funciona
// también con el teléfono en modo avión.
//
// Solo se cachean peticiones GET al propio sitio (mismo origen); las
// llamadas a Odoo (JSON-RPC, que además son POST) y cualquier recurso
// de otro dominio (por ejemplo el modelo de dictado, cargado desde un
// CDN) se dejan pasar tal cual, sin tocarlas aquí.

const CACHE_NAME = 'alventus-offline-v1';

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
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
