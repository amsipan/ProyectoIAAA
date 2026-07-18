# Spec 0013: Paridad SMC TradingView (Neon + Structures/FVG)

## Objetivo

Reemplazar el híbrido SMC/Mxwll por dos capas equivalentes a:

1. **SMC Pro [Neon]** — config de captura del profe  
2. **SMC Structures and FVG** (LudoGH68) — config de captura del profe  

Paridad visual con la misma data CSV para comparar con TradingView.

## Packages

- `Market::Indicators::SMC_Pro` + `Market::Overlays::SMC_Pro` (tag `ov_smc_pro`)
- `Market::Indicators::SMC_Structures_FVG` + `Market::Overlays::SMC_Structures_FVG` (tag `ov_smc_fvg`)

Registro ChartEngine: `smc_pro`, `smc_fvg`.  
Eliminar registro activo `mxwll` y el antiguo `smc` híbrido.

## Defaults = capturas (no defaults Pine)

### SMC Pro

- Historical; swing labels ON; strong/weak ON  
- Internal structure ON (size 5); swing structure ON (length 50)  
- Internal OB OFF; Swing OB ON count 5; ATR filter; mit High/Low  
- EQH/EQL ON bars 3 thr 0.1  
- FVG Pro OFF  
- Daily/Weekly/Monthly H/L ON  

### Structures + FVG (LudoGH68) — captura profe

- Display FVG **ON**; Reduce mitigated **ON**; Number of FVG **5**  
- Break with candle's body **OFF**; Display current structure **OFF**  
- BOS bull/bear **gray**; CHoCH bull **green** / bear **red**; width **1**  
- Number of breaks **10**; all Structure Fibonacci levels **OFF**  
- Source: `docs/reference_indicators/smc_structures_and_fvg_ludogh68.txt`  
- Runtime: `Market::Indicators::SMC_Structures_FVG` + `Overlays::SMC_Structures_FVG`  
- **No** usar `SMC_Structures` legacy ni FVG de Mxwll/SMC Pro para esta capa  

## UI

Toggles: **SMC Pro** | **SMC Structures+FVG**.  
Sin pestaña Mxwll. Sin density filter en estas capas (100% para paridad TV).

## Criterios de aceptación

- Tests unitarios de pivotes/eventos/OB/FVG  
- UI sin Mxwll  
- Misma geometría estructural en swings clave vs TV (checklist manual)
