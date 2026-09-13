# Revisión de rendimiento

Mediciones locales sobre el checkout de trabajo, con sus cambios pendientes
conservados. No se añadieron fuentes ni metadatos al catálogo.

## Resultados

El benchmark de render usa 132 columnas y 40 filas, sin red ni audio y con
salida descartada. Mide tiempo transcurrido, no CPU total de la aplicación.
Son muestras orientativas, sujetas a carga del equipo.

| Operación | Antes | Después |
| --- | ---: | ---: |
| Dibujo completo sin espectro | 35 ms | 34–36 ms |
| Dibujo completo con espectro | 41 ms | 38–40 ms |
| Espectro con niveles repetidos | 4.082 µs | 127–128 µs |
| Espectro con niveles y picos cambiantes | 5.291 µs | 5.122 µs |
| Actualización parcial de metadatos | 1.555 µs | 277–296 µs |
| Filtrar 5.000 emisoras sintéticas | 131.637 µs | 53.496 µs |

El ahorro relevante está en cuadros repetidos, metadatos y búsqueda. El dibujo
completo y los cuadros cambiantes siguen teniendo un coste parecido; no se
atribuye a estas muestras una reducción equivalente de CPU o RAM del equipo.

## Cambios

- Caché acotada del ecualizador: ocho filas, invalidada por ancho, glifos,
  ganancias, selección de banda y estado del editor.
- Caché de filas y cuadro completo del espectro. Se invalida con niveles,
  picos, geometría, caracteres o colores. Los cuadros se siguen emitiendo para
  restaurar la pantalla después de un dibujo completo.
- Celdas gráficas del espectro preparadas una vez por cuadro, en vez de
  reconstruir la misma cadena en cada banda de cada fila.
- Metadatos parciales calculados en el proceso principal: se elimina una
  sustitución de comando de Bash por actualización.
- La búsqueda comprueba una sola vez por filtro la existencia del mapa de
  comentarios, evitando miles de declaraciones y redirecciones repetidas.
- Recientes copia las arrays del historial en bloque, sin recorrerlas en Bash.

Las cachés retienen únicamente el estado actual; no crecen con el número de
cuadros. Añaden unas pocas cadenas en memoria a cambio de menos cálculo.

## Áreas revisadas y límites

El teclado sondea a 20 ms por defecto. El espectro captura a 20 Hz y limita
su presentación mediante un intervalo de 66 ms. No se han reducido estas
frecuencias: afectan a respuesta y fluidez.

El reproductor combina eventos persistentes con snapshots de respaldo, por
defecto a intervalos de un segundo. El JSON sigue validándose con jq y las
operaciones IPC mantienen sus tiempos límite. El filtrado ya normaliza el
catálogo una vez y aplaza el trabajo hasta una pausa breve al escribir.

La captura auxiliar usa parec/ffmpeg/od y un publicador Bash. Su análisis FFT,
la decodificación de mpv y el dibujo del emulador de terminal no se incluyen
en el benchmark. La publicación de niveles sigue usando sustitución atómica
de archivo; eliminarla sin otro transporte podría provocar cuadros parciales.
La persistencia de favoritos e historial conserva sus bloqueos y escrituras
atómicas. No se ha aplicado caché de disco que pueda ocultar cambios externos.

Para cuantificar consumo total y memoria en reproducción real se necesitan
sesiones comparables con la misma emisora, tamaño de terminal y duración;
el proyecto incluye scripts de perfilado para ello. No se afirma una mejora
medida de RAM, consumo de ffmpeg ni autonomía de batería.

## Verificación

Usar `bash tests/render-benchmark.sh` para repetir el benchmark de dibujo.
La búsqueda sintética usa 5.000 nombres y URLs, consulta `prueba`, diez filtros
y un mapa vacío de comentarios; excluye carga del catálogo.

Las pruebas de caché comparan la salida reutilizada con una reconstrucción
forzada al cambiar ancho, Unicode y ganancias. Las pruebas de espectro cubren
coordenadas, silencio, suspensión y tamaño. También se ejecutan pruebas de
metadatos, búsqueda, IPC, reconexión, grabación y persistencia con rutas XDG
temporales. Se corrigió la expectativa de altura del espectro que seguía
utilizando la geometría anterior al espaciado pendiente.
