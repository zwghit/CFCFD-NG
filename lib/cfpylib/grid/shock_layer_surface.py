"""
shock_layer_surface.py: A class for generating a 2D surface between two
                        curves ensuring that the cells adjacent to the 
                        east curve are normal to the surface.

Author: DFP

Version: 30-Oct-2012 : initial repository version, ported from my local version.
         19-Dec-2012 : addition of parametric surface function
"""

import sys
from math import *
# Assume that this module is only used in the context of Eilmer3,
# maybe in preparing a mesh for simulation. (PJ, 11-Mar-2013)
# Importing from libgeom2 seems to play havoc with the class 
# namespaces when we later want to test for types.
from libprep3 import Vector3, Arc, Node, Spline, Line, vabs
from cfpylib.nm.zero_solvers import bisection
from cfpylib.gasdyn.billig import *
from cfpylib.util.YvX import *
try:
    import matplotlib.pyplot as plt
except:
    # print "Could not import matplotlib - plotting disabled."
    with_mpl = False
else:
    with_mpl = True
try:
    from scipy.optimize import *
except:
    # print "Could not import scipy - shock fitting disabled."
    with_scipy = False
else:
    import scipy
    v = scipy.version.version[:-2]
    first_dot = False
    v_short = ''
    for tk in v:
        if tk==".": 
            if not first_dot:
                first_dot = True
            else: break
        v_short += tk
    if float(v_short)<0.1:
        print "WARNING: difficulties with the optimisation routines may be experienced with scipy versions less than 0.10.0"
    with_scipy = True
try:
    from numpy import *
except:
    # print "Could not import numpy - shock fitting disabled."
    with_numpy = False
else:
    with_numpy = True

class ShockLayerSurface:
    def __init__(self, east, west):
	self.east = east
	self.west = west

    def eval(self, r, s):
    	# eval the location on the east face
    	ep = self.east.eval(s)
    	# eval normal angle on the east face
    	dpdt = self.east.dpdt(s)
    	if dpdt.x == 0.0:
            theta = 0.0
        else:
      	    theta = -atan(dpdt.y / dpdt.x) + pi / 2.	
    	#  find the west point
    	if s == 0.0: t = 0
        elif s == 1.0: t = 1
    	elif theta != 0.0:
            def f(t):
    	        wp = self.west.eval(t)
    	        L = (wp.y - ep.y) / sin(theta) 
    	        lp = Vector3(ep.x - L * cos(theta), ep.y + L * sin(theta)) 
    	        return wp.x - lp.x
    	    t = bisection(f, 0.0, 1.0)
    	else:
            def f(t):
    	        wp = self.west.eval(t)
    	        L = (ep.x - wp.x) / cos(theta) 
    	        lp = Vector3(ep.x - L * cos(theta), ep.y + L * sin(theta)) 
    	        return wp.y - lp.y
    	    t = bisection(f, 0.0, 1.0)
    	wp = self.west.eval(t)
            # make the normal line
    	line = Line(ep, wp)
    	# eval the point
    	return line.eval(1 - r)

    def str():
        return "ShockLayerSurface"
        
    def clone( self ):
        return ShockLayerSurface( self.east, self.west )

def make_parametric_surface(bx_scale=1.0, by_scale=1.0, M_inf=1.0, R=1.0, axi=0, east=None, shock=None, f_s=1.1):  
    # model geometry
    if not east:
        # assume a quarter circle with radius R
        o = Vector3(0.0, 0.0)
        a = Vector3(-R, 0.0)
        b = Vector3(0.0, R)
        east = Arc(a, b, o)
    # else: the east boundary has been provided

    # inflow boundary
    if shock == None:
        # billig curve
        x_limit = east.eval(1).x
        inflow_nodes = []
        np = 100
        y_top = by_scale * y_from_x(-x_limit / bx_scale, M_inf, theta=0.0, axi=axi, R_nose=R)
        dy = y_top / (np - 1)
        for iy in range(np):
            y = dy * iy
            x = -bx_scale * x_from_y(y / by_scale, M_inf, theta=0.0, axi=axi, R_nose=R)
            inflow_nodes.append(Vector3(x, y))
        inflow = Spline(inflow_nodes)
            
        # find intersection of surface normal with inflow boundary at the top most point
        ep = east.eval(1)
        dpdt = east.dpdt(1)
        gamma = -atan(dpdt.y / dpdt.x) + pi / 2.
        def f(t):
            wp = inflow.eval(t)
            L = (wp.y - ep.y) / sin(gamma) 
            lp = Vector3(ep.x - L * cos(gamma), ep.y + L * sin(gamma)) 
            return wp.x - lp.x
        t = bisection(f, 0.0, 1.0)
        wp = inflow.eval(t)

        # split the inflow spline
        west_nodes = []
        for node in inflow_nodes:
            if node.y < wp.y: west_nodes.append(node)
        west_nodes.append( Node( wp.x, wp.y ) )

        # create the inflow spline
        west = Spline(west_nodes)    
    else:  
        # create inflow nodes by extending the distances between the wall and the shock by some factor f_s
        inflow_nodes = []
        N = 100
        for i in range(N):
            s = float(i) / float(N - 1)
            ep = east.eval(s)
            dpdt = east.dpdt(s)
            gamma = -atan(dpdt.y / dpdt.x) + pi / 2.
            #  find the west point
            if i == 0: t = 0; gamma = 0.0;
            elif i == N-1: t = 1
            else:
                def f(t):
                    wp = shock.eval(t)
                    L = (wp.y - ep.y) / sin(gamma) 
                    lp = Vector3(ep.x - L * cos(gamma), ep.y + L * sin(gamma)) 
                    return wp.x - lp.x
                t = bisection(f, 0.0, 1.0)
            wp = shock.eval(t)
            L = vabs(wp - ep)
            # print "i = %d, L = %e" % (i, L)
            sp = Vector3(ep.x - L * f_s * cos(gamma), ep.y + L * f_s * sin(gamma))
            # apply scale factors
            sp.x *= bx_scale
            sp.y *= by_scale 
            # print "i = %d, s = %f, t = %e, gamma = %e, wp.y = %e, y = %e" % ( i, s, t, gamma, wp.y, sp.y )
            inflow_nodes.append(sp)
        # create the inflow spline
        west = Spline(inflow_nodes)

    return ShockLayerSurface(east, west), west

def extract_shock_coords( sol ):
    # find the shock (S=1) coordinates from an ExistingSolution
    shock_points = []
    shock_y_coords = []
    shock_x_coords = []
    for flow in sol.flow:
        for i in range(flow.ni):
            for j in range(flow.nj):
                for k in range(flow.nk):
                    if flow.data["S"][i][j][k]==1:
                        shock_points.append( Vector3( flow.data["pos.x"][i][j][k], flow.data["pos.y"][i][j][k], flow.data["pos.z"][i][j][k] ) ) 
                        shock_x_coords.append( flow.data["pos.x"][i][j][k] )
                        shock_y_coords.append( flow.data["pos.y"][i][j][k] )
    print "Found %d shock points" % len(shock_points)
    shock_x_coords, shock_y_coords = zip(*sorted(zip(shock_x_coords, shock_y_coords)))
    return shock_x_coords, shock_y_coords

def fit_billig2shock( sol, axi, M_inf, R, body=None, shock_x_coords=None, shock_y_coords=None, weights=None, show_plot=True ):
    # see if the required packages are available
    if not with_numpy or not with_scipy:
        print "Error: numpy and scipy are required for shock fitting"
        sys.exit()
    if not body:
        # assume a quarter circle with radius R
        o = Vector3(0.0, 0.0)
        a = Vector3(-R, 0.0)
        b = Vector3(0.0, R)
        body = Arc(a, b, o)
    if sol!=None:
        shock_x_coords, shock_y_coords = extract_shock_coords( sol )
    # make a best fit to the shock location point cloud
    def shock_x_from_y( p, y ):
        print p
        _bx_scale, _by_scale = p
        x = []
        for _y in y:
            _x = - _bx_scale * x_from_y(_y/_by_scale, M_inf, theta=0.0, axi=axi, R_nose=R)
            x.append( _x )
        result = array(x)
        return result

    def shock_y_from_x( p, x ):
        print p
        _bx_scale, _by_scale = p
        y = []
        for _x in x:
            _y = _by_scale * y_from_x(-_x*_bx_scale, _M_inf, theta=0.0, axi=axi, R_nose=R)
            y.append( _y )
        result = array(y)
        return result

    def residuals( p, x, y ):
        x_dash = shock_x_from_y(p,y)
        x = array(x)
        # NOTE: now applying weights if present
        if weights!=None:
            result = sqrt(sum(weights*(x - x_dash)**2)/len(x))
        else:
            result = sqrt(sum((x - x_dash)**2)/len(x))
        return result
    
    p0 = [ 1.0, 1.0 ]
    plsq = fmin_slsqp(residuals, p0, args=(shock_x_coords, shock_y_coords), bounds=[(1.0e-1,1e1),(1.0e-1,1e1)], fprime=None)
    # p = p0
    p = plsq
    fit_x = []
    fit_y = copy(shock_y_coords)
    fit_y.sort()
    insert(fit_y,0,0.0)
    fit_x = shock_x_from_y(p,fit_y)
    
    # make a plot if requested, and if matplotlib is available
    if show_plot and with_mpl:
        plt.plot(fit_x,fit_y,"b-",label="fit")
        plt.plot(shock_x_coords,shock_y_coords,"g.",label="points")
        plt.grid()
        plt.legend()
        plt.show()  

    # sample along the billig curve to make a spline
    x_limit = body.eval(1).x
    np = 100
    y_top = p[1] * y_from_x(-x_limit/p[0], M_inf, theta=0.0, axi=axi, R_nose=R)
    dy = y_top / ( np - 1 )
    shock_nodes = []
    for iy in range(np):
        y = dy * iy
        x = - p[0] * x_from_y(y/p[1], M_inf, theta=0.0, axi=axi, R_nose=R)
        shock_nodes.append( Node(x,y) )
    shock_spline = Spline( shock_nodes )
    
    # find intersection of surface normal with the shock spline at t=1
    # eval the location on the east face
    ep = body.eval(1)
    # eval normal angle on the east face
    dpdt = body.dpdt(1)
    if dpdt.x == 0.0:
        theta = 0.0
    else:
        theta = -atan(dpdt.y / dpdt.x) + pi / 2.    
    #  find the west point
    if theta != 0.0:
        def f(t):
            wp = shock_spline.eval(t)
            L = (wp.y - ep.y) / sin(theta) 
            lp = Vector3(ep.x - L * cos(theta), ep.y + L * sin(theta)) 
            return wp.x - lp.x
        t = bisection(f, 0.0, 1.0)
    else:
        def f(t):
            wp = shock_spline.eval(t)
            L = (ep.x - wp.x) / cos(theta) 
            lp = Vector3(ep.x - L * cos(theta), ep.y + L * sin(theta)) 
            return wp.y - lp.y
        t = bisection(f, 0.0, 1.0)
    wp = shock_spline.eval(t)
    
    # sample along the billig curve to make a spline
    np = 100
    y_top = wp.y
    dy = y_top / ( np - 1 )
    shock_nodes = []
    for iy in range(np):
        y = dy * iy
        x = - p[0] * x_from_y(y/p[1], M_inf, theta=0.0, axi=axi, R_nose=R)
        shock_nodes.append( Node(x,y) )
    shock_spline = Spline( shock_nodes )
    
    return shock_spline, shock_nodes

def fit_spline2shock( sol, axi, M_inf, R, body=None, shock_x_coords=None, shock_y_coords=None, weights=None, s=0.0, show_plot=True ):
    # see if the required packages are available
    if not with_numpy or not with_scipy:
        print "Error: numpy and scipy are required for shock fitting"
        sys.exit()
    if not body:
        # assume a quarter circle with radius R
        o = Vector3(0.0, 0.0)
        a = Vector3(-R, 0.0)
        b = Vector3(0.0, R)
        body = Arc(a, b, o)
    if sol!=None:
        shock_x_coords, shock_y_coords = extract_shock_coords( sol )
    # make a best fit to the shock location point cloud  
    spline_fit = scipy.interpolate.splrep( shock_x_coords, shock_y_coords, weights, s=s )
    # describe via the lib/geometry2 spline
    shock_nodes = []
    npoints = 1000
    dx = ( shock_x_coords[-1] - shock_x_coords[0] ) / ( npoints - 1 )
    fit_x = []
    fit_y = []
    for i in range(npoints):
        x = shock_x_coords[0] + i * dx
        fit_x.append(x)
    fit_y = scipy.interpolate.splev(array(fit_x),spline_fit)
    for i in range(npoints):
        shock_nodes.append( Vector3( fit_x[i], fit_y[i] ) )
    shock_spline = Spline(shock_nodes)
    
    # make a plot if requested, and if matplotlib is available
    if show_plot and with_mpl:
        plt.plot(array(fit_x),array(fit_y),"b-",label="fit")
        plt.plot(shock_x_coords,shock_y_coords,"g.",label="points")
        plt.grid()
        plt.legend()
        plt.show()  
    
    return shock_spline, shock_nodes
