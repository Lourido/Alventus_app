{{flutter_js}}
{{flutter_build_config}}

// Arranque de la app. Es la plantilla que usa "flutter build web" para
// generar build/web/flutter_bootstrap.js: las dos líneas de arriba las
// rellena Flutter solo al compilar (NO tocarlas).
//
// Por qué existe este archivo (antes se usaba el que genera Flutter por su
// cuenta): el de Flutter registraba SU service worker
// (flutter_service_worker.js), que está vacío a propósito y lo primero que
// hace es darse de baja... en la MISMA dirección donde vive el nuestro,
// offline_sw.js (el que permite usar la app sin cobertura y recibe los
// avisos). Los dos se pisaban en cada arranque. Para la app sin cobertura
// se notaba poco, pero los avisos van atados al service worker: cada vez
// que Flutter lo daba de baja, el teléfono perdía la suscripción y dejaba
// de recibir avisos. Así que aquí se arranca la app SIN service worker de
// Flutter; el único es offline_sw.js, que registra index.html.
_flutter.loader.load();
