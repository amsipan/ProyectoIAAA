# Task 0050: Replay — atajos de teclado (DIFERIDO)

**Estado:** ⏸ diferido por Bryan (2026-07-05). "Tal vez faltarían los atajos de teclado pero lo
dejaremos para luego". Anotado para no perderlo. NO empezar sin autorización.

## Referencia
- `docs/TRADINGVIEW_BAR_REPLAY_REFERENCE.md` §7 (atajos oficiales TradingView).
- Depende de 0046 (toggle Play/Pause y step forward ya cableados).
- Originalmente parte de 0046; se separó porque Bryan lo dejó para después.

## Objetivo
Atajos de teclado oficiales del Bar Replay, activos solo con el modo replay ON:
- `Shift+↓` → toggle Play/Pause.
- `Shift+→` → step forward (una vela / un intervalo).

## Precedencia crítica (no romper Select Bar)
- Con `_replay_select_mode` ON: `Shift+←/→` SIGUEN moviendo la vela seleccionada (0042). NO tocar.
- Con replay activo y NO en select mode: `Shift+→` avanza el replay un paso.
- Documentar la precedencia en el código y en el test.

## Notas de implementación (heredar lecciones)
- API Tk Fedora35 (0049): usar `$w->Tk::bind($seq,$cb)` sin modo `'+'`; desbindear con
  `$w->Tk::bind($seq,'')` al salir del replay. Bind en la ventana o en los canvas de precio/ATR.
- Instalar los binds al entrar en replay, quitarlos al salir (reusar la limpieza de 0040/0046).
- ASCII/estética: no aplica (sin UI nueva).

## Criterios de aceptación
- `Shift+↓` alterna autoplay; `Shift+→` avanza un paso; ninguno interfiere con Select Bar.
- Al salir del replay los binds se retiran (no quedan atajos huérfanos).
- `prove -l t` verde; test en `t/17-ui-wiring.t` o `t/25-replay-select-bar.t`: precedencia de
  `Shift+→` según modo (select vs replay-activo).

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c market.pl && perl -I. -c Market/UI/Callbacks.pm && prove -l t"
```
**OBLIGATORIO (0049):** arrancar la app real y probar los atajos en runtime; `perl -c` + mocks no
detectan errores de bind de Tk.

## Qué no tocar
- No romper Select Bar (0042) ni sus atajos `Shift+←/→`.
- No romper el toggle Play/Pause ni el step de 0046.
