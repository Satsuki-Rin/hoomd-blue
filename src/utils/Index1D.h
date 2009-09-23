/*!
Highly Optimized Object-oriented Many-particle Dynamics -- Blue Edition
(HOOMD-blue) Open Source Software License Copyright 2008, 2009 Ames Laboratory
Iowa State University and The Regents of the University of Michigan All rights
reserved.

HOOMD-blue may contain modifications ("Contributions") provided, and to which
copyright is held, by various Contributors who have granted The Regents of the
University of Michigan the right to modify and/or distribute such Contributions.

Redistribution and use of HOOMD-blue, in source and binary forms, with or
without modification, are permitted, provided that the following conditions are
met:

* Redistributions of source code must retain the above copyright notice, this
list of conditions, and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this
list of conditions, and the following disclaimer in the documentation and/or
other materials provided with the distribution.

* Neither the name of the copyright holder nor the names of HOOMD-blue's
contributors may be used to endorse or promote products derived from this
software without specific prior written permission.

Disclaimer

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER AND CONTRIBUTORS ``AS IS''
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND/OR
ANY WARRANTIES THAT THIS SOFTWARE IS FREE OF INFRINGEMENT ARE DISCLAIMED.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// $Id$
// $URL$
// Maintainer: joaander

/*! \file Index1D.h
	\brief Defines utility classes for 1D indexing of multi-dimensional arrays
    \detailed These are very low-level, high performance functions. No error checking is performed on their arguments,
    even in debug mode. They are provided mainly as a convenience.
*/

//! Index a 2D array
/*! Row major mapping of 2D onto 1D
    \ingroup utils
*/
class Index2D
    {
    public:
        //! Contstructor
        /*! \param w Width of the 2D array
        */
        inline Index2D(unsigned int w) : m_w(w) {}
        
        //! Calculate an index
        /*! \param i row index
            \param j column index
            \param w width of the 2D array
            \returns 1D array index corresponding to the 2D index (\a i, \a j) in row major order
        */
        inline unsigned int operator()(unsigned int i, unsigned int j)
            {
            return i*m_w + j;
            }
            
        //! Get the number of 1D elements stored
        /*! \returns Number of elements stored in the underlying 1D array
        */
        inline unsigned int getNumElements()
            {
            return m_w*m_w;
            }
        
    private:
        unsigned int m_w;   //!< Width of the 2D array
    };

//! Index a 2D upper triangular array
/*! Row major mapping of a 2D upper triangular array onto 1D
    \ingroup utils
*/
class Index2DUpperTriangular
    {
    public:
        //! Contstructor
        /*! \param w Width of the 2D upper triangular array
        */
        inline Index2DUpperTriangular(unsigned int w) : m_w(w) 
            {
            m_term = 2*m_w - 1;
            }
        
        //! Calculate an index
        /*! \param i row index
            \param j column index
            \param w width of the 2D triangular array
            \pre i <= j
            \returns 1D array index corresponding to the 2D index (\a i, \a j) in row major order
            \note Forumla adapted from: http://www.itl.nist.gov/div897/sqg/dads/HTML/upperTriangularMatrix.html
        */
        inline unsigned int operator()(unsigned int i, unsigned int j)
            {
            return i * (m_term - i) / 2 + j;
            }
            
        //! Get the number of 1D elements stored
        /*! \returns Number of elements stored in the underlying 1D array
        */
        inline unsigned int getNumElements()
            {
            return m_w*(m_w+1) / 2;
            }
        
    private:
        unsigned int m_w;     //!< Width of the 2D upper triangular array
        unsigned int m_term;  //!< Precomputed term of the equation for efficiency
    };    