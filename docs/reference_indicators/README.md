# Referencias TradingView / código fuente de indicadores

Textos **originales** de indicadores de TradingView (Pine Script) usados como
referencia para portar a Perl (`Market/Indicators/`, `Market/Overlays/`).

**Única ubicación canónica** de estos sources en el repo.

Última organización: 2026-07-17 (SMC Pro Neon + Structures/FVG LudoGH).

## Inventario

| Archivo | Origen | Módulo Perl | Config canónica |
|---------|--------|-------------|-----------------|
| `smc_pro_neon.txt` | Smart Money Concepts Pro [Neon] (LuxAlgo lineage, v6) | `SMC_Pro` | Captura `docs/material_profesor/capturas_config/smc_pro_neon_config.jpg` |
| `smc_structures_and_fvg_ludogh68.txt` | SMC Structures and FVG (LudoGH68, MPL-2.0) | `SMC_Structures_FVG` | Captura `.../smc_structures_and_fvg_config.jpg` |
| `luxalgo_smc.txt` | LuxAlgo Smart Money Concepts v5 (clásico) | lectura / paridad histórica | — |
| `mxwll_suite.txt` | Mxwll Capital | **deprecado en producto** (no calibrar estructura) | — |
| `diy_custom_strategy_builder_zp.txt` | ZP DIY Custom Strategy Builder | `Strategy_Builder` | (fase posterior) |
| `zigzag_mtf_fibonacci_lonesometheblue.txt` | LonesomeTheBlue ZigZag MTF + Fib | `ZigZag` | (fase posterior) |
| `zigzag_volumeprofile_chartprime.txt` | ChartPrime ZigZag Volume Profile | `VolumeProfile` / `ZigZag` | (fase posterior) |

## Regla de configuración

Los **defaults del Pine no mandan**. Mandan las **capturas del profesor**.
Ejemplo: en LudoGH, `Reduce mitigated FVG` default es `false` en el source, pero
en la captura del profe está **ON**.

## Licencias

CC BY-NC-SA / MPL-2.0 según cada script. Uso académico de referencia.
