/**
 * gasmodelutil.d
 * Utility functions that make use of the gasmodel class and its derived classes.
 *
 * Author: Peter J. and Rowan G.
 * Version: 2014-06-22, first cut, exploring the options.
 */

module gasmodelutil;

import gasmodel;
import idealgas;
import std.file;
import std.stdio;
import std.json;

/**
 * We get the instructions for setting up the GasModel object
 * from the JSON file.  The first item should be a model name
 * which we use to select the specific GasModel class.
 * When constructing a specific object we pass the name of the 
 * same JSON file through to the class so that it may pick out
 * it's specific parameters.
 * As new GasModel classes are added to the collection, just 
 * add a new case to the switch statement below.
 */
GasModel init_gas_model(in char[] file_name="gas-model.json") {
    auto text = cast(string) read(file_name);
    auto items = parseJSON(text);
    string gas_model_name = items["model"].str;
    GasModel gm;
    switch ( gas_model_name ) {
    case "Ideal_gas":
	gm = new IdealGas(file_name);
	break;
    default:
	gm = new IdealGas("");
    }
    return gm;
}


unittest {
    import std.math;
    auto gm = init_gas_model("sample-data/ideal-air-gas-model.json");
    auto gd = new GasState(gm, 100.0e3, 300.0);
    assert(approxEqual(gm.R(gd), 287.086), "gas constant");
    assert(gm.n_modes == 1, "number of energy modes");
    assert(gm.n_species == 1, "number of species");
    assert(approxEqual(gd.p, 1.0e5), "pressure");
    assert(approxEqual(gd.T[0], 300.0), "static temperature");
    assert(approxEqual(gd.massf[0], 1.0), "massf[0]");

    gm.update_thermo_from_pT(gd);
    gm.update_sound_speed(gd);
    assert(approxEqual(gd.rho, 1.16109), "density");
    assert(approxEqual(gd.e[0], 215314.0), "internal energy");
    assert(approxEqual(gd.a, 347.241), "density");
    gm.update_trans_coeffs(gd);
    assert(approxEqual(gd.mu, 1.84691e-05), "viscosity");
    assert(approxEqual(gd.k[0], 0.0262449), "conductivity");
}