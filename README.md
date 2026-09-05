# Keila Radio Player

Keila Radio Player es un reproductor de radio en Bash para terminal, usando `mpv` como motor de reproducción.

La rama `v2` está en desarrollo activo y usa una arquitectura modular, persistencia XDG, búsqueda en TDTChannels, gestión de favoritos y una TUI navegable con teclado.

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
- Termux/Android: `pkg`
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

En Termux esas rutas se resuelven dentro del `$HOME` de Termux.

## Controles de la TUI

```text
W / S    mover la selección por favoritos
Enter    reproducir el favorito seleccionado
A / D    bajar/subir volumen
P        pausa/reanudar
F        añadir/eliminar la emisora en reproducción de favoritos
B        buscar una emisora en TDTChannels con fzf
U        actualizar el catálogo de TDTChannels
Q        salir
```

La lista de favoritos tiene scroll automático. Al buscar con `B`, Keila suspende temporalmente la TUI, abre `fzf` y vuelve a la interfaz al seleccionar o cancelar.

Al salir, Keila detiene `mpv`, restaura el cursor, abandona la pantalla alternativa de la TUI y limpia la pantalla principal para no dejar restos visuales.
