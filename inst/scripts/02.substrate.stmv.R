
## NOTE:: substrate size is really only relevant for SSE/snowcrab domain right now as no
##        other data source has been found/identified
##        but working at the size of canada.east.highres for compatibility with bathymetry
## TODO:: add data collected by snow crab survey and any others for that matter


# about 1.5 hr
scale_ram_required_main_process = 2 # GB twostep / fft
scale_ram_required_per_process  = 1 # twostep / fft /fields vario ..  (mostly 0.5 GB, but up to 5 GB)
scale_ncpus = min( parallel::detectCores(), floor( (ram_local()- scale_ram_required_main_process) / scale_ram_required_per_process ) )

# nn hrs
interpolate_ram_required_main_process = 2 # GB twostep / fft
interpolate_ram_required_per_process  = 2  # twostep / fft /fields vario ..
interpolate_ncpus = min( parallel::detectCores(), floor( (ram_local()- interpolate_ram_required_main_process) / interpolate_ram_required_per_process ) )
interpolate_ncpus = 8

p = aegis.substrate::substrate_parameters(
  project_class="stmv",
  data_root = project.datadirectory( "aegis", "substrate" ),
  DATA = 'substrate.db( p=p, DS="stmv_inputs" )',
  spatial_domain = "canada.east.highres" ,
  spatial_domain_subareas = c( "canada.east", "SSE", "snowcrab", "SSE.mpa" ),
  inputdata_spatial_discretization_planar_km = 0.5, # 0.5==p$pres; controls resolution of data prior to modelling (km .. ie 20 linear units smaller than the final discretization pres)
  aegis_dimensionality="space",
  stmv_variables = list(Y="substrate.grainsize"),
  stmv_global_modelengine = "gam",
  stmv_global_modelformula = formula( paste(
    'substrate.grainsize ',
    ' ~ s( b.sdSpatial, k=3, bs="ts") + s( b.localrange, k=3, bs="ts") ',
    ' + s(log(z), k=3, bs="ts") + s(log(dZ), k=3, bs="ts") +s(log(ddZ), k=3, bs="ts") '
  ) ),
  stmv_global_family = gaussian(link="log"),
  stmv_local_modelengine="fft",  # currently the perferred approach
  stmv_fft_filter = "matern_tapered_modelled", #
  # stmv_lowpass_nu = 0.1,
  # stmv_lowpass_phi = stmv::matern_distance2phi( distance=0.25, nu=0.1, cor=0.5 ), # default p$res = 0.5;
  stmv_autocorrelation_fft_taper = 0.5,  # benchmark from which to taper
  stmv_autocorrelation_localrange = 0.1,  # for output to stats
  stmv_autocorrelation_basis_interpolation = c(0.25, 0.1, 0.05, 0.01 ),
  stmv_variogram_method = "fft",
  stmv_filter_depth_m = 0.1, # the depth covariate is input in m, so, choose stats locations with elevation > 0 m as being on land
  stmv_local_model_distanceweighted = TRUE,
  stmv_rsquared_threshold = 0.1, # lower threshold == ignore
  stmv_distance_statsgrid = 5, # resolution (km) of data aggregation (i.e. generation of the ** statistics ** )
  stmv_distance_prediction_limits =c( 4, 40 ), # range of permissible predictions km (i.e 1/2 stats grid to upper limit based upon data density)
  stmv_distance_scale = c( 5, 10, 25, 50, 75, 150 ), # km ... approx guess of 95% AC range
  stmv_nmin = 100, # stmv_nmin/stmv_nmax changes with resolution
  stmv_nmax = 400, # numerical time/memory constraint -- anything larger takes too much time .. anything less .. errors
  stmv_runmode = list(
    globalmodel = FALSE,
    scale = rep("localhost", scale_ncpus),
    interpolate = list(
      cor_0.25 = rep("localhost", interpolate_ncpus),
      cor_0.1 = rep("localhost", interpolate_ncpus-2),
      cor_0.05 = rep("localhost", max(1, interpolate_ncpus-3)),
      cor_0.01 = rep("localhost", max(1, interpolate_ncpus-3))
    ),
    interpolate_predictions = list(
      c1 = rep("localhost", max(1, interpolate_ncpus-1)),  # ncpus for each runmode
      c2 = rep("localhost", max(1, interpolate_ncpus-1)),  # ncpus for each runmode
      c3 = rep("localhost", max(1, interpolate_ncpus-2)),
      c4 = rep("localhost", max(1, interpolate_ncpus-3)),
      c5 = rep("localhost", max(1, interpolate_ncpus-4)),
      c6 = rep("localhost", max(1, interpolate_ncpus-4)),
      c7 = rep("localhost", max(1, interpolate_ncpus-5))
    ),
    restart_load = "interpolate_correlation_basis_0.01" ,  # only needed if this is restarting from some saved instance
    save_intermediate_results = TRUE,
    save_completed_data = TRUE # just a dummy variable with the correct name
  )
)


stmv( p=p )


# quick look of data
DATA = substrate.db( p=p, DS="stmv_inputs" )
dev.new(); surface( as.image( Z=DATA$input$substrate.grainsize, x=DATA$input[, c("plon", "plat")], nx=p$nplons, ny=p$nplats, na.rm=TRUE) )

predictions = stmv_db( p=p, DS="stmv.prediction", ret="mean" )
statistics  = stmv_db( p=p, DS="stmv.stats" )

# locations = DATA$output$LOCS # these are the prediction locations
locations = bathymetry.db(spatial_domain=p$spatial_domain, DS="baseline")

# comparisons
dev.new(); surface( as.image( Z=log(predictions), x=locations, nx=p$nplons, ny=p$nplats, na.rm=TRUE) )

# stats
(p$statsvars)
dev.new(); levelplot( (predictions) ~ locations[,1] + locations[,2], aspect="iso" )
dev.new(); levelplot( statistics[,match("nu", p$statsvars)]  ~ locations[,1] + locations[,2], aspect="iso" ) # nu
dev.new(); levelplot( statistics[,match("sdTot", p$statsvars)]  ~ locations[,1] + locations[,2], aspect="iso" ) #sd total
dev.new(); levelplot( statistics[,match("localrange", p$statsvars)]  ~ locations[,1] + locations[,2], aspect="iso" ) #localrange


# as the interpolation process is so expensive, regrid based off the above run
substrate.db( p=p, DS="complete.redo" )


# quick map
b = bathymetry.db(spatial_domain=p$spatial_domain, DS="baseline")
o = substrate.db( p=p, DS="complete" )
lattice::levelplot( log(o$substrate.grainsize) ~ plon +plat, data=b, aspect="iso")


# or a cleaner map:
# p = aegis_parameters()
substrate.figures( p=p, varnames=c( "s.ndata", "s.sdTotal", "s.sdSpatial", "s.sdObs" ), logyvar=FALSE, savetofile="png" )
substrate.figures( p=p, varnames=c( "substrate.grainsize", "s.localrange", "s.nu", "s.phi"), logyvar=TRUE, savetofile="png" )


# to summarize just the global model
o = stmv_db( p=p, DS="global_model" )
summary(o)
plot(o)
AIC(o)  # [1]  3263839.33


# Global model results:
Family: gaussian
Link function: log
Family: gaussian
Link function: log

Formula:
substrate.grainsize ~ s(b.sdSpatial, k = 3, bs = "ts") + s(b.localrange,
    k = 3, bs = "ts") + s(log(z), k = 3, bs = "ts") + s(log(dZ),
    k = 3, bs = "ts") + s(log(ddZ), k = 3, bs = "ts")

Parametric coefficients:
              Estimate Std. Error  t value   Pr(>|t|)
(Intercept) -0.9053906  0.0111006 -81.5626 < 2.22e-16

Approximate significance of smooth terms:
                    edf Ref.df           F    p-value
s(b.sdSpatial)  1.99628      2   304.92667 < 2.22e-16
s(b.localrange) 1.99992      2  4461.65359 < 2.22e-16
s(log(z))       1.99666      2 18144.34273 < 2.22e-16
s(log(dZ))      1.98167      2    26.51703 2.2327e-12
s(log(ddZ))     1.97150      2     7.92948 0.00031715

R-sq.(adj) =   0.14   Deviance explained = 13.8%
GCV = 5.6951  Scale est. = 5.695     n = 713021

