# Proyecto de Inteligencia Artificial y Aprendizaje Automático

- EPN - 2026A
- GR1SW
- Integrantes: Bryan Ayala, Juan Chugá, Sebastián Jibaja, Oscar Tamayo

## Tema: “Visualización de Datos mediante Motor de Charting usando la librería Tk”

Motor de gráficos financieros OHLCV en **Perl/Tk**, con indicadores y overlays de estructura
de mercado y sistema **Replay**.

**Meta posterior del proyecto:** la app genera **observaciones limpias** (estructura + liquidez +
features) para entrenar **t-SNE → GMM → HMM**.

**Prioridad operativa actual:** terminar primero la reforma de indicadores. Punto de entrada:

### → [`docs/BRUJULA_CONTINUIDAD.md`](docs/BRUJULA_CONTINUIDAD.md) ← leer primero

**Memoria histórica completa:** [`docs/MEMORIA_RECUPERADA_019f6e8d.md`](docs/MEMORIA_RECUPERADA_019f6e8d.md)
**Meta ML posterior:** [`docs/PLAN_DEFINITIVO.md`](docs/PLAN_DEFINITIVO.md)
**Producto oficial actual (runtime):** [`docs/PRODUCTO_OFICIAL.md`](docs/PRODUCTO_OFICIAL.md)
(SMC Pro, Structures+FVG, HLD, ZigZag, Fib, Parallel Channel, **Liquidity v2 MVP**).

Código antiguo (Liquidity v1, Mxwll, etc.) está **fuera de este repo**: [`docs/LEGACY.md`](docs/LEGACY.md).

## Estructura del proyecto (resumen)

- **`market.pl`** — punto de entrada; UI por pestañas; carga CSV y lanza el loop Tk.
- **`Data/`** — CSVs OHLCV (p. ej. `tv_nq1_15m.csv`, datasets junio/julio 2026).
- **`Market/`** — código modular:
  - **Datos:** `MarketData.pm`
  - **Indicadores oficiales:** ATR, SMC_Pro, SMC_Structures_FVG, HLD, ZigZag, Liquidity
  - **Drawing tools:** ParallelChannel, FibRetracement
  - **Render:** `ChartEngine.pm`, `Panels/*`, `Overlays/*`
  - **Replay / UI:** `ReplayController.pm`, `OverlayManager.pm`, `UI/*`
- **`docs/`** — **PLAN_DEFINITIVO**, PRODUCTO_OFICIAL, LEGACY, material del profe, SDD
- **`specs/`** / **`tasks/`** — requisitos e historia del curso
- **`t/`** — suite de tests del producto oficial

## Cómo empezar (agentes y desarrolladores)

1. **`docs/BRUJULA_CONTINUIDAD.md`** — prioridad actual, checkpoint y prompt de rescate.
2. `AGENTS.md` — reglas y bootstrap del repo.
3. `docs/PRODUCTO_OFICIAL.md` — runtime real.
4. `docs/MEMORIA_RECUPERADA_019f6e8d.md` — historia completa cuando falte contexto.
5. `docs/PLAN_DEFINITIVO.md` — meta de modelos para después.
6. `docs/CONSTITUTION.md` y spec/task actual.

```bash
# Suite de tests (WSL Fedora35):
wsl -d Fedora35 -- bash -lc "cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && prove -l t"

# App GUI (WSLg):
perl -I. market.pl
```
