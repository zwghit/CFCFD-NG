#! /usr/bin/env python 
# generate-initial-contour.py
#
# This script generates a file that contains x- and y-coordinates
# of the initial (pre-optimised) contour of the nozzle. This file
# is generated from the given Bezier control points.
#
# Wilson Chan, 30 Nov 2013.
# ------------------------------------------------------------------

from math import *

def eval_Bezier(bezCtrlPts, t):
    """
    Return the x- and y-coordinates of point t (0 < t < 1) on
    the Bezier curve generated by the input control points .
    """
    n = len(bezCtrlPts) - 1
    blendingFunc = []
    # Generate blending functions.
    for i in range(len(bezCtrlPts)):
        blendingFunc.append((factorial(n) /(factorial(i)*factorial(n-i))) *\
            pow(t,i) * pow((1-t),(n-i)))
    # Get x and y coordinates.
    x = 0.0; y = 0.0
    for i in range(len(bezCtrlPts)):
        x += blendingFunc[i] * bezCtrlPts[i][0]
        y += blendingFunc[i] * bezCtrlPts[i][1]
    return x, y


# ------------------------------------------------------------------

nPtsOnCurve = 1000  # Number of points on curve generated by the Bezier points

fo = open("contour-t4-m4.initial.data", "w")

# Read in initial Bezier control points
controlPts = []
fi = open("../Bezier-control-pts-t4-m4.initial.data", "r")
fi.readline()
while True:
    buf = fi.readline().strip()
    if len(buf) == 0: break
    buf_temp = buf.split()
    if buf_temp[0] == "#": continue
    tokens = [float(word) for word in buf.split()]
    controlPts.append([tokens[0], tokens[1]])
fi.close()

# Generate data points for the Bezier curve
for n in range(nPtsOnCurve+1):
    t = float(n)/float(nPtsOnCurve)
    x, y = eval_Bezier(controlPts, t)
    fo.write("%.6e %.6e\n" % (x, y))
fo.write("\n")
fo.close()
