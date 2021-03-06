; Calculates the PDO pattern, timeseries, and spectra.
;
; Variables used: TS
;
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_code.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_csm.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/contributed.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/shea_util.ncl"
load "ncl_scripts/functions.ncl"

begin
  print("Running pdo.ncl")
  
  SCALE_TIMESERIES = getenv("SCALE_TIMESERIES")  
  OUTPUT_DATA      = getenv("OUTPUT_DATA")  
  PNG_SCALE        = tofloat(getenv("PNG_SCALE"))
  OPT_CLIMO        = getenv("OPT_CLIMO")
  CLIMO_SYEAR      = toint(getenv("CLIMO_SYEAR"))
  CLIMO_EYEAR      = toint(getenv("CLIMO_EYEAR"))
  CLIMO_FILE       = getenv("CLIMO_FILE")
  OUTPUT_TYPE      = getenv("OUTPUT_TYPE") 
  COLORMAP         = getenv("COLORMAP")  
  
  nsim = numAsciiRow("namelist_byvar/namelist_ts")
  na = asciiread("namelist_byvar/namelist_ts",(/nsim/),"string")
  names = new(nsim,"string")
  paths = new(nsim,"string")
  syear = new(nsim,"integer",-999)
  eyear = new(nsim,"integer",-999)
  delim = "|"

  do gg = 0,nsim-1
     names(gg) = str_strip(str_get_field(na(gg),1,delim))
     paths(gg) = str_strip(str_get_field(na(gg),2,delim))
     syear(gg) = stringtointeger(str_strip(str_get_field(na(gg),3,delim)))
     eyear(gg) = stringtointeger(str_strip(str_get_field(na(gg),4,delim)))
  end do
  nyr = eyear-syear+1
  nyr_max = max(nyr)

  pi=4.*atan(1.0)
  rad=(pi/180.)
         
  wks_type = OUTPUT_TYPE
  if (wks_type.eq."png") then
     wks_type@wkWidth = 1500*PNG_SCALE
     wks_type@wkHeight = 1500*PNG_SCALE
  end if
  wks = gsn_open_wks(wks_type,getenv("OUTDIR")+"pdo")
  wks2 = gsn_open_wks(wks_type,getenv("OUTDIR")+"pdo.powspec")
  wks3 = gsn_open_wks(wks_type,getenv("OUTDIR")+"pdo.timeseries")  
  if (COLORMAP.eq."0") then
     gsn_define_colormap(wks,"ncl_default")   
     gsn_define_colormap(wks2,"cb_9step")
     gsn_define_colormap(wks3,"ncl_default")
  end if
  if (COLORMAP.eq."1") then
     gsn_define_colormap(wks,"BlueDarkRed18")   
     gsn_define_colormap(wks2,"cb_9step")
     gsn_define_colormap(wks3,"ncl_default")
  end if
  map = new(nsim,"graphic")  
  pspec = new(nsim,"graphic")
  xyplot = new(nsim,"graphic")
  xyplot2 = new(nsim,"graphic")
  if (isfilepresent("obs_ts")) then
     pspec_obs = new(nsim,"graphic")
  end if
;  if (isfilepresent("obs_ts")) then
;     c1 = 1
;  else
;     c1 = 76
;  end if  
;  color = (/c1,2,6,11,5,3,7,15,23,31,39,47,55,63,71,79,2,6,11,5,3,7,15,23,31,39,47,55,63,71,79,2,6,11,5,3,7,15,23,31,39,47,55,63,71,79/)   
;  dash   = (/0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2/)   

  ; needed in loop
  d = addfile("$NCARG_ROOT/lib/ncarg/data/cdf/landsea.nc","r")   
  basemap = d->LSMASK
  
  ; read in external climatology before looping
  if (OPT_CLIMO.eq."External") then
      ;print("")
      ;print("   >>>   Opening External Climatology File: "+CLIMO_FILE)
      ;print("")
      climfile = addfile(CLIMO_FILE,"r") 
      climo = climfile->TS
      ;printVarSummary(climo)
      ; convert to Celsius, if necessary
      if (climo@units.eq."K".or.climo@units.eq."Kelvin") then   
        climo = climo-273.15
        climo@units = "C"
      end if
      ; mask land (and sea-ice?)
      climo = where(climo.le.-1.8,-1.8,climo)
      lsm = landsea_mask(basemap,climo&lat,climo&lon)
      climo = mask(climo,conform(climo,lsm,(/1,2/)).ge.1,False)
      delete([/lsm,climfile/])
      ;printVarSummary(climo)
  end if   
     
  do ee = 0,nsim-1
     ;print(paths(ee))
     sst = data_read_in(paths(ee),"TS",syear(ee),eyear(ee))    ; read in data, orient lats/lons correctly, set time coordinate variable up
     if (isatt(sst,"is_all_missing")) then
        delete(sst)
        continue
     end if
       
     if (isfilepresent("obs_ts").and.ee.eq.0) then   ; mask out land in array going into EOF functions
        if (OPT_CLIMO.eq."Full") then
            sst = rmMonAnnCycTLL(sst)
        else
            ; obs require special treatment, because they are on a different grid!
            obs_syr = 1979 ; no obs in future... but use same period length!
            obs_eyr = 1979 + CLIMO_EYEAR - CLIMO_SYEAR
            check_custom_climo(names(ee),syear(ee),eyear(ee),obs_syr,obs_eyr)
            obsclm = clmMonTLL(sst({obs_syr*100+1:obs_eyr*100+12},:,:))                 
            ;printVarSummary(sst)        
            sst   = calcMonAnomTLL(sst,obsclm) 
            delete(obsclm)
        end if
     else
        sst = where(sst.le.-1.8,-1.8,sst)
        ;d = addfile("$NCARG_ROOT/lib/ncarg/data/cdf/landsea.nc","r")   
        ;basemap = d->LSMASK
        lsm = landsea_mask(basemap,sst&lat,sst&lon)
        sst = mask(sst,conform(sst,lsm,(/1,2/)).ge.1,False)
        delete(lsm)         
        if (OPT_CLIMO.eq."Full") then
            sst = rmMonAnnCycTLL(sst)
        else
            if (OPT_CLIMO.eq."Custom") then
              check_custom_climo(names(ee),syear(ee),eyear(ee),CLIMO_SYEAR,CLIMO_EYEAR)
              climo = clmMonTLL(sst({CLIMO_SYEAR*100+1:CLIMO_EYEAR*100+12},:,:))                 
            end if
            ;printVarSummary(sst)        
            sst   = calcMonAnomTLL(sst,climo) 
        end if      
     end if    
  
     coswgt=cos(rad*sst&lat)
     coswgt!0 = "lat"
     coswgt&lat= sst&lat
    
     do ff = 0,dimsizes(sst&time)-1
        sst(ff,:,:) = (/ sst(ff,:,:) - wgt_areaave(sst(ff,{-60:70},:),coswgt({-60.:70.}),1.0,0) /)
     end do
     delete(coswgt)
     sst2 = sst(lat|:,lon|:,time|:)
     delete(sst)
     sst_CW= SqrtCosWeight(sst2(time|:,lat|:,lon|:))
  
     evecv = eofunc(sst_CW({lat|20:70},{lon|110:260},time|:),4,75)
     delete(sst_CW)
     pcts = eofunc_ts(sst2({20:70},{110:260},:),evecv,False)
     pctsS = dim_standardize(pcts(0,:),0)
     pcvari = evecv@pcvar
     finarr = sst2(:,:,0)
     finarr = finarr@_FillValue
     delete(evecv)

     finarr = (/ regCoef(pctsS,sst2) /)
     finarr@syear = syear(ee)
     finarr@eyear = eyear(ee)

     pdo = finarr
     pc1 = pctsS
     pc1!0 = "time"
     pc1&time = sst2&time
     pc1@ts_mean = pcts@ts_mean(0) ; save the mean of the time-series (before normalization)
     delete(pcts)
     pcvari = decimalPlaces(pcvari(0),0,True)     
     if (pdo({37},{200}).lt.0) then   ; arbitrary attempt to make all plots have the same sign..
        pdo = pdo*-1.
        pc1 = pc1*-1.
     end if
     delete([/sst2,pctsS,finarr/])
;---------------------------------------------------------------------------------------------     
     if (OUTPUT_DATA.eq."True") then
        modname = str_sub_str(names(ee)," ","_")
        fn = getenv("OUTDIR")+modname+".cvdp_data."+syear(ee)+"-"+eyear(ee)+".nc"
        if (.not.isfilepresent(fn)) then
           z = addfile(fn,"c")
           z@source = systemfunc("pwd")+"/"+get_script_name()
           z@notes = "Data from "+names(ee)+" from "+syear(ee)+"-"+eyear(ee)
           if (OPT_CLIMO.eq."Full") then
              z@climatology = syear(ee)+"-"+eyear(ee)+" climatology removed prior to all calculations (other than means)"
           else if (OPT_CLIMO.eq."External") then
              z@climatology = "An external climatology from "+CLIMO_SYEAR+"-"+CLIMO_EYEAR+" was removed prior to all calculations (other than means)"              
              z@clim_file = CLIMO_FILE
           else
              z@climatology = CLIMO_SYEAR+"-"+CLIMO_EYEAR+" climatology removed prior to all calculations (other than means)"
           end if
           end if
        else
           z = addfile(fn,"w")
        end if
        z->pdo_pattern_mon = pdo
        z->pdo_timeseries_mon = pc1
        delete(z)
        delete([/modname,fn/])
     end if              
;------------------------------------------------------------------------
     iopt = 0
     jave = (7*nyr(ee))/100
     val1 = .95
     val2 = .99
     if (jave.eq.0) then
       jave = 1
     end if
     pct = 0.1    
     spectra_mvf = False        ; missing value flag for nino3.4
     if (any(ismissing(pc1))) then
        print("Missing data detected for "+names(ee)+", power spectra function does not allow missing data, not creating PDO spectra")
        spectra_mvf = True
        if (isfilepresent("obs_ts").and.ee.eq.0) then
           spectra_mvf_obs = True    ; missing value flag for obs nino3.4
        end if
     else
        if (isfilepresent("obs_ts").and.ee.eq.0) then
           spectra_mvf_obs = False   ; missing value flag for obs nino3.4
        end if 
        sdof = specx_anal(pc1,iopt,jave,pct)   ; pc1 already standardized
        splt1 = specx_ci(sdof,val1,val2)
        if (isfilepresent("obs_ts").and.ee.eq.0) then
           sdof_obs = sdof
        end if
        delete([/iopt,jave,pct/])
     end if
;========================================================================
     res = True
     res@mpProjection = "WinkelTripel"
     res@mpGeophysicalLineColor = "gray42"
     res@mpPerimOn    = False
     res@mpGridLatSpacingF =  90            ; change latitude  line spacing
     res@mpGridLonSpacingF = 180.           ; change longitude line spacing
     res@mpGridLineColor   = "transparent"  ; trick ncl into drawing perimeter
     res@mpGridAndLimbOn   = True           ; turn on lat/lon lines  
     res@mpFillOn = False
     res@mpCenterLonF = 210.
     res@mpOutlineOn = True  
     res@mpDataSetName = "Earth..4"
     res@gsnDraw      = False
     res@gsnFrame     = False
     res@vpYF = 0.95
     res@vpHeightF = 0.3
     res@vpXF = 0.2
     res@vpWidthF = 0.6
  
;     res@cnFillMode = "RasterFill"
     res@cnLevelSelectionMode = "ExplicitLevels"
     
     if (COLORMAP.eq."0") then
        res@cnLevels = fspan(-.65,.65,27)
     end if
     if (COLORMAP.eq."1") then
        res@cnLevels = fspan(-.8,.8,17)
     end if

     res@cnLineLabelsOn = False
     res@cnFillOn        = True
     res@cnLinesOn       = False
     res@lbLabelBarOn    = False

     res@gsnLeftStringOrthogonalPosF = -0.05
     res@gsnLeftStringParallelPosF = .005
     res@gsnRightStringOrthogonalPosF = -0.05
     res@gsnRightStringParallelPosF = 0.96
     res@gsnRightString = ""
     res@gsnLeftString = ""
     res@gsnLeftStringFontHeightF = 0.014
     res@gsnCenterStringFontHeightF = 0.018
     res@gsnRightStringFontHeightF = 0.014
     res@gsnLeftString = syear(ee)+"-"+eyear(ee)
 
     res@gsnRightString = pcvari(0)+"%"
     res@gsnCenterString = names(ee)
     map(ee) = gsn_csm_contour_map(wks,pdo,res)
     
     if (isfilepresent("obs_ts").and.ee.eq.0) then    ; for pattern correlation table
        patcor = new((/nsim,dimsizes(pdo&lat),dimsizes(pdo&lon)/),typeof(pdo))
        patcor!1 = "lat"
        patcor&lat = pdo&lat
        patcor!2 = "lon"
        patcor&lon = pdo&lon
        patcor(ee,:,:) = (/ pdo /)
     end if
     if (isfilepresent("obs_ts").and.ee.ge.1) then
        patcor(ee,:,:) = (/ linint2(pdo&lon,pdo&lat,pdo,True,patcor&lon,patcor&lat,0) /)
     end if
     delete([/pcvari,pdo/])
     
     pres = True
     pres@vpXF = 0.07
     pres@trYMinF = 0.
     pres@trXMinF = 0.0
;     pres@trYMaxF = 82.
     pres@trXMaxF = 0.0832
     pres@tiYAxisString = "Power"              ; yaxis
     pres@xyLineColor   =  "black"         
     pres@gsnFrame      = False
     pres@gsnDraw       = False
  
     pres@tmXBLabelDeltaF = -.8
     pres@tmXTLabelDeltaF = -.8
     pres@pmLegendDisplayMode    = "Never"
     pres@xyLineThicknesses   = (/3.5,2.,1.,1./) 
     pres@xyDashPatterns      = (/0,0,0,0/)
     pres@xyLineColors        = (/"foreground","red","blue","green"/)      
     pres@xyLabelMode = "custom"
     pres@xyLineLabelFontColors = pres@xyLineColors 
     pres@xyExplicitLabels = (/"","",val1*100+"%",val2*100+"%"/)
     pres@tmXTOn = True
     pres@tmYROn = False
     pres@tmXTLabelsOn = True
     pres@tmXUseBottom = False
     pres@tmXTMode   = "Explicit"  
     pres@tmXBMode   = "Explicit"            
     pres@tmXTValues = (/".00167",".00833",".01667",".02778",".0416",".0556",".0832"/)
     pres@tmXTLabels = (/"50","10","5","3","2","1.5","1"/)           
     pres@tmXBValues = (/".0",".01",".02",".03",".042",".056",".083"/)
     pres@tmXBLabels =     pres@tmXBValues
     pres@tmXTLabelFontHeightF = 0.018
     pres@tmXBLabelFontHeightF = 0.018
     pres@tmYLLabelFontHeightF = 0.018
     pres@tiYAxisString = "Variance" ;"Power (~S~o~N~C~S~2~N~ / cycles mo~S~-1~N~)"              ; yaxis
     pres@tiXAxisString = "Frequency (cycles mo~S~-1~N~)"
     pres@tiMainString = ""
     pres@txFontHeightF = 0.015
     pres@xyLineLabelFontHeightF = 0.022
     pres@tiXAxisFontHeightF = 0.025
     pres@tiYAxisFontHeightF = 0.025
     pres@tiMainFontHeightF = 0.03
     
     pres@tiMainOn = False
     pres@gsnCenterString = "Period (years)"
     pres@gsnCenterStringFontHeightF =    pres@tiYAxisFontHeightF
     pres@gsnRightString = ""
     pres@gsnLeftString = "" 
     if (wks_type.eq."png") then
        pres@xyLineThicknessF   = 3.5
        res@mpGeophysicalLineThicknessF = 2.  
     else
        pres@xyLineThicknessF   = 1.5
        res@mpGeophysicalLineThicknessF = 1.  
     end if
     pres@gsnCenterString = names(ee)
     if (spectra_mvf.eq.False) then
        pspec(ee) = gsn_csm_xy(wks2,sdof@frq,splt1,pres) 
     
        if (isfilepresent("obs_ts").and.ee.ge.1.and.spectra_mvf_obs.eq.False) then
           pres@xyLineColors        = (/"gray70","black","black","black"/)
           pres@gsnCenterString = ""
           pspec_obs(ee) = gsn_csm_xy(wks2,sdof_obs@frq,sdof_obs@spcx,pres)
           overlay(pspec(ee),pspec_obs(ee)) 
        end if     
        delete([/sdof,splt1/])
     end if 
     
     xyres = True
     xyres@gsnDraw = False
     xyres@gsnFrame = False
;     xyres@trYMinF = -.65
;     xyres@trYMaxF = .65
;     xyres@tmYLFormat = "f"
;     xyres@tmYLMode = "Explicit"
;     xyres@tmYLValues = (/-0.5,-0.25,0,0.25,0.5/)
;     xyres@tmYLLabels = (/"-0.5","-0.25","0","0.25","0.5"/)
;     xyres@tmYLMinorValues = fspan(-1,1,41)
     xyres@gsnRightString = ""
     xyres@gsnLeftString = ""
     xyres@gsnFrame = False
     xyres@gsnYRefLine = 0.0
     xyres@gsnYRefLineColor = "gray42"
     xyres@gsnXYBarChart = False
     xyres@gsnAboveYRefLineColor = 185
     xyres@gsnBelowYRefLineColor = 35
     xyres@xyLineThicknessF = 0.1
;     xyres@xyLineColors = (/   xyres@gsnAboveYRefLineColor,   xyres@gsnBelowYRefLineColor/)
     xyres@xyLineColor = "gray70"
     xyres@tiYAxisString = ""
     if (nsim.le.5) then
        xyres@tmXBLabelFontHeightF = 0.0125
        xyres@tmYLLabelFontHeightF = 0.0125
        xyres@gsnStringFontHeightF = 0.017     
     else
        xyres@tmXBLabelFontHeightF = 0.018
        xyres@tmYLLabelFontHeightF = 0.018
        xyres@gsnStringFontHeightF = 0.024
     end if
     xyres@vpXF = 0.05
     xyres@vpHeightF = 0.15
     if (SCALE_TIMESERIES.eq."True") then
        xyres@vpWidthF = 0.9*((nyr(ee)*1.)/nyr_max)
     else
        xyres@vpWidthF = 0.9
     end if
     xyres@gsnCenterString = ""
     
     xyres@trXMinF = syear(ee)-.5
     xyres@trXMaxF = eyear(ee)+1.5
     
     xyres2 =    xyres
     delete(xyres2@gsnXYBarChart)
     delete(xyres2@gsnAboveYRefLineColor)
     delete(xyres2@gsnBelowYRefLineColor)
;     delete(xyres2@xyLineColors)
     xyres2@xyLineColor = "black"
     if (wks_type.eq."png") then
        xyres2@xyLineThicknessF = 3.5
     else
        xyres2@xyLineThicknessF = 2.5
     end if

     xyres@gsnCenterString = names(ee)
     xyplot(ee) = gsn_csm_xy(wks3,fspan(syear(ee),eyear(ee)+.91667,dimsizes(pc1)),pc1,xyres)   ; use standardized timeseries  
     xyplot2(ee) = gsn_csm_xy(wks3,fspan(syear(ee),eyear(ee)+.91667,dimsizes(pc1)),runave(pc1,61,0),xyres2)
     overlay(xyplot(ee),xyplot2(ee))
     
     delete([/val1,val2,pc1/])
  end do
  delete([/d,basemap/]) ; used before and through-out the loop
  if (OPT_CLIMO.eq."Custom".or.OPT_CLIMO.eq."External") then 
      delete(climo) 
  end if


  if (isfilepresent("obs_ts")) then    ; for pattern correlation table  
     clat = cos(0.01745329*patcor&lat)
     finpr   = "PDO (Monthly)     "    ; Must be 18 characters long
     line3   = "                  "    ; Must be 18 characters long
     line4   = line3
     do hh = 1,nsim-1
        dimY = dimsizes(tochar(names(hh)))
        nchar = dimY
        nchar = where(nchar.le.10,10,nchar)
        if (dimY.lt.10) then
           ntb = ""
           do ii = 0,10-dimY-1
              ntb = ntb+" "
           end do
           ntb = ntb+names(hh)
        else
           ntb = names(hh)
        end if
        
        ntc = ""
        do ii = 0,nchar-1
           ntc = ntc+"-"
        end do
        format2 = "%"+(nchar-5+1)+".2f"
        format3 = "%4.2f"
        line3 = line3+" "+ntb   
        line4 = line4+" "+ntc 
        if (all(ismissing(patcor(hh,:,:)))) then
           finpr = finpr+sprintf(format2,9.99)+"/"+sprintf(format3,9.99)
        else
           finpr = finpr+sprintf(format2,(pattern_cor(patcor(0,:,:),patcor(hh,:,:),clat,0)))+"/"+sprintf(format3,(dim_rmsd(ndtooned(NewCosWeight(patcor(0,:,:))),ndtooned(NewCosWeight(patcor(hh,:,:))))))
        end if
     end do
     if (.not.isfilepresent(getenv("OUTDIR")+"metrics_orig.txt")) then
        header = (/"","Pattern Correlations/RMS Differences   Observations vs. Model(s)",""/)
        write_table(getenv("OUTDIR")+"metrics_orig.txt","w",[/header/],"%s")
        write_table(getenv("OUTDIR")+"metrics_orig.txt","a",[/line3/],"%s")
        write_table(getenv("OUTDIR")+"metrics_orig.txt","a",[/line4/],"%s")
        delete(header)
     end if
     write_table(getenv("OUTDIR")+"metrics_orig.txt","a",[/finpr/],"%s")
     delete([/finpr,line3,line4,format2,format3,nchar,ntc,clat,patcor,dimY,ntb/])
  end if

  panres = True
  panres@gsnMaximize = True
  panres@gsnPaperOrientation = "portrait"
  panres@gsnPanelLabelBar = True
  panres@gsnPanelYWhiteSpacePercent = 3.0
  panres@pmLabelBarHeightF = 0.05
  panres@pmLabelBarWidthF = 0.55
  panres@lbTitleOn = False
  panres@lbBoxLineColor = "gray70"
  if (nsim.le.5) then
     panres@txFontHeightF = 0.024
  else
     panres@txFontHeightF = 0.016
  end if  
  panres@txString = "PDO (Monthly)"
  ncol = floattointeger(sqrt(nsim))
  nrow = (nsim/ncol)+mod(nsim,ncol)  
  gsn_panel(wks,map,(/nrow,ncol/),panres)
  delete(wks)

  delete(panres@gsnPanelLabelBar)
  panres@txString = "PDO (Monthly)"
  gsn_panel(wks2,pspec,(/nrow,ncol/),panres)  
  delete(wks2)
  
  if (SCALE_TIMESERIES.eq."True") then
     tt = ind(nyr.eq.nyr_max)
     panres@gsnPanelScalePlotIndex = tt(0)
     delete(tt)
  end if
  if (nsim.le.8) then
     lp = (/nsim,1/)
  else
     lp = (/nsim/2+1,nsim/8+1/)  
  end if
  panres@txString = "PDO (Monthly)"
  gsn_panel(wks3,xyplot,lp,panres)  
  delete(wks3)
  delete([/map,pspec,syear,eyear,nyr,nyr_max,lp/])
end
    
