# Proyecto de Inteligencia Artificial y Aprendizaje Automático

- EPN - 2026A
- GR1SW
- Integrantes: Bryan Ayala, Juan Chugá, Sebastián Jibaja, Oscar Tamayo

## Tema: “Visualización de Datos mediante Motor de Charting usando la librería Tk”

Motor de gráficos financieros OHLCV en **Perl/Tk**, con indicadores y overlays de estructura
de mercado (SMC, liquidez, strategy builder, volume profile, VWAP, etc.) y sistema **Replay**.
Base de visualización para la fase de ML (HMM / Viterbi tensorial) a fin de semestre.

Documentación de desarrollo (estado, arquitectura, tasks): ver **`AGENTS.md`** y **`docs/`**.

## Estructura del proyecto (resumen)

- **`market.pl`** — punto de entrada; UI por pestañas; carga CSV y lanza el loop Tk.
- **`Data/`** — CSVs OHLCV (`2026_03.csv` principal; también datasets de junio/julio 2026).
- **`Market/`** — código modular en capas:
  - **Datos:** `MarketData.pm` (OHLCV, timeframes 1m…W, slicing).
  - **Indicadores (cálculo, sin Tk):** `Indicators/*` (ATR, SMC, Liquidity, Strategy_Builder,
    VolumeProfile, AnchoredVWAP, Mxwll_Suite, ZigZag).
  - **Render:** `ChartEngine.pm`, `Panels/*`, `Overlays/*`, `Scales.pm`.
  - **Replay / UI:** `ReplayController.pm`, `OverlayManager.pm`, `UI/*`.
  - **Debug (arquitecto):** `Debug/*`.
- **`docs/`** — SDD (`AI_CONTEXT`, `ARCHITECTURE`, `CONSTITUTION`, `ROADMAP`, …).
- **`specs/`** / **`tasks/`** — requisitos y unidades de trabajo.
- **`t/`** — suite `prove -l t` (Test::More, sin GUI).

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
