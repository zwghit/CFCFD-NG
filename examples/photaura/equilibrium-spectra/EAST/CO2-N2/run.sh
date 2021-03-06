#!/bin/bash
# This simple test case demonstrates how to use the 
# EQ_spectra.py program.
# Here we calculate the post-shock equilibrium 
# radiation intensity spectrum from 50 to 1000nm
# for shot 51-26 (see EAST.inp for the experiment 
# conditions).
# NOTE: The CEA program and scipy need to be installed
#       for this example to run.

# 1. Setup the radiation model LUA input file
radmodel.py -i CO2-N2-radiators.py -L rad-model.lua

# 2. Run EQ_spectra.py
EQ_spectra.py --input-file=EAST.py

# The files coefficient_spectra.txt and intensity_spectra.txt
# should now be in the working directory.
