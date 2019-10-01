

substrate_carstm = function( p=NULL, DS=NULL, sppoly=NULL, redo=FALSE, map_results=FALSE, ... ) {

  #\\ Note inverted convention: depths are positive valued
  #\\ i.e., negative valued for above sea level and positive valued for below sea level

  # ---------------------
  # deal with additional passed parameters
  if ( is.null(p) ) p=list()
  p_add = list(...)
  if (length(p_add) > 0 ) p = c(p, p_add)
  i = which(duplicated(names(p), fromLast = TRUE ))
  if ( length(i) > 0 ) p = p[-i] # give any passed parameters a higher priority, overwriting pre-existing variable





  if ( DS=="carstm_inputs") {

    fn = file.path( p$modeldir, paste( "substrate", "carstm_inputs", p$auid, "rdata", sep=".") )
    if (!redo)  {
      if (file.exists(fn)) {
        load( fn)
        return( S )
      }
    }

    # prediction surface
    if (is.null(sppoly)) sppoly = areal_units( p=p )  # will redo if not found

    # do this immediately to reduce storage for sppoly (before adding other variables)
    M = substrate.db ( p=p, DS="aggregated_data" )  # 16 GB in RAM just to store!
    names(M)[which(names(M)=="substrate.grainsize.mean" )] = "substrate.grainsize"

    # reduce size
    M = M[ which( M$lon > p$corners$lon[1] & M$lon < p$corners$lon[2]  & M$lat > p$corners$lat[1] & M$lat < p$corners$lat[2] ), ]
    # levelplot(substrate.grainsize.mean~plon+plat, data=M, aspect="iso")

    crs_lonlat = sp::CRS(projection_proj4string("lonlat_wgs84"))
    M$StrataID = over( SpatialPoints( M[, c("lon", "lat")], crs_lonlat ), spTransform(sppoly, crs_lonlat ) )$StrataID # match each datum to an area

    M$lon = NULL
    M$lat = NULL
    M$plon = NULL
    M$plat = NULL
    M = M[ which(is.finite(M$StrataID)),]
    M$tag = "observations"

    pb = p
    pb$modeldir = NULL  # resetting forces default bathymetry model dir to be used
    pb$project_name = NULL
    pb$data_root = NULL
    pb$datadir  = NULL
    pb = bathymetry_parameters(p=pb, DS="carstm")
    BI = bathymetry_carstm ( p=pb, DS="carstm_inputs" )  # unmodeled!
    jj = match( as.character( M$StrataID), as.character( BI$StrataID) )
    M$z = BI$z[jj]
    jj =NULL

    M = M[ which(is.finite(M$z)), ]

    BI = NULL

    sppoly_df = as.data.frame(sppoly)
    BM = bathymetry_carstm ( p=pb, DS="carstm_modelled" )  # unmodeled!
    kk = match( as.character(  sppoly_df$StrataID), as.character( BM$StrataID ) )
    sppoly_df$z = BM$z.predicted[kk]
    BM = NULL
    sppoly_df$substrate.grainsize = NA
    sppoly_df$StrataID = as.character( sppoly_df$StrataID )
    sppoly_df$tag ="predictions"

    vn = c("substrate.grainsize", "z", "tag", "StrataID")

    M = rbind( M[, vn], sppoly_df[, vn] )
    sppoly_df = NULL

    M$StrataID  = factor( as.character(M$StrataID), levels=levels( sppoly$StrataID ) ) # revert to factors

    save( M, file=fn, compress=TRUE )
    return( M )
  }

  # -----------------------



  if ( DS %in% c("carstm_modelled", "carstm_modelled_fit") ) {

    fn = file.path( p$modeldir, paste( "substrate", "carstm_modelled", p$auid, p$carstm_modelengine, "rdata", sep=".") )
    fn_fit = file.path( p$modeldir, paste( "substrate", "carstm_modelled_fit", p$auid, p$carstm_modelengine, "rdata", sep=".") )

    if (!redo)  {
      print( "Warning: carstm_modelled is loading from a saved instance ... add redo=TRUE if data needs to be refresh" )
      if (DS=="carstm_modelled") {
        if (file.exists(fn)) {
          load( fn)
          return( sppoly )
        }
      }
      if (DS=="carstm_modelled_fit") {
        if (file.exists(fn_fit)) {
          load( fn_fit )
          return( fit )
        }
      }
      print( "Warning: carstm_modelled load from saved instance failed ... " )
    }

    print( "Warning: carstm_modelled is being recreated ... " )
    print( "Warning: this needs a lot of RAM .. ~XX GB depending upon resolution of discretization .. a few hours " )


    # prediction surface
    if (is.null(sppoly)) sppoly = areal_units( p=p )  # will redo if not found

    M = substrate_carstm( p=p, DS="carstm_inputs" )  # will redo if not found
    fit  = NULL

    if ( grepl("glm", p$carstm_modelengine) ) {

      assign("fit", eval(parse(text=paste( "try(", p$carstm_modelcall, ")" ) ) ))
      if (is.null(fit)) error("model fit error")
      if ("try-error" %in% class(fit) ) error("model fit error")
      save( fit, file=fn_fit, compress=TRUE )

      # s = summary(fit)
      # AIC(fit)  # 104487274
      # reformat predictions into matrix form
      ii = which( M$tag=="predictions" & M$StrataID %in% M[ which(M$tag=="observations"), "StrataID"] )
      preds = predict( fit, newdata=M[ii,], type="link", na.action=na.omit, se.fit=TRUE )  # no/km2

      # out = reformat_to_matrix(
      #   input = preds$fit,
      #   matchfrom = list( StrataID=M$StrataID[ii] ),
      #   matchto   = list( StrataID=sppoly$StrataID  )
      # )
      # iy = match( as.character(sppoly$StrataID), aps$StrataID )
        sppoly@data[,"substrate.grainsize.predicted"] = exp( preds$fit)
        sppoly@data[,"substrate.grainsize.predicted_se"] = exp( preds$se.fit)
        sppoly@data[,"substrate.grainsize.predicted_lb"] = exp( preds$fit - preds$se.fit )
        sppoly@data[,"substrate.grainsize.predicted_ub"] = exp( preds$fit + preds$se.fit )
        save( sppoly, file=fn, compress=TRUE )
      }

      if ( grepl("gam", p$carstm_modelengine) ) {
        assign("fit", eval(parse(text=paste( "try(", p$carstm_modelcall, ")" ) ) ))
        if (is.null(fit)) error("model fit error")
        if ("try-error" %in% class(fit) ) error("model fit error")
        save( fit, file=fn_fit, compress=TRUE )

        s = summary(fit)
        AIC(fit)  # 104487274
        # reformat predictions into matrix form
        ii = which( M$tag=="predictions" & M$StrataID %in% M[ which(M$tag=="observations"), "StrataID"] )
        preds = predict( fit, newdata=M[ii,], type="link", na.action=na.omit, se.fit=TRUE )  # no/km2
        sppoly@data[,"substrate.grainsize.predicted"] = exp( preds$fit)
        sppoly@data[,"substrate.grainsize.predicted_se"] = exp( preds$se.fit)
        sppoly@data[,"substrate.grainsize.predicted_lb"] = exp( preds$fit - preds$se.fit )
        sppoly@data[,"substrate.grainsize.predicted_ub"] = exp( preds$fit + preds$se.fit )
        save( sppoly, file=fn, compress=TRUE )
    }


    if ( grepl("inla", p$carstm_modelengine) ) {

      H = carstm_hyperparameters( sd(log(M$substrate.grainsize), na.rm=TRUE), alpha=0.5, median( log(M$substrate.grainsize), na.rm=TRUE) )

      M$zi = discretize_data( M$z, p$discretization$z )
      M$strata  = as.numeric( M$StrataID)
      M$iid_error = 1:nrow(M) # for inla indexing for set level variation

      assign("fit", eval(parse(text=paste( "try(", p$carstm_modelcall, ")" ) ) ))
      if (is.null(fit)) error("model fit error")
      if ("try-error" %in% class(fit) ) error("model fit error")
      save( fit, file=fn_fit, compress=TRUE )

      s = summary(fit)
      s$dic$dic  # 31225
      s$dic$p.eff # 5200

      plot(fit, plot.prior=TRUE, plot.hyperparameters=TRUE, plot.fixed.effects=FALSE )

      # reformat predictions into matrix form
      ii = which(M$tag=="predictions")
      jj = match(M$StrataID[ii], sppoly$StrataID)
      sppoly@data$substrate.grainsize.predicted = exp( fit$summary.fitted.values[ ii[jj], "mean" ])
      sppoly@data$substrate.grainsize.predicted_lb = exp( fit$summary.fitted.values[ ii[jj], "0.025quant" ])
      sppoly@data$substrate.grainsize.predicted_ub = exp( fit$summary.fitted.values[ ii[jj], "0.975quant" ])
      sppoly@data$substrate.grainsize.random_strata_nonspatial = exp( fit$summary.random$strata[ jj, "mean" ])
      sppoly@data$substrate.grainsize.random_strata_spatial = exp( fit$summary.random$strata[ jj+max(jj), "mean" ])
      sppoly@data$substrate.grainsize.random_sample_iid = exp( fit$summary.random$iid_error[ ii[jj], "mean" ])
      save( sppoly, file=fn, compress=TRUE )
    }


    if (map_results) {
      vn = "substrate.grainsize.predicted"
      brks = interval_break(X= sppoly[[vn]], n=length(p$mypalette), style="quantile")
      dev.new();  spplot( sppoly, vn, col.regions=p$mypalette, main=vn, at=brks, sp.layout=p$coastLayout, col="transparent" )
    }

    return( sppoly )

  }

}