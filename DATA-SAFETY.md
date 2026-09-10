# Protección de datos y grabaciones

## Garantías comprobadas

- Favoritos, comentarios, estado y preferencias se publican mediante sustitución
  de un temporal en el mismo directorio. Un fallo de escritura o publicación no
  sustituye el original por un resultado parcial.
- Estado, favoritos y preferencias utilizan temporales exclusivos y privados.
  Los comentarios ya usaban este mecanismo. La creación inicial de favoritos
  también es atómica; la configuración inicial no reemplaza un archivo existente.
- Las preferencias se guardan bajo bloqueo. Dos sesiones guardan documentos
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

Favoritos (`favorites`), comentarios (`labels`), volumen/última emisora (`state`)
y preferencias del selector (`preferences`) conservan una copia privada `.bak`
en el mismo directorio. Es una sola versión anterior, no un historial ilimitado.
El primer guardado de un archivo nuevo crea también su respaldo. Un guardado
idéntico no hace avanzar una copia válida, evitando perderla por guardados
repetidos al salir. Si no se puede preparar la copia, el guardado falla.

Al arrancar se valida la estructura de estos cuatro archivos. Si uno falta o
está malformado y su copia es válida, se restaura automáticamente. Antes de
reemplazar un archivo dañado se conserva íntegro en `nombre.corrupt.XXXXXX`,
con permisos privados. Se imprime su ruta y se muestra un aviso en el reproductor.
La copia puede ser anterior a la última edición: conviene revisar los datos.

Si tampoco hay copia válida, Keila detiene el arranque con un mensaje y no
reescribe ninguno de los archivos. Una corrupción detectada al guardar durante
la sesión bloquea esa escritura; no se mezcla información parcial con la copia.
Los enlaces simbólicos y rutas no regulares no se restauran automáticamente.

La validación es estructural, no una prueba absoluta de integridad: una lista
vacía es válida, y un cambio o truncado que siga formando registros válidos puede
pasar inadvertido. La recuperación automática `.bak` no cubre todavía el
historial, el archivo manual `config` ni los ajustes persistentes del
ecualizador. Tampoco protege contra pérdida de todo el directorio: para eso hace
falta una copia externa.

## Copias exportables

`./keila-radio --backup [archivo.tar.gz]` crea una copia privada de los datos
personales pequeños: configuración, favoritos, comentarios, preferencias,
volumen/última emisora, historial y ecualizador. No incluye grabaciones, cachés
ni el catálogo de Radio Browser. Los registros de sesión con canciones y marcas
de tiempo tampoco se exportan por defecto, por privacidad y para evitar copias
crecientes sin límite.

`./keila-radio --restore archivo.tar.gz` valida la lista de rutas del archivo y
el formato de cada dato soportado antes de restaurar. Si la copia es válida,
crea primero un respaldo del estado actual en
`~/.config/keila-radio/pre-restore-*.tar.gz`. Una copia con rutas inesperadas,
enlaces simbólicos o datos malformados se rechaza sin modificar los datos
actuales.

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

`bash tests/session-log.sh` comprueba creación privada del registro de sesión,
saneado de texto, deduplicación de títulos, reinicio visual al cambiar de
emisora y cierre del archivo.

## Límites y trabajo pendiente

- Esto no demuestra durabilidad ante pérdida eléctrica: no hay sincronización
  explícita de archivos y directorios a almacenamiento físico.
- La copia anterior y la recuperación cubren únicamente los cuatro archivos
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
