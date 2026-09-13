# Keila Radio Player 2.1.1

Radio por Internet en tu terminal: busca emisoras, organiza tus favoritas, graba programas y escucha sin salir del teclado. Escrito en Bash, con `mpv` como motor de audio.

Linux de escritorio es la plataforma principal; también se ha probado en Termux/Android, incluidas pantallas pequeñas. Esta guía describe la rama de desarrollo `v2.1`, con versión base **2.1.1**. Las novedades aún no publicadas se distinguen en el [historial de cambios](CHANGELOG.md).

[Empezar](#empezar) · [Funciones](#funciones) · [Atajos](#atajos) · [Referencia completa](#referencia-completa) · [Pruebas y desarrollo](#pruebas-y-desarrollo)

## Empezar

Para descargar esta rama necesitas Git:

```bash
git clone --branch v2.1 https://github.com/MauroNovellas/KeilaRadioPlayer.git
cd KeilaRadioPlayer
./keila-radio
```

Si ya tienes el proyecto, basta con ejecutar `./keila-radio` desde su carpeta.

**Primer uso:** pulsa `B`, escribe una búsqueda y elige una emisora con `↑`/`↓` y `Enter`. Ajusta el volumen con `←`/`→`. `O` abre Opciones; `Q` sale.

> Al arrancar, Keila puede instalar dependencias automáticamente, sin una confirmación propia; puede solicitar permisos de administrador. En Termux también puede reparar y actualizar paquetes. Para prepararlo tú mismo, consulta el bloque siguiente.

<details>
<summary>Instalación, dependencias y otras formas de arrancar</summary>

Requiere Bash 5 y las utilidades habituales de Linux/Termux, incluidos `coreutils`, `setsid`, `mpv`, `socat`, `curl`, `jq`, `fzf` y `tput`. La búsqueda integrada es la predeterminada; `fzf` se mantiene como alternativa externa.

Preparación manual habitual:

```bash
# Debian / Ubuntu
sudo apt install git bash coreutils util-linux mpv socat curl jq fzf ncurses-bin

# Termux / Android
pkg install git bash coreutils util-linux mpv socat curl jq fzf ncurses-utils
```

El instalador automático reconoce Debian/Ubuntu (`apt-get`), Termux (`pkg`/`apt-get`), Arch (`pacman`) y Fedora (`dnf`). Si Termux tiene paquetes multimedia inconsistentes, puede ejecutar una reparación y actualización del entorno; si falla el repositorio, el aviso propone `termux-change-repo`.

El espectrograma es opcional: en escritorio utiliza `ffmpeg`, `parec` y `pactl` con un monitor PulseAudio/PipeWire. En Debian/Ubuntu:

```bash
sudo apt install ffmpeg pulseaudio-utils
```

Sin captura compatible se muestra «No disponible», pero la radio sigue funcionando.

También puedes abrir directamente una URL, que tiene prioridad sobre la última emisora guardada:

```bash
./keila-radio "https://servidor.example/stream" "Nombre de la emisora"
./keila-radio --version
```

La URL es un ejemplo: sustitúyela por la dirección real del audio. `--version` consulta `lib/version.sh` sin abrir la TUI ni instalar dependencias.

</details>

## Funciones

Puedes acceder a todo lo habitual desde **`O` Opciones**, sin memorizar atajos.

| Quiero… | Dónde |
| --- | --- |
| Reproducir, pausar, silenciar o cambiar volumen | Reproducción |
| Buscar en Radio Browser y actualizar su copia local | Emisoras |
| Combinar país, región y temática con una búsqueda libre | Emisoras → Filtros de búsqueda |
| Añadir una emisora por su URL | Emisoras → Añadir emisora manual |
| Gestionar Favoritas, Recientes, orden y comentarios | Emisoras |
| Ajustar ecualizador, espectrograma, colores o Unicode | Visualización |
| Programar una alarma para escuchar la última emisora | Temporizador |
| Grabar, comprobar, escuchar, renombrar y recuperar audios | Grabaciones |
| Consultar las canciones anteriores y el TXT de esta sesión | Sesión |
| Guardar preferencias y personalizar teclas | Configuración |
| Crear copias de seguridad o restaurar datos de otro equipo | Datos y almacenamiento |
| Revisar el estado, las rutas y los controles disponibles | Diagnóstico / Ayuda |

Además, Keila recuerda volumen y última emisora, adapta la pantalla al tamaño de la terminal y gestiona reconexiones limitadas. Los detalles y límites están en la referencia desplegable.

## Atajos

Son los valores predeterminados de la **pantalla principal**. Puedes personalizar las acciones desde `,` Configuración; los menús y editores conservan sus teclas locales.

| Teclas | Acción |
| --- | --- |
| `↑`/`↓` o `W`/`S` · `Enter` | Seleccionar · reproducir |
| `←`/`→` o `a`/`d` | Bajar / subir volumen |
| `Home`/`End` · `PgUp`/`PgDn` | Extremos de la lista · avanzar por páginas |
| `F` / `R` · `1–9` y `0` | Favoritas / Recientes · sus diez primeras emisoras; la décima es `0` |
| `B` · `U` | Buscar · actualizar **el catálogo**, no el programa |
| `X` · `C` · `J`/`K` | Favorita · comentario · bajar/subir una favorita |
| `P` · `M` | Pausa · silencio |
| `G` · `;` | Iniciar/detener grabación · biblioteca de grabaciones |
| `Z` · `V` · `L` | Ecualizador · espectrograma · alarma |
| `O` · `,` · `H` o `?` · `D` | Opciones · configuración · ayuda · diagnóstico |
| `Q` | Salir y cerrar la sesión |

**Ojo con el contexto:** `d` sube volumen, pero `D` mayúscula abre Diagnóstico. En la búsqueda, las minúsculas y los números son texto. `X` actúa sobre la entrada seleccionada en Recientes o en la búsqueda; desde Favoritas, sobre la emisora que está sonando. En Opciones siempre actúa sobre la selección.

## Referencia completa

Abre solo el apartado que necesites. Todas las funciones siguen documentadas aquí.

<details>
<summary>Opciones, ayuda y navegación de los menús</summary>

`↑`/`↓` seleccionan; `Enter` abre o ejecuta; `→` abre categorías sin cambiar ajustes ni confirmar borrados; `←`/`Esc` vuelve un nivel. `PgUp`/`PgDn` y `Home`/`End` recorren listas largas. Las letras entre corchetes son accesos locales.

Los menús muestran ruta, estado y explicación; recuerdan la selección al volver. Las acciones no disponibles se atenúan e indican qué falta. `?` abre el detalle completo, desplazable y de solo lectura. En listas también se usa `Enter` para leer detalles; en Configuración, `Enter` cambia el ajuste.

Los submenús, editores, diagnóstico, historial y copias comparten presentación adaptable. En pantallas estrechas el detalle tiene altura fija; nombres y rutas completos siguen accesibles. Redimensionar conserva texto y confirmaciones. En editores de texto, `?` se escribe como carácter normal.

Buscar, ir a Favoritas/Recientes o iniciar una emisora desde Opciones devuelve el control al reproductor. La radio, alarmas, reconexión y tareas pendientes siguen atendidas con los menús abiertos. Los avisos temporales desaparecen solos; el estado real permanece visible.

</details>

<details>
<summary>Emisoras: búsqueda, filtros, catálogo local y alta manual</summary>

**Buscar — `B`.** Escribe nombre, región, temática, país, formato o un comentario personal. `↑`/`↓` navegan y `Enter` reproduce; `Home`/`End` y `PgUp`/`PgDn` permiten saltar. Retroceso borra un carácter y `Supr` vacía la consulta. `Esc` sale conservándola; `B` permite seguir editándola.

Dentro del buscador, `P` mayúscula activa/desactiva el país preferido; `X` gestiona Favoritas, `C` edita el comentario, `M` alterna silencio y `F`/`R` vuelve a esas listas. Las minúsculas y los números no activan estos comandos.

En los tamaños `tiny` y `minimal` se muestran inicialmente solo nombres. `→` despliega los datos disponibles en todas las filas visibles; `←` los oculta. En ese contexto no cambian el volumen.

**Filtrar — `O → E → L`.** Combina país, región/ámbito y temática sin ocupar la consulta: elige España y después busca `rock`, o elige la etiqueta `rock` y busca un nombre. Los selectores admiten escritura, flechas y `Enter`; `Esc` conserva el valor anterior y `Supr` limpia su texto.

- Los filtros duran la sesión y no ocultan Favoritas ni Recientes.
- Cambiar el país limpia la región anterior, pero conserva temática y consulta.
- «Sin este filtro» quita uno; `X` en el menú de filtros los quita todos. Borrar la consulta no los desactiva.
- País usa el código ISO; región y temática usan los datos declarados, sin inventar ubicaciones ni traducir etiquetas. `rock` no equivale a `hard rock`. Una emisora sin el dato requerido queda fuera.
- Los comentarios también respetan los filtros. Cada selector muestra hasta 300 coincidencias: afina el texto para encontrar otras.
- El resumen completo está en Opciones; el indicador existente de búsqueda deja de decir «global» cuando hay filtros, sin añadir filas al reproductor.

**Catálogo.** Usa [Radio Browser](https://api.radio-browser.info/) con copia local actualizada en segundo plano al caducar —24 horas por defecto—. Si falla la red conserva la copia anterior. Con un índice fresco, los primeros resultados aparecen al arrancar sin tomar el foco.

El JSON se transforma en un TSV compacto: nombre, ámbito visible, país, formato, URL, código de país, clave de búsqueda, región y etiquetas separadas. Tener región ya no elimina la temática de la búsqueda. Un índice antiguo permanece disponible mientras se regenera desde el JSON local; si falta ese JSON, usa `U` para actualizar. Los filtros trabajan localmente, también en el selector alternativo:

```bash
KEILA_FZF_SEARCH=1 ./keila-radio
```

**Alta manual — `O → E → N`.** `N` edita el nombre y `D` la URL del audio o lista compatible, no la web de la radio. Admite HTTP/HTTPS sin credenciales en el servidor; no rutas locales ni comandos. `Enter` acepta el campo, `Supr` lo vacía y `Esc` cancela su edición.

`G` guarda en Favoritas sin conexión ni reproducción automática. Una URL existente no se duplica ni cambia de nombre. La emisora sobrevive a las actualizaciones y entra en las copias de Favoritas; no se publica en Radio Browser ni se añade al buscador del catálogo.

`P` permite probarla: cambia lo que suena y puede aparecer en Recientes y en el registro de sesión, pero no la guarda en Favoritas. Está bloqueado mientras se graba. Salir con `Esc` no guarda el formulario ni deshace una prueba ya iniciada.

</details>

<details>
<summary>Favoritas, Recientes y comentarios personales</summary>

Favoritas conserva tu orden; `J`/`K` baja/sube una entrada. Recientes reúne las últimas **20 emisoras distintas** que llegaron a sonar, de más reciente a más antigua, incluidas las favoritas, marcadas con `★`. Una conexión sin audio no entra en el historial.

Las listas tienen selección y desplazamiento independientes, navegación circular y accesos `1–9`/`0` para sus primeras diez entradas. Las restantes siguen accesibles con cursores. Añadir a Favoritas es inmediato; quitar exige confirmar con una segunda pulsación. Moverse cancela la confirmación.

`C` comenta la emisora seleccionada en Favoritas, Recientes o búsqueda. Admite hasta 80 caracteres: `Enter` guarda, `Esc` cancela y `Supr` o `Ctrl+U` vacía; guardar vacío elimina el comentario. Si falla el guardado, el texto permanece para reintentar. Los comentarios son buscables y se conservan aunque el tamaño de pantalla los oculte.

La semilla `defaults/favorites` se copia solo cuando aún no existe tu archivo personal. Las actualizaciones no vuelven a imponer esa lista inicial.

</details>

<details>
<summary>Títulos de canciones, historial visible y registro de sesión</summary>

«Ahora suena» muestra el título recibido y datos como codec, bitrate, frecuencia de muestreo y canales, si la emisora los proporciona. El bitrate procede de `audio-bitrate` de mpv; los títulos se leen de metadatos vivos, campos ICY y `media-title` mediante [JSON IPC](https://mpv.io/manual/stable/#json-ipc).

Algunas emisoras HLS dejan fijo el primer título. En ese caso, una consulta auxiliar con `ffprobe` puede abrir otra conexión cada 20 segundos para renovar metadatos sin reiniciar la escucha. Si no aparece un cambio, el título caduca a los cinco minutos: no se presenta indefinidamente como actual. Estos datos dependen de lo que publique la emisora.

Se reservan **ocho líneas fijas** para canciones anteriores de la misma sintonía, sin repetir la actual; la novena muestra la ruta del TXT de sesión. No desplazan los paneles al llenarse. Se ocultan si falta espacio. `KEILA_TRACK_HISTORY_DISPLAY_LIMIT` admite de 1 a 20 líneas; la ruta queda a continuación.

Cada ejecución interactiva crea un TXT privado con fecha/hora, emisora y canción o evento, separados por tabuladores. `O → S` abre su visor; también `D → S`. Tiene navegación por páginas, detalle completo y actualización en vivo; solo sigue automáticamente las nuevas entradas si estabas al final.

El TXT se guarda en `~/.local/state/keila-radio/sessions/keila-session-*.txt`. Directorios con permisos `700` y archivos `600`; es texto legible, no cifrado. Recientes guarda nombres y URLs por separado, sin títulos ni marcas de tiempo. Rutas y opciones de entorno se recogen más abajo.

</details>

<details>
<summary>Pantalla, ecualizador y espectrograma</summary>

La interfaz se adapta al tamaño y a sus cambios. Desde **112 columnas × 20 filas**, «Ahora suena» queda a la izquierda; Favoritas y Recientes comparten la zona superior derecha y la búsqueda queda debajo. En estrecho, las listas se apilan.

Los otros umbrales son `80×20` (wide), `62×16` (standard), `50×13` (compact) y `42×11` (minimal). Por debajo se usa tiny: la pantalla principal avisa de falta de espacio, mientras los paneles y la búsqueda mantienen su adaptación.

Con menos de 62 columnas **o** 16 filas se ocultan el ecualizador principal y los comentarios de Favoritas/Recientes. El audio sigue ecualizado; comentarios y editores continúan disponibles y reaparecen al ampliar.

Unicode se activa según la locale y admite alternativa ASCII; los colores pueden desactivarse. Los encabezados de comentarios conservan el color de su sección y los comentarios tienen tono propio al seleccionar. Se reserva una columna para evitar saltos de línea y no se añade un salto tras el borde inferior. El eco del terminal permanece desactivado durante la TUI y se restaura al suspender o salir; las repeticiones de teclas se agrupan para evitar una cola de movimientos.

**Ecualizador — `Z` o Visualización.** Cinco bandas: 60 Hz, 250 Hz, 1 kHz, 4 kHz y 12 kHz, entre −12 y +12 dB. `←`/`→` elige banda; `↑`/`↓` ajusta; `C` la centra y `R` deja todas planas. Presets: `1` Plano, `2` Rock, `3` Pop, `4` Jazz y `5` Voz. `?` explica los controles.

Los cambios se aplican y guardan al editar; `Z`, `Enter` o `Esc` vuelven sin deshacerlos. Si falla la aplicación se mantiene el ajuste anterior. En escritorio las barras ocupan el ancho del panel y señalan la banda editada.

**Espectrograma — `V`.** Dieciséis bandas, ocho filas, picos retenidos y suavizado de caídas; amplitud y frecuencias logarítmicas. Es solo visual: no modifica audio ni ecualización. Captura el monitor de la salida PulseAudio/PipeWire sin abrir otra conexión a la emisora; se detiene al ocultarlo, pausar o parar, y vuelve al reanudar.

El análisis trabaja a 20 Hz y la presentación se limita a intervalos de 66 ms, con repintado parcial independiente. `parec` solicita entregas de 20 ms y latencia de 40 ms; el servidor puede ajustarlas. Una columna de guarda evita perder la última banda de `showfreqs`. Las barras permanecen antes de recibir señal; si falta captura compatible se indica «No disponible».

</details>

<details>
<summary>Alarma, silencio y preferencias guardadas</summary>

**Alarma — `L` o `O → T`.** Escribe `HHMM`: los dos puntos se añaden solos. También admite `HH:MM`. `Enter` programa; vacío cancela; `Esc` conserva lo anterior. Si la hora pasó, se programa para mañana, en hora local, con fecha/hora visibles.

Suena **una sola vez** con la última emisora escuchada, incluso si la cambiaste después de programarla. Desactiva el silencio y usa el volumen configurado; comprueba volumen y conexión antes. Si hay una grabación, aplica el mismo cierre seguro que al cambiar de emisora.

Keila debe seguir abierto y el equipo despierto. No es un despertador del sistema, no despierta Android y no se guarda al cerrar.

**Silencio — `M`.** No cambia volumen ni interrumpe grabaciones. El indicador es `MUTE`. Una reproducción elegida manualmente vuelve a tener sonido; las reconexiones automáticas conservan el silencio desde el arranque de mpv.

**Preferencias — `,` o Configuración.** Guarda inicio automático, colores, Unicode, espectrograma y teclas. Volumen, ecualizador y última emisora también se recuperan; solo una emisora que llegó a dar audio reemplaza la última escucha válida. Puedes desactivar el arranque automático; una URL pasada al ejecutar Keila tiene prioridad.

Para reasignar una acción: selecciónala, `Enter` y la nueva letra. Si estaba ocupada, se intercambian ambas. Flechas, números y `A/D/W/S/J/K` quedan reservados; los encabezados muestran los atajos actuales. Los menús, editores y búsqueda mantienen sus teclas locales.

Restaurar valores predeterminados requiere confirmar y afecta a preferencias/atajos, no borra emisoras, comentarios, volumen ni grabaciones, ni modifica la alarma. Un fallo de guardado conserva el valor anterior. Las variables visuales de entorno tienen prioridad.

</details>

<details>
<summary>Grabaciones: grabar, comprobar, escuchar, renombrar y recuperar</summary>

**Grabar — `G`.** Usa el stream del mismo mpv, sin otra conexión. Muestra «Preparando grabación» hasta recibir datos, después «Grabando» con contador y «Cierre pendiente» hasta confirmar que el archivo se liberó. Si la orden inicial no se acepta, limpia la reserva vacía.

El nombre combina emisora y fecha/hora; se reserva sin sobrescribir archivos existentes. Conserva un formato compatible: HLS/m3u8 → `.ts`, MP3 → `.mp3`, AAC → `.aac`, Ogg/Opus → `.ogg` y FLAC → `.flac`. Si la URL no revela el formato, consulta demuxer/codec. Por defecto guarda en `grabaciones/` junto al programa, ignorada por Git. Al cerrar comprueba existencia, datos y tamaño; si mpv cae, intenta conservar y validar lo que haya quedado.

**Biblioteca — `;` o `O → G → R`.** Detecta archivos en segundo plano al arrancar; lista nombre, fecha de modificación, tamaño y estado, con los más recientes primero. No decodifica todos los audios, recorre solo la carpeta configurada y no sigue enlaces. Conserva la selección al actualizar y redimensionar.

| Tecla | En la biblioteca |
| --- | --- |
| Flechas, `Home`/`End`, `PgUp`/`PgDn` | Navegar |
| `U` · `Enter` o `?` | Actualizar · leer detalle y ruta completa |
| `C` · `E` · `N` | Comprobar · escuchar · renombrar |
| `X` y después `Enter` | Mover audio y marcador a papelera; otra tecla cancela |
| `T` · `Esc` | Abrir papelera · volver |

Estados: **Finalizada**, **Pendiente**, **En curso**, **Vacía**, **Dudosa** y **No disponible**. Finalizada significa que no hay cierre pendiente, no una verificación de todo el audio. `C` verifica un fragmento en segundo plano y solo retira el marcador si pasa y el archivo no cambió. Si es dudosa conserva ambos y mantiene el aviso durante la sesión.

Los marcadores `.pending` nuevos identifican al mpv que graba. Un archivo activo no se puede escuchar, comprobar ni mover. Con marcadores antiguos vacíos se actúa conservadoramente si hay otro mpv abierto.

**Escuchar — `E`.** Muestra posición/duración (`03:42 / 28:15`), horas cuando corresponda y `--:--` si falta el dato. La lectura real se consulta en segundo plano como máximo una vez por segundo, sigue los saltos y se detiene en pausa al disponer de ambos tiempos.

- `P` o espacio: pausa/reanuda; `A`/`←` y `D`/`→`: saltos de 10 segundos; `I`: inicio.
- `R`/`Esc` vuelve; también puedes elegir controles con flechas y `Enter`.
- Los saltos dependen del formato. La preparación se puede cancelar sin esperar.
- Usa un mpv separado, hereda volumen/silencio y pausa la radio. La retoma solo si sigue siendo la misma y no estaba ya pausada; una alarma o cambio de radio interrumpe la escucha local.
- No altera el audio, historiales ni última emisora guardada. No se inicia mientras se graba.

**Renombrar — `N`.** Edita solo el nombre, sin extensión ni ruta. Retroceso borra, `Supr` vacía; `Enter` revisa origen/destino y otro `Enter` confirma. `?` muestra las rutas completas. `Esc` en la confirmación vuelve al editor; en el editor cancela. Conserva audio, fecha y marcador; rechaza nombres ocultos, vacíos o demasiado largos y archivos ocupados.

**Recuperar — `T` o `O → G → T`.** La papelera `.trash/recording.*` incluye archivos de versiones anteriores. `E` escucha, `Enter`/`?` muestra detalles y `R` prepara la recuperación. Si el nombre está ocupado propone un sufijo; confirma ese destino exacto. Si alguien lo ocupa después, se rechaza la operación.

No hay borrado definitivo ni vaciado automático. Solo se retiran los contenedores vacíos tras recuperar; los archivos ajenos permanecen. Una interrupción puede dejar marcadores para revisar, nunca se limpian a ciegas. [Garantías y límites](DATA-SAFETY.md).

</details>

<details>
<summary>Datos personales, copias de seguridad y restauración</summary>

**`O → A` Datos y almacenamiento:** `C` crea una copia privada y `R` abre las disponibles, con nombre, fecha y tamaño. En la lista, `C` crea, `U` actualiza, `Enter`/`?` muestra el detalle y `R` verifica para restaurar. Después, solo `Enter` confirma; `Esc` cancela. Navegar o redimensionar no confirma.

Las copias incluyen configuración, Favoritas, comentarios, preferencias, volumen/última emisora guardados, Recientes y ecualizador. **No incluyen audios grabados, catálogo, registros de canciones ni alarmas.** No se borran automáticamente ni se sobrescriben.

Para importar de otro dispositivo, coloca el `.tar.gz` en `~/.local/state/keila-radio/backups/` y actualiza la lista. También reconoce respaldos previos de configuración y copias antiguas junto al programa, sin recorrer el equipo ni seguir enlaces.

Crear y verificar copias no interrumpe la radio. Restaurar exige detener grabaciones y escuchas de la biblioteca, valida el archivo y crea un respaldo previo; si falla, no comienza. Una vez publicando, `Esc` espera a que termine. Un cierre forzado puede dejar una restauración parcial, con el respaldo previo completo conservado.

La restauración desde la TUI recarga favoritas, comentarios, recientes, preferencias y ecualizador, **sin cambiar emisora actual, volumen, silencio ni alarma**. El volumen/última emisora guardados y la carpeta importada de grabaciones se usan al reiniciar.

También existe la vía de terminal:

```bash
./keila-radio --backup
./keila-radio --backup "/ruta/copia.tar.gz"
./keila-radio --restore "/ruta/copia.tar.gz"
```

Sin destino, `--backup` crea el archivo en el directorio actual; desde Opciones se usa la carpeta de copias. `--restore` es una orden explícita y **no pide otra confirmación**. La copia previa queda en `~/.config/keila-radio/pre-restore-*.tar.gz`.

Rutas predeterminadas, respetando `XDG_CONFIG_HOME`, `XDG_STATE_HOME` y `XDG_CACHE_HOME`:

| Directorio | Contenido |
| --- | --- |
| `~/.config/keila-radio/` | `config`, `favorites`, `labels`, `preferences`, `equalizer` y respaldos previos |
| `~/.local/state/keila-radio/` | `state`, `history`, `sessions/keila-session-*.txt` y `backups/` |
| `~/.cache/keila-radio/` | `radio.json` y `radio.tsv` |
| `grabaciones/` junto a Keila, o carpeta configurada | Audios, marcadores y `.trash/` |

La configuración es texto interpretado como datos, nunca ejecutado con `source`. Las escrituras usan temporales y bloqueos portables con `mkdir`; se conserva el último estado válido ante fallos. Cada instancia tiene su socket privado, y las operaciones por índice conservan la identidad por URL frente a cambios de otra instancia.

Puedes vaciar comentarios, Recientes o registros retirando sus archivos correspondientes **con Keila cerrada**, después de hacer una copia si quieres conservarlos. Consulta [Protección de datos](DATA-SAFETY.md) para recuperación, concurrencia y límites ante interrupciones.

</details>

<details>
<summary>Configuración avanzada y variables de entorno</summary>

El archivo `~/.config/keila-radio/config` se crea al iniciar. Valores inválidos se ignoran a favor del predeterminado:

| Clave | Predeterminado | Uso |
| --- | --- | --- |
| `volume_step` | `5` | Salto de volumen, de 1 a 50 |
| `metadata_interval` | `1` | Intervalo de metadatos en segundos, de 1 a 60 |
| `catalog_max_age` | `86400` | Caducidad del catálogo en segundos; `0` fuerza actualización |
| `catalog_limit` | `50000` | Emisoras guardadas, de 100 a 100000 |
| `catalog_country_filter` | `ES` | País preferido, código ISO de dos letras |
| `search_match_limit` | `300` | Resultados por búsqueda, de 100 a 20000; afina el texto para otros |
| `recordings_dir` | Vacío | Usa `grabaciones/` junto a Keila; admite ruta absoluta, `~/…` o relativa a `$HOME` |

Ejemplo de una línea: `catalog_country_filter=FR`. Para preferencias visuales y teclas, usa el selector de Configuración.

Estas variables se aplican al lanzar el programa; las visuales prevalecen sobre las preferencias:

```bash
KEILA_ASCII_UI=1 ./keila-radio       # Forzar ASCII
KEILA_NO_COLOR=1 ./keila-radio       # Desactivar colores
NO_COLOR=1 ./keila-radio             # Alternativa sin color
KEILA_NO_UPDATE_CHECK=1 ./keila-radio # No consultar nuevas versiones al arrancar
KEILA_FZF_SEARCH=1 ./keila-radio      # Selector externo de emisoras
```

Otros ajustes, en segundos salvo donde se indica:

| Variable | Valor inicial | Uso |
| --- | --- | --- |
| `KEILA_TITLE_PROBE_INTERVAL` | `20` | Consulta auxiliar de títulos |
| `KEILA_TITLE_MAX_AGE` | `300` | Caducidad del título sin cambios |
| `KEILA_TRACK_HISTORY_DISPLAY_LIMIT` | `8` | Filas reservadas para canciones anteriores, de 1 a 20 |
| `KEILA_RECONNECT_STALL_TIMEOUT` | `15` | Plazo sin progreso del audio |
| `KEILA_RECONNECT_START_TIMEOUT` | `12` | Plazo de arranque sin audio |
| `KEILA_RECONNECT_MAX_ATTEMPTS` | `3` | Intentos automáticos por ciclo |
| `KEILA_RECONNECT_BASE_DELAY` | `2` | Espera inicial entre reintentos |
| `KEILA_RECONNECT_RESUME_GAP` | `30` | Salto de tiempo que activa la comprobación tras suspensión |

</details>

<details>
<summary>Reconexión, diagnóstico y límites conocidos</summary>

Keila detecta fallos de arranque, cierres de mpv y streams sin progreso. Aplica hasta tres reintentos por ciclo con espera progresiva desde 2 segundos, limitada a 30; no bloquea el teclado. Una URL rechazada como inválida no se reintenta. Al agotarse los intentos, puedes volver a elegir la emisora con `Enter`.

Pausar cancela intentos pendientes; reanudar concede un plazo nuevo. Las reconexiones conservan volumen y silencio, y quedan bloqueadas durante una grabación para protegerla. Tras una suspensión larga comprueba IPC y avance del audio; si se atascó reutiliza la reconexión, sin duplicar el reproductor. Durante una grabación solo avisa.

`D` abre Diagnóstico en vivo: versión, rama/commit si hay Git, mpv, emisora/título, volumen, catálogo, resultados, grabaciones y rutas. Distingue fallos de reproductor, IPC y stream; un error al arrancar mpv no demuestra por sí solo que falte Internet.

Comprobaciones sin abrir la TUI:

```bash
./keila-radio --check           # Datos, dependencias, ecualizador, captura e IPC local
./keila-radio --catalog-status  # Estado, edad, recuento, rutas y próxima actualización
./keila-radio --catalog-rebuild # Regenerar TSV desde el JSON guardado, sin descargar
./keila-radio --catalog-update  # Descargar catálogo y regenerar índice
```

`--check` no instala paquetes ni abre una emisora: puede inicializar rutas/datos y prueba un mpv local en modo inactivo. La falta del analizador es un aviso, no impide escuchar radio.

Cada reproducción usa una sesión y grupo de procesos propios. Al salir o cambiar de emisora, Keila solicita cierre limpio y aplica un plazo antes de terminar su grupo; no actúa sobre otros mpv. Al salir también finaliza grabación, cancela tareas, cierra el registro y restaura eco, cursor y pantalla.

**Límites:** `SIGKILL` impide ejecutar la limpieza de Bash y puede dejar audio reproduciéndose; no se promete recuperación automática de grupos abandonados. Las pruebas simuladas no sustituyen cortes de red, suspensión/reanudación de Android ni grabaciones reales en cada dispositivo. La alarma requiere Keila abierto y el equipo despierto.

La traducción a otros idiomas, la emisión propia a dispositivos por Bluetooth/Wi‑Fi y la distribución oficial Debian siguen pendientes; no son funciones disponibles.

</details>

## Actualizar

`U` actualiza emisoras. Para actualizar **el programa**, distingue tu instalación:

- **Copia Git:** actualiza la misma rama con `git pull --ff-only`, dentro del repositorio y sin descartar cambios locales.
- **Instalación de una versión publicada:** consulta e instala con:

```bash
./keila-radio --check-update
./keila-radio --update
```

El actualizador protege las copias Git de desarrollo. Para versiones compatibles valida rutas, versión, sintaxis y módulos, respalda los componentes gestionados y revierte si falla la comprobación final con `--version`. No sustituye datos XDG ni grabaciones.

Al arrancar hay una consulta de versiones en segundo plano: no retrasa el inicio y un fallo de GitHub no interrumpe la radio. Puede mostrar un aviso discreto en escritorio; `KEILA_NO_UPDATE_CHECK=1` la desactiva.

## Pruebas y desarrollo

```bash
bash tests/check.sh
```

Es el mismo comando de GitHub Actions: cubre lógica, integración y rendimiento con datos ficticios; usa audio sintético sin altavoces y terminales de prueba. No incluye sesiones manuales ni empaquetado Debian. Conserva registros y falla si falta una dependencia o se agota el tiempo.

[Guía de pruebas y grupos](TESTING.md) · [Protección de datos](DATA-SAFETY.md) · [Historial de cambios](CHANGELOG.md)

<details>
<summary>Perfilado, paquete Linux y organización del código</summary>

Para revisar un grupo: `bash tests/check.sh fast`, `integration` o `performance`; `bash tests/check.sh --list` muestra el inventario. `tests/run.sh` no es la batería completa.

Para investigar saltos de audio/interfaz:

```bash
bash tests/profile-live.sh
python3 tests/resource-profile.py --spectrum on
python3 tests/resource-profile.py --spectrum off
python3 tests/resource-profile.py --self-test
```

Son ejecuciones separadas. Con `profile-live.sh` escucha unos 30 segundos y sal con `Q`: informa captura, IPC, teclado y dibujo, sin contenido de emisoras; la instrumentación añade trabajo y no se deben sumar etapas anidadas.

Para comparar recursos, usa la misma emisora y tamaño durante al menos un minuto por sesión; sal con `Q`. No cambies emisora, grabes ni pulses `V`, y no combines ambos perfiladores. `off` desactiva la captura solo en esa sesión. Python 3 solo es necesario para este medidor, no para escuchar radio.

El informe incluye CPU acumulada/media (100 % = un núcleo), memoria residente y procesos, con desglose por Keila, mpv, FFmpeg, captura y auxiliares. No duplica CPU de hijos, pero procesos breves pueden quedar sin atribuir. Muestrea memoria cada 250 ms: puede contar páginas compartidas varias veces y omitir picos. Incluye arranque/cierre, no emulador de terminal ni servidor de audio compartido. Guarda `summary.json` temporal sin URLs, títulos ni configuración; `--self-test` no usa radio ni red.

Paquete Linux limpio:

```bash
bash scripts/package-linux.sh
```

Crea un `.tar.gz` y su SHA-256 en `dist/` con launcher, documentación, `defaults/` y `lib/`, sin Git ni datos personales. Extrae con `tar -xzf archivo.tar.gz` y ejecuta `./keila-radio` dentro de la carpeta extraída.

El código se organiza en `keila-radio` (entrada), `lib/` (módulos), `defaults/` (semilla), `scripts/` (distribución) y `tests/` (regresiones). La v1 está en el historial de Git, no en el árbol actual. La línea 2.1 prioriza correcciones, compatibilidad y pruebas; no implica que cada cambio de desarrollo sea una release publicada.

</details>

## Licencia

**GNU GPL v3 o posterior** (`GPL-3.0-or-later`). Copyright © Mauro Novellas. [Texto completo de la licencia](LICENSE).
