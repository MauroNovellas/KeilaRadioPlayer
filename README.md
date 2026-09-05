# Keila Radio Player

Keila Radio Player es un reproductor de radio en Bash para terminal, usando `mpv` como motor de reproducción.

La versión candidata actual es **`2.0.0-rc2`**. La plataforma principal de esta release candidate es Linux de escritorio; Termux/Android sigue siendo compatible de forma secundaria y recibirá una pasada específica después de estabilizar la versión de PC.

Consulta el historial de cambios en [`CHANGELOG.md`](CHANGELOG.md).

## Versión

La versión vive en una única fuente, `lib/version.sh`, y puede consultarse sin inicializar dependencias ni abrir la TUI:

```bash
./keila-radio --version
```

Salida esperada para esta RC:

```text
Keila Radio Player 2.0.0-rc2
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

En desktop, `Ahora suena` queda como panel contenido a la izquierda y `Favoritos` ocupa la mayor parte del espacio a la derecha. El panel de reproducción muestra emisora, canción/programa, datos técnicos, volumen, estado, grabación y favorito cuando existe espacio suficiente.

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

`U` actualiza exclusivamente el catálogo de TDTChannels; no se reutiliza para actualizar el programa.

La navegación de favoritos es circular y tiene scroll automático. Al buscar con `B`, Keila suspende temporalmente la TUI, abre `fzf` y vuelve a la interfaz al seleccionar o cancelar.

Por defecto la zona de controles ocupa una sola fila para dejar más espacio a favoritos. `H` despliega la ayuda completa y la lista ajusta automáticamente su altura; `H` o `Esc` vuelven a compactarla.

Los mensajes de acciones y errores son temporales: avisos como el cambio de volumen, una búsqueda cancelada o una grabación guardada desaparecen solos después de unos segundos, mientras que el estado real de reproducción permanece en la TUI.

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
ACTUALIZACIÓN    2.0.0 disponible
```

La comprobación automática puede desactivarse:

```bash
KEILA_NO_UPDATE_CHECK=1 ./keila-radio
```

## Persistencia y concurrencia

Cada instancia de Keila usa su propio socket IPC de `mpv`, por lo que dos reproductores abiertos no se pisan entre sí.

Las escrituras de `state` y `favorites` están protegidas con mutex basados en `mkdir`, sin depender de `flock`. En favoritos se bloquea la operación completa leer → modificar → guardar, no solo el reemplazo final. Las operaciones por índice conservan además la identidad de la emisora por URL para evitar actuar sobre otro favorito si una segunda instancia cambia el orden simultáneamente.

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

RC2 incluye regresiones para configuración, estado, favoritos, grabación, tema, responsive, geometría desktop, protección contra autowrap/scroll, actualización, validación de paquetes, rollback y aviso de actualización en la TUI.

Ejecutar la batería local principal:

```bash
./tests/run.sh
bash ./tests/recording-formats.sh
bash ./tests/pre-rc.sh
bash ./tests/ui-theme.sh
bash ./tests/ui-responsive.sh
bash ./tests/ui-desktop.sh
bash ./tests/ui-update-status.sh
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
│   ├── config.sh
│   ├── deps.sh
│   ├── favorites.sh
│   ├── input.sh
│   ├── lock.sh
│   ├── player.sh
│   ├── recording.sh
│   ├── state.sh
│   ├── stations.sh
│   ├── ui.sh
│   ├── ui-responsive.sh
│   ├── ui-safe-width.sh
│   ├── ui-desktop.sh
│   ├── ui-desktop-primary.sh
│   ├── ui-desktop-balance.sh
│   ├── ui-update-status.sh
│   ├── update.sh
│   ├── update-validation.sh
│   └── version.sh
└── tests/
    ├── pre-rc.sh
    ├── recording-formats.sh
    ├── run.sh
    ├── ui-theme.sh
    ├── ui-responsive.sh
    ├── ui-desktop.sh
    ├── ui-update-status.sh
    └── update-check.sh
```

Los scripts, listados y documentación de la antigua v1 se mantienen en el historial de Git, pero ya no forman parte del árbol de trabajo actual.

Al salir, Keila detiene/finaliza la grabación si existe, detiene `mpv`, cancela una comprobación de actualización en segundo plano si sigue activa, restaura el cursor, abandona la pantalla alternativa de la TUI y limpia la pantalla principal para no dejar restos visuales.

## Política de la RC

Durante `2.0.0-rc2` se priorizan correcciones de regresiones y estabilidad. La reconexión automática y otras funciones nuevas quedan fuera de esta release candidate; si RC2 se mantiene estable, el siguiente objetivo es preparar `2.0.0` con cambios mínimos.
