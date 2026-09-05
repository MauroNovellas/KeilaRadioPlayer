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

Los datos personales se guardan fuera del repositorio:

```text
~/.config/keila-radio/favorites
~/.local/state/keila-radio/state
~/.cache/keila-radio/radio.json
```

Las grabaciones, en cambio, se guardan por comodidad junto al proyecto:

```text
KeilaRadioPlayer/grabaciones/
```

La carpeta se crea automáticamente al arrancar y está ignorada por Git.

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
Q                  salir
```

La navegación de favoritos es circular y tiene scroll automático. Al buscar con `B`, Keila suspende temporalmente la TUI, abre `fzf` y vuelve a la interfaz al seleccionar o cancelar.

La entrada de teclado vive en `lib/input.sh`: el lector reconoce WASD y secuencias ANSI de flechas, reacciona a cambios de tamaño de la terminal y despierta periódicamente para detectar si `mpv` termina por su cuenta sin necesidad de pulsar una tecla.

## Información del stream

Mientras una emisora está reproduciéndose, Keila consulta `mpv` mediante JSON IPC aproximadamente una vez por segundo. La TUI puede mostrar, cuando la emisora o el demuxer proporcionan esos datos:

```text
Ahora: Artista - Canción / programa en emisión
Audio: AAC · 128 kbps · 44.1 kHz · stereo
```

Las filas de información son dinámicas: si una emisora no publica título en emisión, no se reserva una línea vacía para `Ahora:`; si tampoco hay información técnica disponible, tampoco aparece `Audio:`.

El bitrate mostrado procede de la propiedad `audio-bitrate` de `mpv`; Keila ya no intenta estimarlo midiendo el tráfico total de la interfaz de red. Para el título en emisión consulta tanto el objeto general de metadatos como campos ICY específicos y `media-title`, de modo que los cambios de canción puedan reflejarse mientras el stream sigue reproduciéndose.

Las consultas de información se agrupan en una sola conexión IPC y la TUI solo se redibuja cuando algún dato cambia.

## Grabaciones

`R` activa o desactiva la grabación del stream que ya está recibiendo el mismo proceso de `mpv`; no se abre una segunda conexión a la emisora. Mientras está activa aparece `[REC]` en la línea de estado.

Los archivos usan contenedor Matroska Audio (`.mka`) para poder guardar distintos codecs de las emisoras sin forzar una conversión. El nombre se genera con la emisora y la fecha/hora de inicio, por ejemplo:

```text
Rock_FM_2026-09-05_20-31-42.mka
```

Si cambias de emisora mientras estás grabando, Keila cierra primero la grabación actual. Al salir también intenta cerrar la grabación antes de detener `mpv`, para que el fichero quede finalizado correctamente.

Al salir, Keila detiene `mpv`, restaura el cursor, abandona la pantalla alternativa de la TUI y limpia la pantalla principal para no dejar restos visuales.
