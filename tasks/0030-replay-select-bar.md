# Task 0030: Replay — seleccionar vela de inicio (Select Bar)

## Origen
- ORDEN 18 de `tasks/0021-volatility-and-choch-noise.md`.
- Notas WhatsApp profe (29/06): "Elegir una vela y de ahí que haga play";
  "Replay debe haber un botón que diga select bar"; "Shift+flecha se puede ir
  cambiando las velas"; "la vela seleccionada no se cuenta, sino que empieza una
  antes" (Sebas).

## Objetivo
Permitir al usuario elegir la vela desde la cual arranca el Replay (en vez de un
punto automático), con un botón "Select Bar", ajuste fino por Shift+flechas, y
que el replay comience en (vela_seleccionada - 1).

## Estado verificado (02/07)
- `Market/UI/Callbacks.pm` `make_replay_start`: hoy arranca AUTOMÁTICO en
  `last_index - visible_bars` (clamp >=0). No hay selección de vela.
- `Market/ReplayController.pm`: `start($idx)` ya acepta un índice inicial con
  clamp a `[0, last_index]`. La infraestructura para arrancar en un índice
  arbitrario YA existe; falta la UI/interacción para elegirlo.
- ChartEngine ya tiene binds de eventos (crosshair, zoom, drag) donde se podría
  enganchar un click de selección.

## Diseño
- Modo "Select Bar":
  1. Botón nuevo "Select Bar" en la barra de Replay (`market.pl`).
  2. Al activarlo, el siguiente click en el chart fija la vela seleccionada
     (usar el índice bajo el crosshair, que ya se calcula).
  3. Shift+Left/Right mueven la vela seleccionada ±1 (bind de teclas en
     ChartEngine cuando el modo está activo).
  4. Un marcador visual (línea vertical) indica la vela seleccionada.
  5. Al pulsar Play/Inicio, `start(selected - 1)` (la seleccionada no se cuenta,
     empieza una antes, según Sebas).
- Estado nuevo en ChartEngine: `_replay_select_mode`, `_selected_bar`.
- Reusar `ReplayController->start($idx)` existente.

## Criterios de aceptación
- Botón "Select Bar" visible en la barra de Replay.
- Click selecciona vela; Shift+flechas la ajustan ±1; marcador visible.
- Play arranca en (seleccionada - 1).
- No rompe el Replay actual (Inicio/Play/Pause/step/fast-fwd/Salir) ni Fase 1.
- Tests headless del cableado (callback de select, start en selected-1).

## Pendiente de confirmar
- ¿La selección es por click en el chart, o por navegación con teclado desde una
  vela por defecto? El profe menciona ambas (click + shift+flecha). Implementar
  las dos si es viable.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/ReplayController.pm && perl -I. -c Market/UI/Callbacks.pm && perl -I. -c Market/ChartEngine.pm && perl -I. -c market.pl && prove -l t/12-replay.t t/17-ui-wiring.t"
```

## Qué no tocar
- No romper los controles de Replay existentes ni el índice-tope (replay_idx).
- Selección/teclas deben estar acotadas al modo Select Bar (no interferir con
  crosshair/zoom normales).
