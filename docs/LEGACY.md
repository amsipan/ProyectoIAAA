# Código legacy (no producto oficial)

Código del mes de desarrollo que **existía pero fallaba** o fue sustituido.  
Cuarentena: `legacy/Market/` y `t/legacy/`. **No cargar en ChartEngine ni market.pl.**

## Por qué se aisló

| Módulo | Problema histórico |
|--------|-------------------|
| **Liquidity** | Sweep/Grab/Run con pivotes propios o SMC ruidoso; profe/QA: basura, posiciones arbitrarias |
| **Mxwll Suite** | Profe: no fuente de verdad de estructura externa ni FVG |
| **SMC_Structures** (unificado) | Reemplazado por SMC Pro + Structures_FVG |
| **Strategy Builder** | No calibrado en el plan paso a paso actual |
| **Volume Profile** (app) | No es el ChartPrime OFF del ZZ; fase posterior |
| **Anchored VWAP** | Fase posterior (HLD anticipa VWAP para ATH) |

## Liquidity y TradingView

No hay captura del profe de un indicador “Liquidity Sweep/Grab/Run” 1:1.  
La fuente es el **PDF 2ª fase** + `maquina_estados_liquidez.png`.  
**No** reactivar `legacy/.../Liquidity.pm` creyendo que TV lo valida.

## Restaurar (solo si se rediseña)

1. No copiar el feed viejo `SMC → Liquidity` sin revisar pivotes.  
2. Preferir swings del **ZigZag externo** y/o **SMC Pro**.  
3. Plan + tests nuevos; luego mover de `legacy/` al árbol principal.
