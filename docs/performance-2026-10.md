# Revisión de recursos — 4 de octubre de 2026

Cambios posteriores a 2.2.0. Prioridad: reducir trabajo recurrente sin
recortar funciones, calidad de audio, búferes de red ni persistencia.

## Hallazgos y cambios

1. El teclado despertaba el mantenimiento cada 20 ms aunque no hubiese gráfico
   que animar. Ahora usa 200 ms en reposo; una tecla interrumpe `read` inmediatamente.
   Espectrograma visible y búsqueda/calidad/logo pendientes conservan 20 ms.
   Los intervalos ajustados por el usuario siguen teniendo prioridad.
2. Los relojes de progreso y reconexión usaban sustitución de comandos: un
   proceso Bash auxiliar por consulta, incluso para obtener `EPOCHSECONDS`.
   La ruta frecuente publica el valor directamente; la API de texto se conserva.
3. El listener IPC analizaba cada mensaje por separado, incluidos los ACKs.
   Un parser procesa la ráfaga disponible, sin observar relojes de audio de alta
   frecuencia. Mantiene el límite por tick, fragmentos y recuperación por línea
   solo si un JSON malformado invalida la ráfaga.
4. El analizador podía seguir capturando/FFT detrás de los menús o después de
   morir mpv. Se detiene cuando queda oculto y vuelve al salir, conservando la
   preferencia. También se cierra si ya no queda reproductor. FFmpeg usa un
   hilo por decoder/filtro/encoder para la salida mono de 17×16 píxeles.

No se cambia el límite de resultados ni se carga todo el catálogo en arrays:
la búsqueda ya usa TSV y un conjunto acotado de resultados. Tampoco se reducen
los búferes de mpv: perjudicar conexiones inestables no sería una optimización
segura sin pruebas reales de red.

## Medición reproducible de mantenimiento

```bash
python3 tests/runtime-performance.py --duration 10 --output /tmp/keila-runtime.json
```

Cuatro sesiones independientes. Bucle de teclado, parser de snapshot,
reconexión y mantenimiento reales; fuente/terminal simulados y sin catálogo,
red, altavoces ni perfiles personales. La animación usa un frame sintético,
no un FFT ni el audio de mpv. Incluye arranque y cierre.

Referencia local, Bash 5.2.37 / FFmpeg 7.1.5, diez segundos solicitados por caso:

| Escenario | CPU antes | CPU después | Ticks/s antes → después |
|---|---:|---:|---:|
| Detenido | 13,48% | 2,17% | 42,61 → 4,85 |
| Escucha sin espectrograma | 20,04% | 2,72% | 39,32 → 4,77 |
| Menú sin animación | 20,08% | 2,87% | 39,11 → 4,81 |
| Lector de espectrograma | 22,05% | 10,27% | 38,09 → 44,16 |

100% significa un núcleo. Son medidas de esta máquina, no presupuestos que
deban cumplir otros equipos. La segunda medida se hizo tras introducir reposo
adaptativo y relojes directos; no atribuye mejoras adicionales al agrupado de
eventos ni al límite de hilos. El caso de menú parte del espectro desactivado:
no cuantifica el ahorro extra al cerrar una captura que antes estaba oculta.

La RAM estable del mantenimiento cambió poco: RSS media de escucha de 14,01
a 13,41 MiB y con animación de 15,26 a 15,28 MiB. Los picos muestreados no son
una prueba de ahorro: pueden coincidir con forks y contar páginas compartidas
dos veces. Menos subprocesos y cerrar capturas ocultas evita trabajo y memoria
auxiliar, sin afirmar una gran reducción de la RAM residente del launcher.

Una comprobación separada de FFmpeg con seno mono, filtro 17×16 y salida nula
durante seis segundos dio RSS media aproximada de 49,2 a 47,8 MiB al acotar
hilos. Es una mejora pequeña y orientativa, no una medición completa del monitor
PulseAudio/PipeWire. Las pruebas de audio continuo comprueban que siguen llegando
frames antes de EOF con los argumentos nuevos.

## Verificación y límites

Batería inicial local: **101 correctas, 0 fallidas** (206 s). Se comprobó además el
self-test actualizado del medidor de recursos y las nuevas regresiones de
reposo/eventos con jq 1.6. No se ha ejecutado una sesión prolongada en Android
para estas optimizaciones. La integración posterior añade pruebas de cambio
de calidad provisional y de bienvenida/salida: **104 correctas, 0 fallidas**.

- Regresiones de teclado, Unicode, ráfagas, Supr y suspensión bajo PTY.
- Reposo, tareas pendientes, intervalos explícitos, resize y teclas sin esperar
  200 ms. Transiciones de captura oculta y limpieza sin mpv.
- Parser único por ráfaga válida, ACKs, límite, fragmentación y JSON malformado.
- Pruebas de reconexión/progreso, metadatos, alarma, programación y grabación
  permanecen en la batería completa: `bash tests/check.sh`.

CPU muestreada/cumulativa y RSS no son una medida de batería. Para comprobar
autonomía real hay que comparar sesiones prolongadas en los mismos teléfonos,
con igual emisora, red, volumen, brillo y estado visual. Tampoco se cuentan aquí
los recursos del emulador ni del servidor de audio compartido.

Para medir escucha real en Linux se mantiene `tests/resource-profile.py`;
su modo `--spectrum on/off` se aplica después de leer la configuración, sin
persistirlo ni cambiar la preferencia guardada. La regresión comprueba ambos
valores persistentes y conserva errores de inicialización.
Véase la [guía de pruebas](../TESTING.md) y las instrucciones del [README](../README.md).
