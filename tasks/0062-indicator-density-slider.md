# Task 0062: Control de densidad de indicadores — slider 1–100% de significancia

## Estado
🔲 ABIERTA (2026-07-05). Feedback profe/QA 2ª ronda. Idea de Bryan.

## Origen
- `docs/FEEDBACK_PROFESOR_QA_2026-07-05.md` sección 2.
- Bryan: "En lugares con poca interacción del mercado que se marquen menos etiquetas y dejar solo
  visibles las más significativas. Crear un menú o una barra deslizante para seleccionar en números
  del 1 al 100 cuánto porcentaje de indicadores deben estar indicándose."
- Profe (lista): "Identificar las tomas de liquidez más relevantes para que no haya tanta
  aglomeración."

## Objetivo
Una perilla (slider) que controle EN VIVO cuántas etiquetas/eventos se muestran, del más
significativo al menos, sin recalcular indicadores (solo filtra al dibujar).

## Decisión de alcance (PENDIENTE confirmar con Bryan)
- **Fase A (esta task, recomendada):** UN slider GLOBAL 0–100% que actúa sobre los eventos de
  liquidez (BSL/SSL, sweep/grab/run) que YA tienen `magnitude`/`relevant`. 100% = todo; valores
  menores = solo el top-% por magnitud.
- **Fase B (task futura, si el profe lo pide):** sliders por familia (BSL/SSL, sweep/grab, EQH/EQL,
  estructura SMC).
> Confirmar con Bryan antes de implementar si arrancamos con global (Fase A) o directo por familia.

## Enfoque (a implementar — Fase A)
- Widget: `Tk::Scale` horizontal 1–100 (funciona en WSLg; NO usar NoteBook/Optionmenu). Ubicarlo
  en un panel existente (p.ej. pestaña "Liq" o "Capas"). Etiqueta "Densidad %".
- Estado compartido: un `Scalar::Ref` `density_pct` (como los otros toggles en `market.pl`),
  cableado por callback a los overlays de liquidez.
- Filtrado en el OVERLAY (no en el indicador): al dibujar, ordenar los eventos/niveles VISIBLES por
  `magnitude` desc y quedarse con el top `ceil(N * density_pct/100)`. Sin recalcular indicadores →
  barato, en vivo. Re-render vía `request_render()`.
- Aplicar a: niveles BSL/SSL y eventos sweep/grab/run. (EQH/EQL y estructura → Fase B.)
- Default: 100% (comportamiento actual; el slider solo puede REDUCIR ruido).
- Interacción con `_only_relevant`: el slider opera sobre lo que ya pasó el filtro de relevancia
  (o lo reemplaza — decidir; recomendado: slider filtra sobre TODOS los relevantes por percentil).

## Criterios de aceptación
- Mover el slider a 100% muestra todo; bajarlo reduce progresivamente a los más significativos, en
  vivo, sin recalcular.
- No rompe toggles ni bandas existentes; con 100% la vista es idéntica a hoy.
- `Tk::Scale` renderiza y responde en WSLg (verificación visual del arquitecto).
- `prove -l t` verde; test de la lógica de filtrado por percentil (dado N eventos con magnitudes
  conocidas y pct=X, se seleccionan los K correctos). El test ejercita la función real de selección,
  no una reimplementación inline.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/Overlays/Liquidity.pm && perl -I. -c market.pl && prove -l t"
```
OBLIGATORIA verificación visual del arquitecto (slider en WSLg + efecto en vivo).

## Relación
- Complementa 0054 (baja densidad en origen). El slider es control fino de usuario; 0054 es el piso.

## Qué no tocar
- CSV, MarketData, Market/Debug/.
- No recalcular indicadores por movimiento del slider (solo filtrado de render).
- No usar NoteBook/Optionmenu/menubar nativo (fallan en WSLg): usar Scale + Frames.
