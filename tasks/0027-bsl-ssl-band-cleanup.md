# Task 0027: BSL/SSL más limpio — agrupar en banda (tarea E)

## Origen
- ORDEN 15 de `tasks/0021-volatility-and-choch-noise.md` (= tarea E original).
- Notas WhatsApp profe (29/06): "BSL y SSL debe ser más limpio para tener una
  banda"; "están mostrándose muchos BSL".

## Objetivo
Reducir la densidad de líneas BSL/SSL (Buy/Sell Side Liquidity) y presentarlas
como una BANDA (zona) más limpia en vez de muchas líneas horizontales sueltas.

## Estado verificado (02/07)
- `Market/Indicators/Liquidity.pm`: BSL = swing high, SSL = swing low. Cada swing
  genera un nivel → en 1m hay cientos de líneas BSL/SSL, de ahí el "muchos BSL".
- `Market/Overlays/Liquidity.pm`: dibuja cada nivel como línea horizontal punteada
  (`_draw_hline_label`) individual. No hay agrupación en banda.

## Diseño (a decidir con usuario)
Dos enfoques posibles:
1. **Banda por proximidad**: agrupar niveles BSL (o SSL) cercanos en precio (dentro
   de X*ATR) en una única zona sombreada (rectángulo tenue) que abarque el rango
   de esos niveles. Menos líneas, más limpio.
2. **Solo niveles vigentes/relevantes**: mostrar solo los BSL/SSL no barridos y
   más recientes/relevantes (reusar criterio de relevancia de ORDEN 4), reduciendo
   el número de líneas.
- Se pueden combinar: banda de los niveles vigentes cercanos al precio.
- Mantener toggles BSL/SSL existentes.

## Criterios de aceptación
- La vista de BSL/SSL es notablemente más limpia (menos líneas o banda agrupada).
- Sigue siendo posible ver dónde está la liquidez compradora/vendedora.
- Toggles BSL/SSL funcionan.
- Suite `prove -l t` verde con test del agrupamiento/banda.

## Pendiente de confirmar con el profe/usuario
- ¿Banda sombreada (enfoque 1) o solo filtrar niveles (enfoque 2)?
- ¿Cuántos niveles/qué proximidad define una banda?

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/Overlays/Liquidity.pm && prove -l t/10-liquidity.t t/15-overlay-liquidity-render.t"
```

## Qué no tocar
- No romper la vinculación toma→nivel (ORDEN 3) ni los toggles.
