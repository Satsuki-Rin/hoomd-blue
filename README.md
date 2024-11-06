[toc]

# Set up HOOMD-blue benchmark

## Clone HOOMD-blue codes

The following commands

1. Created a workspace directory for HOOMD-blue under `scratch` directory
2. Clone `HOOMD-blue` which we modified and `hoomd-benchmarks` code to the work directory
4. Create the `initial_configuration_cache` directory to hold the initial condition files
4. Copy the initial configuration file prepared at `/scracth/public` to the `initial_configuration_cache` directory

```bash
mkdir ${HOME}/scratch/workdir/hoomd -p
git -C ${HOME}/scratch/workdir/hoomd clone https://github.com/Satsuki-Rin/hoomd-blue  --recursive
time git -C ${HOME}/scratch/workdir/hoomd clone https://github.com/glotzerlab/hoomd-benchmarks
mkdir -p ${HOME}/scratch/workdir/hoomd/initial_configuration_cache
cp /scratch/public/2024-apac-hpc-ai/hoomd/initial_configuration_cache/hard_sphere_200000_1.0_3.gsd \
${HOME}/scratch/workdir/hoomd/initial_configuration_cache
```

## Create Python 3 environment

The following commands

1. Set up a Python 3 Conda environment
2. Install latest `pybind11(2.13.5)` with PIP, to fix `pybind11 version(v2.10.1)` issue caused by wrong HOOMD-blue prerequisite list in the HOOMD-blue git code
3. Run`install-prereq-headers.py` scripts that provided by HOOMD-blue developers
4. Install `GSD` and `numpy`

```bash
conda create -p ${HOME}/scratch/workdir/hoomd/hoomd.py312 python=3.12 -y
${HOME}/scratch/workdir/hoomd/hoomd.py312/bin/pip install pybind11
${HOME}/scratch/workdir/hoomd/hoomd.py312/bin/python3 ${HOME}/scratch/workdir/hoomd/hoomd-blue/install-prereq-headers.py -y
${HOME}/scratch/workdir/hoomd/hoomd.py312/bin/pip install numpy gsd
```

## Build HOOMD-blue with IntelMPI

The following commands

1. Check available MPI libraries that pre-built by the Supercomputer administrator
2. Load IntelMPI environment variables
3. Configure the scripts for building HOOMD-blue with IntelMPI and pip-installed `pybind11`
4. Build the Python package
5. Validate the built Python package

```bash
#!/bin/bash
#PBS -j oe
#PBS -M 1652074432@qq.com
#PBS -m abe
#PBS -P qa09
#PBS -l ngpus=0
#PBS -l walltime=00:10:00
##PBS -l other=hyperthread
#-report-bindings \

module purge
module load intel-compiler-llvm/2024.2.0
module load intel-mkl/2024.2.0
module load intel-mpi/2021.13.0

time PATH=${HOME}/scratch/workdir/hoomd/hoomd.py312/bin:$PATH \
cmake \
-B ${HOME}/scratch/workdir/hoomd/build/hoomd-intelmpi \
-S ${HOME}/scratch/workdir/hoomd/hoomd-blue \
-D ENABLE_MPI=on \
-DCMAKE_CXX_FLAGS=-march=native -DCMAKE_C_FLAGS=-march=native \
-D MPI_HOME=/apps/intel-tools/intel-mpi/2021.13.0 \
-D cereal_DIR=${HOME}/scratch/workdir/hoomd/hoomd.py312/lib64/cmake/cereal \
-D Eigen3_DIR=${HOME}/scratch/workdir/hoomd/hoomd.py312/share/eigen3/cmake \
-D pybind11_DIR=${HOME}/scratch/workdir/hoomd/hoomd.py312/lib/python3.12/site-packages/pybind11/share/cmake/pybind11
-DCMAKE_CXX_FLAGS="-O3 -xHost -DMKL_ILP64 -qmkl-ilp64=parallel -fiopenmp" \
-DCMAKE_C_FLAGS="-O3 -xHost -DMKL_ILP64 -qmkl-ilp64=parallel -fiopenmp"

time cmake --build ${HOME}/scratch/workdir/hoomd/build/hoomd-intelmpi -j 48

# Validate the built package by loading it with Python
PYTHONPATH=${HOME}/scratch/workdir/hoomd/build/hoomd-intelmpi \
${HOME}/scratch/workdir/hoomd/hoomd.py312/bin/python \
-m hoomd
# python: No module named hoomd.__main__; 'hoomd' is a package and cannot be directly executed
```

# Run the Task 

## Create PBS bash script

Create a shell script file, `${HOME}/run/run.sh`, with following contents

```bash
#!/bin/bash
#PBS -j oe
#PBS -M 1652074432@qq.com
#PBS -m abe
#PBS -P qa09
#PBS -l ngpus=0
#PBS -l walltime=00:10:00
##PBS -l other=hyperthread
#-report-bindings \

module purge
module load intel-compiler-llvm/2024.2.0
module load intel-mkl/2024.2.0
module load intel-mpi/2021.13.0

hosts=$(sort -u ${PBS_NODEFILE} | paste -sd ',')

cmd="time mpirun \
-host ${hosts} \
-wdir ${HOME}/scratch/workdir/hoomd \
-ppn 48 \
--env PYTHONPATH ${HOME}/scratch/workdir/hoomd/build/hoomd-intelmpi:${HOME}/scratch/workdir/hoomd/hoomd-benchmarks \
${HOME}/scratch/workdir/hoomd/hoomd.py312/bin/python \
-m hoomd_benchmarks.md_pair_wca \
--device CPU -v \
-N ${N} --repeat ${repeat} \
--warmup_steps ${warmup_steps} --benchmark_steps ${benchmark_steps}"

echo ${cmd}

exec ${cmd}
date
```

## When you run with 8 nodes
Please modify the file 'md_pair.py' in hoomd-benchmarks/hoomd_benchmarks.
Change DEFAULT_BUFFER = 0.4 to DEFAULT_BUFFER = 0.5,and you'll get better performance.

## Submit the job script to PBS

The following command

1. Define the number of nodes as an environment variable to set the job scale.
2. Submit the PBS job script to normal queue(CPU queue)

Use PBS to submit the build.sh
```bash
cd ${HOME}/run

nodes=1 walltime=00:10:00 \
bash -c \
'qsub -V \
-l walltime=${walltime},ncpus=$((48*nodes)),mem=$((48*nodes*1))gb \
-N hoomd.nodes${nodes}.WS${warmup_steps}.BS${benchmark_steps} \
build.sh'
```

Use PBS to run
```bash
cd ${HOME}/run

nodes=1 walltime=00:10:00 \
warmup_steps=40000 benchmark_steps=80000 repeat=1 N=200000 \
bash -c \
'qsub -V \
-l walltime=${walltime},ncpus=$((48*nodes)),mem=$((48*nodes*1))gb \
-N hoomd.nodes${nodes}.WS${warmup_steps}.BS${benchmark_steps} \
run.sh'

nodes=2 walltime=00:10:00 \
warmup_steps=40000 benchmark_steps=80000 repeat=1 N=200000 \
bash -c \
'qsub -V \
-l walltime=${walltime},ncpus=$((48*nodes)),mem=$((48*nodes*1))gb \
-N hoomd.nodes${nodes}.WS${warmup_steps}.BS${benchmark_steps} \
run.sh'

nodes=4 walltime=00:00:300 \
warmup_steps=40000 benchmark_steps=80000 repeat=1 N=200000 \
bash -c \
'qsub -V \
-l walltime=${walltime},ncpus=$((48*nodes)),mem=$((48*nodes*1))gb \
-N hoomd.nodes${nodes}.WS${warmup_steps}.BS${benchmark_steps} \
run.sh'

nodes=8 walltime=00:00:300 \
warmup_steps=40000 benchmark_steps=80000 repeat=1 N=200000 \
bash -c \
'qsub -V \
-l walltime=${walltime},ncpus=$((48*nodes)),mem=$((48*nodes*1))gb \
-N hoomd.nodes${nodes}.WS${warmup_steps}.BS${benchmark_steps} \
run.sh'

nodes=16 walltime=00:00:300 \
warmup_steps=10000 benchmark_steps=160000 repeat=1 N=200000 \
bash -c \
'qsub -V \
-l walltime=${walltime},ncpus=$((48*nodes)),mem=$((48*nodes*1))gb \
-N hoomd.nodes${nodes}.WS${warmup_steps}.BS${benchmark_steps} \
run.sh'

nodes=32 walltime=00:00:300 \
warmup_steps=10000 benchmark_steps=320000 repeat=1 N=200000 \
bash -c \
'qsub -V \
-l walltime=${walltime},ncpus=$((48*nodes)),mem=$((48*nodes*1))gb \
-N hoomd.nodes${nodes}.WS${warmup_steps}.BS${benchmark_steps} \
run.sh'
```

Read the results
```bash
grep "time steps per second" ${HOME}/run/hoomd*.* |sort  --version-sort
```
