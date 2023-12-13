// Copyright (c) 2009-2023 The Regents of the University of Michigan.
// Part of HOOMD-blue, released under the BSD 3-Clause License.

#include "PairPotentialLennardJones.h"

namespace hoomd
    {
namespace hpmc
    {

PairPotentialLennardJones::PairPotentialLennardJones(std::shared_ptr<SystemDefinition> sysdef)
    : PairPotential(sysdef), m_type_param_index(sysdef->getParticleData()->getNTypes()),
      m_params(sysdef->getParticleData()->getNTypes())
    {
    }

ShortReal PairPotentialLennardJones::getRCut()
    {
    ShortReal r_cut = 0;
    for (const auto& param : m_params)
        {
        r_cut = std::max(r_cut, slow::sqrt(param.r_cut_squared));
        }
    return r_cut;
    }

ShortReal PairPotentialLennardJones::energy(const vec3<ShortReal>& r_ij,
                                            unsigned int type_i,
                                            const quat<ShortReal>& q_i,
                                            ShortReal charge_i,
                                            unsigned int type_j,
                                            const quat<ShortReal>& q_j,
                                            ShortReal charge_j)
    {
    ShortReal r_squared = dot(r_ij, r_ij);

    unsigned int param_index = m_type_param_index(type_i, type_j);
    const auto& param = m_params[param_index];
    if (r_squared > param.r_cut_squared)
        return 0;

    ShortReal lj1 = param.epsilon_x_4 * param.sigma_6 * param.sigma_6;
    ShortReal lj2 = param.epsilon_x_4 * param.sigma_6;

    ShortReal r_2_inverse = ShortReal(1.0) / r_squared;
    ShortReal r_6_inverse = r_2_inverse * r_2_inverse * r_2_inverse;

    ShortReal energy = r_6_inverse * (lj1 * r_6_inverse - lj2);

    if (param.mode == shift)
        {
        ShortReal r_cut_2_inverse = ShortReal(1.0) / param.r_cut_squared;
        ShortReal r_cut_6_inverse = r_cut_2_inverse * r_cut_2_inverse * r_cut_2_inverse;
        energy -= r_cut_6_inverse * (lj1 * r_cut_6_inverse - lj2);
        }

    if (param.mode == xplor && r_squared > param.r_on_squared)
        {
        ShortReal a = param.r_cut_squared - param.r_on_squared;
        ShortReal denominator = a * a * a;

        ShortReal b = param.r_cut_squared - r_squared;
        ShortReal numerator = b * b
                              * (param.r_cut_squared + ShortReal(2.0) * r_squared
                                 - ShortReal(3.0) * param.r_on_squared);
        energy *= numerator / denominator;
        }

    return energy;
    }

void PairPotentialLennardJones::setParamsPython(pybind11::tuple typ, pybind11::dict params)
    {
    auto pdata = m_sysdef->getParticleData();
    auto type_i = pdata->getTypeByName(typ[0].cast<std::string>());
    auto type_j = pdata->getTypeByName(typ[1].cast<std::string>());
    unsigned int param_index = m_type_param_index(type_i, type_j);
    m_params[param_index] = ParamType(params);
    }

pybind11::dict PairPotentialLennardJones::getParamsPython(pybind11::tuple typ)
    {
    auto pdata = m_sysdef->getParticleData();
    auto type_i = pdata->getTypeByName(typ[0].cast<std::string>());
    auto type_j = pdata->getTypeByName(typ[1].cast<std::string>());
    unsigned int param_index = m_type_param_index(type_i, type_j);
    return m_params[param_index].asDict();
    }

namespace detail
    {
void export_PairPotentialLennardJones(pybind11::module& m)
    {
    pybind11::class_<PairPotentialLennardJones,
                     PairPotential,
                     std::shared_ptr<PairPotentialLennardJones>>(m, "PairPotentialLennardJones")
        .def(pybind11::init<std::shared_ptr<SystemDefinition>>())
        .def("setParams", &PairPotentialLennardJones::setParamsPython)
        .def("getParams", &PairPotentialLennardJones::getParamsPython);
    }
    } // end namespace detail
    } // end namespace hpmc
    } // end namespace hoomd
