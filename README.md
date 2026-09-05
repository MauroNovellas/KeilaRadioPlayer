# Keila Radio Player

Keila Radio Player es un reproductor de radio en Bash para terminal, usando `mpv` como motor de reproducción.

La rama `v2` está en desarrollo activo y añade una arquitectura modular, persistencia XDG, búsqueda en TDTChannels y gestión de favoritos.

## Requisitos

- bash
- mpv
- socat
- curl
- jq
- fzf

En Debian:

```bash
sudo apt install mpv socat curl jq fzf
```

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

Durante la reproducción:

```text
p       pausa/reanudar
a / d   bajar/subir volumen
f       añadir/eliminar la emisora actual de favoritos
q       salir
```

En el menú de favoritos:

```text
N       reproducir favorito N
d N     eliminar favorito N
k N     mover favorito N hacia arriba
j N     mover favorito N hacia abajo
q       volver
```
