# Keila Radio Player

Keila Radio Player es un reproductor de radio en Bash para terminal, usando `mpv` como motor de reproducción.

La versión estable actual es **`2.0.0`**. Linux de escritorio es la plataforma principal, y la TUI también ha sido validada en Termux/Android, incluyendo terminales de pantalla pequeña.

Consulta el historial de cambios en [`CHANGELOG.md`](CHANGELOG.md).

## Versión

La versión vive en una única fuente, `lib/version.sh`, y puede consultarse sin inicializar dependencias ni abrir la TUI:

```bash
./keila-radio --version
```

Salida esperada para esta versión:

```text
Keila Radio Player 2.0.0
```

## Dependencias

Keila comprueba sus dependencias al arrancar. En esta fase de desarrollo personal, si falta alguna intenta instalarla automáticamente sin pedir confirmación.

Dependencias de ejecución:

- bash
- mpv
- socat
- curl
- jq
- fzf
- tput

`fzf` se conserva como selector externo opcional; la búsqueda integrada es la interfaz predeterminada.

Gestores soportados por el instalador automático:

- Debian/Ubuntu: `apt-get`
- Termux/Android: `pkg`/`apt-get`
- Arch Linux: `pacman`
- Fedora: `dnf`

Para `tput`, Keila instala `ncurses-bin` en Debian y `ncurses-utils` en Termux.

## Ejecutar

```bash
./keila-radio
```

También existe un smoke check de inicialización que no abre la TUI ni inicia `mpv`:

```bash
./keila-radio --check
```

Comprueba que la configuración, favoritos, estado y carpeta de grabaciones pueden inicializarse correctamente.

Los datos personales se guardan fuera del repositorio:

```text
~/.config/keila-radio/config
~/.config/keila-radio/favorites
~/.local/state/keila-radio/state
~/.cache/keila-radio/radio.json
```

La semilla inicial de favoritos vive en `defaults/favorites`. Solo se copia al directorio personal si todavía no existe un fichero de favoritos del usuario.

## TUI responsive

Keila adapta automáticamente la composición al tamaño de la terminal y recalcula el layout durante el redimensionado:

```text
≥ 112 columnas y ≥ 20 filas   desktop de dos paneles
≥ 80x20                       wide
≥ 62x16                       standard
≥ 50x13                       compact
≥ 42x11                       minimal
< 42x11                       aviso de terminal demasiado pequeña
```

En desktop, `Ahora suena` queda como panel contenido a la izquierda. La columna derecha se divide verticalmente en `Favoritos` y `Recientes` arriba y `BUSQUEDA EMISORAS` abajo, con selección y scroll independientes. El panel de reproducción muestra emisora, canción/programa, datos técnicos, volumen, estado, grabación y favorito cuando existe espacio suficiente.

El modo ancho de PC utiliza prácticamente toda la anchura disponible, reservando una columna física de seguridad para evitar autowrap. El borde inferior tampoco imprime un salto de línea adicional, evitando que la terminal haga scroll durante los redibujados.

La interfaz usa Unicode cuando la locale lo permite y cae automáticamente a ASCII. Puede forzarse manualmente con:

```bash
KEILA_ASCII_UI=1 ./keila-radio
```

Los colores son semánticos y no participan en los cálculos de anchura. Pueden desactivarse con cualquiera de estas opciones:

```bash
KEILA_NO_COLOR=1 ./keila-radio
NO_COLOR=1 ./keila-radio
```

## Configuración

En el primer arranque Keila crea automáticamente:

```text
~/.config/keila-radio/config
```

El fichero se interpreta como datos y nunca se ejecuta con `source`. Las claves disponibles son:

```text
volume_step=5
metadata_interval=1
catalog_max_age=86400
recordings_dir=
```

- `volume_step`: salto de volumen para A/D y ←/→, entre 1 y 50.
- `metadata_interval`: segundos entre consultas de metadatos de `mpv`, entre 1 y 60.
- `catalog_max_age`: edad máxima de la caché de TDTChannels en segundos; `0` fuerza actualización.
- `recordings_dir`: vacío usa `grabaciones/` junto a Keila. También acepta rutas absolutas, `~/...` y rutas relativas a `$HOME`.

Los valores inválidos se ignoran y se conserva el valor por defecto.

## Controles de la TUI

```text
W / S o ↑ / ↓     mover la selección por favoritos y recientes
A / D o ← / →     bajar/subir volumen
Enter              reproducir el favorito seleccionado
Home / End         ir al primer/último favorito
PageUp / PageDown  saltar por la lista
P                  pausa/reanudar
R                  iniciar/detener grabación del stream actual
E                  editar etiqueta de la emisora seleccionada
Z                  abrir ecualizador
V                  mostrar/ocultar analizador de espectro
F                  añadir/eliminar la emisora en reproducción de favoritos
J / K              mover el favorito seleccionado abajo/arriba
X                  eliminar el favorito seleccionado
B                  abrir/editar la búsqueda integrada de emisoras
U                  actualizar el catálogo de TDTChannels
H                  abrir/cerrar la ayuda completa
Esc                cerrar la ayuda completa
Q                  salir
```

`U` actualiza exclusivamente el catálogo de TDTChannels; no se reutiliza para actualizar el programa.

La navegación de favoritos y recientes es circular y tiene scroll automático. El catálogo local de TDTChannels se carga al iniciar Keila y se actualiza en segundo plano cuando caduca. Sin conexión se conserva la copia guardada. Al pulsar `B`, Keila activa el filtro de la búsqueda integrada. La reproducción, los metadatos y los avisos continúan activos mientras se busca.

Dentro de la búsqueda:

```text
escribir             filtrar por nombre, ámbito, país y formato
↑ / ↓                mover por los resultados
Home / End            primer/último resultado
PageUp / PageDown     saltar por los resultados
Enter                 reproducir el resultado seleccionado
F                     añadir/quitar el resultado de Favoritos
E                     editar la etiqueta del resultado seleccionado
Backspace             borrar un carácter
Ctrl+U                limpiar la consulta
Esc                   volver a Favoritos conservando la consulta
```

Todas las emisoras admiten una etiqueta personal: selecciona una en Favoritos, Recientes o la búsqueda y pulsa `E` (por ejemplo, `Rock FM` → `Heavy Metal`). `Enter` guarda, `Esc` cancela y `Ctrl-U` vacía el campo; guarda vacío para quitar la etiqueta. Las etiquetas también se incluyen en el filtro de búsqueda y aparecen en las tres listas. Sus encabezados cambian de `ETIQUETAS PERSONALES` a `ETIQUETAS` cuando disminuye el ancho disponible.

Debajo de Favoritos, `Recientes` muestra emisoras escuchadas que no están en Favoritos. Usa la misma navegación y `Enter` para reproducirlas. El historial local conserva hasta 20 emisoras distintas, en orden de última escucha; una conexión que no llega a audio no se registra. Si añades una emisora a Favoritos se oculta de Recientes. Los presets `1–9/0` siguen reservados exclusivamente a favoritos.

Las etiquetas se guardan en `$XDG_CONFIG_HOME/keila-radio/labels` (por defecto `~/.config/keila-radio/labels`) y el historial en `$XDG_STATE_HOME/keila-radio/history` (por defecto `~/.local/state/keila-radio/history`). El historial contiene nombres y URLs de emisoras, sin títulos de canciones ni marcas de tiempo. Puedes borrar el archivo con Keila cerrada para vaciarlo.

Las letras `e` y `f` minúsculas son texto normal dentro del buscador; `F` mayúscula alterna Favorito y `E` mayúscula abre la etiqueta. Los resultados favoritos muestran `[★]`, y la emisora que además está sonando puede mostrar `[PLAY] [★]`.

Al salir de la búsqueda con `Esc`, la consulta permanece visible. Pulsar de nuevo `B` la reabre para seguir editándola. Para usar el selector externo clásico con `fzf`:

```bash
KEILA_FZF_SEARCH=1 ./keila-radio
```

Por defecto la zona de controles ocupa una sola fila para dejar más espacio a la interfaz. `H` despliega la ayuda completa y la composición ajusta automáticamente su altura; `H` o `Esc` vuelven a compactarla.

Los mensajes de acciones y errores son temporales: avisos como el cambio de volumen, una grabación guardada o un cambio de Favoritos desaparecen solos después de unos segundos, mientras que el estado real de reproducción permanece en la TUI.

### Ecualizador

El ecualizador de cinco bandas —60 Hz, 250 Hz, 1 kHz, 4 kHz y 12 kHz— permanece visible junto al volumen. Cada barra representa su ganancia entre −12 y +12 dB y el punto medio corresponde a 0 dB.

Pulsa `Z` para activar la edición sobre ese mismo panel, sin cambiar de pantalla. Usa `←`/`→` para elegir la frecuencia y `↑`/`↓` para subir o bajar su valor. `C` centra únicamente la banda seleccionada en 0 dB y `R` devuelve las cinco bandas al sonido plano; `Z`, `Enter` o `Esc` desactivan la edición.

En el layout de escritorio, las cinco barras ampliadas forman parte permanente de `Ahora suena`. Durante la edición, una marca más gruesa en el eje indica la frecuencia seleccionada y el encabezado muestra su valor exacto.

Los cambios se aplican inmediatamente a la emisora en reproducción y se conservan para las siguientes sesiones en `~/.config/keila-radio/equalizer` (o su ruta XDG equivalente). Si una aplicación del filtro falla, Keila mantiene el ajuste anterior.

### Analizador de espectro

El panel `Ahora suena` muestra un analizador de 16 bandas cuando existe audio real. Pulsa `V` para ocultarlo o volverlo a mostrar. La captura se detiene automáticamente al pausar o detener la reproducción y vuelve a arrancar al reanudarla.

En Linux de escritorio usa el monitor de la salida PulseAudio/PipeWire mediante `parec`, `ffmpeg` y `pactl`; analiza el audio que ya está reproduciendo `mpv` y no abre otra conexión a la emisora. Las barras de 16 frecuencias permanecen dibujadas incluso antes de recibir señal. Estas herramientas son opcionales: si no existen o el sistema no expone un monitor compatible, Keila continúa funcionando y muestra `No disponible` en el panel. En Debian/Ubuntu pueden instalarse con:

```bash
sudo apt install ffmpeg pulseaudio-utils
```

## Teclado y terminal

Keila mantiene desactivado el `ECHO` del terminal durante toda la vida activa de la TUI, no solo mientras Bash espera una tecla. Esto evita que pulsaciones rápidas aparezcan directamente como caracteres sueltos durante IPC o redibujados.

El estado exacto del terminal se restaura al suspender la TUI y al salir. La protección no pone el terminal completo en modo raw y no modifica el parser de flechas/secuencias ANSI.

Las teclas repetibles de navegación y volumen aplican además control de autorepeat: Keila consume las ráfagas pendientes en bloque, limita el trabajo útil por frame y descarta repeticiones atrasadas. Al soltar una tecla mantenida, volumen o selección dejan de avanzar prácticamente al momento en lugar de procesar una cola antigua.

## Actualizaciones

Para consultar los tags publicados compatibles con la versión actual:

```bash
./keila-radio --check-update
```

Para instalar una versión nueva publicada:

```bash
./keila-radio --update
```

El actualizador:

1. selecciona únicamente una versión publicada compatible;
2. descarga el paquete a un directorio temporal;
3. comprueba rutas seguras, versión, sintaxis Bash y todos los módulos runtime obligatorios;
4. crea una copia de seguridad temporal de los componentes gestionados;
5. instala la nueva versión;
6. ejecuta una comprobación final con `--version`;
7. restaura automáticamente la versión anterior si la comprobación final falla.

La actualización no sustituye los datos XDG del usuario ni `grabaciones/`.

Las copias Git de desarrollo, como una rama distinta de `main`, no se sustituyen automáticamente por una release. Keila las protege y pide actualizarlas mediante Git.

Al abrir la TUI se realiza además una comprobación de actualización en segundo plano. No retrasa el arranque: si GitHub no responde, Keila sigue funcionando sin mostrar un error. Cuando existe una versión superior, el layout desktop puede mostrar discretamente:

```text
ACTUALIZACIÓN    2.0.1 disponible
```

La comprobación automática puede desactivarse:

```bash
KEILA_NO_UPDATE_CHECK=1 ./keila-radio
```

## Persistencia y concurrencia

Cada instancia de Keila usa su propio socket IPC de `mpv`, por lo que dos reproductores abiertos no se pisan entre sí.

Las escrituras de `state` y `favorites` están protegidas con mutex basados en `mkdir`, sin depender de `flock`. En favoritos se bloquea la operación completa leer → modificar → guardar, no solo el reemplazo final. Las operaciones por índice conservan además la identidad de la emisora por URL para evitar actuar sobre otro favorito si una segunda instancia cambia el orden simultáneamente.

Si una escritura de Favoritos falla, Keila vuelve a cargar en memoria el último estado válido del archivo para no mostrar cambios que realmente no llegaron a persistirse.

## Información del stream

Mientras una emisora está reproduciéndose, Keila consulta `mpv` mediante JSON IPC. La TUI puede mostrar, cuando la emisora o el demuxer proporcionan esos datos:

```text
Artista - Canción / programa en emisión
AAC · 128 kbps · 44.1 kHz · stereo
```

Las filas son dinámicas: si una emisora no publica título en emisión o datos técnicos, el layout adapta el espacio disponible.

El bitrate mostrado procede de `audio-bitrate` de `mpv`. Para el título en emisión Keila consulta tanto el objeto general de metadatos como campos ICY específicos y `media-title`, de modo que los cambios de canción puedan reflejarse mientras el stream sigue reproduciéndose.

## Grabaciones

`R` activa o desactiva la grabación del stream que ya está recibiendo el mismo proceso de `mpv`; no se abre una segunda conexión a la emisora.

Mientras está activa aparece un contador:

```text
[REC 00:03:27]
```

Keila conserva un formato compatible con el stream de entrada en lugar de forzar siempre un único contenedor. Entre los casos habituales:

```text
HLS / m3u8  -> .ts
MP3         -> .mp3
AAC         -> .aac
Ogg / Opus  -> .ogg
FLAC        -> .flac
```

Cuando la URL no revela el formato, Keila consulta a `mpv` qué demuxer está usando y, si hace falta, utiliza también el codec de audio conocido.

El nombre se genera con la emisora y la fecha/hora de inicio, por ejemplo:

```text
Rock_FM_2026-09-05_20-31-42.ts
```

Por defecto se guardan en:

```text
KeilaRadioPlayer/grabaciones/
```

La carpeta está ignorada por Git. Al detener una grabación Keila espera a que el muxer termine de cerrar buffers, comprueba que el fichero existe y contiene datos, y muestra también su tamaño. Si `mpv` cae inesperadamente, intenta validar y conservar el archivo que haya quedado.

## Comprobaciones

Keila 2.0.0 incluye regresiones para configuración, estado, favoritos, grabación, tema, responsive, geometría desktop, protección contra autowrap/scroll, búsqueda integrada, Favoritos desde búsqueda, persistencia fallida, protección del terminal, autorepeat, actualización, validación de paquetes, rollback y aviso de actualización en la TUI.

Ejecutar la batería local principal:

```bash
./tests/run.sh
bash ./tests/recording-formats.sh
bash ./tests/pre-rc.sh
bash ./tests/ui-theme.sh
bash ./tests/ui-responsive.sh
bash ./tests/ui-desktop.sh
bash ./tests/ui-update-status.sh
bash ./tests/search-integrated.sh
bash ./tests/equalizer.sh
bash ./tests/spectrum.sh
bash ./tests/search-favorites.sh
bash ./tests/ui-desktop-search-pane.sh
bash ./tests/ui-terminal-guard.sh
bash ./tests/input-repeat.sh
bash ./tests/update-check.sh
```

El workflow `.github/workflows/checks.yml` instala ShellCheck y ejecuta automáticamente la batería completa en GitHub Actions.

## Estructura

```text
KeilaRadioPlayer/
├── .github/workflows/checks.yml
├── keila-radio
├── CHANGELOG.md
├── README.md
├── defaults/
│   └── favorites
├── lib/
│   ├── app-search.sh
│   ├── config.sh
│   ├── deps.sh
│   ├── favorites.sh
│   ├── input.sh
│   ├── lock.sh
│   ├── player.sh
│   ├── recording.sh
│   ├── search.sh
│   ├── spectrum.sh
│   ├── state.sh
│   ├── stations.sh
│   ├── ui.sh
│   ├── ui-responsive.sh
│   ├── ui-safe-width.sh
│   ├── ui-desktop.sh
│   ├── ui-desktop-primary.sh
│   ├── ui-desktop-balance.sh
│   ├── ui-desktop-search-pane.sh
│   ├── ui-search.sh
│   ├── ui-terminal-guard.sh
│   ├── ui-update-status.sh
│   ├── update.sh
│   ├── update-validation.sh
│   └── version.sh
└── tests/
    ├── input-repeat.sh
    ├── pre-rc.sh
    ├── recording-formats.sh
    ├── run.sh
    ├── search-favorites.sh
    ├── search-integrated.sh
    ├── spectrum.sh
    ├── ui-desktop.sh
    ├── ui-desktop-search-pane.sh
    ├── ui-responsive.sh
    ├── ui-terminal-guard.sh
    ├── ui-theme.sh
    ├── ui-update-status.sh
    └── update-check.sh
```

Los scripts, listados y documentación de la antigua v1 se mantienen en el historial de Git, pero ya no forman parte del árbol de trabajo actual.

Al salir, Keila detiene/finaliza la grabación si existe, detiene `mpv`, cancela una comprobación de actualización en segundo plano si sigue activa, restaura el estado exacto del terminal y el cursor, abandona la pantalla alternativa de la TUI y limpia la pantalla principal para no dejar restos visuales.

## Política de estabilidad

`2.0.0` promociona el comportamiento ya validado en `2.0.0-rc3` sin introducir cambios funcionales de runtime. Las nuevas funciones quedan para versiones posteriores; los cambios sobre la línea estable deben priorizar correcciones, compatibilidad y regresiones bien cubiertas por pruebas.
