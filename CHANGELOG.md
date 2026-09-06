# Changelog

Todos los cambios relevantes de Keila Radio Player se documentarán en este archivo.

## [Sin publicar] - rama v2.1

- Reducido el coste del sondeo de eventos de `mpv`: la TUI ya no espera innecesariamente cuando no hay notificaciones y cada evento se parsea con una sola invocación de `jq`.
- Las posiciones del rectángulo del espectro se calculan una sola vez por geometría de terminal, evitando lanzar `tput` repetidamente durante los redibujados completos.

## [2.1.0] - 2026-09-07

Segunda versión estable de Keila Radio Player, centrada en completar la experiencia de reproducción de escritorio y cerrar la línea `v2.1` con pruebas de rendimiento, reconexión y distribución portable para Linux.

- Añadido empaquetado Linux reproducible con suma SHA-256, runtime limpio y prueba de extracción del launcher sin configuraciones ni grabaciones personales.
- Añadidos cinco presets de ecualizador (`1` Plano, `2` Rock, `3` Pop, `4` Jazz y `5` Voz) dentro del modo `Z`, con aplicación inmediata y persistencia.
- Añadido pico retenido por banda en el espectro: el marcador permanece unos cuadros y cae gradualmente para dar más continuidad visual sin añadir trabajo de captura.
- Corregida la última banda del espectro: una columna de guarda evita que el borde vacío de `showfreqs` aparezca como una banda inmóvil.
- Activada y documentada la reconexión automática tras una caída o un stream estancado, con backoff progresivo, protección durante grabaciones y sin destellos de error genérico en la TUI.
- Añadido suavizado ligero entre cuadros del espectro para amortiguar ráfagas y pausas irregulares sin introducir procesos ni cambiar el audio.
- Ajustada la tubería FFmpeg del espectro para evitar reprogramar cuadros ya generados y solicitar baja latencia (`nobuffer`, `low_delay`, `avioflags direct`, `fps_mode passthrough`).
- La captura del espectro solicita latencia de 40 ms y procesamiento de 20 ms para evitar las ráfagas observadas de unos 700 ms. El backend PulseAudio directo usa fragmentos equivalentes a 20 ms de PCM mono.
- Diagnóstico opcional de pausas en reproducción con `bash tests/profile-live.sh`: registra tiempos por etapa y cadencia de cuadros, y presenta un resumen al salir.
- Refresco parcial del espectro con un límite de 20 Hz: actualiza solo el rectángulo de barras, sin reconstruir las listas. Los editores de etiquetas y ecualizador evitan redibujos completos en cada tick; las posiciones se recalculan al redimensionar.
- El espectro usa amplitud logarítmica para destacar señales suaves y aprovechar más altura, conservando el refresco a 4 Hz y el audio original.
- Corregido el reloj del espectro con coma decimal (configuración regional española), que provocaba errores aritméticos durante el refresco. La medición de rendimiento admite también ambos separadores.
- Eliminados subprocesos por celda al dibujar las barras ampliadas. Añadida medición aislada del dibujo con `bash tests/render-benchmark.sh`, sin audio ni red.
- Reorganizada la vista desktop: el ecualizador y el espectro ocupan todo el ancho de `Ahora suena`, y el analizador queda apilado debajo del ecualizador en lugar de compartir sus filas.
- El analizador de espectro pasa a un gráfico vertical de ocho filas, igualando la altura visible del ecualizador. Agrupa las 16 bandas en hasta ocho columnas separadas y usa bloques parciales para distinguir mejor cada barra; la pantalla se actualiza a cuatro cuadros por segundo sin reducir la frecuencia de captura.

- Corregido el buffering del analizador: entrega cuadros durante la captura continua sin esperar a cerrar el flujo. Prueba integral con PCM generado en tiempo real.

- Añadido ecualizador de cinco bandas persistente: 60 Hz, 250 Hz, 1 kHz, 4 kHz y 12 kHz, ajustable desde la TUI con `Z` y restablecible a sonido plano.
- Las cinco barras ampliadas del ecualizador permanecen dentro del panel normal; `Z` activa la edición en el sitio, `←`/`→` seleccionan frecuencia, `↑`/`↓` ajustan el valor, `C` centra la banda y `R` restablece las cinco.
- Añadido analizador de espectro real de 16 bandas en el panel de reproducción de escritorio, con activación mediante `V`, captura sobre el monitor PulseAudio/PipeWire y degradación limpia cuando no está disponible.
- La detección y la detención del proceso auxiliar del espectro tienen tiempos máximos y cierre forzado para que nunca bloqueen la entrada de la TUI.
- El espectro usa `parec` cuando está disponible para capturar de forma más compatible el monitor PulseAudio/PipeWire y muestra 16 barras de altura variable, incluida una línea base visible sin señal.
- `--check` informa del ecualizador y explica si el analizador carece de herramientas, backend o monitor de salida; los mismos motivos aparecen en la TUI cuando falla la captura.
- Favoritos y BUSQUEDA EMISORAS muestran una columna de etiquetas personales; el encabezado se abrevia a «ETIQUETAS» al reducir el ancho. La separación del buscador utiliza el color de los demás bordes.

- El catálogo se carga al abrir la TUI. La caché se muestra de inmediato y la descarga se realiza en segundo plano; un fallo de red conserva el catálogo anterior.
- El panel Emisoras elimina las instrucciones duplicadas y aprovecha esa fila para mostrar resultados. `B` activa el filtro.
- `E` edita una etiqueta personal de la emisora seleccionada en Favoritos, Recientes o búsqueda; Enter guarda, Esc cancela y Ctrl-U vacía. El filtro también encuentra etiquetas.
- Recientes aparece bajo Favoritos, dentro del mismo recuadro, con navegación y reproducción mediante las teclas habituales. Conserva las últimas 20 emisoras distintas que alcanzaron audio y oculta las favoritas.
- Etiquetas e historial se guardan de forma local y atómica en archivos XDG separados, sin cambiar el formato existente de favoritos.

## [2.0.0] - 2026-09-06

Primera versión estable de Keila Radio Player 2.0. Promociona el código validado como `2.0.0-rc3` tras pruebas intensivas en Debian con `foot`, Termux/Android y uso adicional de terceros sin regresiones reportadas.

### Estable

- Se declara estable la TUI responsive introducida y refinada durante RC1, RC2 y RC3.
- La búsqueda integrada, Favoritos, reproducción, grabación, metadatos, actualización y persistencia mantienen el comportamiento validado en RC3.
- La gestión de teclado conserva la protección de `ECHO` y el control de autorepeat que evitan caracteres fantasma y colas de pulsaciones atrasadas.
- El actualizador seguro mantiene validación completa del paquete, backup, rollback y preservación de datos XDG y grabaciones.
- Linux de escritorio continúa como plataforma principal y Termux/Android queda también validado para uso real, incluida la TUI en pantallas pequeñas.

### Cambiado

- La versión pasa de `2.0.0-rc3` a `2.0.0`.
- No se introducen cambios funcionales de runtime respecto a RC3: la estable es una promoción del candidato ya validado.

### Conocido

- La reconexión automática de streams no forma parte de 2.0.0; si `mpv` cae, Keila informa del fallo en lugar de reintentar silenciosamente.

## [2.0.0-rc3] - 2026-09-06

Tercera release candidate de Keila Radio Player 2.0, centrada en integrar la búsqueda dentro de la TUI y en pulir el comportamiento del terminal bajo uso rápido e intensivo antes de la versión estable.

### Añadido

- Búsqueda de emisoras integrada directamente en la TUI, sin abandonar la interfaz principal.
- En desktop, la columna de navegación se divide en `Favoritos` arriba y `Buscar emisoras` abajo, con scroll y selección independientes.
- Filtrado incremental por nombre, ámbito, país y formato sobre el catálogo local de TDTChannels.
- Navegación de resultados con flechas, Home/End y PageUp/PageDown, además de reproducción con `Enter`.
- `F` mayúscula dentro de la búsqueda para añadir o quitar directamente el resultado seleccionado de Favoritos sin abandonar el buscador ni cambiar la emisora en reproducción.
- Indicadores `[★]` y `[PLAY] [★]` en resultados de búsqueda para distinguir favoritos y emisora en reproducción.
- `KEILA_FZF_SEARCH=1` para conservar `fzf` como selector externo opcional.
- Protección persistente del estado `ECHO` del terminal durante toda la vida activa de la TUI, con restauración exacta al suspender o salir.
- Agrupación y limitación de autorepeat de teclado para volumen y navegación, evitando colas de pulsaciones atrasadas tras soltar una tecla.
- Regresiones específicas para búsqueda integrada, favoritos desde búsqueda, panel dividido, protección de terminal y autorepeat.

### Corregido

- Eliminados los caracteres sueltos que podían aparecer en pantalla al pulsar teclas muy rápidamente durante IPC o redibujados.
- Eliminado el efecto de “tecla pegada” por el que volumen o selección podían seguir avanzando después de soltar una tecla mantenida.
- `Esc` conserva ahora la consulta de búsqueda y `B editar` reabre realmente la misma búsqueda, incluso cuando no había resultados.
- Si falla la persistencia de Favoritos, el estado en memoria vuelve inmediatamente al último estado válido del archivo y no muestra cambios fantasma.
- La selección y el scroll de Favoritos ya no compiten con la selección y el scroll de resultados en el layout desktop dividido.

### Mejorado

- El filtrado de búsqueda se difiere ligeramente respecto a la escritura para que cada carácter aparezca inmediatamente incluso con catálogos grandes.
- Se precalcula un índice de búsqueda en minúsculas para reducir el trabajo repetido durante el filtrado.
- Las ráfagas de autorepeat se consumen en bloque y aplican un máximo de pasos útiles por frame, descartando trabajo atrasado pero conservando la siguiente tecla distinta.
- Durante el foco de búsqueda, el pie muestra únicamente controles válidos para ese contexto y evita anunciar atajos que en ese momento son texto.
- La búsqueda conserva reproducción, metadatos, mensajes y comprobación de actualización mientras permanece abierta.
- El árbol obligatorio del auto-update incluye todos los módulos de búsqueda y la protección nueva del terminal.
- La TUI actual ha sido validada en uso real tanto en Debian con `foot` como en Termux/Android, incluyendo pantallas pequeñas.

### Cambiado

- `B` abre por defecto la búsqueda integrada. `fzf` queda como fallback explícito mediante `KEILA_FZF_SEARCH=1`.
- En búsqueda integrada, `f` minúscula sigue siendo texto normal y solo `F` mayúscula se reserva para alternar Favorito sobre el resultado seleccionado.
- Termux/Android deja de figurar como adaptación pendiente: RC3 mantiene Linux de escritorio como plataforma principal, pero la TUI responsive y la interacción han sido verificadas también en Termux.

### Conocido / pendiente para 2.0.0

- La reconexión automática de streams no está habilitada; Keila informa de una caída de `mpv` en lugar de reintentar silenciosamente.
- Durante RC3 se priorizarán únicamente correcciones de regresiones, estabilidad y documentación; no se añadirán funciones nuevas antes de decidir la versión estable.

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
