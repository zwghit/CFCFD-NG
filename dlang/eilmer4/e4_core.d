/** e4_core.d
 * Eilmer4 compressible-flow simulation code, core coordination functions.
 *
 * Author: Peter J. and Rowan G. 
 * First code: 2015-02-05
 */

import std.stdio;
import std.json;
import std.file;
import std.conv;
import std.array;
import std.format;
import std.string;

import json_helper;
import geom;
import gas;
import fvcore;
import globalconfig;
import flowstate;
import sblock;
import bc;
import bc_slip_wall;
import bc_supersonic_in;
import bc_extrapolate_out;
import bc_fixed_p_out;
import bc_fixed_t_wall;
import bc_adiabatic_wall;
import bc_full_face_exchange;
import bc_mapped_cell_exchange;

//-----------------------------------------------------------------------------------------

// Flow condition array for use in boundary conditions.
static FlowState[] flow_state;

// Storage for the actual blocks of flow data.
static SBlock[] blk_data;

void make_flow_state_from_json(JSONValue json_data)
{
    double p = getJSONdouble(json_data, "p", 100.0e3);
    double T[] = getJSONdoublearray(json_data, "T", [300.0,]);
    double u = getJSONdouble(json_data, "u", 0.0);
    double v = getJSONdouble(json_data, "v", 0.0);
    double w = getJSONdouble(json_data, "w", 0.0);
    Vector3 vel = Vector3(u,v,w);
    double[] massf = getJSONdoublearray(json_data, "massf", [1.0,]);
    double quality = 1.0;
    double Bx = getJSONdouble(json_data, "Bx", 0.0);
    double By = getJSONdouble(json_data, "By", 0.0);
    double Bz = getJSONdouble(json_data, "Bz", 0.0);
    Vector3 B = Vector3(Bx,By,Bz);
    double tke = getJSONdouble(json_data, "tke", 0.0);
    double omega = getJSONdouble(json_data, "omega", 1.0);
    double mu_t = getJSONdouble(json_data, "mu_t", 0.0);
    double k_t = getJSONdouble(json_data, "k_t", 0.0);
    int S = getJSONint(json_data, "S", 0);
    flow_state ~= new FlowState(GlobalConfig.gmodel, p, T, vel,  massf,
				quality, B, tke, omega, mu_t, k_t, S);
} // end make_flow_state_from_json()

BoundaryCondition make_BC_from_json(JSONValue json_data, ref SBlock blk, int i)
{
    writeln("    BC for block: ", blk.id, ", face: ", face_name[i]);
    string bc_name = json_data["bc"].str;
    BoundaryCondition new_bc;
    switch (toLower(bc_name)) {
    case "sup_in":
	// TODO // need to pass reference to the condition
	// or put the flow_condition data and block data into globaldata.d
	int inflow_condition_id = 0; 
	new_bc = new SupersonicInBC(blk, i, inflow_condition_id);
	break;
    case "slip_wall":
	new_bc = new SlipWallBC(blk, i);
	break;
    case "extrapolate_out":
	new_bc = new ExtrapolateOutBC(blk, i);
	break;
    case "adjacent":
        // "other_block": -1,
        // "other_face": "none",
        // "neighbour_orientation": 0,
 	new_bc = new FullFaceExchangeBC();
	break;
    default:
	new_bc = new SlipWallBC(blk, i);
    }
    return new_bc;
} // end make_BC_from_json()

void make_Block_from_json(int id, JSONValue json_data)
{
    int nicell = getJSONint(json_data, "nni", 0);
    int njcell = getJSONint(json_data, "nnj", 0);
    int nkcell = getJSONint(json_data, "nnk", 0);
    SBlock blk = new SBlock(id, nicell, njcell, nkcell);
    blk.label = json_data["label"].str;
    blk.active = getJSONbool(json_data, "active", true);
    blk.omegaz = getJSONdouble(json_data, "omegaz", 0.0);
    foreach (i; 0 .. (GlobalConfig.dimensions == 3 ? 6 : 4)) {
	blk.bc[i] = make_BC_from_json(json_data["face_" ~ face_name[i]], blk, i);
    }
    blk_data ~= blk;
} // end make_Block_from_json()

//-----------------------------------------------------------------------------------------

void read_config_file()
{
    if (GlobalConfig.verbosity_level > 1) writeln("Read config file.");
    string fileName = GlobalConfig.base_file_name ~ ".config";
    string content;
    try {
        content = readText(fileName);
    } catch (Exception e) {
	writeln("Failed to read config file: ", fileName);
	exit(1);
    }
    JSONValue jsonData;
    try {
	jsonData = parseJSON!string(content);
    } catch (Exception e) {
	writeln("Failed to parse JSON from config file: ", fileName);
	exit(1);
    }
    // Now that we have parsed JSON data, dip into it to get config values.
    GlobalConfig.title = jsonData["title"].str;
    string gasModelFile = jsonData["gas_model_file"].str;
    GlobalConfig.gmodel = init_gas_model(gasModelFile);
    if (GlobalConfig.verbosity_level > 1) {
	writeln("  title: ", GlobalConfig.title);
	writeln("  gasModelFile: ", gasModelFile);
    }
    GlobalConfig.dimensions = getJSONint(jsonData, "dimensions", 2);
    GlobalConfig.axisymmetric = getJSONbool(jsonData, "axisymmetric_flag", false);
    GlobalConfig.viscous = getJSONbool(jsonData, "viscous_flag", false);
    GlobalConfig.viscous_delay = getJSONdouble(jsonData, "viscous_delay", 0.0);
    GlobalConfig.viscous_factor_increment = 
	getJSONdouble(jsonData, "viscous_factor_increment", 0.01);
    try {
	string name = jsonData["turbulence_model"].str;
	GlobalConfig.turbulence_model = turbulence_model_from_name(name);
    } catch (Exception e) {
	GlobalConfig.turbulence_model = TurbulenceModel.none;
    }
    GlobalConfig.turbulence_prandtl =
	getJSONdouble(jsonData, "turbulence_prandtl_number", 0.89);
    GlobalConfig.turbulence_schmidt =
	getJSONdouble(jsonData, "turbulence_schmidt_number", 0.75);
    GlobalConfig.max_mu_t_factor = getJSONdouble(jsonData, "max_mu_t_factor", 300.0);
    GlobalConfig.transient_mu_t_factor = getJSONdouble(jsonData, "transient_mu_t_factor", 1.0);
    if (GlobalConfig.verbosity_level > 1) {
	writeln("  dimensions: ", GlobalConfig.dimensions);
	writeln("  axisymmetric: ", GlobalConfig.axisymmetric);
	writeln("  viscous: ", GlobalConfig.viscous);
	writeln("  viscous_delay: ", GlobalConfig.viscous_delay);
	writeln("  viscous_factor_increment: ", GlobalConfig.viscous_factor_increment);
	writeln("  turbulence_model: ", turbulence_model_name(GlobalConfig.turbulence_model));
	writeln("  turbulence_prandtl: ", GlobalConfig.turbulence_prandtl);
	writeln("  turbulence_schmidt: ", GlobalConfig.turbulence_schmidt);
	writeln("  max_mu_t_factor: ", GlobalConfig.max_mu_t_factor);
	writeln("  transient_mu_t_factor: ", GlobalConfig.transient_mu_t_factor);
    }
    GlobalConfig.moving_grid = getJSONbool(jsonData, "moving_grid_flag", false);
    GlobalConfig.write_vertex_velocities = 
	getJSONbool(jsonData, "write_vertex_velocities_flag", false);
    GlobalConfig.compression_tolerance = 
	getJSONdouble(jsonData, "compression_tolerance", -0.30);
    try {
	string name = jsonData["interpolation_type"].str;
	GlobalConfig.thermo_interpolator = thermo_interpolator_from_name(name);
    } catch (Exception e) {
	GlobalConfig.thermo_interpolator = InterpolateOption.rhoe;
    }
    GlobalConfig.apply_limiter = getJSONbool(jsonData, "apply_limiter_flag", true);
    GlobalConfig.extrema_clipping = getJSONbool(jsonData, "extreme_clipping_flag", true);
    GlobalConfig.interpolate_in_local_frame = 
	getJSONbool(jsonData, "interpolate_in_local_frame", true);
    try {
	string name = jsonData["flux_calc"].str;
	GlobalConfig.flux_calculator = fluxcalc_from_name(name);
    } catch (Exception e) {
	GlobalConfig.flux_calculator = FluxCalculator.adaptive;
    }
    GlobalConfig.shear_tolerance = getJSONdouble(jsonData, "shear_tolerance", 0.20);
    GlobalConfig.M_inf = getJSONdouble(jsonData, "M_inf", 0.01);
    if (GlobalConfig.verbosity_level > 1) {
	writeln("  moving_grid: ", GlobalConfig.moving_grid);
	writeln("  write_vertex_velocities: ", GlobalConfig.write_vertex_velocities);
	writeln("  compression_tolerance: ", GlobalConfig.compression_tolerance);
	writeln("  thermo_interpolator: ",
		thermo_interpolator_name(GlobalConfig.thermo_interpolator));
	writeln("  apply_limiter: ", GlobalConfig.apply_limiter);
	writeln("  extrema_clipping: ", GlobalConfig.extrema_clipping);
	writeln("  interpolate_in_local_frame: ", GlobalConfig.interpolate_in_local_frame);
	writeln("  flux_calculator: ", fluxcalc_name(GlobalConfig.flux_calculator));
	writeln("  shear_tolerance: ", GlobalConfig.shear_tolerance);
	writeln("  M_inf: ", GlobalConfig.M_inf);
    }
    GlobalConfig.reacting = getJSONbool(jsonData, "reacting_flag", false);
    // TODO GlobalConfig.reaction_update
    if (GlobalConfig.verbosity_level > 1) {
	writeln("  reacting: ", GlobalConfig.reacting);
    }
    GlobalConfig.control_count = getJSONint(jsonData, "control_count", 10);
    GlobalConfig.adjust_invalid_cell_data =
	getJSONbool(jsonData, "adjust_invalid_cell_data", false);
    GlobalConfig.max_invalid_cells = getJSONint(jsonData, "max_invalid_cells", 0);
    if (GlobalConfig.verbosity_level > 1) {
	writeln("  control_count: ", GlobalConfig.control_count);
	writeln("  adjust_invalid_cell_data: ", GlobalConfig.adjust_invalid_cell_data);
	writeln("  max_invalid_cells: ", GlobalConfig.max_invalid_cells);
    }
    // Configure flow conditions, for use in boundary conditions.
    int nflow = getJSONint(jsonData, "nflow", 0);
    foreach (i; 0 .. nflow) {
	make_flow_state_from_json(jsonData["flow_" ~ to!string(i)]);
	if (GlobalConfig.verbosity_level > 1) {
	    writeln("  flow[", i, "]=", flow_state[i]);
	}
    }
    // Now, configure blocks that make up the flow domain.
    GlobalConfig.nBlocks = getJSONint(jsonData, "nblock", 0);
    if (GlobalConfig.verbosity_level > 1) {
	writeln("  nBlocks: ", GlobalConfig.nBlocks);
    }
    foreach (i; 0 .. GlobalConfig.nBlocks) {
	make_Block_from_json(i, jsonData["block_" ~ to!string(i)]);
	if (GlobalConfig.verbosity_level > 1) {
	    writeln("  Block[", i, "]:", blk_data[i]);
	}
    }
    // TODO -- still have other entries such as nheatzone, nreactionzone, ...
} // end read_config_file()


void read_control_file()
{
    if (GlobalConfig.verbosity_level > 1) writeln("read_control_file()");
    string fileName = GlobalConfig.base_file_name ~ ".control";
    string content;
    try {
        content = readText(fileName);
    } catch (Exception e) {
	writeln("Failed to read control file: ", fileName);
	exit(1);
    }
    JSONValue jsonData;
    try {
	jsonData = parseJSON!string(content);
    } catch (Exception e) {
	writeln("Failed to parse JSON from control file: ", fileName);
	exit(1);
    }

    GlobalConfig.Xorder = getJSONint(jsonData, "x_order", 2);
    try {
	string name = jsonData["gasdynamic_update_scheme"].str;
	fvcore.gasdynamic_update_scheme = update_scheme_from_name(name);
    } catch (Exception e) {
	fvcore.gasdynamic_update_scheme = GasdynamicUpdate.pc;
    }
    GlobalConfig.max_step = getJSONint(jsonData, "max_step", 100);
    GlobalConfig.max_time = getJSONdouble(jsonData, "max_time", 1.0e-3);
    GlobalConfig.halt_now = getJSONint(jsonData, "halt_now", 0);
    GlobalConfig.print_count = getJSONint(jsonData, "print_count", 0);
    GlobalConfig.cfl_count = getJSONint(jsonData, "cfl_count", 0);
    GlobalConfig.dt_init = getJSONdouble(jsonData, "dt", 1.0e-6);
    GlobalConfig.dt_max = getJSONdouble(jsonData, "dt_max", 1.0-3);
    GlobalConfig.cfl_value = getJSONdouble(jsonData, "cfl", 0.5);
    GlobalConfig.stringent_cfl = getJSONbool(jsonData, "stringent_cfl", false);
    GlobalConfig.fixed_time_step = getJSONbool(jsonData, "fixed_time_step", false);
    GlobalConfig.dt_reduction_factor = getJSONdouble(jsonData, "dt_reduction_factor", 0.2);
    GlobalConfig.dt_plot = getJSONdouble(jsonData, "dt_plot", 1.0e-3);
    GlobalConfig.dt_history = getJSONdouble(jsonData, "dt_history", 1.0e-3);
    if (GlobalConfig.verbosity_level > 1) {
	writeln("  Xorder: ", GlobalConfig.Xorder);
	writeln("  gasdynamic_update_scheme: ",
		gasdynamic_update_scheme_name(fvcore.gasdynamic_update_scheme));
	writeln("  max_step: ", GlobalConfig.max_step);
	writeln("  max_time: ", GlobalConfig.max_time);
	writeln("  halt_now: ", GlobalConfig.halt_now);
	writeln("  print_count: ", GlobalConfig.print_count);
	writeln("  cfl_count: ", GlobalConfig.cfl_count);
	writeln("  dt_init: ", GlobalConfig.dt_init);
	writeln("  dt_max: ", GlobalConfig.dt_max);
	writeln("  cfl_value: ", GlobalConfig.cfl_value);
	writeln("  stringent_cfl: ", GlobalConfig.stringent_cfl);
	writeln("  dt_reduction_factor: ", GlobalConfig.dt_reduction_factor);
	writeln("  fixed_time_step: ", GlobalConfig.fixed_time_step);
	writeln("  dt_plot: ", GlobalConfig.dt_plot);
	writeln("  dt_history: ", GlobalConfig.dt_history);
    }
} // end read_control_file()


double init_simulation(int tindx)
{
    if (GlobalConfig.verbosity_level > 0) writeln("Begin init_simulation...");
    read_config_file();
    double sim_time;
    foreach (ref myblk; blk_data) {
	myblk.assemble_arrays();
	myblk.bind_faces_and_vertices_to_cells();
	writeln("myblk=", myblk);
	auto writer = appender!string();
	formattedWrite(writer, "grid/t%04d/%s.grid.b%04d.t%04d.gz",
		       tindx, GlobalConfig.base_file_name, myblk.id, tindx);
	auto fileName = writer.data();
	myblk.read_grid(fileName, 0);
	writer = appender!string();
	formattedWrite(writer, "flow/t%04d/%s.flow.b%04d.t%04d.gz",
		       tindx, GlobalConfig.base_file_name, myblk.id, tindx);
	fileName = writer.data();
	sim_time = myblk.read_solution(fileName);
    }
    if (GlobalConfig.verbosity_level > 0) writeln("Done init_simulation.");
    return sim_time;
} // end init_simulation()

double integrate_in_time(double sim_time)
{
    writeln("Integrate in time.");
    read_control_file(); // every step
    writeln("TODO fill in the REAL details.");
    writeln("Done integrate_in_time.");
    return sim_time;
} // end integrate_in_time()

void finalize_simulation(double sim_time)
{
    writeln("Finalize the simulation.");
    writeln("TODO fill in the REAL details.");
    foreach (ref myblk; blk_data) {
	myblk.write_solution("test-flow.txt.gz", 1.0);
    }
    writeln("Done finalize_simulation.");
} // end finalize_simulation()
