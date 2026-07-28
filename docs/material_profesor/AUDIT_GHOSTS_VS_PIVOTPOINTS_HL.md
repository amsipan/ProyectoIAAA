# Audit: Ghosts_in_swings (Pine) vs PivotPointsHL (Perl)

**Fecha:** 2026-07-27  
**Veredicto:** **ALINEADO_PARCIAL**  
**Alcance:** solo fantasma provisional + rastro `"1"` + pivotes/missed/confirmación/Replay (no AVWAP del mismo `.txt`).  
**Decisión pedida al auditor Paso 1:** ¿OK para labels ML o hay que ajustar X antes del extractor?

---

## Fuentes contrastadas

| Rol | Path |
|---|---|
| Referencia DOCX (aula) | `docs/material_aula_virtual/08_unidad5_no_supervisado/Proyecto/Capturas-de-pantallas-configuracion-indicadores/Ghosts_in_swings.txt` |
| Copia canónica repo | `docs/reference_indicators/ghosts_in_swings_josafa.txt` |
| Implementación | `Market/Indicators/PivotPointsHL.pm` |
| Render | `Market/Overlays/PivotPointsHL.pm` |
| Feed / Replay | `Market/ChartEngine.pm` (`_feed_indicator_to`, rewind `reset`) |
| Tests | `t/42-pivot-points-hl.t` (§ fantasma se mueve, rastro, reset+refeed) |

Las dos copias del `.txt` son **idénticas byte a byte** (SHA-256 `1B5D7931…CCA8`, 22007 bytes).

El script Pine es el indicador Josafa *Dynamic Swing Anchored VWAP* (v6): motor LuxAlgo de pivotes + bloque `barstate.islast` del fantasmita/rastro + AVWAP. Este audit **no** exige paridad del AVWAP embebido (en la app vive aparte).

---

## Resumen ejecutivo

El núcleo **pivote regular / missed-ghost / zigzag / os / max·min·follow** es un port fiel y **causal** (apto Replay).  
El **fantasmita provisional** y el **rastro `"1"`** — precisamente lo que dispara muestras y labels LSTM — **no son idénticos** al literal del `.txt`, aunque el Perl se acerca más al *comentario* Josafa (“solo cuando el fantasma cambia de lugar”) que al código Pine tal cual.

**Recomendación:** **no OK para labels “idénticos TV” sin decisión previa.**  
Ajustar (o congelar por contrato) **antes del extractor**:

1. Regla canónica del rastro (literal Pine vs “solo si se mueve”).  
2. Ventana de búsqueda del provisional (`px1` inclusive vs exclusivo) + desempate de extremos.  
3. (Opcional / menor) orden serie `max_x1`/`min_x1` en barras donde hay pivot + update de tracking.

---

## Coincidencias (OK)

1. **Pivot length default 50**; confirmación simétrica `length` izquierda/derecha ≡ `ta.pivothigh/low(length,length)`.
2. **Estado serial LuxAlgo:** `max/min`, `max_x1/min_x1`, `follow_*`, `os`, `px1/py1` con la misma semántica de swing.
3. **Missed ghosts** al confirmar PH/PL (`os` contrario o `ph < max` / `pl > min`) + zigzag dashed + ghost levels.
4. **Pivotes regulares** ▼/▲ en `b - length`, reset de `max/min` al precio del pivot, `os` 1=high / 0=low.
5. **Fantasma provisional (intención):** con `os==1` busca el **mínimo low** desde el último pivot; con `os==0` el **máximo high**; colores ghost vs líneas diagonales/horizontales **opuestos** (como en el bloque islast).
6. **Causalidad Replay:** `update_last` solo usa velas `≤ index`; tests de reset+refeed deterministas para labels y trails (`t/42`).
7. **Toggle rastro:** overlay `show_rastro` solo afecta dibujo; el cálculo de `trails` se conserva (útil para extractor headless).

---

## Diferencias (detalle)

### D1 — Rastro `"1"`: semántica distinta (CRÍTICO para ML)

**Pine (`Ghosts_in_swings.txt`, bloque `barstate.islast`):**

- L.371–374: en cada actualización de la última barra, `label.new(..., '1', …)` en la **punta actual** `(x_last, y_last)` (con caja).
- L.417–419: si `barstate.isconfirmed`, otro `label.new(..., '1', …)` **también en la punta actual**, sin comprobar si el fantasma se movió.
- El comentario en L.417 dice: *“solo cuando la vela cierra y el fantasma cambia de lugar”* — **el código no implementa ese “cambia de lugar”**.

**Perl (`_update_rastro_from_provisional`):**

- Si la punta provisional cambia (`index` o `price`), empuja un trail `"1"` en la **posición previa**.
- No deja `"1"` por el mero cierre de vela si la punta no se movió.
- No duplica el paint “con caja” + “sin caja” del Pine.

**Impacto labels:** conteos `y3/y5/y10/y15` pueden divergir fuerte si se interpreta el literal Pine (casi un `"1"` por barra confirmada en punta) frente al Perl (un `"1"` por salto). El oral/DOCX (reubicaciones, tip. 0…3 en 3 min) encaja mejor con el Perl + comentario, **no** con el literal L.417–419.

### D2 — Ventana del provisional: `px1` incluido vs excluido (CRÍTICO)

**Pine:** `for i = 0 to b - px1 - 1` → barras `b … px1+1` (**excluye** la barra del pivot `px1`). Si `b == px1`, el rango queda vacío → no hay ghost.

**Perl:** `for $i ($from .. $n)` con `$from = px1` → **incluye** `px1`.

**Impacto:** punta distinta justo tras confirmar un pivot (sobre todo si el extremo sigue en la propia barra pivot). Eso mueve apariciones/reubicaciones y, en cascada, trails y disparos de muestra.

### D3 — Desempate cuando hay varios barras con el mismo extremo (MEDIO)

**Pine:** `array.indexof` sobre un array empujado de **nuevo → viejo** → gana la barra **más reciente**.  
**Perl:** primer extremo estricto al recorrer **viejo → nuevo** → gana la barra **más antigua**.

Misma serie de precios puede fijar el fantasmita en índices distintos → reubicaciones distintas.

### D4 — Timing Pine `islast` / ticks vs Perl por vela cerrada (ACEPTABLE en Replay 1m)

Pine recalcula el live ghost en la última barra (ticks). Perl alimenta velas cerradas en Replay. Para dataset 1m OHLCV cerrado es el modelo correcto de la app; no es bug, pero no es “tick-idéntico” a TV en tiempo real.

### D5 — Serie `max_x1` / `min_x1` al llamar missed (MEDIO-BAJO)

**Pine:** actualiza `max_x1` en el frame y pasa **`max_x1[1]`** (valor barra previa) a `get_swing_pivots`.  
**Perl:** actualiza `_max_x1` y usa el valor **ya actualizado** en `_on_pivot_*`.

Puede desalinear *missed* ghosts cuando en la misma barra hay update de tracking y confirmación de pivot opuesto. Menos central para el muestreo por fantasmita provisional, sí para paridad visual TV de 👻 missed.

### D6 — Semilla inicial (BAJO, consciente)

Pine inicia `max/min = 0`. Perl siembra con el primer `high/low[length]` válido (`_seeded_run`) para evitar artefacto en 0. Divergencia solo al arranque de serie.

### D7 — `os` inicial (BAJO)

Pine: `var int os = 0`. Perl: `undef` hasta el primer pivot → sin provisional hasta entonces. Alineado en la práctica tras el primer regular.

### D8 — Fuera de alcance (no cuenta como fallo del port de labels)

- AVWAP / bandas SD / `ghostVwapData` del mismo `.txt` no están en `PivotPointsHL` (AVWAP auto en otros módulos).
- Glyph emoji vs fantasma dibujado en Tk: solo render.
- Input `rastro_css` declarado en Pine pero el paint de `"1"` usa `miss_pl`/`miss_ph`; overlay Perl usa gris tema `pph_rastro`.

### D9 — Doble paint de `"1"` en el propio Pine (nota sobre la referencia)

El `.txt` deja rastros por **dos** caminos (L.371–374 y L.417–419) con estilos distintos. Cualquier “implementación idéntica” literal heredaría esa ambigüedad. Conviene que el auditor fije **una** regla canónica para el extractor.

---

## Tabla rápida: regla → ¿alineado?

| Regla | Pine | Perl | ¿Alineado? |
|---|---|---|---|
| Confirmación pivot `length/length` | sí | sí | Sí |
| Missed + zigzag + ghost levels | sí | sí (con matiz D5) | Parcial |
| Fantasma live punta extremo post-`px1` | excluye `px1` | incluye `px1` | **No** |
| Desempate extremo | más reciente | más antiguo | **No** |
| Rastro `"1"` | punta actual / casi cada confirm | punta previa si se mueve | **No** (literal); **Sí** (comentario) |
| Causal Replay | N/A (TV) | sí | Sí (app) |

---

## Riesgo para labels ML

| Elemento | Riesgo | Por qué |
|---|---|---|
| Disparo muestra (aparición / reubicación) | **Alto** | D2+D3 cambian cuándo/dónde se considera “reubicación”. |
| Conteos `y3…y15` de rastros `"1"` | **Alto** | D1: literal Pine vs Perl pueden no ser la misma variable aleatoria. |
| Features en la vela del evento | Medio | Índice/precio del fantasma distinto → distancias en PIPs distintas. |
| Missed 👻 consolidado | Bajo–medio | Más visual / features de nivel; no es el contador DOCX principal. |
| Fuga de futuro Replay | Bajo | Port causal; tests de refeed OK. |

Oral 20/27 + DOCX: evento = aparición/reubicación; label = cuántos `"1"` adelante. Eso asume **la misma definición de reubicación y de rastro** que TradingView con el `.txt`. Hoy eso **no está garantizado**.

---

## Recomendación (para el auditor Paso 1)

**Estado:** `ALINEADO_PARCIAL` — base LuxAlgo usable; **bloqueante para labels “idénticos”** hasta cerrar D1–D3.

**Opción A (recomendada para ML / oral):** congelar contrato *comentario Josafa*:

- Rastro solo si la punta se mueve; `"1"` en punta **previa** (como Perl hoy).  
- Decidir ventana: excluir `px1` (más fiel al loop Pine) **o** documentar inclusivo como contrato app.  
- Desempate: fijar “más reciente” (Pine) o “más antiguo” (Perl) y unificar.

**Opción B (literal DOCX “idéntico”):** portar el bloque islast tal cual (incl. L.371–374 + L.417–419) y aceptar conteos distintos al tip oral 0…3 — **desaconsejado** sin validar con el profe.

**No refactorizar de golpe** hasta esa decisión. El extractor no debe asumir paridad TV todavía.

**Checklist mínima antes de Paso 2:**

- [ ] Decisión escrita: regla rastro A o B.  
- [ ] Ajuste o aceptación documentada de ventana `px1` + tie-break.  
- [ ] Smoke Replay 1m: mismos instantes de salto vs captura TV (o vs contrato A).  
- [ ] Conteo trails en ventana 3/5/10/15 en 1 día de abril ≈ expectativa oral (masa en 0…3).

---

## Veredicto final

**ALINEADO_PARCIAL**

Motor de pivotes/missed: usable.  
Fantasma + rastro (corazón de labels): **no idéntico** al `.txt` literal; Perl ≈ comentario, no al código.  
**Antes del extractor:** resolver D1–D3 (o aceptar contrato app explícito). No tratar el ítem DOCX “implementación idéntica” como cerrado.
