# Información de lo que está en antena

Keila no trata todos los títulos como canciones. «En antena» puede mostrar una
canción, el nombre de un programa, una entrevista o un boletín, **si la emisora
publica esa información**. El historial y el TXT de sesión registran el mismo
contenido recibido; no identifican audio ni inventan una parrilla.

## Fuentes disponibles

1. **Metadatos del audio mediante mpv:** ICY (`icy-title`, `StreamTitle`),
   título/artista, etiquetas explícitas de programa (`programme-title`,
   `program-title`, `show-title`, `programme`, `program`) y `media-title`.
   Las claves se leen sin distinguir mayúsculas. Se descartan URLs, el nombre
   estático de la emisora y valores no textuales. Una descripción genérica del
   canal no se presenta como programa actual.
2. **Icecast:** JSON público `/status-json.xsl`, leyendo `title` y `artist`
   únicamente del montaje cuyo `listenurl` corresponde al stream actual.
   Si falta `listenurl`, admite un `mount` exacto en el mismo servidor para una
   URL sin query. Se rechazan coincidencias ambiguas.
3. **AzuraCast:** primero `/api/nowplaying_static/{shortcode}.json` cuando la
   entrada tiene una ruta `/listen/{shortcode}/…` o `/hls/{shortcode}/…`;
   como alternativa, `/api/nowplaying` en el mismo servidor. Identifica la
   entrada por `listen_url`, montajes, relés o `hls_url`, nunca por el nombre.
   Lee título/artista o `song.text`. Un DJ conectado puede aparecer como
   «En directo: …»; no garantiza que sea el presentador del programa.
4. **Probe HLS existente:** `ffprobe` consulta metadatos cada 20 s por defecto.
   Puede abrir otra conexión al audio, a diferencia de las consultas JSON.
   Un resultado nuevo ya no alterna con el título antiguo de mpv; un cambio
   posterior dentro del stream tiene prioridad.

La coincidencia de URL conserva ruta, query y puerto; solo normaliza el host
y los puertos HTTP/HTTPS por defecto. Una API alojada en otro dominio/puerto,
un alias de stream no declarado o una API privada **no se adivinan**. Estas
limitaciones evitan atribuir a una emisora el programa de otra.

## Vigencia y comportamiento

- El JSON se consulta después de empezar a reproducir, nunca durante la carga
  del catálogo o la búsqueda. Primer intento tras tres segundos; después,
  como máximo un trabajo a la vez, 30 s después de cada respuesta correcta.
- Los fallos espacian los intentos: 60, 120, 240, 480 y 960 s. Tras tres fallos
  se vuelve a descubrir el endpoint. La sesión recuerda como máximo 64
  endpoints/plazos, **no los títulos de otras emisoras**.
- Una respuesta confirmada vale como máximo 120 s. Si AzuraCast declara inicio
  y duración, también se respeta su hora de finalización. Se rechazan respuestas
  con datos temporales incoherentes, contenido ya terminado o un `Age` HTTP de
  120 s o más. La API puede tener unos segundos de caché y el audio puede llevar
  retraso: no es sincronización exacta ni una garantía sobre datos del servidor.
- Un programa con el mismo nombre durante una hora no desaparece mientras las
  respuestas públicas sigan confirmándolo. Si fallan, deja de mostrarse al
  agotarse su vigencia; no reaparece el primer título congelado del audio.
- Solo con metadatos del audio, un título sin cambios sigue caducando a los
  cinco minutos (`KEILA_TITLE_MAX_AGE`). No se renueva por releer el mismo campo.
  Un cambio de contenido recibido durante una consulta tiene prioridad sobre
  esa respuesta. Un estado explícito fuera de línea retira el anterior; una
  fuente sin información útil no sustituye los metadatos del audio.
- Pausa o buffering cancelan el trabajo JSON. Cambiar de stream, reconectar,
  parar y cerrar limpian su grupo y el temporal. Los archivos locales no generan
  consultas. Diagnóstico muestra la fuente y la edad de la confirmación pública.

## Recursos, seguridad y privacidad

Se usan Bash, jq, curl, timeout y setsid existentes. Para consultar JSON se
necesita además `getent ahostsv4`; si no está disponible, se conserva la ruta
de metadatos del audio, sin añadir dependencias obligatorias ni bloquear la TUI.

Solo HTTP/HTTPS sin credenciales; resolución IPv4 pública fijada para evitar
DNS rebinding. Las redirecciones se verifican de nuevo. No se accede a redes
privadas, paneles de administración, cookies ni proxies. Cuerpo máximo 512 KiB,
conexión de hasta 2 s, petición de hasta 4 s y trabajo de hasta 20 s más el
segundo de cierre forzado. Texto saneado, publicación atómica y temporal privado
con permisos `700`, retirado al recoger o cancelar el trabajo.

Se consulta al servidor de la emisora: este puede conocer tu IP, hora de acceso
y URL solicitada, como ocurre al reproducir. No se envían favoritos, comentarios
ni historial. El TXT local de sesión sigue siendo privado, pero no cifrado.
Para desactivar **solo el complemento JSON**:

```bash
KEILA_NOW_PLAYING=0 ./keila-radio
```

## Lo que no hace todavía

No integra parrillas RadioDNS/SPI, páginas web específicas de cadenas, scraping
HTML, estadísticas nativas de Shoutcast, ID3 privado no expuesto por mpv ni
servicios de reconocimiento. Una parrilla requeriría distinguir «según
programación» de información confirmada en directo. No todas las radios emiten
metadatos útiles: puede seguir apareciendo «Sin título de emisión disponible».

Referencias oficiales utilizadas:

- [Propiedades y metadatos de mpv](https://mpv.io/manual/stable/#property-list-metadata).
- [Comentarios Vorbis](https://xiph.org/vorbis/doc/v-comment.html).
- [Estadísticas JSON de Icecast](https://www.icecast.org/docs/icecast-latest/server_stats/).
- [Now Playing de AzuraCast](https://www.azuracast.com/docs/developers/now-playing-data/).
