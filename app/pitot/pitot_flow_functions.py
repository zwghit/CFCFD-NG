#! /usr/bin/env python
"""
pitot_flow_functions.py: pitot flow functions

This file collects all of the functions that the larger pitot program uses to
process the gases as they travel through the tube.

Chris James (c.james4@uq.edu.au) - 07/05/13 

"""

from cfpylib.nm.zero_solvers import secant
# We base our calculation of gas properties upon calls to the NASA Glenn CEA code.
from cfpylib.gasdyn.cea2_gas import Gas, make_gas_from_name
from cfpylib.gasdyn.gas_flow import *
from cfpylib.gasdyn.ideal_gas_flow import p0_p, pitot_p

#to do some perfect gas stuff

import cfpylib.gasdyn.ideal_gas as pg

from pitot_input_utils import make_test_gas

PRINT_STATUS = 1 #if print status is 1, some basic printouts are done

def secondary_driver_calculation(cfg, states, V, M):
    """Function that does the expansion through the secondary driver 
    tube if required."""
    
    def error_in_velocity_s3s_to_sd3_expansion_pressure_iterator(psd1, state3s=states['s3s'], 
                                               V3sg=V['s3s'], statesd1=states['sd1'],
                                                statesd2=states['sd2'],Vsd=cfg['Vsd'],
                                                steps=cfg['secondary_driver_expansion_steps']):
        """Compute the velocity mismatch for a given pressure ratio across the 
        unsteady expansion in the driver into the secondary driver gas."""
        
        print "current guess for psd1 = {0} Pa".format(psd1)            
        
        statesd1.set_pT(psd1,300.0) #set s1 at set pressure and ambient temp
        
        (Vsd2, Vsd2g) = normal_shock(statesd1, Vsd, statesd2)
        
        #Across the contact surface, p3 == p2
        psd3 = statesd2.p
        
        # Across the expansion, we get a velocity, V5g.
        Vsd3g, statesd3 = finite_wave_dp('cplus', V3sg, state3s, psd3, steps=steps)

        return (Vsd2g - Vsd3g)/Vsd2g
        
    def error_in_velocity_s3s_to_sd3_driver_expansion_shock_speed_iterator(Vsd,state3s=states['s3s'], 
                                               V3sg=V['s3s'], statesd1=states['sd1'],
                                                statesd2=states['sd2'],
                                                steps=cfg['secondary_driver_expansion_steps']):
        """Compute the velocity mismatch for a given shock speed with the driver
        unsteady expansion into the secondary driver gas behind it.
        
        Make sure you set the fill pressure in sd1 before you start!"""
        
        print "current guess for Vsd = {0} m/s".format(Vsd)            
        
        (Vsd2, Vsd2g) = normal_shock(statesd1, Vsd, statesd2)
        
        #Across the contact surface, p3 == p2
        psd3 = statesd2.p
        
        # Across the expansion, we get a velocity, V5g.
        Vsd3g, statesd3 = finite_wave_dp('cplus', V3sg, state3s, psd3, steps=steps)

        return (Vsd2g - Vsd3g)/Vsd2g  
    
    if cfg['test'] == "fulltheory-shock": #get psd1 for our chosen shock speed
        cfg['psd1'] = secant(error_in_velocity_s3s_to_sd3_expansion_pressure_iterator, 5000.0, 6000.0, tol=1.0e-5,limits=[1000.0,1000000.0])
        if PRINT_STATUS: print "From secant solve: psd1 = {0} Pa".format(cfg['psd1'])
        #start using psd1 now, compute states sd1,sd2 and sd3 using the correct psd1
        if PRINT_STATUS: print "Once p1 is known, find conditions at state 1 and 2."
        states['sd1'].set_pT(cfg['psd1'],cfg['T0'])
    
    elif cfg['test'] == "fulltheory-pressure": #get Vsd for our chosen fill pressure
        if cfg['tunnel_mode'] == 'expansion-tube':
            cfg['Vsd'] = secant(error_in_velocity_s3s_to_sd3_driver_expansion_shock_speed_iterator, 4000.0, 5000.0, tol=1.0e-5,limits=[1000.0,1000000.0])
        elif cfg['tunnel_mode'] == 'nr-shock-tunnel': #do a higher speed guess for a nr-shock-tunnel
            cfg['Vsd'] = secant(error_in_velocity_s3s_to_sd3_driver_expansion_shock_speed_iterator, 7000.0, 8000.0, tol=1.0e-5,limits=[1000.0,1000000.0]) 
        if PRINT_STATUS: print "From secant solve: Vsd = {0} m/s".format(cfg['Vsd'])
        #start using Vs1 now, compute states 1,2 and 3 using the correct Vs1
        if PRINT_STATUS: print "Once Vsd is known, find conditions at state sd1 and sd2."
    
    (Vsd2, V['sd2']) = normal_shock(states['sd1'], cfg['Vsd'], states['sd2'])
    V['sd3'], states['sd3'] = finite_wave_dv('cplus', V['s3s'], states['s3s'], V['sd2'], steps=cfg['secondary_driver_expansion_steps'])

    #get mach numbers for the txt_output
    cfg['Msd1'] = cfg['Vsd']/states['sd1'].son
    M['sd2'] = V['sd2']/states['sd2'].son
    M['sd3']= V['sd3']/states['sd3'].son
    
    return cfg, states, V, M
    
#----------------------------------------------------------------------------

def shock_tube_calculation(cfg, states, V, M):
    """Function that performs all of the shock tube calculations."""

    #--------------------- shock tube functions ---------------------------------
        
    def error_in_velocity_shock_tube_expansion_pressure_iterator(p1, 
                                               expanding_state=states[cfg['shock_tube_expansion']], 
                                               expansion_start_V=V[cfg['shock_tube_expansion']], 
                                                state1=states['s1'],
                                                state2=states['s2'],Vs1=cfg['Vs1'],
                                                solver=cfg['solver'], test_gas=cfg['test_gas'],
                                                steps=cfg['shock_tube_expansion_steps']):
        """Compute the velocity mismatch for a given pressure ratio across the 
        unsteady expansion in the shock tube."""
        
        print "current guess for p1 = {0} Pa".format(p1)            
        
        state1.set_pT(p1,300.0) #set s1 at set pressure and ambient temp
        
        if solver == 'eq' or solver == 'pg':
            (V2, V2g) = normal_shock(state1, Vs1, state2)  
        elif solver == 'pg-eq': #if we're using the perfect gas eq solver, we want to make an eq state1, set it's T and p, clone it to state2_eq and then shock process it through CEA
            if gasName == 'mars' or gasName == 'co2' or gasName == 'venus':
                state1_eq, nothing1, nothing2, nothing3 = make_test_gas(test_gas) #make eq state1
            else: 
                state1_eq, nothing = make_test_gas(test_gas) #make eq state1
            state2 = state1_eq.clone() #clone state 1 to a new state2
            #set state 2 with state 1's properties as we're about to shock it:
            state2.p = state1.p; state2.T = state1.T
            state2.shock_process(Vs1) #shock it
            #now we're going to use continuity to set the gas velocity manually here:
            V1 = Vs1
            V2 = V1 * state1.rho / state2.rho
            V2g = V1 - V2
               
        #Across the contact surface, p3 == p2
        p3 = state2.p
        
        # Across the expansion, we get a velocity, V5g.
        V3g, state3 = finite_wave_dp('cplus', expansion_start_V, expanding_state, p3,steps=steps)

        return (V2g - V3g)/V2g
        
    def p1_reflected_iterator(p1, statesd2=states[cfg['shock_tube_expansion']], 
                              Vsd2g=V[cfg['shock_tube_expansion']], state1=states['s1'], 
                              state2=states['s2'], state3=states['s3'], Vs1=cfg['Vs1']):
        """Compute the velocity mismatch for a given pressure ratio across the reflected
            shock from the secondary driver into the shock tube. 
            
            Used when Vsd > Vs1"""
                    
        print "current guess for p1 = {0} Pa".format(p1)

        state1.set_pT(p1,300.0) #set s1 at set pressure and ambient temp
        
        V2, V2g = normal_shock(state1, Vs1, state2)
        
        def reflected_shock_speed_iterator(Vr,statesd2=statesd2,
                                           Vsd2g=Vsd2g, state3=state3,
                                           V2g=V2g):
            """iterates out the reflected shock speed that gives the right velocity behind
                a normal shock."""
    
            print "Current guess for Vr = {0} m/s".format(Vr)
    
            V3, V3g = normal_shock(statesd2, Vsd2g+Vr, state3)
    
            return (V3-(V2g+Vr))/V3
        
        Vr = secant(reflected_shock_speed_iterator, 100.0, 200.0, tol=1.0e-4)
    
        V3,V3g = normal_shock(statesd2,Vsd2g+Vr,state3)
    
        return (state3.p-state2.p)/state2.p
            
        
        #Across the contact surface, p3 == p2
        p3 = state2.p
        
        # therefore we know the required pressure ratio across our shock
        
        print 'shocking state psd2 = {0} Pa, p3 = {1} Pa'.format(shocking_state.p,p3)
        
        (Vs1found, V3, V3g, state3) = normal_shock_p2p1(shocking_state, p3/shocking_state.p)
        
        print 'Vs1 found is {0} m/s'.format(Vs1found)
        
        print 'V2g = {0} m/s, V3g = {1} m/s'.format(V2g,V3g)
        
        print 'V3 = {0} m/s'.format(V3)
        
        return (V2g - V3g)/V2g        
        
    def error_in_velocity_shock_tube_expansion_shock_speed_iterator(Vs1,
                                                expanding_state=states[cfg['shock_tube_expansion']], 
                                                expansion_start_V=V[cfg['shock_tube_expansion']],                    
                                                state1=states['s1'], state2=states['s2'],
                                                solver=cfg['solver'], test_gas=cfg['test_gas'],
                                                steps=cfg['shock_tube_expansion_steps']):
        """Compute the velocity mismatch for a given shock speed with the shock tube
        unsteady expansion behind it.
        
        Make sure you set the fill pressure in state 1 before you start!"""
        
        print "current guess for Vs1 = {0} m/s".format(Vs1)            
        
        if solver == 'eq' or solver == 'pg':
            (V2, V2g) = normal_shock(state1, Vs1, state2) 
        elif solver == 'pg-eq': #if we're using the perfect gas eq solver, we want to make an eq state1, set it's T and p, clone it to state2_eq and then shock process it through CEA
            if test_gas == 'mars' or test_gas == 'co2' or test_gas == 'venus':
                state1_eq, nothing1, nothing2, nothing3 = make_test_gas(test_gas) #make eq state1
            else: 
                state1_eq, nothing = make_test_gas(test_gas) #make eq state1
            state2 = state1_eq.clone() #clone state 1 to a new state2
            #set state 2 with state 1's properties as we're about to shock it:
            state2.p = state1.p; state2.T = state1.T
            state2.shock_process(Vs1) #shock it
            #now we're going to use continuity to set the gas velocity manually here:
            V1 = Vs1
            V2 = V1 * state1.rho / state2.rho
            V2g = V1 - V2
                    
        #Across the contact surface, p3 == p2
        p3 = state2.p
        
        # Across the expansion, we get a velocity, V5g.
        V3g, state3 = finite_wave_dp('cplus', expansion_start_V, expanding_state, p3, steps=steps)
    
        return (V2g - V3g)/V2g

    def primary_shock_speed_reflected_iterator(Vs1,statesd2=states[cfg['shock_tube_expansion']],
                                               Vsd2g=V[cfg['shock_tube_expansion']],state1=states['s1'],
                                               state2=states['s2'],state3=states['s3']):
        """The other new iterator for pitot. Has another iterator inside it, will take
        AGES to run. Oh well, no other choice as far as I see."""
    
        print "Current guess for Vs1 = {0} m/s".format(Vs1)
        
        V2, V2g = normal_shock(state1, Vs1, state2)
    
        def reflected_shock_speed_iterator(Vr,statesd2=statesd2,
                                           Vsd2g=Vsd2g, state3=state3,
                                           V2g=V2g):
            """iterates out the reflected shock speed that gives the right velocity behind
                a normal shock."""
    
            print "Current guess for Vr = {0} m/s".format(Vr)
    
            V3, V3g = normal_shock(statesd2, Vsd2g+Vr, state3)
    
            return (V3-(V2g+Vr))/V3
    
        Vr = secant(reflected_shock_speed_iterator, 100.0, 200.0, tol=1.0e-4)
    
        V3,V3g = normal_shock(statesd2,Vsd2g+Vr,state3)
    
        return (state3.p-state2.p)/state2.p


    #----------------------- shock tube calculations --------------------------------                           
      
    if cfg['test'] == "fulltheory-shock": #get p1 for our chosen shock speed
        if cfg['secondary']: #if secondary, check which shock speed is greater, Vsd or Vs1
            if cfg['Vsd'] > cfg['Vs1']: #we get a shock into the shock tube, not an expansion
                cfg['shock_switch'] = True #flip over this switch
                if PRINT_STATUS: print "Vsd is a stronger shock than Vs1. Therefore a normal shock processes the secondary driver gas moving into the shock tube."
                cfg['p1'] = secant(p1_reflected_iterator, 1000.0, 100000.0, tol=1.0e-5,limits=[100.0,1000000.0])
            else: #same expansion as we're used to
                if PRINT_STATUS: print "Start unsteady expansion of the secondary driver gas into the shock tube."
                cfg['p1'] = secant(error_in_velocity_shock_tube_expansion_pressure_iterator, 1000.0, 100000.0, tol=1.0e-4,limits=[100.0,1000000.0])
        else: #just do the expansion
            if PRINT_STATUS: print "Start unsteady expansion of the driver gas into the shock tube."
            cfg['p1'] = secant(error_in_velocity_shock_tube_expansion_pressure_iterator, 1000.0, 100000.0, tol=1.0e-4,limits=[100.0,1000000.0])

        if PRINT_STATUS: print "From secant solve: p1 = {0} Pa".format(cfg['p1'])
        #start using p1 now, compute states 1,2 and 3 using the correct p1
        if PRINT_STATUS: print "Once p1 is known, find conditions at state 1 and 2."
        states['s1'].set_pT(cfg['p1'],cfg['T0'])
        
    elif cfg['test'] =="fulltheory-pressure": #get Vs1 for our chosen fill pressure
        if cfg['shock_switch']: #if we've been told to do a shock here instead of an expansion, do a shock instead of an expansion
            if PRINT_STATUS: print "The shock switch is turned on, therefore doing a shock here instead of the normal expansion... Turn this off if you didn't want it"
            if PRINT_STATUS: print "Current settings with the shock switch turned on here HALF the selected p1 and p5 to match experiment."
            if PRINT_STATUS: print "the fill pressure's will be returned back to normal when the results are printed at the end..."
            states['s1'].p = states['s1'].p/2.0
            states['s5'].p = states['s5'].p/2.0
            cfg['Vs1'] = secant(primary_shock_speed_reflected_iterator, 2000.0, 4000.0, tol=1.0e-5,limits=[500.0,1000000.0])
        else: #just do the expansion
            if cfg['tunnel_mode'] == 'expansion-tube':
                cfg['Vs1'] = secant(error_in_velocity_shock_tube_expansion_shock_speed_iterator, 4000.0, 6000.0, tol=1.0e-3,limits=[1000.0,1000000.0])
            elif cfg['tunnel_mode'] == 'nr-shock-tunnel': #start with a higher speed guess in nr-shock-tunnel mode
                cfg['Vs1'] = secant(error_in_velocity_shock_tube_expansion_shock_speed_iterator, Vsd+2000.0, Vsd+3000.0, tol=1.0e-3,limits=[1000.0,1000000.0])
        if PRINT_STATUS: print "From secant solve: Vs1 = {0} m/s".format(cfg['Vs1'])
        #start using Vs1 now, compute states 1,2 and 3 using the correct Vs1
        if PRINT_STATUS: print "Once Vs1 is known, find conditions at state 1 and 2."
    (V2, V['s2']) = normal_shock(states['s1'], cfg['Vs1'], states['s2'])
    if cfg['solver'] == 'pg-eq': #if we're using the pg-eq solver this is the point where we move from pg to eq gas objects
        if cfg['test_gas'] == 'mars' or cfg['test_gas'] == 'co2' or cfg['test_gas'] == 'venus':
            states['s1-eq'], nothing1, nothing2, nothing3 = make_test_gas(cfg['test_gas']) #make eq state1
        else: 
            states['s1-eq'], nothing = make_test_gas(cfg['test_gas']) #make eq state1
        states['s2'] = states['s1-eq'].clone() #get a new state2 ready   
        #set state 2 with state 1's properties as we're about to shock it:
        states['s2'].p = states['s1'].p; states['s2'].T = states['s1'].T
        states['s2'].shock_process(cfg['Vs1']) #shock it
        states['s7'] = states['s2'].clone() #need to turn s7 into an eq object too
        #now we're going to use continuity to set the gas velocity manually here:
        V1 = cfg['Vs1']
        V2 = V1 * states['s1'].rho / states['s2'].rho
        V['s2'] = V1 - V2
        
    if cfg['shock_switch']: #do a shock here if required
        V['s3'] = V['s2']
        #need to back out Vr again here, for now I was lazy and put the function back in:
        if PRINT_STATUS: print "Need to reiterate to find Vr again here..."   
        def reflected_shock_speed_iterator(Vr,statesd2=states['sd2'],
                                           Vsd2g=V[cfg['shock_tube_expansion']],
                                            state3=states['s3'], V2g=V['s2']):
            """iterates out the reflected shock speed that gives the right velocity behind
                a normal shock."""
    
            print "Current guess for Vr = {0} m/s".format(Vr)
    
            V3, V3g = normal_shock(statesd2, Vsd2g+Vr, state3)
    
            return (V3-(V2g+Vr))/V3
        
        Vr = secant(reflected_shock_speed_iterator, 100.0, 200.0, tol=1.0e-4)
        (V3,Vjunk) = normal_shock(states['sd2'],V[cfg['shock_tube_expansion']]+Vr,states['s3'])
    else:
        V['s3'], states['s3'] = finite_wave_dv('cplus', V[cfg['shock_tube_expansion']], states[cfg['shock_tube_expansion']], V['s2'],cfg['shock_tube_expansion_steps'])
    
    #get mach numbers for the txt_output
    cfg['Ms1'] = cfg['Vs1']/states['s1'].son
    M['s2'] = V['s2']/states['s2'].son
    M['s3']= V['s3']/states['s3'].son
    
    #erase the gas guess if we don't think we'll need it in the acc tube
    
    if ('p5' in cfg and cfg['solver'] == 'eq' or cfg['solver'] == 'pg-eq') \
    or (cfg['Vs2'] >= 9000.0 and cfg['solver'] == 'eq' or cfg['solver'] == 'pg-eq'): 
        # just use the gas guess if you don't know if you'll need it
        # and set an air guess too
        cfg['gas_guess_air'] = {'gam':1.35,'R':571.49}     
    else:
        cfg['gas_guess'] = None ; cfg['gas_guess_air'] = None
        
    return cfg, states, V, M
    
#----------------------------------------------------------------------------
    
def acceleration_tube_calculation(cfg, states, V, M):
    """Function that contains all of the acceleration tube calculations."""
            
    if PRINT_STATUS: print "Start unsteady expansion of the test gas into the acceleration tube."

    #----------------------- acceleration tube functions -----------------------

    def error_in_velocity_s2_expansion_pressure_iterator(p5, state2=states['s2'], 
                                       V2g=V['s2'], state5=states['s5'],
                                        state6=states['s6'],Vs2=cfg['Vs2'],
                                        ideal_gas_guess=cfg['gas_guess_air'],
                                        expand_to = cfg['expand_to'], 
                                        expansion_factor = cfg['expansion_factor'],
                                        steps=cfg['acc_tube_expansion_steps']):
        """Compute the velocity mismatch for a given pressure ratio across the 
        unsteady expansion from state 2 to state 7."""
        
        print "current guess for p5 = {0} Pa".format(p5)
        
        state5.set_pT(p5,300.0) #set s1 at set pressure and ambient temp
        
        (V6, V6g) = normal_shock(state5, Vs2, state6,ideal_gas_guess)
        
        #do any modifications that were requested to the velocity behind the shock here 
        if expand_to == 'flow-behind-shock':
            V6g = V6g*expansion_factor
        elif expand_to == 'shock-speed':
            V6g = Vs2*expansion_factor
        
        
        #Across the contact surface, p3 == p2
        p7 = state6.p
        
        # Across the expansion, we get a velocity, V7g.
        V7g, state7 = finite_wave_dp('cplus', V2g, state2, p7, steps=steps)

        return (V6g - V7g)/V6g
        
    def error_in_pressure_s2_expansion_shock_speed_iterator(Vs2, state2=states['s2'], 
                                       V2g=V['s2'], state5=states['s5'],
                                        state6=states['s6'],
                                        ideal_gas_guess=cfg['gas_guess_air'],
                                        expand_to = cfg['expand_to'], 
                                        expansion_factor = cfg['expansion_factor'],
                                        steps=cfg['acc_tube_expansion_steps']):
        """Compute the velocity mismatch for a given shock speed in front of the 
        unsteady expansion from state 2 to state 7."""
        
        print "current guess for Vs2 = {0} m/s".format(Vs2)
               
        (V6, V6g) = normal_shock(state5, Vs2, state6, ideal_gas_guess)
        
        #do any modifications that were requested to the velocity behind the shock here 
        if expand_to == 'flow-behind-shock':
            V6g = V6g*expansion_factor
        elif expand_to == 'shock-speed':
            V6g = Vs2*expansion_factor
        
        #Across the contact surface, p3 == p2
        p7 = state6.p
                   
        # Across the expansion, we get a velocity, V7g.
        V7g, state7 = finite_wave_dp('cplus', V2g, state2, p7, steps=steps)

        return (V6g - V7g)/V6g    
        
    #---------------------- acceleration tube calculations -----------------------
           
    if cfg['test'] == 'fulltheory-shock': #get p5 for our chosen shock speed
        #put two sets of limits here to try and make code that works will all conditions
        if cfg['Vs2'] > 4000.0 and 'p5_lower' not in cfg and 'p5_upper' not in cfg \
        and 'p5_guess_1' not in cfg and 'p5_guess_2' not in cfg:
            cfg['p5_lower'] = 1.0; cfg['p5_upper'] = 1000.0 #upper and lower limits (Pa)
            cfg['p5_guess_1'] = 10.0; cfg['p5_guess_2'] = 100.0 #first and second guesses for secant solver (Pa)
        elif cfg['Vs2'] <= 4000.0 and 'p5_lower' not in cfg and 'p5_upper' not in cfg \
        and 'p5_guess_1' not in cfg and 'p5_guess_2' not in cfg:
            cfg['p5_lower'] = 20.0; cfg['p5_upper'] = 1000.0 #upper and lower limits (Pa)
            cfg['p5_guess_1'] = 500.0; cfg['p5_guess_2'] = 1000.0 #first and second guesses for secant solver (Pa)
        cfg['p5'] = secant(error_in_velocity_s2_expansion_pressure_iterator, \
        cfg['p5_guess_1'], cfg['p5_guess_2'], tol=1.0e-5,limits=[cfg['p5_lower'],cfg['p5_upper']])
        if PRINT_STATUS: print "From secant solve: p5 = {0} Pa".format(cfg['p5'])
        
        #start using p5 now, compute states 5,6 and 7 using the correct p5
        if PRINT_STATUS: print "Once p5 is known, find conditions at state 5 and 6."
        states['s5'].set_pT(cfg['p5'],cfg['T0'])
        
    elif cfg['test'] == 'fulltheory-pressure': #compute the shock speed for the chosen fill pressure, uses Vs1 as starting guess
        #put two sets of limits here to try and make more stuff work
        if cfg['Vs1'] < 2000.0 and 'Vs2_lower' and 'Vs2_upper' not in cfg:
            cfg['Vs2_lower'] = cfg['Vs1'] + 1000.0; cfg['Vs2_upper'] = 25000.0
        elif cfg['Vs1'] >= 2000.0 and 'Vs2_lower' and 'Vs2_upper' not in cfg:
            cfg['Vs2_lower'] = cfg['Vs1'] + 1000.0; cfg['Vs2_upper'] = 25000.0
        if 'Vs2_guess_1' not in cfg and 'Vs2_guess_2' not in cfg:
            cfg['Vs2_guess_1'] = cfg['Vs1']+7000.0; cfg['Vs2_guess_2'] = 15100.0
        cfg['Vs2'] = secant(error_in_pressure_s2_expansion_shock_speed_iterator, \
        cfg['Vs2_guess_1'], cfg['Vs2_guess_2'], tol=1.0e-5,limits=[cfg['Vs2_lower'],cfg['Vs2_upper']])
        if PRINT_STATUS: print "From secant solve: Vs2 = {0} m/s".format(cfg['Vs2'])
        #start using Vs1 now, compute states 1,2 and 3 using the correct Vs1
        if PRINT_STATUS: print "Once Vs2 is known, find conditions at state 5 and 6."            
        
    (V6, V['s6']) = normal_shock(states['s5'], cfg['Vs2'], states['s6'],cfg['gas_guess_air'])
    #do any modifications that were requested to the velocity behind the shock here 
    if cfg['expand_to'] == 'flow-behind-shock':
        V['s6'] = V['s6']*cfg['expansion_factor']
    elif cfg['expand_to'] == 'shock-speed':
        V['s6'] = cfg['Vs2']*cfg['expansion_factor']
    V['s7'], states['s7'] = finite_wave_dv('cplus', V['s2'], states['s2'], V['s6'], steps=cfg['acc_tube_expansion_steps'])
    
    #get mach numbers for the txt_output
    cfg['Ms2'] = cfg['Vs2']/states['s5'].son
    M['s6'] = V['s6']/states['s6'].son
    M['s7']= V['s7']/states['s7'].son
    
    return cfg, states, V, M
    
#----------------------------------------------------------------------------
    
def test_section_setup(cfg, states, V, M):
    """Function to setup what is the test section state. It will also do the
    steady expansion through the nozzle if it detects that it needs to."""
                      
    if cfg['tunnel_mode'] == 'expansion-tube' and cfg['nozzle']:    
            if PRINT_STATUS: print "Start steady expansion through the nozzle."
            (V['s8'], states['s8']) = steady_flow_with_area_change(states['s7'], V['s7'], cfg['area_ratio'])
            M['s8']= V['s8']/states['s8'].son
            cfg['test_section_state'] = 's8'
    elif cfg['tunnel_mode'] == 'expansion-tube' and not cfg['nozzle']:
            cfg['test_section_state'] = 's7' 
    elif cfg['tunnel_mode'] == 'nr-shock-tunnel' and cfg['nozzle']:
            if PRINT_STATUS: print "Start steady expansion through the nozzle."
            (V['s8'], states['s8']) = steady_flow_with_area_change(states['s2'], V['s2'], cfg['area_ratio'])
            M['s8']= V['s8']/states['s8'].son
            cfg['test_section_state'] = 's8'
    elif cfg['tunnel_mode'] == 'nr-shock-tunnel' and not cfg['nozzle']:            
            cfg['test_section_state'] = 's2'

    return cfg, states, V, M

#----------------------------------------------------------------------------      
    
def shock_over_model_calculation(cfg, states, V, M):
    """Function that takes the cfg, states, V and M dictionaries
    and does the shock over model calculations if the user requests it.
    The changed dictionaries are then returned.
    """
    if PRINT_STATUS: print "Start frozen normal shock calculation over the test model."  
    states['s10f'] = states[cfg['test_section_state']].clone()
    (V10, V['s10f']) = shock_ideal(states[cfg['test_section_state']], V[cfg['test_section_state']], states['s10f'])
    M['s10f']= V['s10f']/states['s10f'].son

    if PRINT_STATUS: print "Start equilibrium normal shock calculation over the test model."  
    if cfg['solver'] == 'eq' or cfg['solver'] == 'pg-eq': 
        states['s10e'] = states[cfg['test_section_state']].clone()
        (V10, V['s10e']) = normal_shock(states[cfg['test_section_state']], V[cfg['test_section_state']], states['s10e'])
        M['s10e']= V['s10e']/states['s10e'].son
    elif cfg['solver'] == 'pg': #we need to make a cea2 gas object to do this equilibrium calculaiton if every other gas object is pg
        states[cfg['test_section_state']+'eq'] = make_test_gas(cfg['test_gas'])[0]
        states[cfg['test_section_state']+'eq'].set_pT(states[cfg['test_section_state']].p,states[cfg['test_section_state']].T)
        states['s10e'] = states[cfg['test_section_state']+'eq'].clone()
        (V10, V['s10e']) = normal_shock(states[cfg['test_section_state']+'eq'], V[cfg['test_section_state']], states['s10e'])
        M['s10e']= V['s10e']/states['s10e'].son
        
    return cfg, states, V, M
    
#----------------------------------------------------------------------------
    
def conehead_calculation(cfg, states, V, M):
    """Function that takes the cfg, states, V and M dictionaries, does a 
    calculation for a conehead in the test section at a specified angle
    and then returns the changes cfg, states, V, M dictionaries."""
    
    if PRINT_STATUS: print 'Doing taylor maccoll conehead calculation on {0} degree conehead.'.format(cfg['conehead_angle'])
    shock_angle = beta_cone(states[cfg['test_section_state']], V[cfg['test_section_state']], math.radians(cfg['conehead_angle']))
    if PRINT_STATUS: print "\nShock angle over cone:", math.degrees(shock_angle)
    # Reverse the process to get the flow state behind the shock and check the surface angle is correct
    delta_s, V['s10c'], states['s10c'] = theta_cone(states[cfg['test_section_state']], V[cfg['test_section_state']], shock_angle)
    M['s10c'] = V['s10c']/states['s10c'].son
    if PRINT_STATUS: print "Surface angle should be the same.....: 15deg = ", math.degrees(delta_s), "deg"
    #if PRINT_STATUS: print "\nConehead surface conditions:"
    #if PRINT_STATUS: states['s10c'].write_state(sys.stdout)
    # Need to check whether the pressure are the same
    if PRINT_STATUS: print "Computed conehead pressure is {0} Pa".format(states['s10c'].p)
    
    return cfg, states, V, M
    
#----------------------------------------------------------------------------
        
def test_time_calculator(cfg, states, V):
    """Function that takes the cfg, states and V dictionaries and will return
    the cfg dictionary with basic test time calculated if it is able to."""
    
    #This was based off code written by David Gildfind that was based off a paper
    #by Allan Paull and Ray Stalker. I've only considered the basic test time case here
    # A. Paull & R. J. Stalker, "Test Flow Disturbances in an Expansion Tube", J. Fluid Mech. (1992), vol. 245, pp. 493-521 (p499).
    
    cfg['calculate_test_time'] = False #defaults to false unless we have enough info to calculate it
    
    if cfg['facility'] == 'x2' and cfg['tunnel_mode'] == 'expansion-tube':
        #a few different tunnel scenarios give different lengths
        #all the distances are taken from my L1D run file, written by David Gildfind
        #0m is the primary diaphragm burst location
        cfg['calculate_test_time'] = True
        if not cfg['secondary'] and not cfg['nozzle']:
            distances = [3.418, 8.979] #secondary diaphragm, and then end of acc tube (m)
        elif cfg['secondary'] and not cfg['nozzle']:
            distances = [3.418, 5.976, 8.979] #secondary diaphragm, tertiary diaphragm, end of acc tube (m)
        elif not cfg['secondary'] and cfg['nozzle']:
            distances = [3.418, 8.585] #secondary diaphragm, entrance to nozzle (m)
        elif cfg['secondary'] and cfg['nozzle']:
            distances = [3.418, 5.976, 8.585] #secondary diaphragm, tertiary, entrance to nozzle (m)
    
        t_start = 0.0 #time of primary diaphragm burst
    
        if cfg['secondary']: #if secondary we have a third tube to consider
            #calculate some lengths
            L_sec_drv = distances[0]
            L_shk_tube = distances[1] - distances[0]
            L_acc_tube = distances[2] - distances[1]
            
            #shocks
            t_inc_shock_sd = t_start + L_sec_drv/cfg['Vsd']
            t_inc_shock_st = t_inc_shock_sd + L_shk_tube/cfg['Vs1']
            t_inc_shock_at = t_inc_shock_st + L_acc_tube/cfg['Vs2']
            
            #contact surfaces
            t_cs_sd = t_start + L_sec_drv/V['sd3']
            t_cs_st = t_inc_shock_sd + L_shk_tube/V['s3']
            t_cs_at = t_inc_shock_st + L_acc_tube/V['s7']

        
        else: #so we're going straight from primary driver to shock tube now
            #calculate some lengths
            L_shk_tube = distances[0]
            L_acc_tube = distances[1] - distances[0]
            
            #shocks
            t_inc_shock_st = t_start + L_shk_tube/cfg['Vs1']
            t_inc_shock_at = t_inc_shock_st +  L_acc_tube/cfg['Vs2']
            
            #contact surfaces
            t_cs_sd = t_start + L_shk_tube/V['s3']
            t_cs_at = t_inc_shock_st +  L_acc_tube/V['s7']
            
        
        #now we can actually calculate the basic test time...
        # (borrowed from the procedure David Gildfind used in his PhD)
        
        #now we just need to calculate the time taken for the unsteady 
        #expansion to hit the end of the acc tube
        
        t_final_usx = t_inc_shock_st + L_acc_tube/(V['s7']-states['s7'].son)
        
        cfg['t_test_basic'] = t_final_usx - t_cs_at
        
    return cfg