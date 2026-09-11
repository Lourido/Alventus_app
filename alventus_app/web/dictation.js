// Dictado por voz 100% local (dentro del propio navegador, via
// WebAssembly), pensado para iPhone/Safari, donde el reconocimiento de
// voz nativo del navegador (Web Speech API) no funciona nunca -- es un
// bug conocido y sin arreglar de WebKit/Safari, no de esta app.
//
// No manda el audio a ningun servidor: la transcripcion corre entera
// en el propio telefono usando @xenova/transformers (una version de
// Whisper compilada a WebAssembly). El modelo se descarga la primera
// vez que se usa y luego queda cacheado por el propio navegador
// (Cache Storage), asi que a partir de ahi funciona tambien sin
// conexion. Cual modelo exactamente: ver la nota en la constante
// MODEL_ID mas abajo.
//
// Expone unas pocas funciones sueltas en "window" (en vez de un modulo
// ES, para no complicar la interoperabilidad con Dart): esta pensado
// para llamarse desde lib/widgets/speech/local_dictation.dart.
(function () {
  let transformersModule = null;
  let transcriber = null;
  let mediaRecorder = null;
  let chunks = [];
  let activeStream = null;
  let loadingPromise = null;

  async function ensureTransformers() {
    if (!transformersModule) {
      transformersModule = await import('https://cdn.jsdelivr.net/npm/@xenova/transformers@2.17.2');
      transformersModule.env.allowLocalModels = false;
      transformersModule.env.useBrowserCache = true;
    }
    return transformersModule;
  }

  window.dictationIsSupported = function () {
    return !!(navigator.mediaDevices && window.MediaRecorder);
  };

  window.dictationIsLoaded = function () {
    return !!transcriber;
  };

  // Pide permiso de micrófono por su cuenta, sin grabar nada (solo abre
  // y cierra el micrófono al momento). Se llama ANTES de descargar el
  // modelo: en iPhone, cuando la app está añadida a la pantalla de
  // inicio (modo standalone), la primera vez que una página pide el
  // micrófono puede hacer que Safari recargue la app -- pidiéndolo aquí,
  // antes de la descarga pesada del modelo, esa recarga (si pasa) es
  // barata, en vez de perder una descarga de varios MB ya hecha.
  window.dictationRequestMicPermission = async function () {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      stream.getTracks().forEach(function (t) { t.stop(); });
      return true;
    } catch (e) {
      console.error('dictationRequestMicPermission error:', e);
      return false;
    }
  };

  // Descarga e inicializa el modelo. Se puede llamar varias veces
  // seguidas (p. ej. desde dos campos de texto distintos) sin que se
  // dispare la descarga dos veces: la segunda llamada espera a que
  // termine la primera.
  // "tiny" en vez de "base": en iPhone, con la app anadida a la
  // pantalla de inicio (modo standalone), cargar el modelo "base"
  // (unos 150 MB) parecia hacer que Safari reiniciara la app a mitad
  // de carga -- probablemente por quedarse sin memoria, ya que el
  // propio motor de Flutter (CanvasKit) tambien usa bastante memoria
  // a la vez. "tiny" (unos 40 MB) reduce mucho ese riesgo; ya se
  // probo por separado y reconoce bien el espanol.
  const MODEL_ID = 'Xenova/whisper-tiny';

  window.dictationLoad = function () {
    if (transcriber) return Promise.resolve(true);
    if (loadingPromise) return loadingPromise;

    loadingPromise = (async () => {
      try {
        const mod = await ensureTransformers();
        transcriber = await mod.pipeline('automatic-speech-recognition', MODEL_ID, {
          quantized: true,
        });
        return true;
      } catch (e) {
        console.error('dictationLoad error:', e);
        transcriber = null;
        return false;
      } finally {
        loadingPromise = null;
      }
    })();

    return loadingPromise;
  };

  async function resampleTo16kMono(blob) {
    const arrayBuffer = await blob.arrayBuffer();
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    const audioCtx = new AudioCtx();
    const decoded = await audioCtx.decodeAudioData(arrayBuffer);
    const targetLength = Math.ceil(decoded.duration * 16000);
    const offlineCtx = new OfflineAudioContext(1, targetLength, 16000);
    const source = offlineCtx.createBufferSource();
    source.buffer = decoded;
    source.connect(offlineCtx.destination);
    source.start();
    const rendered = await offlineCtx.startRendering();
    audioCtx.close();
    return rendered.getChannelData(0);
  }

  window.dictationStart = async function () {
    if (!transcriber) throw new Error('El modelo de dictado todavia no esta cargado');
    chunks = [];
    activeStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    mediaRecorder = new MediaRecorder(activeStream);
    mediaRecorder.ondataavailable = function (e) {
      if (e.data && e.data.size > 0) chunks.push(e.data);
    };
    mediaRecorder.start();
    return true;
  };

  // Para de grabar y devuelve el texto transcrito (cadena vacia si no
  // se reconocio nada o no habia nada grabado).
  window.dictationStop = async function () {
    if (!mediaRecorder || mediaRecorder.state === 'inactive') return '';

    const stopped = new Promise(function (resolve) {
      mediaRecorder.onstop = resolve;
    });
    mediaRecorder.stop();
    if (activeStream) {
      activeStream.getTracks().forEach(function (t) { t.stop(); });
      activeStream = null;
    }
    await stopped;

    const recordedChunks = chunks;
    chunks = [];
    if (recordedChunks.length === 0) return '';

    const blob = new Blob(recordedChunks, { type: mediaRecorder.mimeType || 'audio/webm' });
    if (blob.size === 0) return '';

    const audioData = await resampleTo16kMono(blob);
    if (!transcriber) return '';
    const output = await transcriber(audioData, { language: 'spanish', task: 'transcribe' });
    return (output && output.text) ? output.text.trim() : '';
  };

  // Por si el usuario cancela a medio grabar (p. ej. cierra el diálogo
  // sin terminar): corta el micrófono sin intentar transcribir nada.
  window.dictationCancel = function () {
    if (mediaRecorder && mediaRecorder.state !== 'inactive') {
      try { mediaRecorder.stop(); } catch (e) { /* nada que hacer */ }
    }
    if (activeStream) {
      activeStream.getTracks().forEach(function (t) { t.stop(); });
      activeStream = null;
    }
    chunks = [];
  };
})();
