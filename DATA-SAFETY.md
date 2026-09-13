# Protección de datos y grabaciones

## Garantías comprobadas

- La parada final de una grabación es optativa, de sesión y confirmada con el
  horario. Solo se ejecuta tras cerrar su archivo y comprobar de nuevo la ruta,
  URL y proceso; no detiene otra escucha ni se activa por una cancelación manual.
  Conserva archivos dudosos, cancela reintentos y respeta alarmas futuras. El
  silencio y volumen de salida no se aplican a la copia del stream: se verifica
  con audio sintético a volumen cero/silenciado y medición del archivo resultante.
- La grabación programada es una reserva en memoria con confirmación de fecha,
  emisora y final. No modifica favoritas ni instala tareas del sistema. Usa la
  reserva exclusiva y los marcadores del grabador habitual; no crea el archivo
  hasta que el reproductor confirma audio. Solo cierra el archivo ligado a su
  ruta, URL y proceso, nunca una grabación posterior o manual. Un cierre atascado
  reintenta a cadencia limitada; después de cinco segundos puede cerrar su mpv
  y verificar de nuevo. Solo declara finalizada una grabación verificada; los
  archivos dudosos y sus marcadores se conservan. Una salida inesperada de mpv
  se avisa como posible grabación incompleta, aunque su audio sea reproducible.
  No garantiza grabar mientras
  el sistema está suspendido: omite inicios con más de 60 segundos de retraso.
- M3U se prepara desde una instantánea privada y acotada (256 KiB, 2000 entradas),
  sin seguir enlaces ni abrir FIFO y sin interpretar comandos o etiquetas como
  código. La confirmación importa esa vista previa, no una fuente modificada
  después. Se releen las favoritas bajo bloqueo antes de fusionar URL nuevas:
  no se reemplazan nombres, orden ni comentarios. Una única publicación y su
  copia .bak protegen el conjunto; un fallo restaura también los arrays en memoria.
- La exportación M3U usa un temporal hermano y rename sin reemplazo; una colisión
  se rechaza también al publicar. No incluye comentarios ni ajustes. Las URL
  pueden contener tokens privados: el usuario debe revisarlas antes de compartir.
- El temporizador consume su plazo una sola vez, desactiva reintentos y evita
  que cerrar la escucha de una grabación reanude la radio. Solicita primero el
  cierre de la grabación; si mpv aún escribe, lo cierra y vuelve a verificar.
  Los archivos dudosos se conservan con aviso. No borra audio ni datos personales.
- El alta manual reutiliza la escritura bloqueada y atómica de Favoritas y sus
  copias de seguridad. No sustituye otra emisora con la misma URL ni publica en
  Radio Browser. Guardar no reproduce; la prueba de escucha es una acción explícita
  que puede generar entradas normales en Recientes y el registro de sesión.
- Los filtros son estado de sesión: no escriben en favoritas ni en preferencias.
  El índice antiguo sigue disponible durante su migración local de región/temática.
- Favoritos, comentarios, estado, preferencias, recientes y ecualizador se
  publican mediante sustitución de un temporal en el mismo directorio. Un fallo de escritura o publicación no
  sustituye el original por un resultado parcial.
- Estado, favoritos, preferencias, recientes y ecualizador utilizan temporales
  exclusivos y privados.
  Los comentarios ya usaban este mecanismo. La creación inicial de favoritos
  también es atómica; la configuración inicial no reemplaza un archivo existente.
- Preferencias y ecualizador se guardan bajo bloqueo. Dos sesiones guardan documentos
  completos: prevalece el último guardado, no se fusionan opciones entre sesiones.
- Cada nombre de grabación se reserva mediante creación exclusiva antes de
  enviarlo a mpv. Las colisiones, incluidos enlaces simbólicos rotos, generan
  otro nombre. No se reutilizan archivos vacíos de intentos anteriores.
- Junto al audio nuevo se crea `nombre.ext.pending`. Solo se retira cuando el
  cierre es confirmado y la comprobación de reproducción tiene éxito. Si queda
  tras un fallo o cierre forzado, el audio puede estar incompleto o no verificado.
  No se elimina automáticamente ese audio, aunque esté vacío.
- Cada sesión interactiva crea un registro de escucha en
  `$XDG_STATE_HOME/keila-radio/sessions/` con permisos privados. Se escribe en
  modo append, como texto legible, y no participa en los archivos estructurados
  que se restauran automáticamente desde `.bak`.

## Copia anterior y recuperación

Favoritos (`favorites`), comentarios (`labels`), volumen/última emisora (`state`),
preferencias del selector (`preferences`), recientes (`history`) y ecualizador
(`equalizer`) conservan una copia privada `.bak`
en el mismo directorio. Es una sola versión anterior, no un historial ilimitado.
El primer guardado de un archivo nuevo crea también su respaldo. Un guardado
idéntico no hace avanzar una copia válida, evitando perderla por guardados
repetidos al salir. Si no se puede preparar la copia, el guardado falla.

La configuración manual (`config`) también tiene copia privada `.bak`, con una
semántica distinta: conserva el contenido de la última carga válida, porque las
ediciones se hacen fuera del programa. Al cargar una edición válida se actualiza
su copia sin reescribir el original: comentarios, espacios, CRLF y claves
desconocidas se conservan. Los valores conocidos fuera de rango siguen usando
los valores por defecto; no se ejecutan expresiones ni comandos del archivo.
Si no se puede respaldar la edición, la carga falla y conserva ambos archivos.
Para volver a los valores por defecto, editar los valores o retirar el archivo
**y su copia**; retirar solo `config` activa la recuperación, no un reinicio.

Al arrancar se valida la estructura de estos siete archivos. Si uno falta o
está malformado y su copia es válida, se restaura automáticamente. Antes de
reemplazar un archivo dañado se conserva íntegro en `nombre.corrupt.XXXXXX`,
con permisos privados. Se imprime su ruta y se muestra un aviso en el reproductor.
La copia puede ser anterior a la última edición: conviene revisar los datos.

Si tampoco hay copia válida, Keila detiene el arranque con un mensaje y no
reescribe ninguno de los archivos. Una corrupción detectada al guardar durante
la sesión bloquea esa escritura; no se mezcla información parcial con la copia.
Los enlaces simbólicos y rutas no regulares no se restauran automáticamente.

Las instalaciones anteriores reciben una copia de los archivos válidos que aún
no tengan respaldo, sin cambiar su contenido. Los archivos opcionales ausentes
no se inventan. Los recientes conservan su orden, deduplicación y límite de 20;
el ecualizador se valida completo, no solamente su primera línea.

La validación es estructural, no una prueba absoluta de integridad: una lista
vacía es válida, y un cambio o truncado que siga formando registros válidos puede
pasar inadvertido. También es válida una configuración vacía o solo comentada,
por su carácter opcional. Tampoco protege contra pérdida de todo el directorio:
para eso hace falta una copia externa.

## Fallos de guardado durante el uso

- Recientes no incorpora una emisora a la lista si no puede publicar el archivo.
  Una corrupción detectada durante la sesión bloquea la escritura, no se elimina
  silenciosamente al volver a guardar.
- Bandas, centrado, perfil plano y presets del ecualizador comparten la misma
  reversión: si mpv rechaza el cambio o falla el guardado, se conserva el ajuste
  anterior en memoria y se intenta reaplicarlo al audio. Si tampoco se puede
  confirmar ese segundo comando, el aviso lo indica y recomienda reabrir la
  emisora. Audio y disco no forman una transacción conjunta.
- El espectrograma guarda la preferencia antes de cambiar la visualización. Si
  falla, no inicia ni detiene la captura. Las otras preferencias y atajos también
  conservan sus valores anteriores ante un error de guardado.
- Un fallo al guardar volumen o última emisora se comunica. La reproducción
  puede continuar con su volumen actual, sin presentarlo como persistido.

## Copias exportables

`./keila-radio --backup [archivo.tar.gz]` crea una copia privada de los datos
personales pequeños: configuración, favoritos, comentarios, preferencias,
volumen/última emisora, historial y ecualizador. No incluye grabaciones, cachés
ni el catálogo de Radio Browser. Los registros de sesión con canciones y marcas
de tiempo tampoco se exportan por defecto, por privacidad y para evitar copias
crecientes sin límite.

La TUI ofrece las mismas copias en `O` → `A` (Datos y almacenamiento): `C` crea
y `R` abre el gestor. Las nuevas copias se guardan en
`$XDG_STATE_HOME/keila-radio/backups`, con directorio privado y archivos `600`.
La lista solo inspecciona esa carpeta, los respaldos previos de configuración
y las copias antiguas con nombre `keila-backup-*` junto al programa. Importar
consiste en colocar un `.tar.gz` en la carpeta de copias y actualizar la lista.

Crear una copia ya no inicializa la aplicación ni recarga ajustes en memoria.
Se toma una instantánea bajo los bloqueos de los siete archivos. La compresión
se hace en un temporal y se publica de forma exclusiva: un archivo existente,
incluido un enlace roto o una colisión durante la compresión, nunca se sustituye.
Si algo falla, no se borra una copia creada por otra sesión.

`./keila-radio --restore archivo.tar.gz` valida la lista de rutas del archivo y
el formato de cada dato soportado antes de restaurar. Si la copia es válida,
crea primero un respaldo del estado actual en
`~/.config/keila-radio/pre-restore-*.tar.gz`. Una copia con rutas inesperadas,
enlaces simbólicos o datos malformados se rechaza sin modificar los datos
actuales.

Antes de extraer se comprueban rutas, tipos y tamaños: solo se admiten los
miembros conocidos, sin duplicados, enlaces simbólicos o duros, dispositivos
ni rutas de escape. Máximos: 8 MiB comprimidos, 4 MiB por archivo y 16 MiB de
datos en total; las consultas de TAR y su extracción tienen tiempo limitado.
Estas copias son para datos personales pequeños, no para audio ni archivos
arbitrarios. Una instantánea privada impide cambiar los bytes entre validación
y publicación. El formato sigue siendo `keila-backup-v1`.

En la interfaz, seleccionar o consultar detalles no restaura. `R` verifica en
segundo plano y muestra el contenido antes de la confirmación con `Enter`.
Cambiar o retirar el archivo original invalida esa confirmación. Cancelar o
salir antes de confirmar descarta únicamente los temporales, no la copia.
Los datos actuales deben poder leerse y respaldarse; si no, se rechaza restaurar.

Cada archivo restaurado se publica con bloqueo, temporal privado y copia
anterior, igual que en un guardado normal. La restauración de **todo el conjunto**
no es una única transacción: una interrupción puede dejar algunos archivos
restaurados y otros anteriores. Se conserva el respaldo previo completo.

La TUI difiere sus escrituras automáticas mientras el trabajo mantiene los
bloqueos, para no bloquear el teclado ni sobrescribir los datos restaurados.
La escucha actual, silencio, volumen y alarma se conservan. Los datos y ajustes
visuales se recargan; el ecualizador se reaplica. Si algún ajuste no puede
aplicarse, se informa y se recomienda reiniciar. La carpeta de grabaciones y
el estado de inicio importados se usan en el siguiente arranque.

El trabajador de copias usa un grupo de procesos propio y se limpia al salir.
Una restauración confirmada no se cancela con `Esc` durante la publicación;
un cierre forzado sigue teniendo los límites de interrupción indicados arriba.
No se aplica retención automática ni borrado definitivo de copias.

## Pruebas reproducibles

`bash tests/data-protection.sh` trabaja con rutas XDG temporales y datos ficticios:
errores de escritura y publicación, SIGKILL justo antes de publicar, recuperación
de bloqueos del escritor muerto, lectura en una nueva sesión y doce reservas
simultáneas de grabación con la misma emisora y segundo.

`bash tests/recording-validation.sh` comprueba archivos vacíos, reproducción no
verificable y permanencia del marcador cuando el cierre no está confirmado.
Los fallos de escritura son inyectados; no se llena el disco del usuario.

`bash tests/data-recovery.sh` comprueba restauración, conservación exacta del
archivo dañado, permisos privados, copia también dañada, fallo de restauración,
archivo ausente y lectura de los datos recuperados.

`bash tests/backup-restore.sh` comprueba exportación, exclusión de grabaciones y
caché, restauración validada, respaldo previo automático y rechazo de una copia
malformada.

`tests/backup-archive.sh`, `tests/backup-manager.sh` y `tests/backup-menu.sh`
cubren colisiones, instantáneas, archivos maliciosos, respaldo previo obligatorio,
trabajos reales en segundo plano, confirmación/cancelación, cambios de archivo,
conservación del audio y entrada desde Opciones. Los layouts del gestor y su
confirmación se comprueban en 13 tamaños y en ASCII/Unicode.

`bash tests/session-log.sh` comprueba creación privada del registro de sesión,
saneado de texto, deduplicación de títulos, reinicio visual al cambiar de
emisora y cierre del archivo.

`bash tests/persistence-extended.sh` comprueba migración de archivos antiguos,
conservación de configuración manual, formatos completos, fallos en la publicación
final, reversión del audio, avisos de persistencia, cierres forzados durante la
escritura y recuperación de los tres formatos nuevos en el arranque completo.

Todas estas regresiones se ejecutan con `bash tests/check.sh`, también en GitHub.
Ver [Guía de pruebas](TESTING.md) para grupos, dependencias y registros de fallos.

## Límites y trabajo pendiente

### Renombrado y recuperación de la papelera

Las operaciones requieren confirmar el origen y el destino y vuelven a comprobar
la firma del audio y su marcador antes de moverlos. No afectan a grabaciones,
verificaciones o escuchas activas de ese archivo. Se rechazan enlaces simbólicos,
rutas fuera de la carpeta prevista y nombres no válidos. La papelera solo recorre
contenedores `recording.*` directos; no sigue enlaces ni ejecuta metadatos.

Un bloqueo breve serializa estas operaciones entre sesiones cooperantes. Antes
de mover el audio se reserva un marcador privado en el destino mediante creación
exclusiva, conservando aún el original. Después se mueve el audio sin reemplazar
destinos existentes y se comprueba el resultado: que `mv -n` termine con éxito
no basta para dar por hecho que se trasladó. La operación rechaza distintos
dispositivos para evitar una copia costosa de audio. No requiere enlaces duros,
que no están disponibles en algunos almacenamientos compartidos de Android.

Audio y marcador **no son una transacción única**. Un cierre entre pasos puede
dejar un marcador en el destino todavía vacío, o el audio y su marcador en el
destino con el marcador anterior sobrante. Se conservan esos restos y se avisa
de los errores detectados; no se intenta un rollback que pudiera sobrescribir
otro archivo. Una grabación nueva evita también nombres cuyo `.pending` existe.
No hay garantía frente a modificaciones simultáneas por programas que ignoren
estas reservas y bloqueos, ni frente a pérdida eléctrica del almacenamiento.

Recuperar no sobrescribe el nombre original ocupado: se propone un nombre
alternativo antes de confirmar. Tampoco cambia automáticamente ese destino si
aparece una colisión después de confirmarlo. No se elimina audio definitivamente;
solo se retiran contenedores vacíos mediante `rmdir`, conservando cualquier otro
archivo del contenedor. Los nombres demasiado largos se acortan en la propuesta
alternativa sin cambiar la extensión.

`tests/recording-files.sh` simula colisiones, errores, marcadores sobrantes y
SIGKILL a ambos lados del traslado; `tests/recording-file-menu.sh` comprueba
confirmación, cancelación, refresco, resize y separación entre biblioteca y
papelera. Todos los datos usados son ficticios y temporales.

### Escucha y límites generales

La biblioteca de grabaciones no decodifica los archivos durante el escaneo ni
considera la ausencia de `.pending` una verificación del audio. Un marcador que
sea enlace, directorio o FIFO bloquea las operaciones; nunca se lee como texto.
La advertencia Dudosa de una comprobación fallida se conserva durante la sesión
mientras el archivo no cambie. El audio y el marcador se mantienen para revisarlos.

Escuchar utiliza un mpv con configuración desactivada, socket en directorio
privado y grupo de procesos propio. No escribe posiciones de reanudación ni
modifica los archivos, sus marcadores o historiales. Al cerrar se limpia solo
ese reproductor y se retoma la radio únicamente si esta escucha la pausó y no
ha cambiado. Una alarma tiene prioridad. Las pruebas cubren fin de archivo,
errores, pausa previa, IPC rechazado, timeout y saltos reales con audio sintético.

- Esto no demuestra durabilidad ante pérdida eléctrica: no hay sincronización
  explícita de archivos y directorios a almacenamiento físico.
- La copia anterior y la recuperación cubren únicamente los siete archivos
  indicados y sus errores estructurales detectables, no cualquier corrupción.
- Los registros de sesión son append-only: no tienen `.bak`, no se validan al
  arrancar y pueden truncarse si el sistema se apaga justo durante la escritura.
  Una línea dañada no impide arrancar porque Keila no necesita releerlos.
- Un marcador pendiente no certifica daño ni recuperabilidad. El gestor (`;`)
  comprueba un fragmento de audio, no la integridad completa de toda la grabación.
  Su eliminación mueve audio y marcador a `.trash` con confirmación. Los dos
  movimientos no son una transacción: si falla el segundo, el audio ya movido
  se conserva y se comunica el error. No hay vaciado automático de la papelera.
- La reserva evita carreras entre instancias cooperantes de Keila, no ataques
  de otro proceso que pueda borrar o reemplazar archivos del mismo usuario.
- Suspensión y cierre de Android, almacenamiento compartido y apagado físico
  requieren pruebas reales en Termux. No se borran automáticamente temporales
  dejados por SIGKILL, pues pueden ayudar a recuperar información.

## Validación manual pendiente en Termux

Usar un perfil de prueba separado mediante `XDG_CONFIG_HOME`, `XDG_STATE_HOME`
y `XDG_CACHE_HOME`, y una carpeta de grabaciones de prueba. No utilizar los datos
personales reales ni llenar el almacenamiento del teléfono para estas pruebas.

1. Crear favoritos y comentarios ficticios, cambiar preferencias y volumen;
   cerrar normalmente, abrir de nuevo y comprobar la persistencia.
2. Repetir tras enviar Termux al fondo y reanudar, y tras forzar su detención
   desde Android. Comprobar tanto los datos como los avisos de recuperación.
3. Interrumpir una grabación de prueba, comprobar que audio y `.pending`
   permanecen y que una grabación posterior no reutiliza su nombre.
4. Registrar Android/Termux, ubicación del almacenamiento y resultado. Un cierre
   forzado no equivale a un apagado físico; no se afirma durabilidad eléctrica.
5. Escuchar una grabación de prueba, pausar, saltar y volver: comprobar que se
   retoma la radio anterior. Repetir con la radio ya pausada y con una alarma;
   no debe reanudarse una pausa previa ni sustituirse la emisora de la alarma.
6. Recorrer la biblioteca a 40 y 62 columnas, abrir detalles y actualizar la
   lista. Comprobar que conserva el archivo seleccionado y no desplaza columnas.
7. Renombrar un audio de prueba, cancelar primero y confirmar después; comprobar
   extensión y contenido. Moverlo a papelera, crear otro con el mismo nombre y
   recuperarlo: debe proponer otro destino y conservar ambos archivos.
