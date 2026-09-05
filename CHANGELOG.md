# Changelog

Todos los cambios relevantes de Keila Radio Player se documentarán en este archivo.

## [2.0.0-rc1] - 2026-09-05

Primera release candidate de la reconstrucción v2, centrada en Linux de escritorio.

### Añadido

- TUI interactiva con navegación por WASD, flechas, Home/End, PageUp/PageDown y ayuda contextual con `H`.
- Reproducción mediante `mpv` controlado por JSON IPC, con socket independiente por instancia.
- Estado de reproducción en vivo: conectando, reproduciendo, pausa y buffering.
- Metadatos dinámicos del stream: título/canción, codec, bitrate, frecuencia de muestreo y canales cuando la emisora los publica.
- Catálogo de TDTChannels con caché local y selección mediante `fzf`.
- Gestión persistente de favoritos: añadir, eliminar, reordenar y semilla inicial separada del estado personal.
- Grabación del stream actual sin abrir una segunda conexión, con contador `[REC HH:MM:SS]`, nombres por emisora/fecha y validación del archivo al cerrar.
- Selección automática de formato de grabación compatible con el stream (`.ts`, `.mp3`, `.aac`, `.ogg`, `.flac`, etc.).
- Configuración personal segura en `~/.config/keila-radio/config`.
- Persistencia XDG para configuración, favoritos, estado y caché.
- `./keila-radio --check` para validar la inicialización sin abrir la TUI.
- `./keila-radio --version` con versión centralizada en `lib/version.sh`.
- Tests de sintaxis, ShellCheck, configuración, estado, favoritos, grabación, TUI, concurrencia y smoke pre-RC.
- GitHub Actions para ejecutar automáticamente la batería de checks.

### Mejorado

- Redibujado de la TUI sin `clear` continuo para reducir parpadeo.
- Layout dinámico: las filas de metadatos y ayuda solo ocupan espacio cuando existen.
- Mensajes temporales que desaparecen automáticamente.
- Detección de cambios de canción mientras la emisora sigue reproduciéndose.
- Manejo de caídas inesperadas de `mpv` y recuperación/validación de grabaciones parciales.
- Nombres de grabación sanitizados y prevención de sobrescrituras.
- Bloqueo concurrente de favoritos y estado para evitar corrupción o pérdidas entre varias instancias.
- Escrituras atómicas mediante archivos temporales y sustitución final.

### Cambiado

- La plataforma principal de esta RC es Linux de escritorio. Termux/Android permanece soportado de forma secundaria y se pulirá después de estabilizar la versión de PC.
- Los restos de la antigua v1 ya no forman parte del árbol de trabajo de `v2`; continúan disponibles en el historial de Git.

### Conocido / pendiente para 2.0.0

- La reconexión automática de streams no está habilitada; Keila informa de una caída de `mpv` en lugar de reintentar silenciosamente.
- Termux necesita una pasada específica de adaptación visual y de interacción antes de considerarse al mismo nivel que la versión de escritorio.
- Durante la fase RC se priorizarán correcciones de regresiones y estabilidad sobre nuevas funciones.
