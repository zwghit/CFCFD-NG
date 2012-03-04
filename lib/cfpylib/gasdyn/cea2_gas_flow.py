"""
cea2_gas_flow.py -- Gas flow calculations using CEA2 Gas objects.

.. Author:
   PA Jacobs

.. Version:
   26-Feb-2012 : functions moved out of estcj.py to this module.
"""

import sys, math, numpy
from cea2_gas import Gas
from ..nm.zero_solvers import secant

DEBUG_GAS_FLOW = False

#----------------------------------------------------------------------------
# 1-D flow functions abstracted from estcj.py
# and made a little more generic.

def shock_ideal(s1, Vs, s2):
    """
    Computes post-shock conditions in the shock frame, assuming ideal gas.

    :param s1: pre-shock Gas state
    :param Vs: speed of gas coming into shock
    :param s2: post-shock Gas state
    :returns: the post-shock gas speed, V2 in the shock-reference frame, Vg in the lab frame.
    """
    #
    M1 = Vs / s1.a
    V1 = Vs
    gam = s1.gam
    R = s1.R
    C_v = s1.C_v
    #
    s2.rho = s1.rho * (gam + 1.0) * M1 * M1 \
             / (2.0 + (gam - 1.0) * M1 * M1)
    s2.p = s1.p * (2.0 * gam * M1 * M1 - (gam - 1.0)) / (gam + 1.0)
    s2.T = s2.p / (R * s2.rho)
    s2.e = s2.T * C_v
    #
    V2 = s1.rho / s2.rho * V1
    Vg = V1 - V2
    s2.a = s1.a * math.sqrt(s2.T / s1.T)
    #
    s2.R = s1.R
    s2.gam = s1.gam
    s2.C_v = s1.C_v
    #
    return (V2, Vg)


def my_limiter(delta, orig, frac=0.5):
    """
    Limit the magnitude of delta to no more than a fraction of the original.

    It occasionally happens that the Newton iterations go badly.
    It is worth trying to take smaller steps in these situations,
    assuming that the computed direction is still a fair guess.
    """
    if delta >= 0.0:
        sign = 1
    else:
        sign = -1
    abs_delta = min(abs(delta), frac*abs(orig))
    return sign * abs_delta


def shock_real(s1, Vs, s2):
    """
    Computes post-shock conditions, using high-temperature gas properties
    and a shock-stationary frame.

    :param s1: pre-shock gas state
    :param Vs: speed of gas coming into shock
    :param s2: post-shock gas state
    :returns: the post-shock gas speed, V2 in the shock-reference frame, Vg in the lab frame.
    """
    #
    (V2,Vg) = shock_ideal(s1, Vs, s2)
    if DEBUG_GAS_FLOW:
        print 'shock_real(): post-shock condition assuming ideal gas'
        s2.write_state(sys.stdout)
        print '    V2: %g m/s, Vg: %g m/s' % (V2,Vg)
    #
    # We assume that p1 and T1 are correct
    # and that s2 contains a fair initial guess.
    V1 = Vs
    s1.EOS(problemType='pT');
    if DEBUG_GAS_FLOW:
        print 'shock_real(): pre-shock condition assuming real gas and original pT'
        s1.write_state(sys.stdout)
    s2.EOS(problemType='pT');
    if DEBUG_GAS_FLOW:
        print 'shock_real(): post-shock condition assuming real gas and ideal pT'
        s2.write_state(sys.stdout)
    #
    p1    = s1.p
    e1    = s1.e
    rho1  = s1.rho
    temp1 = p1 + rho1 * V1 * V1;             # momentum
    H1    = e1 + p1 / rho1 + 0.5 * V1 * V1;  # total enthalpy
    #
    rho_delta = 1.0
    T_delta = 1.0
    rho_tol = 1.0e-3; # tolerance in kg/m^3
    T_tol = 0.25;  # tolerance in degrees K
    #
    s0 = s1.clone(); # temporary workspace
    #
    # Update the estimates using the Newton-Raphson method.
    #
    for count in range(20):
        rho_save = s2.rho
        T_save = s2.T
        p_save = s2.p
        #
        p2 = p_save
        T2 = T_save
        s2.EOS(problemType='pT')
        e2 = s2.e
        rho2 = rho_save
        r2r1 = rho2 / rho1
        f1 = temp1 - p2 - rho1 * rho1 * V1 * V1 / rho2
        f2 = H1 - e2 - p2 / rho2 - 0.5 * V1 * V1 / (r2r1 * r2r1)
        f1_save = f1
        f2_save = f2
        #
        # Use finite differences to compute the Jacobian.
        d_rho = rho_save * 0.01
        d_T = T_save * 0.01
        #
        rho2 = rho_save + d_rho
        T2 = T_save
        s0.rho = rho2
        s0.T = T2
        s0.EOS(problemType='rhoT')
        p2 = s0.p
        e2 = s0.e
        f1 = temp1 - p2 - rho1 * rho1 * V1 * V1 / rho2
        f2 = H1 - e2 - p2 / rho2 - 0.5 * V1 * V1 / (r2r1 * r2r1)
        A = (f1 - f1_save) / d_rho
        C = (f2 - f2_save) / d_rho
        #
        rho2 = rho_save
        T2 = T_save + d_T
        s0.rho = rho2
        s0.T = T2
        s0.EOS(problemType='rhoT')
        e2 = s0.e
        p2 = s0.p
        f1 = temp1 - p2 - rho1 * rho1 * V1 * V1 / rho2
        f2 = H1 - e2 - p2 / rho2 - 0.5 * V1 * V1 / (r2r1 * r2r1)
        B = (f1 - f1_save) / d_T
        D = (f2 - f2_save) / d_T
        #
        # Invert Jacobian and multiply.
        det = A * D - B * C
        rho_delta = (D * f1_save - B * f2_save) / det
        T_delta = (-C * f1_save + A * f2_save) / det
        #
        rho_delta = my_limiter(rho_delta, rho_save)
        T_delta = my_limiter(T_delta, T_save)
        rho_new = rho_save - rho_delta
        T_new   = T_save - T_delta
        if DEBUG_GAS_FLOW:
            print('shock_real(): rho_save=%e, T_save=%e' % (rho_save, T_save))
            print('shock_real(): rho_delta=%e, T_delta=%e' % (rho_delta, T_delta))
            print('shock_real(): rho_new=%e, T_new=%e' % (rho_new, T_new))
        #
        s2.rho = rho_new
        s2.T   = T_new
        s2.EOS(problemType='rhoT')
        #
        # Check convergence.
        if abs(rho_delta) < rho_tol and abs(T_delta) < T_tol: break
    #
    if DEBUG_GAS_FLOW:
        print ('shock_real(): count = %d, drho=%e, dT=%e' %
               (count, rho_delta, T_delta) )
    #
    # Back-out velocities via continuity.
    V2 = V1 * s1.rho / s2.rho
    Vg = V1 - V2
    return (V2, Vg)


def reflected_shock(s2, Vg, s5):
    """
    Computes state5 which has brought the gas to rest at the end of the shock tube.

    :param s2: the post-incident-shock gas state
    :param Vg: the lab-frame velocity of the gas in state 2
    :param s5: the stagnation state that will be filled in
        (as a side effect of this function)
    :returns: Vr, the reflected shock speed in the lab frame.
    """
    #
    # As an initial guess, 
    # assume that we have a very strong shock in an ideal gas.
    density_ratio = (s2.gam + 1.0)/(s2.gam - 1.0)
    Vr_a = Vg / density_ratio;
    V5, Vjunk = shock_real(s2, Vr_a+Vg, s5)
    # The objective function is the difference in speeds,
    # units are m/s.  A value of zero for this function means
    # that, as the shock propagates upstream with speed ur,
    # the processed test gas is left in the end of the tube
    # with a velocity of zero in the laboratory frame.
    f_a = V5 - Vr_a
    if DEBUG_GAS_FLOW:
        print 'Reflected shock: Vr_a: %g, V5: %g' % (Vr_a, V5)
    #
    # Now, we need to update this guess...use a secant update.
    #
    Vr_b = 1.1 * Vr_a
    V5, Vjunk = shock_real(s2, Vr_b+Vg, s5)
    f_b = V5 - Vr_b
    if DEBUG_GAS_FLOW:
        print 'Reflected shock: Vr_b: %g, V5: %g' % (Vr_b, V5)
    if abs(f_a) < abs(f_b):
        f_a, f_b = f_b, f_a
        Vr_a, Vr_b = Vr_b, Vr_a
    count = 0
    while abs(f_b) > 0.5 and count < 20:
        slope = (f_b - f_a) / (Vr_b - Vr_a)
        Vr_c = Vr_b - f_b / slope
        V5, Vjunk = shock_real(s2, Vr_c+Vg, s5)
        f_c = V5 - Vr_c
        if abs(f_c) < abs(f_b):
            Vr_b = Vr_c; f_b = f_c
        else:
            Vr_a = Vr_c; f_a = f_c
        count = count + 1
    #
    # At this point, ur_b should be out best guess.
    # Update the gas state data and return the best-guess value.
    #
    if count >= 20:
        print 'Reflected shock iteration did not converge.'
    V5, Vjunk = shock_real(s2, Vr_b+Vg, s5)
    return Vr_b


def expand_from_stagnation(p_over_p0, state0):
    """
    Given a stagnation condition state0, expand to a new pressure.

    :param p_over_p0: pressure ratio
    :param state0: Gas object specifying stagnation conditions
    :returns: new gas state and the corresponding velocity (in m/s)
        of the expanded stream.
    """
    new_state = state0.clone()
    new_state.p = state0.p * p_over_p0;
    new_state.EOS(problemType='ps')
    # Matt McGilvray had a note about CEA giving bad entropy values
    # so we'll assert things are OK before proceeding.
    assert abs(new_state.s - state0.s)/abs(state0.s) < 0.001
    h = new_state.e + new_state.p/new_state.rho  # static enthalpy
    H = state0.e + state0.p/state0.rho  # stagnation enthalpy
    V = math.sqrt(2.0*(H-h))
    return new_state, V


def total_condition(state1, V1):
    """
    Given a free-stream condition and velocity,
    compute the corresponding stagnant condition
    at which the gas is brought to rest isentropically.

    :param state1: Gas object specifying free-stream condition
    :param V1: free-stream velocity, m/s
    :returns: Gas object specifying gas total conditions (isentropic, stagnant)
    """
    H1 = state1.p/state1.rho + state1.e + 0.5*V1*V1
    def error_in_total_enthalpy(x, state1=state1, H1=H1):
        """
        The enthalpy at the stagnation condition should match
        the total enthalpy of the stream.
        """
        new_state = state1.clone()
        new_state.p *= x
        new_state.EOS(problemType='ps')
        h = new_state.p/new_state.rho + new_state.e
        return (H1 - h)/abs(H1)
    x_total = secant(error_in_total_enthalpy, 1.0, 1.01, tol=1.0e-4)
    if x_total == 'FAIL':
        print "Failed to find total conditions iteratively."
        x_total = 1.0
    new_state = state1.clone()
    new_state.p *= x_total
    new_state.EOS(problemType='ps')
    return new_state


def pitot_condition(state1, V1):
    """
    Given a free-stream condition, compute the corresponding Pitot condition
    at which the gas is brought to rest, possibly through a shock.

    :param state1: Gas object specifying free-stream condition
    :param V1: free-stream velocity, m/s
    :returns: Gas object specifying gas impact conditions, 
        possibly after processing be a normal shock. 
    """
    if V1 > state1.a:
        # Supersonic free-stream; process through a shock first.
        state2 = state1.clone()
        (V2,Vg) = shock_real(state1, V1, state2)
        return total_condition(state2, V2)
    else:
        # Subsonic free-stream
        return total_condition(state1, V1)
    
#------------------------------------------------------------------------
# Oblique shock relations

def theta_oblique(state1, V1, beta):
    """
    Compute the deflection angle and post-shock conditions given the shock wave angle.

    :param state1: upstream gas condition
    :param V1: speed of gas into shock
    :param beta: shock wave angle wrt stream direction (in radians)
    :returns: tuple of theta, V2 and state2:
        theta is stream deflection angle in radians
        V2 is post-shock speed of gas in m/s
        state2 is post-shock gas state
    """
    V1_n = V1 * math.sin(beta)
    V_t = V1 * math.cos(beta)
    M1_n = V1 / state1.a
    if M1_n < 1.0:
        raise Exception, 'theta_oblique(): subsonic inflow M1_n=%e' % M1_n
    state2 = state1.clone()
    V2_n, Vg_n = shock_real(state1, V1_n, state2)
    V2 = math.sqrt(V2_n * V2_n + V_t * V_t)
    theta = beta - math.atan2(V2_n, V_t)
    return theta, V2, state2


def beta_oblique(state1, V1, theta):
    """
    Compute the oblique shock wave angle given the deflection angle.

    :param state1: upstream gas condition
    :param V1: speed of gas into shock
    :param theta: stream deflection angle (in radians)
    :returns: shock wave angle wrt incoming stream direction (in radians)
    """
    M1 = V1 / state1.a
    b1 = math.asin(1.0 / M1)
    b2 = b1 * 1.05
    def error_in_theta(beta_guess):
        theta_guess, V2, state2 = theta_oblique(state1, V1, beta_guess)
        return theta_guess - theta
    return secant(error_in_theta, b1, b2, tol=1.0e-6)

#------------------------------------------------------------------------
# Taylor-Maccoll cone flow.

def EOS_derivatives(state):
    """
    Compute equation-of-state derivatives at the specified state.

    :param state: a complete state (with valid data)
    :returns: tuple of approximations (drho/dp, drho/dh)
    """
    rho_0 = state.rho
    # Choose relatively-small increments in enthalpy (J/kg) and pressure (Pa).
    dh = abs(state.h) * 0.01 + 1000.0
    dp = state.p * 0.01 + 1000.0
    # Use finite-differences to get the partial derivative.
    state_new = state.clone()
    state_new.set_ph(state.p + dp, state.h)
    drhodp = (state_new.rho - rho_0) / dp
    # and again, for the other.
    state_new.set_ph(state.p, state.h + dh)
    drhodh = (state_new.rho - rho_0) / dh
    # Assume that these first-order differences will suffice.
    return drhodp, drhodh

def taylor_maccoll_odes(z, theta, gas_state):
    """
    The ODEs from the Taylor-Maccoll formulation.

    See PJ's workbook for Feb 2012 for details.
    We've packaged them formally so that we might one day use
    a more sophisticated ODE integrator requiring fewer steps.
    """
    rho, V_r, V_theta, h, p = z
    dfdp, dfdh = EOS_derivatives(gas_state)
    print "DEBUG dfdp=", dfdp, "dfdh=", dfdh
    # Assemble linear system for determining the derivatives wrt theta.
    A = numpy.zeros((5,5), float)
    b = numpy.zeros((5,), float)
    A[0,0] = V_theta; A[0,2] = rho; b[0] = -2.0*rho*V_r - rho*V_theta/math.tan(theta)
    A[1,1] = 1.0; b[1] = V_theta
    A[2,1] = rho*V_r; A[2,2] = rho*V_theta; A[2,4] = 1.0
    A[3,1] = V_r; A[3,2] = V_theta; A[3,3] = 1.0
    A[4,0] = 1.0; A[4,3] = -dfdh; A[4,4] = -dfdp
    dzdtheta = numpy.linalg.solve(A,b)
    return dzdtheta

def theta_cone(state1, V1, beta):
    """
    Compute the cone-surface angle and conditions given the shock wave angle.

    :param state1: upstream gas condition
    :param V1: speed of gas into shock
    :param beta: shock wave angle wrt stream direction (in radians)
    :returns: tuple of theta_c, V_c and state_c:
        theta_c is stream deflection angle in radians
        V_c is cone-surface speed of gas in m/s
        state_c is cone-surface gas state

    The computation starts with the oblique-shock jump and then integrates
    across theta until V_theta goes through zero.
    The cone surface corresponds to V_theta == 0.
    """
    # Start at the point just downstream the oblique shock.
    theta_s, V2, state2 = theta_oblique(state1, V1, beta)
    print "DEBUG beta=%g V1=%g state1:" % (beta, V1)
    state1.write_state(sys.stdout)
    print "DEBUG theta_s=%g V2=%g state2:" % (theta_s, V2)
    state2.write_state(sys.stdout)
    #
    # Initial conditions.
    dtheta = -0.5 * math.pi / 180.0  # fraction-of-a-degree steps
    theta = beta
    V_r = V2 * math.cos(beta - theta_s)
    V_theta = -V2 * math.sin(beta - theta_s)
    rho = state2.rho; h = state2.h; p = state2.p
    gas_state = state2.clone()
    # For integrating across the shock layer, the state vector is:
    z = numpy.array([rho, V_r, V_theta, h, p])
    while V_theta < 0.0:
        # Keep a copy for linear interpolation at the end.
        z_old = z.copy(); theta_old = theta
        # Do the update using a low-order method (Euler) for the moment.
        dzdtheta = taylor_maccoll_odes(z, theta, gas_state)
        z += dtheta * dzdtheta; theta += dtheta
        rho, V_r, V_theta, h, p = z
        gas_state.set_ph(p, h)
        print "DEBUG theta=", theta, "V_r=", V_r, "V_theta=", V_theta
    # At this point, V_theta should have crossed zero so
    # we can linearly-interpolate the cone-surface conditions.
    V_theta_old = z_old[2]
    frac = (0.0 - V_theta_old)/(V_theta - V_theta_old)
    z_c = z_old*(1.0-frac) + z*frac
    theta_c = theta_old*(1.0-frac) + theta*frac
    # At the cone surface...
    rho, V_r, V_theta, h, p = z_c
    gas_state.set_ph(p, h)
    assert abs(V_theta) < 1.0e-6
    #
    return theta_c, V_r, gas_state


def beta_cone(state1, V1, theta):
    """
    Compute the conical shock wave angle given the cone-surface deflection angle.

    :param state1: upstream gas condition
    :param V1: speed of gas into shock
    :param theta: stream deflection angle (in radians)
    :returns: shock wave angle wrt incoming stream direction (in radians)
    """
    M1 = V1 / state1.a
    b1 = math.asin(1.0 / M1) * 1.01 # to be stronger than a Mach wave
    b2 = b1 * 1.05
    def error_in_theta(beta_guess):
        print "DEBUG beta_guess(deg)=", beta_guess*180/math.pi
        theta_guess, V_c, state_c = theta_cone(state1, V1, beta_guess)
        print "DEBUG theta_guess(deg)=", theta_guess*180/math.pi
        return theta_guess - theta
    return secant(error_in_theta, b1, b2, tol=1.0e-6)

#------------------------------------------------------------------------

def demo():
    print "cea2_gas_flow Demonstration -- reflected shock tunnel."
    s1 = Gas({'Air':1.0})
    s1.set_pT(1.0e5, 300.0)
    s1.set_pT(1.0e5, 300.0)
    print "s1:"
    s1.write_state(sys.stdout)
    print "Incident shock"
    s2 = s1.clone()
    V2,Vg = shock_real(s1, 3000.0, s2)
    print "V2=", V2, "Vg=", Vg
    print "s2:"
    s2.write_state(sys.stdout)
    print "Reflected shock"
    s5 = s1.clone()
    Vr_b = reflected_shock(s2, Vg, s5)
    print "Vr_b=", Vr_b
    print "s5:"
    s5.write_state(sys.stdout)
    print "Expand from stagnation"
    s6, V = expand_from_stagnation(0.0025, s5)
    print "V=", V, "Mach=", V/s6.a, "s6:"
    s6.write_state(sys.stdout)
    print "Total condition"
    s7 = total_condition(s6, V)
    print "s7:"
    s7.write_state(sys.stdout)
    print "Pitot condition from state 6"
    s8 = pitot_condition(s6, V)
    print "pitot-p/total-p=", s8.p/s5.p, "s8:"
    s8.write_state(sys.stdout)
    #
    M1 = 1.5
    print "\nOblique-shock demo for M1=%g." % M1
    from ideal_gas_flow import theta_obl
    s1.set_pT(100.0e3, 300.0)
    beta = 45.0 * math.pi/180
    V1 = 1.5 * s1.a
    print "s1:"
    s1.write_state(sys.stdout)
    theta, V2, s2 = theta_oblique(s1, V1, beta)
    print "theta=", theta, "V2=", V2, "s2:"
    s2.write_state(sys.stdout)
    print "c.f. ideal gas angle=", theta_obl(M1, beta)
    #
    print "Oblique shock angle from deflection."
    beta2 = beta_oblique(s1, V1, theta)
    print "beta2(degrees)=", beta2*180/math.pi
    #
    M1 = 1.5
    print "\nTaylor-Maccoll cone flow demo with M1=%g" % M1
    print "for M1=1.5, beta=49deg, expect theta=20deg."
    V1 = M1 * s1.a
    beta = 49.0 * math.pi/180
    theta_c, V_c, s_c = theta_cone(s1, V1, beta)
    print "theta_c(deg)=", theta_c*180.0/math.pi, "expected 20deg, surface speed V_c=", V_c
    print "surface pressure coefficient=", (s_c.p - s1.p)/(0.5*s1.rho*V1*V1), "expected 0.385"
    print "s_c:"
    s_c.write_state(sys.stdout)
    #
    M1 = 1.5
    print "\nTaylor-Maccoll cone flow demo with M1=%g" % M1
    print "for M1=1.5, beta=49.0404423512deg, expect theta=20deg."
    V1 = M1 * s1.a
    beta = 49.0404423512 * math.pi/180
    theta_c, V_c, s_c = theta_cone(s1, V1, beta)
    print "theta_c(deg)=", theta_c*180.0/math.pi, "expected 20deg, surface speed V_c=", V_c
    print "surface pressure coefficient=", (s_c.p - s1.p)/(0.5*s1.rho*V1*V1), "expected 0.385"
    print "s_c:"
    s_c.write_state(sys.stdout)
    sys.exit(-1)
    #
    M1 = 1.8
    print "\nTaylor-Maccoll cone flow demo with M1=%g" % M1
    print "for M1=1.8, beta=45deg, theta=24deg."
    V1 = M1 * s1.a
    beta = 45.0 * math.pi/180
    theta_c, V_c, s_c = theta_cone(s1, V1, beta)
    print "theta_c(deg)=", theta_c*180.0/math.pi, "expected 24deg, surface speed V_c=", V_c
    print "surface pressure coefficient=", (s_c.p - s1.p)/(0.5*s1.rho*V1*V1), "expected 0.466"
    print "s_c:"
    s_c.write_state(sys.stdout)
    #
    M1 = 1.5
    print "Conical shock from cone with half-angle 20deg in M1=", M1
    V1 = M1 * s1.a
    beta = beta_cone(s1, V1, 20.0*math.pi/180)
    print "sigma(deg)=", beta*180/math.pi, "expected 49deg"
    print "Done."
