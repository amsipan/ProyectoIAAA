# Task 0049: [CRÍTICO/runtime] App crashea al abrir — `-pady => (lista)` inválido en Tk

## Origen
- Validación del arquitecto de la task 0044 (05/07). `perl -I. -c` y `prove -l t` (1090) pasan,
  PERO **la app crashea al arrancar** en WSLg Fedora35 con:
  ```
  extra option "2" (option with no value?) at /usr/lib64/perl5/vendor_perl/Tk/Widget.pm line 1217.
   at Market/UI/ReplayGotoMenu.pm line 34.
  ```
- Los tests con mock Tk NO lo detectan porque el mock no valida las opciones de `pack`. Solo se ve
  al ejecutar la GUI real. (Recordatorio: la 0044 estaba "verde" en tests pero rota en runtime.)

## Causa raíz
En Perl, una lista literal dentro de argumentos de función **se aplana**. Al escribir:
```perl
->pack(-fill => 'x', -padx => 6, -pady => (4, 2));   # MAL
```
`(4, 2)` se aplana a la lista `..., -pady, 4, 2` → Tk recibe `2` como una opción huérfana sin valor
→ `extra option "2"`. Tk::pack espera un ESCALAR para `-pady` (`4`) o un **arrayref** para pad
asimétrico (`[4, 2]` = 4px arriba, 2px abajo).

## Ubicaciones (2)
- `Market/UI/ReplayGotoMenu.pm:39` → `-pady => (4, 2)`  (introducido en 0044; crashea al abrir)
- `Market/UI/Callbacks.pm:266`    → `-pady => (8, 4)`   (dentro de `_replay_date_prompt`; mismo bug,
  crashearía al abrir el diálogo Date...)

## Fix requerido
Cambiar los paréntesis por **arrayref** (mantiene el pad asimétrico deseado):
```perl
->pack(-fill => 'x', -padx => 6, -pady => [4, 2]);   # BIEN
...
->pack(-padx => 10, -pady => [8, 4]);                # BIEN
```
(El arquitecto ya validó localmente que con `[..]` la app arranca. Aplicar el fix oficial y
revisar que no haya OTROS `-pady => (...)`/`-padx => (...)` con paréntesis en el repo:
`git grep -nE '\-(pady|padx)\s*=>\s*\('`.)

## Criterios de aceptación
- La app **arranca sin crash** en WSLg: `perl -I. market.pl` abre la ventana y rinde el chart.
- El menú Go-to se despliega al pulsar el botón `v` del panel (validación visual del arquitecto).
- El diálogo `Date...` abre sin crash.
- `prove -l t` sigue verde (1090+).
- Añadir, si es barato, una verificación que ejercite el build real del panel/menú de forma que
  un `-pady => (...)` roto falle en test (p.ej. un smoke que instancie con un mock que valide
  que las opciones de pack no traigan claves numéricas sueltas). `ponytail:` si es caro, basta la
  validación visual + el grep; no montar un mini-Tk validador completo.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/UI/ReplayGotoMenu.pm && perl -I. -c Market/UI/Callbacks.pm && prove -l t && perl -I. market.pl"
# La app DEBE abrir la ventana (no morir con 'extra option').
```

## Qué no tocar
- Solo los dos `-pady`. No cambiar la lógica del menú (0044) ni las etiquetas ASCII (0048).

## Lección para el implementor
En Tk, para pad asimétrico usar SIEMPRE arrayref `[top, bottom]`, nunca `(top, bottom)` — los
paréntesis se aplanan y rompen la llamada. Un `perl -c` NO detecta esto; solo la ejecución real.
Regla nueva: **toda task que toque la GUI debe arrancar `perl -I. market.pl` al menos una vez**
(el arquitecto ya lo hace en la revisión visual, pero el implementor debería smoke-abrir también).
