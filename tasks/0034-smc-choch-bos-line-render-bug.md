# Task 0034: SMC CHoCH/BOS — líneas mal dibujadas (a mitad de vela, colores/posición)

## Origen
- Reporte del usuario (03/07) con captura, capa SMC activa en 2h:
  1. Las líneas de CHoCH/BOS salen de un extremo de una vela pero **no llegan al
     otro extremo, se quedan a la mitad** de una vela. Se ve notablemente mal.
  2. Los CHoCH aparecen con **colores tal vez alterados**, unos arriba y otros
     abajo. No está claro si es correcto que estén en ambas posiciones o solo una.

## Estado verificado (03/07)
Overlay `Market/Overlays/SMC_Structures.pm`, bloque "Etiquetas BOS/CHoCH"
(lineas ~227-269):
- La línea va de `x_start = index_to_center_x(start_index)` a
  `x_end = index_to_center_x(index)`. Ambos usan CENTRO de vela, así que en
  teoría van de centro a centro. El sintoma "llega a la mitad" sugiere que
  `start_index` o `index` no son los correctos, o que la conversion local/x no
  cuadra con el ancho de vela actual (posible desajuste en zoom/downsample).
- Color: usa `smc_bos`/`smc_choch_true`/`smc_choch_false` del tema, o cae en
  `$dir_color` (verde up / rojo down). El "color alterado" y "arriba/abajo"
  probablemente viene de la direccion del evento (`dir`) y del anchor 's'
  (siempre south) — la etiqueta se ancla siempre en 's' aunque el evento sea
  bajista, lo que puede ponerla en un lado no intuitivo.

## Objetivo
- La línea CHoCH/BOS debe ir limpiamente del pivote roto hasta la vela del
  quiebre (extremo a extremo, no a media vela).
- Color y posicion (arriba/abajo) coherentes con la direccion: alcista arriba/
  verde, bajista abajo/rojo (confirmar convencion con el profe/LuxAlgo).

## Diseño (a confirmar tras reproducir)
1. Revisar `start_index`/`index` del evento en el indicador SMC: que apunten al
   pivote de origen y a la vela de quiebre reales.
2. Verificar la conversion `_local_index` + `index_to_center_x` bajo distintos
   zoom (posible interaccion con downsample por pixel cuando bar_w<2).
3. Ajustar anchor de la etiqueta segun `dir` (alcista 's' arriba, bajista 'n'
   abajo) para que no queden "unas arriba y otras abajo" sin criterio.

## Criterios de aceptación
- Las líneas CHoCH/BOS conectan pivote→quiebre de extremo a extremo en todos los
  niveles de zoom.
- Color por direccion consistente; etiqueta en posicion coherente.
- No se rompe el resto del overlay SMC ni los tests t/14.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/Overlays/SMC_Structures.pm && prove -l t/09-smc-structures.t t/14-overlay-smc-render.t"
```
Requiere confirmacion visual (capa SMC en 2h).

## Nota
Relacionado con task 0033: si el enfoque ZigZag del profe reemplaza a HH/HL/LL/LH
y a la estructura SMC, esta correccion podria volverse innecesaria. CONFIRMAR el
alcance antes de invertir mucho: quiza solo haya que arreglar lo minimo o
directamente migrar a ZigZag.
