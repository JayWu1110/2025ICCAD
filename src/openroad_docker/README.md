# OpenROAD Docker environment (project-local)

This directory stores the **OpenROAD Docker definition and launch scripts** for the repo.
The heavy image/binary stays in Docker (too large to commit).

## Options

| Approach | When | How |
|----------|------|-----|
| **A. Build from `.deb`** (recommended) | New machine / clean install | Put `.deb` here → `./run.sh build` → `./run.sh shell` |
| **B. Import old container** | You already have `openroad-env` | `./run.sh import-from-container openroad-env` |
| **C. Export image tarball** | Backup / move machines | `./run.sh export-image` (do **not** git-commit the `.tar`) |
| **D. Copy binary into the folder** | Not recommended | Library deps break outside Ubuntu 22.04 |

**What belongs in the repo:** Dockerfile, `run.sh`, compose — not the full Docker rootfs.

## vs legacy flow

Old README flow: create a container, `docker cp` design files, then run inside.

Now:
1. Environment definition lives in `src/openroad_docker/`
2. Entire `src/` is mounted at `/workspace` (edits apply immediately; no repeated `docker cp`)

## Prerequisite: Docker visible in WSL

If `docker version` fails:

1. Start **Docker Desktop**
2. **Settings → Resources → WSL Integration** → enable your distro
3. Re-open the WSL terminal

## A. Build from `.deb`

1. Download the contest OpenROAD package, e.g.  
   `openroad_2.0-17598-ga008522d8_amd64-ubuntu-22.04.deb`  
   from [Precision-Innovations/OpenROAD releases](https://github.com/Precision-Innovations/OpenROAD/releases)

2. Place it in this directory.

3. Build and enter:
   ```bash
   chmod +x run.sh
   ./run.sh build
   ./run.sh shell
   ```

4. Inside the container:
   ```bash
   cd /workspace/openRoad_eval_script
   openroad -exit eval_def.tcl
   openroad -exit optimize_adaptive.tcl
   ```

Or from the host:
```bash
./run.sh eval
./run.sh optimize
./run.sh strengthen
```

## B. Import an existing container

```bash
./run.sh import-from-container openroad-env
./run.sh shell
```

## C. Backup image (optional)

```bash
./run.sh export-image openroad-image.tar
docker load -i openroad-image.tar
```

`.gitignore` already ignores `*.deb` / `*.tar`.

## Related: `ICCAD_ProbC_ENV`

| Directory | Purpose |
|-----------|---------|
| `openroad_docker/` | Run **OpenROAD** (eval / timing repair) |
| `ICCAD_ProbC_ENV/` | **CUDA + PyTorch** (future GPU / differentiable work) |

Use this directory for day-to-day OpenROAD runs.
