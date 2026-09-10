// Descarga de archivos en Flutter Web.
//
// Sustituye al mecanismo anterior (URL de datos "data:" abierta con
// url_launcher / window.open), que en iPhone/Safari fallaba en dos
// casos frecuentes:
//  a) archivos grandes: Safari tiene un límite de tamaño para las URLs
//     de datos abiertas en una pestaña nueva, y una foto o un PDF lo
//     superan con facilidad;
//  b) cuando pasa algo de tiempo entre el toque del usuario y la
//     apertura -- por ejemplo, mientras se descarga el archivo de Odoo
//     por la red -- Safari deja de considerarlo una acción directa del
//     usuario y bloquea la apertura en silencio, sin avisar de nada.
//
// Un Blob real + un enlace <a download> no tiene ninguno de los dos
// problemas: no hay límite de tamaño práctico, y no abre pestaña ni
// ventana nueva (es una descarga dentro de la misma página), así que
// no lo bloquea el bloqueador de pop-ups.
window.saveBytesAsFile = function (base64Data, mimeType, fileName) {
  try {
    const binaryString = atob(base64Data);
    const len = binaryString.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }
    const blob = new Blob([bytes], { type: mimeType || 'application/octet-stream' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = fileName || 'archivo';
    link.rel = 'noopener';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    // Dar tiempo a que el navegador empiece la descarga antes de liberar
    // la URL del Blob.
    setTimeout(function () {
      URL.revokeObjectURL(url);
    }, 30000);
    return true;
  } catch (e) {
    console.error('saveBytesAsFile error:', e);
    return false;
  }
};
