# Referencias TradingView / código fuente de indicadores

Textos **originales** de indicadores de TradingView (lenguaje **Pine Script**) que el
profesor autorizó usar como referencia para portar funcionalidad a Perl
(`Market/Indicators/`, `Market/Overlays/`).

Se guardan como **`.txt`** (texto plano), igual que cuando los exportaste/copiaste.
No hace falta otra extensión: Pine Script es código en texto; TradingView a veces usa
la extensión informal `.pine`, pero es lo mismo.

**Única ubicación canónica** de estos sources en el repo.

Última organización: 2026-07-08.

## ¿Qué es “Pine” entonces?

- **Pine Script** = el lenguaje de programación de indicadores de TradingView.
- El archivo es solo el código fuente (líneas que empiezan con `//@version=…`,
  `indicator(...)`, etc.).
- En este proyecto los guardamos como **`.txt`** para abrirlos fácil en cualquier editor.

## Inventario

| Archivo | Origen (autor / script TV) | Módulo Perl relacionado |
|---------|----------------------------|-------------------------|
| `luxalgo_smc.txt` | LuxAlgo — Smart Money Concepts | `SMC_Structures` (+ partes Liq/Mxwll) |
| `mxwll_suite.txt` | Mxwll Capital — Mxwll Suite | `Mxwll_Suite` |
| `diy_custom_strategy_builder_zp.txt` | ZP (@ZPayab) — DIY Custom Strategy Builder | `Strategy_Builder` |
| `zigzag_mtf_fibonacci_lonesometheblue.txt` | LonesomeTheBlue — ZigZag MTF + Fibonacci | `ZigZag` / Fib |
| `zigzag_volumeprofile_chartprime.txt` | ChartPrime — ZigZag Volume Profile | `VolumeProfile` / `ZigZag` |

## Cómo añadir un source nuevo

1. Copiar el código completo desde TradingView a un `.txt`.
2. Guardarlo **solo aquí**, nombre estable en ASCII: `autor_nombre_corto.txt`.
3. Añadir una fila a la tabla de arriba.
4. No dejar copias en `Downloads/` ni en `docs/material_profesor/`.

## Licencias

Varios scripts son MPL-2.0 / CC BY-NC-SA. Uso académico de referencia; no republicar
como producto comercial sin revisar la licencia del original.
