# Keila Radio Player

Keila Radio Player es un reproductor de radio en Bash para terminal, usando `mpv` como motor de reproducción.

La versión estable actual es **`2.1.1`**. Linux de escritorio es la plataforma principal, y la TUI también ha sido validada en Termux/Android, incluyendo terminales de pantalla pequeña.

Consulta el historial de cambios en [`CHANGELOG.md`](CHANGELOG.md).

## Licencia

Keila Radio Player se distribuye bajo la licencia **GNU General Public License
3 o posterior** (`GPL-3.0-or-later`). Consulta el texto en [`LICENSE`](LICENSE).
El copyright corresponde a Mauro Novellas.

## Versión

### Preferencias y ayuda

Pulsa `,` en la pantalla principal para abrir **Configuración**. Usa las flechas
para elegir y `Enter` para cambiar; cada cambio se guarda inmediatamente.
`Esc` regresa al reproductor. Puedes activar o desactivar la reproducción al
inicio, los colores, Unicode y el espectrograma. Cada opción muestra
«Activado» o «Desactivado» y una explicación breve. La última opción permite
restaurar los valores predeterminados con confirmación: no borra emisoras,
comentarios ni volumen, y no modifica la alarma temporal.
Las preferencias se guardan como datos en
`$XDG_CONFIG_HOME/keila-radio/preferences` (por defecto,
`~/.config/keila-radio/preferences`), con permisos privados y sustitución atómica.
Las variables `NO_COLOR`, `KEILA_NO_COLOR` y `KEILA_ASCII_UI` siguen teniendo
prioridad sobre las preferencias visuales.

El volumen se recupera automáticamente y, por defecto, también se reproduce la
última emisora que llegó a entregar audio. Una conexión fallida no reemplaza
esa última escucha. Puedes desactivar el inicio automático en Configuración;
una URL proporcionada al ejecutar Keila tiene prioridad. La alarma sigue siendo
temporal: nunca se guarda ni se arma al volver a abrir el programa.

En el mismo selector puedes reasignar las acciones de la pantalla principal.
Selecciona una acción, pulsa `Enter` y después su nueva letra. Si ya pertenece
a otra acción, se intercambian ambas. Las flechas, números y A/D/W/S/J/K quedan
reservados para navegación, volumen y ordenación. Los editores y la búsqueda
mantienen sus teclas locales, para poder escribir sin activar acciones.
Los encabezados de la pantalla principal reflejan las letras asignadas.

Pulsa `O` para abrir **Opciones**, un menú jerárquico pensado para no memorizar
todos los atajos. Desde ahí puedes entrar en `Reproducción`, `Emisoras`,
`Visualización`, `Temporizador`, `Grabaciones`, `Sesión`, `Configuración`,
`Datos y almacenamiento`, `Diagnóstico` y `Ayuda`. Muchos controles cotidianos —pausa, silencio, volumen,
búsqueda, catálogo, favoritos, comentarios, grabación, alarma, ecualizador y
espectrograma— también pueden ejecutarse navegando por ese árbol. Los atajos
directos siguen disponibles para usuarios habituales.

El menú muestra la ruta (`OPCIONES > EMISORAS`) y conserva la selección de cada
categoría al volver. `↑`/`↓` seleccionan, `Enter` abre o ejecuta, `→` abre una
categoría y `←`/`Esc` vuelve un nivel. La flecha derecha no cambia ajustes ni
confirma eliminaciones. `PgUp`/`PgDn` avanza una página visible y `Home`/`End`
salta a los extremos. Las letras entre corchetes son accesos locales del menú;
no cambian al personalizar los atajos de la pantalla principal.

Cada opción incluye una explicación y su estado cuando corresponde: pausa,
silencio, volumen, alarma, fase de grabación, catálogo o preferencia guardada.
Las acciones no disponibles se atenúan y explican qué falta para usarlas.
En terminales anchas la explicación queda al lado de la lista; en Termux se
usan filas compactas y un bloque de detalle de altura fija. `?` abre la
explicación completa, desplazable incluso en pantallas pequeñas; `Esc` vuelve
a la misma opción. Esta vista es de lectura y no ejecuta acciones.

`Ir a Favoritas`, `Ir a Recientes`, la búsqueda y una reproducción iniciada
desde el menú devuelven el control al reproductor. La gestión de favoritas
dentro de Opciones actúa sobre la emisora **seleccionada**, aunque otra esté
sonando. Añadir es inmediato; eliminar exige repetir `Enter` o `X`, y navegar
cancela esa confirmación. Si falla el guardado de colores, Unicode o inicio
automático desde Opciones, se mantiene el valor anterior y se muestra el error.
La alarma, reconexión y detección de grabaciones siguen atendidas con el menú
abierto; los estados se reutilizan sin analizar el catálogo por cada tecla.

Preferencias, Ayuda, Alarma, Ecualizador, Comentarios, Grabaciones, Historial
de sesión, Diagnóstico y Copias de seguridad comparten esa misma presentación, tanto al abrirlos
desde Opciones como mediante su atajo directo: cabecera con ruta, cursor
estable, estados alineados, explicación y controles al pie. El formato se
adapta al tamaño y al modo ASCII/Unicode desde un único renderizador.
En las listas, `Enter` o `?` permite leer los detalles completos y `Esc` vuelve
al nivel anterior; en Preferencias, `Enter` cambia el ajuste y `?` lo explica.
Los editores conservan sus teclas de escritura y ajuste: un `?` escrito en
Comentarios forma parte del texto.

La alarma y los comentarios disponen de un campo de edición propio. El texto
y las confirmaciones se conservan al redimensionar la terminal. Si falla el
guardado de un comentario, el editor permite reintentarlo sin perder el texto;
si falla el guardado de preferencias o atajos, se conserva el valor anterior.
Diagnóstico y el historial permiten llegar a cualquier fila con las flechas,
`PgUp`/`PgDn` y `Home`/`End`, y consultar rutas y textos largos en su detalle.
El historial solo sigue las nuevas canciones si ya estabas leyendo al final.

`D` mayúscula abre **Diagnóstico en vivo** sin detener la reproducción. Muestra
versión, rama/commit si el árbol es Git, estado de `mpv`, emisora y título
actual, volumen, catálogo, resultados precargados, grabaciones pendientes y
rutas de configuración, estado, caché, favoritos, comentarios y grabaciones.

`?` abre siempre la ayuda completa, también accesible con `H` de forma
predeterminada. La ayuda se desplaza con las flechas y muestra los atajos
actuales, presets, búsqueda, comentarios, grabaciones, ecualizador y alarma.
El audio y la reconexión siguen atendidos mientras estos paneles están abiertos.

Las reconexiones automáticas conservan volumen y silencio desde el arranque de
`mpv`, sin un instante de sonido previo. Elegir manualmente otra emisora vuelve
a activar el sonido. Un fallo al iniciar el reproductor no se presenta como
prueba de que no haya Internet.

Validación manual pendiente en Termux: suspender y reanudar Android, cortar y
recuperar la red con el sonido silenciado y comprobar una grabación real. Las
pruebas automatizadas simulan estos estados, pero no sustituyen al dispositivo.

La versión vive en una única fuente, `lib/version.sh`, y puede consultarse sin inicializar dependencias ni abrir la TUI:

```bash
./keila-radio --version
```

Salida esperada para esta versión:

```text
Keila Radio Player 2.1.1
```

## Revisar grabaciones

Pulsa `;` en la pantalla principal para abrir el gestor. Al arrancar, Keila
busca en segundo plano audios con marcador `.pending` y avisa si los encuentra,
sin retrasar el inicio de la radio. La lista muestra nombre, fecha de modificación
y tamaño en bytes; en pantallas estrechas cada entrada ocupa dos filas.

- Flechas / Home / End: seleccionar; `Esc`: regresar.
- `C`: comprobar el audio en segundo plano. Si mpv verifica un fragmento y el
  archivo no ha cambiado, se retira el marcador y sale de la lista. El audio
  permanece en su ubicación original; una comprobación dudosa no lo elimina.
- `E`: escuchar o detener. Se pausa temporalmente la radio y se reanuda al
  terminar o salir, si sigue siendo la misma sesión. No cambia el historial ni
  la última emisora guardada. No se inicia una escucha mientras se graba.
- `X`, seguido de `Enter`: mover audio y marcador a la carpeta `.trash` dentro
  de grabaciones. Cualquier otra tecla cancela. No es un borrado definitivo:
  los archivos pueden recuperarse manualmente desde esa carpeta.

Los marcadores nuevos identifican el proceso de mpv para excluir grabaciones
activas. Con marcadores antiguos vacíos, Keila es conservador y puede aplazar
la revisión mientras haya otro mpv abierto. Solo se revisa la carpeta configurada,
sin recorrer subcarpetas ni seguir enlaces simbólicos a archivos.

Al iniciar una grabación se muestra «Preparando grabación» hasta que aparecen
datos; después pasa a «Grabando». Al detenerla, «Cierre pendiente» indica que
mpv aún no ha confirmado que liberó el archivo. Un fallo antes de que mpv acepte
la orden limpia la reserva vacía.

Las garantías de guardado y los marcadores de grabación `.pending` se explican
en [Protección de datos](DATA-SAFETY.md), con pruebas y límites conocidos.

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

El diagnóstico también informa del perfil de ecualización y comprueba si el analizador dispone de `ffmpeg`, un backend de captura y un monitor PulseAudio/PipeWire. La ausencia del analizador se muestra como aviso porque no impide reproducir emisoras.

Para diagnosticar el catálogo de Radio Browser sin abrir la TUI:

```bash
./keila-radio --catalog-status   # estado, edad, recuento, rutas y próxima actualización
./keila-radio --catalog-rebuild  # regenera el índice rápido desde la copia JSON
./keila-radio --catalog-update   # descarga Radio Browser y regenera el índice
```

## Datos y almacenamiento: copias de seguridad

Pulsa `O` → `A` para abrir **Datos y almacenamiento**. Desde este menú:

- `C` crea una copia privada de favoritas, comentarios, recientes y ajustes.
- `R` abre las copias disponibles, ordenadas por fecha de modificación, con
  nombre y tamaño. Dentro del gestor, `Enter` o `?` abre el detalle; `C` crea,
  `U` actualiza la lista y `R` comprueba la copia seleccionada para restaurarla.
- Tras la comprobación aparece una pantalla con el archivo y los datos
  incluidos. Solo `Enter` confirma; `Esc` cancela sin cambiar nada. Redimensionar
  o recorrer los datos no confirma. Se conserva la selección al volver.

Las nuevas copias se guardan en `$XDG_STATE_HOME/keila-radio/backups` (por
defecto, `~/.local/state/keila-radio/backups`). También se muestran los respaldos
`pre-restore-*.tar.gz` de configuración y las antiguas `keila-backup-*.tar.gz`
que estén junto al programa. No se recorre el teléfono ni se siguen enlaces.
Para importar desde otro equipo, coloca su `.tar.gz` en esa carpeta de copias
y pulsa `U`. La ruta también aparece en Diagnóstico.

Las operaciones se ejecutan en segundo plano mientras se atienden audio,
reconexión y alarma. Restaurar requiere detener cualquier grabación o escucha
del gestor de grabaciones. Antes de cambiar datos se crea un respaldo previo;
si falla, no se restaura. Durante la publicación, `Esc` espera a que termine,
para no interrumpir a mitad del conjunto. Un cierre forzado puede dejar una
restauración parcial: se conserva el respaldo previo completo.

La restauración recarga favoritas, comentarios, recientes, preferencias y
ecualizador. **No cambia la emisora actual, el volumen, el silencio ni la alarma**.
El volumen/última emisora guardados y la carpeta importada de grabaciones se usan
al reiniciar. Las acciones posteriores del usuario vuelven a guardarse normalmente.
Una copia no contiene grabaciones, catálogo ni registros de canciones de sesión.
No se borran copias automáticamente ni se sobrescribe una existente.

También siguen disponibles los comandos para mover datos entre equipos:

```bash
./keila-radio --backup [archivo.tar.gz]
./keila-radio --restore archivo.tar.gz
```

La copia incluye configuración, favoritos, comentarios, preferencias, estado,
historial y ecualizador. No incluye grabaciones, registros de sesión ni caché
de Radio Browser. Al restaurar se valida el archivo completo antes de tocar nada
y se crea una copia previa automática en
`~/.config/keila-radio/pre-restore-*.tar.gz`.
El comando `--restore` es explícito y no muestra una segunda confirmación;
desde la TUI siempre se pide confirmar. Límites y garantías en
[Protección de datos](DATA-SAFETY.md).

## Rutas de datos

Los datos personales se guardan fuera del repositorio:

```text
~/.config/keila-radio/config
~/.config/keila-radio/favorites
~/.local/state/keila-radio/state
~/.local/state/keila-radio/history
~/.local/state/keila-radio/sessions/keila-session-*.txt
~/.cache/keila-radio/radio.json
~/.cache/keila-radio/radio.tsv
```

La semilla inicial de favoritos vive en `defaults/favorites`. Solo se copia al directorio personal si todavía no existe un fichero de favoritos del usuario.

## TUI responsive

Keila adapta automáticamente la composición al tamaño de la terminal y recalcula el layout durante el redimensionado:

En los modos pequeños (menos de 62 columnas o de 16 filas), la pantalla
principal no muestra el ecualizador ni los comentarios de Favoritas y
Recientes. La ecualización sigue aplicada y los comentarios se conservan;
los editores siguen disponibles. Al ampliar la terminal reaparecen los detalles.

```text
≥ 112 columnas y ≥ 20 filas   desktop de dos paneles
≥ 80x20                       wide
≥ 62x16                       standard
≥ 50x13                       compact
≥ 42x11                       minimal
< 42x11                       aviso de terminal demasiado pequeña
```

En pantalla completa, `Ahora suena` queda como panel contenido a la izquierda. La mitad superior de la columna derecha muestra `Emisoras favoritas` y `Recientes` lado a lado, con selección y scroll independientes; debajo queda `BUSQUEDA EMISORAS`. En terminales estrechas las listas se apilan. El panel de reproducción muestra emisora, canción/programa, datos técnicos, volumen, estado, grabación y favorito cuando existe espacio suficiente.

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
catalog_limit=50000
catalog_country_filter=ES
search_match_limit=300
recordings_dir=
```

- `volume_step`: salto de volumen para A/D y ←/→, entre 1 y 50.
- `metadata_interval`: segundos entre consultas de metadatos de `mpv`, entre 1 y 60.
- `catalog_max_age`: edad máxima de la caché de Radio Browser en segundos; `0` fuerza actualización.
- `catalog_limit`: máximo de emisoras a guardar desde Radio Browser, entre 100 y 100000.
- `catalog_country_filter`: país preferido para el filtro rápido de búsqueda, en código ISO de dos letras (`ES`, `FR`, `US`...).
- `search_match_limit`: máximo de resultados visibles por búsqueda, entre 100 y 20000. El catálogo completo sigue disponible; escribe más texto para afinar.
- `recordings_dir`: vacío usa `grabaciones/` junto a Keila. También acepta rutas absolutas, `~/...` y rutas relativas a `$HOME`.

Los valores inválidos se ignoran y se conserva el valor por defecto.

## Controles de la TUI

```text
W / S o ↑ / ↓     mover la selección por favoritos y recientes
A / D o ← / →     bajar/subir volumen
Enter              reproducir la emisora seleccionada
Home / End         ir al primer/último favorito
PageUp / PageDown  saltar por la lista
0–9                reproducir un preset de Emisoras favoritas o Recientes según la sección activa
P                  pausa/reanudar
M                  silenciar/recuperar el sonido sin cambiar volumen
L                  configurar o cancelar alarma (HH:MM)
F                  ir a Favoritas
C                  editar comentario de la emisora seleccionada
R                  ir a Recientes
G                  iniciar/detener grabación del stream actual
Z                  abrir ecualizador
V                  mostrar/ocultar analizador de espectro
X                  añadir/quitar la emisora en reproducción de Favoritas
J / K              mover el favorito seleccionado abajo/arriba
O                  abrir Opciones
B                  abrir/editar la búsqueda integrada de emisoras
D                  diagnóstico en vivo
U                  actualizar el catálogo de Radio Browser
H                  abrir/cerrar la ayuda completa
Esc                cerrar la ayuda completa
Q                  salir
```

`U` actualiza exclusivamente el catálogo de Radio Browser; no se reutiliza para actualizar el programa.

La navegación de Emisoras favoritas y Recientes es circular y tiene scroll automático. En cualquiera de las dos secciones, `1–9` reproduce las posiciones 1–9 y `0` la posición 10 de esa misma lista. El catálogo local de Radio Browser se actualiza en segundo plano cuando caduca. La respuesta JSON se conserva como copia de respaldo y Keila genera a partir de ella un índice TSV podado con solo los campos que usa la TUI: nombre, ámbito/tags, país, formato, URL, código de país y una clave interna de búsqueda. Sin conexión se conserva la copia guardada. Si el índice ya está fresco, Keila precarga los primeros resultados al arrancar sin tomar el foco; `B` solo entra a editar la búsqueda. La reproducción, los metadatos y los avisos continúan activos mientras se busca.

Dentro de la búsqueda:

```text
escribir             filtrar por nombre, ámbito, país y formato
P                     activar/desactivar filtro rápido por país
← / →                ocultar/mostrar detalles en pantallas pequeñas
↑ / ↓                mover por los resultados
Home / End            primer/último resultado
PageUp / PageDown     saltar por los resultados
Enter                 reproducir el resultado seleccionado
X                     añadir/quitar el resultado de Favoritas
F / R                 salir de búsqueda e ir a Favoritas / Recientes
C                     editar el comentario del resultado seleccionado
Backspace             borrar un carácter
Supr                  limpiar la consulta
Esc                   volver a Favoritos conservando la consulta
```

Todas las emisoras admiten un comentario personal: selecciona una en Favoritos, Recientes o la búsqueda y pulsa `C` (por ejemplo, `Rock FM` → `Heavy Metal`). `Enter` guarda, `Esc` cancela y `Ctrl-U` vacía el campo; guarda vacío para quitar el comentario. Los comentarios también se incluyen en el filtro de búsqueda y aparecen en las tres listas. Sus encabezados se muestran siempre como `COMENTARIOS` y conservan el color de su sección.

`Recientes` muestra las últimas 20 emisoras distintas escuchadas, de más reciente a más antigua, incluidas las favoritas, marcadas con `★`. Una conexión que no llega a audio no se registra. `X` añade o quita de Favoritas la entrada reciente seleccionada; añadir es inmediato y quitar exige una segunda pulsación. La selección permanece en Recientes. Los presets `1–9` y `0` corresponden a las diez primeras entradas de la sección activa; las demás se recorren con cursores.

Algunas emisoras HLS publican el cambio de canción mediante metadatos ID3
temporizados. Keila lee primero los metadatos vivos de `mpv`; si el reproductor
conserva fijo el primer título, abre en segundo plano una consulta nueva con
`ffprobe` cada 20 segundos para leer de nuevo el stream sin reiniciar la emisora.
Si tampoco aparece un título distinto, se aplica una caducidad de cinco minutos
para no mostrar una canción antigua indefinidamente. `KEILA_TITLE_PROBE_INTERVAL`
y `KEILA_TITLE_MAX_AGE` permiten ajustar ambos límites en segundos.

Mientras escuchas una emisora, Keila reserva un bloque fijo con ocho líneas para
canciones anteriores detectadas en esa misma sintonía, sin repetir la canción
actual que ya aparece en `Ahora suena`. La novena línea muestra la ruta del TXT
de sesión. Al quedar el espacio reservado desde el principio, la TUI no desplaza
favoritos, volumen ni paneles cuando van apareciendo canciones nuevas. En modos
compactos o sin altura suficiente se oculta para no volver ilegible la pantalla.
Durante pruebas puede ajustarse con `KEILA_TRACK_HISTORY_DISPLAY_LIMIT` entre
1 y 20; en ese caso la ruta del TXT aparece después de las líneas reservadas.

Desde `O > Sesión` puedes abrir ese TXT dentro de la TUI. La pantalla muestra
hora, emisora y canción/evento, permite desplazarse con flechas, Home/End y
PageUp/PageDown, enseña la ruta del archivo y se actualiza mientras la radio
sigue sonando. Desde `D` Diagnóstico también puedes entrar con `S`.

Cada ejecución interactiva crea además un archivo de sesión en texto plano:

```text
~/.local/state/keila-radio/sessions/keila-session-AAAA-MM-DD_HH-MM-SS-*.txt
```

Cada línea útil contiene fecha/hora, emisora y canción o evento, separados por
tabuladores. El archivo se crea con permisos privados (`600`) dentro de un
directorio privado (`700`). Es intencionadamente legible para poder revisarlo,
depurar metadatos o importarlo más adelante en otra herramienta.

Los comentarios se guardan en `$XDG_CONFIG_HOME/keila-radio/labels` (por defecto
`~/.config/keila-radio/labels`) y el historial de emisoras recientes en
`$XDG_STATE_HOME/keila-radio/history` (por defecto
`~/.local/state/keila-radio/history`). Ese historial contiene solo nombres y
URLs de emisoras; los títulos y marcas de tiempo quedan en los registros de
sesión. Puedes borrar esos archivos con Keila cerrada para vaciarlos.

La futura opción para emitir hacia altavoces, televisores u otros dispositivos
por Bluetooth o Wi‑Fi queda pendiente como bloque separado: requerirá elegir
backends por plataforma, especialmente en Termux/Android.

Las minúsculas son texto normal dentro del buscador. `X` mayúscula añade o solicita confirmación para quitar el resultado de Favoritas; `C` abre su comentario y `F`/`R` cambian de sección. Los números siguen siendo texto de consulta. `Supr` limpia la consulta completa.

En pantallas `tiny` y `minimal`, la búsqueda muestra de entrada solo los nombres de emisora para mantener la lista legible. Dentro del buscador, `→` despliega los detalles disponibles en todas las filas visibles y `←` vuelve a ocultarlos; en ese contexto las flechas izquierda/derecha no cambian el volumen.

Al salir de la búsqueda con `Esc`, la consulta permanece visible. Pulsar de nuevo `B` la reabre para seguir editándola. Para usar el selector externo clásico con `fzf`:

```bash
KEILA_FZF_SEARCH=1 ./keila-radio
```

Por defecto la zona de controles ocupa una sola fila para dejar más espacio a la interfaz. `H` despliega la ayuda completa y la composición ajusta automáticamente su altura; `H` o `Esc` vuelven a compactarla.

Los mensajes de acciones y errores son temporales: avisos como el cambio de volumen, una grabación guardada o un cambio de Favoritos desaparecen solos después de unos segundos, mientras que el estado real de reproducción permanece en la TUI.

### Ecualizador

El ecualizador de cinco bandas —60 Hz, 250 Hz, 1 kHz, 4 kHz y 12 kHz— permanece visible a todo el ancho de `Ahora suena`, justo debajo del volumen. Cada barra representa su ganancia entre −12 y +12 dB y el punto medio corresponde a 0 dB.

Pulsa `Z` para abrir el editor del ecualizador, con el mismo estilo que Opciones
y disponible también en pantallas pequeñas. Usa `←`/`→` para elegir la banda y
`↑`/`↓` para ajustar su ganancia. `C` centra la banda seleccionada en 0 dB y `R`
deja las cinco planas; `Z`, `Enter` o `Esc` vuelven. Los cambios se aplican al
editarlos; salir del editor no los deshace. `?` explica los controles completos.

Mientras editas, las teclas `1` a `5` aplican presets rápidos: `1` Plano, `2` Rock, `3` Pop, `4` Jazz y `5` Voz. Solo funcionan dentro del editor y se guardan igual que los ajustes manuales; fuera de `Z`, las teclas numéricas mantienen sus presets de Favoritos.

En el layout de escritorio, las cinco barras ampliadas forman parte permanente de `Ahora suena` y utilizan todo el ancho del panel. Durante la edición, una marca más gruesa en el eje indica la frecuencia seleccionada.

Los cambios se aplican inmediatamente a la emisora en reproducción y se conservan para las siguientes sesiones en `~/.config/keila-radio/equalizer` (o su ruta XDG equivalente). Si una aplicación del filtro falla, Keila mantiene el ajuste anterior.

### Analizador de espectro

El panel `Ahora suena` muestra el analizador vertical de 16 bandas debajo del ecualizador, separado en su propio bloque y utilizando también todo el ancho del panel. Ocupa ocho filas cuando existe audio real, con la misma altura visible que el ecualizador. Las bandas se agrupan en columnas anchas separadas y se usan bloques parciales en la parte superior. Pulsa `V` para ocultarlo o volverlo a mostrar. La captura se detiene automáticamente al pausar o detener la reproducción y vuelve a arrancar al reanudarla.

El espectro se refresca de forma independiente, con un máximo de veinte cuadros por segundo. Cada frame actualiza solo sus barras; favoritos, búsqueda y ecualizador se redibujan cuando hay otros cambios. La frecuencia efectiva depende del equipo y de las demás acciones de la interfaz.

La captura solicita entregas de audio pequeñas (20 ms, con latencia solicitada de 40 ms en `parec`) para reducir acumulaciones y ráfagas. El servidor de audio puede ajustar estos valores según el dispositivo. La tubería reserva una columna de guarda en `showfreqs` para que la última banda visible no coincida con el borde vacío que dibuja FFmpeg.

Entre cuadros consecutivos se aplica un suavizado ligero: las subidas responden rápido y las caídas se amortiguan para que una entrega irregular no produzca saltos visuales. No afecta al audio ni al ecualizador.

Cada banda conserva además un marcador de pico durante unos cuadros. El marcador desciende gradualmente después de que la señal baje, haciendo visible el nivel máximo reciente sin retrasar la respuesta de las barras.

La altura utiliza una escala logarítmica de amplitud para hacer más visibles las señales suaves. Las frecuencias también se distribuyen logarítmicamente. Este ajuste es solo visual y no modifica el volumen ni el ecualizador.

Para investigar saltos durante la reproducción, ejecuta `bash tests/profile-live.sh`, reproduce una emisora durante unos 30 segundos y sal con `Q`. Al cerrar aparece un resumen de tiempos de captura, consulta a mpv, teclado y dibujo, con los intervalos máximos entre cuadros. El registro temporal contiene solo etapas y tiempos, no contenido de emisoras. La instrumentación añade algo de trabajo y solo está activa en esa ejecución. Las duraciones de etapas anidadas no deben sumarse.

Para comparar recursos en Linux, usa Python 3 (solo necesario para esta prueba):

```bash
python3 tests/resource-profile.py --spectrum on
python3 tests/resource-profile.py --spectrum off
```

Son dos sesiones independientes: en cada una reproduce la misma emisora durante al menos un minuto, conserva el tamaño de terminal y sal con `Q`. No pulses `V`, no grabes ni cambies de emisora durante la comparación. No combines esta prueba con `profile-live.sh`. El modo `off` desactiva la captura del espectro solo en esa sesión.

Al salir se muestra CPU acumulada y media (100 % equivale a un núcleo), memoria residente sumada y número de procesos. La tabla de desglose agrupa la CPU observada entre Keila, `mpv`, FFmpeg, captura y auxiliares; cuenta solo la CPU propia de cada proceso para no duplicar la de los hijos. Los procesos muy breves y el tramo final entre dos muestras pueden quedar en «CPU sin atribuir», por lo que el total de CPU del encabezado es la referencia. La memoria se muestrea cada 250 ms: puede contar páginas compartidas varias veces y omitir picos breves. El resumen incluye arranque y cierre; no mide el emulador de terminal ni el servidor de audio compartido. Se guarda también en un archivo temporal `summary.json`, sin URLs, títulos ni configuración personal. Para validar el medidor sin radio ni red: `python3 tests/resource-profile.py --self-test`.

En Linux de escritorio usa el monitor de la salida PulseAudio/PipeWire mediante `parec`, `ffmpeg` y `pactl`; analiza el audio que ya está reproduciendo `mpv` y no abre otra conexión a la emisora. Las barras de 16 frecuencias permanecen dibujadas incluso antes de recibir señal. Estas herramientas son opcionales: si no existen o el sistema no expone un monitor compatible, Keila continúa funcionando y muestra `No disponible` en el panel. En Debian/Ubuntu pueden instalarse con:

```bash
sudo apt install ffmpeg pulseaudio-utils
```

### Reconexión automática

Después de que una emisora haya reproducido audio real, Keila detecta si `mpv` termina o si el stream deja de avanzar. Mantiene la emisora y sus ajustes, muestra el intento actual y reintenta sin bloquear el teclado. Los reintentos usan una espera progresiva que empieza en 2 segundos y se duplica hasta 30, con un máximo de tres intentos por ciclo. Una reproducción que nunca llegó a producir audio no se reintenta automáticamente para evitar bucles sobre URLs inválidas.

Durante una grabación la reconexión automática queda bloqueada para proteger el archivo. Pausar también cancela los intentos pendientes; al reanudar se concede una ventana nueva para que el stream avance. Los límites se pueden ajustar por entorno si el equipo o la emisora lo necesitan: `KEILA_RECONNECT_STALL_TIMEOUT`, `KEILA_RECONNECT_START_TIMEOUT`, `KEILA_RECONNECT_MAX_ATTEMPTS` y `KEILA_RECONNECT_BASE_DELAY`.

Para crear un paquete Linux limpio desde el checkout, ejecuta `bash scripts/package-linux.sh`. El resultado se guarda en `dist/` junto con una suma SHA-256 e incluye el launcher, la documentación, `defaults/` y `lib/`; no incluye `.git`, configuraciones personales ni `grabaciones/`. Puedes extraerlo en cualquier carpeta Linux con `tar -xzf` y lanzar `./keila-radio` desde allí.

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

## Alarma y silencio

`L` abre el editor de alarma: escribe `HH:MM` y pulsa Enter. Si la hora ya ha
pasado, se programa para mañana (hora local del equipo). Enter con el campo
vacío cancela la alarma; Esc vuelve sin modificarla. La cabecera indica la
fecha y hora programadas. Solo hay una alarma por sesión, de una ejecución.

Keila debe permanecer abierto y el equipo despierto; no es un despertador del
sistema ni persiste al cerrar el programa. Al llegar la hora intenta reproducir
la última emisora escuchada, incluidas escuchas posteriores a la programación,
y desactiva el silencio. Usa el volumen configurado: compruébalo antes, así
como la conexión. Un fallo de conexión se muestra en pantalla. Durante una
grabación se aplica el mismo cierre seguro que al cambiar de emisora.

`M` alterna el silencio sin cambiar el volumen ni interrumpir las grabaciones.
En la búsqueda se usa `M` mayúscula; la minúscula sigue siendo texto. Una nueva
reproducción comienza con sonido. El indicador `MUTE` aparece en la cabecera.

Cada reproducción de `mpv` se inicia en una sesión y grupo de procesos privado.
Al cerrar o cambiar de emisora, Keila solicita una salida limpia, espera un
tiempo limitado y termina ese grupo si fuese necesario. Solo utiliza el grupo
cuando su líder coincide con el PID registrado de la instancia, evitando
afectar a otros reproductores. El cierre forzado de Keila (`SIGKILL`) no permite
ejecutar ninguna limpieza de Bash; ese caso sigue siendo una limitación del
sistema y puede dejar el grupo reproduciendo. El aislamiento evita confundirlo
con otro `mpv` y deja preparada la siguiente mejora: registrar sesiones activas
para limpiar grupos abandonados al iniciar una nueva instancia.

Al volver de una suspensión larga, el ciclo de la interfaz detecta el salto de
tiempo, valida el IPC y comprueba que el reloj de audio continúa avanzando. Si
la conexión quedó bloqueada, reutiliza la reconexión automática sin crear una
segunda instancia; durante una grabación solo avisa y protege el archivo.

Si una emisora falla al iniciar o no llega a producir audio, Keila muestra el
motivo disponible y realiza hasta tres reintentos con espera progresiva. Los
fallos posteriores del proceso o del stream siguen la misma política. Una URL
inválida no se reintenta automáticamente y las grabaciones nunca se cambian de
emisora por una reconexión.

## Grabación del stream

`G` activa o desactiva la grabación del stream que ya está recibiendo el mismo proceso de `mpv`; no se abre una segunda conexión a la emisora.

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

Las regresiones cubren datos personales, recuperación, grabaciones, reproducción,
reconexión, metadatos, catálogo, búsqueda, navegación, pantallas pequeñas,
Opciones, submenús, sesiones y actualización.

Ejecutar la batería local principal:

```bash
bash tests/check.sh
```

GitHub Actions ejecuta ese mismo comando. Incluye los grupos `fast`,
`integration` y `performance`; el empaquetado Debian y las sesiones interactivas
quedan fuera. El runner detecta pruebas sin clasificar, exige las dependencias,
aísla los datos y conserva registros de cada ejecución.

Para revisar un grupo o consultar el inventario:

```bash
bash tests/check.sh fast
bash tests/check.sh integration
bash tests/check.sh performance
bash tests/check.sh --list
```

Dependencias, límites y cómo incorporar regresiones en [Guía de pruebas](TESTING.md).

## Estructura

```text
KeilaRadioPlayer/
├── .github/workflows/checks.yml
├── keila-radio
├── CHANGELOG.md
├── README.md
├── scripts/
│   └── package-linux.sh
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
    ├── package-linux.sh
    └── update-check.sh
```

Los scripts, listados y documentación de la antigua v1 se mantienen en el historial de Git, pero ya no forman parte del árbol de trabajo actual.

Al salir, Keila detiene/finaliza la grabación si existe, detiene `mpv`, cancela una comprobación de actualización en segundo plano si sigue activa, restaura el estado exacto del terminal y el cursor, abandona la pantalla alternativa de la TUI y limpia la pantalla principal para no dejar restos visuales.

## Política de estabilidad

`2.1.0` reúne el comportamiento validado en la rama `v2.1`, con Linux de escritorio como plataforma principal. Los cambios sobre la línea estable deben priorizar correcciones, compatibilidad y regresiones bien cubiertas por pruebas.
