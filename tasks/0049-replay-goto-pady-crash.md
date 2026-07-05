# Task 0049: [CRÍTICO/runtime] ✅ RESUELTA — 4 bugs de API de Tk en el lote 0044 (menú Go-to)

## Origen
- Validación del arquitecto de la task 0044 (05/07). `perl -I. -c` y `prove -l t` (1090) pasan,
  PERO **la app crashea al arrancar** en WSLg Fedora35 con:
  ```
  extra option "2" (option with no value?) at /usr/lib64/perl5/vendor_perl/Tk/Widget.pm line 1217.
   at Market/UI/ReplayGotoMenu.pm line 34.
  ```
- Los tests con mock Tk NO lo detectan porque el mock no valida las opciones de `pack`. Solo se ve
  al ejecutar la GUI real. (Recordatorio: la 0044 estaba "verde" en tests pero rota en runtime.)

## RESUELTA POR EL ARQUITECTO (05/07). Eran CUATRO bugs de runtime, no uno.
La validación visual destapó una cadena de 4 errores de API de Tk en el lote 0044. NINGUNO lo
detecta `perl -c` ni los tests con mock Tk; solo se ven ejecutando la GUI real. Esta versión de
perl-Tk (Fedora35) usa nombres de método SIN el prefijo `winfo_` y no acepta algunas formas.

### Bug 1 — `-pady => (lista)` aplana argumentos
En Perl, una lista literal dentro de argumentos de función **se aplana**:
```perl
->pack(..., -pady => (4, 2));   # MAL: se aplana a ..., -pady, 4, 2 → Tk ve "2" huérfano
->pack(..., -pady => [4, 2]);   # BIEN: arrayref = pad asimétrico [top, bottom]
```
Error: `extra option "2" (option with no value?)`. Sitios: `ReplayGotoMenu.pm`, `Callbacks.pm:266`.

### Bug 2 — métodos `winfo_*` no existen en este Tk
`winfo_exists`, `winfo_rootx`, `winfo_rooty`, `winfo_containing` → `Failed to AUTOLOAD`.
Los nombres correctos aquí son SIN prefijo: `exists`, `rootx`, `rooty`, `containing`.
Peor aún: estaban dentro de `eval {}`, así que no explotaban visiblemente — el `eval` fallaba,
devolvía undef, y el guard `return unless ...` hacía que **el menú nunca se abriera** (fallo
silencioso). Sitios: `ReplayGotoMenu.pm` (show + outside-bind), `Callbacks.pm:259`.

### Bug 3 — `update_idletasks` no existe
El nombre correcto es `idletasks` (o `update`). Error: `Failed to AUTOLOAD update_idletasks`.
Sitio: `ReplayGotoMenu.pm` show().

### Bug 4 — `$top->wait($top)` y `bind(seq, cb, '+')` no soportados
- `wait` no existe → usar `waitWindow`. Sitio: `Callbacks.pm` (diálogo Date...).
- `bind('<Button-1>', $cb, '+')` → `wrong # args`. Esta versión no acepta el modo append `'+'`.
  Usar `$w->Tk::bind('<Button-1>', $cb)` y desbindear con `$w->Tk::bind('<Button-1>', '')`.
  (Seguro aquí porque el root solo tenía `<Configure>` bindeado.)

### Verificación del arquitecto
- `perl -I. -c` OK en los 3 archivos. `prove -l t` → 1090 PASS.
- App **arranca** sin crash (`perl -I. market.pl`).
- Menú Go-to **se despliega** (validado con harness que fuerza `show()` + captura): título
  "SELECT STARTING POINT" + 4 filas ASCII, sobre el chart, coincide con captura 3 de la referencia.
- `grep -rn 'winfo_\|update_idletasks\|->wait(' Market/` → vacío.

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

## Lección para el implementor (CRÍTICA — API de Tk en Fedora35)
1. **Pad asimétrico = arrayref `[top, bottom]`, NUNCA `(top, bottom)`** — los paréntesis se
   aplanan y rompen la llamada.
2. **Esta versión de perl-Tk usa métodos SIN prefijo `winfo_`:** `exists`, `rootx`, `rooty`,
   `width`, `height`, `containing`, `pointerx`, `pointery`. Los `winfo_*` fallan con AUTOLOAD.
3. **`idletasks`, no `update_idletasks`. `waitWindow`, no `wait`.**
4. **`bind` en modo append `'+'` NO se soporta:** usar `$w->Tk::bind($seq, $cb)`; desbindear con
   `$w->Tk::bind($seq, '')`. Antes de bindear en el root, confirmar que no pisas otro bind.
5. **`perl -c` y los tests con mock Tk NO detectan NADA de esto.** Un método mal nombrado dentro
   de `eval {}` produce un fallo SILENCIOSO (el widget no aparece y no hay error visible).

**Regla dura nueva:** toda task que toque la GUI debe arrancar `perl -I. market.pl` al menos una
vez Y, si añade un widget que se muestra bajo demanda (menú/dropdown/diálogo), verificar que ese
widget REALMENTE se muestra (harness que fuerce `show()` o click real). "Tests verdes" ≠ "funciona".
Referencia de métodos válidos: ver `scratch/probe_*.pl` (sondeos de API que dejó el arquitecto).
