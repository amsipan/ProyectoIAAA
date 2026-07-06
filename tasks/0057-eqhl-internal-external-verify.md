# Task 0057: EQH/EQL interno vs externo — verificar y garantizar render en runtime

## Estado
✅ HECHO + VERIFICADO arquitecto (2026-07-05). Diagnóstico/fix mínimo delegado a grok composer-2.5-fast;
arquitecto verificó tests y captura WSLg. 1237 PASS.

Diagnóstico:
- Los internos ya estaban activos por default (`eqhl_int_size=2`) y ChartEngine no los desactivaba.
- El cálculo emitía `EQH/EQL` externos e `I-EQH/I-EQL` internos, pero en pantalla la nomenclatura
  `I-*` podía pasar desapercibida para QA/profe.

Fix:
- Render ahora muestra etiquetas explícitas `EQH EXT`, `EQL EXT`, `EQH INT`, `EQL INT`.
- Internos mantienen línea dashed/tenue; externos sólidos.
- Tests cubren emisión de tipos internos/externos y render de etiquetas/estilo.
- Verificación visual WSLg: `C:\Users\ASUS ROG\AppData\Local\Temp\opencode\0057_eqhl_internal_external.png`.

## Origen
- `docs/FEEDBACK_PROFESOR_QA_2026-07-05.md` punto 7, audio 1.
- Profe (lista): "Distinguir entre EQL y EQH interno y externo."
- QA (audio 1): "Lo del EQL y EQH interno, eso no está puesto. Yo no vi en ningún momento en el
  programa que decía EQL/EQH interno o externo."

## Estado en código (verificado)
El cálculo YA distingue interno/externo (`Market/Indicators/Liquidity.pm`, `_update_eqhl_leg`):
externo `eqhl_size=3` → etiquetas `EQH`/`EQL`; interno `eqhl_int_size=2` → `I-EQH`/`I-EQL`
(constructor 39-47). El render está en `Overlays/Liquidity.pm` `_draw_pair_line` (463-515):
externos sólido, internos entrecortado. → El código existe pero el QA NO lo ve en la app.

## Objetivo
Confirmar por qué no se ven los internos en runtime y garantizar que EQH/EQL internos y externos
aparecen y se distinguen visualmente (etiqueta y estilo de línea claros).

## Enfoque (diagnóstico primero — arquitecto ejecuta en app real)
Posibles causas a descartar, en orden:
1. `eqhl_int_size` efectivo = 0 (desactivado) por config en `market.pl`/ChartEngine → activar.
2. Toggle de EQH/EQL en el panel Liq apaga ambos y no hay sub-toggle interno → revisar UI.
3. Los internos se calculan pero con tolerancia/tamaño que casi nunca dispara en los datos reales.
4. Etiqueta `I-EQH`/`I-EQL` se dibuja pero tapada/fuera de viewport/color igual al fondo.
5. Nomenclatura: el profe espera ver la distinción explícita (quizá "EQH int"/"EQH ext").

## Criterios de aceptación
- En la app real (captura del arquitecto) se ven EQH/EQL externos E internos, distinguibles por
  estilo (sólido vs entrecortado) y por etiqueta.
- Si faltaba activarlos, quedan activos por default con densidad razonable (no ruido).
- `prove -l t` verde; test que verifique que, dada una secuencia con pares equales internos y
  externos, el indicador emite ambos tipos con sus etiquetas.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/Indicators/Liquidity.pm && perl -I. -c Market/Overlays/Liquidity.pm && prove -l t/10-liquidity.t && prove -l t"
```
OBLIGATORIA verificación visual del arquitecto (el QA reporta ausencia en pantalla).

## Qué no tocar
- CSV, MarketData, Market/Debug/.
