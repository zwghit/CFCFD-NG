// Author: Daniel F Potter
// Date: 07-Apr-2010
// Place: Dutton Park, QLD, Oz

#include <iostream>

#include "../../util/source/useful.h"

#include "../models/chemical-species-library.hh"

#include "chemistry-energy-coupling.hh"

using namespace std;

/************************* Chemistry_energy_coupling *************************/

Chemistry_energy_coupling::
Chemistry_energy_coupling( int isp, string mode, vector<Coupling_component*> &ccs )
: isp_( isp ), mode_( mode )
{
    Chemical_species * X = get_library_species_pointer( isp_ );
    bool found = false;
    for ( int itm=0; itm<X->get_n_modes(); ++itm ) {
    	Species_energy_mode * sem = X->get_mode_pointer(itm);
    	if ( sem->get_type()==mode_ ) {
    	    found = true;
    	    sems_.push_back( sem );
    	}
    }
    if ( !found ) {
    	cout << "Chemistry_energy_coupling::Chemistry_energy_coupling()" << endl
    	     << "mode: " << mode_ << " not found for species: " << X->get_name() << endl
    	     << "Exiting." << endl;
    	exit( BAD_INPUT_ERROR );
    }
    imode_ = sems_[0]->get_iT();
    m_ = X->get_M() / PC_Avogadro;
    
    // Make copies of the Coupling_components
    for ( size_t i=0; i<ccs.size(); ++i )
    	components_.push_back( ccs[i]->clone() );
}

Chemistry_energy_coupling::
~Chemistry_energy_coupling()
{
    for ( size_t i=0; i<components_.size(); ++i )
    	delete components_[i];
}

void
Chemistry_energy_coupling::
set_e_and_N_old( Gas_data &Q, vector<double> &c_old )
{
    e_old_ = 0.0;
    for ( size_t i = 0; i < sems_.size(); ++i ) 
    	e_old_ += sems_[i]->eval_energy(Q) * m_;		// Convert J/kg -> J/particle
    double N_old = c_old[isp_]*PC_Avogadro;			// Convert moles/m**3 -> particles/m**3
    for( size_t i = 0; i < components_.size(); ++i ) {
    	components_[i]->set_e_and_N_old( e_old_, N_old );
    }
}

int
Chemistry_energy_coupling::
update_energy( Gas_data &Q, valarray<double> &delta_c, vector<double> &c_new )
{
    // 1. Loop over the components add compute the contributions
    
    double delta_E = 0.0;
    
    for( size_t i = 0; i < components_.size(); ++i ) {
    	delta_E += components_[i]->compute_contribution(Q, delta_c);
    }
    
    double N_new = c_new[isp_]*PC_Avogadro;
    // double e_new = 0.0;
    // if ( N_new>0.0 ) e_new = e_old_ + delta_E/N_new;
    
    // Q.e[imode_] += Q.massf[isp_]  * e_new / m_;			// convert J/particle -> J/kg-mix
    
    double delta_e = 0.0;
    if ( N_new > 0.0 ) delta_e = delta_E/N_new;
    
    //Q.e[imode_] += Q.massf[isp_] * delta_e / m_;			// convert J/particle -> J/kg-mix
    Q.e[imode_] += delta_e / m_;
    
    return SUCCESS;
}

double
Chemistry_energy_coupling::
eval_source_term( Gas_data &Q, valarray<double> &dcdt )
{
    // 1. Loop over the components add compute the contributions
    
    double dEdt = 0.0;
    
    for( size_t i = 0; i < components_.size(); ++i ) {
    	dEdt += components_[i]->compute_source_term(Q, dcdt );
    }
    
    dEdt /= Q.rho;		// convert J/m**3 -> J/kg
    
    return dEdt;
}

/************************** creation function *****************************/

void create_Chemistry_energy_coupling_for_species_mode( int isp, string mode, 
    vector<Coupling_component*> &ccs, vector<Chemistry_energy_coupling*> &cecs )
{
    vector<Coupling_component*> components;
    
    for ( size_t i=0; i<ccs.size(); ++i ) {
    	if ( ccs[i]->get_isp()==isp && ccs[i]->get_mode()==mode ) 
    	    components.push_back( ccs[i] );
    }
    
    if ( components.size()>0 ) {
    	cout << "- creating " << components.size() 
    	     << " chemistry-energy coupling components for mode: " << mode 
    	     << " of species: " << get_library_species_name(isp) << endl;
    	cecs.push_back( new Chemistry_energy_coupling( isp, mode, components ) );
    }
    
    return;
}
