# Task 0020: Anclaje de temporalidades a sesión CME/TradingView

## Spec relacionada

- `specs/0001-temporalidades-extendidas.md`
- `specs/0000g-time-axis-global-cadence-tradingview.md`
- Observación beta visual contra TradingView NQ1!/CME en zona UTC-5.

## Objetivo

Corregir la agregación de temporalidades superiores para que las velas respeten el anclaje de sesión de futuros CME usado por TradingView/Supercharts en NQ:

- sesión local UTC-5 inicia a las **17:00**;
- 2h queda anclado a `17:00, 19:00, 21:00, 23:00, 01:00, ...`;
- 3h observado en TradingView queda anclado a `17:00, 20:00, 23:00, 02:00, ...` (aunque no sea TF oficial de la UI);
- 4h queda anclado a `17:00, 21:00, 01:00, ...`;
- D agrupa por día de trading CME: `17:00` del día calendario anterior hasta antes del cierre de la sesión del día de trading.

## Archivos probablemente relevantes

- `Market/MarketData.pm`
- `t/11-timeframes.t`
- `tasks/README.md`

## Pasos

1. Mantener 1m/5m/15m por fronteras de reloj existentes.
2. Cambiar la agregación intradía >= 1h para calcular buckets desde el inicio de sesión local `17:00`, no desde medianoche. Para 1h el resultado visible sigue siendo cada hora; para 2h/4h cambia la fase a TradingView.
3. Para D, usar fecha de trading: si la vela local es `>= 17:00`, pertenece al día de trading siguiente; si es `< 17:00`, pertenece al día calendario actual. El timestamp del bucket diario se conserva como `YYYY-MM-DDT00:00:00-05:00` de la fecha de trading para que el eje diario siga etiquetando fechas, no horas de apertura.
4. Para W, aplicar el mismo día de trading antes de truncar al lunes ISO, de modo que el domingo 17:00 pertenezca a la semana de trading que empieza el lunes siguiente.
5. Añadir regresiones para los buckets 2h/180m/4h y D/W de sesión.

## Criterios de aceptación

- `_bucket_timestamp('2026-04-06T01:30:00-05:00', '2h')` devuelve `2026-04-06T01:00:00-05:00`.
- `_bucket_timestamp('2026-04-06T02:30:00-05:00', 180)` devuelve `2026-04-06T02:00:00-05:00`.
- `_bucket_timestamp('2026-04-06T01:30:00-05:00', '4h')` devuelve `2026-04-06T01:00:00-05:00`.
- `_bucket_timestamp('2026-04-06T17:30:00-05:00', 'D')` devuelve `2026-04-07T00:00:00-05:00`.
- No se rompe 1m/5m/15m ni la agregación OHLCV existente.

## Comandos de verificación

```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/MarketData.pm && prove -l t/11-timeframes.t && prove -l t"
```

## Qué no tocar

- `Data/2026_03.csv`.
- `Market/Debug/`.
- La lista oficial de timeframes de la UI, salvo confirmación humana para añadir 3h como botón visible.
