# Task 0044: Replay — menú "Go to" (Select bar / Date / Random / First available)

## Referencia
- `docs/TRADINGVIEW_BAR_REPLAY_REFERENCE.md` §4, §19 captura 3.
- Depende de 0043 (panel flotante). Disparador: botón `v` del panel (callback `goto_menu`).

## CRITERIO FIJO (heredado de 0048)
Etiquetas ASCII legibles, **NO glyphs unicode** (la fuente de Tk en Fedora35 no los tiene → mojibake).
Filas del menú: `Bar`, `Date...`, `First available date`, `Random bar` (prefijo ASCII opcional tipo
`| Bar`). Título del dropdown: `SELECT STARTING POINT`. Nada de `▾ ▷ ✂` etc. en el UI.

## Objetivo
Calcar el dropdown "SELECT STARTING POINT" (captura 3) con 4 opciones:
- **Bar** — entra en modo selección manual (tijeras, 0042).
- **Date…** — pide una fecha/hora y salta a la vela más cercana.
- **First available date** — salta a la primera vela con datos (índice 0).
- **Random bar** — punto de inicio aleatorio dentro del rango disponible.

## Estado actual
- Solo existe "Select Bar" (activa el modo selección). No hay Date/First/Random.

## Diseño
1. **Dropdown:** Frame flotante posicionado con `place` justo encima del botón `v` del panel
   (sin `Optionmenu`). Título gris "SELECT STARTING POINT" + 4 filas clicables con etiqueta ASCII.
   Se cierra al elegir o al hacer click fuera (bind `<Button-1>` global temporal).
2. **Callbacks nuevos en `Market/UI/Callbacks.pm`:**
   - `make_replay_goto_bar` → `set_replay_select_mode(1)` (modo tijeras).
   - `make_replay_goto_first` → inicio en índice 0: `_replay_begin($chart, 0)` (respeta selected-1:
     ojo, con índice 0 el inicio efectivo se clampa a 0). Documentar.
   - `make_replay_goto_random` → índice aleatorio en `[MIN_VISIBLE_BARS, last_index-1]`;
     `_replay_begin($chart, $rand)`. Semilla por defecto del sistema.
   - `make_replay_goto_date` → prompt de fecha simple (Tk `DialogBox` con Entry, formato
     `YYYY-MM-DD` o `YYYY-MM-DDTHH:MM`); buscar la vela con timestamp más cercano vía
     `MarketData` (búsqueda lineal o binaria sobre timestamps) y `_replay_begin` en ese índice.
     `ponytail:` Entry de texto basta; calendario gráfico queda fuera de alcance (plan §fuera).
3. **Búsqueda de vela por fecha:** añadir helper `index_for_timestamp($ts)` si no existe en
   ChartEngine/MarketData (buscar el más cercano por epoch). Si `MarketData` ya expone algo
   equivalente, reusarlo; si no, implementarlo en ChartEngine consumiendo `get_timestamp`.
4. Todas las opciones dejan el chart en modo replay listo para Play (excepto Bar, que espera click).

## Criterios de aceptación
- El menú muestra las 4 opciones con el layout de la captura 3.
- **Bar:** entra en modo selección (tijeras).
- **First available date:** replay arranca en la primera vela.
- **Random bar:** replay arranca en una vela aleatoria válida (distinta entre llamadas, salvo azar).
- **Date…:** dada una fecha, el inicio queda en la vela de timestamp más cercano.
- `prove -l t` verde; test en `t/25-replay-select-bar.t`: `index_for_timestamp` devuelve el índice
  más cercano; random cae en rango válido; first = 0.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c market.pl && perl -I. -c Market/UI/Callbacks.pm && perl -I. -c Market/ChartEngine.pm && prove -l t/25-replay-select-bar.t t"
```
Validación visual en WSLg (comparar con captura 3).

## Qué no tocar
- No romper el modo selección manual (0042) ni el truncado por replay_idx.
- Calendario gráfico completo queda fuera (mejora futura).
