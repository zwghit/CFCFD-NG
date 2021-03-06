/** \file ray_tracing.cxx
 *  \ingroup radiation
 *
 *  \author Daniel F. Potter
 *  \version 19-Sept-08 
 *
 **/

#include <string>
#include <sstream>
#include <iostream>
#include <iomanip>
#include <fstream>
#include <cmath>
#include <algorithm>

#ifdef _OPENMP
#include <omp.h>
#else
#define omp_get_thread_num() 0
#define omp_get_max_threads() 1
#endif

#include "ray_tracing_pieces.hh"

#include "../../../lib/radiation/source/spectral_model.hh"
#include "../../../lib/radiation/source/radiation_constants.hh"
#include "../../../lib/util/source/useful.h"

using namespace std;

/* RayTracingPoint class definitions */

RayTracingPoint::RayTracingPoint( Gas_data * Q, double * Q_rE_rad, double s, double vol, CoeffSpectra * X, BinnedCoeffSpectra * Y, vector<double> * Q_rE_rad_temp )
: Q_( Q ), Q_rE_rad_( Q_rE_rad ), s_( s ), vol_( vol ), X_( X ), Y_( Y ), Q_rE_rad_temp_( Q_rE_rad_temp )
{}

RayTracingPoint::~RayTracingPoint() {}

/* RayTracingRay class definitions */

RayTracingRay::RayTracingRay( double theta, double phi, double domega,
    			      Vector3 ray_origin )
: theta_( theta ), phi_( phi ), domega_( domega ), ray_origin_( ray_origin ),
  status_( INSIDE_GRID ), L_( 0.0 ), E_exit_( 0.0 )
{}

RayTracingRay::~RayTracingRay()
{
    for ( size_t ip=0; ip<points_.size(); ++ip )
    	delete points_[ip];
}

RayTracingRay2D::RayTracingRay2D( double theta, double phi, double domega,
    			          Vector3 ray_origin )
: RayTracingRay( theta, phi, domega, ray_origin )
{}

RayTracingRay2D::~RayTracingRay2D() {}

Vector3 RayTracingRay2D::get_point_on_line( double &L )
{
    double x = ray_origin_.x + L * cos( phi_ ) * cos( theta_ );
    double y = ray_origin_.y + L * sin( phi_ );
    double z = ray_origin_.z + L * cos( phi_ ) * sin( theta_ );
    
    // Computational space coords
    double x_dash = x;
    double y_dash = sqrt( y*y + z*z );
    
    // To avoid assuming a reflecting southern boundary at y=0
    // FIXME: doesn't work for axisymmetric cases...
    // if ( y < 0.0 ) y_dash *= -1.0;
    
    return Vector3( x_dash, y_dash, 0.0 );
}

RayTracingRay3D::RayTracingRay3D( double theta, double phi, double domega,
    			          Vector3 ray_origin )
: RayTracingRay( theta, phi, domega, ray_origin )
{}

RayTracingRay3D::~RayTracingRay3D() {}

Vector3 RayTracingRay3D::get_point_on_line( double &L )
{
    // Computational space coords
    double x = ray_origin_.x + L * cos( phi_ ) * cos( theta_ );
    double y = ray_origin_.y + L * sin( phi_ );
    double z = ray_origin_.z + L * cos( phi_ ) * sin( theta_ );
    
    return Vector3( x, y, z );
}

/* RayTracingCell class definitions */

RayTracingCell::RayTracingCell( Gas_data * Q, double * Q_rE_rad, Vector3 origin, double vol, double area )
: Q_( Q ), Q_rE_rad_( Q_rE_rad ), origin_( origin ), vol_( vol ), area_( area )
{
    // 0. Initialise CoeffSpectra
    X_ = new CoeffSpectra();
    
    // 1. Initialise BinnedCoeffSpectra to zero as it may not be required
    Y_ = 0;

    // NOTE: - not computing spectra until DiscreteTransfer::compute_Q_rad_for_flowfield()
    //         is called
}

RayTracingCell::~RayTracingCell()
{
    // 1. delete CoeffSpectra
    delete X_;
    
    // 2. delete BinnedCoeffSpectra
    if ( Y_ ) delete Y_;

    // 2. delete all rays
    for ( size_t ir=0; ir<rays_.size(); ++ir )
    	delete rays_[ir];
}

void RayTracingCell::recompute_spectra( RadiationSpectralModel * rsm ) 
{
    rsm->radiative_spectra_for_gas_state( *Q_, *X_ );

    // Also store the cumulative (integrated) emission coefficient
    if ( rsm->get_spectral_points()==1 ) {
	// This is the equilibrum air model
	X_->j_int.resize(1);
        X_->j_int[0] = X_->j_nu[0];
    }
    else {
        X_->calculate_cumulative_emission(true);
    }
    
    return;
}

void RayTracingCell::read_precomputed_parade_spectra( size_t ib, size_t ic )
{
    // 0. Make sure the vectors in CoeffSpectra are sized to zero.
    X_->clear_data();

    // 3. Pick up the solution and insert it into CoeffSpectra
    ostringstream path;
    path << "block-" << ib << "/par_res_" << ic << ".txt";
    cout << path.str() << endl;
    ifstream specfile( path.str().c_str() );
    if ( !specfile.is_open() ) {
        cout << "RayTracingCell::read_precomputed_parade_spectra()" << endl
             << "Could not open parade spectra file '" << path.str() << "'." << endl
             << "Exiting program." << endl;
        exit( FAILURE );
    }
    
    // Discard 8 header lines
    char header[128];
    for ( int i=0; i<8; ++i )
		specfile.getline(header,128);

    // Remaining lines should be spectral data
    // Note that the parade data starts from the lower wavelength whereas the
    // CoeffSpectra class starts from the highest wavelength, and parade outputs
    // j_lambda whereas we need j_nu (hence the conversion)
    double lambda_ang, nu, j_lambda, kappa;
    while ( specfile >> lambda_ang >> j_lambda >> kappa ) {
        nu = lambda2nu( lambda_ang/10.0 );
        X_->nu.push_back( nu );
        X_->j_nu.push_back( j_lambda * RC_c_SI / nu / nu );
        X_->kappa_nu.push_back( kappa );
    }
    specfile.close();
    
    if ( X_->nu.size()==0 ) {
        cout << "RayTracingCell::read_precomputed_parade_spectra()" << endl
             << "No valid spectral data read from file: " << path.str() << endl
             << "Check the contents of the file and try again." << endl;
        exit( FAILURE );
    }

    // We want ascending frequencies for consistency with photaura model
    if ( X_->nu.front() > X_->nu.back() ) {
        reverse( X_->nu.begin(), X_->nu.end() );
        reverse( X_->j_nu.begin(), X_->j_nu.end() );
        reverse( X_->kappa_nu.begin(), X_->kappa_nu.end() );
    }

    // The Monte-Carlo models need the integrated emission spectra
    X_->integrate_emission_spectra();
    
    // Also store the cumulative (integrated) emission coefficient
    if ( X_->nu.size()==1 ) {
	// This is the equilibrum air model
	X_->j_int.resize(1);
        X_->j_int[0] = X_->j_nu[0];
    }
    else {
        X_->calculate_cumulative_emission(true);
    }

    return;
}

void RayTracingCell::set_CFD_cell_indices( size_t ii, size_t jj, size_t kk )
{
    ii_ = ii;
    jj_ = jj;
    kk_ = kk;
    
    return;
}

void RayTracingCell::get_CFD_cell_indices( size_t &ii, size_t &jj, size_t &kk )
{
    ii = ii_;
    jj = jj_;
    kk = kk_;
    
    return;
}

string RayTracingCell::str()
{
    ostringstream ost;
    ost << "ii = " << ii_ << ", jj = " << jj_ << ", kk = " << kk_ << endl;
    
    return ost.str();
}

void RayTracingCell::write_rays_to_file( string filename )
{
    ofstream outfile;
    outfile.open( filename.c_str() );
    outfile << setprecision(12) << showpoint << scientific;
    outfile << "# Column 1: x coord (m)" << endl
            << "# Column 2: y coord (m)" << endl
            << "# Column 3: z coord (m)" << endl;
            
    for ( size_t iray=0; iray<rays_.size(); ++iray ) {
    	RayTracingRay * ray = rays_[iray];
    	outfile << "# iray = " << iray << endl;
    	for ( size_t ip=0; ip<ray->points_.size(); ++ip ) {
    	    RayTracingPoint * point = ray->points_[ip];
    	    Vector3 p = ray->get_point_on_line( point->s_ );
    	    outfile << setw(20) << p.x << setw(20) << p.y << setw(20) << p.z << endl;
    	}
    }
    
    outfile.close();
    
    return;
}

DiscreteTransferCell::DiscreteTransferCell( Gas_data * Q, double * Q_rE_rad, Vector3 origin, double vol, size_t nrays, size_t ndim, bool planar )
: RayTracingCell( Q, Q_rE_rad, origin, vol )
{
    if ( nrays > 0 ) {
	if ( planar == true ) {
	    // uniform planar ray distribution
	    double alpha = 0.0, theta = 0.0, phi = 0.0, domega = 0.0;
	    for ( size_t iray=0; iray<nrays; ++iray ) {
		alpha = 2.0 * M_PI * iray / nrays;
		if ( alpha>=0.0 && alpha<M_PI/2.0 ) {
		    theta = 0.0; phi = alpha;
		} else if ( alpha>=M_PI/2.0 && alpha<1.5*M_PI ) {
		    theta = M_PI; phi = M_PI - alpha;
		} else if ( alpha>=1.5*M_PI && alpha<2.0*M_PI ) {
		    theta = 0.0; phi = alpha - M_PI*2.0;
		}
		domega = fabs( cos( phi ) ) * 2.0 * M_PI / double( nrays ) * M_PI ;
		rays_.push_back( new RayTracingRay2D( theta, phi, domega, origin_ ) );
	    }
	} else {
	    // uniform 3D ray distribution - create rays via golden spiral method
	    vector<Vector3> pts;
	    double inc = M_PI * ( 3.0 - sqrt(5.0) );
	    double off = 2.0 / double(nrays);
	    double phi, theta = 0.0;
	    for ( size_t iray=0; iray<nrays; ++iray ) {
		double y = double(iray)*off - 1.0 + ( off/2.0 );
		double r = sqrt( 1.0 - y*y );
		phi = double(iray)*inc;
		pts.push_back( Vector3(cos(phi)*r, y, sin(phi)*r) );
	    }
	    
	    // Extract angles in our coordinate system
	    double domega = 4.0 * M_PI / double ( nrays );
	    for ( size_t iray=0; iray<nrays; ++iray ) {
		double x=pts[iray].x, y=pts[iray].y, z=pts[iray].z;
		double L = vabs( pts[iray] );
		phi = asin( y / L );
		// calculate theta
		if      ( x >0.0 && z >0.0 ) theta = atan(z/x);
		else if ( x==0.0 && z >0.0 ) theta = 0.5*M_PI;
		else if ( x <0.0 && z >0.0 ) theta = M_PI - atan(z/-x);
		else if ( x <0.0 && z==0.0 ) theta = 1.0*M_PI;
		else if ( x <0.0 && z <0.0 ) theta = M_PI + atan(-z/x);
		else if ( x==0.0 && z <0.0 ) theta = 1.5*M_PI;
		else if ( x >0.0 && z <0.0 ) theta = 2.0*M_PI - atan(-z/x);
		else if ( x >0.0 && z==0.0 ) theta = 0.0;
		// else: impossible!
		
		if ( ndim==2 ) {
		    rays_.push_back( new RayTracingRay2D( theta, phi, domega, origin_ ) );
		}
		else if ( ndim==3 ) {
		    rays_.push_back( new RayTracingRay3D( theta, phi, domega, origin_ ) );
		}
	    }
	}
    }
    // Done.	
}

DiscreteTransferCell::~DiscreteTransferCell() {}

MonteCarloCell::MonteCarloCell( Gas_data * Q, double * Q_rE_rad, Vector3 origin, double vol, double area )
: RayTracingCell( Q, Q_rE_rad, origin, vol, area )
{
   // Rays are initialised later
}
MonteCarloCell::~MonteCarloCell() {}

/* RayTracingInterface class definitions */

RayTracingInterface::RayTracingInterface( Gas_data * Q, Vector3 origin,
        double area, double length, double epsilon )
: Q_( Q ), origin_( origin ), area_( area ), length_( length ),
  epsilon_( epsilon )
{
    // 0. Initialise SpectralIntensity
    S_ = new SpectralIntensity();
    
    // 1. Initialise BinnedSpectralIntensity to zero as it may not be used
    U_ = 0;

    // NOTE: - not computing spectra until DiscreteTransfer::compute_Q_rad_for_flowfield()
    //         is called
}

RayTracingInterface::~RayTracingInterface()
{
    // 1. delete SpectralIntensity
    delete S_;
    
    // 1. delete BinnedSpectralIntensity
    if ( U_ ) delete U_;

    // 2. delete all rays
    for ( size_t ir=0; ir<rays_.size(); ++ir )
    	delete rays_[ir];
}

void RayTracingInterface::recompute_spectra( RadiationSpectralModel * rsm ) 
{
    if ( rsm->get_spectral_points()==1 ) {
	// This is the equilibrum air model
	S_->nu.resize( 1, 1.0 );
        S_->I_nu.resize( 1, 0.0 );
        S_->I_int.resize( 1, 0.0 );

        double T = Q_->T[0];
        S_->I_nu[0] = RC_sigma_SI * pow( T, 4 ) / 4.0 / M_PI;
        S_->I_int[0] = S_->I_nu[0];
    }
    else {
        rsm->radiative_spectral_grid( S_->nu );
        S_->I_nu.resize( S_->nu.size(), 0.0 );
        S_->I_int.resize( S_->nu.size(), 0.0 );
    
        double T = Q_->T[0];
        double I_total = 0.0;
        for ( size_t inu=0; inu<S_->nu.size(); ++inu ) {
    	    S_->I_nu[inu] = planck_intensity( S_->nu[inu], T );
    	    if ( inu>0 ) I_total += 0.5 * ( S_->I_nu[inu] + S_->I_nu[inu-1] ) * fabs(S_->nu[inu]-S_->nu[inu-1]);
    	    S_->I_int[inu] = I_total;
        }
    }
    
    return;
}

void RayTracingInterface::set_CFD_cell_indices( size_t ii, size_t jj, size_t kk )
{
    ii_ = ii;
    jj_ = jj;
    kk_ = kk;
    
    return;
}

void RayTracingInterface::get_CFD_cell_indices( size_t &ii, size_t &jj, size_t &kk )
{
    ii = ii_;
    jj = jj_;
    kk = kk_;
    
    return;
}

void RayTracingInterface::write_rays_to_file( string filename )
{
    ofstream outfile;
    outfile.open( filename.c_str() );
    outfile << setprecision(12) << showpoint << scientific;
    outfile << "# Column 1: x coord (m)" << endl
            << "# Column 2: y coord (m)" << endl
            << "# Column 3: z coord (m)" << endl;
            
    for ( size_t iray=0; iray<rays_.size(); ++iray ) {
    	RayTracingRay * ray = rays_[iray];
    	outfile << "# iray = " << iray << endl;
    	for ( size_t ip=0; ip<ray->points_.size(); ++ip ) {
    	    RayTracingPoint * point = ray->points_[ip];
    	    Vector3 p = ray->get_point_on_line( point->s_ );
    	    outfile << setw(20) << p.x << setw(20) << p.y << setw(20) << p.z << endl;
    	}
    }
    
    outfile.close();
    
    return;
}

DiscreteTransferInterface::DiscreteTransferInterface( Gas_data * Q,
        Vector3 origin, double area, double length, double epsilon,
        size_t nrays, size_t ndim, bool planar )
: RayTracingInterface( Q, origin, area, length, epsilon )
{
    if ( nrays > 0 ) {
	if ( planar == true ) {
	    // uniform planar ray distribution
	    double alpha = 0.0, theta = 0.0, phi = 0.0, domega = 0.0;
	    for ( size_t iray=0; iray<nrays; ++iray ) {
		alpha = 2.0 * M_PI * iray / nrays;
		if ( alpha>=0.0 && alpha<M_PI/2.0 ) {
		    theta = 0.0; phi = alpha;
		} else if ( alpha>=M_PI/2.0 && alpha<1.5*M_PI ) {
		    theta = M_PI; phi = M_PI - alpha;
		} else if ( alpha>=1.5*M_PI && alpha<2.0*M_PI ) {
		    theta = 0.0; phi = alpha - M_PI*2.0;
		}
		domega = fabs( cos( phi ) ) * 2.0 * M_PI / double( nrays ) * M_PI ;
		rays_.push_back( new RayTracingRay2D( theta, phi, domega, origin_ ) );
	    }
	} else {
	    // uniform 3D ray distribution - create rays via golden spiral method
	    vector<Vector3> pts;
	    double inc = M_PI * ( 3.0 - sqrt(5.0) );
	    double off = 2.0 / double(nrays);
	    double phi, theta = 0.0;
	    for ( size_t iray=0; iray<nrays; ++iray ) {
		double y = double(iray)*off - 1.0 + ( off/2.0 );
		double r = sqrt( 1.0 - y*y );
		phi = double(iray)*inc;
		pts.push_back( Vector3(cos(phi)*r, y, sin(phi)*r) );
	    }
	    
	    // Extract angles in our coordinate system
	    double domega = 4.0 * M_PI / double ( nrays );
	    for ( size_t iray=0; iray<nrays; ++iray ) {
		double x=pts[iray].x, y=pts[iray].y, z=pts[iray].z;
		double L = vabs( pts[iray] );
		phi = asin( y / L );
		// calculate theta
		if      ( x >0.0 && z >0.0 ) theta = atan(z/x);
		else if ( x==0.0 && z >0.0 ) theta = 0.5*M_PI;
		else if ( x <0.0 && z >0.0 ) theta = M_PI - atan(z/-x);
		else if ( x <0.0 && z==0.0 ) theta = 1.0*M_PI;
		else if ( x <0.0 && z <0.0 ) theta = M_PI + atan(-z/x);
		else if ( x==0.0 && z <0.0 ) theta = 1.5*M_PI;
		else if ( x >0.0 && z <0.0 ) theta = 2.0*M_PI - atan(-z/x);
		else if ( x >0.0 && z==0.0 ) theta = 0.0;
		// else: impossible!
		
		if ( ndim==2 ) {
		    rays_.push_back( new RayTracingRay2D( theta, phi, domega, origin_ ) );
		}
		else if ( ndim==3 ) {
		    rays_.push_back( new RayTracingRay3D( theta, phi, domega, origin_ ) );
		}
	    }
	}
    }
    // Done.	
}

DiscreteTransferInterface::~DiscreteTransferInterface() {}

MonteCarloInterface::MonteCarloInterface( Gas_data * Q, Vector3 origin,
        double area, double length, double epsilon )
: RayTracingInterface( Q, origin, area, length, epsilon )
{
   // Rays are initialised later
}

MonteCarloInterface::~MonteCarloInterface() {}

