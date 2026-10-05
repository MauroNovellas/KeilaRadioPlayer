# Comprobaciones de Keila

## Un único comando, en local y en GitHub

Desde la raíz del repositorio:

```bash
bash tests/check.sh
```

Ejecuta las pruebas automatizadas con datos locales, sin necesitar una emisora
real, instalar dependencias ni iniciar una escucha interactiva. GitHub Actions
llama al mismo comando; no mantiene otra lista de scripts.

CI ejecuta la batería completa en Ubuntu 22.04 y 24.04, en cada push y pull
request, y permite ejecución manual. Ambas plataformas terminan aunque una
falle. Los registros de cada prueba y el resumen se pueden descargar durante
siete días desde la ejecución de Actions; no se suben audios ni perfiles de
prueba. Un fallo sigue haciendo fallar el trabajo aunque se conserve su salida.
Las acciones están fijadas a commits y solo reciben permiso de lectura.

Cada script dispone de sus propias rutas XDG y directorio temporal. Los tests de
datos usan información ficticia; los fallos de disco se simulan sin llenar el
almacenamiento. No se cambia la configuración personal del reproductor. Las
pruebas del terminal usan un pseudoterminal y las de audio una señal sintética
o dobles de prueba, no los altavoces del usuario.

Las pruebas de grabación programada y calidad con mpv real usan un nombre de
socket corto dentro de su temporal privado. La ruta XDG habitual, al anidarla
en el TMPDIR del runner, superaba el límite del socket Unix en CI; no se evita
el IPC ni se omiten esas comprobaciones.
La verificación de volumen/silencio reúne todos los mensajes y exige una
respuesta correcta para cada request_id. Así no depende de que un evento o
una segunda respuesta disparen el [fallo de select/-e en jq 1.6](https://github.com/jqlang/jq/pull/1697).

La batería cierra la entrada estándar de cada prueba: ninguna debe leer el
teclado de la terminal principal. `timeout` usa un grupo de procesos separado;
heredar el TTY puede detener herramientas como ffmpeg o script y producir un
124 aunque no haya un fallo de audio. Los tests interactivos crean su propio
PTY, sin renunciar a comprobar el eco y su restauración. `check-terminal.sh`
comprueba esta separación lanzando una batería ficticia desde un terminal real.
Véase el [comportamiento de timeout con el terminal](https://www.gnu.org/software/coreutils/manual/html_node/timeout-invocation.html).

El runner necesita Bash 5, las utilidades habituales de GNU/Linux o Termux
(incluido `timeout`), `jq`, Python 3 y ShellCheck. Integración necesita además
`ffmpeg`, `ffprobe`, `script`, `setsid`, `mpv` y `socat`. La falta de una dependencia requerida
es un error, no una prueba aprobada por omisión. El reproductor no necesita
ShellCheck: es una dependencia exclusiva de desarrollo.

## Grupos

```bash
bash tests/check.sh fast
bash tests/check.sh integration
bash tests/check.sh performance
bash tests/check.sh --list
```

- `fast`: sintaxis y ShellCheck, lógica, navegación, layouts, metadatos,
  preferencias, sesiones y regresiones de interfaz. No inicia una radio real.
- `integration`: recuperación, fallos de escritura, cierres forzados,
  concurrencia, arranque del catálogo, procesos, terminal, audio sintético y
  archivo distribuible Linux. El perfilador se ejecuta solo con `--self-test`.
- `performance`: búsqueda con 50.000 emisoras sintéticas y tiempos de render.
  La búsqueda comprueba su presupuesto existente de 1.500 ms; el benchmark de
  render informa medidas, no impone un límite de CPU, memoria o batería.
  Incluye reproducción simulada con ocho canciones anteriores, actualización
  parcial de metadatos, reserva de logo y navegación por Visualización. Compara
  escritura y borrado con dibujo completo y con repintado de consulta. No mide
  la descarga del logo, el decodificador de audio ni el pintado del emulador.
  `search-latency.py` mide tecla → campo dibujado con el bucle de búsqueda real
  bajo PTY en `132×40` y `40×10`. Simula reproducción/espectro a 20 Hz y un logo
  SIXEL en desktop, sin red/audio físico/GPU ni medir un móvil real. Compara un
  filtro deliberadamente lento en primer plano con el worker asíncrono: exige
  respuesta de Retroceso menor de 250 ms mientras trabaja (retraso controlado
  de 350 ms), conserva Unicode/ráfagas y verifica cancelación y cierre. Los
  percentiles normales son informativos; el margen general es 750 ms.
  La consulta de versiones sobre un JSON de 50.000 emisoras también exige
  menos de cinco segundos, identificando antes de normalizar las coincidencias;
  ese trabajo solo se usa en segundo plano al abrir el selector de calidad.
  `logo-cache-performance.sh` mide mantenimiento y evicción con 64 emisoras:
  exige cero consultas de fechas sin desbordamiento y una consulta agrupada al
  superar el límite. Comprueba emisoras con logo/check, protección de la entrante,
  auxiliares, archivos ajenos y rutas con espacios/saltos de línea. Los tiempos
  se informan sin umbrales dependientes de la máquina.
- `packaging`: comprobación optativa del empaquetado Debian existente, fuera
  de `all` y de CI. No implica retomar el desarrollo del paquete.
- `manual`: inventario de herramientas para sesiones reales. `--list` las
  muestra, pero el runner nunca las ejecuta interactivamente.

Sin argumentos, `all` ejecuta `fast`, `integration` y `performance` de forma
secuencial. Medir rendimiento en una máquina sobrecargada puede dar resultados
distintos: repetir aisladamente y revisar el tiempo antes de cambiar el umbral.
Las pruebas individuales siguen siendo ejecutables con `bash tests/nombre.sh`.
`tests/run.sh` conserva sus comprobaciones básicas, pero no es la batería completa.

`ui-size-cache.sh` verifica que redibujar reutiliza el tamaño del terminal,
sin repetir `tput` por pulsación. WINCH invalida aun después de consumir RESIZE;
entrar/reanudar, cambiar TERM, errores, reloj atrasado y la revisión periódica
sin señales también conservan un tamaño correcto. `render-cache.sh` compara
las APIs de texto y de cálculo directo de geometría, volumen y autorepetición
en siete tamaños, con ayuda y reproducción activadas/desactivadas.

`runtime-idle.sh` comprueba el reposo de 200 ms, ticks rápidos cuando hacen falta,
intervalos personalizados, teclado que interrumpe la espera, resize inmediato,
relojes en el proceso principal y suspensión/reanudación de captura oculta.
`player-events.sh` exige un solo parser por ráfaga válida, limita mensajes por
tick, conserva ACKs/fragmentos y no pierde eventos junto a JSON malformado.
El caso de agrupación usa un margen de lectura sobre JSON precargados para no
confundir desplanificación del runner con un fallo del límite; el caso de
fragmentos conserva el timeout real de producción.

`runtime-performance.py` mide CPU acumulada de Keila y sus auxiliares, RSS
muestreada y ticks/s con mantenimiento real. Audio/metadata y terminal son
dobles; no conecta radios, abre altavoces ni usa datos personales. Incluido en
`performance`, con tres segundos por escenario y sin umbrales de CPU/RAM
dependientes de la máquina. Para una comparación más larga:

```bash
python3 tests/runtime-performance.py --duration 10 --output /tmp/keila-runtime.json
```

No equivale a medir mpv, FFT, emulador, servidor de audio ni batería de Android.
La RSS sumada puede duplicar páginas compartidas y omitir picos entre muestras.
Véase el [análisis y límites de la medición](docs/performance-2026-10.md).

`search-query-redraw.sh` compara el campo parcial con el dibujo completo en ocho
tamaños, ASCII y Unicode; comprueba borrado, redimensionado y suspensión sin
consultar `tput` ni recorrer resultados durante la edición. `search-transition.sh`
verifica el filtro diferido y que Enter/cursores usan la consulta vigente.

`search-async.sh` compara todas las columnas con el filtro síncrono, incluidos
Unicode, campos vacíos, comentarios y filtros combinados. Rechaza snapshots
truncados, corruptos o enlazados sin publicar arrays parciales. Comprueba que
solo se publica la última consulta, que Enter reutiliza un resultado terminado
y que navegar, Esc, recargar y salir cancelan el grupo privado y sus hijos.
Un fallo de worker vuelve al filtro síncrono sin relanzarlo en bucle. Los
metacaracteres del catálogo y de la entrada son datos, nunca código ejecutado.

`input-tty.py` envía teclas a un pseudoterminal real mientras la aplicación
está procesando, no esperando teclado: reproduce el Retroceso que el modo
canónico absorbía entre lecturas. Comprueba DEL/Ctrl-H, borrado Unicode,
ráfagas, Enter, Supr y cursores, con drenajes de 2/512 y ambas configuraciones
de VERASE. Verifica que no se desactivan las señales, que suspender/salir
restauran el estado exacto y que reanudar reactiva la entrada de la TUI.
Las pruebas por tuberías no cubren este comportamiento de la terminal.

`dependencies.sh` usa dobles de gestores para comprobar descripciones, paquetes,
rechazo sin TTY, instalación mínima en Termux, reintentos y registros privados.
`dependency-prompt.py` prueba la confirmación real en PTY: S, N, Enter, EOF y
respuesta inválida, incluida reparación de Termux sin dependencias ausentes.
Nunca usa sudo ni modifica paquetes. La salida normal del gestor se oculta;
los fallos conservan un registro 600 y un resumen sin controles de terminal.

`app-exit.sh` comprueba que Enter inicial, Esc, N y Q repetida no cierran;
S o seleccionar Salir y Enter sí confirman. Cubre foco del padre, atajo
personalizado, solicitudes de submenús, ticks y avisos de grabación/reserva.
`app-exit-tty.py` verifica el perro con KEILA durante dos segundos, teclas en
cola, una pantalla de 8×4, resize, Ctrl+C en un editor sin perder texto,
TERM/HUP sin bloqueo, retirada de la TUI, pantalla final vacía y restauración
exacta de termios. Usa un PTY y rutas XDG privadas, sin audio, red ni datos reales.

La escucha de grabaciones se verifica también con mpv real: genera un WAV
sintético, lo reproduce mediante `--ao=null` y comprueba pausa, saltos, posición,
fin de archivo y limpieza del grupo privado. No envía audio a los altavoces.
Requiere que el entorno permita sockets Unix locales: un aislamiento que
bloquee su creación impedirá esta prueba. No se omite ni se declara aprobada
por ese motivo; ejecutarla en un entorno que permita ese IPC local.

## Resultados y fallos

`quality.sh` comprueba validación, privacidad, fusión de otra sesión, recuperación
de memoria ante fallo de escritura y reversión de una conexión fallida. Protege
grabación, programación, preview y procesos obsoletos. `quality-metadata.sh`
verifica agrupación conservadora y listas HLS: CRLF, atributos con comas, codecs,
vídeo excluido, truncados, límites ambiguos y controles. `quality-menu.sh`
comprueba aplicación con un Enter, cancelación, conflictos y trece geometrías en
ASCII/Unicode; quitar país no deja una zona global ni borra temática/consulta.
`quality-access.sh` comprueba el acceso directo, mapas antiguos/personalizados,
entrada local T sin perder la consulta, selección actual estable entre resultados
asíncronos y resize, consumo y marca Actual en móvil. Verifica la ventana compacta
con un lector independiente de cursores/anchos Unicode y que el fondo no se
repinta por cada pulsación; Termux conserva el panel común a pantalla completa.
`quality-check.sh` exige dos muestras crecientes de audio antes de guardar:
IPC/códec/reloj congelado no bastan. Comprueba recuperación única por caída,
timeout o disco; pausa, suspensión y buffering; cambios de volumen/silencio;
cancelación por otra emisora/parada/restauración; bloqueo de grabación provisional
y prioridad de reservas. La recuperación no sobrescribe elecciones concurrentes.
`quality-files.sh` verifica los resultados en dos fases, fallos de catálogo/red,
snapshots malformados, bloqueo de red privada, DNS fijado, cancelación del grupo
y compatibilidad de copias anteriores. No necesita red exterior.
`quality-audio.sh` usa mpv real con MP3/AAC y un master HLS local de dos bitrates:
elección/reinicio/original, volumen/silencio/pausa por IPC, protección de grabación,
formato y audio guardado, sin modificar identidad, favoritas, comentarios ni
Recientes. Fuente sintética, `--ao=null`, sin altavoces ni radio remota.
También comprueba confirmación diferida al reanudar, metadata_interval=60 sin
alterar la preferencia, IPC abierto sin audio y caída de una candidata pausada:
recuperación real conservando audio/preferencia y sin grupo mpv abandonado.

`sleep-timer.sh` comprueba plazos, edición cancelable, prioridad sobre alarmas
vencidas, conservación de alarmas futuras y el orden de cierre de audio/grabación.
`record-schedule.sh` usa reloj/audio simulados para comprobar inicio único,
espera de datos, límites, suspensión, conflictos, propiedad del archivo y cierres
pendientes/fallidos. `record-schedule-menu.sh` comprueba selección sin reproducir,
HHMM automático, borradores, confirmación caducada, cancelación y terminal mínima.
Los formularios y la revisión se incluyen en las pruebas de layout responsive.
`record-schedule-audio.sh` conecta el tick real de la aplicación con mpv y una
fuente MP3 sintética local: comprueba silencio/volumen por IPC, escritura,
marcador, cierre verificado y reproducción del resultado. Prueba continuar y
parar al finalizar, sin procesos huérfanos. Mide el nivel medio del audio
guardado y lo compara con el original (tolerancia de 1 dB), también silenciado
y con volumen cero. Los tests de estados/menús cubren confirmación, cancelación,
alarmas, cierres pendientes y protección de otras grabaciones. Solo adelanta el final previsto
para no esperar un minuto; no utiliza emisoras remotas ni altavoces.
`m3u-files.sh` verifica BOM/CRLF, duplicados, límites, entradas no admitidas,
ida y vuelta, privacidad, fusión bloqueada, escritura fallida y colisiones.
`m3u-menu.sh` prueba la preparación asíncrona, ticks atendidos, confirmación,
consulta de detalles y cancelación. Las pruebas de layout incluyen los menús
y formularios nuevos en 13 tamaños, con ASCII y Unicode.

`now-playing.sh` comprueba metadatos ICY/título/artista/programa, saneado,
caducidad, confirmación de programas largos, respuestas tardías, retirada de
contenido, snapshots inválidos, backoff y memoria acotada. `now-playing-files.sh`
usa JSON y descargas simuladas para verificar Icecast/AzuraCast, coincidencia
exacta del stream, contenido ambiguo/offline/terminado, endpoint estático, DNS
fijado, límites de tamaño/tiempo, respuestas cacheadas y redirecciones privadas.
Un worker con hijo real comprueba la cancelación en pausa, cambio y cierre sin
grupos huérfanos. `player-title-probe.sh` verifica además que mpv congelado no
deshace un probe nuevo y que sus metadatos posteriores sí lo sustituyen. La
batería desactiva el complemento JSON salvo en sus pruebas simuladas: no añade
tráfico de emisoras a los tests offline. La cobertura real depende de lo que
publique cada servidor; ver [fuentes y límites](docs/now-playing.md).

`ui-frame-scroll.sh` interpreta movimientos ANSI y anchuras Unicode del frame
completo y sus actualizaciones parciales. Verifica foot/Kitty en siete tamaños,
ASCII/Unicode, ayuda y reserva de logo, con navegación y cambios de contenido,
caracteres de dos celdas e historial internacional. Detecta autowrap y scroll,
en lugar de limitarse al número de caracteres o saltos de línea. La caché del
recorte queda acotada; el test de metadatos incluye un parser fallido que no
imprime errores sobre el frame y conserva el último estado válido.

`station-logo-ui.sh` comprueba el espacio fijo del logo, el fallback de
iniciales, bloques de color, cambio de emisora, redimensionado, pantallas
pequeñas, Termux y el protocolo Kitty sin consultas interactivas.
`station-logo-redraw.sh` verifica que cursores, estado, título y búsqueda no
borran ni retransmiten una imagen visible. Un intérprete independiente del
cursor comprueba que el frame salta las seis filas de doce columnas sin
escribir sobre ellas, en ASCII/Unicode y SIXEL/Kitty. También verifica que
menús/detalles, suspensión, cambios de imagen/geometría y vistas sin logo
invalidan la colocación y que esta se recupera al volver al reproductor.
`station-logo-files.sh` valida PNG/JPEG, WebP, primer cuadro GIF e ICO con
PNG/BMP, el formato RGB interno,
la caché privada con límite/caducidad, rechazos de SVG y ficheros grandes, y
la protección contra DNS/redirecciones hacia redes privadas.
`station-logo-lifecycle.sh` comprueba el valor por defecto, guardado, lectura
inmediata de caché sin worker, cancelación al cambiar de emisora, limpieza del
grupo de procesos y
rollback si falla el guardado de la preferencia.
`station-logo-cache.sh` comprueba reinicio/offline, copia antigua visible mientras
se actualiza, interrupciones, imagen idéntica sin nueva generación, plazos de
reintento y ausencia de candidatos. Verifica SIXEL persistente ligado exactamente
al RGB, tamaño distinto sin red/ffmpeg, conservación de la edad, permisos,
validación, enlaces y evicción conjunta sin tocar otros archivos. Usa tareas y
descargas simuladas; el lector independiente verifica todos los píxeles SIXEL.
`station-logo-candidates.sh` verifica alternativas sin duplicados, nombres
normalizados sin confundir emisoras, ambigüedad de país/web, query intacta y
enlaces estáticos con rutas relativas y redirecciones.
`station-logo-sixel.sh` decodifica de forma independiente el SIXEL generado en
42/60/96 píxeles: comprueba paleta, geometría, todos los píxeles y rechazos de
payloads corruptos. Reutiliza la caché RGB anterior sin descargar/convertir,
verifica consulta asíncrona, fallback y borrado limitado al espacio reservado.
`input-tty.py` comprueba además la elección de Kitty/foot bajo un TTY real y
que la respuesta de tamaño de celda no consume texto, Retroceso ni cursores.
La apariencia final de las imágenes requiere una comprobación visual en el
emulador real; los tests no sustituyen esa revisión.

Cada prueba tiene un límite de 180 segundos. Si falla o excede ese límite, el
runner informa del error, continúa con las restantes y termina con código no
cero. No confunde el tiempo agotado con una prueba aprobada.

El código 124 significa que se agotó el tiempo, no que una aserción falló. La
prueba de escucha imprime sus fases (generación, mpv, controles y cierre) para
localizar un bloqueo. La generación de audio y el probe de terminal tienen
además límites propios cortos; aumentar el límite global no arregla una espera
accidental de teclado.

Al terminar muestra un resumen y la carpeta temporal de registros. Cada
`nombre/output.log` contiene la salida completa de ese script. Los registros y
datos ficticios se conservan para poder investigar el fallo; no contienen una
copia de los datos personales. Se pueden retirar después de la revisión.

En un dispositivo especialmente lento se puede ampliar el límite por script:

```bash
KEILA_TEST_TIMEOUT=300 bash tests/check.sh
```

Esto no cambia los presupuestos internos de rendimiento. La batería no reclama
durabilidad ante pérdida eléctrica ni sustituye pruebas de Android suspendido,
cierres desde el sistema o sesiones largas con emisoras reales. La lista de
comprobaciones de datos en Termux está en [DATA-SAFETY.md](DATA-SAFETY.md).

## Incorporar una regresión

1. Crear el script en `tests/`, con datos ficticios y limpieza de sus procesos.
2. Clasificarlo en `tests/suites.txt` con grupo, nombre y argumento opcional.
3. Ejecutar su grupo y, antes de publicar, `bash tests/check.sh`.

El runner detecta ejecutables `.sh` o `.py` sin clasificar, entradas duplicadas,
rutas inválidas y archivos desaparecidos. No se debe excluir una prueba para
ocultar un fallo. Los helpers compartidos deben vivir en un subdirectorio,
no camuflarse como tests aprobados.

Sintaxis y ShellCheck recorren todos los módulos, scripts y tests Bash de primer
nivel. ShellCheck analiza cada archivo por separado para evitar expandir el
launcher entero repetidamente. En tests se ignora el aviso de funciones sin
llamadas visibles (`SC2317`): los dobles se invocan desde los módulos probados.
Esa excepción no se aplica a los archivos de producción.
