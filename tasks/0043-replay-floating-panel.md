# Task 0043: Replay — panel flotante media-player (layout TradingView)

**Estado:** ✅ hecho

## Referencia
- `docs/TRADINGVIEW_BAR_REPLAY_REFERENCE.md` §3, §19 capturas 1 y 2.
- Depende de 0041 (backend velocidad/intervalo) para poder etiquetar los botones de speed/intervalo.

## Objetivo
Reemplazar la fila de botones de la pestaña Replay por un **panel flotante horizontal** centrado en
la parte inferior del chart, con el layout de TradingView:

```
[✂ Select bar ▾]   [▷ Play]  [▷| Fwd]   [1x]   [D]   [▷▷|]   ……………   [✕]
```

## Estado actual
- Pestaña Replay en `market.pl` (líneas ~319-337): 8 botones planos
  (`Select Bar, Inicio, Play, Pause, <, >, >>, Salir`).
- Callbacks en `Market/UI/Callbacks.pm` (make_replay_*).

## Diseño
1. **Contenedor flotante:** un `Frame` hijo del área del chart, posicionado con `place`
   (`-relx=>0.5, -rely=>1.0, -anchor=>'s', -y=>-8`) para quedar centrado abajo, superpuesto al
   canvas. `ponytail:` place sobre el canvas basta; no hace falta Toplevel salvo que el usuario
   quiera arrastrarlo. Fondo claro con `-relief=>'groove'` para simular la píldora de TV.
2. **Botones (Frames+Label clicables o Button planos), de izquierda a derecha:**
   - `Select bar ▾` — abre el menú Go-to (0044). El `▾` es el disparador del dropdown.
   - `Play/Pause` — un solo botón toggle (texto/icono cambia según `is_active` + `playing`). (0046)
   - `Fwd` (`▷|`) — step forward (una vela / un intervalo).
   - `1x` — etiqueta de velocidad; abre dropdown de velocidad (0045).
   - `D` — etiqueta de intervalo; abre dropdown de intervalo (0045).
   - `▷▷|` — Jump to real-time (0046).
   - `✕` — cerrar replay (equivale a Salir actual).
3. **Visibilidad:** el panel aparece al activar Replay y se oculta (packForget/place forget) al
   salir. Añadir un disparador de "activar Replay" (botón en la barra superior o en la pestaña) que
   entra directo a modo selección (flujo TV: abrir = seleccionar). El botón `Inicio` separado se
   pliega dentro de este flujo; conservar `make_replay_start` como callback interno.
4. **Mantener `<` (step back):** TV no lo tiene, pero es extra del proyecto. Colocarlo discretamente
   (p.ej. junto a Fwd como `|◁`) o dejarlo accesible por Shift+←. Decidir por mínima intrusión
   visual; documentar la elección en el commit.
5. Cablear cada botón a los callbacks existentes en `Callbacks.pm` (nuevos wrappers si hace falta).

## Criterios de aceptación
- Al activar Replay aparece el panel flotante centrado abajo, con los controles en el orden de la
  captura; al salir desaparece.
- Todos los botones existentes siguen funcionando (Play, Fwd, step back, jump, cerrar).
- No se usa `Tk::NoteBook`/`Optionmenu`/menubar nativo.
- `prove -l t` verde; `t/17-ui-wiring.t` verifica que las factorías de callbacks del panel existen y
  son CODE, y que el panel se construye sin error (smoke test headless con mock si aplica).

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c market.pl && perl -I. -c Market/UI/Callbacks.pm && prove -l t/17-ui-wiring.t t"
```
Validación visual obligatoria en WSLg (comparar con capturas 1 y 2).

## Qué no tocar
- No romper los otros paneles/pestañas (Capas, Liq, Mxwll, ZigZag, Escala).
- No cambiar el backend de ReplayController (solo consumirlo).
