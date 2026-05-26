# Informe de cambios frente a `origin/main`

## Contexto

Se revisó el proyecto contra la última versión remota (`origin/main`) y contra los requisitos del documento base `Proyecto-Visualizacion-de-Datos-Parte1-v0.1.2.pdf`.

El documento exige una arquitectura modular en Perl/Tk con estas capas:

- Datos: `Market/MarketData.pm`
- Indicadores: `Market/IndicatorManager.pm`, `Market/Indicators/ATR.pm`
- Renderizado: `Market/ChartEngine.pm`, `Market/Panels/PricePanel.pm`, `Market/Panels/ATRPanel.pm`, `Market/Panels/Scales.pm`
- Aplicación: `market.pl`

También exige separación de responsabilidades, indicadores desacoplados, ejes independientes por panel, crosshair sincronizado, scroll horizontal, zoom, temporalidades de 1, 5 y 15 minutos, y evitar mezclar cálculo con renderizado, variables globales o acoplar indicadores al chart.

## Archivos modificados

Frente a `origin/main`, actualmente existen cambios en:

- `market.pl`
- `Market/ChartEngine.pm`
- `Market/MarketData.pm`
- `Market/IndicatorManager.pm`
- `Market/Indicators/ATR.pm`
- `Market/Panels/PricePanel.pm`
- `Market/Panels/ATRPanel.pm`
- `Market/Panels/Scales.pm`

## Cambios realizados

### 1. Corrección del cálculo de ATR por temporalidad

Antes, `market.pl` calculaba el ATR mientras iba leyendo cada vela de 1 minuto. Luego se construían las temporalidades de 5 y 15 minutos. Eso dejaba el ATR calculado principalmente sobre la serie original de 1 minuto, lo que podía producir desalineación cuando el usuario cambiaba a 5m o 15m.

Se cambió el flujo para:

1. Leer todas las velas del CSV.
2. Construir las temporalidades de 5m y 15m.
3. Seleccionar la temporalidad activa.
4. Calcular el ATR recorriendo explícitamente los índices de la serie activa.

También se modificaron:

- `IndicatorManager::update_last`
- `ATR::update_last`

para aceptar opcionalmente un índice de vela. Esto permite recalcular correctamente una serie completa de ATR para cualquier timeframe sin acoplar el indicador al motor visual.

Mejora aplicada:

- ATR consistente en `1m`, `5m` y `15m`.
- Mejor sincronización entre velas visibles y valores ATR.
- Mantiene indicadores desacoplados del chart, como exige el PDF.

Validación ejecutada:

```txt
1m candles=29888 atr_values=29875 last=2.93950394653257
5m candles=5978 atr_values=5965 last=8.81585328087976
15m candles=1993 atr_values=1980 last=21.5838627224824
```

### 2. Corrección de `get_slice` en `MarketData.pm`

Se robusteció `get_slice` para manejar:

- arrays vacíos,
- índices negativos,
- rangos fuera del tamaño disponible,
- casos donde `start > end`.

Antes, ciertos rangos inválidos podían provocar slices inconsistentes. Ahora devuelve un arreglo vacío cuando el rango no es válido.

Mejora aplicada:

- Evita errores de renderizado con ventanas fuera de rango.
- Mantiene la responsabilidad de validación dentro de la capa de datos.

### 3. Corrección del crosshair y eventos de mouse

En `ChartEngine.pm` existía una llamada a `on_mouse_move`, pero el método implementado realmente era `_on_mouse_move`. Eso impedía que el crosshair funcionara correctamente con los eventos de Tk.

Se corrigió para usar `_on_mouse_move` y se cambió el binding de eventos para capturar:

- movimiento del mouse,
- click izquierdo,
- arrastre con click izquierdo mantenido,
- liberación del click,
- rueda del mouse,
- salida del panel.

Además, durante el drag se llama también a `_on_mouse_move`, de modo que el crosshair sigue actualizándose mientras el usuario arrastra el gráfico.

Mejora aplicada:

- Crosshair vertical sincronizado entre el panel de precios y el panel ATR.
- Línea horizontal solo en el panel activo, evitando interpretar la coordenada Y de un panel con la escala del otro.
- Mejor comportamiento tipo TradingView durante drag.

### 4. Scroll horizontal mediante drag

Se agregó soporte de arrastre horizontal con click izquierdo.

El desplazamiento usa la coordenada global del puntero (`pointerx`) para reducir saltos al mover el mouse entre paneles. Ambos paneles comparten el mismo `offset` y `visible_bars`, por lo que el panel de precios y el panel ATR permanecen sincronizados temporalmente.

Mejora aplicada:

- Navegación horizontal del histórico.
- Sincronización temporal entre múltiples paneles.
- Cumple el requisito de scroll horizontal indicado en el PDF.

### 5. Eje temporal visible

`ChartEngine.pm` ahora llama a `draw_time_axis` después de renderizar el panel de precios.

Además, `get_all_timestamps` parsea timestamps con `Time::Moment`, permitiendo generar etiquetas de tiempo `HH:MM` para el eje X.

Mejora aplicada:

- El eje horizontal de tiempo ya se dibuja explícitamente.
- Las etiquetas se calculan desde los timestamps reales de las velas visibles.

### 6. Render diferido

`request_render` ahora evita renderizados redundantes usando `afterIdle` y un flag `render_pending`.

Mejora aplicada:

- Reduce llamadas repetidas a `render` durante eventos rápidos.
- Mejora la estabilidad al mover mouse, hacer scroll o arrastrar.

### 7. Ajustes menores de panel ATR y escalas

En `ATRPanel.pm`:

- La línea ATR ahora usa `index_to_center_x`, para alinear los puntos al centro de cada vela.
- El crosshair usa el tamaño real del canvas en lugar de atributos inexistentes como `$self->{width}` o `$self->{height}`.

En `Scales.pm`:

- Se mantiene la transformación básica índice→X y valor→Y, respetando la separación entre coordenadas de datos y coordenadas de pantalla.

## Cumplimiento del PDF base

### Cumple actualmente

- Arquitectura modular en las cuatro capas solicitadas.
- Separación entre datos, indicadores, renderizado y aplicación.
- Velas OHLC renderizadas en `PricePanel.pm`.
- Panel ATR separado en `ATRPanel.pm`.
- Escalas verticales independientes por panel.
- Temporalidades de 1, 5 y 15 minutos.
- Indicador ATR desacoplado del chart.
- Crosshair sincronizado en X entre paneles.
- Scroll horizontal por drag.
- Eje temporal visible.
- No se agregaron variables globales.
- No se mezcló cálculo de indicadores dentro del renderizado.
- No se acopló el indicador ATR al chart.
- No se agregaron librerías externas fuera de las ya contempladas por el documento y el proyecto (`Tk`, `Time::Moment`).

### Pendiente conocido

El zoom horizontal con la rueda del mouse todavía presenta un problema visual: al usar la rueda, el gráfico puede desacoplarse del encuadre visual del panel principal. Específicamente, el contenedor del gráfico y el eje temporal pueden aparentar desplazarse o descuadrarse respecto al área esperada.

Por lo tanto, aunque el zoom existe, todavía no cumple completamente el comportamiento esperado tipo TradingView. Queda pendiente corregir el zoom para que:

- solo modifique la densidad horizontal de velas,
- no afecte el encuadre vertical,
- no desplace visualmente el eje de fechas,
- mantenga el marco del panel estable.

## Validaciones ejecutadas

Se ejecutaron validaciones en Fedora35 dentro de WSL.

### Sintaxis Perl

```txt
market.pl syntax OK
Market/MarketData.pm syntax OK
Market/IndicatorManager.pm syntax OK
Market/Indicators/ATR.pm syntax OK
Market/Panels/Scales.pm syntax OK
Market/Panels/PricePanel.pm syntax OK
Market/Panels/ATRPanel.pm syntax OK
Market/ChartEngine.pm syntax OK
```

### Prueba lógica de temporalidades y ATR

```txt
1m candles=29888 atr_values=29875 last=2.93950394653257
5m candles=5978 atr_values=5965 last=8.81585328087976
15m candles=1993 atr_values=1980 last=21.5838627224824
```

### Smoke test de aplicación

La aplicación inicia, lee datos, construye temporalidades, abre Tk y ejecuta el render inicial.

Nota: al ejecutar con `timeout` para pruebas automáticas, WSLg/Tk puede emitir un `X Error` al matar la ventana forzosamente. Eso no corresponde necesariamente a un error lógico de la aplicación, sino al cierre abrupto del proceso gráfico.

## Conclusión

Los cambios actuales mejoran la corrección funcional del proyecto frente a `origin/main`, especialmente en:

- cálculo correcto del ATR por temporalidad,
- scroll horizontal,
- crosshair sincronizado,
- eje temporal,
- render diferido,
- robustez de slices de datos.

El proyecto cumple la mayor parte de los requisitos del PDF base y respeta sus prohibiciones principales. Sin embargo, queda documentado como pendiente que el zoom con rueda del mouse todavía no replica correctamente el comportamiento de TradingView porque puede desacoplar visualmente el gráfico del encuadre.
