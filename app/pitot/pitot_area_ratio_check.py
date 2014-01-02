#! /usr/bin/env python
"""
pitot_area_ratio_check.py: pitot area ratio check

This file includes functions that run through multiple specified
area ratios after a normal pitot run is completed.

Chris James (c.james4@uq.edu.au) - 20/08/13 

"""

import sys

from pitot_flow_functions import nozzle_expansion, conehead_calculation, shock_over_model_calculation

def area_ratio_check(cfg, states, V, M):
    """Overarching area ratio check function."""
    
    # open a file to start saving our results
    area_ratio_output = open(cfg['filename']+'-area-ratio-check.csv',"w")  #csv_output file creation
    # print a line explaining the results
    intro_line_1 = "# Output of pitot area ratio checking program performed using Pitot version {0}.".format(cfg['VERSION_STRING'])
    area_ratio_output.write(intro_line_1 + '\n')
    intro_line_2 = "# units are the same as the program. Velocities in m/s, pressures in Pa, temperatures in K."
    area_ratio_output.write(intro_line_2 + '\n')
    if cfg['conehead'] and not cfg['shock_over_model']:
        intro_line_3 = "# area ratio,p8,T8,V8,M8,p10c,T10c,V10c"
    elif cfg['shock_over_model'] and not cfg['conehead']:
        intro_line_3 = "# area ratio,p8,T8,V8,M8,p10f,T10f,V10f,p10e,T10e,V10e"
    elif cfg['shock_over_model'] and cfg['conehead']:
        intro_line_3 = "# area ratio,p8,T8,V8,M8,p10c,T10c,V10c,p10f,T10f,V10f,p10e,T10e,V10e"        
    else:
        intro_line_3 = "# area ratio,p8,T8,V8,M8"
    area_ratio_output.write(intro_line_3 + '\n')
    
    # start by storing old area ratio so it can be retained later

    old_area_ratio = cfg['area_ratio']  
    
    print "Performing area ratio check by running through a {0} different area ratios."\
    .format(len(cfg['area_ratio_check_list']))
    
    counter = 0 #counter used to tell user how far through the calculations we are
               
    for area_ratio in cfg['area_ratio_check_list']:
        # add the current area ratio
        counter += 1
        cfg['area_ratio'] = area_ratio
        print 60*"-"
        print "Test {0} of {1} (Current area ratio = {2})."\
        .format(counter, len(cfg['area_ratio_check_list']), area_ratio)
        # run the nozzle expansion
        cfg, states, V, M = nozzle_expansion(cfg, states, V, M)
        if cfg['conehead']: #do the conehead calculation if required
            cfg, states, V, M = conehead_calculation(cfg, states, V, M)
        if cfg['shock_over_model']: #do the shock over model calc if required
            cfg, states, V, M = shock_over_model_calculation(cfg, states, V, M)
        # print some stuff to the screen
        print "V8 = {0} m/s, M8 = {1}.".format(V['s8'], M['s8'])
        print "State 8 (freestream at the nozzle exit):"
        states['s8'].write_state(sys.stdout)
        if cfg['conehead'] and cfg['conehead_completed']:
            print "V10c = {0} m/s.".format(V['s10c'])
            print "State 10c (surface of a 15 degree conehead):"
            states['s10c'].write_state(sys.stdout)
        elif cfg['conehead'] and not cfg['conehead_completed']:
            print "Conehead calculation failed so result is not being printed."
        if cfg['shock_over_model']:
            print "V10f = {0} m/s.".format(V['s10f'])
            print "State 10f (frozen normal shock over the test model):"
            states['s10f'].write_state(sys.stdout)      
            print "V10e = {0} m/s.".format(V['s10e'])
            print "State 10e (equilibrium normal shock over the test model):"
            states['s10e'].write_state(sys.stdout)  
        
        #now add a new line to the output file
        #only prints the line to the csv if the conehead calc completed
        if cfg['conehead'] and cfg['conehead_completed'] and not cfg['shock_over_model']:        
            new_output_line = "{0},{1},{2},{3},{4},{5},{6},{7}"\
            .format(area_ratio, states['s8'].p, states['s8'].T,V['s8'],\
                    M['s8'], states['s10c'].p, states['s10c'].T,V['s10c'])
        elif cfg['shock_over_model'] and not cfg['conehead']:
            new_output_line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10}"\
            .format(area_ratio, states['s8'].p, states['s8'].T,V['s8'],\
                    M['s8'], states['s10f'].p, states['s10f'].T,V['s10f'],
                    states['s10e'].p, states['s10e'].T,V['s10e'])
        elif cfg['shock_over_model'] and cfg['conehead'] and cfg['conehead_completed']:
            new_output_line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12},{13}"\
            .format(area_ratio, states['s8'].p, states['s8'].T,V['s8'],\
                    M['s8'], states['s10c'].p, states['s10c'].T,V['s10c'],
                    states['s10f'].p, states['s10f'].T,V['s10f'],
                    states['s10e'].p, states['s10e'].T,V['s10e'])            
        elif not cfg['shock_over_model'] and not cfg['conehead']:
            new_output_line = "{0},{1},{2},{3},{4}"\
            .format(area_ratio, states['s8'].p, states['s8'].T,V['s8'], M['s8'])
        area_ratio_output.write(new_output_line + '\n')
    
    # close the output file
    area_ratio_output.close()        
    
    #return the original area ratio and values when we leave
    print 60*"-"
    print "Now returning original area ratio and values..."
    cfg['area_ratio'] = old_area_ratio
    # run the nozzle expansion
    cfg, states, V, M = nozzle_expansion(cfg, states, V, M)
    if cfg['conehead']: #do the conehead calculation if required
        cfg, states, V, M = conehead_calculation(cfg, states, V, M)
    if cfg['shock_over_model']: #do the shock over model calc if required
        cfg, states, V, M = shock_over_model_calculation(cfg, states, V, M)
       
    return cfg, states, V, M