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

## ENFOQUE DECIDIDO (04/07) — DESBLOQUEADA
Combinar los dos: **agrupar en banda los niveles BSL (o SSL) cercanos en precio**
y mostrar solo los vigentes. El profe dijo literal "para tener una banda", así
que el resultado debe ser ZONAS sombreadas, no líneas sueltas.

Diseño concreto:
- En el OVERLAY (`Market/Overlays/Liquidity.pm`), NO en el indicador (el cálculo
  de BSL/SSL no cambia; solo cómo se dibuja). Nuevo parámetro `band_atr` (default
  0.5): dos niveles del MISMO tipo (BSL con BSL, SSL con SSL) cuya diferencia de
  precio sea <= band_atr * ATR se agrupan en una banda.
- Cada banda se dibuja como un rectángulo tenue (stipple 'gray12') que abarca
  desde el min hasta el max de los niveles del grupo, en X desde el pivote más
  antiguo del grupo hasta el borde derecho (último candle real, como Mxwll).
  Color: BSL rojo (#ef5350), SSL verde (#26a69a), semitransparente.
- Etiqueta 'BSL'/'SSL' una sola vez por banda (no por nivel).
- ATR: reusar el ATR que ya calcula el indicador Liquidity (exponer un getter
  `current_atr()` si no existe, o pasar el ATR del último índice). Si no hay ATR
  aún, caer a dibujar líneas individuales (comportamiento actual) como fallback.
- Toggle: un nuevo flag `_band_mode` (default ON). Con OFF, dibuja líneas sueltas
  como hoy (para no perder el modo anterior). Setter `set_band_mode($bool)`.

## Criterios de aceptación
- Con band_mode ON (default), BSL/SSL cercanos se muestran como banda sombreada;
  la vista queda notablemente más limpia (muchas menos líneas).
- Con band_mode OFF, comportamiento actual (líneas individuales) intacto.
- Toggles BSL/SSL siguen encendiendo/apagando cada familia.
- Suite `prove -l t` verde; test nuevo en t/15 que verifique: (a) N niveles BSL
  cercanos → 1 banda (createRectangle), (b) niveles lejanos → bandas separadas,
  (c) band_mode OFF → líneas como antes.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/Overlays/Liquidity.pm && prove -l t/10-liquidity.t t/15-overlay-liquidity-render.t"
```

## Qué no tocar
- No romper la vinculación toma→nivel (ORDEN 3) ni los toggles.
