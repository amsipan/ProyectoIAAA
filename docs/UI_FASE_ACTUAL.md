# UI — producto oficial (paso a paso)

Lista canónica: **`docs/PRODUCTO_OFICIAL.md`**.  
Código viejo aislado: **`docs/LEGACY.md`** + carpeta `legacy/`.

## ⚠️ Restricción de ancho (laptop 14")

La barra de controles inferior debe caber COMPLETA en una laptop de 14"
(resolución típica **1366×768**). En pantallas así, el área útil horizontal es
de aproximadamente **1080 px** (descontando bordes de ventana y márgenes Tk).

- **Corte real observado (2026-07-22)** en la laptop 14" del usuario: en la
  pestaña **ZigZag** (la más ancha) la barra se corta **a la mitad del primer
  botón "Fib Retracement"**. En pantalla se alcanza a leer la etiqueta `Fib:` y
  el inicio del botón `Fib Retracement`; todo lo que sigue a la derecha
  (resto de Fibonacci, "Desde ZZ ext", "Borrar Fib", "Hasta última vela") queda
  fuera de la pantalla.
- Ese punto de corte equivale a **~1080 px** desde el borde izquierdo. Como el
  valor exacto depende del render de fuentes de cada equipo, se adopta un
  **presupuesto de diseño conservador de ~1050 px** (deja margen de seguridad).
- **Ancho máximo de diseño para cualquier fila de la barra: ~1050 px**
  (nunca acercarse al límite duro de ~1080 px).
- Regla de diseño: si una pestaña supera ese ancho, hay que **dividir sus
  herramientas en una pestaña nueva** (ej. separar Canal/Trend/Fib de ZigZag) o
  **compactar etiquetas** (íconos, texto corto), nunca dejar controles fuera del
  borde. Verificar en 1366×768 antes de dar por buena una fila.

### Pestañas actuales (2026-07-22)

`Estructura · Liquidez · ZigZag · Dibujo · Volumen · Vista` (fila 1: selector TF
+ estas 6 pestañas + botón ↻).

- **ZigZag**: solo ZZ interno (+ res 15/30/60) y ZZ externo.
- **Dibujo**: herramientas de trazado — Parallel Channel, TrendLine y Fib
  Retracement (movidas desde ZigZag por el límite de ancho de 14").
- **Volumen**: AVP, AVWAP (±σ1/2/3 + Relleno), Pivots & Fantasmas, DIY.
  ⚠️ Pendiente: esta pestaña también roza el límite; candidata a compactar.

## Activo (oficial)

| Pieza | Notas |
|--------|--------|
| Chart OHLC + TF + Replay + Escala | Base |
| **SMC Pro** | Neon TV |
| **SMC Structures+FVG** | LudoGH |
| **Parallel Channel** | 3 clics TV |
| **HLD (4h/D)** | Video profe |
| **ZigZag externo / interno** | ChartPrime + ZZMTF |
| **Fib Retracement** | Herramienta TV |
| **Liquidity v2** | BSL/SSL/EQH/EQL + Sweep/Grab/Run (PDF FSM) |

## Liquidity — uso

1. Checkbox **Liquidity** en Capas (OFF por defecto; on-demand).
2. Sub-toggles: **BSL SSL EQH EQL SWEEP GRAB RUN**.
3. Spec: `docs/LIQUIDITY_V2.md`. Export de eventos para fase modelos.

## No reactivar sin rediseño

- Liquidity v1 del archive externo — no copiar; ya hay v2 oficial
- Mxwll, Strategy, VP, VWAP, SMC_Structures unificado — archive externo
- Placeholder HTF sobre LTF — eliminado

## Dataset

Base nativa **15m** (`Data/tv_nq1_15m.csv`). 4h/D se agregan desde 15m.

## Fib Retracement — uso

1. **Fib Retracement** → clic 1 (nivel **1**) y clic 2 (nivel **0**), como en TV.
2. **Desde ZZ ext** → modo “elige pierna”: clic en la **línea azul** del ZZ externo que quieras (no elige al azar). Impulso from→to = 1→0 (bajista: 1 arriba, 0 abajo).
3. Arrastrar handles **azules** (p1/p2): mueven precio **e** índice; la caja y las etiquetas se mueven con ellos (sin handles de ancho sueltos).
4. **Hasta última vela** → proyecta la caja solo hasta la última vela del dataset.
5. **Desde ZZ ext** también marca el checkbox **ZigZag externo** en Capas.
6. **Borrar Fib** / Esc cancela el modo.

## HLD — recordatorio

- Video ~40:00–46:30; sin indicador TV.
- Elige vela pasada (rango que contiene el precio, o OHLC más cercano).
- Dibuja high=resistencia, low=soporte hasta la última vela.
- ATH → no dibuja (usar VWAP en fase posterior).
