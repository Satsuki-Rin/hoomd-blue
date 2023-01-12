// Copyright (c) 2009-2022 The Regents of the University of Michigan.
// Part of HOOMD-blue, released under the BSD 3-Clause License.

#include "hip/hip_runtime.h"
// Copyright (c) 2009-2022 The Regents of the University of Michigan.
// Part of HOOMD-blue, released under the BSD 3-Clause License.

#include "AreaConservationMeshForceComputeGPU.cuh"
#include "hoomd/TextureTools.h"
#include "hoomd/VectorMath.h"

#include <assert.h>

#include <stdio.h>

/*! \file MeshAreaConservationGPU.cu
    \brief Defines GPU kernel code for calculating the area_constraint forces. Used by
   MeshAreaConservationComputeGPU.
*/

namespace hoomd
    {
namespace md
    {
namespace kernel
    {
//! Kernel for calculating area_constraint sigmas on the GPU
/*! \param d_sigma Device memory to write per paricle sigma
    \param d_sigma_dash Device memory to write per particle sigma_dash
    \param N number of particles
    \param d_pos device array of particle positions
    \param d_rtag device array of particle reverse tags
    \param box Box dimensions (in GPU format) to use for periodic boundary conditions
    \param blist List of mesh bonds stored on the GPU
    \param d_triangles device array of mesh triangles
    \param n_bonds_list List of numbers of mesh bonds stored on the GPU
*/
__global__ void gpu_compute_area_constraint_area_kernel(Scalar* d_partial_sum_area,
                                                        const unsigned int N,
                                                        const unsigned int tN,
                                                        const unsigned int type_id,
                                                        const Scalar4* d_pos,
                                                        BoxDim box,
                                                        const group_storage<3>* tlist,
                                                        const unsigned int* tpos_list,
                                                        const Index2D tlist_idx,
                                                        const unsigned int* n_triangles_list)
    {
    HIP_DYNAMIC_SHARED(char, s_data)
    Scalar* area_sdata = (Scalar*)&s_data[0];

    int idx = blockIdx.x * blockDim.x + threadIdx.x;

    Scalar area_transfer = 0;

    if (idx < N)
        {
        int n_triangles = n_triangles_list[idx];
        Scalar4 postype = __ldg(d_pos + idx);
        Scalar3 pos_a = make_scalar3(postype.x, postype.y, postype.z);

        for (int triangle_idx = 0; triangle_idx < n_triangles; triangle_idx++)
            {
            group_storage<3> cur_triangle = tlist[tlist_idx(idx, triangle_idx)];

            int cur_triangle_type = cur_triangle.idx[2];

	    if (cur_triangle_type != type_id)
		    continue;

            int cur_triangle_b = cur_triangle.idx[0];
            int cur_triangle_c = cur_triangle.idx[1];

            int cur_triangle_abc = tpos_list[tlist_idx(idx, triangle_idx)];

            // get the b-particle's position (MEM TRANSFER: 16 bytes)
            Scalar4 bb_postype = d_pos[cur_triangle_b];
            Scalar3 pos_b = make_scalar3(bb_postype.x, bb_postype.y, bb_postype.z);

            // get the c-particle's position (MEM TRANSFER: 16 bytes)
            Scalar4 cc_postype = d_pos[cur_triangle_c];
            Scalar3 pos_c = make_scalar3(cc_postype.x, cc_postype.y, cc_postype.z);

            Scalar3 dab, dac;
            if (cur_triangle_abc == 0)
                {
                dab = pos_b - pos_a;
                dac = pos_c - pos_a;
                }
            else
                {
                dab = pos_a - pos_b;
                dac = pos_c - pos_b;
                }

            dab = box.minImage(dab);
            dac = box.minImage(dac);

            Scalar rab = dab.x * dab.x + dab.y * dab.y + dab.z * dab.z;
            rab = sqrt(rab);
            Scalar rac = dac.x * dac.x + dac.y * dac.y + dac.z * dac.z;
            rac = sqrt(rac);

            Scalar3 nab, nac;
            nab = dab / rab;
            nac = dac / rac;

            Scalar c_baac = nab.x * nac.x + nab.y * nac.y + nab.z * nac.z;

            if (c_baac > 1.0)
                c_baac = 1.0;
            if (c_baac < -1.0)
                c_baac = -1.0;

            Scalar s_baac = sqrt(1.0 - c_baac * c_baac);

            Scalar Area = rab * rac * s_baac / 6.0;
            area_transfer += Area;
            }
        }

    area_sdata[threadIdx.x] = area_transfer;
    __syncthreads();

    // reduce the sum in parallel
    int offs = blockDim.x >> 1;
    while (offs > 0)
        {
        if (threadIdx.x < offs)
            area_sdata[threadIdx.x] += area_sdata[threadIdx.x + offs];
        offs >>= 1;
        __syncthreads();
        }

    // write out our partial sum
    if (threadIdx.x == 0)
        d_partial_sum_area[blockIdx.x + tN * type_id] = area_sdata[0];
    }

//! Kernel function for reducing a partial sum to a full sum (one value)
/*! \param d_sum Placeholder for the sum
    \param d_partial_sum Array containing the partial sum
    \param num_blocks Number of blocks to execute
*/
__global__ void gpu_area_reduce_partial_sum_kernel(Scalar* d_sum,
                                                   Scalar* d_partial_sum,
                                                   unsigned int tN,
                                                   unsigned int type_id,
                                                   unsigned int num_blocks)
    {
    HIP_DYNAMIC_SHARED(char, s_data)
    Scalar* area_sdata = (Scalar*)&s_data[0];

    Scalar sum = Scalar(0.0);
    // sum up the values in the partial sum via a sliding window
    for (int start = 0; start < num_blocks; start += blockDim.x)
        {
        __syncthreads();
        if (start + threadIdx.x < num_blocks)
            area_sdata[threadIdx.x] = d_partial_sum[start + threadIdx.x + tN * type_id];
        else
            area_sdata[threadIdx.x] = Scalar(0.0);
        __syncthreads();

        // reduce the sum in parallel
        int offs = blockDim.x >> 1;
        while (offs > 0)
            {
            if (threadIdx.x < offs)
                area_sdata[threadIdx.x] += area_sdata[threadIdx.x + offs];
            offs >>= 1;
            __syncthreads();
            }

        // everybody sums up sum2K
        sum += area_sdata[0];
        }

    if (threadIdx.x == 0)
        d_sum[type_id] = sum;
    }

/*! \param d_sigma Device memory to write per paricle sigma
    \param d_sigma_dash Device memory to write per particle sigma_dash
    \param N number of particles
    \param d_pos device array of particle positions
    \param d_rtag device array of particle reverse tags
    \param box Box dimensions (in GPU format) to use for periodic boundary conditions
    \param blist List of mesh bonds stored on the GPU
    \param d_triangles device array of mesh triangles
    \param n_bonds_list List of numbers of mesh bonds stored on the GPU
    \param block_size Block size to use when performing calculations
    \param compute_capability Device compute capability (200, 300, 350, ...)

    \returns Any error code resulting from the kernel launch
    \note Always returns hipSuccess in release builds to avoid the hipDeviceSynchronize()
*/
hipError_t gpu_compute_area_constraint_area(Scalar* d_sum_area,
                                            Scalar* d_sum_partial_area,
                                            const unsigned int N,
                                            const unsigned int tN,
                                            const unsigned int type_id,
                                            const Scalar4* d_pos,
                                            const BoxDim& box,
                                            const group_storage<3>* tlist,
                                            const unsigned int* tpos_list,
                                            const Index2D tlist_idx,
                                            const unsigned int* n_triangles_list,
                                            unsigned int block_size,
                                            unsigned int num_blocks)
    {
    dim3 grid(num_blocks, 1, 1);
    dim3 grid1(1, 1, 1);
    dim3 threads(block_size, 1, 1);

    // run the kernel
    hipLaunchKernelGGL((gpu_compute_area_constraint_area_kernel),
                       dim3(grid),
                       dim3(threads),
                       block_size * sizeof(Scalar),
                       0,
                       d_sum_partial_area,
                       N,
                       tN,
		       type_id,
                       d_pos,
                       box,
                       tlist,
                       tpos_list,
                       tlist_idx,
                       n_triangles_list);

    hipLaunchKernelGGL((gpu_area_reduce_partial_sum_kernel),
                       dim3(grid1),
                       dim3(threads),
                       block_size * sizeof(Scalar),
                       0,
                       d_sum_area,
                       d_sum_partial_area,
                       tN,
		       type_id,
                       num_blocks);

    return hipSuccess;
    }

//! Kernel for calculating area_constraint sigmas on the GPU
/*! \param d_force Device memory to write computed forces
    \param d_virial Device memory to write computed virials
    \param virial_pitch
    \param N number of particles
    \param d_pos device array of particle positions
    \param d_rtag device array of particle reverse tags
    \param box Box dimensions (in GPU format) to use for periodic boundary conditions
    \param d_sigma Device memory to write per paricle sigma
    \param d_sigma_dash Device memory to write per particle sigma_dash
    \param blist List of mesh bonds stored on the GPU
    \param d_triangles device array of mesh triangles
    \param n_bonds_list List of numbers of mesh bonds stored on the GPU
    \param d_params K params packed as Scalar variables
    \param n_bond_type number of mesh bond types
    \param d_flags Flag allocated on the device for use in checking for bonds that cannot be
*/
__global__ void gpu_compute_area_constraint_force_kernel(Scalar4* d_force,
                                                         Scalar* d_virial,
                                                         const size_t virial_pitch,
                                                         const unsigned int N,
                                                         const Scalar4* d_pos,
                                                         BoxDim box,
                                                         const Scalar* area,
                                                         const group_storage<3>* tlist,
                                                         const unsigned int* tpos_list,
                                                         const Index2D tlist_idx,
                                                         const unsigned int* n_triangles_list,
                                                         Scalar2* d_params,
                                                         const unsigned int n_triangle_type,
                                                         unsigned int* d_flags)
    {
    // start by identifying which particle we are to handle
    int idx = blockIdx.x * blockDim.x + threadIdx.x;

    if (idx >= N)
        return;

    // load in the length of the list for this thread (MEM TRANSFER: 4 bytes)
    int n_triangles = n_triangles_list[idx];

    // read in the position of our b-particle from the a-b-c triplet. (MEM TRANSFER: 16 bytes)
    Scalar4 postype = __ldg(d_pos + idx);
    Scalar3 pos_a = make_scalar3(postype.x, postype.y, postype.z);

    Scalar4 force = make_scalar4(Scalar(0.0), Scalar(0.0), Scalar(0.0), Scalar(0.0));

    // initialize the virial to 0
    Scalar virial[6];
    for (int i = 0; i < 6; i++)
        virial[i] = Scalar(0.0);

    // loop over all triangles
    for (int triangle_idx = 0; triangle_idx < n_triangles; triangle_idx++)
        {
        group_storage<3> cur_triangle = tlist[tlist_idx(idx, triangle_idx)];

        int cur_triangle_b = cur_triangle.idx[0];
        int cur_triangle_c = cur_triangle.idx[1];
        int cur_triangle_type = cur_triangle.idx[2];

        // get the angle parameters (MEM TRANSFER: 8 bytes)
        Scalar2 params = __ldg(d_params + cur_triangle_type);
        Scalar K = params.x;
        Scalar A_mesh = params.y;

        Scalar AreaDiff = area[cur_triangle_type] - A_mesh;

        Scalar energy = K * AreaDiff * AreaDiff / (2 * A_mesh * N);

        AreaDiff = -K / A_mesh * AreaDiff / 2.0;

        int cur_triangle_abc = tpos_list[tlist_idx(idx, triangle_idx)];

        // get the b-particle's position (MEM TRANSFER: 16 bytes)
        Scalar4 bb_postype = d_pos[cur_triangle_b];
        Scalar3 pos_b = make_scalar3(bb_postype.x, bb_postype.y, bb_postype.z);

        // get the c-particle's position (MEM TRANSFER: 16 bytes)
        Scalar4 cc_postype = d_pos[cur_triangle_c];
        Scalar3 pos_c = make_scalar3(cc_postype.x, cc_postype.y, cc_postype.z);

        Scalar3 dab, dac;
        if (cur_triangle_abc == 0)
            {
            dab = pos_b - pos_a;
            dac = pos_c - pos_a;
            }
        else
            {
            if (cur_triangle_abc == 1)
                {
                dab = pos_a - pos_b;
                dac = pos_c - pos_b;
                }
            else
                {
                dab = pos_c - pos_b;
                dac = pos_a - pos_b;
                }
            }

        dab = box.minImage(dab);
        dac = box.minImage(dac);

        Scalar rab = dab.x * dab.x + dab.y * dab.y + dab.z * dab.z;
        rab = sqrt(rab);
        Scalar rac = dac.x * dac.x + dac.y * dac.y + dac.z * dac.z;
        rac = sqrt(rac);

        Scalar3 nab, nac;
        nab = dab / rab;
        nac = dac / rac;

        Scalar c_baac = nab.x * nac.x + nab.y * nac.y + nab.z * nac.z;

        if (c_baac > 1.0)
            c_baac = 1.0;
        if (c_baac < -1.0)
            c_baac = -1.0;

        Scalar s_baac = sqrt(1.0 - c_baac * c_baac);
        Scalar inv_s_baac = 1.0 / s_baac;

        Scalar3 dc_dra;
        if (cur_triangle_abc == 0)
            {
            dc_dra = -nac / rab - nab / rac + c_baac / rab * nab + c_baac / rac * nac;
            }
        else
            {
            if (cur_triangle_abc == 1)
                {
                dc_dra = nac / rab - c_baac / rab * nab;
                }
            else
                {
                dc_dra = nab / rac - c_baac / rac * nac;
                }
            }

        Scalar3 ds_dra = -c_baac * inv_s_baac * dc_dra;

        Scalar3 Fa;

        if (cur_triangle_abc == 0)
            {
            Fa = -nab * rac * s_baac - nac * rab * s_baac + ds_dra * rab * rac;
            }
        else
            {
            if (cur_triangle_abc == 1)
                {
                Fa = nab * rac * s_baac + ds_dra * rab * rac;
                }
            else
                {
                Fa = nac * rab * s_baac + ds_dra * rab * rac;
                }
            }

        Fa.x = AreaDiff * Fa.x;
        Fa.y = AreaDiff * Fa.y;
        Fa.z = AreaDiff * Fa.z;

        force.x += Fa.x;
        force.y += Fa.y;
        force.z += Fa.z;
        force.w = energy;

        virial[0] += Scalar(1. / 2.) * pos_a.x * Fa.x; // xx
        virial[1] += Scalar(1. / 2.) * pos_a.y * Fa.x; // xy
        virial[2] += Scalar(1. / 2.) * pos_a.z * Fa.x; // xz
        virial[3] += Scalar(1. / 2.) * pos_a.y * Fa.y; // yy
        virial[4] += Scalar(1. / 2.) * pos_a.z * Fa.y; // yz
        virial[5] += Scalar(1. / 2.) * pos_a.z * Fa.z; // zz
        }

    // now that the force calculation is complete, write out the result (MEM TRANSFER: 20 bytes)
    d_force[idx] = force;

    for (unsigned int i = 0; i < 6; i++)
        d_virial[i * virial_pitch + idx] = virial[i];
    }

/*! \param d_force Device memory to write computed forces
    \param d_virial Device memory to write computed virials
    \param N number of particles
    \param d_pos device array of particle positions
    \param d_rtag device array of particle reverse tags
    \param box Box dimensions (in GPU format) to use for periodic boundary conditions
    \param d_sigma Device memory to write per paricle sigma
    \param d_sigma_dash Device memory to write per particle sigma_dash
    \param blist List of mesh bonds stored on the GPU
    \param d_triangles device array of mesh triangles
    \param n_bonds_list List of numbers of mesh bonds stored on the GPU
    \param d_params K params packed as Scalar variables
    \param n_bond_type number of mesh bond types
    \param block_size Block size to use when performing calculations
    \param d_flags Flag allocated on the device for use in checking for bonds that cannot be
    \param compute_capability Device compute capability (200, 300, 350, ...)

    \returns Any error code resulting from the kernel launch
    \note Always returns hipSuccess in release builds to avoid the hipDeviceSynchronize()
*/
hipError_t gpu_compute_area_constraint_force(Scalar4* d_force,
                                             Scalar* d_virial,
                                             const size_t virial_pitch,
                                             const unsigned int N,
                                             const Scalar4* d_pos,
                                             const BoxDim& box,
                                             const Scalar* area,
                                             const group_storage<3>* tlist,
                                             const unsigned int* tpos_list,
                                             const Index2D tlist_idx,
                                             const unsigned int* n_triangles_list,
                                             Scalar2* d_params,
                                             const unsigned int n_triangle_type,
                                             int block_size,
                                             unsigned int* d_flags)
    {
    unsigned int max_block_size;
    hipFuncAttributes attr;
    hipFuncGetAttributes(&attr, (const void*)gpu_compute_area_constraint_force_kernel);
    max_block_size = attr.maxThreadsPerBlock;

    unsigned int run_block_size = min(block_size, max_block_size);

    // setup the grid to run the kernel
    dim3 grid(N / run_block_size + 1, 1, 1);
    dim3 threads(run_block_size, 1, 1);

    // run the kernel
    hipLaunchKernelGGL((gpu_compute_area_constraint_force_kernel),
                       dim3(grid),
                       dim3(threads),
                       0,
                       0,
                       d_force,
                       d_virial,
                       virial_pitch,
                       N,
                       d_pos,
                       box,
                       area,
                       tlist,
                       tpos_list,
                       tlist_idx,
                       n_triangles_list,
                       d_params,
                       n_triangle_type,
                       d_flags);

    return hipSuccess;
    }

    } // end namespace kernel
    } // end namespace md
    } // end namespace hoomd
