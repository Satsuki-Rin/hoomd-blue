# HOOMD-blue

HOOMD-blue is a general purpose particle simulation toolkit. It performs hard particle Monte Carlo simulations
of a variety of shape classes, and molecular dynamics simulations of particles with a range of pair, bond, angle,
and other potentials. HOOMD-blue runs fast on NVIDIA GPUs, and can scale across
many nodes. For more information, see the [HOOMD-blue website](http://glotzerlab.engin.umich.edu/hoomd-blue).

# Tutorial

[Read the HOOMD-blue tutorial online](http://nbviewer.jupyter.org/github/joaander/hoomd-examples/blob/master/index.ipynb).

## Installing HOOMD-blue

HOOMD-blue binaries are available via [Anaconda](http://conda.pydata.org/docs/) and images via the
[Docker Hub](https://hub.docker.com/). Anaconda packages are best suited for use on *local workstations*,
while the images are best for use on HPC clusters with Singularity.

### Docker images

The [glotzerlab/software](https://hub.docker.com/r/glotzerlab/software/) images contain HOOMD-blue along with
many other tools commonly used in simulation workflows. You can use these images to execute HOOMD-blue and related tools in Docker/Singularity containers on Mac, Linux, and cloud systems you control and on HPC clusters with Singularity support. CUDA and MPI operate with native performance on supported HPC systems
See full usage information on the [glotzerlab/software docker hub page](https://hub.docker.com/r/glotzerlab/software/).

Singularity:
```bash
$ umask 002
$ singularity pull docker://glotzerlab/software
```

Docker:
```bash
$ docker pull glotzerlab/software
```

### Anaconda

Anaconda packages are available on
the [glotzer channel](https://anaconda.org/glotzer).
To install HOOMD-blue, first download and install
[miniconda](http://conda.pydata.org/miniconda.html) following [conda's instructions](http://conda.pydata.org/docs/install/quick.html).
Then add the `glotzer` channel and install HOOMD-blue:

```bash
$ conda config --add channels glotzer
$ conda install hoomd
```

## Compiling HOOMD-blue

Use cmake to configure an out of source build and make to build hoomd.

```bash
mkdir build
cd build
cmake ../
make -j20
```

To run out of the build directory, add the build directory to your `PYTHONPATH`:

```bash
export PYTHONPATH=`pwd`:$PYTHONPATH
```

For more detailed instructions, [see the documentation](http://hoomd-blue.readthedocs.io/en/stable/compiling.html).

### Prerequisites

 * Required:
     * Python >= 2.7
     * numpy >= 1.7
     * CMake >= 2.8.0
     * C++ 11 capable compiler (tested with gcc 4.8, 4.9, 5.4, 6.4, clang 3.8, 5.0)
 * Optional:
     * NVIDIA CUDA Toolkit >= 7.0
     * Intel Threaded Building Blocks >= 4.3
     * MPI (tested with OpenMPI, MVAPICH)
     * sqlite3

## Job scripts

HOOMD-blue job scripts are python scripts. You can control system initialization, run protocol, analyze simulation data,
or develop complex workflows all with python code in your job.

Here is a simple example.

```python
import hoomd
from hoomd import md
hoomd.context.initialize()

# create a 10x10x10 square lattice of particles with name A
hoomd.init.create_lattice(unitcell=hoomd.lattice.sc(a=2.0, type_name='A'), n=10)
# specify Lennard-Jones interactions between particle pairs
nl = md.nlist.cell()
lj = md.pair.lj(r_cut=3.0, nlist=nl)
lj.pair_coeff.set('A', 'A', epsilon=1.0, sigma=1.0)
# integrate at constant temperature
all = hoomd.group.all();
md.integrate.mode_standard(dt=0.005)
hoomd.md.integrate.langevin(group=all, kT=1.2, seed=4)
# run 10,000 time steps
hoomd.run(10e3)
```

Save this as `lj.py` and run with `python lj.py` (or `singularity exec software.simg python3 lj.py` if using containers).

## Reference Documentation

Read the [reference documentation on readthedocs](http://hoomd-blue.readthedocs.io).

## Change log

See [ChangeLog.md](ChangeLog.md).

## Contributing to HOOMD-blue.

See [CONTRIBUTING.md](CONTRIBUTING.md).

