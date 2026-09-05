# Keila Radio Player

Keila Radio Player es un reproductor de radio en Bash para terminal, usando `mpv` como motor de reproducción.

La rama `v2` está en desarrollo activo y usa una arquitectura modular, persistencia XDG, búsqueda en TDTChannels, gestión de favoritos, grabación del stream y una TUI navegable con teclado.

La plataforma principal de desarrollo es Linux de escritorio. La compatibilidad con Termux/Android existe, pero por ahora se considera secundaria y se pulirá cuando la versión de PC esté más consolidada.

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

Gestores soportados por el instalador automático:

- Debian/Ubuntu: `apt-get`
- Termux/Android: `pkg`/`apt-get`
- Arch Linux: `pacman`
- Fedora: `dnf`

Para `tput`, Keila instala `ncurses-bin` en Debian y `ncurses-utils` en Termux.

## Ejecutar v2

```bash
./keila-radio
```

También existe un smoke check de inicialización que no abre TUI, red ni `mpv`:

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
W / S o ↑ / ↓     mover la selección por favoritos
A / D o ← / →     bajar/subir volumen
Enter              reproducir el favorito seleccionado
Home / End         ir al primer/último favorito
PageUp / PageDown  saltar por la lista
P                  pausa/reanudar
R                  iniciar/detener grabación del stream actual
F                  añadir/eliminar la emisora en reproducción de favoritos
J / K              mover el favorito seleccionado abajo/arriba
X                  eliminar el favorito seleccionado
B                  buscar una emisora en TDTChannels con fzf
U                  actualizar el catálogo de TDTChannels
H                  abrir/cerrar la ayuda completa
Esc                cerrar la ayuda completa
Q                  salir
```

La navegación de favoritos es circular y tiene scroll automático. Al buscar con `B`, Keila suspende temporalmente la TUI, abre `fzf` y vuelve a la interfaz al seleccionar o cancelar.

Por defecto la zona de controles ocupa una sola fila para dejar más espacio a favoritos. `H` despliega cuatro filas con todos los atajos y la lista ajusta automáticamente su altura; `H` o `Esc` vuelven a compactarla.

Los mensajes de acciones y errores son temporales: avisos como el cambio de volumen, una búsqueda cancelada o una grabación guardada desaparecen solos después de unos segundos, mientras que el estado real de reproducción permanece en las líneas superiores de la TUI.

## Persistencia y concurrencia

Cada instancia de Keila usa su propio socket IPC de `mpv`, por lo que dos reproductores abiertos no se pisan entre sí.

Las escrituras de `state` y `favorites` también están protegidas con mutex basados en `mkdir`, sin depender de `flock`. En favoritos se bloquea la operación completa leer → modificar → guardar, no solo el `mv` final. Las operaciones por índice conservan además la identidad de la emisora por URL para evitar actuar sobre otro favorito si una segunda instancia cambia el orden simultáneamente.

## Información del stream

Mientras una emisora está reproduciéndose, Keila consulta `mpv` mediante JSON IPC. La TUI puede mostrar, cuando la emisora o el demuxer proporcionan esos datos:

```text
Ahora: Artista - Canción / programa en emisión
Audio: AAC · 128 kbps · 44.1 kHz · stereo
```

Las filas son dinámicas: si una emisora no publica título en emisión, no se reserva una línea vacía para `Ahora:`; si tampoco hay información técnica disponible, tampoco aparece `Audio:`.

El bitrate mostrado procede de `audio-bitrate` de `mpv`. Para el título en emisión Keila consulta tanto el objeto general de metadatos como campos ICY específicos y `media-title`, de modo que los cambios de canción puedan reflejarse mientras el stream sigue reproduciéndose.

## Grabaciones

`R` activa o desactiva la grabación del stream que ya está recibiendo el mismo proceso de `mpv`; no se abre una segunda conexión a la emisora.

Mientras está activa aparece un contador en la línea de estado:

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

La rama `v2` incluye pruebas de regresión para configuración, estado, favoritos, helpers/formato de grabación y estado visual de la TUI. La batería pre-RC añade un smoke test real de inicialización y una prueba con varios procesos escribiendo favoritos simultáneamente.

Ejecutarlas localmente:

```bash
./tests/run.sh
bash ./tests/recording-formats.sh
bash ./tests/pre-rc.sh
```

Si `shellcheck` está instalado, el runner principal también lo ejecuta sobre los módulos principales. El workflow `.github/workflows/checks.yml` instala ShellCheck y ejecuta todas estas comprobaciones automáticamente en GitHub.

## Estructura v2

```text
KeilaRadioPlayer/
├── keila-radio
├── defaults/
│   └── favorites
├── lib/
│   ├── config.sh
│   ├── deps.sh
│   ├── favorites.sh
│   ├── input.sh
│   ├── lock.sh
│   ├── player.sh
│   ├── recording.sh
│   ├── state.sh
│   ├── stations.sh
│   └── ui.sh
├── tests/
│   ├── pre-rc.sh
│   ├── recording-formats.sh
│   └── run.sh
└── README.md
```

Los scripts, listados y documentación de la antigua v1 se mantienen en el historial de Git, pero ya no forman parte del árbol de trabajo de `v2`.

Al salir, Keila detiene/finaliza la grabación si existe, detiene `mpv`, restaura el cursor, abandona la pantalla alternativa de la TUI y limpia la pantalla principal para no dejar restos visuales.
