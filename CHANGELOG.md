# Changelog

Todos los cambios relevantes de Keila Radio Player se documentarán en este archivo.

## [2.0.0-rc2] - 2026-09-05

Segunda release candidate de Keila Radio Player 2.0, centrada en cerrar la experiencia de escritorio y endurecer el proceso de actualización antes de la versión estable.

### Añadido

- TUI rediseñada con marco Unicode y fallback ASCII automático.
- Tema semántico con colores para reproducción, grabación, favoritos, avisos y selección, con soporte para `NO_COLOR` y `KEILA_NO_COLOR=1`.
- Layout responsive con modos `wide`, `standard`, `compact` y `minimal`, adaptándose automáticamente al redimensionar la terminal.
- Vista desktop de dos paneles para terminales amplias: `Ahora suena` a la izquierda y `Favoritos` como panel principal de navegación a la derecha.
- Dashboard de reproducción con estado, metadatos, volumen, grabación y estado de favorito.
- `./keila-radio --check-update` para consultar versiones publicadas en GitHub.
- `./keila-radio --update` con descarga temporal, validación previa, backup, sustitución y rollback automático.
- Comprobación de actualizaciones en segundo plano dentro de la TUI, sin bloquear el arranque ni mostrar errores de red al usuario.
- `KEILA_NO_UPDATE_CHECK=1` para desactivar la consulta automática de actualizaciones de la TUI.
- Validación completa del árbol runtime antes de instalar una actualización.
- Pruebas específicas de tema, responsive, geometría desktop, ancho seguro, actualización, rollback y estado de actualización en la TUI.

### Corregido

- Eliminado el desplazamiento de una fila que hacía aparecer/desaparecer la primera línea durante los redibujados.
- Evitado el autowrap horizontal al tocar la última columna física de la terminal.
- Eliminado el arrastre visual de la barra de volumen y otros restos en la línea superior.
- `--check-update` y opciones desconocidas ya no pueden interpretarse accidentalmente como URLs para `mpv`.
- El comando `--update` se despacha explícitamente desde el launcher.

### Mejorado

- En PC, el modo ancho aprovecha prácticamente toda la anchura disponible dejando una única columna física de seguridad.
- La proporción desktop mantiene `Ahora suena` contenido y entrega el espacio adicional a `Favoritos`, mejorando la lectura de nombres largos.
- La barra de volumen y los badges se adaptan al espacio disponible sin introducir códigos ANSI en los cálculos de ancho.
- La composición conserva el mismo estado y selección al pasar dinámicamente entre desktop, wide, standard, compact y minimal.
- El auto-update conserva configuración, favoritos, estado, caché y grabaciones; los paquetes incompletos se rechazan antes de modificar la instalación.
- Las copias Git de desarrollo quedan protegidas frente a sustituciones por una release; deben seguir actualizándose mediante Git.

### Cambiado

- La TUI de escritorio rediseñada pasa a ser la interfaz candidata para Keila 2.0.
- `U` continúa reservado para actualizar el catálogo de TDTChannels; la actualización del programa se gestiona mediante `--update`.
- RC2 mantiene Linux de escritorio como plataforma principal. Termux/Android continúa como plataforma secundaria pendiente de una pasada específica tras estabilizar PC.

### Conocido / pendiente para 2.0.0

- La reconexión automática de streams no está habilitada; Keila informa de una caída de `mpv` en lugar de reintentar silenciosamente.
- Termux necesita una pasada específica de adaptación visual y de interacción antes de considerarse al mismo nivel que la versión de escritorio.
- Durante la fase RC se priorizarán correcciones de regresiones y estabilidad sobre nuevas funciones.

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
