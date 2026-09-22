// Avisos (notificaciones push) en el teléfono.
//
// Lo usa lib/utils/push_notifications.dart. El servidor (Odoo, ver
// models/push_notification.py del módulo) es quien manda los avisos; aquí
// solo se pide permiso al usuario y se crea la "suscripción" del teléfono,
// que la app manda después a Odoo.
//
// Quien recibe los avisos es el service worker offline_sw.js (eventos
// "push" y "notificationclick"), aunque la app esté cerrada.
//
// Requisitos (si no se cumplen, alventusPushStatus lo dice):
//  - iPhone: iOS 16.4 o superior y la app AÑADIDA A LA PANTALLA DE INICIO.
//    Desde Safari normal, Apple no deja recibir avisos.
//  - Android: Chrome (u otro navegador moderno).
//
// OJO: alventusPushEnable tiene que llamarse directamente desde el toque
// de un botón (sin esperas antes): el iPhone solo deja pedir permiso de
// avisos en ese instante.

(function () {
  'use strict';

  function aBytes(base64url) {
    var s = String(base64url || '').replace(/-/g, '+').replace(/_/g, '/');
    while (s.length % 4) s += '=';
    var bin = atob(s);
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  function aBase64url(buffer) {
    if (!buffer) return '';
    var bytes = new Uint8Array(buffer);
    var bin = '';
    for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  function esIOS() {
    var ua = navigator.userAgent || '';
    return /iPad|iPhone|iPod/.test(ua) ||
      (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  }

  function instalada() {
    try {
      return navigator.standalone === true ||
        window.matchMedia('(display-mode: standalone)').matches;
    } catch (e) {
      return false;
    }
  }

  function zonaHoraria() {
    try {
      return Intl.DateTimeFormat().resolvedOptions().timeZone || '';
    } catch (e) {
      return '';
    }
  }

  function descripcionDispositivo() {
    var ua = navigator.userAgent || '';
    if (/iPhone/.test(ua)) return 'iPhone';
    if (/iPad/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) return 'iPad';
    if (/Android/.test(ua)) return 'Android';
    if (/Windows/.test(ua)) return 'Windows';
    if (/Macintosh/.test(ua)) return 'Mac';
    return 'Navegador';
  }

  function aTexto(sub) {
    var json = sub.toJSON ? sub.toJSON() : {};
    var keys = json.keys || {};
    return JSON.stringify({
      endpoint: sub.endpoint,
      p256dh: keys.p256dh || aBase64url(sub.getKey && sub.getKey('p256dh')),
      auth: keys.auth || aBase64url(sub.getKey && sub.getKey('auth')),
      timezone: zonaHoraria(),
      device: descripcionDispositivo(),
    });
  }

  // El service worker que recibe los avisos es offline_sw.js (el mismo
  // que permite usar la app sin cobertura). Se asegura que está registrado
  // y activo antes de suscribirse.
  async function registro() {
    var reg = await navigator.serviceWorker.getRegistration();
    var activo = reg && (reg.active || reg.waiting || reg.installing);
    var url = activo ? (activo.scriptURL || '') : '';
    if (!reg || url.indexOf('offline_sw.js') < 0) {
      await navigator.serviceWorker.register('offline_sw.js');
    }
    return navigator.serviceWorker.ready;
  }

  // Estado: 'unsupported' (este navegador no puede), 'ios-needs-install'
  // (iPhone sin la app en la pantalla de inicio), 'denied' (el usuario
  // bloqueó los avisos), 'default' (aún no se ha preguntado) o 'granted'.
  window.alventusPushStatus = function () {
    try {
      if (esIOS() && !instalada()) return 'ios-needs-install';
      if (!('serviceWorker' in navigator) || !('PushManager' in window) ||
          !('Notification' in window)) {
        return 'unsupported';
      }
      return Notification.permission || 'default';
    } catch (e) {
      return 'unsupported';
    }
  };

  // Pide permiso y suscribe el teléfono. Devuelve el JSON de la
  // suscripción ({endpoint, p256dh, auth, timezone, device}) o
  // 'denied' / 'default' / 'error: ...'.
  window.alventusPushEnable = function (clavePublica) {
    var permiso;
    try {
      // Tiene que ir lo PRIMERO, sin nada asíncrono antes (ver arriba).
      permiso = Notification.requestPermission();
    } catch (e) {
      return Promise.resolve('error: ' + ((e && e.message) || String(e)));
    }
    return (async function () {
      try {
        var resultado = await permiso;
        if (resultado !== 'granted') return resultado || 'default';
        var reg = await registro();
        var clave = aBytes(clavePublica);
        var sub = await reg.pushManager.getSubscription();
        if (sub) {
          // Si la suscripción era de otra clave del servidor, se rehace.
          var actual = sub.options && sub.options.applicationServerKey;
          if (actual && aBase64url(actual) !== aBase64url(clave)) {
            await sub.unsubscribe();
            sub = null;
          }
        }
        if (!sub) {
          sub = await reg.pushManager.subscribe({
            userVisibleOnly: true,
            applicationServerKey: clave,
          });
        }
        return aTexto(sub);
      } catch (e) {
        console.error('alventusPushEnable:', e);
        return 'error: ' + ((e && e.message) || String(e));
      }
    })();
  };

  // La suscripción actual (JSON como el de arriba) o '' si no hay o no hay
  // permiso. No pregunta nada al usuario.
  window.alventusPushCurrent = async function () {
    try {
      if (window.alventusPushStatus() !== 'granted') return '';
      var reg = await navigator.serviceWorker.getRegistration();
      if (!reg) return '';
      var sub = await reg.pushManager.getSubscription();
      return sub ? aTexto(sub) : '';
    } catch (e) {
      return '';
    }
  };

  // Da de baja la suscripción de este teléfono. Devuelve su endpoint (para
  // borrarla también en Odoo) o ''.
  window.alventusPushDisable = async function () {
    try {
      var reg = await navigator.serviceWorker.getRegistration();
      if (!reg) return '';
      var sub = await reg.pushManager.getSubscription();
      if (!sub) return '';
      var endpoint = sub.endpoint;
      await sub.unsubscribe();
      return endpoint;
    } catch (e) {
      return '';
    }
  };
})();
