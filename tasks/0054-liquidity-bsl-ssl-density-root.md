# Task 0054: Reducir ruido de BSL/SSL en origen (densidad de niveles de liquidez)

## Estado
🔲 ABIERTA (2026-07-05). Feedback profe/QA 2ª ronda.

## Origen
- `docs/FEEDBACK_PROFESOR_QA_2026-07-05.md` puntos 1, 3, 6.
- QA (audio 1): "El BSL y el SSL todavía salía como demasiado, con mucho ruido. Salían un montón."
- Refina `tasks/0027-bsl-ssl-band-cleanup.md` (✅ hecho): la banda agrupa al DIBUJAR, pero
  el cálculo base sigue generando cientos de niveles.

## Causa raíz (verificada)
`Market/Indicators/Liquidity.pm:33` usa profundidad de swing `k=1` (hipersensible): casi cada
vela confirma un swing → un BSL/SSL por swing consecutivo. La banda (0027) solo mitiga el render,
no la fuente. `_only_relevant` filtra eventos (sweep/grab/run) pero NO los NIVELES BSL/SSL dibujados.

## Objetivo
Que salgan MUCHOS MENOS niveles BSL/SSL, dejando solo los significativos, atacando la densidad en
el cálculo (no solo en el render).

## Enfoque (a implementar)
1. **Subir la profundidad de swing** de liquidez: parámetro `k` configurable, default más alto
   (probar `k=3` como en SMC, o exponerlo). `_is_swing_high`/`_is_swing_low` (257-281) ya usan `k`.
   Verificar que subir `k` no rompe la FSM de sweep/grab/run (que consume estos swings).
2. **Filtro de significancia de niveles**: además de subir `k`, descartar niveles BSL/SSL cuyo
   swing sea poco significativo (desplazamiento vs swing opuesto < factor·ATR), análogo a
   `_swing_significant` de Mxwll (`Indicators/Mxwll_Suite.pm:247-254`). Nuevo parámetro
   `level_atr_factor` (default ~1.0).
3. **Endurecer la banda** (opcional): revisar `band_atr` (default 0.5) en `Overlays/Liquidity.pm`;
   subirlo si tras (1)+(2) aún se aglomeran.

## Criterios de aceptación
- En 1m sobre el CSV, el número de niveles BSL/SSL activos baja drásticamente (orden de magnitud
  menos que hoy); solo quedan los de swings marcados.
- No se rompe la vinculación toma→nivel ni la FSM sweep/grab/run (los eventos siguen resolviendo).
- Toggles BSL/SSL y modo banda siguen funcionando.
- `prove -l t` verde; test nuevo/ampliado en `t/10-liquidity.t` que verifique: con `k` alto y
  `level_atr_factor` dado, una secuencia sintética produce N niveles esperados (pocos), y con k=1
  produce muchos (regresión de sensibilidad).

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/Indicators/Liquidity.pm && prove -l t/10-liquidity.t && prove -l t"
```
Requiere confirmación visual del arquitecto (captura antes/después).

## Qué no tocar
- CSV, MarketData, Market/Debug/.
- No cambiar la semántica de RUN/GRAB/SWEEP (solo su cantidad al haber menos niveles).
