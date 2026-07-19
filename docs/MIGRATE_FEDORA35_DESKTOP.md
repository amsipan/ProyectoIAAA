# Migración Fedora35 WSL — laptop ↔ PC de escritorio

Estado (2026-07-15): **import en escritorio completado y verificado** (PDL + AI::MXNet + slice).

## Objetivo

Tener la **misma distro WSL `Fedora35`** (stack del curso IAAA: Perl 5.34, PDL, Tk/WSLg, `/opt` MXNet, parches AI::MXNet) en:

| Máquina | Rol | Cómo llegar |
|---------|-----|-------------|
| Laptop ASUS ROG | Origen / día a día | Local |
| PC de escritorio (hostname `A`, user Windows `bryan`) | Segunda estación | SSH (ver abajo) |

El **código del proyecto** se sincroniza con **Git**, no con el export WSL.  
El **runtime Linux** se clona con `wsl --export` / `wsl --import`.

## Inventario de red (escritorio)

| Ruta | Destino | Notas |
|------|---------|--------|
| **LAN (preferida en casa)** | `bryan@192.168.100.4` | Ping ICMP suele fallar; **TCP 22 OK**. Laptop típica: Wi‑Fi `192.168.100.26` |
| Tailscale | `ssh pc2` → `100.79.21.108` | Skill `ssh-bryan` |
| Radmin VPN | `ssh pc2-radmin` → `26.108.172.34` | Fallback |

Clave laptop: `C:\Users\ASUS ROG\.ssh\id_ed25519`  
Config: `C:\Users\ASUS ROG\.ssh\config` (`Host pc2`, `Host pc2-radmin`)

**No confundir** con `ssh vps` (Oracle cloud).

Ejemplo LAN:

```powershell
ssh -i $env:USERPROFILE\.ssh\id_ed25519 -o IdentitiesOnly=yes bryan@192.168.100.4
```

## Artefactos

| Qué | Ruta |
|-----|------|
| Export master (laptop) | `C:\WSL\Fedora35-ia.tar` (~16.71 GB) |
| Copia en escritorio (post-transfer) | `C:\WSL\Exports\Fedora35-ia.tar` |
| VHDX importado escritorio | `C:\WSL\Fedora35\ext4.vhdx` |
| VHDX vivo laptop | `C:\Users\ASUS ROG\fedora35\ext4.vhdx` |
| Setup / parches MXNet | `docs/SETUP_FEDORA35.md` |
| Env Perl/MXNet | `/etc/profile.d/mxnet_perl.sh` y `~/.bashrc` (root) |

## Export (laptop, ya hecho)

```powershell
wsl --shutdown
wsl --export Fedora35 C:\WSL\Fedora35-ia.tar
```

## Import (escritorio)

```powershell
# En el escritorio (o vía SSH)
wsl --shutdown
# Si ya existía un Fedora35 viejo:
wsl --unregister Fedora35
# Import fresco
wsl --import Fedora35 C:\WSL\Fedora35 C:\WSL\Exports\Fedora35-ia.tar --version 2
```

- Usuario por defecto tras import: **root** (alineado con el curso / SETUP_FEDORA35).
- No cambiar `wsl --set-default` a ciegas si otras distros (Ubuntu/OpenClaw) dependen del default.

## Variables de entorno (crítico para AI::MXNet)

Sin esto, `libmxnet.so` / `AI::MXNetCAPI` fallan.

```bash
export MXNET_HOME=/opt/softwares/apache-mxnet-src-1.9.1-incubating
export LD_LIBRARY_PATH=${MXNET_HOME}/lib:/usr/local/lib:/usr/lib64:${LD_LIBRARY_PATH}
export PERL5LIB=/usr/local/share/perl5/5.34/x86_64-linux-thread-multi:${PERL5LIB}
```

Está en:

- `/root/.bashrc`
- `/etc/profile.d/mxnet_perl.sh` (recomendado para shells de agentes)

**Agentes / SSH no interactivo:** preferir

```text
wsl -d Fedora35 -- bash -lc '…comando…'
```

para cargar profile/bashrc.

## Checklist de verificación

```bash
wsl -d Fedora35 -- bash -lc '
  whoami
  perl -e "print \$^V, qq(\n)"
  perl -MPDL -e "print qq(PDL OK\n)"
  perl -MAI::MXNet -e "print qq(MXNet OK\n)"
  perl -MAI::MXNet -e "my \$a=AI::MXNet::NDArray->array([1,2,3,4,5,6]); \$a->slice([0,2,4]); print qq(Slice OK\n)"
  du -sh /opt /usr/local
'
```

Esperado:

- `root`
- Perl **v5.34.x**
- `PDL OK`, `MXNet OK`, `Slice OK`
- `/opt` ~**7.6G**, `/usr/local` ~**450M**

GUI Tk (`perl -I. market.pl`): validar **en el escritorio con sesión local** (WSLg), no solo por SSH headless.

## Código del proyecto

El export **no** trae el código Windows. En el escritorio (2026-07-15):

| Concepto | Ruta en escritorio |
|----------|-------------------|
| Clone Git | `C:\Users\bryan\ia\proyecto_iaaa\Proyecto\ProyectoIAAA` |
| Atajo | `C:\ia\...` (junction → `C:\Users\bryan\ia`) |
| Remotes | `origin` = `amsipan/ProyectoIAAA`, `backup` = `ayalast/ProyectoIAAA` |
| WSL path | `/mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA` |

**Nota:** En el escritorio, `C:\m` es un junction viejo a OneDrive del perfil `USER` y **no** sirve como en la laptop. No uses `C:\m\ia` allá; usa `C:\Users\bryan\ia` o `C:\ia`.

En la laptop el trabajo suele vivir bajo `C:\m\ia` (reparse/OneDrive) y el git de ProyectoIAAA apunta a los mismos remotes.

Flujo diario entre PCs: **commit → push → pull**. Re-export WSL solo si cambia el **stack del sistema**.

```powershell
# Escritorio: actualizar código
cd C:\Users\bryan\ia\proyecto_iaaa\Proyecto\ProyectoIAAA
git pull origin main

# Tests en Fedora35
wsl -d Fedora35 -- bash -lc "cd /mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && prove -l t"
```

## Transferencia grande (lecciones)

- SCP de 17 GB por Tailscale/Radmin se corta; usar **trozos de ~1 GB** + `copy /b` o reintentos.
- En la misma red local (`192.168.100.4`) la velocidad **no fue mucho mayor** con la laptop en **Wi‑Fi** (~0.6 MB/s). Cable o USB suelen ser mejores.
- Tras import exitoso se puede borrar `C:\WSL\Exports\Fedora35-ia.tar` en el escritorio para liberar ~17 GB (conservar master en laptop si hay espacio).

## Política para agentes futuros

1. Runtime IAAA = distro **`Fedora35`** (`wsl -d Fedora35`), no Ubuntu por defecto.  
2. Comandos con `bash -lc` o env de `mxnet_perl.sh`.  
3. Código vía Git; no reinstalar el PDF del profesor si el import está sano.  
4. Escritorio = `ssh pc2` / `pc2-radmin` / LAN `192.168.100.4` como `bryan`.  
5. Detalle de parches MXNet: `docs/SETUP_FEDORA35.md`.
