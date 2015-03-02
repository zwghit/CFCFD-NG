// luaglobalconfig.d
// Lua access to the GlobalConfig class data, for use in the preparation script.
//
// Peter J. and Rowan G.
// 2015-03-02: First code adapted from the other lua wrapper modules.

module luaglobalconfig;

// We cheat to get the C Lua headers by using LuaD.
import luad.all;
import luad.c.lua;
import luad.c.lauxlib;
import std.stdio;
import std.string;
import std.conv;
import util.lua_service;

import gas;
import globalconfig;

immutable string GlobalConfigMT = "GlobalConfig";

extern(C) int get_or_set_field(string name, T)(lua_State* L)
{
    // Note that, in both sets of tests below,
    // we must test for the bool before the int
    // because the bool is a more specialized type of int
    // in the D language.
    int narg = lua_gettop(L); 
    if (narg == 0) {
	// This is a getter
	static if (is(T : bool)) {
	    mixin("lua_pushboolean(L, to!int(GlobalConfig."~name~"));");
	} else static if (is(T : double)) {
	    mixin("lua_pushnumber(L, GlobalConfig."~name~");");
	} else static if (is(T : int)) {
	    mixin("lua_pushnumber(L, GlobalConfig."~name~");");
	} else static if (is(T : string)) {
	    mixin("lua_pushstring(L, GlobalConfig."~name~".toStringz);");
	} else {
	    assert(0, "Unavailable type");
	}
	return 1;
    } else {
	// This is a setter
	static if (is(T : bool)) {
	    mixin("GlobalConfig."~name~" = to!T(lua_toboolean(L, 1));");
	} else static if (is(T : double)) {
	    mixin("GlobalConfig."~name~" = to!T(luaL_checknumber(L, 1));");
	} else static if (is(T : int)) {
	    mixin("GlobalConfig."~name~" = to!T(luaL_checkint(L, 1));");
	} else static if (is(T : string)) {
	    mixin("GlobalConfig."~name~" = to!T(luaL_checkstring(L, 1));");
	} else {
	    assert(0, "Unavailable type");
	}
	return 0;
    }
} // end get_set_field()()

//------------------------------------------------------------------------
// Functions related to the managed gas model.

extern(C) int setGasModel(lua_State* L)
{
    string fname = to!string(luaL_checkstring(L, 1));
    GlobalConfig.gasModelFile = fname;
    GlobalConfig.gmodel = init_gas_model(fname);
    lua_pushinteger(L, GlobalConfig.gmodel.n_species);
    lua_pushinteger(L, GlobalConfig.gmodel.n_modes);
    return 2;
    
}

extern(C) int get_nspecies(lua_State* L)
{
    lua_pushinteger(L, GlobalConfig.gmodel.n_species);
    return 1;
}

extern(C) int get_nmodes(lua_State* L)
{
    lua_pushinteger(L, GlobalConfig.gmodel.n_modes);
    return 1;
}

extern(C) int species_name(lua_State* L)
{
    int i = to!int(luaL_checkinteger(L, 1));
    lua_pushstring(L, GlobalConfig.gmodel.species_name(i).toStringz);
    return 1;
}

//-----------------------------------------------------------------------
void registerGlobalConfig(LuaState lua)
{
    auto L = lua.state;

    // Register the GlobalConfig2D object
    luaL_newmetatable(L, GlobalConfigMT.toStringz);
    //
    /* metatable.__index = metatable */
    lua_pushvalue(L, -1); // duplicates the current metatable
    lua_setfield(L, -2, "__index");
    //
    /* Register methods for use. */
    lua_pushcfunction(L, &toStringObj!(GlobalConfig, GlobalConfigMT));
    lua_setfield(L, -2, "__tostring");
    //
    lua_pushcfunction(L, &get_or_set_field!("title", string));
    lua_setfield(L, -2, "title");
    lua_pushcfunction(L, &get_or_set_field!("dimensions", int));
    lua_setfield(L, -2, "dimensions");
    lua_pushcfunction(L, &get_or_set_field!("max_time", double));
    lua_setfield(L, -2, "max_time");
    lua_pushcfunction(L, &get_or_set_field!("dt_init", double));
    lua_setfield(L, -2, "dt_init");
    lua_pushcfunction(L, &get_or_set_field!("axisymmetric", bool));
    lua_setfield(L, -2, "axisymmetric");
    //
    lua_setglobal(L, GlobalConfigMT.toStringz);

    // Register other global functions related to the managed gas model.
    lua_pushcfunction(L, &setGasModel);
    lua_setglobal(L, "setGasModel");
    lua_pushcfunction(L, &get_nspecies);
    lua_setglobal(L, "get_nspecies");
    lua_pushcfunction(L, &get_nmodes);
    lua_setglobal(L, "get_nmodes");
    lua_pushcfunction(L, &species_name);
    lua_setglobal(L, "species_name");
} // end registerGlobalConfig()
