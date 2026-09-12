# Comprobaciones de Keila

## Un único comando, en local y en GitHub

Desde la raíz del repositorio:

```bash
bash tests/check.sh
```

Ejecuta las pruebas automatizadas con datos locales, sin necesitar una emisora
real, instalar dependencias ni iniciar una escucha interactiva. GitHub Actions
llama al mismo comando; no mantiene otra lista de scripts.

Cada script dispone de sus propias rutas XDG y directorio temporal. Los tests de
datos usan información ficticia; los fallos de disco se simulan sin llenar el
almacenamiento. No se cambia la configuración personal del reproductor. Las
pruebas del terminal usan un pseudoterminal y las de audio una señal sintética
o dobles de prueba, no los altavoces del usuario.

El runner necesita Bash 5, las utilidades habituales de GNU/Linux o Termux
(incluido `timeout`), `jq`, Python 3 y ShellCheck. Integración necesita además
`ffmpeg`, `ffprobe`, `script` y `setsid`. La falta de una dependencia requerida
es un error, no una prueba aprobada por omisión. El reproductor no necesita
ShellCheck: es una dependencia exclusiva de desarrollo.

## Grupos

```bash
bash tests/check.sh fast
bash tests/check.sh integration
bash tests/check.sh performance
bash tests/check.sh --list
```

- `fast`: sintaxis y ShellCheck, lógica, navegación, layouts, metadatos,
  preferencias, sesiones y regresiones de interfaz. No inicia una radio real.
- `integration`: recuperación, fallos de escritura, cierres forzados,
  concurrencia, arranque del catálogo, procesos, terminal, audio sintético y
  archivo distribuible Linux. El perfilador se ejecuta solo con `--self-test`.
- `performance`: búsqueda con 50.000 emisoras sintéticas y tiempos de render.
  La búsqueda comprueba su presupuesto existente de 1.500 ms; el benchmark de
  render informa medidas, no impone un límite de CPU, memoria o batería.
- `packaging`: comprobación optativa del empaquetado Debian existente, fuera
  de `all` y de CI. No implica retomar el desarrollo del paquete.
- `manual`: inventario de herramientas para sesiones reales. `--list` las
  muestra, pero el runner nunca las ejecuta interactivamente.

Sin argumentos, `all` ejecuta `fast`, `integration` y `performance` de forma
secuencial. Medir rendimiento en una máquina sobrecargada puede dar resultados
distintos: repetir aisladamente y revisar el tiempo antes de cambiar el umbral.
Las pruebas individuales siguen siendo ejecutables con `bash tests/nombre.sh`.
`tests/run.sh` conserva sus comprobaciones básicas, pero no es la batería completa.

## Resultados y fallos

Cada prueba tiene un límite de 180 segundos. Si falla o excede ese límite, el
runner informa del error, continúa con las restantes y termina con código no
cero. No confunde el tiempo agotado con una prueba aprobada.

Al terminar muestra un resumen y la carpeta temporal de registros. Cada
`nombre/output.log` contiene la salida completa de ese script. Los registros y
datos ficticios se conservan para poder investigar el fallo; no contienen una
copia de los datos personales. Se pueden retirar después de la revisión.

En un dispositivo especialmente lento se puede ampliar el límite por script:

```bash
KEILA_TEST_TIMEOUT=300 bash tests/check.sh
```

Esto no cambia los presupuestos internos de rendimiento. La batería no reclama
durabilidad ante pérdida eléctrica ni sustituye pruebas de Android suspendido,
cierres desde el sistema o sesiones largas con emisoras reales. La lista de
comprobaciones de datos en Termux está en [DATA-SAFETY.md](DATA-SAFETY.md).

## Incorporar una regresión

1. Crear el script en `tests/`, con datos ficticios y limpieza de sus procesos.
2. Clasificarlo en `tests/suites.txt` con grupo, nombre y argumento opcional.
3. Ejecutar su grupo y, antes de publicar, `bash tests/check.sh`.

El runner detecta ejecutables `.sh` o `.py` sin clasificar, entradas duplicadas,
rutas inválidas y archivos desaparecidos. No se debe excluir una prueba para
ocultar un fallo. Los helpers compartidos deben vivir en un subdirectorio,
no camuflarse como tests aprobados.

Sintaxis y ShellCheck recorren todos los módulos, scripts y tests Bash de primer
nivel. ShellCheck analiza cada archivo por separado para evitar expandir el
launcher entero repetidamente. En tests se ignora el aviso de funciones sin
llamadas visibles (`SC2317`): los dobles se invocan desde los módulos probados.
Esa excepción no se aplica a los archivos de producción.
