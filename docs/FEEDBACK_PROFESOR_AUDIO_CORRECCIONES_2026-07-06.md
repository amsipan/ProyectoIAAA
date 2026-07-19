# Feedback profesor — Audio_Correcciones.ogg (sesión ~6 de julio)

> **Origen:** `C:\Users\ASUS ROG\Downloads\Audio_Correcciones.ogg`  
> **Transcripción VPS:** Groq `whisper-large-v3-turbo` vía  
> `/home/openclaw/.openclaw/scripts/long-audio-transcribe.py`  
> Job: `/home/openclaw/.openclaw/media/transcripts/Audio_Correcciones-20260714-212544/`  
> **Copia local del transcript crudo:**  
> `docs/material_profesor/Audio_Correcciones_transcript_20260714.txt`  
> **Fecha del chart revisado en el audio:** dataset ~ **6 de julio** (1m).  
> **Extraído:** 2026-07-14 (sesión de transcripción). Whisper mezcló ES/EN y deformó
> nombres (LuxAlgo, Mxwll, SMC, DIY); abajo van términos corregidos.

---

## Resumen ejecutivo (correcciones / requisitos)

El profe compara la app del grupo con referencias TradingView (LuxAlgo SMC, “SMC Pro”,
Mxwll Suite, DIY Strategy Builder, ZigZag externo) y marca **dónde aciertan y fallan**.
El hilo conductor: **distinguir bien interno vs externo**; si eso falla, el algoritmo de
ML posterior se equivoca.

| # | Tema | Qué pide / corrige | Severidad |
|---|------|--------------------|-----------|
| 1 | **BOS / CHoCH externos** | Basarse en **LuxAlgo / SMC Pro**, no en Mxwll. Mxwll confunde internos con externos. | Alta |
| 2 | **Interno vs externo** | No intercambiar etiquetas; validar con **ZigZag externo** (tendencia real). | Crítica |
| 3 | **ZigZag externo** | Es la guía de cuándo cambia la tendencia **externa**; un CHoCH “externo” que no mueve el ZZ externo es **interno**. | Crítica |
| 4 | **FVG (Mxwll)** | FVG de Mxwll es “horrible / no funciona”. Usar el indicador del **documento** (el que tiene FVG en el nombre / SMC). | Alta |
| 5 | **FVG mitigación** | Antiguos deben **desaparecer** al mitigarse; solo vigentes cerca del precio / última dirección del movimiento. | Alta |
| 6 | **FVG gap de sesión** | Un FVG por gap de apertura (mercado cerrado ~1 h) **sí es válido**. | Nota de validación |
| 7 | **Fibonacci** | Anclar solo a la **rama consolidada del ZigZag externo** (no al tramo aún en ajuste). | Alta |
| 8 | **Fibonacci niveles** | Niveles 0.236 / 0.382 / 0.5 / 0.618 / 0.786 (y observación de reacción del precio). | Media (ya parcialmente en código) |
| 9 | **Order Blocks** | Usar referencia **DIY** (Supply/Demand) + config con **delete / mitigate order blocks** ON. | Alta |
| 10 | **OB mitigación** | Si la vela consume el bloque, el viejo se mitiga y **desaparece**; solo queda el nuevo. | Alta |
| 11 | **Confluencia OB + DIY** | Coincidencia DIY (nivel) + caja OB = **alta probabilidad** (ambos convergen). | Feature / diseño ML |
| 12 | **Canal de tendencia** | Tubo que se desarrolla en el tiempo (p. ej. HL/LH repetidos); **no** un indicador rígido de un instante. | Alta |
| 13 | **Canal se deshace** | Al consumir liquidez del canal / salir de tendencia → **desaparece**. | Alta |
| 14 | **ZigZag 1m vs TF** | Calibrar en 1m (ej. día 2 ~19:00); al cambiar temporalidad también se afecta. | Media (calibración) |
| 15 | **Analizar 3 fuentes** | No fiarse de un solo indicador; cruzar LuxAlgo / SMC Pro / Mxwll / ZZ externo. | Proceso |

---

## 1. Estructura: BOS / CHoCH y niveles interno/externo

### Problema que ve el profe
- En la app (y en Mxwll de referencia) se ve **mucho “interno” pintado como si fuera externo**.
- Mxwll **intercambia** a menudo entre interno y externo → no se sabe por dónde guiarse.
- En un caso concreto: un CHoCH etiquetado como externo **coincide en hora** con Mxwll, pero al quitar capas y cruzar con **LuxAlgo + SMC Pro**, el **externo real** es otro; Mxwll se equivoca.
- Si no se distingue bien interno/externo, **el algoritmo (ML) va a fallar**.

### Requisitos / correcciones
1. **Fuente de verdad para BOS/CHoCH externos:** LuxAlgo y/o “SMC Pro”, **no** Mxwll.
2. **Validación con ZigZag externo:** la tendencia externa es la del **zigzag externo** (línea azul / ChartPrime-style). Si el ZZ externo no giró, el evento es **interno**, aunque otro script diga “externo”.
3. Ejemplo conceptual del profe: el precio tomó liquidez y luego fue al otro lado → el nivel **externo relevante** es el que el ZZ externo refleja tras la manipulación; no el “chiquito” intermedio.
4. Revisar en la app (dataset del **6 de julio**, 1m) que los CHoCH/BOS **externos** coincidan con LuxAlgo/Pro y con el ZZ externo; no con el ruido de Mxwll.

### Implicación para el código actual
- `SMC_Structures` / `Mxwll_Suite` y etiquetas INT/EXT (tasks 0022, 0056, 0057) deben **alinearse a LuxAlgo/Pro + ZZ externo**, no “parecerse a Mxwll” cuando Mxwll está mal.
- Convivencia de capas está bien, pero la **calibración de “externo”** es el punto a corregir.

---

## 2. FVG (Fair Value Gap)

### Problema
- FVG de **Mxwll**: “horrible”, pinta líneas a todos lados, **no funciona**.
- El que sí funciona es el del **documento / indicador con FVG en el nombre** (SMC-style).

### Requisitos / correcciones
1. **No basarse en FVG de Mxwll** para la app.
2. Implementar/calibrar FVG estilo **SMC del documento**:
   - Gap entre **tres velas** (vela 1 y 3).
   - Preferir el FVG **cerca del precio actual** / en la **última dirección** del movimiento.
   - **Mitigación:** FVG antiguos **desaparecen** al mitigarse (`Reduce mitigating FVG` / equivalentes ON en la referencia).
3. **Excepción válida:** FVG por **gap de apertura** (mercado cerrado ~1 h entre cierre y apertura) — el profe confirma que el indicador de referencia lo marca bien y es correcto.

### Implicación código
- Refina/refuerza tasks **0023 / 0059** (FVG near price + mitigación). Revisar si Mxwll overlay sigue mostrando FVG ruidoso y si debe apagarse por defecto o filtrarse más.

---

## 3. Order Blocks (OB)

### Referencias que usa el profe
- **DIY Custom Strategy Builder** (favorito): solo **Supply and Demand**; quitar el resto de toggles del DIY.
- Otro script de referencia con **Delete / mitigate order blocks** habilitado (en el audio suena “MSVV” / similar — config: delete order blocks ON, zigzag OFF en ese indicador de TV).

### Requisitos / correcciones
1. Los OB deben **mitigarse**: si la vela **consume** el bloque hacia atrás, esa parte queda mitigada y **no se dibuja**.
2. Tras consumir, puede abrirse un **OB nuevo**; solo el vigente debe verse.
3. **Confluencia de calidad:** cuando el nivel azul DIY (S/D) **coincide** con la “cajita” del OB → zona de **alta probabilidad** (compradores/vendedores acumulados). Útil como señal/feature, no solo dibujo.

### Implicación código
- Revisar `Mxwll_Suite` / SMC OB (task 0026 y derivados): mitigación real vs cajas eternas.
- `Strategy_Builder` Supply/Demand como capa de confluencia con OB.

---

## 4. Canal de tendencia

### Requisitos / correcciones
1. El canal es un **tubo** que se **desarrolla en el tiempo**, no un snap de un instante.
2. Base conceptual: pivotes del **mismo lado** (p. ej. **HL** en uptrend, o **LH** en downtrend) **repetidos** (menciona al menos **3** en un horizonte tipo 1h) → se puede proyectar 4.º / 5.º.
3. El precio **respeta** el tubo; se dibuja cuando ya se observa ese comportamiento.
4. **Desaparición:** cuando se **toma la liquidez del canal**, se rompe la estructura o se pasa a rango lateral / cambio de tendencia → el canal **deja de tener sentido y desaparece**.
5. No hay un único indicador TV “mágico”; se basa en estructura (HL/LH) y zigzag/estructura.

### Implicación código
- Refina task **0061** (canal clásico): no solo “2 paralelas por pierna”, sino **ciclo de vida** (aparición con ≥N pivotes, desaparición al break/consumo de liquidez). Validar visual vs lo que el profe dibuja a mano.

---

## 5. Fibonacci anclado al ZigZag externo consolidado

### Requisitos / correcciones
1. Fibonacci **automático** debe anclarse a la **rama consolidada del ZigZag externo**.
2. El tramo del ZZ que **aún se ajusta** (último segmento no consolidado) **no** se usa para Fib.
3. Usar las **últimas dos piernas ya cerradas** del zigzag externo (alto/bajo definidos).
4. Niveles de interés: **0.236, 0.382, 0.5, 0.618, 0.786** — observar **reacción del precio** (el profe muestra reacción en 0.5, 0.382, etc.).
5. Se puede dibujar en ambos sentidos (rama up o down) según la pierna consolidada elegida.
6. En calibración 1m (ej. día 2 ~19:00 del dataset del 6): un “pico” del grupo quedó **más alzado** que la referencia; el resto coincidía mejor.

### Implicación código
- Fib hoy en SMC/Mxwll (tasks 0029, 0060) debe **anclarse explícitamente a vértices consolidados del ZigZag externo**, no a HH/HL ruidosos del SMC.
- Refuerza el audio WhatsApp del 05/07 (feedback previo: basarse en zigzag, no en montón de HH/HL del SMC).

---

## 6. Proceso de trabajo / referencias TV

1. Tener en TradingView (favoritos) y **configurar** como el profe:
   - LuxAlgo SMC / SMC Pro (estructura externa).
   - Mxwll (contraste; **no** como fuente de verdad de externo ni de FVG).
   - DIY S/D (solo supply/demand).
   - ZigZag externo (ChartPrime-style, solo línea).
   - Indicador FVG del documento (mitigating ON).
2. Comparar la app en la **misma fecha/hora** (6 de julio, 1m) y marcar divergencias.
3. “Analizar los indicadores entre los tres”: no decidir por un solo script.

---

## 7. Lista accionable para el equipo (checklist)

### Crítico / alto impacto
- [ ] **Regla INT/EXT:** un BOS/CHoCH solo es **externo** si el **ZigZag externo** (o LuxAlgo/Pro externo) lo respalda.
- [ ] **Dejar de copiar Mxwll** en BOS/CHoCH externos y en FVG.
- [ ] **FVG:** solo SMC-style, mitigación = desaparece, near price / última dirección.
- [ ] **OB:** mitigación real al consumo de precio; sin cajas eternas.
- [ ] **Fib:** ancla = **rama consolidada del ZZ externo** (no último tramo en ajuste).
- [ ] **Canal:** aparición con estructura repetida en el tiempo; **desaparece** al break / consumo de liquidez del tubo.

### Calibración / QA visual
- [ ] Replay/dataset **6 de julio** (y referencias del día 2 ~19:00 en 1m) vs LuxAlgo + Pro + ZZ externo.
- [ ] Verificar un caso de FVG por **gap de sesión** (no marcarlo como bug).
- [ ] Verificar confluencia DIY S/D + OB en la misma zona.

### Medio / producto ML (Fase 3)
- [ ] Features de “alta probabilidad” cuando DIY y OB coinciden.
- [ ] Features INT vs EXT + alineación de direcciones ZZ interno/externo (convergencia = señal limpia).

---

## 8. Relación con feedback anterior (05/07 → tasks 0054–0062)

| Tema audio 05/07 (tasks) | Este audio (~06/07 review) |
|--------------------------|----------------------------|
| Menos ruido BSL/SSL, runs, EQH/EQL INT/EXT | Enfoca **estructura** INT/EXT y fuentes LuxAlgo vs Mxwll |
| FVG cerca del precio | Reafirma + **mitigación desaparece** + **Mxwll FVG no sirve** |
| Fib 3 niveles en TF bajas; ML/MH primero | Añade ancla **ZZ externo consolidado** |
| Canal clásico (0061) | Añade **ciclo de vida** (aparece/desaparece) |
| Densidad / slider | No es el foco de este audio |

Muchas tasks 0054–0062 **tocan el mismo territorio**, pero este audio **endurece la fuente de verdad** (LuxAlgo/Pro + ZZ externo, no Mxwll) y el anclaje de Fib/canal/OB.

---

## 9. Transcript crudo

Ver archivo completo:

`docs/material_profesor/Audio_Correcciones_transcript_20260714.txt`

Notas de ASR: “LUPZALGO/Luxalvo” → LuxAlgo; “Maxwell/Maxon/Maxapunk” → Mxwll; “SMS/SMC”; “COXCH” → CHoCH; “D-I-Y” → DIY Strategy Builder; “SFVG” → FVG; “Pesor corrections…” = ruido del prompt de Whisper.
