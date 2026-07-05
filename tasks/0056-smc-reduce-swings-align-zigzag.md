# Task 0056: Reducir HH/HL del SMC — alinear estructura con el ZigZag (pocos pivotes)

## Estado
🔲 ABIERTA (2026-07-05). Feedback profe/QA 2ª ronda.

## Origen
- `docs/FEEDBACK_PROFESOR_QA_2026-07-05.md` punto 11, audio 2.
- QA (audio 2): "El HH, el HL en el SMC todavía salen demasiados. El profe no quería que salgan
  casi nada. Para él solo son los mismos que salen en el zigzag, que son relativamente poquitos.
  Hay que basarse más en los del zigzag que los del SMC para el Fibonacci."

## Causa raíz (verificada)
`Market/Indicators/SMC_Structures.pm:42` usa `k=3` y aun así etiqueta un pivote por cada swing
confirmado alternando high/low → demasiados HH/HL/LH/LL. El ZigZag externo
(`Indicators/ZigZag.pm`, `swing_length=150`) produce MUCHOS MENOS vértices (los que el profe
considera correctos).

## Objetivo
Que las etiquetas HH/HL/LH/LL del SMC sean pocas y significativas, alineadas con los pivotes que
marca el ZigZag; y que el Fibonacci (0029) se ancle en esos pocos puntos.

## Enfoque (a decidir con arquitecto)
- **Opción A (preferida):** subir la significancia de los pivotes SMC — filtrar los que no superen
  un desplazamiento mínimo (factor·ATR) respecto al pivote opuesto, o subir `k`. Reduce etiquetas
  sin acoplar módulos.
- **Opción B:** que el SMC use como fuente de swings los vértices del ZigZag externo
  (`get_values->{external_vertices}`), reetiquetándolos HH/HL/LH/LL. Alinea 1:1 con lo que ve el
  profe, pero acopla SMC↔ZigZag (respetar Replay/no-futuro).
- Confirmar cuál usar. La 0056 y la 0029 (fib) deben quedar coherentes: el fib debe anclar en los
  MISMOS pocos pivotes que queden visibles.

## Criterios de aceptación
- El número de etiquetas HH/HL/LH/LL del SMC baja drásticamente (comparable en cantidad a los
  vértices del zigzag externo en la misma ventana).
- El Fibonacci se ancla en esos pivotes reducidos (major_high/major_low coherentes).
- No se rompe BOS/CHoCH ni el render de estructura.
- `prove -l t` verde; test que compare cantidad de pivotes SMC antes/después sobre secuencia fija.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/Indicators/SMC_Structures.pm && prove -l t/05-smc.t && prove -l t"
```
Requiere confirmación visual del arquitecto.

## Relación
- Coordinar con 0029 (fib major high/low anchor) y 0060 (fib 3 niveles en TF baja).

## Qué no tocar
- CSV, MarketData, Market/Debug/.
- No romper BOS/CHoCH ni FVG.
