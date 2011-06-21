#!/usr/bin/python 
#
# Cython version of the Navarro & Fuss, 2009 DDM PDF. Based directly
# on the following code by Navarro & Fuss:
# http://www.psychocmath.logy.adelaide.edu.au/personalpages/staff/danielnavarro/resources/wfpt.m
#
# This implementation is about 170 times faT than the matlab
# reference version.
#
# Copyleft Thomas Wiecki (thomas_wiecki[at]brown.edu), 2010 
# GPLv3

from copy import copy
import numpy as np
cimport numpy as np

cimport cython

include "wfpt.pyx"

@cython.wraparound(False)
@cython.boundscheck(False) # turn of bounds-checking for entire function
def wiener_like_full_intrp(np.ndarray[DTYPE_t, ndim=1] x, double v, double V, double a, double z, double Z, double t, 
                           double T, double err, int nT= 10, int nZ=10, bint use_adaptive=1, double simps_err=1e-8):
    cdef Py_ssize_t i
    cdef double p
    cdef sum_logp = 0
    
    for i from 0 <= i < x.shape[0]:
        p = full_pdf(x[i], v, V, a, z, Z, t, T, err, nT, nZ, use_adaptive, simps_err)
        # If one probability = 0, the log sum will be -Inf
        if p == 0:
            return -infinity
        sum_logp += log(p)
        
    return sum_logp


cpdef double simpson_1D(double x, double v, double V, double a, double z, double t, double err, 
                        double lb_z, double ub_z, int nZ, double lb_t, double ub_t, int nT):
    assert ((nZ&1)==0 and (nT&1)==0), "nT and nZ have to be even"
    assert ((ub_t-lb_t)*(ub_z-lb_z)==0 and (nZ*nT)==0), "the function is defined for 1D-integration only"
    
    cdef double ht, hz
    cdef int n = max(nT,nZ)
    if nT==0: #integration over z
        hz = (ub_z-lb_z)/n
        ht = 0
        lb_t = t
        ub_t = t
    else: #integration over t
        hz = 0
        ht = (ub_t-lb_t)/n
        lb_z = z
        ub_z = z

    cdef double S = pdf_V(x - lb_t, v, V, a, lb_z, err)
    cdef double z_tag, t_tag, y
    cdef int i
    
    for i from 1 <= i <= n:
        z_tag = lb_z + hz * i
        t_tag = lb_t + ht * i
        y = pdf_V(x - t_tag, v, V, a, z_tag, err)
        if i&1: #check if i is odd
            S += (4 * y)
        else:
            S += (2 * y)
    S = S - y #the last term should be f(b) and not 2*f(b) so we subtract y
    S = S / ((ub_t-lb_t)+(ub_z-lb_z)) #the right function if pdf_V()/Z or pdf_V()/T

    return ((ht+hz) * S / 3)

cpdef double simpson_2D(double x, double v, double V, double a, double z, double t, double err, double lb_z, double ub_z, int nZ, double lb_t, double ub_t, int nT):
    assert ((nZ&1)==0 and (nT&1)==0), "nT and nZ have to be even"
    assert ((ub_t-lb_t)*(ub_z-lb_z)>0 and (nZ*nT)>0), "the function is defined for 2D-integration only, lb_t: %f, ub_t %f, lb_z %f, ub_z %f, nZ: %d, nT %d" % (lb_t, ub_t, lb_z, ub_z, nZ, nT)

    cdef double ht
    cdef double S
    cdef double t_tag, y
    cdef int i_t

    ht = (ub_t-lb_t)/nT

    S = simpson_1D(x, v, V, a, z, lb_t, err, lb_z, ub_z, nZ, 0, 0, 0)

    for i_t  from 1 <= i_t <= nT:
        t_tag = lb_t + ht * i_t
        y = simpson_1D(x, v, V, a, z, t_tag, err, lb_z, ub_z, nZ, 0, 0, 0)
        if i_t&1: #check if i is odd
            S += (4 * y)
        else:
            S += (2 * y)
    S = S - y #the last term should be f(b) and not 2*f(b) so we subtract y
    S = S/ (ub_t-lb_t)

    return (ht * S / 3)

cpdef double adaptiveSimpsonsAux(double x, double v, double V, double a, double z, double t, double pdf_err,
                                 double lb_z, double ub_z, double lb_t, double ub_t, double ZT, double simps_err,
                                 double S, double f_beg, double f_end, double f_mid, int bottom):
    
    cdef double z_c, z_d, z_e, t_c, t_d, t_e, h
    cdef double fd, fe
    cdef double Sleft, Sright, S2
    #print "in AdaptiveSimpsAux: lb_z: %f, ub_z: %f, lb_t %f, ub_t %f, f_beg: %f, f_end: %f, bottom: %d" % (lb_z, ub_z, lb_t, ub_t, f_beg, f_end, bottom)
    
    if (ub_t-lb_t) == 0: #integration over Z
        h = ub_z - lb_z
        z_c = (ub_z + lb_z)/2.
        z_d = (lb_z + z_c)/2.
        z_e = (z_c  + ub_z)/2.
        t_c = t
        t_d = t
        t_e = t
    
    else: #integration over t
        h = ub_t - lb_t
        t_c = (ub_t + lb_t)/2.
        t_d = (lb_t + t_c)/2.
        t_e = (t_c  + ub_t)/2.
        z_c = z
        z_d = z
        z_e = z
    
    fd = pdf_V(x - t_d, v, V, a, z_d, pdf_err)/ZT
    fe = pdf_V(x - t_e, v, V, a, z_e, pdf_err)/ZT
    
    Sleft = (h/12)*(f_beg + 4*fd + f_mid)
    Sright = (h/12)*(f_mid + 4*fe + f_end)
    S2 = Sleft + Sright                                          
    if (bottom <= 0 or fabs(S2 - S) <= 15*simps_err):
        return S2 + (S2 - S)/15
    return adaptiveSimpsonsAux(x, v, V, a, z, t, pdf_err,
                                 lb_z, z_c, lb_t, t_c, ZT, simps_err/2,
                                 Sleft, f_beg, f_mid, fd, bottom-1) + \
            adaptiveSimpsonsAux(x, v, V, a, z, t, pdf_err,
                                 z_c, ub_z, t_c, ub_t, ZT, simps_err/2,
                                 Sright, f_mid, f_end, fe, bottom-1)
 
cpdef double adaptiveSimpsons_1D(double x, double v, double V, double a, double z, double t, 
                              double pdf_err, double lb_z, double ub_z, double lb_t, double ub_t, 
                              double simps_err, int maxRecursionDepth):

    cdef double h
    
    if (ub_t - lb_t) == 0: #integration over z
        lb_t = t
        ub_t = t
        h = ub_z - lb_z
    else: #integration over t
        h = (ub_t-lb_t)
        lb_z = z
        ub_z = z
    
    cdef double ZT = h
    cdef double c_t = (lb_t + ub_t)/2.
    cdef double c_z = (lb_z + ub_z)/2.

    cdef double f_beg, f_end, f_mid, S
    f_beg = pdf_V(x - lb_t, v, V, a, lb_z, pdf_err)/ZT
    f_end = pdf_V(x - ub_t, v, V, a, ub_z, pdf_err)/ZT
    f_mid = pdf_V(x - c_t, v, V, a, c_z, pdf_err)/ZT
    S = (h/6)*(f_beg + 4*f_mid + f_end)                                 
    cdef double res =  adaptiveSimpsonsAux(x, v, V, a, z, t, pdf_err,
                                 lb_z, ub_z, lb_t, ub_t, ZT, simps_err,           
                                 S, f_beg, f_end, f_mid, maxRecursionDepth)
    return res

cdef double adaptiveSimpsonsAux_2D(double x, double v, double V, double a, double z, double t, double pdf_err, double err_1d,
                                 double lb_z, double ub_z, double lb_t, double ub_t, double T, double err_2d,
                                 double S, double f_beg, double f_end, double f_mid, int maxRecursionDepth_Z, int bottom):

    cdef double fd, fe
    cdef double Sleft, Sright, S2
    #print "in AdaptiveSimpsAux_2D: lb_z: %f, ub_z: %f, lb_t %f, ub_t %f, f_beg: %f, f_end: %f, bottom: %d" % (lb_z, ub_z, lb_t, ub_t, f_beg, f_end, bottom)
    
    cdef double t_c = (ub_t + lb_t)/2.
    cdef double t_d = (lb_t + t_c)/2.
    cdef double t_e = (t_c  + ub_t)/2.
    cdef double h = ub_t - lb_t
    
    fd = adaptiveSimpsons_1D(x, v, V, a, z, t_d, pdf_err, lb_z, ub_z,
                              0, 0, err_1d, maxRecursionDepth_Z)/T
    fe = adaptiveSimpsons_1D(x, v, V, a, z, t_e, pdf_err, lb_z, ub_z,
                              0, 0, err_1d, maxRecursionDepth_Z)/T
    
    Sleft = (h/12)*(f_beg + 4*fd + f_mid)
    Sright = (h/12)*(f_mid + 4*fe + f_end)
    S2 = Sleft + Sright

    if (bottom <= 0 or fabs(S2 - S) <= 15*err_2d):                                     
        return S2 + (S2 - S)/15;
        
    return adaptiveSimpsonsAux_2D(x, v, V, a, z, t, pdf_err, err_1d,
                                 lb_z, ub_z, lb_t, t_c, T, err_2d/2,
                                 Sleft, f_beg, f_mid, fd, maxRecursionDepth_Z, bottom-1) + \
            adaptiveSimpsonsAux_2D(x, v, V, a, z, t, pdf_err, err_1d,
                                 lb_z, ub_z, t_c, ub_t, T, err_2d/2,
                                 Sright, f_mid, f_end, fe, maxRecursionDepth_Z, bottom-1)
                             
                                 
        
cpdef double adaptiveSimpsons_2D(double x, double v, double V, double a, double z, double t,  
                                 double pdf_err, double lb_z, double ub_z, double lb_t, double ub_t, 
                                 double simps_err, int maxRecursionDepth_Z, maxRecursionDepth_T):

    cdef double h = (ub_t-lb_t)
    
    cdef double T = (ub_t - lb_t)
    cdef double c_t = (lb_t + ub_t)/2.
    cdef double c_z = (lb_z + ub_z)/2.
 
    cdef double f_beg, f_end, f_mid, S
    cdef double err_1d = simps_err
    cdef double err_2d = simps_err
    
    f_beg = adaptiveSimpsons_1D(x, v, V, a, z, lb_t, pdf_err, lb_z, ub_z,
                              0, 0, err_1d, maxRecursionDepth_Z)/T

    f_end = adaptiveSimpsons_1D(x, v, V, a, z, ub_t, pdf_err, lb_z, ub_z,
                              0, 0, err_1d, maxRecursionDepth_Z)/T
    f_mid = adaptiveSimpsons_1D(x, v, V, a, z, (lb_t+ub_t)/2, pdf_err, lb_z, ub_z, 
                              0, 0, err_1d, maxRecursionDepth_Z)/T
    S = (h/6)*(f_beg + 4*f_mid + f_end)    
    cdef double res =  adaptiveSimpsonsAux_2D(x, v, V, a, z, t, pdf_err, err_1d,
                                 lb_z, ub_z, lb_t, ub_t, T, err_2d,
                                 S, f_beg, f_end, f_mid, maxRecursionDepth_Z, maxRecursionDepth_T)
    return res

cpdef double full_pdf(double x, double v, double V, double a, double z, double Z, 
                     double t, double T, double err, int nT=2, int nZ=2, bint use_adaptive = 1, double simps_err = 1e-3):
    """full pdf"""

    # Check if parpameters are valid
    if z<0 or z>1 or a<0 or ((fabs(x)-(t-T/2.))<0) or (z+Z/2.>1) or (z-Z/2.<0) or (t-T/2.<0) or (t<0):
        return 0

    # transform x,v,z if x is upper bound response
    if x > 0:
        v = -v
        z = 1.-z
    
    x = fabs(x)
    
    if T<1e-3:
        T = 0
    if Z <1e-3:
        Z = 0  

    if (Z==0):
        if (T==0): #V=0,Z=0,T=0
            return pdf_V(x - t, v, V, a, z, err)
        else:      #V=0,Z=0,T=$
            if use_adaptive>0:
                return adaptiveSimpsons_1D(x,  v, V, a, z, t, err, z, z, t-T/2., t+T/2., simps_err, nT)
            else:
                return simpson_1D(x, v, V, a, z, t, err, z, z, 0, t-T/2., t+T/2., nT)
            
    else: #Z=$
        if (T==0): #V=0,Z=$,T=0
            if use_adaptive:
                return adaptiveSimpsons_1D(x, v, V, a, z, t, err, z-Z/2., z+Z/2., t, t, simps_err, nZ)
            else:
                return simpson_1D(x, v, V, a, z, t, err, z-Z/2., z+Z/2., nZ, t, t , 0)
        else:      #V=0,Z=$,T=$
            if use_adaptive:
                return adaptiveSimpsons_2D(x, v, V, a, z, t, err, z-Z/2., z+Z/2., t-T/2., t+T/2., simps_err, nZ, nT)
            else:
                return simpson_2D(x, v, V, a, z, t, err, z-Z/2., z+Z/2., nZ, t-T/2., t+T/2., nT)

@cython.wraparound(False)
@cython.boundscheck(False) # turn of bounds-checking for entire function
def wiener_like_full(np.ndarray[DTYPE_t, ndim=1] x, np.ndarray[DTYPE_t, ndim=1] v, np.ndarray[DTYPE_t, ndim=1] a, np.ndarray[DTYPE_t, ndim=1] z, np.ndarray[DTYPE_t, ndim=1] t, err):
    cdef Py_ssize_t size = x.shape[0]
    cdef Py_ssize_t i
    cdef double p
    cdef double sum_logp = 0

    for i from 0 <= i < size:
        p = pdf_sign(x[i], v[i], a[i], z[i], t[i], err)
        # If one probability = 0, the log sum will be -Inf
        if p == 0:
            return -infinity
        sum_logp += log(p)

    return sum_logp


@cython.wraparound(False)
@cython.boundscheck(False) # turn of bounds-checking for entire function
def wiener_like_full_collCont(np.ndarray[DTYPE_t, ndim=1] x, np.ndarray[bint, ndim=1] cont_x, double gamma, double v, double V, double a, double z, double Z, 
                     double t, double T, double t_min, double t_max, double err=1e-4, int nT=2, int nZ=2, bint use_adaptive = 1, double simps_err = 1e-3):
    """Wiener likelihood function where RTs could come from a
    separate, uniform contaminant distribution.

    Reference: Lee, Vandekerckhove, Navarro, & Tuernlinckx (2007)
    """
    return 0
#    cdef Py_ssize_t i
#    cdef double p
#    cdef sum_logp = 0
#    for i from 0 <= i < x.shape[0]:
#        if cont_x[i] == 1:
#            p = full_pdf(x[i], v, V, a, z, Z, t, T, err, nT, nZ, use_adaptive, simps_err)
#        elif cont_y[i] == 0:
#            p = prob_boundary(x[i], v, a, z, t, err) * 1./(t_max-t_min)
#        else:
#            p = .5 * 1./(t_max-t_min)
#        #print p, x[i], v, a, z, t, err, t_max, t_min, cont_x[i], cont_y[i]
#        # If one probability = 0, the log sum will be -Inf
#        if p == 0:
#            return -infinity
#
#        sum_logp += log(p)
#        
#    return sum_logp



@cython.wraparound(False)
@cython.boundscheck(False) # turn of bounds-checking for entire function
def wiener_like_full_multi(np.ndarray[DTYPE_t, ndim=1] x, v, V, a, z, Z, t, T, double err, multi=None):
    cdef unsigned int size = x.shape[0]
    cdef unsigned int i
    cdef double p = 0

    if multi is None:
        return wiener_like_full_intrp(x, v, V, a, z, Z, t, T, err)
    else:
        params = {'v':v, 'z':z, 't':t, 'a':a, 'V':V, 'Z':Z, 'T':T}
        params_iter = copy(params)
        for i from 0 <= i < size:
            for param in multi:
                params_iter[param] = params[param][i]
                
            p += log(full_pdf(x[i], params_iter['v'],
                              params_iter['V'], params_iter['a'], params_iter['z'],
                              params_iter['Z'], params_iter['t'], params_iter['T'],
                              err))
        return p
    
@cython.wraparound(False)
@cython.boundscheck(False) # turn of bounds-checking for entire function
def gen_rts_from_cdf(double v, double V, double a, double z, double Z, double t, \
                           double T, int samples=1000, double cdf_lb = -6, double cdf_ub = 6, double dt=1e-2):
    
    cdef np.ndarray[DTYPE_t, ndim=1] x = np.arange(cdf_lb, cdf_ub, dt)
    cdef np.ndarray[DTYPE_t, ndim=1] l_cdf = np.empty(x.shape[0], dtype=DTYPE)
    cdef double pdf, rt
    cdef Py_ssize_t i, j
    cdef int idx
    
    l_cdf[0] = 0
    for i from 1 <= i < x.shape[0]:
        pdf = full_pdf(x[i], v, V, a, z, Z, 0, 0, 1e-4)
        l_cdf[i] = l_cdf[i-1] + pdf
    
    l_cdf /= l_cdf[x.shape[0]-1]
    
    cdef np.ndarray[DTYPE_t, ndim=1] rts = np.empty(samples, dtype=DTYPE)
    cdef np.ndarray[DTYPE_t, ndim=1] f = np.random.rand(samples)
    cdef np.ndarray[DTYPE_t, ndim=1] delay
    
    if T!=0:
        delay = (np.random.rand(samples)*T + (t - T/2.))
    for i from 0 <= i < samples:
        idx = np.searchsorted(l_cdf, f[i])
        rt = x[idx]
        if T==0:
            rt = rt + np.sign(rt)*t
        else:
            rt = rt + np.sign(rt)*delay[i]
        rts[i] = rt
    return rts

@cython.wraparound(False)
@cython.boundscheck(False) # turn of bounds-checking for entire function
def wiener_like_full_contaminant(np.ndarray[DTYPE_t, ndim=1] value, np.ndarray[int_DTYPE_t, ndim=1] cont_x, double gamma, double v, double V, double a, double z, double Z, double t, double T, double t_min, double t_max, double err):
    """Wiener likelihood function where RTs could come from a
    separate, uniform contaminant distribution.

    Reference: Lee, Vandekerckhove, Navarro, & Tuernlinckx (2007)
    """
    cdef Py_ssize_t i
    cdef double p
    cdef double sum_logp = 0
    cdef int n_cont = np.sum(cont_x)
    cdef int pos_cont = 0
    
    for i from 0 <= i < value.shape[0]:
        if cont_x[i] == 0:
            p = full_pdf(value[i], v, V, a, z, Z, t, T, err)
            if p == 0:
                return -infinity
            sum_logp += log(p)      
        elif value[i]>0:
            pos_cont += 1
        # If one probability = 0, the log sum will be -Inf
        
    
    # add the log likelihood of the contaminations
    #first the guesses
    sum_logp += n_cont*log(gamma*(0.5 * 1./(t_max-t_min)))     
    #then the positive prob_boundary 
    sum_logp += pos_cont*log((1-gamma) * prob_ub(v, a, z) * 1./(t_max-t_min))
    #and the negative prob_boundary
    sum_logp += (n_cont - pos_cont)*log((1-gamma)*(1-prob_ub(v, a, z)) * 1./(t_max-t_min))

    return sum_logp
