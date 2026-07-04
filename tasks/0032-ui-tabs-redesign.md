# Task 0032: Rediseño de la barra de controles con pestañas

## Origen
- Reporte del usuario (03/07): al abrir la app, los botones de la barra inferior
  se salen de la pantalla; hay más controles de los que se ven (la fila `Mxwll:`
  queda cortada a la derecha).
- El profe sugirió un menú para ahorrar espacio; el usuario prefiere pestañas
  desplegables tras una experiencia previa mala con menú.

## Objetivo
Que ningún control se salga de la pantalla, organizando la barra en pestañas.

## Estado: HECHO (2026-07-03, 799 tests PASS)
Rediseño en `market.pl` (sección barra de controles):
- FILA SUPERIOR (siempre visible): selector TF (lo más usado) + botones de
  pestaña (Radiobutton `-indicatoron=>0`).
- FILA INFERIOR: un solo panel visible a la vez, según la pestaña activa.
- Pestañas: **Capas** (SMC/Liquidez/Estrategia/Perfil Vol/VWAP/Mxwll + HTF),
  **Liq** (BSL/SSL/EQH/EQL/SWEEP/GRAB/RUN), **Mxwll** (Estr/Swings/OB/FVG/AOE/
  Fibs), **Escala** (Precio/ATR Auto-Manual + Reset Vista), **Replay** (7 botones).
- Implementado con Frames + pack/packForget (patrón "notebook manual"). NO se usa
  menubar nativo, Optionmenu ni Tk::NoteBook: bajo WSLg abren ventanas X aparte y
  fallan (misma razón documentada en task 0018b).
- Sin cambios en callbacks (los mismos de antes; cobertura en t/17 intacta).

## Criterios de aceptación
- Ningún control se corta en pantalla al abrir con la ventana maximizada.
- Cambiar de pestaña muestra/oculta el panel correcto sin reabrir ventanas.
- TF siempre accesible sin cambiar de pestaña.
- Toda la funcionalidad previa sigue disponible.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '<repo>' && perl -I. -c market.pl && prove -l t"
```
Validación visual: `perl market.pl` en Fedora35 (WSLg) y probar cada pestaña.

## Qué no tocar
- No usar menubar nativo / Optionmenu / Tk::NoteBook (fallan en WSLg).
- No cambiar los callbacks ni la lógica de overlays.
