-- Auto-generated by gasfile on: 26-Aug-2013 23:28:25
model = 'composite gas'
equation_of_state = 'perfect gas'
thermal_behaviour = 'thermal nonequilibrium'
mixing_rule = 'GuptaYos'
sound_speed = 'equilibrium'
diffusion_coefficients = 'GuptaYos'
min_massf = 1.000000e-15

thermal_modes = { 'transrotational', 'vibroelectronic' }

transrotational = {}
transrotational.type = 'constant Cv'
transrotational.iT = 0
transrotational.components = { 'all-translation', 'all-rotation' }

vibroelectronic = {}
vibroelectronic.type = 'variable Cv'
vibroelectronic.iT = 1
vibroelectronic.components = { 'all-vibration', 'all-electronic' }
vibroelectronic.T_min = 20.000000
vibroelectronic.T_max = 100000.000000
vibroelectronic.iterative_method = 'NewtonRaphson'
vibroelectronic.convergence_tolerance = 1.000000e-06
vibroelectronic.max_iterations = 100

species = {'N2', 'O2', }

N2 = {}
N2.species_type = "nonpolar diatomic"
N2.oscillator_type = "truncated harmonic"
N2.M = {
  value = 0.0280134,
  reference = "from CEA2::thermo.inp",
  description = "molecular mass",
  units = "kg/mol",
}
N2.s_0 = {
  value = 6839.91,
  reference = "NIST Chemistry WebBook: http://webbook.nist.gov/chemistry/",
  description = "Standard state entropy at 1 bar",
  units = "J/kg-K",
}
N2.h_f = {
  value = 0,
  reference = "from CEA2::thermo.inp",
  description = "Heat of formation",
  units = "J/kg",
}
N2.I = {
  value = 53661441,
  reference = "NIST Chemistry WebBook: http://webbook.nist.gov/chemistry/",
  description = "Ground state ionization energy",
  units = "J/kg",
}
N2.Z = {
  value = 0,
  reference = "NA",
  description = "Charge number",
  units = "ND",
}
N2.eps0 = {
  value = 9.85789812e-22,
  reference = "Svehla (1962) NASA Technical Report R-132",
  description = "Depth of the intermolecular potential minimum",
  units = "J",
}
N2.sigma = {
  value = 3.798e-10,
  reference = "Svehla (1962) NASA Technical Report R-132",
  description = "Hard sphere collision diameter",
  units = "m",
}
N2.charge = 0
N2.r0 = {
  value = 4.2e-10,
  reference = "Thivet et al (1991) Phys. Fluids A 3 (11)",
  description = "Zero of the intermolecular potential",
  units = "m",
}
N2.r_eq = {
  value = 1.1e-10,
  reference = "See ilev_0 data below",
  description = "Equilibrium intermolecular distance",
  units = "m",
}
N2.f_m = {
  value = 1,
  reference = "Thivet et al (1991) Phys. Fluids A 3 (11)",
  description = "Mass factor = ( M ( Ma^2 + Mb^2 ) / ( 2 Ma Mb ( Ma + Mb ) )",
  units = "ND",
}
N2.mu = {
  value = 2.32587e-26,
  reference = "See molecular weight for N",
  description = "Reduced mass of constituent atoms",
  units = "kg/particle",
}
N2.alpha = {
  value = 1.09,
  reference = "Hirschfelder, Curtiss, and Bird (1954). Molecular theory of gases and liquids.",
  description = "Polarizability",
  units = "Angstrom^3",
}
N2.electronic_levels = {
  n_levels = 5,
  ref = "Spradian07::diatom.dat",
  ilev_0 = {
    0,
    1.0977,
    1,
    78740,
    2358.569,
    14.3244,
    -0.002258,
    -0.00024,
    1.99824,
    0.01732,
    5.76e-06,
    0,
    0,
    0,
    1,
  },
  ilev_1 = {
    50203.66,
    1.2864,
    3,
    28980,
    1460.941,
    13.98,
    0.024,
    -0.00256,
    1.4539,
    0.0175,
    5.78e-06,
    0,
    0,
    0,
    3,
  },
  ilev_2 = {
    59619.09,
    1.2126,
    6,
    38660,
    1734.025,
    14.412,
    -0.0033,
    -0.00079,
    1.63772,
    0.01793,
    5.9e-06,
    0,
    42.24,
    1,
    3,
  },
  ilev_3 = {
    59808,
    1.27,
    6,
    38590,
    1501.4,
    11.6,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    2,
    3,
  },
  ilev_4 = {
    66272.5,
    1.2784,
    3,
    51340,
    1516.88,
    12.181,
    0.04186,
    0,
    1.4733,
    0.01666,
    5.56e-06,
    0,
    0,
    0,
    3,
  },
}
N2.CEA_coeffs = {
  {
    T_high = 1000,
    T_low = 200,
    coeffs = {
      22103.71497,
      -381.846182,
      6.08273836,
      -0.00853091441,
      1.384646189e-05,
      -9.62579362e-09,
      2.519705809e-12,
      710.846086,
      -10.76003744,
    },
  },
  {
    T_high = 6000,
    T_low = 1000,
    coeffs = {
      587712.406,
      -2239.249073,
      6.06694922,
      -0.00061396855,
      1.491806679e-07,
      -1.923105485e-11,
      1.061954386e-15,
      12832.10415,
      -15.86640027,
    },
  },
  {
    T_high = 20000,
    T_low = 6000,
    coeffs = {
      831013916,
      -642073.354,
      202.0264635,
      -0.03065092046,
      2.486903333e-06,
      -9.70595411e-11,
      1.437538881e-15,
      4938707.04,
      -1672.09974,
    },
  },
  ref = "from CEA2::thermo.inp",
}
N2.viscosity = {
  model = 'collision integrals'
}
N2.thermal_conductivity = {
  model = 'collision integrals'
}

O2 = {}
O2.species_type = "nonpolar diatomic"
O2.oscillator_type = "truncated harmonic"
O2.M = {
  value = 0.0319988,
  reference = "from CEA2::thermo.inp",
  description = "molecular mass",
  units = "kg/mol",
}
O2.s_0 = {
  value = 6411.18,
  reference = "NIST Chemistry WebBook: http://webbook.nist.gov/chemistry/",
  description = "Standard state entropy at 1 bar",
  units = "J/kg-K",
}
O2.h_f = {
  value = 0,
  reference = "from CEA2::thermo.inp",
  description = "Heat of formation",
  units = "J/kg",
}
O2.I = {
  value = 36397495,
  reference = "NIST Chemistry WebBook: http://webbook.nist.gov/chemistry/",
  description = "Ground state ionization energy",
  units = "J/kg",
}
O2.Z = {
  value = 0,
  reference = "NA",
  description = "Charge number",
  units = "ND",
}
O2.eps0 = {
  value = 1.473162086e-21,
  reference = "Svehla (1962) NASA Technical Report R-132",
  description = "Depth of the intermolecular potential minimum",
  units = "J",
}
O2.sigma = {
  value = 3.467e-10,
  reference = "Svehla (1962) NASA Technical Report R-132",
  description = "Hard sphere collision diameter",
  units = "m",
}
O2.charge = 0
O2.r0 = {
  value = 3.541e-10,
  reference = "Hirschfelder, Curtiss, and Bird (1954). Molecular theory of gases and liquids.",
  description = "Zero of the intermolecular potential",
  units = "m",
}
O2.r_eq = {
  value = 1.21e-10,
  reference = "See ilev_0 data below",
  description = "Equilibrium intermolecular distance",
  units = "m",
}
O2.f_m = {
  value = 1,
  reference = "Thivet et al (1991) Phys. Fluids A 3 (11)",
  description = "Mass factor = ( M ( Ma^2 + Mb^2 ) / ( 2 Ma Mb ( Ma + Mb ) )",
  units = "ND",
}
O2.mu = {
  value = 2.65676e-26,
  reference = "See molecular weight for O",
  description = "Reduced mass of constituent atoms",
  units = "kg/particle",
}
O2.alpha = {
  value = 0.793,
  reference = "FIXME: Rowans mTg_input.dat",
  description = "Polarizability",
  units = "ND",
}
O2.mu_B = {
  value = 8.199176e-19,
  reference = "FIXME: Rowans mTg_input.dat",
  description = "Dipole moment",
  units = "Debye",
}
O2.electronic_levels = {
  n_levels = 5,
  ref = "Spradian07::diatom.dat",
  ilev_0 = {
    0,
    1.2075,
    3,
    41280,
    1580.193,
    11.9808,
    0.04747,
    -0.001273,
    1.44563,
    0.01593,
    4.839e-06,
    0,
    0,
    0,
    3,
  },
  ilev_1 = {
    7918.04,
    1.2156,
    2,
    33410,
    1509.763,
    13.065,
    0.011,
    0,
    1.42642,
    0.0172,
    4.86e-06,
    0,
    0,
    2,
    1,
  },
  ilev_2 = {
    13195.1,
    1.2269,
    1,
    28160,
    1432.77,
    14,
    0,
    0,
    1.40037,
    0.0182,
    5.351e-06,
    3.2e-08,
    0,
    0,
    1,
  },
  ilev_3 = {
    33057.3,
    1.5174,
    1,
    8620,
    794.29,
    12.736,
    -0.2444,
    0,
    0.9155,
    0.01391,
    7.4e-06,
    0,
    0,
    0,
    1,
  },
  ilev_4 = {
    34690,
    1.48,
    6,
    6960,
    850,
    20,
    0,
    0,
    0.96,
    0.0262,
    0,
    0,
    145.9,
    2,
    3,
  },
}
O2.CEA_coeffs = {
  {
    T_high = 1000,
    T_low = 200,
    coeffs = {
      -34255.6342,
      484.700097,
      1.119010961,
      0.00429388924,
      -6.83630052e-07,
      -2.0233727e-09,
      1.039040018e-12,
      -3391.45487,
      18.4969947,
    },
  },
  {
    T_high = 6000,
    T_low = 1000,
    coeffs = {
      -1037939.022,
      2344.830282,
      1.819732036,
      0.001267847582,
      -2.188067988e-07,
      2.053719572e-11,
      -8.19346705e-16,
      -16890.10929,
      17.38716506,
    },
  },
  {
    T_high = 20000,
    T_low = 6000,
    coeffs = {
      497529430,
      -286610.6874,
      66.9035225,
      -0.00616995902,
      3.016396027e-07,
      -7.4214166e-12,
      7.27817577e-17,
      2293554.027,
      -553.062161,
    },
  },
  ref = "from CEA2::thermo.inp",
}
O2.viscosity = {
  model = 'collision integrals'
}
O2.thermal_conductivity = {
  model = 'collision integrals'
}

collision_integrals = {
  {
    i = "N2",
    j = "N2",
    reference = "Wright et al, AIAA Journal Vol. 43 No. 12 December 2005",
    model = "GuptaYos curve fits",
    parameters = {
      {
        Pi_Omega_11 = {
          -0.0066,
          0.1392,
          -1.1559,
          6.9352,
        },
        T_high = 10000,
        T_low = 300,
        D = {
          0.0066,
          -0.1392,
          2.6559,
          -9.9442,
        },
        Pi_Omega_22 = {
          -0.0087,
          0.1948,
          -1.6023,
          8.1845,
        },
      },
    },
  },
  {
    i = "N2",
    j = "O2",
    reference = "Wright et al, AIAA Journal Vol. 43 No. 12 December 2005",
    model = "GuptaYos curve fits",
    parameters = {
      {
        Pi_Omega_11 = {
          -0.0075,
          0.1811,
          -1.6451,
          8.3532,
        },
        T_high = 15000,
        T_low = 300,
        D = {
          0.0075,
          -0.1811,
          3.1451,
          -11.3943,
        },
        Pi_Omega_22 = {
          -0.0077,
          0.1842,
          -1.6438,
          8.3784,
        },
      },
    },
  },
  {
    i = "O2",
    j = "O2",
    reference = "Wright et al, AIAA Journal Vol. 43 No. 12 December 2005",
    model = "GuptaYos curve fits",
    parameters = {
      {
        Pi_Omega_11 = {
          -0.0023,
          0.0516,
          -0.5785,
          5.6041,
        },
        T_high = 15000,
        T_low = 300,
        D = {
          0.0023,
          -0.0516,
          2.0785,
          -8.6796,
        },
        Pi_Omega_22 = {
          -0.0089,
          0.2066,
          -1.7522,
          8.6099,
        },
      },
    },
  },

}
