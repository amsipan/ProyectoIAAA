# Código legacy — FUERA del repositorio GitHub

## Ubicación en disco (acceso local, no git)

```
C:\ia\proyecto_iaaa\Proyecto\ProyectoIAAA_LEGACY_ARCHIVE\
```

| Contenido | Ruta en el archivo |
|-----------|-------------------|
| Módulos antiguos | `legacy/Market/Indicators/`, `legacy/Market/Overlays/` |
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
- Tests asociados (incl. t/16, t/18 ondemand liq, etc.)

## Política hasta terminar el plan maestro

1. **No copiar** de vuelta a `Market/Indicators` ni `Market/Overlays` del repo.  
2. **No** `use` ni registrar en ChartEngine.  
3. Si hace falta una idea antigua: abrir el archivo en el explorador o editor; copiar **lógica de referencia** a un módulo **nuevo**, no reactivar el archivo tal cual.  
4. Liquidity se reimplementará **desde cero** (PDF + FSM del profe + pivotes del stack oficial).

## Producto oficial

Ver `docs/PRODUCTO_OFICIAL.md`.
