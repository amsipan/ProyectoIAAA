# Código legacy — FUERA del repositorio GitHub

## Ubicación en disco (acceso local, no git)

```
C:\ia\proyecto_iaaa\Proyecto\ProyectoIAAA_LEGACY_ARCHIVE\
```

| Contenido | Ruta en el archivo |
|-----------|-------------------|
| Módulos antiguos | `legacy/Market/Indicators/`, `legacy/Market/Overlays/` |
| UI legacy (hline last-price) | `legacy/Market/Panels/last_price_hline_legacy.pm` |
| Tests antiguos | `t_legacy/` |
| Nota de extracción | `README.md` en la raíz del archivo |

**No está en GitHub.** El repo de producto solo documenta esta ruta.

## Qué hay ahí (histórico, no usar en runtime)

- Liquidity (BSL/SSL, Sweep/Grab/Run) — mal calibrado / pivotes dudosos  
- Mxwll Suite  
- Strategy Builder  
- Volume Profile (app)  
- Anchored VWAP  
- SMC_Structures unificado (reemplazado por SMC Pro + Structures_FVG)  
- **Línea horizontal entrecortada del último precio** (full-width plot; no existe en TV) —
  `legacy/Market/Panels/last_price_hline_legacy.pm`  
- Tests asociados (incl. t/16, t/18 ondemand liq, etc.)

## Política

1. **No copiar** de vuelta a `Market/Indicators` ni `Market/Overlays` del repo.  
2. **No** `use` ni registrar en ChartEngine el código del archive.  
3. Si hace falta una idea antigua: copiar **lógica de referencia** a un módulo **nuevo**, no reactivar el archivo tal cual.  
4. **Liquidity v2** ya está en el producto oficial (`docs/LIQUIDITY_V2.md`) — **sin** usar el Liquidity del archive.

## Producto oficial

Ver `docs/PRODUCTO_OFICIAL.md`.
