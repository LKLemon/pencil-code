#!/bin/bash -l
#SBATCH --job-name=helical-gpu-256
#SBATCH --output=helical-gpu-256_%j.out
#SBATCH --error=helical-gpu-256_%j.err
#SBATCH --account=project_462001734
#SBATCH --partition=dev-g
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gpus-per-task=1
#SBATCH --cpus-per-task=7
#SBATCH --time=02:00:00
#SBATCH --mem=0

set -eo pipefail

export PENCIL_HOME=/scratch/project_462001734/wangzhao/pencil-code
cd "$PENCIL_HOME/samples/helical-MHDturb"

module purge
module load CrayEnv
module load PrgEnv-cray
module load rocm buildtools cray-mpich cray-hdf5-parallel cray-python

export _sourceme_quiet=1
source "$PENCIL_HOME/sourceme.sh"

export OMP_NUM_THREADS=7
export OMP_PROC_BIND=close,spread
export OMP_MAX_ACTIVE_LEVELS=2
export OMP_WAIT_POLICY=PASSIVE
export MPICH_GPU_SUPPORT_ENABLED=0

CONF="$PENCIL_HOME/config/hosts/lumi/host-uan04-GNU_Linux.conf"

# Build if binary missing (same modules as run)
pc_setupsrc --force-astaroth
# Force rebuild after Makefile.local / grid changes
pc_build -f "$CONF"

pc_start -f "$CONF"
pc_run -f "$CONF"