-- Author: Daniel F. Potter
-- Date: 24-Sept-2009

-- Atomic nitrogen cation

N_plus = {}
N_plus.species_type = "monatomic"
N_plus.M = {
   value = 14.0061514e-3,
   units = 'kg/mol',
   description = 'molecular mass',
   reference = 'CEA2::thermo.inp'
}
N_plus.charge = 1
N_plus.gamma = {
   value = 1.641, 
   units = 'non-dimensional',
   description = '(ideal) ratio of specific heats at room temperature',
   reference = 'Cp/Cv from CEA2 at room temperature'
}
N_plus.viscosity = {
   model = "CEA",
   parameters = {
      {T_low=1000.0, T_high=5000.0, A=0.83724737e+00, B=0.43997150e+03, C=-0.17450753e+06, D=0.10365689e+00},
      {T_low=5000.0, T_high=15000.0, A=0.89986588e+00, B=0.14112801e+04, C=-0.18200478e+07, D=-0.55811716e+00},
      ref = 'from CEA2 data for N'
   }
}
N_plus.thermal_conductivity = {
   model = "CEA",
   parameters = {
      {T_low=1000.0, T_high=5000.0, A=0.83771661e+00, B=0.44243270e+03, C=-0.17578446e+06, D=0.89942915e+00},
      {T_low=5000.0, T_high=15000.0, A=0.90001710e+00, B=0.14141175e+04, C=-0.18262403e+07, D=0.24048513e+00},
      ref = 'from CEA2 data for N'
   }
}
N_plus.CEA_coeffs = {
  { T_low = 298.150,
    T_high = 1000.0,
    coeffs = { 5.237079210e+03,  2.299958315e+00,  2.487488821e+00,
               2.737490756e-05, -3.134447576e-08,  1.850111332e-11,
              -4.447350984e-15,  2.256284738e+05,  5.076830786e+00
    }
  },
  { T_low = 1000.0,
    T_high = 6000.0,
    coeffs = {  2.904970374e+05, -8.557908610e+02,  3.477389290e+00,
               -5.288267190e-04,  1.352350307e-07, -1.389834122e-11,
                5.046166279e-16,  2.310809984e+05, -1.994146545e+00
    }
  },
  { T_low = 6000.0,
    T_high = 20000.0,
    coeffs = {  1.646092148e+07, -1.113165218e+04,  4.976986640e+00,
               -2.005393583e-04,  1.022481356e-08, -2.691430863e-13,
                3.539931593e-18,  3.136284696e+05, -1.706646380e+01
    }
  }
}

-- Thermal nonequilibrium data

N_plus.s_0 = {
   value = 11408.56,
   units = 'J/kg-K',
   description = 'Standard state entropy at 1 bar',
   reference = 'NIST Chemistry WebBook: http://webbook.nist.gov/chemistry/'
}
N_plus.h_f = {
   value = 1.343786e+08,
   units = 'J/kg',
   description = 'Heat of formation',
   reference = 'from CEA2::thermo.inp'
}
N_plus.I = {
   value = 2.039169e+08,
   units = 'J/kg',
   description = 'Ground state ionization energy',
   reference = 'NIST Atomic Spectra Database: http://physics.nist.gov/PhysRefData/ASD/index.html'
}
N_plus.Z = {
   value = 1,
   units = 'ND',
   description = 'Charge number',
   reference = 'NA'
}
N_plus.electronic_levels = {
   -- n_levels = 81,
   n_levels = 4,
   ref = 'NIST ASD: http://physics.nist.gov/PhysRefData/ASD/index.html',
   comments = 'All the individual NIST levels expressed as multiplets',
   -- ===========================================================
   --   No.    n      E(cm-1)      g     l     L     S    parity 
   -- ===========================================================
   ilev_0   =  { 2,       88.90,     9,   -1,    1,    1,    2 },
   ilev_1   =  { 2,    15316.20,     5,   -1,    2,    0,    2 },
   ilev_2   =  { 2,    32688.80,     1,   -1,    0,    0,    2 },
   ilev_3   =  { 2,    46784.60,     5,   -1,    0,    2,    1 },
   ilev_4   =  { 2,    92244.49,    15,   -1,    2,    1,    1 },
   ilev_5   =  { 2,   109217.92,     9,   -1,    1,    1,    1 },
   ilev_6   =  { 2,   144187.94,     5,   -1,    2,    0,    1 },
   ilev_7   =  { 2,   149012.41,     9,    0,    1,    1,    1 },
   ilev_8   =  { 2,   149187.80,     3,    0,    1,    0,    1 },
   ilev_9   =  { 2,   155126.73,     3,   -1,    0,    1,    1 },
   ilev_10  =  { 2,   164610.76,     3,    1,    1,    0,    2 },
   ilev_11  =  { 2,   166615.19,    15,    1,    2,    1,    2 },
   ilev_12  =  { 2,   166765.66,     3,   -1,    1,    0,    1 },
   ilev_13  =  { 2,   168892.21,     3,    1,    0,    1,    2 },
   ilev_14  =  { 2,   170636.38,     9,    1,    1,    1,    2 },
   ilev_15  =  { 2,   174212.03,     5,    1,    2,    0,    2 },
   ilev_16  =  { 2,   178273.38,     1,    1,    0,    0,    2 },
   ilev_17  =  { 2,   186591.77,    21,    2,    3,    1,    1 },
   ilev_18  =  { 2,   187091.37,     5,    2,    2,    0,    1 },
   ilev_19  =  { 2,   187470.92,    15,    2,    2,    1,    1 },
   ilev_20  =  { 2,   188883.51,     9,    2,    1,    1,    1 },
   ilev_21  =  { 2,   189335.16,     7,    2,    3,    0,    1 },
   ilev_22  =  { 2,   190120.24,     3,    2,    1,    0,    1 },
   ilev_23  =  { 2,   196652.68,     9,    0,    1,    1,    1 },
   ilev_24  =  { 2,   197858.69,     3,    0,    1,    0,    1 },
   ilev_25  =  { 2,   202170.63,     3,    1,    1,    0,    2 },
   ilev_26  =  { 2,   202799.88,    15,    1,    2,    1,    2 },
   ilev_27  =  { 2,   203224.94,     9,    1,    1,    1,    2 },
   ilev_28  =  { 2,   203537.66,     3,    1,    0,    1,    2 },
   ilev_29  =  { 2,   205350.18,     5,    1,    2,    0,    2 },
   ilev_30  =  { 2,   205675.91,    15,    0,    1,    2,    2 },
   ilev_31  =  { 2,   206910.24,     1,    1,    0,    0,    2 },
   ilev_32  =  { 2,   209759.49,    21,    2,    3,    1,    1 },
   ilev_33  =  { 2,   209925.76,     5,    2,    2,    0,    1 },
   ilev_34  =  { 2,   210277.43,    15,    2,    2,    1,    1 },
   ilev_35  =  { 2,   210728.56,     9,    2,    1,    1,    1 },
   ilev_36  =  { 2,   211031.26,    12,    3,   -1,    1,    2 },
   ilev_37  =  { 2,   211058.50,    16,    3,   -1,    1,    2 },
   ilev_38  =  { 2,   211103.63,     7,    2,    3,    0,    1 },
   ilev_39  =  { 2,   211291.52,    16,    3,   -1,    1,    2 },
   ilev_40  =  { 2,   211336.16,     3,    2,    1,    0,    1 },
   ilev_41  =  { 2,   211395.39,    20,    3,   -1,    1,    2 },
   ilev_42  =  { 2,   211412.42,    12,    3,   -1,    1,    2 },
   ilev_43  =  { 2,   211488.90,     8,    3,   -1,    1,    2 },
   ilev_44  =  { 2,   211802.89,     9,    0,    1,    1,    2 },
   ilev_45  =  { 2,   214322.85,     9,    0,    1,    1,    1 },
   ilev_46  =  { 2,   214829.18,     3,    0,    1,    0,    1 },
   ilev_47  =  { 2,   220295.56,     9,   -1,    1,    1,    2 },
   ilev_48  =  { 2,   220495.36,     5,    2,    2,    0,    1 },
   ilev_49  =  { 2,   220698.50,    15,    2,    2,    1,    1 },
   ilev_50  =  { 2,   221055.55,    12,    3,   -1,    1,    2 },
   ilev_51  =  { 2,   221071.54,    16,    3,   -1,    1,    2 },
   ilev_52  =  { 2,   221141.61,     7,    2,    3,    0,    1 },
   ilev_53  =  { 2,   221163.71,    16,   -1,   -1,    1,    1 },
   ilev_54  =  { 2,   221167.48,    20,   -1,   -1,    1,    1 },
   ilev_55  =  { 2,   221229.61,    16,    3,   -1,    1,    2 },
   ilev_56  =  { 2,   221246.17,     3,    2,    1,    0,    1 },
   ilev_57  =  { 2,   221293.95,    12,    3,   -1,    1,    2 },
   ilev_58  =  { 2,   221305.60,    20,    3,   -1,    1,    2 },
   ilev_59  =  { 2,   221322.82,    20,   -1,   -1,    1,    1 },
   ilev_60  =  { 2,   221342.92,    16,   -1,   -1,    1,    1 },
   ilev_61  =  { 2,   221353.41,     8,    3,   -1,    1,    2 },
   ilev_62  =  { 2,   221363.99,    24,   -1,   -1,    1,    1 },
   ilev_63  =  { 2,   221380.30,    12,   -1,   -1,    1,    1 },
   ilev_64  =  { 2,   222828.05,     9,    0,    1,    1,    1 },
   ilev_65  =  { 2,   223069.02,     3,    1,    0,    1,    1 },
   ilev_66  =  { 2,   223101.82,     3,    0,    1,    0,    1 },
   ilev_67  =  { 2,   223730.08,    25,    1,    2,    2,    1 },
   ilev_68  =  { 2,   225643.09,    15,    1,    1,    2,    1 },
   ilev_69  =  { 2,   226483.50,    12,    3,   -1,    1,    2 },
   ilev_70  =  { 2,   226490.65,    16,    3,   -1,    1,    2 },
   ilev_71  =  { 2,   226641.92,    16,    3,   -1,    1,    2 },
   ilev_72  =  { 2,   226676.99,    12,    3,   -1,    1,    2 },
   ilev_73  =  { 2,   226692.18,    20,    3,   -1,    1,    2 },
   ilev_74  =  { 2,   226719.98,     8,    3,   -1,    1,    2 },
   ilev_75  =  { 2,   228752.32,    15,    1,    2,    1,    1 },
   ilev_76  =  { 2,   229749.35,    16,    3,   -1,    1,    2 },
   ilev_77  =  { 2,   229838.96,     5,    1,    0,    2,    1 },
   ilev_78  =  { 2,   229907.50,     9,    3,   -1,    1,    2 },
   ilev_79  =  { 2,   229940.35,    20,    3,   -1,    1,    2 },
   ilev_80  =  { 2,   230831.74,     9,    1,    1,    1,    1 },
   -- ===========================================================
}
N_plus.spradian_electronic_levels = {
   n_levels = 12,
   ref = 'Spradian07::atom.dat',
   -- ===================================
   --  Level   n      E(cm-1)        g
   -- ===================================
   ilev_0  = { 2,        0.00,       1 },
   ilev_1  = { 2,       70.07,       3 },
   ilev_2  = { 2,      188.19,       5 },
   ilev_3  = { 2,    22036.47,       5 },
   ilev_4  = { 2,    47031.63,       1 },
   ilev_5  = { 2,    67312.23,       5 },
   ilev_6  = { 2,   132708.02,       7 },
   ilev_7  = { 2,   132726.87,       5 },
   ilev_8  = { 2,   132729.03,       3 },
   ilev_9  = { 3,   157137.46,       3 },
   ilev_10 = { 3,   157138.90,       5 },
   ilev_11 = { 3,   157147.39,       1 },
   -- ===================================
}
