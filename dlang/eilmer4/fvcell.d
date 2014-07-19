/**
 * fvcell.d
 * Finite-volume cell class for use in the CFD codes.
 *
 * Author: Peter J. and Rowan G.
 * Version: 2014-07-17: initial cut, to explore options.
 */

module fvcell;

import std.conv;
import std.string;
import std.array;
import std.format;
import std.stdio;
import std.math;
import geom;
import gasmodel;
import fvcore;
import flowstate;
import conservedquantities;
import fvvertex;
import fvinterface;
import globalconfig;


class FVCell {
public:
    uint id;  // allows us to work out where, in the block, the cell is
    bool fr_reactions_allowed; // if true, will call chemical_increment (also thermal_increment)
    double dt_chem; // acceptable time step for finite-rate chemistry
    double dt_therm; // acceptable time step for thermal relaxation
    bool in_turbulent_zone; // if true, we will keep the turbulence viscosity
    double base_qdot; // base-level of heat addition to cell, W/m**3
    // Geometry
    Vector3[] pos; // Centre x,y,z-coordinates for time-levels, m,m,m
    double[] volume; // Cell volume for time-levels (per unit depth or radian in 2D), m**3
    double[] areaxy; // (x,y)-plane area for time-levels, m**2
    double iLength; // length in the i-index direction
    double jLength; // length in the j-index direction
    double kLength; // length in the k-index direction
    double L_min;   // minimum length scale for cell
    double distance_to_nearest_wall; // for turbulence model correction.
    double half_cell_width_at_wall;  // ditto
    FVCell cell_at_nearest_wall;   // ditto
    // Connections
    FVInterface[] iface;  // references to defining interfaces of cell
    FVVertex[] vtx;  // references to vertices for quad (2D) and hexahedral (3D) cells
    // Flow
    FlowState fs; // Flow properties
    ConservedQuantities[] U;  // Conserved flow quantities for the update stages.
    ConservedQuantities[] dUdt; // Time derivatives for the update stages.
    ConservedQuantities Q; // source (or production) terms
    // Terms for loose-coupling of radiation.
    double Q_rad_org;
    double f_rad_org;
    double Q_rE_rad; // Rate of energy addition to cell via radiation.
    double Q_rE_rad_save; // Presently, the radiation source term is calculated
                          // at the first update stage.  We need to retain that
                          // value for all of the update stages.
    // Data for computing residuals.
    double rho_at_start_of_step, rE_at_start_of_step;
    // [TODO] implicit variables

    this(in GasModel gm, size_t id_init=0)
    {
	id = id_init;
	pos.length = n_time_levels;
	volume.length = n_time_levels;
	fs = new FlowState(gm, 100.0e3, [300.0,], Vector3(0.0,0.0,0.0));
	foreach(i; 0 .. n_time_levels) {
	    U ~= new ConservedQuantities(gm);
	    dUdt ~= new ConservedQuantities(gm);
	}
	Q = new ConservedQuantities(gm);
    }

    void copy_values_from(in FVCell other, uint type_of_copy)
    {
	switch ( type_of_copy ) {
	case copy_flow_data:
	    fs.copy_values_from(other.fs);
	    Q.copy_values_from(other.Q);
	    foreach(i; 0 .. n_time_levels) {
		U[i].copy_values_from(other.U[i]);
		dUdt[i].copy_values_from(other.dUdt[i]);
	    }
	    break;
	case copy_grid_data:
	    foreach(i; 0 .. n_time_levels) {
		pos[i] = other.pos[i];
		volume[i] = other.volume[i];
		areaxy[i] = other.areaxy[i];
	    }
	    iLength = other.iLength;
	    jLength = other.jLength;
	    kLength = other.kLength;
	    L_min = other.L_min;
	    break;
	case copy_cell_lengths_only:
	    iLength = other.iLength;
	    jLength = other.jLength;
	    kLength = other.kLength;
	    L_min = other.L_min;
	    break;
	case copy_all_data: 
	default:
	    // [TODO] really need to think about what needs to be copied...
	    id = other.id;
	    foreach(i; 0 .. n_time_levels) {
		pos[i] = other.pos[i];
		volume[i] = other.volume[i];
		areaxy[i] = other.areaxy[i];
	    }
	    iLength = other.iLength;
	    jLength = other.jLength;
	    kLength = other.kLength;
	    L_min = other.L_min;
	    fs.copy_values_from(other.fs);
	    Q.copy_values_from(other.Q);
	    foreach(i; 0 .. n_time_levels) {
		U[i].copy_values_from(other.U[i]);
		dUdt[i].copy_values_from(other.dUdt[i]);
	    }
	} // end switch
    }

    void copy_grid_level_to_level(uint from_level, uint to_level)
    {
	pos[to_level] = pos[from_level];
	volume[to_level] = volume[from_level];
	areaxy[to_level] = areaxy[from_level];
	// When working over all cells in a block, the following copies
	// will no doubt do some doubled-up work, but it should be otherwise benign.
	foreach(ref face; iface) {
	    if ( face ) face.copy_grid_level_to_level(from_level, to_level);
	}
	foreach(ref v; vtx) {
	    if ( v ) v.copy_grid_level_to_level(from_level, to_level);
	}
    }

    override string toString()
    {
	char[] repr;
	repr ~= "FVCell(";
	repr ~= "id=" ~ to!string(id);
	repr ~= ", pos=" ~ to!string(pos);
	repr ~= ", volume=" ~ to!string(volume);
	repr ~= ", areaxy=" ~ to!string(areaxy);
	repr ~= ", iLength=" ~ to!string(iLength);
	repr ~= ", jLength=" ~ to!string(jLength);
	repr ~= ", kLength=" ~ to!string(kLength);
	repr ~= ", L_min=" ~ to!string(L_min);
	repr ~= ", dt_chem=" ~ to!string(dt_chem);
	repr ~= ", dt_therm=" ~ to!string(dt_therm);
	repr ~= ", in_turbulent_zone=" ~ to!string(in_turbulent_zone);
	repr ~= ", fr_reactions_allowed=" ~ to!string(fr_reactions_allowed);
	repr ~= ", fs=" ~ to!string(fs);
	repr ~= ", U=" ~ to!string(U);
	repr ~= ", dUdt=" ~ to!string(dUdt);
	repr ~= ")";
	return to!string(repr);
    }

    const bool point_is_inside(in Vector3 p, int dimensions, int gtl)
    // Returns true if the point p is inside or on the cell surface.
    {
	if ( dimensions == 2 ) {
	    // In 2 dimensions,
	    // we split the x,y-plane into half-planes and check which side p is on.
	    double xA = vtx[1].pos[gtl].x; double yA = vtx[1].pos[gtl].y;
	    double xB = vtx[1].pos[gtl].x; double yB = vtx[2].pos[gtl].y;
	    double xC = vtx[3].pos[gtl].x; double yC = vtx[3].pos[gtl].y;
	    double xD = vtx[0].pos[gtl].x; double yD = vtx[0].pos[gtl].y;
	    // Now, check to see if the specified point is on the
	    // left of (or on) each bloundary line AB, BC, CD and DA.
	    if ((p.x - xB) * (yA - yB) >= (p.y - yB) * (xA - xB) &&
		(p.x - xC) * (yB - yC) >= (p.y - yC) * (xB - xC) &&
		(p.x - xD) * (yC - yD) >= (p.y - yD) * (xC - xD) &&
		(p.x - xA) * (yD - yA) >= (p.y - yA) * (xD - xA)) {
		return true;
	    } else {
		return false;
	    }
	} else {
	    // In 3 dimensions,
	    // the test consists of dividing the 6 cell faces into triangular facets
	    // with outwardly-facing normals and then computing the volumes of the
	    // tetrahedra formed by these facets and the sample point p.
	    // If any of the tetrahedra volumes are positive
	    // (i.e. p is on the positive side of a facet) and we assume a convex cell,
	    // it means that the point is outside the cell and we may say so
	    // without further testing.

	    // North
	    if ( tetrahedron_volume(vtx[2].pos[gtl], vtx[3].pos[gtl], vtx[7].pos[gtl], p) > 0.0 ) return false;
	    if ( tetrahedron_volume(vtx[7].pos[gtl], vtx[6].pos[gtl], vtx[2].pos[gtl], p) > 0.0 ) return false;
	    // East
	    if ( tetrahedron_volume(vtx[1].pos[gtl], vtx[2].pos[gtl], vtx[6].pos[gtl], p) > 0.0 ) return false;
	    if ( tetrahedron_volume(vtx[6].pos[gtl], vtx[5].pos[gtl], vtx[1].pos[gtl], p) > 0.0 ) return false;
	    // South
	    if ( tetrahedron_volume(vtx[0].pos[gtl], vtx[1].pos[gtl], vtx[5].pos[gtl], p) > 0.0 ) return false;
	    if ( tetrahedron_volume(vtx[5].pos[gtl], vtx[4].pos[gtl], vtx[0].pos[gtl], p) > 0.0 ) return false;
	    // West
	    if ( tetrahedron_volume(vtx[3].pos[gtl], vtx[0].pos[gtl], vtx[4].pos[gtl], p) > 0.0 ) return false;
	    if ( tetrahedron_volume(vtx[4].pos[gtl], vtx[7].pos[gtl], vtx[3].pos[gtl], p) > 0.0 ) return false;
	    // Bottom
	    if ( tetrahedron_volume(vtx[1].pos[gtl], vtx[0].pos[gtl], vtx[3].pos[gtl], p) > 0.0 ) return false;
	    if ( tetrahedron_volume(vtx[3].pos[gtl], vtx[2].pos[gtl], vtx[1].pos[gtl], p) > 0.0 ) return false;
	    // Top
	    if ( tetrahedron_volume(vtx[4].pos[gtl], vtx[5].pos[gtl], vtx[6].pos[gtl], p) > 0.0 ) return false;
	    if ( tetrahedron_volume(vtx[6].pos[gtl], vtx[7].pos[gtl], vtx[4].pos[gtl], p) > 0.0 ) return false;
	    // If we arrive here, we haven't determined that the point is outside...
	    return true;
	} // end dimensions != 2
    } // end point_is_inside()

    const void copy_values_to_buffer(ref double[] buf, int type_of_copy, int gtl) {
	throw new Error("[TODO] not yet implemented");
    }

    void copy_values_from_buffer(in double buf, int type_of_copy, int gtl) {
	throw new Error("[TODO] not yet implemented");
    }

    void replace_flow_data_with_average(in FVCell[] others) 
    {
	uint n = others.length;
	if (n == 0) throw new Error("Need to average from a nonempty array.");
	FlowState[] fsList;
	// We need to be honest and not to fiddle with the other gas states.
	foreach(other; others) {
	    if ( this is other ) throw new Error("Must not include destination in source list.");
	    fsList ~= cast(FlowState)other.fs;
	}
	fs.copy_average_values_from(fsList, GlobalConfig.gmodel);
	// Accumulate from a clean slate and then divide.
	Q_rE_rad = 0.0;
	foreach(other; others) {
	    Q_rE_rad += other.Q_rE_rad;
	}
	Q_rE_rad /= n;
    }

    void scan_values_from_string(string buffer) 
    {
	auto items = split(buffer);
	auto gm = GlobalConfig.gmodel;
	pos[0].refx = to!double(items.front); items.popFront();
	pos[0].refy = to!double(items.front); items.popFront();
	pos[0].refz = to!double(items.front); items.popFront();
	volume[0] = to!double(items.front); items.popFront();
	fs.gas.rho = to!double(items.front); items.popFront();
	fs.vel.refx = to!double(items.front); items.popFront();
	fs.vel.refy = to!double(items.front); items.popFront();
	fs.vel.refz = to!double(items.front); items.popFront();
	if ( GlobalConfig.MHD ) {
	    fs.B.refx = to!double(items.front); items.popFront();
	    fs.B.refy = to!double(items.front); items.popFront();
	    fs.B.refz = to!double(items.front); items.popFront();
	}
	fs.gas.p = to!double(items.front); items.popFront();
	fs.gas.a = to!double(items.front); items.popFront();
	fs.gas.mu = to!double(items.front); items.popFront();
	foreach(i; 0 .. gm.n_modes) {
	    fs.gas.k[i] = to!double(items.front); items.popFront();
	}
	fs.mu_t = to!double(items.front); items.popFront();
	fs.k_t = to!double(items.front); items.popFront();
	fs.S = to!int(items.front); items.popFront();
	if ( GlobalConfig.radiation ) {
	    Q_rad_org = to!double(items.front); items.popFront();
	    f_rad_org = to!double(items.front); items.popFront();
	    Q_rE_rad = to!double(items.front); items.popFront();
	} else {
	    Q_rad_org = 0.0; f_rad_org = 0.0; Q_rE_rad = 0.0;
	}
	fs.tke = to!double(items.front); items.popFront();
	fs.omega = to!double(items.front); items.popFront();
	foreach(i; 0 .. gm.n_species) {
	    fs.gas.massf[i] = to!double(items.front); items.popFront();
	}
	if ( gm.n_species > 1 ) {
	    dt_chem = to!double(items.front); items.popFront();
	}
	foreach(i; 0 .. gm.n_modes) {
	    fs.gas.e[i] = to!double(items.front); items.popFront();
	    fs.gas.T[i] = to!double(items.front); items.popFront();
	}
	if ( gm.n_modes > 1 ) {
	    dt_therm = to!double(items.front); items.popFront(); 
	}
    }

    const string write_values_to_string() 
    {
	auto writer = appender!string();
	formattedWrite(writer, "%.12e %.12e %.12e %.12e %.12e %.12e %.12e %.12e",
		       pos[0].x, pos[0].y, pos[0].z, volume[0], fs.gas.rho,
		       fs.vel.x, fs.vel.y, fs.vel.z);
	if ( GlobalConfig.MHD ) 
	    formattedWrite(writer, " %.12e %.12e %.12e", fs.B.x, fs.B.y, fs.B.z); 
	formattedWrite(writer, " %.12e %.12e %.12e", fs.gas.p, fs.gas.a, fs.gas.mu);
	auto gm = GlobalConfig.gmodel;
	foreach(i; 0 .. gm.n_modes) formattedWrite(writer, " %.12e", fs.gas.k[i]); 
	formattedWrite(writer, " %.12e %.12e %d", fs.mu_t, fs.k_t, fs.S);
	if ( GlobalConfig.radiation ) 
	    formattedWrite(writer, " %.12e %.12e %.12e", Q_rad_org, f_rad_org, Q_rE_rad); 
	formattedWrite(writer, " %.12e %.12e", fs.tke, fs.omega);
	foreach(i; 0 .. gm.n_species) formattedWrite(writer, " %.12e", fs.gas.massf[i]); 
	if ( gm.n_species > 1 ) formattedWrite(writer, " %.12e", dt_chem); 
	foreach(i; 0 .. gm.n_modes) formattedWrite(writer, " %.12e %.12e", fs.gas.e[i], fs.gas.T[i]); 
	if ( gm.n_modes > 1 ) formattedWrite(writer, " %.12e", dt_therm);
	return writer.data();
    }

    void scan_BGK_from_string(string bufptr) {
	throw new Error("[TODO] not yet implemented");
    }

    const string write_BGK_to_string() {
	throw new Error("[TODO] not yet implemented");
    }

    void encode_conserved(int gtl, int ftl, double omegaz, bool with_k_omega) 
    {
	ConservedQuantities myU = U[ftl];

	myU.mass = fs.gas.rho;
	// X-, Y- and Z-momentum per unit volume.
	myU.momentum.refx = fs.gas.rho * fs.vel.x;
	myU.momentum.refy = fs.gas.rho * fs.vel.y;
	myU.momentum.refz = fs.gas.rho * fs.vel.z;
	// Magnetic field
	myU.B.refx = fs.B.x;
	myU.B.refy = fs.B.y;
	myU.B.refz = fs.B.z;
	// Total Energy / unit volume = density
	// (specific internal energy + kinetic energy/unit mass).
	double e = 0.0; foreach(elem; fs.gas.e) e += elem;
	double ke = 0.5 * (fs.vel.x * fs.vel.x + fs.vel.y * fs.vel.y + fs.vel.z * fs.vel.z);
	if ( with_k_omega ) {
	    myU.tke = fs.gas.rho * fs.tke;
	    myU.omega = fs.gas.rho * fs.omega;
	    myU.total_energy = fs.gas.rho * (e + ke + fs.tke);
	} else {
	    myU.tke = 0.0;
	    myU.omega = fs.gas.rho * 1.0;
	    myU.total_energy = fs.gas.rho * (e + ke);
	}
	if ( GlobalConfig.MHD ) {
	    double me = 0.5 * (fs.B.x * fs.B.x + fs.B.y * fs.B.y + fs.B.z * fs.B.z);
	    myU.total_energy += me;
	}
	// Species densities: mass of species is per unit volume.
	foreach(isp; 0 .. myU.massf.length) {
	    myU.massf[isp] = fs.gas.rho * fs.gas.massf[isp];
	}
	// Individual energies: energy in mode per unit volume
	foreach(imode; 0 .. myU.energies.length) {
	    myU.energies[imode] = fs.gas.rho * fs.gas.e[imode];
	}
    
	if ( omegaz != 0.0 ) {
	    // Rotating frame.
	    // Finally, we adjust the total energy to make rothalpy.
	    // We do this last because the gas models don't know anything
	    // about rotating frames and we don't want to mess their
	    // energy calculations around.
	    double rho = fs.gas.rho;
	    double x = pos[gtl].x;
	    double y = pos[gtl].y;
	    double rsq = x*x + y*y;
	    // The conserved quantity is rothalpy. I = E - (u**2)/2
	    // where rotating frame velocity  u = omegaz * r.
	    myU.total_energy -= rho * 0.5 * omegaz * omegaz * rsq;
	}
    } // end encode_conserved()

    void decode_conserved(int gtl, int ftl, double omegaz, bool with_k_omega) 
    {
	ConservedQuantities myU = U[ftl];
	auto gmodel = GlobalConfig.gmodel;
	double e, ke, dinv, rE, me;
	// Mass / unit volume = Density
	double rho = myU.mass;
	fs.gas.rho = rho; // This is limited to nonnegative and finite values.
	if ( rho <= 0.0 ) {
	    writeln("FVCell.decode_conserved(): Density is below minimum rho= " ,rho);
	    writeln("id= ", id, " x= ", pos[gtl].x, " y= ", pos[gtl].y, " z= ", pos[gtl].z);
	    writeln(fs.gas);
	}
	dinv = 1.0 / rho;
	if ( omegaz != 0.0 ) {
	    // Rotating frame.
	    // The conserved quantity is rothalpy so we need to convert
	    // back to enthalpy to do the rest of the decode.
	    double x = pos[gtl].x;
	    double y = pos[gtl].y;
	    double rsq = x*x + y*y;
	    rE = myU.total_energy + rho * 0.5 * omegaz * omegaz * rsq;
	} else {
	    // Non-rotating frame.
	    rE = myU.total_energy;
	}
	// Velocities from momenta.
	fs.vel.refx = myU.momentum.x * dinv;
	fs.vel.refy = myU.momentum.y * dinv;
	fs.vel.refz = myU.momentum.z * dinv;
	// Magnetic field
	fs.B.refx = myU.B.x;
	fs.B.refy = myU.B.y;
	fs.B.refz = myU.B.z;
	// Specific internal energy from total energy per unit volume.
	ke = 0.5 * (fs.vel.x * fs.vel.x + fs.vel.y * fs.vel.y + fs.vel.z * fs.vel.z);
	if ( GlobalConfig.MHD ) {
	    me = 0.5*(fs.B.x*fs.B.x + fs.B.y*fs.B.y + fs.B.z*fs.B.z);
	} else {
	    me = 0.0;
	}
	if ( with_k_omega ) {
	    fs.tke = myU.tke * dinv;
	    fs.omega = myU.omega * dinv;
	    e = (rE - myU.tke - me) * dinv - ke;
	} else {
	    fs.tke = 0.0;
	    fs.omega = 1.0;
	    e = (rE - me) * dinv - ke;
	}
	foreach(isp; 0 .. gmodel.n_species) fs.gas.massf[isp] = myU.massf[isp] * dinv; 
	if ( gmodel.n_species > 1 ) scale_mass_fractions(fs.gas.massf);
	foreach(imode; 0 .. gmodel.n_modes) fs.gas.e[imode] = myU.energies[imode] * dinv; 
	// We can recompute e[0] from total energy and component
	// modes NOT in translation.
	if ( gmodel.n_modes > 1 ) {
	    double e_tmp = 0.0;
	    foreach(imode; 1 .. gmodel.n_modes) e_tmp += fs.gas.e[imode];
	    fs.gas.e[0] = e - e_tmp;
	} else {
	    fs.gas.e[0] = e;
	}
	// Fill out the other variables: P, T, a, and viscous transport coefficients.
	gmodel.update_thermo_from_rhoe(fs.gas);
	gmodel.update_sound_speed(fs.gas);
	if ( GlobalConfig.viscous ) gmodel.update_trans_coeffs(fs.gas);
	// if ( GlobalConfig.diffusion ) gmodel.update_diff_coeffs(fs.gas);
    } // end decode_conserved()

    bool check_flow_data() 
    {
	bool is_data_valid = fs.gas.check_values(true);
	const double MAXVEL = 30000.0;
	if (fabs(fs.vel.x) > MAXVEL || fabs(fs.vel.y) > MAXVEL || fabs(fs.vel.z) > MAXVEL) {
	    writeln("Velocity bad ", fs.vel.x, " ", fs.vel.y, " ", fs.vel.z);
	    is_data_valid = false;
	}
	if ( !isFinite(fs.tke) ) {
	    writeln("Turbulence KE invalid number ", fs.tke);
	    is_data_valid = false;
	}
	if ( fs.tke < 0.0 ) {
	    writeln("Turbulence KE negative ", fs.tke);
	    is_data_valid = false;
	}
	if ( !isFinite(fs.omega) ) {
	    writeln("Turbulence frequency invalid number ", fs.omega);
	    is_data_valid = false;
	}
	if ( fs.omega <= 0.0 ) {
	    writeln("Turbulence frequency nonpositive ", fs.omega);
	    is_data_valid = false;
	}
	if ( !is_data_valid ) {
	    writeln("cell pos=", pos[0]);
	    writeln(fs);
	    writeln("----------------------------------------------------------");
	}
	return is_data_valid;
    } // end check_flow_data()

    void time_derivatives(int gtl, int ftl, int dimensions, bool with_k_omega) 
    // These are the spatial (RHS) terms in the semi-discrete governing equations.
    // gtl : (grid-time-level) flow derivatives are evaluated at this grid level
    // ftl : (flow-time-level) specifies where computed derivatives are to be stored.
    //       0: Start of stage-1 update.
    //       1: End of stage-1.
    //       2: End of stage-2.
    // dimensions : number of space dimensions (2 or 3)
    {
	FVInterface IFn = iface[north];
	FVInterface IFe = iface[east];
	FVInterface IFs = iface[south];
	FVInterface IFw = iface[west];
	FVInterface IFt = iface[top];
	FVInterface IFb = iface[bottom];
	// Cell volume (inverted).
	double vol_inv = 1.0 / volume[gtl];
	double integral;
    
	// Time-derivative for Mass/unit volume.
	// Note that the unit normals for the interfaces are oriented
	// such that the unit normals for the east, north and top faces
	// are outward and the unit normals for the south, west and
	// bottom faces are inward.
	integral = -IFe.F.mass * IFe.area[gtl] - IFn.F.mass * IFn.area[gtl]
	    + IFw.F.mass * IFw.area[gtl] + IFs.F.mass * IFs.area[gtl];
	if ( dimensions == 3 )
	    integral += IFb.F.mass * IFb.area[gtl] - IFt.F.mass * IFt.area[gtl];
	dUdt[ftl].mass = vol_inv * integral + Q.mass;

	// Time-derivative for X-Momentum/unit volume.
	integral = -IFe.F.momentum.x * IFe.area[gtl] - IFn.F.momentum.x * IFn.area[gtl]
	    + IFw.F.momentum.x * IFw.area[gtl] + IFs.F.momentum.x * IFs.area[gtl];
	if ( dimensions == 3 )
	    integral += IFb.F.momentum.x * IFb.area[gtl] - IFt.F.momentum.x * IFt.area[gtl];
	dUdt[ftl].momentum.refx = vol_inv * integral + Q.momentum.x;
	// Time-derivative for Y-Momentum/unit volume.
	integral = -IFe.F.momentum.y * IFe.area[gtl] - IFn.F.momentum.y * IFn.area[gtl]
	    + IFw.F.momentum.y * IFw.area[gtl] + IFs.F.momentum.y * IFs.area[gtl];
	if ( dimensions == 3 )
	    integral += IFb.F.momentum.y * IFb.area[gtl] - IFt.F.momentum.y * IFt.area[gtl];
	dUdt[ftl].momentum.refy = vol_inv * integral + Q.momentum.y;
    
	// we require the z-momentum for MHD even in 2D
	if ((dimensions == 3) || ( GlobalConfig.MHD )) {
	    // Time-derivative for Z-Momentum/unit volume.
	    integral = -IFe.F.momentum.z * IFe.area[gtl] - IFn.F.momentum.z * IFn.area[gtl]
		+ IFw.F.momentum.z * IFw.area[gtl] + IFs.F.momentum.z * IFs.area[gtl];
	}
	if ( dimensions == 3) {
	    integral += IFb.F.momentum.z * IFb.area[gtl] - IFt.F.momentum.z * IFt.area[gtl];
	}
	if ((dimensions == 3) || ( GlobalConfig.MHD )) {
	    dUdt[ftl].momentum.refz = vol_inv * integral + Q.momentum.z;
	} else {
	    dUdt[ftl].momentum.refz = 0.0;
	}
    
	if ( GlobalConfig.MHD ) {
	    // Time-derivative for X-Magnetic Field/unit volume.
	    integral = -IFe.F.B.x * IFe.area[gtl] - IFn.F.B.x * IFn.area[gtl]
		+ IFw.F.B.x * IFw.area[gtl] + IFs.F.B.x * IFs.area[gtl];
	    if ( dimensions == 3 )
		integral += IFb.F.B.x * IFb.area[gtl] - IFt.F.B.x * IFt.area[gtl];
	    dUdt[ftl].B.refx = vol_inv * integral + Q.B.x;
	    // Time-derivative for Y-Magnetic Field/unit volume.
	    integral = -IFe.F.B.y * IFe.area[gtl] - IFn.F.B.y * IFn.area[gtl]
		+ IFw.F.B.y * IFw.area[gtl] + IFs.F.B.y * IFs.area[gtl];
	    if ( dimensions == 3 )
		integral += IFb.F.B.y * IFb.area[gtl] - IFt.F.B.y * IFt.area[gtl];
	    dUdt[ftl].B.refy = vol_inv * integral + Q.B.y;
	    // Time-derivative for Z-Magnetic Field/unit volume.
	    integral = -IFe.F.B.z * IFe.area[gtl] - IFn.F.B.z * IFn.area[gtl]
		+ IFw.F.B.z * IFw.area[gtl] + IFs.F.B.z * IFs.area[gtl];
	    if ( dimensions == 3 ) {
		integral += IFb.F.B.z * IFb.area[gtl] - IFt.F.B.z * IFt.area[gtl];
	    }
	    dUdt[ftl].B.refz = vol_inv * integral + Q.B.z;
	}
	else {
	    dUdt[ftl].B.refx = 0.0;
	    dUdt[ftl].B.refy = 0.0;
	    dUdt[ftl].B.refz = 0.0;
	}

	// Time-derivative for Total Energy/unit volume.
	integral = -IFe.F.total_energy * IFe.area[gtl] - IFn.F.total_energy * IFn.area[gtl]
	    + IFw.F.total_energy * IFw.area[gtl] + IFs.F.total_energy * IFs.area[gtl];
	if ( dimensions == 3 )
	    integral += IFb.F.total_energy * IFb.area[gtl] - IFt.F.total_energy * IFt.area[gtl];
	dUdt[ftl].total_energy = vol_inv * integral + Q.total_energy;
    
	if ( with_k_omega ) {
	    integral = -IFe.F.tke * IFe.area[gtl] - IFn.F.tke * IFn.area[gtl]
		+ IFw.F.tke * IFw.area[gtl] + IFs.F.tke * IFs.area[gtl];
	    if ( dimensions == 3 )
		integral += IFb.F.tke * IFb.area[gtl] - IFt.F.tke * IFt.area[gtl];
	    dUdt[ftl].tke = vol_inv * integral + Q.tke;
	
	    integral = -IFe.F.omega * IFe.area[gtl] - IFn.F.omega * IFn.area[gtl]
		+ IFw.F.omega * IFw.area[gtl] + IFs.F.omega * IFs.area[gtl];
	    if ( dimensions == 3 )
		integral += IFb.F.omega * IFb.area[gtl] - IFt.F.omega * IFt.area[gtl];
	    dUdt[ftl].omega = vol_inv * integral + Q.omega;
	} else {
	    dUdt[ftl].tke = 0.0;
	    dUdt[ftl].omega = 0.0;
	}
	// Time-derivative for individual species.
	// The conserved quantity is the mass per unit
	// volume of species isp and
	// the fluxes are mass/unit-time/unit-area.
	// Units of DmassfDt are 1/sec.
	foreach(isp; 0 .. GlobalConfig.gmodel.n_species) {
	    integral =
		-IFe.F.massf[isp] * IFe.area[gtl]
		- IFn.F.massf[isp] * IFn.area[gtl]
		+ IFw.F.massf[isp] * IFw.area[gtl]
		+ IFs.F.massf[isp] * IFs.area[gtl];
	    if ( dimensions == 3 )
		integral += IFb.F.massf[isp] * IFb.area[gtl] - IFt.F.massf[isp] * IFt.area[gtl];
	    dUdt[ftl].massf[isp] = vol_inv * integral + Q.massf[isp];
	}
	// Individual energies.
	// We will not put anything meaningful in imode = 0 (RJG & DFP : 22-Apr-2013)
	// Instead we get this from the conservation of total energy
	foreach(imode; 1 .. GlobalConfig.gmodel.n_modes) {
	    integral =
		-IFe.F.energies[imode] * IFe.area[gtl]
		- IFn.F.energies[imode] * IFn.area[gtl]
		+ IFw.F.energies[imode] * IFw.area[gtl]
		+ IFs.F.energies[imode] * IFs.area[gtl];
	    if ( dimensions == 3 )
		integral += IFb.F.energies[imode] * IFb.area[gtl] - IFt.F.energies[imode] * IFt.area[gtl];
	    dUdt[ftl].energies[imode] = vol_inv * integral + Q.energies[imode];
	}
    } // end time_derivatives()

    void stage_1_update_for_flow_on_fixed_grid(double dt, bool force_euler, bool with_k_omega) 
    {
	ConservedQuantities dUdt0 = dUdt[0];
	ConservedQuantities U0 = U[0];
	ConservedQuantities U1 = U[1];
	double gamma_1 = 1.0; // for normal Predictor-Corrector or Euler update.
	// In some parts of the code (viscous updates, k-omega updates)
	// we use this function as an Euler update even when the main
	// gasdynamic_update_scheme is of higher order.
	if ( !force_euler ) {
	    switch ( gasdynamic_update_scheme ) {
	    case euler_update:
	    case pc_update: gamma_1 = 1.0; break;
	    case midpoint_update: gamma_1 = 0.5; break;
	    case classic_rk3_update: gamma_1 = 0.5; break;
	    case tvd_rk3_update: gamma_1 = 1.0; break;
	    case denman_rk3_update: gamma_1 = 8.0/15.0; break;
	    default:
		throw new Error("FV_Cell.stage_1_update_for_flow_on_fixed_grid(): invalid update scheme.");
	    }
	}
	U1.mass = U0.mass + dt * gamma_1 * dUdt0.mass;
	// Side note: 
	// It would be convenient (codewise) for the updates of these Vector3 quantities to
	// be done with the Vector3 arithmetic operators but I suspect that the implementation
	// of those oerators is such that a whole lot of Vector3 temporaries would be created.
	U1.momentum.refx = U0.momentum.x + dt * gamma_1 * dUdt0.momentum.x;
	U1.momentum.refy = U0.momentum.y + dt * gamma_1 * dUdt0.momentum.y;
	U1.momentum.refz = U0.momentum.z + dt * gamma_1 * dUdt0.momentum.z;
	if ( GlobalConfig.MHD ) {
	    // Magnetic field
	    U1.B.refx = U0.B.x + dt * gamma_1 * dUdt0.B.x;
	    U1.B.refy = U0.B.y + dt * gamma_1 * dUdt0.B.y;
	    U1.B.refz = U0.B.z + dt * gamma_1 * dUdt0.B.z;
	}
	U1.total_energy = U0.total_energy + dt * gamma_1 * dUdt0.total_energy;
	if ( with_k_omega ) {
	    U1.tke = U0.tke + dt * gamma_1 * dUdt0.tke;
	    U1.tke = fmax(U1.tke, 0.0);
	    U1.omega = U0.omega + dt * gamma_1 * dUdt0.omega;
	    U1.omega = fmax(U1.omega, U0.mass);
	    // ...assuming a minimum value of 1.0 for omega
	    // It may occur (near steps in the wall) that a large flux of romega
	    // through one of the cell interfaces causes romega within the cell
	    // to drop rapidly.
	    // The large values of omega come from Menter's near-wall correction that may be
	    // applied outside the control of this finite-volume core code.
	    // These large values of omega will be convected along the wall and,
	    // if they are convected past a corner with a strong expansion,
	    // there will be an unreasonably-large flux out of the cell.
	} else {
	    U1.tke = U0.tke;
	    U1.omega = U0.omega;
	}
	foreach(isp; 0 .. U1.massf.length) {
	    U1.massf[isp] = U0.massf[isp] + dt * gamma_1 * dUdt0.massf[isp];
	}
	// We will not put anything meaningful in imode = 0 (RJG & DFP : 22-Apr-2013)
	// Instead we get this from the conservation of total energy
	foreach(imode; 1 .. U1.energies.length) {
	    U1.energies[imode] = U0.energies[imode] + dt * gamma_1 * dUdt0.energies[imode];
	}
    } // end stage_1_update_for_flow_on_fixed_grid()

    void stage_2_update_for_flow_on_fixed_grid(double dt, bool with_k_omega) 
    {
	ConservedQuantities dUdt0 = dUdt[0];
	ConservedQuantities dUdt1 = dUdt[1];
	ConservedQuantities U_old = U[0];
	if ( gasdynamic_update_scheme == denman_rk3_update ) U_old = U[1];
	ConservedQuantities U2 = U[2];
	double gamma_1 = 0.5; // Presume predictor-corrector.
	double gamma_2 = 0.5;
	switch ( gasdynamic_update_scheme ) {
	case pc_update: gamma_1 = 0.5, gamma_2 = 0.5; break;
	case midpoint_update: gamma_1 = 0.0; gamma_2 = 1.0; break;
	case classic_rk3_update: gamma_1 = -1.0; gamma_2 = 2.0; break;
	case tvd_rk3_update: gamma_1 = 0.25; gamma_2 = 0.25; break;
	case denman_rk3_update: gamma_1 = -17.0/60.0; gamma_2 = 5.0/12.0; break;
	default:
	    throw new Error("FV_Cell.stage_2_update_for_flow_on_fixed_grid(): invalid update scheme.");
	}
	U2.mass = U_old.mass + dt * (gamma_1 * dUdt0.mass + gamma_2 * dUdt1.mass);
	U2.momentum.refx = U_old.momentum.x + dt * (gamma_1 * dUdt0.momentum.x + gamma_2 * dUdt1.momentum.x);
	U2.momentum.refy = U_old.momentum.y + dt * (gamma_1 * dUdt0.momentum.y + gamma_2 * dUdt1.momentum.y);
	U2.momentum.refz = U_old.momentum.z + dt * (gamma_1 * dUdt0.momentum.z + gamma_2 * dUdt1.momentum.z);
	if ( GlobalConfig.MHD ) {
	    // Magnetic field
	    U2.B.refx = U_old.B.x + dt * (gamma_1 * dUdt0.B.x + gamma_2 * dUdt1.B.x);
	    U2.B.refy = U_old.B.y + dt * (gamma_1 * dUdt0.B.y + gamma_2 * dUdt1.B.y);
	    U2.B.refz = U_old.B.z + dt * (gamma_1 * dUdt0.B.z + gamma_2 * dUdt1.B.z);
	}
	U2.total_energy = U_old.total_energy + 
	    dt * (gamma_1 * dUdt0.total_energy + gamma_2 * dUdt1.total_energy);
	if ( with_k_omega ) {
	    U2.tke = U_old.tke + dt * (gamma_1 * dUdt0.tke + gamma_2 * dUdt1.tke);
	    U2.tke = fmax(U2.tke, 0.0);
	    U2.omega = U_old.omega + dt * (gamma_1 * dUdt0.omega + gamma_2 * dUdt1.omega);
	    U2.omega = fmax(U2.omega, U_old.mass);
	} else {
	    U2.tke = U_old.tke;
	    U2.omega = U_old.omega;
	}
	foreach(isp; 0 .. U2.massf.length) {
	    U2.massf[isp] = U_old.massf[isp] + dt * (gamma_1 * dUdt0.massf[isp] + gamma_2 * dUdt1.massf[isp]);
	}
	// We will not put anything meaningful in imode = 0 (RJG & DFP : 22-Apr-2013)
	// Instead we get this from the conservation of total energy
	foreach(imode; 1 .. U2.energies.length) {
	    U2.energies[imode] = U_old.energies[imode] + 
		dt * (gamma_1 * dUdt0.energies[imode] + gamma_2 * dUdt1.energies[imode]);
	}
    } // end stage_2_update_for_flow_on_fixed_grid()

    void stage_3_update_for_flow_on_fixed_grid(double dt, bool with_k_omega) 
    {
	ConservedQuantities dUdt0 = dUdt[0];
	ConservedQuantities dUdt1 = dUdt[1];
	ConservedQuantities dUdt2 = dUdt[2];
	ConservedQuantities U_old = U[0];
	if ( gasdynamic_update_scheme == denman_rk3_update ) U_old = U[2];
	ConservedQuantities U3 = U[3];
	double gamma_1 = 1.0/6.0; // presume TVD_RK3 scheme.
	double gamma_2 = 1.0/6.0;
	double gamma_3 = 4.0/6.0;
	switch ( gasdynamic_update_scheme ) {
	case classic_rk3_update: gamma_1 = 1.0/6.0; gamma_2 = 4.0/6.0; gamma_3 = 1.0/6.0; break;
	case tvd_rk3_update: gamma_1 = 1.0/6.0; gamma_2 = 1.0/6.0; gamma_3 = 4.0/6.0; break;
	    // FIX-ME: Really don't think that we have Andrew Denman's scheme ported correctly.
	case denman_rk3_update: gamma_1 = 0.0; gamma_2 = -5.0/12.0; gamma_3 = 3.0/4.0; break;
	default:
	    throw new Error("FV_Cell::stage_3_update_for_flow_on_fixed_grid(): invalid update scheme.");
	}
	U3.mass = U_old.mass + dt * (gamma_1*dUdt0.mass + gamma_2*dUdt1.mass + gamma_3*dUdt2.mass);
	U3.momentum.refx = U_old.momentum.x +
	    dt * (gamma_1*dUdt0.momentum.x + gamma_2*dUdt1.momentum.x + gamma_3*dUdt2.momentum.x);
	U3.momentum.refy = U_old.momentum.y +
	    dt * (gamma_1*dUdt0.momentum.y + gamma_2*dUdt1.momentum.y + gamma_3*dUdt2.momentum.y);
	U3.momentum.refz = U_old.momentum.z + 
	    dt * (gamma_1*dUdt0.momentum.z + gamma_2*dUdt1.momentum.z + gamma_3*dUdt2.momentum.z);
	if ( GlobalConfig.MHD ) {
	    // Magnetic field
	    U3.B.refx = U_old.B.x + dt * (gamma_1*dUdt0.B.x + gamma_2*dUdt1.B.x + gamma_3*dUdt2.B.x);
	    U3.B.refy = U_old.B.y + dt * (gamma_1*dUdt0.B.y + gamma_2*dUdt1.B.y + gamma_3*dUdt2.B.y);
	    U3.B.refz = U_old.B.z + dt * (gamma_1*dUdt0.B.z + gamma_2*dUdt1.B.z + gamma_3*dUdt2.B.z);
	}
	U3.total_energy = U_old.total_energy + 
	    dt * (gamma_1*dUdt0.total_energy + gamma_2*dUdt1.total_energy + gamma_3*dUdt2.total_energy);
	if ( with_k_omega ) {
	    U3.tke = U_old.tke + dt * (gamma_1*dUdt0.tke + gamma_2*dUdt1.tke + gamma_3*dUdt2.tke);
	    U3.tke = fmax(U3.tke, 0.0);
	    U3.omega = U_old.omega + dt * (gamma_1*dUdt0.omega + gamma_2*dUdt1.omega + gamma_3*dUdt2.omega);
	    U3.omega = fmax(U3.omega, U_old.mass);
	} else {
	    U3.tke = U_old.tke;
	    U3.omega = U_old.omega;
	}
	foreach(isp; 0 .. U3.massf.length) {
	    U3.massf[isp] = U_old.massf[isp] +
		dt * (gamma_1*dUdt0.massf[isp] + gamma_2*dUdt1.massf[isp] + gamma_3*dUdt2.massf[isp]);
	}
	// We will not put anything meaningful in imode = 0 (RJG & DFP : 22-Apr-2013)
	// Instead we get this from the conservation of total energy
	foreach(imode; 1 .. U3.energies.length) {
	    U3.energies[imode] = U_old.energies[imode] +
		dt * (gamma_1*dUdt0.energies[imode] + gamma_2*dUdt1.energies[imode] +
		      gamma_3*dUdt2.energies[imode]);
	}
    } // end stage_3_update_for_flow_on_fixed_grid()

    void stage_1_update_for_flow_on_moving_grid(double dt, bool with_k_omega) 
    {
	throw new Error("[TODO] not yet ready for use");
	ConservedQuantities dUdt0 = dUdt[0];
	ConservedQuantities U0 = U[0];
	ConservedQuantities U1 = U[1];
	double gamma_1 = 1.0;
	double vr = volume[0] / volume[1];

	U1.mass = vr * (U0.mass + dt * gamma_1 * dUdt0.mass);
	U1.momentum.refx = vr * (U0.momentum.x + dt * gamma_1 * dUdt0.momentum.x);
	U1.momentum.refy = vr * (U0.momentum.y + dt * gamma_1 * dUdt0.momentum.y);
	U1.momentum.refz = vr * (U0.momentum.z + dt * gamma_1 * dUdt0.momentum.z);
	if ( GlobalConfig.MHD ) {
	    // Magnetic field
	    U1.B.refx = vr * (U0.B.x + dt * gamma_1 * dUdt0.B.x);
	    U1.B.refy = vr * (U0.B.y + dt * gamma_1 * dUdt0.B.y);
	    U1.B.refz = vr * (U0.B.z + dt * gamma_1 * dUdt0.B.z);
	}
	U1.total_energy = vr * (U0.total_energy + dt * gamma_1 * dUdt0.total_energy);
	if ( with_k_omega ) {
	    U1.tke = vr * (U0.tke + dt * gamma_1 * dUdt0.tke);
	    U1.tke = fmax(U1.tke, 0.0);
	    U1.omega = vr * (U0.omega + dt * gamma_1 * dUdt0.omega);
	    U1.omega = fmax(U1.omega, U0.mass);
	} else {
	    U1.tke = U0.tke;
	    U1.omega = U0.omega;
	}
	foreach(isp; 0 .. U1.massf.length) {
	    U1.massf[isp] = vr * (U0.massf[isp] + dt * gamma_1 * dUdt0.massf[isp]);
	}
	// We will not put anything meaningful in imode = 0 (RJG & DFP : 22-Apr-2013)
	// Instead we get this from the conservation of total energy
	foreach(imode; 1 .. U1.energies.length) {
	    U1.energies[imode] = vr * (U0.energies[imode] + dt * gamma_1 * dUdt0.energies[imode]);
	}
    } // end stage_1_update_for_flow_on_moving_grid()

    void stage_2_update_for_flow_on_moving_grid(double dt, bool with_k_omega) 
    {
	throw new Error("[TODO] not yet ready for use");
	ConservedQuantities dUdt0 = dUdt[0];
	ConservedQuantities dUdt1 = dUdt[1];
	ConservedQuantities U0 = U[0];
	// ConservedQuantities U1 = U[1];
	ConservedQuantities U2 = U[2];
	double gamma_2 = 0.5;
	double gamma_1 = 0.5;
	double v_old = volume[0];
	double vol_inv = 1.0 / volume[2];
	gamma_1 *= volume[0]; gamma_2 *= volume[1]; // Roll-in the volumes for convenience below. 
    
	U2.mass = vol_inv * (v_old * U0.mass + dt * (gamma_1 * dUdt0.mass + gamma_2 * dUdt1.mass));
	U2.momentum.refx = vol_inv * (v_old * U0.momentum.x + 
				      dt * (gamma_1 * dUdt0.momentum.x + gamma_2 * dUdt1.momentum.x));
	U2.momentum.refy = vol_inv * (v_old * U0.momentum.y + 
				      dt * (gamma_1 * dUdt0.momentum.y + gamma_2 * dUdt1.momentum.y));
	U2.momentum.refz = vol_inv * (v_old * U0.momentum.z + 
				      dt * (gamma_1 * dUdt0.momentum.z + gamma_2 * dUdt1.momentum.z));
	if ( GlobalConfig.MHD ) {
	    // Magnetic field
	    U2.B.refx = vol_inv * (v_old * U0.B.x + dt * (gamma_1 * dUdt0.B.x + gamma_2 * dUdt1.B.x));
	    U2.B.refy = vol_inv * (v_old * U0.B.y + dt * (gamma_1 * dUdt0.B.y + gamma_2 * dUdt1.B.y));
	    U2.B.refz = vol_inv * (v_old * U0.B.z + dt * (gamma_1 * dUdt0.B.z + gamma_2 * dUdt1.B.z));
	}
	U2.total_energy = vol_inv * (v_old * U0.total_energy + 
				     dt * (gamma_1 * dUdt0.total_energy + gamma_2 * dUdt1.total_energy));
	if ( with_k_omega ) {
	    U2.tke = vol_inv * (v_old * U0.tke + dt * (gamma_1 * dUdt0.tke + gamma_2 * dUdt1.tke));
	    U2.tke = fmax(U2.tke, 0.0);
	    U2.omega = vol_inv * (v_old * U0.omega + dt * (gamma_1 * dUdt0.omega + gamma_2 * dUdt1.omega));
	    U2.omega = fmax(U2.omega, U0.mass);
	} else {
	    U2.tke = vol_inv * (v_old * U0.tke);
	    U2.omega = vol_inv * (v_old * U0.omega);
	}
	foreach(isp; 0 .. U2.massf.length) {
	    U2.massf[isp] = vol_inv * (v_old * U0.massf[isp] +
				       dt * (gamma_1 * dUdt0.massf[isp] + 
					     gamma_2 * dUdt1.massf[isp]));
	}
	// We will not put anything meaningful in imode = 0 (RJG & DFP : 22-Apr-2013)
	// Instead we get this from the conservation of total energy
	foreach(imode; 1 .. U2.energies.length) {
	    U2.energies[imode] = vol_inv * (v_old * U0.energies[imode] +
					    dt * (gamma_1 * dUdt0.energies[imode] + 
						  gamma_2 * dUdt1.energies[imode]));
	}
    } // end stage_2_update_for_flow_on_moving_grid()

    void chemical_increment(double dt, double T_frozen) 
    // Use the finite-rate chemistry module to update the species fractions
    // and the other thermochemical properties.
    {
	throw new Error("[TODO] not yet ready for use");

	if ( !fr_reactions_allowed || fs.gas.T[0] <= T_frozen ) return;
	auto gmodel = GlobalConfig.gmodel;
	// [TODO] auto rupdate = GlobalConfig.reaction_update_scheme;
	const bool copy_gas_in_case_of_failure = false;
	GasState gcopy;
	if ( copy_gas_in_case_of_failure ) {
	    // Make a copy so that we can print out if things go wrong.
	    gcopy = new GasState(fs.gas);
	}
	double T_save = fs.gas.T[0];
	if ( GlobalConfig.ignition_zone_active ) {
	    // When active, replace gas temperature with an effective ignition temperature
	    foreach(zone; GlobalConfig.ignition_zones) {
		if ( zone.is_inside(pos[0], GlobalConfig.dimensions) ) fs.gas.T[0] = zone._Tig; 
	    }
	}
	try {
	    // [TODO] rupdate.update_state(fs.gas, dt, dt_chem, gmodel);
	    if ( GlobalConfig.ignition_zone_active ) {
		// Restore actual gas temperature
		fs.gas.T[0] = T_save;
	    }
	} catch(Exception err) {
	    writefln("catch %s", err.msg);
	    writeln("The chemical_increment() failed for cell: ", id);
	    if ( copy_gas_in_case_of_failure ) {
		writeln("The gas state before the update was:");
		writefln("gcopy %s", gcopy);
	    }
	    writeln("The gas state after the update was:");
	    writefln("fs.gas %s", fs.gas);
	}

	// The update only changes mass fractions; we need to impose
	// a thermodynamic constraint based on a call to the equation of state.
	gmodel.update_thermo_from_rhoe(fs.gas);

	// If we are doing a viscous sim, we'll need to ensure
	// viscous properties are up-to-date
	if ( GlobalConfig.viscous ) gmodel.update_trans_coeffs(fs.gas);
	// [TODO] if ( GlobalConfig.diffusion ) gmodel.update_diffusion_coeffs(fs.gas);

	// Finally, we have to manually update the conservation quantities
	// for the gas-dynamics time integration.
	// Species densities: mass of species isp per unit volume.
	foreach(isp; 0 .. fs.gas.massf.length)
	    U[0].massf[isp] = fs.gas.rho * fs.gas.massf[isp];
    } // end chemical_increment()

    void thermal_increment(double dt, double T_frozen_energy) 
    // Use the nonequilibrium multi-Temperature module to update the
    // energy values and the other thermochemical properties.
    // We are assuming that this is done after a successful gas-dynamic update
    // and that the current conserved quantities are held in U[0].
    {
	throw new Error("[TODO] not yet ready for use");
	if ( !fr_reactions_allowed || fs.gas.T[0] <= T_frozen_energy ) return;
	auto gmodel = GlobalConfig.gmodel;
	// [TODO] auto eeupdate = GlobalConfig.energy_exchange_update_scheme;

	// [TODO] eeupdate.update_state(fs.gas, dt, dt_therm, gmodel);

	// The update only changes modal energies, we need to impose
	// a thermodynamic constraint based on a call to the equation
	// of state.
	gmodel.update_thermo_from_rhoe(fs.gas);

	// If we are doing a viscous sim, we'll need to ensure
	// viscous properties are up-to-date
	if ( GlobalConfig.viscous ) gmodel.update_trans_coeffs(fs.gas);
	// [TODO] if ( GlobalConfig.diffusion ) gmodel.update_diff_coeffs(fs.gas);

	// Finally, we have to manually update the conservation quantities
	// for the gas-dynamics time integration.
	// Independent energies energy: Joules per unit volume.
	foreach(imode; 0 .. U[0].energies.length) {
	    U[0].energies[imode] = fs.gas.rho * fs.gas.e[imode];
	}
    } // end thermal_increment()

    double signal_frequency(int dimensions, bool with_k_omega) 
    {
	double signal;
	double un_N, un_E, un_T, u_mag;
	double Bn_N = 0.0;
	double Bn_E = 0.0;
	double Bn_T = 0.0;
	double B_mag = 0.0;
	double ca2 = 0.0;
	double cfast = 0.0;
	double gam_eff;
	int statusf;
	auto gmodel = GlobalConfig.gmodel;
	FVInterface north_face = iface[north];
	FVInterface east_face = iface[east];
	FVInterface top_face = iface[top];
	// Get the local normal velocities by rotating the
	// local frame of reference.
	// Also, compute the velocity magnitude and
	// recall the minimum length.
	un_N = fabs(dot(fs.vel, north_face.n));
	un_E = fabs(dot(fs.vel, east_face.n));
	if ( dimensions == 3 ) {
	    un_T = fabs(dot(fs.vel, top_face.n));
	    u_mag = sqrt(fs.vel.x*fs.vel.x + fs.vel.y*fs.vel.y + fs.vel.z*fs.vel.z);
	}  else {
	    un_T = 0.0;
	    u_mag = sqrt(fs.vel.x*fs.vel.x + fs.vel.y*fs.vel.y);
	}
	if ( GlobalConfig.MHD ) {
	    Bn_N = fabs(dot(fs.B, north_face.n));
	    Bn_E = fabs(dot(fs.B, east_face.n));
	    if ( dimensions == 3 ) {
		Bn_T = fabs(dot(fs.B, top_face.n));
	    }
	    u_mag = sqrt(fs.vel.x * fs.vel.x + fs.vel.y * fs.vel.y + fs.vel.z * fs.vel.z);
	    B_mag = sqrt(fs.B.x * fs.B.x + fs.B.y * fs.B.y + fs.B.z * fs.B.z);
	}
	// Check the INVISCID time step limit first,
	// then add a component to ensure viscous stability.
	if ( GlobalConfig.stringent_cfl ) {
	    // Make the worst case.
	    if ( GlobalConfig.MHD ) {
		ca2 = B_mag*B_mag / fs.gas.rho;
		cfast = sqrt( ca2 + fs.gas.a * fs.gas.a );
		signal = (u_mag + cfast) / L_min;
	    } else {
		// Hydrodynamics only
		signal = (u_mag + fs.gas.a) / L_min;
	    }
	} else {
	    // Standard signal speeds along each face.
	    double signalN, signalE, signalT;
	    if ( GlobalConfig.MHD ) {
		double catang2_N, catang2_E, cfast_N, cfast_E;
		ca2 = B_mag * B_mag / fs.gas.rho;
		ca2 = ca2 + fs.gas.a * fs.gas.a;
		catang2_N = Bn_N * Bn_N / fs.gas.rho;
		cfast_N = 0.5 * ( ca2 + sqrt( ca2*ca2 - 4.0 * (fs.gas.a * fs.gas.a * catang2_N) ) );
		cfast_N = sqrt(cfast_N);
		catang2_E = Bn_E * Bn_E / fs.gas.rho;
		cfast_E = 0.5 * ( ca2 + sqrt( ca2*ca2 - 4.0 * (fs.gas.a * fs.gas.a * catang2_E) ) );
		cfast_E = sqrt(cfast_E);
		if ( dimensions == 3 ) {
		    double catang2_T, cfast_T;
		    catang2_T = Bn_T * Bn_T / fs.gas.rho;
		    cfast_T = 0.5 * ( ca2 + sqrt( ca2*ca2 - 4.0 * (fs.gas.a * fs.gas.a * catang2_T) ) );
		    cfast_T = sqrt(cfast_T);
		    signalN = (un_N + cfast_N) / jLength;
		    signal = signalN;
		    signalE = (un_E + cfast_E) / iLength;
		    if ( signalE > signal ) signal = signalE;
		    signalT = (un_T + cfast_T) / kLength;
		    if ( signalT > signal ) signal = signalT;
		} else {
		    signalN = (un_N + cfast) / jLength;
		    signalE = (un_E + cfast) / iLength;
		    signal = fmax(signalN, signalE);
		}
	    } else if ( dimensions == 3 ) {
		// eilmer -- 3D cells
		signalN = (un_N + fs.gas.a) / jLength;
		signal = signalN;
		signalE = (un_E + fs.gas.a) / iLength;
		if ( signalE > signal ) signal = signalE;
		signalT = (un_T + fs.gas.a) / kLength;
		if ( signalT > signal ) signal = signalT;
	    } else {
		// mbcns2 -- 2D cells
		// The velocity normal to the north face is assumed to run
		// along the length of the east face.
		signalN = (un_N + fs.gas.a) / jLength;
		signalE = (un_E + fs.gas.a) / iLength;
		signal = fmax(signalN, signalE);
	    }
	}
	if ( GlobalConfig.viscous && fs.gas.mu > 10.0e-23) {
	    // Factor for the viscous time limit.
	    // This factor is not included if viscosity is zero.
	    // See Swanson, Turkel and White (1991)
	    gam_eff = gmodel.gamma(fs.gas);
	    // Need to sum conductivities for TNE
	    double k_total = 0.0;
	    foreach(i; 0 .. fs.gas.k.length) k_total += fs.gas.k[i];
	    double Prandtl = fs.gas.mu * gmodel.Cp(fs.gas) / k_total;
	    if ( dimensions == 3 ) {
		signal += 4.0 * GlobalConfig.viscous_factor * (fs.gas.mu + fs.mu_t)
		    * gam_eff / (Prandtl * fs.gas.rho)
		    * (1.0/(iLength*iLength) + 1.0/(jLength*jLength) + 1.0/(kLength*kLength));
	    } else {
		signal += 4.0 * GlobalConfig.viscous_factor * (fs.gas.mu + fs.mu_t) 
		    * gam_eff / (Prandtl * fs.gas.rho)
		    * (1.0/(iLength*iLength) + 1.0/(jLength*jLength));
	    }
	}
	if ( with_k_omega == 1 ) {
	    if ( fs.omega > signal ) signal = fs.omega;
	}
	return signal;
    } // end signal_frequency()

    void turbulence_viscosity_zero() 
    {
	fs.mu_t = 0.0;
	fs.k_t = 0.0;
    }

    void turbulence_viscosity_zero_if_not_in_zone() 
    {
	if ( in_turbulent_zone ) {
	    /* Do nothing, leaving the turbulence quantities as set. */ ;
	} else {
	    /* Presume this part of the flow is laminar; clear turbulence quantities. */
	    fs.mu_t = 0.0;
	    fs.k_t = 0.0;
	}
    }

    void turbulence_viscosity_limit(double factor) 
    // Limit the turbulent viscosity to reasonable values relative to
    // the local molecular viscosity.
    // In shock started flows, we seem to get crazy values on the
    // starting shock structure and the simulations do not progress.
    {
	fs.mu_t = fmin(fs.mu_t, factor * fs.gas.mu);
	fs.k_t = fmin(fs.k_t, factor * fs.gas.k[0]); // ASSUMPTION re k[0]
    }

    void turbulence_viscosity_factor(double factor) 
    // Scale the turbulent viscosity to model effects
    // such as not-fully-developed turbulence that might be expected
    // in short-duration transient flows.
    {
	fs.mu_t *= factor;
	fs.k_t *= factor;
    }

    void turbulence_viscosity_k_omega() 
    {
/+
	if ( G.turbulence_model != TM_K_OMEGA ) {
	    // FIX-ME may have to do something better if another turbulence model is active.
	    fs.mu_t = 0.0;
	    fs.k_t = 0.0;
	    return SUCCESS;
	}
	double dudx, dudy, dvdx, dvdy;
	double S_bar_squared;
	double C_lim = 0.875;
	double beta_star = 0.09;
	if ( G.dimensions == 2 ) {
	    // 2D cartesian or 2D axisymmetric
	    dudx = 0.25 * (vtx[0].dudx + vtx[1].dudx + vtx[2].dudx + vtx[3].dudx);
	    dudy = 0.25 * (vtx[0].dudy + vtx[1].dudy + vtx[2].dudy + vtx[3].dudy);
	    dvdx = 0.25 * (vtx[0].dvdx + vtx[1].dvdx + vtx[2].dvdx + vtx[3].dvdx);
	    dvdy = 0.25 * (vtx[0].dvdy + vtx[1].dvdy + vtx[2].dvdy + vtx[3].dvdy);
	    if ( G.axisymmetric ) {
		// 2D axisymmetric
		double v_over_y = fs.vel.y / pos[0].y;
		S_bar_squared = dudx*dudx + dvdy*dvdy + v_over_y*v_over_y
		    - 1.0/3.0 * (dudx + dvdy + v_over_y)
		    * (dudx + dvdy + v_over_y)
		    + 0.5 * (dudy + dvdx) * (dudy + dvdx) ;
	    } else {
		// 2D cartesian
		S_bar_squared = dudx*dudx + dvdy*dvdy
		    - 1.0/3.0 * (dudx + dvdy) * (dudx + dvdy)
		    + 0.5 * (dudy + dvdx) * (dudy + dvdx);
	    }
	} else {
	    // 3D cartesian
	    double dudz, dvdz, dwdx, dwdy, dwdz;
	    dudx = 0.125 * (vtx[0].dudx + vtx[1].dudx + vtx[2].dudx + vtx[3].dudx +
			    vtx[4].dudx + vtx[5].dudx + vtx[6].dudx + vtx[7].dudx);
	    dudy = 0.125 * (vtx[0].dudy + vtx[1].dudy + vtx[2].dudy + vtx[3].dudy +
			    vtx[4].dudy + vtx[5].dudy + vtx[6].dudy + vtx[7].dudy);
	    dudz = 0.125 * (vtx[0].dudz + vtx[1].dudz + vtx[2].dudz + vtx[3].dudz +
			    vtx[4].dudz + vtx[5].dudz + vtx[6].dudz + vtx[7].dudz);
	    dvdx = 0.125 * (vtx[0].dvdx + vtx[1].dvdx + vtx[2].dvdx + vtx[3].dvdx +
			    vtx[4].dvdx + vtx[5].dvdx + vtx[6].dvdx + vtx[7].dvdx);
	    dvdy = 0.125 * (vtx[0].dvdy + vtx[1].dvdy + vtx[2].dvdy + vtx[3].dvdy +
			    vtx[4].dvdy + vtx[5].dvdy + vtx[6].dvdy + vtx[7].dvdy);
	    dvdz = 0.125 * (vtx[0].dvdz + vtx[1].dvdz + vtx[2].dvdz + vtx[3].dvdz +
			    vtx[4].dvdz + vtx[5].dvdz + vtx[6].dvdz + vtx[7].dvdz);
	    dwdx = 0.125 * (vtx[0].dwdx + vtx[1].dwdx + vtx[2].dwdx + vtx[3].dwdx +
			    vtx[4].dwdx + vtx[5].dwdx + vtx[6].dwdx + vtx[7].dwdx);
	    dwdy = 0.125 * (vtx[0].dwdy + vtx[1].dwdy + vtx[2].dwdy + vtx[3].dwdy +
			    vtx[4].dwdy + vtx[5].dwdy + vtx[6].dwdy + vtx[7].dwdy);
	    dwdz = 0.125 * (vtx[0].dwdz + vtx[1].dwdz + vtx[2].dwdz + vtx[3].dwdz +
			    vtx[4].dwdz + vtx[5].dwdz + vtx[6].dwdz + vtx[7].dwdz);
	    // 3D cartesian
	    S_bar_squared =  dudx*dudx + dvdy*dvdy + dwdz*dwdz
		- 1.0/3.0*(dudx + dvdy + dwdz)*(dudx + dvdy + dwdz)
		+ 0.5 * (dudy + dvdx) * (dudy + dvdx)
		+ 0.5 * (dudz + dwdx) * (dudz + dwdx)
		+ 0.5 * (dvdz + dwdy) * (dvdz + dwdy);
	}
	S_bar_squared = max(0.0, S_bar_squared);
	double omega_t = max(fs.omega, C_lim*sqrt(2.0*S_bar_squared/beta_star));
	fs.mu_t = fs.gas.rho * fs.tke / omega_t;
	double Pr_t = G.turbulence_prandtl;
	Gas_model *gmodel = get_gas_model_ptr();
	int status_flag;
	fs.k_t = gmodel.Cp(*(fs.gas), status_flag) * fs.mu_t / Pr_t;
+/
    } // end turbulence_viscosity_k_omega()

    void update_k_omega_properties(double dt) 
    {
	throw new Error("[TODO] not yet implemented");
    }

    void k_omega_time_derivatives(ref double Q_rtke, ref double Q_romega, double tke, double omega) 
    {
	throw new Error("[TODO] not yet implemented");
    }

    void clear_source_vector() 
    {
	throw new Error("[TODO] not yet implemented");
    }

    void add_inviscid_source_vector(int gtl, double omegaz=0.0) 
    {
	throw new Error("[TODO] not yet implemented");
    }

    void add_viscous_source_vector(bool with_k_omega) 
    {
	throw new Error("[TODO] not yet implemented");
    }

    double calculate_wall_Reynolds_number(int which_boundary) 
    {
	throw new Error("[TODO] not yet implemented");
    }

    void store_rad_scaling_params() 
    {
	throw new Error("[TODO] not yet implemented");
    }

    void rescale_Q_rE_rad() 
    {
	throw new Error("[TODO] not yet implemented");
    }

    void reset_Q_rad_to_zero() 
    {
	throw new Error("[TODO] not yet implemented");
    }

    double rad_scaling_ratio() 
    {
	throw new Error("[TODO] not yet implemented");
    }

} // end class FVCell


string[] variable_list_for_cell()
{
    // This function needs to be kept consistent with functions
    // FVCell.write_values_to_string, FVCell.scan_values_from_string
    // (found above) and with the corresponding Python functions
    // write_cell_data and variable_list_for_cell
    // that may be found in app/eilmer3/source/e3_flow.py.
    string[] list;
    list ~= ["pos.x", "pos.y", "pos.z"];
    list ~= ["rho", "vel.x", "vel.y", "vel.z"];
    if ( GlobalConfig.MHD ) list ~= ["B.x", "B.y", "B.z"];
    list ~= ["p", "a", "mu"];
    auto gm = GlobalConfig.gmodel;
    foreach(i; 0 .. gm.n_modes) list ~= "k[" ~ to!string(i) ~ "]";
    list ~= ["mu_t", "k_t", "S"];
    if ( GlobalConfig.radiation ) list ~= ["Q_rad_org", "f_rad_org", "Q_rE_rad"];
    list ~= ["tke", "omega"];
    foreach(i; 0 .. gm.n_species) {
	auto name = cast(char[]) gm.species_name(i);
	name = tr(name, " \t", "--", "s"); // Replace internal whitespace with dashes.
	list ~= ["massf[" ~ to!string(i) ~ "]-" ~ to!string(name)];
    }
    if ( gm.n_species > 1 ) list ~= ["dt_chem"];
    foreach(i; 0 .. gm.n_modes) list ~= ["e[" ~ to!string(i) ~ "]", "T[" ~ to!string(i) ~ "]"];
    if ( gm.n_modes > 1 ) list ~= ["dt_therm"];
    return list;
} // end variable_list_for_cell()
