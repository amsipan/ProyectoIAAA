# Plan de implementación — Calque del Bar Replay de TradingView

> Arquitecto: convierte `docs/TRADINGVIEW_BAR_REPLAY_REFERENCE.md` (referencia UX + 5 capturas
> del usuario, sección 19) en tareas ejecutables. Objetivo: que el Replay se vea y funcione
> **igual que TradingView**.

## Estado de partida (jul 2026)
- **Backend OK:** `ReplayController` con `start/play/pause/step_forward/step_backward/fast_forward/exit`,
  truncado por `replay_idx` sin fuga de futuro (0015/0038), estado limpio tras salir/cambiar TF (0040).
- **UI actual:** fila de botones en pestaña Replay (`Select Bar, Inicio, Play, Pause, <, >, >>, Salir`).
- **Falta:** panel flotante media-player, modo selección automático, cursor tijeras + línea azul +
  etiqueta `Re:`, velo blanco sobre velas futuras, menú Go-to (Bar/Date/Random/First), dropdown de
  velocidad (9 valores), dropdown de intervalo, Play/Pause toggle, Jump-to-real-time, atajos Shift+↓/→.

## Decisiones fijadas (no re-abrir sin el usuario)
- **Semántica de inicio:** se conserva `selected - 1` (requisito del profe). NO cambiar a "vela
  clickeada = inicio" sin confirmación. La UI puede parecerse a TV aunque el índice interno reste 1.
- **Step back (`<`):** se conserva como extra propio (TV no lo tiene). No se elimina.
- **Restricciones EPN:** nada de `Tk::NoteBook`, `Optionmenu`, menubar nativo. Solo Frames +
  pack/packForget/place. Los dropdowns se hacen con un `Toplevel` sin borde o Frame flotante + place.
- **Un solo TF de datos:** el intervalo de replay se limita a lo que `MarketData` puede servir
  (1m..D/W ya existentes). No inventar resoluciones nuevas.

## Tareas (orden de ejecución)

| # | Task | Depende | Riesgo |
|---|------|---------|--------|
| 0041 | Backend velocidad (9 multiplicadores) + intervalo de replay | — | bajo |
| 0042 | Modo selección visual: auto-entrar, cursor tijeras, línea azul, etiqueta `Re:`, velo blanco | — | medio |
| 0043 | Panel flotante media-player (layout TradingView) reemplaza fila de botones | 0041 | medio |
| 0044 | Menú Go-to (Select bar / Date… / Random bar / First available date) | 0043 | medio |
| 0045 | Dropdown velocidad + dropdown intervalo cableados al backend | 0041,0043 | bajo |
| 0046 | Play/Pause toggle + Jump-to-real-time + atajos Shift+↓/→ + marca de agua "Replay" | 0043 | bajo |

**Orden recomendado:** 0041 → 0042 → 0043 → 0044 → 0045 → 0046.
0041 y 0042 son independientes y se pueden hacer en cualquier orden; 0043 debe ir antes de 0044/0045/0046.

## Fuera de alcance (baja prioridad, NO en este lote)
- Sesión Continue/Start new al reabrir (TV oct 2025).
- Multi-chart sync.
- Replay Trading (panel P&L, Buy/Sell).
- Select date con calendario gráfico completo (en 0044 basta un prompt de fecha simple; el calendario
  visual queda como mejora futura).

## Regla de verificación (todas las tasks)
Cada task: `perl -I. -c` de archivos tocados + `prove -l t` COMPLETO verde + test propio en `t/`.
Los cambios de UI que no se puedan testear headless se cubren con test de la lógica subyacente
(estado, cálculo de posición del velo, mapeo velocidad→ms) + validación visual del usuario en WSLg.
