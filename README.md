# Proyecto de Inteligencia Artificial y Aprendizaje Automático

- EPN - 2026A
- GR1SW
- Integrantes: Bryan Ayala, Juan Chugá, Sebastián Jibaja, Oscar Tamayo

## Tema: “Visualización de Datos mediante Motor de Charting usando la librería Tk”

Motor de gráficos financieros OHLCV en **Perl/Tk**, con indicadores y overlays de estructura
de mercado y sistema **Replay**. Base para la fase de ML (HMM / Viterbi) a fin de semestre.

**Producto oficial actual:** ver **`docs/PRODUCTO_OFICIAL.md`**  
(SMC Pro, Structures+FVG, HLD, ZigZag, Fib Retracement, Parallel Channel).

Código antiguo (Liquidity vieja, Mxwll, etc.) está **fuera de este repo**: **`docs/LEGACY.md`**.

## Estructura del proyecto (resumen)

- **`market.pl`** — punto de entrada; UI por pestañas; carga CSV y lanza el loop Tk.
- **`Data/`** — CSVs OHLCV (p. ej. `tv_nq1_15m.csv`, datasets junio/julio 2026).
- **`Market/`** — código modular:
  - **Datos:** `MarketData.pm`
  - **Indicadores oficiales:** ATR, SMC_Pro, SMC_Structures_FVG, HLD, ZigZag
  - **Drawing tools:** ParallelChannel, FibRetracement
  - **Render:** `ChartEngine.pm`, `Panels/*`, `Overlays/*`
  - **Replay / UI:** `ReplayController.pm`, `OverlayManager.pm`, `UI/*`
- **`docs/`** — SDD + material del profe + PRODUCTO_OFICIAL / LEGACY
- **`specs/`** / **`tasks/`** — requisitos e historia del curso
- **`t/`** — suite de tests del producto oficial

## Cómo empezar (agentes y desarrolladores)

1. Leer `AGENTS.md`.
2. Leer `docs/AI_CONTEXT.md` y `docs/CONSTITUTION.md`.
3. Estado de features: `tasks/README.md`.

```bash
# Suite de tests (WSL Fedora35):
wsl -d Fedora35 -- bash -lc "cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && prove -l t"

# App GUI (WSLg):
perl -I. market.pl
```
