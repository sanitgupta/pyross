import  numpy as np
cimport numpy as np
cimport cython

DTYPE   = np.float
ctypedef np.float_t DTYPE_t
@cython.wraparound(False)
@cython.boundscheck(False)
@cython.cdivision(True)
@cython.nonecheck(False)
cdef class SIR:
    """
    Susceptible, Infected, Recovered (SIR)
    Ia: asymptomatic
    Is: symptomatic
    """
    cdef:
        readonly int N, M,
        readonly double alpha, beta, gIa, gIs, fsa
        readonly np.ndarray rp0, Ni, drpdt, CM, FM, CC

    def __init__(self, parameters, M, Ni):
        self.alpha = parameters.get('alpha')                    # fraction of asymptomatic infectives
        self.beta  = parameters.get('beta')                     # infection rate
        self.gIa   = parameters.get('gIa')                      # recovery rate of Ia
        self.gIs   = parameters.get('gIs')                      # recovery rate of Is
        self.fsa   = parameters.get('fsa')                      # the self-isolation parameter

        self.N     = np.sum(Ni)
        self.M     = M
        self.Ni    = np.zeros( self.M, dtype=DTYPE)             # # people in each age-group
        self.Ni    = Ni

        self.CM    = np.zeros( (self.M, self.M), dtype=DTYPE)   # contact matrix C
        self.FM    = np.zeros( self.M, dtype = DTYPE)           # seed function F
        self.drpdt = np.zeros( 3*self.M, dtype=DTYPE)           # right hand side


    cdef rhs(self, rp, tt):
        cdef:
            int N=self.N, M=self.M, i, j
            double alpha=self.alpha, beta=self.beta, gIa=self.gIa, aa, bb
            double fsa=self.fsa, alphab=1-self.alpha,gIs=self.gIs
            double [:] S    = rp[0  :M]
            double [:] Ia   = rp[M  :2*M]
            double [:] Is   = rp[2*M:3*M]
            double [:] Ni   = self.Ni
            double [:,:] CM = self.CM
            double [:]   FM = self.FM
            double [:] X    = self.drpdt

        for i in range(M):
            bb=0
            for j in range(M):
                 bb += beta*CM[i,j]*(Ia[j]+fsa*Is[j])/Ni[j]
            aa = bb*S[i]
            X[i]     = -aa - FM[i]
            X[i+M]   = alpha *aa - gIa*Ia[i] + alpha * FM[i]
            X[i+2*M] = alphab*aa - gIs*Is[i] + alphab* FM[i]
        return


    def simulate(self, S0, Ia0, Is0, contactMatrix, Tf, Nf, Ti=0, integrator='odeint', seedRate=None):
        from scipy.integrate import odeint

        def rhs0(rp, t):
            self.CM = contactMatrix(t)
            if None != seedRate :
                self.FM = seedRate(t)
            else :
                self.FM = np.zeros( self.M, dtype = DTYPE)
            self.rhs(rp, t)
            return self.drpdt

        if integrator=='odeint':
            time_points=np.linspace(Ti, Tf, Nf);  ## intervals at which output is returned by integrator.
            u = odeint(rhs0, np.concatenate((S0, Ia0, Is0)), time_points, mxstep=100000)
        else:
            import odespy
            time_points=np.linspace(Ti, Tf, Nf);  ## intervals at which output is returned by integrator.
            solver = odespy.Vode(rhs0, method = 'bdf', atol=1E-7, rtol=1E-6, order=5, nsteps=10**6)
            #solver = odespy.RKF45(rhs0)
            #solver = odespy.RK4(rhs0)
            solver.set_initial_condition(np.concatenate((S0, Ia0, Is0)))
            u, time_points = solver.solve(time_points)

        data={'X':u, 't':time_points, 'N':self.N, 'M':self.M,'alpha':self.alpha, 'beta':self.beta,'gIa':self.gIa, 'gIs':self.gIs }
        return data




@cython.wraparound(False)
@cython.boundscheck(False)
@cython.cdivision(True)
@cython.nonecheck(False)
cdef class SIRS:
    """
    Susceptible, Infected, Recovered, Susceptible (SIRS)
    Ia: asymptomatic
    Is: symptomatic
    """
    cdef:
        readonly int N, M,
        readonly double alpha, beta, gIa, gIs, fsa, ep
        readonly np.ndarray rp0, Ni, drpdt, CM, FM, CC, sa, iaa

    def __init__(self, parameters, M, Ni):
        self.alpha = parameters.get('alpha')                    # fraction of asymptomatic infectives
        self.beta  = parameters.get('beta')                     # infection rate
        self.gIa   = parameters.get('gIa')                      # recovery rate of Ia
        self.gIs   = parameters.get('gIs')                      # recovery rate of Is
        self.fsa   = parameters.get('fsa')                      # the self-isolation parameter of symptomatics

        self.ep    = parameters.get('ep')                       # fraction of recovered who is susceptible
        sa         = parameters.get('sa')                       # daily arrival of new susceptibles
        iaa        = parameters.get('iaa')                      # daily arrival of new asymptomatics

        self.N     = np.sum(Ni)
        self.M     = M
        self.Ni    = np.zeros( self.M, dtype=DTYPE)             # # people in each age-group
        self.Ni    = Ni

        self.CM    = np.zeros( (self.M, self.M), dtype=DTYPE)   # contact matrix C
        self.FM    = np.zeros( self.M, dtype = DTYPE)           # seed function F
        self.drpdt = np.zeros( 4*self.M, dtype=DTYPE)           # right hand side

        self.sa    = np.zeros( self.M, dtype = DTYPE)
        if np.size(sa)==1:
            self.sa = sa*np.ones(M)
        elif np.size(sa)==M:
            self.sa= sa
        else:
            print('sa can be a number or an array of size M')

        self.iaa   = np.zeros( self.M, dtype = DTYPE)
        if np.size(iaa)==1:
            self.iaa = iaa*np.ones(M)
        elif np.size(iaa)==M:
            self.iaa = iaa
        else:
            print('iaa can be a number or an array of size M')


    cdef rhs(self, rp, tt):
        cdef:
            int N=self.N, M=self.M, i, j
            double alpha=self.alpha, beta=self.beta, gIa=self.gIa, aa, bb
            double fsa=self.fsa, alphab=1-self.alpha,gIs=self.gIs, ep=self.ep
            double [:] S    = rp[0  :M]
            double [:] Ia   = rp[M  :2*M]
            double [:] Is   = rp[2*M:3*M]
            double [:] Ni   = rp[3*M:4*M]
            double [:,:] CM = self.CM
            double [:] sa   = self.sa
            double [:] iaa  = self.iaa
            double [:] X    = self.drpdt

        for i in range(M):
            bb=0
            for j in range(M):
                 bb += beta*CM[i,j]*(Ia[j]+fsa*Is[j])/Ni[j]
            aa = bb*S[i]
            X[i]     = -aa + sa[i] + ep*(gIa*Ia[i] + gIs*Is[i])
            X[i+M]   = alpha *aa - gIa*Ia[i] + iaa[i]
            X[i+2*M] = alphab*aa - gIs*Is[i]
            X[i+3*M] = sa[i] + iaa[i]
        return


    def simulate(self, S0, Ia0, Is0, contactMatrix, Tf, Nf, Ti=0, integrator='odeint', seedRate=None):
        from scipy.integrate import odeint

        def rhs0(rp, t):
            self.CM = contactMatrix(t)
            self.rhs(rp, t)
            return self.drpdt

        if integrator=='odeint':
            time_points=np.linspace(Ti, Tf, Nf);  ## intervals at which output is returned by integrator.
            u = odeint(rhs0, np.concatenate((S0, Ia0, Is0, self.Ni)), time_points, mxstep=5000000)
        else:
            import odespy
            time_points=np.linspace(Ti, Tf, Nf);  ## intervals at which output is returned by integrator.
            solver = odespy.Vode(rhs0, method = 'bdf', atol=1E-7, rtol=1E-6, order=5, nsteps=10**6)
            #solver = odespy.RKF45(rhs0)
            #solver = odespy.RK4(rhs0)
            solver.set_initial_condition(np.concatenate((S0, Ia0, Is0, self.Ni)))
            u, time_points = solver.solve(time_points)

        data={'X':u, 't':time_points, 'N':self.N, 'M':self.M,'alpha':self.alpha, 'beta':self.beta,'gIa':self.gIa, 'gIs':self.gIs }
        return data




@cython.wraparound(False)
@cython.boundscheck(False)
@cython.cdivision(True)
@cython.nonecheck(False)
cdef class SEIR:
    """
    Susceptible, Exposed, Infected, Recovered (SEIR)
    Ia: asymptomatic
    Is: symptomatic
    """
    cdef:
        readonly int N, M,
        readonly double alpha, beta, gIa, gIs, gE, fsa
        readonly np.ndarray rp0, Ni, drpdt, CM, CC, FM

    def __init__(self, parameters, M, Ni):
        self.alpha = parameters.get('alpha')                    # fraction of asymptomatic infectives
        self.beta  = parameters.get('beta')                     # infection rate
        self.gIa   = parameters.get('gIa')                      # recovery rate of Ia
        self.gIs   = parameters.get('gIs')                      # recovery rate of Is
        self.gE    = parameters.get('gE')                       # recovery rate of E
        self.fsa   = parameters.get('fsa')                      # the self-isolation parameter

        self.N     = np.sum(Ni)
        self.M     = M
        self.Ni    = np.zeros( self.M, dtype=DTYPE)             # # people in each age-group
        self.Ni    = Ni

        self.CM    = np.zeros( (self.M, self.M), dtype=DTYPE)   # contact matrix C
        self.FM    = np.zeros( self.M, dtype = DTYPE)           # seed function F
        self.drpdt = np.zeros( 4*self.M, dtype=DTYPE)           # right hand side


    cdef rhs(self, rp, tt):
        cdef:
            int N=self.N, M=self.M, i, j
            double alpha=self.alpha, beta=self.beta, gIa=self.gIa, gIs=self.gIs, aa, bb
            double fsa=self.fsa, gE=self.gE, ce1=self.gE*self.alpha, ce2=self.gE*(1-self.alpha)
            double [:] S    = rp[0  :  M]
            double [:] E    = rp[  M:2*M]
            double [:] Ia   = rp[2*M:3*M]
            double [:] Is   = rp[3*M:4*M]
            double [:] Ni   = self.Ni
            double [:,:] CM = self.CM
            double [:]   FM = self.FM
            double [:] X    = self.drpdt

        for i in range(M):
            bb=0
            for j in range(M):
                 bb += beta*CM[i,j]*(Ia[j]+fsa*Is[j])/Ni[j]
            aa = bb*S[i]
            X[i]     = -aa - FM[i]
            X[i+M]   = aa       - gE*  E[i] + FM[i]
            X[i+2*M] = ce1*E[i] - gIa*Ia[i]
            X[i+3*M] = ce2*E[i] - gIs*Is[i]
        return


    def simulate(self, S0, E0, Ia0, Is0, contactMatrix, Tf, Nf, Ti=0, integrator='odeint', seedRate=None):
        from scipy.integrate import odeint

        def rhs0(rp, t):
            self.CM = contactMatrix(t)
            if None != seedRate :
                self.FM = seedRate(t)
            else :
                self.FM = np.zeros( self.M, dtype = DTYPE)
            self.rhs(rp, t)
            return self.drpdt

        if integrator=='odeint':
            time_points=np.linspace(Ti, Tf, Nf);  ## intervals at which output is returned by integrator.
            u = odeint(rhs0, np.concatenate((S0, E0, Ia0, Is0)), time_points, mxstep=5000000)
        else:
            import odespy
            time_points=np.linspace(Ti, Tf, Nf);  ## intervals at which output is returned by integrator.
            solver = odespy.Vode(rhs0, method = 'bdf', atol=1E-7, rtol=1E-6, order=5, nsteps=10**6)
            #solver = odespy.RKF45(rhs0)
            #solver = odespy.RK4(rhs0)
            solver.set_initial_condition(np.concatenate((S0, E0, Ia0, Is0)))
            u, time_points = solver.solve(time_points)

        data={'X':u, 't':time_points, 'N':self.N, 'M':self.M,'alpha':self.alpha, 'beta':self.beta,'gIa':self.gIa,'gIs':self.gIs,'gE':self.gE}
        return data




@cython.wraparound(False)
@cython.boundscheck(False)
@cython.cdivision(True)
@cython.nonecheck(False)
cdef class SEI5R:
    """
    Susceptible, Exposed, Infected, Recovered (SEIR)
    The infected class has 5 groups:
    * Ia: asymptomatic
    * Is: symptomatic
    * Ih: hospitalized
    * Ic: ICU
    * Im: Mortality

    S  ---> E
    E  ---> Ia, Is
    Ia ---> R
    Is ---> Ih, R
    Ih ---> Ic, R
    Ic ---> Im, R
    """
    cdef:
        readonly int N, M,
        readonly double alpha, beta, gE, gIa, gIs, gIh, gIc, fsa, fh
        readonly np.ndarray rp0, Ni, drpdt, CM, FM, CC, sa, iaa, hh, cc, mm

    def __init__(self, parameters, M, Ni):
        self.alpha = parameters.get('alpha')                    # fraction of asymptomatic infectives
        self.beta  = parameters.get('beta')                     # infection rate
        self.gE    = parameters.get('gE')                       # recovery rate of E class
        self.gIa   = parameters.get('gIa')                      # recovery rate of Ia
        self.gIs   = parameters.get('gIs')                      # recovery rate of Is
        self.gIh   = parameters.get('gIh')                      # recovery rate of Is
        self.gIc   = parameters.get('gIc')                      # recovery rate of Ih
        self.fsa   = parameters.get('fsa')                      # the self-isolation parameter of symptomatics
        self.fh    = parameters.get('fh')                       # the self-isolation parameter of hospitalizeds

        sa         = parameters.get('sa')                       # daily arrival of new susceptibles
        hh         = parameters.get('hh')                       # hospital
        cc         = parameters.get('cc')                       # ICU
        mm         = parameters.get('mm')                       # mortality

        self.N     = np.sum(Ni)
        self.M     = M
        self.Ni    = np.zeros( self.M, dtype=DTYPE)             # # people in each age-group
        self.Ni    = Ni

        self.CM    = np.zeros( (self.M, self.M), dtype=DTYPE)   # contact matrix C
        self.drpdt = np.zeros( 8*self.M, dtype=DTYPE)           # right hand side

        self.sa    = np.zeros( self.M, dtype = DTYPE)
        if np.size(sa)==1:
            self.sa = sa*np.ones(M)
        elif np.size(sa)==M:
            self.sa= sa
        else:
            print('sa can be a number or an array of size M')

        self.hh    = np.zeros( self.M, dtype = DTYPE)
        if np.size(hh)==1:
            self.hh = hh*np.ones(M)
        elif np.size(hh)==M:
            self.hh= hh
        else:
            print('hh can be a number or an array of size M')

        self.cc    = np.zeros( self.M, dtype = DTYPE)
        if np.size(cc)==1:
            self.cc = cc*np.ones(M)
        elif np.size(cc)==M:
            self.cc= cc
        else:
            print('cc can be a number or an array of size M')

        self.mm    = np.zeros( self.M, dtype = DTYPE)
        if np.size(mm)==1:
            self.mm = mm*np.ones(M)
        elif np.size(mm)==M:
            self.mm= mm
        else:
            print('mm can be a number or an array of size M')


    cdef rhs(self, rp, tt):
        cdef:
            int N=self.N, M=self.M, i, j
            double alpha=self.alpha, beta=self.beta, aa, bb
            double fsa=self.fsa, fh=self.fh, alphab=1-self.alpha, gE=self.gE
            double gIs=self.gIs, gIa=self.gIa, gIh=self.gIh, gIc=self.gIh
            double ce1=self.gE*self.alpha, ce2=self.gE*(1-self.alpha)
            double [:] S    = rp[0  :M]
            double [:] E    = rp[M  :2*M]
            double [:] Ia   = rp[2*M:3*M]
            double [:] Is   = rp[3*M:4*M]
            double [:] Ih   = rp[4*M:5*M]
            double [:] Ic   = rp[5*M:6*M]
            double [:] Im   = rp[6*M:7*M]
            double [:] Ni   = rp[7*M:8*M]
            double [:,:] CM = self.CM
            double [:] sa   = self.sa       #sa is rate of additional/removal of population by birth etc
            double [:] hh   = self.hh
            double [:] cc   = self.cc
            double [:] mm   = self.mm
            double [:] X    = self.drpdt

        for i in range(M):
            bb=0
            for j in range(M):
                 bb += beta*CM[i,j]*(Ia[j]+fsa*Is[j]+fh*Ih[j])/Ni[j]
            aa = bb*S[i]
            X[i]     = -aa + sa[i]                       
            X[i+M]   = aa  - gE*E[i]                     
            X[i+2*M] = ce1*E[i] - gIa*Ia[i]              
            X[i+3*M] = ce2*E[i] - gIs*Is[i]              
            X[i+4*M] = gIs*hh[i]*Is[i] - gIh*Ih[i]       
            X[i+5*M] = gIh*cc[i]*Ih[i] - gIc*Ic[i]       
            X[i+6*M] = gIc*mm[i]*Ic[i]                   
            X[i+7*M] = sa[i] - gIc*mm[i]*Im[i]           
        return


    def simulate(self, S0, E0, Ia0, Is0, Ih0, Ic0, Im0, contactMatrix, Tf, Nf, Ti=0, integrator='odeint', seedRate=None):
        from scipy.integrate import odeint

        def rhs0(rp, t):
            self.CM = contactMatrix(t)
            self.rhs(rp, t)
            return self.drpdt

        if integrator=='odeint':
            time_points=np.linspace(Ti, Tf, Nf);  ## intervals at which output is returned by integrator.
            u = odeint(rhs0, np.concatenate((S0, E0, Ia0, Is0, Ih0, Ic0, Im0, self.Ni)), time_points, mxstep=5000000)
        else:
            import odespy
            time_points=np.linspace(Ti, Tf, Nf);  ## intervals at which output is returned by integrator.
            solver = odespy.Vode(rhs0, method = 'bdf', atol=1E-7, rtol=1E-6, order=5, nsteps=10**6)
            #solver = odespy.RKF45(rhs0)
            #solver = odespy.RK4(rhs0)
            solver.set_initial_condition(np.concatenate((S0, E0, Ia0, Is0, Ih0, Ic0, Im0, self.Ni)))
            u, time_points = solver.solve(time_points)

        data={'X':u, 't':time_points, 'N':self.N, 'M':self.M,'alpha':self.alpha, 'beta':self.beta,'gIa':self.gIa,'gIs':self.gIs,'gE':self.gE}
        return data




@cython.wraparound(False)
@cython.boundscheck(False)
@cython.cdivision(True)
@cython.nonecheck(False)
cdef class SIkR:
    """
    Susceptible, Infected, Recovered (SIkR)
    method of k-stages of I
    """
    cdef:
        readonly int N, M, ki
        readonly double alpha, beta, gI, fsa
        readonly np.ndarray rp0, Ni, drpdt,  CM, CC, FM

    def __init__(self, parameters, M, Ni):
        self.alpha = parameters.get('alpha')                    # fraction of asymptomatic infectives
        self.beta  = parameters.get('beta')                     # infection rate
        self.gI    = parameters.get('gI')                       # recovery rate of Ia
        self.ki    = parameters.get('k')                        # recovery rate of Ia
        self.fsa   = parameters.get('fsa')                      # the self-isolation parameter

        self.N     = np.sum(Ni)
        self.M     = M
        self.Ni    = np.zeros( self.M, dtype=DTYPE)             # # people in each age-group
        self.Ni    = Ni

        self.CM    = np.zeros( (self.M, self.M), dtype=DTYPE)   # contact matrix C
        self.FM    = np.zeros( self.M, dtype = DTYPE)           # seed function F
        self.drpdt = np.zeros( (self.ki+1)*self.M, dtype=DTYPE) # right hand side


    cdef rhs(self, rp, tt):
        cdef:
            int N=self.N, M=self.M, i, j, jj, ki=self.ki
            double alpha=self.alpha, beta=self.beta, gI=self.ki*self.gI, aa, bb
            double [:] S    = rp[0  :M]
            double [:] I    = rp[M  :(ki+1)*M]
            double [:] Ni   = self.Ni
            double [:,:] CM = self.CM
            double [:]   FM = self.FM
            double [:] X    = self.drpdt

        for i in range(M):
            bb=0
            for jj in range(ki):
                for j in range(M):
                    bb += beta*(CM[i,j]*I[j+jj*M])/Ni[j]
            aa = bb*S[i]
            X[i]     = -aa - FM[i]
            X[i+M]   = aa - gI*I[i] + FM[i]

            for j in range(ki-1):
                X[i+(j+2)*M]   = gI*I[i+j*M] - gI*I[i+(j+1)*M]
        return


    def simulate(self, S0, I0, contactMatrix, Tf, Nf, Ti=0, integrator='odeint', seedRate=None):
        from scipy.integrate import odeint

        def rhs0(rp, t):
            self.CM = contactMatrix(t)
            if None != seedRate :
                self.FM = seedRate(t)
            else :
                self.FM = np.zeros( self.M, dtype = DTYPE)
            self.rhs(rp, t)
            return self.drpdt

        if integrator=='odeint':
            time_points=np.linspace(Ti, Tf, Nf);  ## intervals at which output is returned by integrator.
            u = odeint(rhs0, np.concatenate((S0, I0)), time_points, mxstep=5000000)
        else:
            import odespy
            time_points=np.linspace(Ti, Tf, Nf);  ## intervals at which output is returned by integrator.
            solver = odespy.Vode(rhs0, method = 'bdf', atol=1E-7, rtol=1E-6, order=5, nsteps=10**6)
            #solver = odespy.RKF45(rhs0)
            #solver = odespy.RK4(rhs0)
            solver.set_initial_condition(np.concatenate((S0, I0)))
            u, time_points = solver.solve(time_points)

        data={'X':u, 't':time_points, 'N':self.N, 'M':self.M,'alpha':self.alpha, 'beta':self.beta,'gI':self.gI, 'k':self.ki }
        return data




@cython.wraparound(False)
@cython.boundscheck(False)
@cython.cdivision(True)
@cython.nonecheck(False)
cdef class SEkIkR:
    """
    Susceptible, Infected, Recovered (SIkR)
    method of k-stages of I
    See: Lloyd, Theoretical Population Biology 60, 59􏰈71 (2001), doi:10.1006􏰅tpbi.2001.1525.
    """
    cdef:
        readonly int N, M, ki, ke
        readonly double alpha, beta, gI, fsa, gE
        readonly np.ndarray rp0, Ni, drpdt, CM, CC, FM

    def __init__(self, parameters, M, Ni):
        self.alpha = parameters.get('alpha')                    # fraction of asymptomatic infectives
        self.beta  = parameters.get('beta')                     # infection rate
        self.gE    = parameters.get('gE')
        self.gI    = parameters.get('gI')                      # recovery rate of Ia
        self.ki    = parameters.get('kI')                      # recovery rate of Ia
        self.ke    = parameters.get('kE')
        self.fsa   = parameters.get('fsa')                      # the self-isolation parameter

        self.N     = np.sum(Ni)
        self.M     = M
        self.Ni    = np.zeros( self.M, dtype=DTYPE)             # # people in each age-group
        self.Ni    = Ni

        self.CM    = np.zeros( (self.M, self.M), dtype=DTYPE)   # contact matrix C
        self.FM    = np.zeros( self.M, dtype = DTYPE)           # seed function F
        self.drpdt = np.zeros( (self.ki + self.ke + 1)*self.M, dtype=DTYPE)           # right hand side


    cdef rhs(self, rp, tt):
        cdef:
            int N=self.N, M=self.M, i, j, jj, ki=self.ki, ke = self.ke
            double alpha=self.alpha, beta=self.beta, gI=self.ki*self.gI, aa, bb
            double fsa=self.fsa, alphab=1-self.alpha, gE = self.ke * self.gE
            double [:] S    = rp[0  :M]
            double [:] E    = rp[M  :(ke+1)*M]
            double [:] I    = rp[(ke+1)*M  :(ke+ki+1)*M]
            double [:] Ni   = self.Ni
            double [:,:] CM = self.CM
            double [:]   FM = self.FM
            double [:] X    = self.drpdt

        for i in range(M):
            bb=0
            for jj in range(ki):
                for j in range(M):
                    bb += beta*(CM[i,j]*I[j+jj*M])/Ni[j]
            aa = bb*S[i]
            X[i]     = -aa - FM[i]

            # If there is any E stage...
            if 0 != ke :
                # People removed from S are put in E[0]
                X[i+M+0] = aa - gE*E[i] + FM[i]

                # Propagate cases along the E stages
                for j in range(ke - 1) :
                    X[i + M +  (j+1)*M ] = gE * E[i+j*M] - gE * E[i+(j+1)*M]

                # Transfer cases from E[-1] to I[0]
                X[i + (ke+1)* M + 0] = gE * E[i+(ke-1)*M] - gI * I[i]

            # However, if there aren't any E stages
            else :
                # People removed from S are put in I[0]
                X[i + (ke+1)* M + 0] = aa + FM[i] - gI * I[i]

            # In both cases, propagate cases along the I stages.
            for j in range(ki-1):
                X[i+(ke+1)*M + (j+1)*M ]   = gI*I[i+j*M] - gI*I[i+(j+1)*M]
        return


    def simulate(self, S0, E0, I0, contactMatrix, Tf, Nf, Ti=0, integrator='odeint', seedRate=None):
        from scipy.integrate import odeint

        def rhs0(rp, t):
            self.CM = contactMatrix(t)
            if None != seedRate :
                self.FM = seedRate(t)
            else :
                self.FM = np.zeros( self.M, dtype = DTYPE)
            self.rhs(rp, t)
            return self.drpdt

        if integrator=='odeint':
            time_points=np.linspace(Ti, Tf, Nf);  ## intervals at which output is returned by integrator.
            u = odeint(rhs0, np.concatenate((S0, E0, I0)), time_points, mxstep=5000000)
        else:
            import odespy
            time_points=np.linspace(Ti, Tf, Nf);  ## intervals at which output is returned by integrator.
            solver = odespy.Vode(rhs0, method = 'bdf', atol=1E-7, rtol=1E-6, order=5, nsteps=10**6)
            #solver = odespy.RKF45(rhs0)
            #solver = odespy.RK4(rhs0)
            solver.set_initial_condition(np.concatenate((S0, E0, I0)))
            u, time_points = solver.solve(time_points)

        data={'X':u, 't':time_points, 'N':self.N, 'M':self.M,'alpha':self.alpha, 'beta':self.beta,'gI':self.gI, 'k':self.ki }
        return data




@cython.wraparound(False)
@cython.boundscheck(False)
@cython.cdivision(True)
@cython.nonecheck(False)
cdef class SEAIR:
    """
    Susceptible, Exposed, Asymptomatic and infected, Infected, Recovered (SEAIR)
    Ia: asymptomatic
    Is: symptomatic
    A : Asymptomatic and infectious
    """
    cdef:
        readonly int N, M,
        readonly double alpha, beta, gIa, gIs, gE, gAA, gAS, fsa
        readonly np.ndarray rp0, Ni, drpdt,  CM, CC, FM

    def __init__(self, parameters, M, Ni):
        self.alpha = parameters.get('alpha')                    # fraction of asymptomatic infectives
        self.beta  = parameters.get('beta')                     # infection rate
        self.gIa   = parameters.get('gIa')                      # recovery rate of Ia
        self.gIs   = parameters.get('gIs')                      # recovery rate of Is
        self.gE    = parameters.get('gE')                       # recovery rate of E
        self.gAA   = parameters.get('gAA')                       # rate to go from A to Ia
        self.gAS   = parameters.get('gAS')                       # rate to go from A to Is
        self.fsa   = parameters.get('fsa')                      # the self-isolation parameter

        self.N     = np.sum(Ni)
        self.M     = M
        self.Ni    = np.zeros( self.M, dtype=DTYPE)             # # people in each age-group
        self.Ni    = Ni

        self.CM    = np.zeros( (self.M, self.M), dtype=DTYPE)   # contact matrix C
        self.FM    = np.zeros( self.M, dtype = DTYPE)           # seed function F
        self.drpdt = np.zeros( 5*self.M, dtype=DTYPE)           # right hand side


    cdef rhs(self, rp, tt):
        cdef:
            int N=self.N, M=self.M, i, j
            double beta=self.beta, aa, bb
            double fsa=self.fsa, gE=self.gE, gIa=self.gIa, gIs=self.gIs
            double gAA=self.gAA*self.alpha, gAS=self.gAS*(1-self.alpha)

            double [:] S    = rp[0*M:M]
            double [:] E    = rp[1*M:2*M]
            double [:] A    = rp[2*M:3*M]
            double [:] Ia   = rp[3*M:4*M]
            double [:] Is   = rp[4*M:5*M]
            double [:] Ni   = self.Ni
            double [:,:] CM = self.CM
            double [:]   FM = self.FM
            double [:] X    = self.drpdt

        for i in range(M):
            bb=0
            for j in range(M):
                 bb += beta*CM[i,j]*(Ia[j]+fsa*Is[j])/Ni[j]
            aa = bb*S[i]
            X[i]     = -aa - FM[i]
            X[i+M]   =  aa      - gE       *E[i] + FM[i]
            X[i+2*M] = gE* E[i] - (gAA+gAS)*A[i]
            X[i+3*M] = gAA*A[i] - gIa     *Ia[i]
            X[i+4*M] = gAS*A[i] - gIs     *Is[i]
        return


    def simulate(self, S0, E0, A0, Ia0, Is0, contactMatrix, Tf, Nf, Ti=0, integrator='odeint', seedRate=None):
        from scipy.integrate import odeint

        def rhs0(rp, t):
            self.CM = contactMatrix(t)
            if None != seedRate :
                self.FM = seedRate(t)
            else :
                self.FM = np.zeros( self.M, dtype = DTYPE)
            self.rhs(rp, t)
            return self.drpdt

        if integrator=='odeint':
            time_points=np.linspace(Ti, Tf, Nf);  ## intervals at which output is returned by integrator.
            u = odeint(rhs0, np.concatenate((S0, E0, A0, Ia0, Is0)), time_points, mxstep=5000000)
        else:
            import odespy
            time_points=np.linspace(Ti, Tf, Nf);  ## intervals at which output is returned by integrator.
            solver = odespy.Vode(rhs0, method = 'bdf', atol=1E-7, rtol=1E-6, order=5, nsteps=10**6)
            #solver = odespy.RKF45(rhs0)
            #solver = odespy.RK4(rhs0)
            solver.set_initial_condition(np.concatenate((S0, E0, A0, Ia0, Is0)))
            u, time_points = solver.solve(time_points)

        data={'X':u, 't':time_points, 'N':self.N, 'M':self.M,'alpha':self.alpha,'beta':self.beta,'gIa':self.gIa,'gIs':self.gIs,'gE':self.gE,'gAA':self.gAA,'gAS':self.gAS}
        return data




@cython.wraparound(False)
@cython.boundscheck(False)
@cython.cdivision(True)
@cython.nonecheck(False)
cdef class SEAIRQ:
    """
    Susceptible, Exposed, Asymptomatic and infected, Infected, Recovered, Quarantined (SEAIRQ)
    Ia: asymptomatic
    Is: symptomatic
    A : Asymptomatic and infectious
    """
    cdef:
        readonly int N, M,
        readonly double alpha, beta, gIa, gIs, gE, gAA, gAS, fsa
        readonly double tS, tE, tA, tIa, tIs
        readonly np.ndarray rp0, Ni, drpdt, CM, CC, FM

    def __init__(self, parameters, M, Ni):
        self.alpha = parameters.get('alpha')                    # fraction of asymptomatic infectives
        self.beta  = parameters.get('beta')                     # infection rate
        self.gIa   = parameters.get('gIa')                      # recovery rate of Ia
        self.gIs   = parameters.get('gIs')                      # recovery rate of Is
        self.gE    = parameters.get('gE')                       # recovery rate of E
        self.gAA   = parameters.get('gAA')                       # rate to go from A to Ia
        self.gAS   = parameters.get('gAS')                       # rate to go from A to Is
        self.fsa   = parameters.get('fsa')                      # the self-isolation parameter


        self.tS    = parameters.get('tS ')                       # testing rate in S
        self.tE    = parameters.get('tE ')                       # testing rate in E
        self.tA    = parameters.get('tA ')                       # testing rate in A
        self.tIa   = parameters.get('tIa')                       # testing rate in Ia
        self.tIs   = parameters.get('tIs')                       # testing rate in Is

        self.N     = np.sum(Ni)
        self.M     = M
        self.Ni    = np.zeros( self.M, dtype=DTYPE)             # # people in each age-group
        self.Ni    = Ni

        self.CM    = np.zeros( (self.M, self.M), dtype=DTYPE)   # contact matrix C
        self.FM    = np.zeros( self.M, dtype = DTYPE)           # seed function F
        self.drpdt = np.zeros( 5*self.M, dtype=DTYPE)           # right hand side


    cdef rhs(self, rp, tt):
        cdef:
            int N=self.N, M=self.M, i, j
            double beta=self.beta, aa, bb
            double tS=self.tS, tE=self.tE, tA=self.tA, tIa=self.tIa, tIs=self.tIs
            double fsa=self.fsa, gE=self.gE, gIa=self.gIa, gIs=self.gIs
            double gAA=self.gAA*self.alpha, gAS=self.gAS*(1-self.alpha)

            double [:] S    = rp[0*M:M]
            double [:] E    = rp[1*M:2*M]
            double [:] A    = rp[2*M:3*M]
            double [:] Ia   = rp[3*M:4*M]
            double [:] Is   = rp[4*M:5*M]
            double [:] Ni   = self.Ni
            double [:,:] CM = self.CM
            double [:]   FM = self.FM
            double [:] X    = self.drpdt

        for i in range(M):
            bb=0
            for j in range(M):
                 bb += beta*CM[i,j]*(Ia[j]+fsa*Is[j])/Ni[j]
            aa = bb*S[i]
            X[i]     = -aa      - tS          *S[i] - FM[i]
            X[i+M]   =  aa      - (gE+tE)     *E[i] + FM[i]
            X[i+2*M] = gE* E[i] - (gAA+gAS+tA)*A[i]
            X[i+3*M] = gAA*A[i] - (gIa+tIa   )*Ia[i]
            X[i+4*M] = gAS*A[i] - (gIs+tIs   )*Is[i]
        return


    def simulate(self, S0, E0, A0, Ia0, Is0, contactMatrix, Tf, Nf, Ti=0, integrator='odeint', seedRate=None):
        from scipy.integrate import odeint

        def rhs0(rp, t):
            self.CM = contactMatrix(t)
            if None != seedRate :
                self.FM = seedRate(t)
            else :
                self.FM = np.zeros( self.M, dtype = DTYPE)
            self.rhs(rp, t)
            return self.drpdt

        if integrator=='odeint':
            time_points=np.linspace(Ti, Tf, Nf);  ## intervals at which output is returned by integrator.
            u = odeint(rhs0, np.concatenate((S0, E0, A0, Ia0, Is0)), time_points, mxstep=5000000)
        else:
            import odespy
            time_points=np.linspace(Ti, Tf, Nf);  ## intervals at which output is returned by integrator.
            solver = odespy.Vode(rhs0, method = 'bdf', atol=1E-7, rtol=1E-6, order=5, nsteps=10**6)
            #solver = odespy.RKF45(rhs0)
            #solver = odespy.RK4(rhs0)
            solver.set_initial_condition(np.concatenate((S0, E0, A0, Ia0, Is0)))
            u, time_points = solver.solve(time_points)

        data={'X':u, 't':time_points, 'N':self.N, 'M':self.M,'alpha':self.alpha,'beta':self.beta,'gIa':self.gIa,'gIs':self.gIs,'gE':self.gE,'gAA':self.gAA,'gAS':self.gAS,'tS':self.tS,'tE':self.tE,'tIa':self.tIa,'tIs':self.tIs}
        return data
