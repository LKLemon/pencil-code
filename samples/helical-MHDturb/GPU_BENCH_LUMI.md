# helical-MHDturb GPU benchmark on LUMI (Astaroth)

## Summary

`helical-MHDturb` runs on a single AMD MI250 GPU on CSC LUMI with Astaroth at **256³**:
**≈ 0.69 µs per meshpoint per timestep** (job 24022384, `nt=10`, no NaNs).

| Grid | GPUs | Job | Wall clock / timestep / meshpoint | Status |
|------|------|-----|-----------------------------------|--------|
| 128³ | 1× MI250 | 23990582 | 4.41 µs | OK |
| 256³ | 1× MI250 | 24022384 | **0.69 µs** | OK |
| 256³ | 8× MI250 | 24021979 | — | Failed: `MPI_Isend: Invalid count` (Cray MPICH GTL) |

This is a continuum-only run (`noparticles`, `nopower_spectrum`), meant as a performance
baseline rather than a science run.

## Configuration

- `src/Makefile.local`: `GPU=gpu_astaroth`, `PARTICLES=noparticles`, `POWER=nopower_spectrum`
- `src/cparam.local`: `nxgrid=256`, `ncpus=1`, `npar` commented out
- `run.in`: `nt=10`, `dt=2e-2`, `dspec` disabled
- `print.in`: particle columns commented out
- `run_gpu_256.slurm`: `dev-g`, `PrgEnv-cray` + `rocm`, `MPICH_GPU_SUPPORT_ENABLED=0`

## Reproduce

```bash
export PENCIL_HOME=/scratch/project_462001734/wangzhao/pencil-code
cd $PENCIL_HOME
git submodule update --init --remote src/astaroth
git submodule update --init fortran-parser

cd samples/helical-MHDturb
sbatch run_gpu_256.slurm
grep -i 'Wall clock' helical-gpu-256_<JOBID>.out
```

The first run spends ~10 minutes compiling Astaroth before time stepping starts.

## Earlier failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| `umax` jumps at step 2, then `found nans: after reading from the GPU` | Fixed `dt=4e-2` exceeds the viscous time-step limit at 256³ (see below). Not GPU-specific. | `dt=2e-2` |
| GPU memory fault | Particles enabled; no GPU particle support yet | `PARTICLES=noparticles`, `npar` commented out |
| `MPI_Isend: Invalid count` (8 GPUs) | Cray MPICH GTL on LUMI ROCm; not resolved | Single GPU for now |
| `ac_build.log`: missing `parse.py` | `fortran-parser` submodule not initialized | `git submodule update --init fortran-parser` |
| Job fails immediately | GNU environment on compute nodes | `PrgEnv-cray` + `rocm` |

`power_spectrum` / `dspec` were disabled at the same time as the `dt` fix as a precaution;
they were not isolated as a cause. Delete stale `data/var.dat` when changing the grid size.

### Viscous time-step limit

With a fixed `dt` in `run.in`, Pencil does not adjust the time step, so `dt` must stay below
the diffusive limit. Pencil's criterion (default `lmaximal_cdtv=F`, see `grid.f90`, `equ.f90`) is

```
dt <= cdtv / (max(nu, eta) * (1/dx^2 + 1/dy^2 + 1/dz^2)) = cdtv * dx^2 / (3 * max(nu, eta))
```

with box size `L = 2*pi`, `dx = L/nxgrid`, `nu = eta = 5e-3`, `cdtv = 0.3` (from `run.in`):

| Grid | dx | dx^2 | Limit |
|------|----|------|-------|
| 128³ | 0.0491 | 2.41e-3 | 0.3 * 2.41e-3 / (3 * 5e-3) ≈ **0.048** |
| 256³ | 0.0245 | 6.02e-4 | 0.3 * 6.02e-4 / (3 * 5e-3) ≈ **0.012** |

Halving `dx` cuts the limit by 4. `dt=4e-2` is below the 128³ limit and far above the 256³
one. `dt=2e-2` is also above the 256³ limit (and above the von Neumann bound ≈ 0.017 for
6th-order differences with RK3); it survived `nt=10` only because grid-scale amplitudes start
small. Timing per step does not depend on `dt`, but longer 256³ runs should use `dt=1e-2`
or `dt=0` (automatic time step).

## GPU with particles (`particles_tracers`)

Touko's follow-up: same 256³ GPU run **with tracers** (upstream helical defaults).

| Setting | Value |
|---------|--------|
| `src/Makefile.local` | `PARTICLES=particles_tracers`, `PARTICLES_STALKER=particles_stalker` |
| `src/cparam.local` | `npar=30000`, `npar_stalk=1000` |
| `print.in` | `xp2m`, `yp2m`, `zp2m` enabled |

Submit:

```bash
cd $PENCIL_HOME/samples/helical-MHDturb
sbatch run_gpu_256_particles.slurm
grep -i 'Wall clock' helical-gpu-256-particles_<JOBID>.out
```

With particles, the main line is:

`Wall clock time/timestep/(meshpoint+particle) [microsec] =`

Compare to continuum-only **0.693 µs/meshpoint** (job 24022384). If GPU memory fault,
lower `npar` in `cparam.local` (e.g. 10000), rebuild, and retry.
