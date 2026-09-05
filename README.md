# Keila Radio Player

Keila Radio Player es un reproductor de radio en Bash para terminal, usando `mpv` como motor de reproducción.

La rama `v2` está en desarrollo activo y usa una arquitectura modular, persistencia XDG, búsqueda en TDTChannels, gestión de favoritos y una TUI navegable con teclado.

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

## Controles de la TUI

```text
W / S o ↑ / ↓     mover la selección por favoritos
A / D o ← / →     bajar/subir volumen
Enter              reproducir el favorito seleccionado
Home / End         ir al primer/último favorito
PageUp / PageDown  saltar por la lista
P                  pausa/reanudar
F                  añadir/eliminar la emisora en reproducción de favoritos
J / K              mover el favorito seleccionado abajo/arriba
X                  eliminar el favorito seleccionado
B                  buscar una emisora en TDTChannels con fzf
U                  actualizar el catálogo de TDTChannels
Q                  salir
```

La navegación de favoritos es circular y tiene scroll automático. Al buscar con `B`, Keila suspende temporalmente la TUI, abre `fzf` y vuelve a la interfaz al seleccionar o cancelar.

La entrada de teclado vive en `lib/input.sh`: el lector reconoce WASD y secuencias ANSI de flechas, reacciona a cambios de tamaño de la terminal y despierta periódicamente para detectar si `mpv` termina por su cuenta sin necesidad de pulsar una tecla.

Al salir, Keila detiene `mpv`, restaura el cursor, abandona la pantalla alternativa de la TUI y limpia la pantalla principal para no dejar restos visuales.
