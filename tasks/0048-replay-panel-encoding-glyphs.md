# Task 0048: [ALTO/regresión visual] Panel Replay muestra mojibake — encoding + glyphs sin fuente

## Origen
- Validación visual del arquitecto de la task 0043 (05/07). El panel flotante aparece centrado
  abajo con la estructura correcta, PERO todas las etiquetas salen como mojibake:
  `â ( Select bar   â ¾   â · Play   â ·| Fwd   |â )   1x   D   â ·â ·|   â(¦   â`
  en lugar de `✂ Select bar ▾ / ▷ Play / ▷| Fwd / |◁ / 1x / D / ▷▷| / … / ✕`.

## Causa raíz (dos capas)
1. **Falta `use utf8;` en `Market/UI/ReplayPanel.pm`.** El archivo tiene glyphs UTF-8 literales
   (`✂`, `▷`, `▾`, `◁`, `▷▷|`, `…`, `✕`) en las cadenas de los botones, pero solo declara
   `use strict; use warnings;`. Sin `use utf8`, Perl interpreta cada byte del glyph multi-byte como
   un carácter Latin-1 → mojibake `â...`. (Comparar: `market.pl` sí tiene `use utf8` en línea 4.)
2. **Aunque se corrija el encoding, la fuente Tk de Fedora35 NO tiene estos glyphs.** La task 0042
   ya lo demostró: el glyph tijeras `\x{2702}` renderizó como una `x`. Las flechas de reproductor
   (`▷ ▷| ▷▷| ◁ ✂ ✕`) probablemente tampoco existan en la fuente por defecto.

## Fix requerido
**Opción recomendada (robusta, mínima, elegida por el arquitecto): usar etiquetas ASCII/texto**
en vez de glyphs unicode que la fuente no tiene. Es lo más fiable en Tk/Fedora35 y sigue siendo
legible y parecido a TradingView (que combina icono + palabra):
- `Select bar ▾`  → `Select bar  v`  (o `Select bar` + botón separado `▾`→`v`)
- `▷ Play`         → `Play`   (el toggle Play/Pause real llega en 0046)
- `▷| Fwd`         → `Fwd >|` con ASCII, o simplemente `Fwd`
- `|◁` (step back) → `|< Back` o `<`
- `1x` / `D`       → se quedan igual (ya son ASCII)
- `▷▷|` (jump)     → `Jump >>|` con ASCII, o `>>`
- `✕` (cerrar)     → `X`

Y **añadir `use utf8;`** a `ReplayPanel.pm` de todas formas (buena práctica; deja la puerta abierta
a iconos vectoriales luego).

**Alternativa (más trabajo, mejor aspecto):** iconos vectoriales con `createLine`/`createPolygon`
en mini-canvas por botón (triángulo Play, etc.). Coordinar con 0047 (tijeras) para un enfoque común.
Si se elige esta, dejarlo para después; NO bloquear el lote por estética.

## Criterios de aceptación
- El panel NO muestra mojibake: todas las etiquetas son legibles.
- Los botones siguen cableados a sus callbacks (no cambia la lógica de 0043).
- `perl -I. -c Market/UI/ReplayPanel.pm` OK; `prove -l t` verde.
- Validación visual del arquitecto: panel legible, comparado con captura 1 de la referencia.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/UI/ReplayPanel.pm && perl -I. -c market.pl && prove -l t"
```

## Qué no tocar
- No cambiar la posición/estructura del panel (place, orden de botones) ni las factorías de callbacks.
- No tocar el backend de ReplayController.

## Nota
Esta task tiene prioridad ALTA dentro del lote visual: sin ella el panel es inusable estéticamente.
Conviene hacerla ANTES de 0044/0045/0046 (que añaden más botones/menús con el mismo riesgo de glyph).
Aplicar el mismo criterio de etiquetas legibles a los dropdowns de 0044/0045.
