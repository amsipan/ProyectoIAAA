# Feedback Profesor / QA Tester — 2026-07-05

> **Estado:** ARCHIVO A COMPLETAR. Fuente cruda para formalizar tasks. NO editar el
> contenido citado (transcripciones/mensajes textuales); las notas del arquitecto van
> claramente marcadas aparte. Origen: cosas que el profesor mencionó para mejorar,
> anotadas por un compañero, más lo que observó el QA tester al abrir la app.

---

## 1. Lista textual del compañero (cosas que dijo el profesor / notó el QA)

> BSL y SSL debe ser más limpio para tener una banda
> Run implica continuidad, los sweep/grab implican rebote
> Identificar las tomas de liquidez más relevantes para que no haya tanta aglomeración
> Las etiquetas del SMC se usan como base del run y sweep
> El run debería colocarse al romper el nivel y continuar
> Si se avanza pone run y rebota se pone grab, solo en niveles importantes
> Distinguir entre EQL y EQH interno y externo
> Cambiar colores de velas importantes para saber cuanto ocurrió un liquidity run
> Solo dejar FVG vigentes cuando estén cerca al precio actual, sino dejarlos inactivos
> Los ML y MH deben identificarse primero para calcular fibonacci sino da los márgenes equivocados

---

## 2. Idea propuesta por Bryan (a evaluar)

> En lugares con poca interacción del mercado se marquen menos etiquetas y dejar solo
> visibles las más significativas. Crear un menú o una barra deslizante para seleccionar
> en números del 1 al 100 cuánto porcentaje de indicadores deben estarse indicando, para
> manipularlo según se quiera.

Nota arquitecto: viable. Cada evento de liquidez ya tiene `magnitude`; un `Scale` de Tk
(funciona en WSLg) filtraría por percentil de significancia al dibujar (sin recalcular).
Decidir si aplica global o por familia (BSL/SSL, sweep/grab, EQH/EQL).

---

## 3. Audio WhatsApp 1 (transcripción textual)

**Archivo original:** `C:\Users\ASUS ROG\Downloads\WhatsApp Ptt 2026-07-05 at 9.45.52 AM.txt`
(mensaje más largo — feedback sobre BSL/SSL, RAN, GRAB, EQL/EQH, colores de velas, FBG, ML/MH, Fibonacci)

> Verás, bro. Eso es lo único que recuerdo. Es que ya ahorita con más claridad estaba
> viendo las cosas que notó el Oscar y el Belki. ¿Qué es lo que faltaba poner? Y eso es lo
> que vi verás. El BSL y el SSL todavía salía como demasiado, o sea, salía demasiado, con
> mucho ruido. Salían un montón y ya decían, eso es lo que dijo que le estaba mal. Lo del
> RAN, a ver, algunos de RAN no le veía que tenía mucho sentido. Igual los grab no tenía
> mucho sentido. O sea, era como que, o sea, están puestos así como medio arbitrariamente
> y es como, está medio raro. Ya. ¿Qué más, qué más, qué más te iba a decir? Ah, lo del
> EQL y EQH interno, si no estoy mal, eso no está puesto. No está puesto, según yo, yo no
> le vi que decía ahí EQL, digo, EQL, EQL, etc. ¿Ecuál interno o Ecuál externo? No, eso yo
> no vi en ningún momento en el programa. Lo de los colores de las velas, eso es de ley que
> no estaba puesto. Y ya, lo del FBG creo que estaba puesto. Y lo del ML y MH deben
> identificarse primero para regular. Eso sí, creo que está bien hecho lo del Fibonacci. El
> único problema que había era esto de que dijo el profe, que en temporalidades más bajas
> se pueden solo poner tres niveles del Fibonacci,

---

## 4. Audio WhatsApp 2 (transcripción textual)

**Archivo original:** `C:\Users\ASUS ROG\Downloads\WhatsApp Ptt 2026-07-05 at 9.46.30 AM.txt`
(mensaje más corto — HH/HL en SMC vs zigzag para Fibonacci)

> Y lo único que yo sí vi es que eso del HH, del HL en el SMC, en el Smart Money Concepts,
> todavía salen demasiados. O sea, no deberían salir tantos igual. El profe no quería que
> salgan casi nada, literal. O sea, para él solo son los mismos que salen en el zigzag, que
> son relativamente poquitos. Porque en el SMS salen un montón en realidad. Yo cacho que
> hay que basarse más en los que da el zigzag que los que da el SMS para hacer, digamos,
> esto del... ¿Qué es esto? Lo del Fibonacci, cosas así. Creo que hay que basarse más bien
> en los del zigzag que los del SMS.

---

## 5. Mapa contra el código actual (notas del arquitecto — 2026-07-05)

Estado real por punto tras explorar el código (cálculo en `Market/Indicators/`, render en
`Market/Overlays/`). Leyenda: ✅ hecho · ⚠️ hecho pero mal calibrado / a verificar · ❌ falta.

| # | Punto | Estado | Detalle / archivo |
|---|-------|--------|-------------------|
| 1 | BSL/SSL más limpio con banda | ⚠️ | Modo banda existe (`Overlays/Liquidity.pm` `_cluster_bsl_ssl`, ≤0.5·ATR). Raíz del ruido: swings con `k=1` (`Indicators/Liquidity.pm:33`) hipersensible. Fix: subir `k` / endurecer clustering |
| 2 | Run=continuidad, sweep/grab=rebote | ✅ | FSM `_update_fsm` ya distingue RUN (acepta N velas) vs GRAB (rechazo ≤3) vs SWEEP (rechazo tardío) |
| 3 | Tomas de liquidez más relevantes, menos aglomeración | ⚠️ | Filtro `_only_relevant` (magnitud vs ATR) existe, pero base k=1 mete demasiados candidatos |
| 4 | Run/sweep basados en etiquetas del SMC | ❌ | Arquitectónico: `Liquidity.pm` calcula swings PROPIOS, no usa los del SMC. Por eso se ven arbitrarios |
| 5 | Run al romper el nivel y continuar | ✅ | Coincide con aceptación tras N velas |
| 6 | Run si avanza / grab si rebota, solo niveles importantes | ⚠️ | Distinción run/grab OK; "solo importantes" NO (usa todos los swings k=1) |
| 7 | Distinguir EQH/EQL interno vs externo | ⚠️ | Codificado (ext `EQH/EQL`, int `I-EQH/I-EQL`) pero QA nunca los vio → verificar render en runtime |
| 8 | Colores de velas en liquidity run | ❌ | Solo hay halo/stipple encima (`_highlight_run_candle`); la vela NO se recolorea |
| 9 | FVG vigente solo si cerca del precio | ⚠️ | `Mxwll_Suite` sí filtra (`fvg_near_atr=8`); `SMC_Structures` NO filtra por cercanía |
| 10 | ML/MH primero para anclar Fibonacci | ✅ | Fibo ancla en `major_high`/`major_low`. QA cree que está bien |
| 11 | HH/HL del SMC demasiados; basarse en zigzag | ❌ | SMC usa `k=3`, aún genera muchos. Profe quiere estructura/Fibo sobre los pocos puntos del ZigZag |
| 12 | En TF bajas solo 3 niveles de Fibonacci | ❌ | Niveles fijos en 5; sin lógica por temporalidad |

### Prioridad sugerida (impacto sobre la queja del profe/QA)
1. Bajar densidad de swings (subir `k` Liquidity + reconciliar con SMC/ZigZag) → ataca 1,3,4,6,11.
2. Slider de significancia 1–100% (idea de Bryan) → control directo del ruido.
3. Recolorear velas en RUN (punto 8) → visible y fácil.
4. Fibonacci 3 niveles en TF bajas (punto 12) → fácil.
5. Verificar EQH/EQL internos en runtime (punto 7).
6. Unificar filtro de cercanía FVG en capa SMC (punto 9).

---

## 5b. Canal (Channel) — corrección de concepto (Bryan, 2026-07-05)

**Pedido de Bryan (textual):** "el tema del canal que está en nuestra app, lo que el profe se
refería al pedir un canal era esto que se ve aquí [imagen Static Liquidity de Smart Risk]. Eso es
lo que debes corregir para que se vea como en el gráfico. Actualmente el botón canal crea unas dos
líneas alrededor de otra principal que se ven raras y creo que eso nunca lo pidió el profesor."

**Referencia visual (imagen del profe — slide "Static Liquidity" de Smart Risk):** un **canal de
tendencia clásico** = dos líneas diagonales PARALELAS que encierran una pierna de tendencia. En la
imagen, tendencia bajista: una línea toca los swing highs (arriba), la paralela toca los swing lows
(abajo), y el precio oscila DENTRO. Etiquetas del slide: "Trendline" (una sola línea de soporte) y
"Channel" (las dos paralelas). Punto 3 de la lista de liquidez estática: "Below or above Dynamic
Trendlines & Channels".

**Qué hace la app hoy (❌ incorrecto):** El botón CHANNEL dibuja un ENVELOPE / sobre, no un canal.
- `Indicators/ZigZag.pm` `_rebuild_external_segments` (392-416) + `_external_channel_list` (108-126):
  por CADA segmento del zigzag externo genera dos líneas desplazadas a **±ATR fijo**
  (`channel_offset = channel_width * ATR`), o sea dos rieles equidistantes a UNA sola diagonal.
- `Overlays/ZigZag.pm` (143-166) las dibuja punteadas (`-dash '.'`) alrededor de la línea principal.
- Resultado: "dos líneas alrededor de otra que se ven raras" — no es lo que pidió el profe.

**Qué debería hacer (✅ objetivo):** Canal de tendencia de 3 puntos (paralelas NO equidistantes por
ATR, sino ajustadas a los extremos reales):
- Trendline: ajustar por 2 extremos del mismo lado de una pierna (ej. 2 lows en tendencia bajista →
  línea de soporte con su pendiente real).
- Canal: línea PARALELA (misma pendiente) desplazada hasta tocar el extremo opuesto más lejano
  (el high que más sobresale). Precio queda encerrado entre ambas.
- Se dibuja por PIERNA de tendencia (una tendencia = un canal), no por cada micro-segmento zigzag.
- Sólidas, no un offset de ATR.

**Estado:** ❌ FALTA rehacer. Requiere reescribir la generación del canal en `Indicators/ZigZag.pm`
(nueva geometría de canal por pierna) y ajustar el render en `Overlays/ZigZag.pm`. El botón/toggle
CHANNEL ya existe (`market.pl` panel ZigZag). Decidir: ¿el canal cuelga del ZigZag externo o de una
trendline propia? (probablemente del zigzag externo, que es el que marca las piernas grandes).

---

## 6. Pendiente

- [ ] Formalizar cada punto como task en `tasks/` (numeración siguiente disponible).
- [ ] Confirmar con Bryan alcance del slider (global vs por familia).
- [ ] Verificar en app real puntos ⚠️ (7 EQH/EQL internos; 1/3/6 densidad; 9 qué capa FVG).
- [ ] Aclarar cuánto pidió exactamente el profesor (el compañero no recuerda el detalle completo).
