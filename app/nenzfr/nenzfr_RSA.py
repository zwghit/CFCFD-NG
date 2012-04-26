#!/usr/bin/env python
# nenzfr_RSA.py
#
# This script either:
#    1) Builds an approximation to the Response Surface
#    for the freestream properties (w.r.t Vs and pe) using 
#    a number of nenzfr cases generated by 
#    "nenzfr_perturbed.py", 
# or
#    2) Using a nominated RSA file, calculates the 
#    freestream properties for given values of (Vs,pe). 
# 
# Luke Doherty
# School of Mechancial and Mining Engineering
# The University of Queensland

VERSION_STRING = "26-April-2012"

import shlex, subprocess, string
from subprocess import PIPE
import sys, os, gzip
import optparse
#from numpy import array, mean, logical_and, zeros, dot, sqrt, linalg
from numpy import *
import copy
from nenzfr_sensitivity import read_case_summary, read_nenzfr_outfile, \
     read_estcj_outfile
E3BIN = os.path.expandvars("$HOME/e3bin")
sys.path.append(E3BIN)

#---------------------------------------------------------------
  
def run_command(cmdText):
    """
    Run the command as a subprocess.
    """
    print "About to run cmd:", cmdText
    args = shlex.split(cmdText)
    p = subprocess.Popen(args)
    # wait until the subprocess is finished
    stdoutData, stderrData = p.communicate() 
    return

def quote(str):
    """
    Put quotes around a string.
    """
    return '"' + str + '"'

def calculate_RS_coefficients(exitVar, DictOfCases, nozzleData):
    """
    """
    beta = {}
    # Loop through each freestream property
    for var in exitVar:
        F = zeros((len(DictOfCases),1))
        X = zeros((len(DictOfCases),len(DictOfCases)))
        
        # Loop through each perturbation case
        k = 0
        X0 = array(DictOfCases['case00'])
        for case in DictOfCases.keys():
            # Store the value of the exit flow property
            # for the current case
            F[k] = nozzleData[case][var]
            # Using normalised coordinates for (Vs,pe), 
            # calculate the set of Euclidean norms for 
            # the current case with respect to all other
            # cases.
            X_temp = array(DictOfCases[case])/X0 - \
                     array(DictOfCases.values())/X0
            X[k,:] = [sqrt(dot(X_temp[i],X_temp[i])) for i in range(len(X_temp))]
            k += 1
        # Now solve the set of linear equations:
        #     F = X*B
        B = linalg.solve(X,F)
        beta[var] = B
    return beta

def write_RSA_file(beta, exitVar, DictOfCases, FileToWrite):
    """
    """
    fout = open(FileToWrite,'w')
    # Write out title line
    fout.write('{0:>9}'.format('variable'))
    for case in DictOfCases.keys():
        fout.write('{0:>15}'.format(case))
    fout.write('\n')
    # Write out the Vs values for each case
    fout.write('{0:>9}'.format('Vs'))
    for values in DictOfCases.values():
        fout.write('{0:>15.5g}'.format(values[0]))
    fout.write('\n')
    # Write out the pe values for each case
    fout.write('{0:>9}'.format('pe'))
    for values in DictOfCases.values():
        fout.write('{0:>15.5g}'.format(values[1]))
    fout.write('\n')
    # Write out a horizontal line
    for k in range(len(DictOfCases)):
        fout.write('{0:->15}'.format('-'))
    fout.write('{0:->9}'.format('-'))
    fout.write('\n')
    # Now write out the radial basis function coefficients
    # for each freestream property
    for var in exitVar:
        fout.write('{0:>9}'.format(var))
        for b in beta[var]:
            fout.write('{0:>15.7g}'.format(b[0]))
        fout.write('\n')
    fout.close()
    return 0

def read_RSA_file(FileToRead):
    """
    """
    fp = open(FileToRead,'r')
    
    # Get case names
    titles = fp.readline().strip().split(" ")
    titleList = [k for k in titles if k!="" and k!="variable"]
    # Get  Vs value for each case
    values = fp.readline().strip().split(" ")
    caseVs = [float(k) for k in values if k!="" and k!="Vs"]
    # Get pe value for each case
    values = fp.readline().strip().split(" ")
    casePe = [float(k) for k in values if k!="" and k!="pe"]
    # Assemble a Dictionary of Cases
    DictOfCases = {}
    for j in range(len(titleList)):
        DictOfCases[titleList[j]] = [caseVs[j],casePe[j]]
    fp.readline() # This is just a line of "-"
    # Now read the rest of the data and assemble a 
    # dictionary of beta values
    beta = {}
    fileLines = fp.readlines()
    exitVar = []
    for line in fileLines:
        data = line.strip().split(" ")
        values = [k for k in data if k!=""]
        var = values[0]
        exitVar.append(var)
        del values[0]
        beta[var] = [float(values[k]) for k in range(len(values))]
    fp.close()
    return exitVar, DictOfCases, beta

def calculate_freestream(Vs, pe, exitVar, DictOfCases, beta):
    """
    """
    freeStreamValues = {}
    # Loop through each nozzle property
    for var in exitVar:
        # Get the nominal values for (Vs,pe)
        X0 = array(DictOfCases['case00'])
        # Calculate normalised coordinates
        X = array([Vs,pe])/X0
        Xi = array(DictOfCases.values())/X0
        # Calculate Euclidean distance from the current (Vs,pe)
        # values to each of the cases
        Xdiff = X - Xi
        R = [sqrt(dot(Xdiff[i],Xdiff[i])) for i in range(len(Xdiff))]
        # Calculate the nozzle property
        freeStreamValues[var] = sum(R*array(beta[var]))
    return freeStreamValues    

def write_flow_summary(valuesDict,outFileName,exitVar):
    """
    """
    fout = open(outFileName,'w')
    
    # Write title line
    fout.write('{0:>12}{1:>12}'.format('variable','value'))
    fout.write('\n')
    fout.write('{0:->24}'.format('-'))
    fout.write('\n')
    # Loop through each nozzle property 
    for var in exitVar: 
        fout.write('{0:>12}'.format(var))
        fout.write('{0:>12.5g}'.format(valuesDict[var]))
        fout.write('\n')
    fout.close()

def main():
    """
    Examine the command-line options to decide the what to do
    and then either build a Response Surface Approximation or 
    use a nominated RSA and Vs, and pe values to calculate 
    new freestream property values.
    """
    op = optparse.OptionParser(version=VERSION_STRING)

    op.add_option('--create-RSA', dest='createRSA', action='store_true',
                  default=False, 
                  help="create the Response Surface approximation using "
                  "perturbation results generated by 'nenzfr_perturbed.py'.")

    op.add_option('--RSA-file', dest='RSAfile', default='response_surface.dat',
                  help="specify the name of the reponse surface file that "
                  "is to be either created or used/read.")

    op.add_option('--exitStatsfile', dest='exitStatsFileName',
                  default='nozzle-exit.stats',
                  help="file that holds the averaged nozzle-exit "
                       "data and is to be read in for each perturbation "
                       "case [default: %default]")
    op.add_option('--estcjFile', dest='estcjFile', default='nozzle-estcj.dat',
                  help="file that holds the estcj result and is to be read in "
                       "for each perturbation case. [default: %default]")

    
    op.add_option('--Vs', dest='Vs', default=None, type='float',
                  help=("incident shock speed, in m/s. [default: %default]"))
    op.add_option('--pe', dest='pe', default=None, type='float',
                  help=("equilibrium pressure (after shock reflection), in Pa. "
                        "[default: %default]"))
    op.add_option('--exitfile', dest='exitFileName', default='nozzle-exit.dat',
                  help="file for holding the calculated nozzle-exit data "
                       "[default: %default]")

    opt, args = op.parse_args()
        
    # Go ahead with a new calculation.
    # First, make sure that we have the needed parameters.
    bad_input = False
    if not opt.createRSA:
        if opt.Vs is None:
            print "Need to supply a value for Vs."
            bad_input = True    
        if opt.pe is None:
            print "Need to supply a value for pe."
            bad_input = True
    if bad_input:
        return -2
    
    if opt.createRSA: # We want to create a RSA file
        # Read the "perturbation_cases.dat" file
        perturbedVariables, DictOfCases = read_case_summary()
        
        # Load in all the freestream data and the supply temperature
        # and enthalpy
        nozzleData = {}
        for case in DictOfCases.keys():
            nozzleData[case], exitVar = \
                 read_nenzfr_outfile('./'+case+'/'+opt.exitStatsFileName)
            supply = read_estcj_outfile('./'+case+'/'+opt.estcjFile)
            nozzleData[case]['supply_T'] = supply['T']
            nozzleData[case]['supply_h'] = supply['h']
        exitVar.insert(0,'supply_T')
        exitVar.insert(1,'supply_h')
        
        # Calculate the basis function coefficients
        beta = calculate_RS_coefficients(exitVar, DictOfCases, nozzleData)
        # Write out a file summarising the coefficients
        write_RSA_file(beta, exitVar, DictOfCases, opt.RSAfile)
        # TODO: Check the quality of the RSA
    
    else: # Use an RSA file to predict new freestream properties
        # Load in the nominated file
        exitVar, DictOfCases, beta = read_RSA_file(opt.RSAfile)
        
        # Calculate nozzle property values
        freeStreamValues = calculate_freestream(opt.Vs,opt.pe,exitVar,\
                                                DictOfCases,beta)
        # Write an output file
        write_flow_summary(freeStreamValues,opt.exitFileName,exitVar)

    return 0

#---------------------------------------------------------------

if __name__ == '__main__':
    if len(sys.argv) <= 1:
        print "NENZFr Sensitivity:\n Calculate Sensitivity of Shock Tunnel Test Flow Conditions for a varying inputs"
        print "   Version:", VERSION_STRING
        print "   To get some useful hints, invoke the program with option --help."
        sys.exit(0)
    return_flag = main()
    sys.exit(return_flag)
