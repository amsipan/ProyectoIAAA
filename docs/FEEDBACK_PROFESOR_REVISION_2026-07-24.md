# Feedback del profesor — revisión post-entrega (2026-07-24)

Fuente: revisión exclusiva del proyecto entregado.  
Documento de trabajo vigente para la tanda de correcciones actual.  
Prioridad: **este archivo** frente a docs/handoffs/brújulas anteriores cuando haya conflicto.

---

## 1. Rendimiento al cambiar temporalidades (`MarketData`)

Se observa lentitud al cambiar TF en el gráfico.

**Expectativa**
- Alimentar los arreglos de **todas** las temporalidades **una sola vez** al inicio.
- Dejarlos en memoria para no repetir el mismo procesamiento al cambiar de TF.

**Observación técnica**
- `add_candle()` en `MarketData.pm` debería ser **O(1)**, pero hay un bucle `for` que sugiere **O(n)** sobre la historia.

**Acción**
- Reutilizar las optimizaciones del `MarketData.pm` del profesor (código de referencia que él proporcionará / ya compartió).
- Incorporar `$base_index` en `build_tf_candles()` para mapear entre temporalidades **sin búsquedas innecesarias**.
- Objetivo: fluidez al cambiar TF.

**Estado:** hecho (merge `feature/marketdata-tf-optimizacion` / ATR cache).

---

## 2. HLD (4h/D) en temporalidades bajas

La función HLD del menú Estructura **no plotea** en gráficas de baja temporalidad.

**Expectativa**
- Las líneas de soporte/resistencia HLD deben verse en **todas las temporalidades iguales o inferiores** a 4h/D.
- Objetivo: ver lo de TF superiores **sin cambiar** las velas del gráfico.

**Acción**
1. Primero: optimizaciones de `MarketData` (§1).
2. Luego: mostrar HLD en TF iguales o inferiores, consultando los vectores de TF ya armados en memoria (cálculo barato).

**Implementación (rama `feature/hld-mtf-toggles` → `main`)**
- Dos toggles independientes: **HLD 4h** y **HLD D**.
- Regla por fuente: HLD 4h si chart ≤ 4h; HLD D si chart ≤ D (en W no plotea).
- Cálculo sobre `$md->{data}{4h|D}` sin mutar `active_tf` del gráfico.

**Estado:** hecho.

---

## 3. Replay — margen derecho

Replay se ve bien implementado.

**Ajuste**
- Aumentar un poco el margen derecho para que la **última vela se vea completa**.
- Hoy, al llegar al margen, casi la mitad de la vela queda detrás del eje de precios.
- Debe verse la última vela completa **más** el mismo espacio en blanco que ya separa una vela de otra.

**Implementación (`feature/replay-right-margin` → `main`)**
- Solo con Replay activo: padding px (`_replay_plot_right_margin_px`) = cuerpo completo + inter-vela `0.4*bar_w` (cualquier TF).
- En Play, al auto-scroll del head al borde: mínimo 1 slot vacío a la derecha.
- Live: rampa continua de margen en zoom-out fino (`bar_w` 12→3 px) para que la última vela visible no se coma el borde (final o medio del historial).
- Clip de dibujo al `plot_width` (no pintar overscan en la franja del margen).
- Rueda sin Ctrl: conserva el borde derecho (`offset=0` al final; mismo `offset` en medio).

**Estado:** hecho (2026-07-24).

---

## 4. SMC Structures+FVG — toggle independiente de FVG

**Problema**
- Las etiquetas BOS/CHoCH de Structures+FVG se solapan con las de SMC Pro.

**Expectativa**
- Botón propio (estilo habilitado/deshabilitado, como el resto de checks) para **independizar** FVG del etiquetado BOS/CHoCH interno de ese indicador.
- Poder ver BOS/CHoCH de **SMC Pro** junto con **FVGs**, sin solape de etiquetas Structures+FVG.

**Implementación (`feature/smc-fvg-toggle-independiente` → `main`)**
- Capa maestra **SMC Structures+FVG** + sub-toggles **FVG** y **BOS/CHoCH** (mismo patrón que OB int/ext).
- Overlay `show_fvg` / `show_structure` controlan qué se dibuja sin re-feed.
- Default al activar: **FVG ON**, **BOS/CHoCH OFF** (anti-solape con SMC Pro).

**Estado:** hecho (2026-07-24).

---

## 5. SMC Pro — toggles independientes de etiquetas

Botones propios para habilitar/deshabilitar por separado:

1. Etiquetado BOS/CHoCH **interno**
2. Etiquetado BOS/CHoCH **externo**
3. Etiquetado **EQH/EQL**

---

## 6. Liquidez — quitar EQH/EQL de esa capa

El EQH/EQL del menú Liquidez dibuja una línea punteada entre extremidades lejanas.

**Veredicto del profesor**
- No tiene sentido: se extiende demasiado y solapa picos/valles.
- **Quitarla por completo** de Liquidez.
- EQH/EQL ya está bien en **SMC Pro**.

---

## 7. AVP (Volume Profile) — ancla visible

**Manual**
- El puntito de ancla casi invisible cuando solapa velas/etiquetas del mismo color; parece dibujarse detrás.
- Mostrarlo con más claridad (referencia TradingView), preferiblemente por encima.

**Automático**
- También debe mostrar dónde está la ancla de la misma forma.
- Si el usuario **mueve** la ancla auto, deja de ser automático y pasa a **manual** (reutilizar el comportamiento manual ya hecho).

---

## 8. AVWAP — mismas optimizaciones visuales de ancla

Aplicar al AVWAP manual y automático las mismas mejoras de claridad de ancla que al AVP (§7).

---

## 9. AVWAP automático — diferenciación visual de curvas

**Correcto**
- En auto se dibujan **2** AVWAP con curvas principales de colores distintos y destacados.

**Problemas**
- Las desviaciones (σ) usan los **mismos** colores en ambos AVWAP → difícil distinguir origen.
- El verde se repite entre el primer AVWAP principal y su primera desviación → confusión.

**Dirección sugerida**
- Diferenciar origen de cada curva (p. ej. el segundo VWAP / sus bandas en **línea discontinua**).
- No repetir el mismo color verde entre principal y primera desviación.

---

## 10. Canal paralelo manual — mediana

Poner una **línea punteada en el medio** del canal, como en TradingView.

---

## Orden de trabajo sugerido (por dependencias del propio feedback)

1. ~~Optimizar `MarketData` (TF en memoria, `add_candle` O(1), `$base_index`).~~ **hecho**
2. ~~HLD 4h / HLD D (toggles) visibles en TF ≤ fuente, vectores prearmados.~~ **hecho**
3. ~~Margen derecho Replay + zoom-out live estable.~~ **hecho**
4. Toggles SMC Pro / Structures+FVG; quitar EQH/EQL de Liquidez. ← **siguiente: §4 FVG independiente**
5. Anclas AVP/AVWAP + colores/estilos AVWAP auto + mediana canal paralelo.
