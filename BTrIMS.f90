!%%%%%%% AUTHORSHIP %%%%%%%
! This program was written by Jason P. Evans (UNSW) and modified by Chiara M. Holgate (ANU).
! Please seek permission before publishing all or part of this code, from jason.evans@unsw.edu.au and/or chiara.holgate@anu.edu.au.


!%%%%%%% PURPOSE %%%%%%%
! This program calculates the quasi-isentropic back trajectories of water vapor using a method based on Dirmeyer & Brubaker, 1999, "Contrasting evaporative moisture sources during the drought of 1988 and the flood of 1993", Journal of Geophysical Research, 104 D16 pg 19,383-19,397.
!
!%%%%%%% INPUT %%%%%%%
! Input data are taken from NARCliM output. 
! Data here:
! /srv/ccrc/data33/z3481416/CCRC-WRF3.6.0.5-SEB/ERA-Interim/R2_nudging/out/
! And copied to here: /g/data/hh5/tmp/w28/jpe561/back_traj/

!%%Model expects:%%
! % Data to range between 0deg and 360deg.
! % Rainfall: [mm], 3d.
! % Latent heat [W/m2], 3d, which is converted to evaporation by program.
! % Temperature: actual temperature [K], 4d.
! % Pressure: total pressure [Pa], 4d, where first vertical level is at the top of the model.
! % Surface pressure [Pa], 3d.
! % U,V wind speed [m/s] components, 4d. If you're using vertical wind speeds, you need W [m/s] too.
! % Water-equivalent variables: in wrf, this is QCLD, QRAIN, QSNOW, QICE, QVAPOR [kg/kg], 4d.


!%%%%%%% OUTPUT %%%%%%%
! The program outputs a daily 2d grid of water vapour contribution of each grid cell to each precipitation cell. 
! It also outputs the total rainfall depth in each cell where it rained, and the coordinates of each rain grid cell.
! 
! The output file is dimensioned (rec,lat,lon) where rec is the number of grid cells where it rained that day, 
! lat & lon are the sizes of the domain in the lat and lon directions. Attributes include location and time and amount 
! of precip in the pixel of interest (y,x,day,month,year,precip) each of which is a 1D array of length rec.
!

!%%%%%%% EXPLANATION OF TIME-RELATED VARIABLES %%%%%%%
! "set"   = user defined values
! "calcd" = calculated within program

! totdays =  number of days to run simulation forward, based on set start/end dates(calcd)
! totbtadays = number of days to back-track for (set)
! tstep = number of minutes for back-track time step (set)
! daytsteps = 1440/tstep = 48 = number of simulation time steps in a day (calcd)
! totsteps = daytsteps*(totbtadays+1) = total number of simulation time steps over period (calcd)
! datatstep = 180 = input file time step in minutes (set)
! datadaysteps = 1440/datatstep = 8 = number of input file time steps in a day (calcd)
! indatatsteps = datatstep/tstep = number of simulation time steps per input time step  (calcd)
! datatotsteps = (datadaysteps*(totbtadays+1)) + 1 = total number of input time steps over the back-track period (calcd)
!.............we want the event day + totbtadays before it + the time step after ! (ie 0 hour time step which is the last in each file)
! ttdataday = = ((tt-1)/indatatsteps) + 1 = position of parcel time step in input file (calcd)
! ttdata = datatotsteps - datadaysteps - 1 + ttdataday = input file time step from the beginning of the loaded files (calcd)


!%%%%%%% ASSUMPTIONS %%%%%%%
! All forms of water are included (vapour, rain, ice, snow, cloud water) in the parcel's mixing ratio. 
! The PBL is NOT split from the upper atmosphere, i.e. the whole column is assumed to be well-mixed at the time step scale.
! Height of parcel release is determined randomly from a humidity-weighted vertical profile, i.e the vertical distribution of water vapour indicates where the rain forms.
! Time of parcel release is determined randomly through a precipitation-weighted time profile.
! The only source of parcel moisture is surface evaporation.
! The only sink for parcel moisture is precipitation.
! Program assumes data ranges between 0deg and 360deg. 
! If input data of different structure is to be used for this program, subroutines (e.g. get_data, get_data_mixtot) will need to be changed. 
! Note that I have not checked the isentropic routines "implicit_back_traj" or potential temp routines. If you want to use that version of the program (instead of moving parcels vertically using w), then those routines will need to be thoroughly checked.

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

MODULE global_data

IMPLICIT NONE

SAVE

!
!*******user modified variables**********************
!

INTEGER :: sday,smon,syear    !start day for calculations
INTEGER :: edday,edmon,edyear !end day for calculations (Exclusive. Must be at least one day after start day)
INTEGER :: totdays
INTEGER, PARAMETER :: totbtadays = 15   !number of days of data to keep for bta; i.e. how far back in time to calc.
                                       !must be less than days you have input data for
INTEGER, PARAMETER :: tstep = 15   !number of minutes for back trajectory time step (simultion time step)
                      !must divide evenly into number of minutes in day 1440 and number of minutes in MM5 time step (here 180)
INTEGER, PARAMETER :: nparcels = 10   !set the number of parcels to release if it rains
REAL, PARAMETER :: minpre = 1   !min daily precip to deal with (mm)

INTEGER, PARAMETER :: bdy = 6   !boundary layers to ignore; trajectories will be tracked to this boundary

CHARACTER(LEN=50), PARAMETER :: diri = "/g/data/hh5/tmp/w28/jpe561/back_traj/" 
CHARACTER(LEN=50), PARAMETER :: diri_era5 = "/g/data/w28/jpe561/BTrIMS/"
! CHARACTER(LEN=50), PARAMETER :: diri = "/srv/ccrc/data03/z3131380/PartB/Masks/"
! CHARACTER(LEN=100), PARAMETER :: diro = "/g/data/xc0/user/Holgate/QIBT/exp02/"
CHARACTER(LEN=100) :: diro  
CHARACTER(LEN=100), PARAMETER :: dirdata_atm = "/g/data/hh5/tmp/w28/jpe561/back_traj/wrfout/"
CHARACTER(LEN=100), PARAMETER :: dirdata_era5 = "/g/data/rt52/era5/"
CHARACTER(LEN=100), PARAMETER :: dirdata_land = "/g/data/hh5/tmp/w28/jpe561/back_traj/wrfhrly/"  
! CHARACTER(LEN=100), PARAMETER :: dirdata_atm = "/srv/ccrc/data33/z3481416/CCRC-WRF3.6.0.5-SEB/ERA-Interim/R2_nudging/out/"
! CHARACTER(LEN=100), PARAMETER :: dirdata_land = "/srv/ccrc/data03/z3131380/PartB/NARCliM_postprocess/" 

INTEGER, PARAMETER :: numthreads = 48   !set the number of parallel openmp threads

LOGICAL, PARAMETER :: peak = .FALSE.	!does the daylist indicate storm peaks (TRUE) or whole days (FALSE)

LOGICAL, PARAMETER :: wshed = .TRUE. !only calculate trajectories for watershed

CHARACTER(LEN=50), PARAMETER :: fwshed = "NARCliM_AUS_land_sea_mask.nc"
CHARACTER(LEN=50), PARAMETER :: fwshed_era5 = "Pakistan_mask_int_to180.nc"
                                !set to "" if no watershed
                                !0 outside watershed, >0 inside

REAL, PARAMETER :: min_del_q = 0.0001    !the minimum change in parcel mixing ratio (kg/kg) to be considered "real"
REAL, PARAMETER :: delta_coord = 0.0001  ! 1/10000th degree - for floating point calculations

LOGICAL, PARAMETER :: eachParcel = .FALSE.   !output the data along the trajectory of each parcel


!****************************************************
!

INTEGER :: daytsteps,totsteps,indatatsteps,datadaysteps,datatotsteps
INTEGER :: dim_i,dim_j,dim_k,fdim_i,fdim_j,ssdim
INTEGER :: dim_i_start, dim_j_start, dim_k_start
INTEGER :: dim_i_end, dim_j_end, dim_k_end
INTEGER :: mon,year,dd,totpts
INTEGER :: day
! Additional variable to define the number of time intervals in the input data, now that the input data is monthly instead of daily
INTEGER :: datansteps


REAL, PARAMETER :: Lv = 2.25E6   !latent heat of vaporization of water (Jkg-1)
REAL, PARAMETER :: g = 9.8     !gravity (m.s-2)
REAL, PARAMETER :: P0 = 100000   !reference surface pressure (Pa)
REAL, PARAMETER :: Rd = 287.053   !ideal gas constant for dry air (J/kgK)
REAL, PARAMETER :: Cp = 1004.67   !heat capacity of air at constant pressure (J/kgK)
REAL, PARAMETER :: Rv = 461.5    !gas constant of water vapor (J/kgK)
REAL, PARAMETER :: Cl = 4400     !heat capacity of liquid water at ~-20C (J/kgK)
REAL, PARAMETER :: pi = 3.14159265
REAL, PARAMETER :: deg_dist = 111.   !average distance of 1 degree lat is assumed to be 111km
REAL, PARAMETER :: water_density = 1000 ! density of water (kg/m3)

END MODULE global_data


MODULE util

	IMPLICIT NONE

	CONTAINS

	SUBROUTINE handle_err(status)
	!---------------------------------
	! handle any errors from the fortran 90 netCDF interface
	!---------------------------------

		USE netcdf

		IMPLICIT NONE

		integer, intent (in) :: status

		print *,'status = ',status

		if(status /= nf90_noerr) then
			print *, trim(nf90_strerror(status))
			stop "Stopped"
		end if

	END SUBROUTINE handle_err

	!***********************************************************************

	INTEGER FUNCTION string_to_int(string)
	!------------------------------------------
	! converts a character string to an integer
	!--------------------------------------------

		IMPLICIT NONE

		character (len=*), intent(in) :: string

		! local constant
		integer, parameter :: zero = iachar("0")
		integer :: i,  sign, integ
		character (len=50) :: str

		str = trim(string)
		integ = 0

		select case (str(1:1))
		case ("-")
		  sign = -1
		  str = str(2:)
		case ("+")
		  sign = 1
		  str = str(2:)
		case ("0":"9")
		  sign = 1
		end select

		do i=len(trim(str)),1,-1
			select case (str(i:i))
				case ("0":"9")
					integ = integ + (iachar(string(i:i))-zero)*10**(len(trim(str))-i)
				case default
					print *, "cannot convert a non-integer character to an integer!!"
					return
			end select
		end do

		string_to_int = integ

	end FUNCTION string_to_int

	!***********************************************************************

	CHARACTER(LEN=50) FUNCTION int_to_string(integ)
	!----------------------------------------------
	! converts an integer to a character string
	!----------------------------------------------

		IMPLICIT NONE

		integer, intent(in) :: integ

		! local constant
		integer, parameter :: zero = iachar("0")
		character (len=50) :: str
		integer :: i, inte

		str="                                                  "
		inte = integ

		do i=1,50
			str(50-i:50-i) = achar(mod(abs(inte),10)+zero)
			inte = int(inte/10)
			if (abs(inte)<1) exit
		end do

		if (integ<0) str(50-i-1:50-i) = "-"

		int_to_string = adjustl(str)

	end FUNCTION int_to_string

	!***********************************************************************

	CHARACTER(LEN=50) FUNCTION real_to_string(num)
	!----------------------------------------------
	! converts an real to a character string
	! here I allow a maximum of 10 decimal places
	!----------------------------------------------

		IMPLICIT NONE

		!real, intent(in) :: num
		INTEGER, intent(in) :: num

		! local
		integer :: i, whole, frac
		real :: fracnum


		whole = num !AINT(num)
		fracnum = num - whole

		do i=1,10
			if (MOD(fracnum,1.)==0) exit
			fracnum = fracnum * 10.
		end do

		frac = AINT(fracnum)

		real_to_string = TRIM(int_to_string(whole))//"."//TRIM(int_to_string(frac))

	end FUNCTION real_to_string

	!***********************************************************************

	INTEGER FUNCTION julian(year,mon,day)

	! From http://aa.usno.navy.mil/faq/docs/JD_Formula.php

		IMPLICIT NONE
		INTEGER, INTENT(IN) :: year,mon,day

		julian= day-32075+1461*(year+4800+(mon-14)/12)/4+367*(mon-2-(mon-14)/12*12)/12-3*((year+4900+(mon-14)/12)/100)/4

	END FUNCTION julian

		!***********************************************************************

	SUBROUTINE GREGORIAN(JD,YEAR,MONTH,DAY)

	! From http://aa.usno.navy.mil/faq/docs/JD_Formula.php

		IMPLICIT NONE
		!REAL, INTENT(IN) :: JD
		INTEGER :: JD
		INTEGER, INTENT(OUT) :: YEAR, MONTH, DAY!, HOUR, MINUTE, SECOND
		REAL :: JT
		INTEGER :: I,J,K,L,N

		L = INT(JD)+68569!JD= K-32075+1461*(I+4800+(J-14)/12)/4+367*(J-2-(J-14)/12*12)/12-3*((I+4900+(J-14)/12)/100)/4
		N = 4*L/146097
		L = L-(146097*N+3)/4
		I = 4000*(L+1)/1461001
		L = L-1461*I/4+31
		J = 80*L/2447
		K = L-2447*J/80
		L = J/11
		J = J+2-12*L
		I = 100*(N-49)+I+L

		YEAR = I
		MONTH = J
		DAY = K

		! JT = DMOD(JD,1.D0)*24.D0
		! HOUR = INT(JT)
		! JT = DMOD(JT,1.D0)*60.D0
		! MINUTE = INT(JT)
		! JT = DMOD(JT,1.D0)*60.D0
		! SECOND = NINT(JT)
		!
		! IF (SECOND == 60) THEN
		! 	SECOND = SECOND-60
		! 	MINUTE = MINUTE+1
		! END IF

	END SUBROUTINE GREGORIAN

		!***********************************************************************

	INTEGER FUNCTION simlength(startday,startmon,startyear,endday,endmon,endyear)
	!-----------------------------------------------------
	! given the start and end dates of the desired simulation
	! period (top of global data), calculate the number of days
	! in the period

	! Functions: don't need to specify what comes out, e.g. fn_name(in,in,in)
	! Subroutines: do specify in and out, e.g. sbrtn_name(in,in,in,out,out)

	!-----------------------------------------------------
		USE global_data

		IMPLICIT NONE

		INTEGER, intent(in) :: startday,startmon,startyear,endday,endmon,endyear
		INTEGER :: start_jd, end_jd

		start_jd = julian(startyear,startmon,startday)
		end_jd = julian(endyear,endmon,endday)
		simlength = end_jd - start_jd

	END FUNCTION simlength

	!***********************************************************************

	SUBROUTINE day_month_year(simday)
	!----------------------------------------------
	! given the simulation day, calculate the corresponding month and year
	! simulation day one is the first day
	!-----------------------------------------------------

		USE global_data

		IMPLICIT NONE

		INTEGER,INTENT(IN) :: simday	!simulation day

		INTEGER :: jday,simdayyear,simdaymonth,simdayday

		if (simday==1) then
			year=syear
			mon=smon
			day=sday
		else
			! Find julian day of simday, being the start day + an increment of days
			jday=julian(syear,smon,sday)+(simday-1)
			! Convert the julian day to a gregorian day
		call gregorian(jday,simdayyear,simdaymonth,simdayday)
			year=simdayyear
			mon=simdaymonth
			day=simdayday
		end if

	END SUBROUTINE day_month_year

	!***********************************************************************

	SUBROUTINE all_positive_longitude(lon2d,lon2d_corrected)
		!------------------------------------------------
		! NARCliM longitude 2d grid (XLONG) is negative east of dateline.
		! This subroutine converts the negative values to positive.
		!------------------------------------------------

			REAL, DIMENSION(:,:) :: lon2d,lon2d_corrected

			lon2d_corrected=lon2d

			WHERE (lon2d < 0)
				lon2d_corrected = lon2d+360
			END WHERE

		END SUBROUTINE all_positive_longitude

	!***********************************************************************

	FUNCTION to_iso_date(y,m,d)
	!----------------------------------------------------
	! Convert year month day integers to iso date string
	!----------------------------------------------------

		INTEGER, INTENT(IN) :: y,m,d
		CHARACTER(len=8)    :: to_iso_date

		write(to_iso_date,'(i4.4,i2.2,i2.2)') y,m,d

	END FUNCTION to_iso_date

	FUNCTION month_end(y,m)
	!----------------------------------------------------
	! Lookup table for ends of months
	!----------------------------------------------------
		INTEGER, INTENT(IN) :: y,m
		INTEGER :: month_end

		SELECT CASE	(m)
			CASE(1,3,5,7,8,10,12)
				month_end = 31
				RETURN
			CASE(4,6,9,11)
				month_end = 30
				RETURN
		END SELECT

		IF ( MODULO(y,4) == 0 ) then
			IF ( MODULO(y,100) == 0 .and. MODULO(y,400) /= 0 ) then
				month_end = 28
				RETURN
			ELSE
				month_end = 29
				RETURN
			END IF
		ELSE
			month_end = 28
			RETURN
		END IF

	END FUNCTION month_end

	SUBROUTINE array_extents(arr,in_start,in_end,i_start,i_end,reverse,periodic)

		USE global_data, ONLY: delta_coord

		IMPLICIT NONE

		REAL, DIMENSION(:), INTENT(IN) :: arr
		REAL, INTENT(IN)               :: in_start, in_end
		INTEGER, INTENT(OUT)           :: i_start, i_end
		LOGICAL,OPTIONAL,INTENT(IN)    :: reverse
		LOGICAL,OPTIONAL,INTENT(IN)    :: periodic

		!!! Locals
		INTEGER :: i
		REAL :: start, end

		i_start = -1
		i_end   = -1
		if( .not.present(periodic) .or. .not.periodic ) then
			if ( in_start > in_end ) then
				!!! Swap bounds if necessary
				end   = in_start
				start = in_end
			else
				start = in_start
				end   = in_end
			end if
		else
			start = in_start
			end   = in_end
		end if


		if( present(reverse) .and. reverse ) then
			do i=1,SIZE(arr)
				if ( i_start == -1 ) then
					if ( abs(arr(i) - end) < delta_coord ) i_start = i
				else if ( i_end == -1 ) then
					if ( abs(arr(i) - start) < delta_coord ) i_end = i
				else
					exit
				end if
			end do
		else
			do i=1,SIZE(arr)
				if ( i_start == -1 ) then
					if ( abs(arr(i) - start) < delta_coord ) i_start = i
				else if ( i_end == -1 ) then
					if ( abs(arr(i) - end) < delta_coord ) i_end = i
				else
					exit
				end if
			end do
		end if

		if ( i_start == -1 ) i_start = 1
		if ( i_end == -1 ) then
			if ( present(periodic) .and. periodic ) then
				!!! If we haven't found and 'end', check if we need to wrap around
				if ( end < start ) then
					!!! Redo the loop from the start
					do i=1,SIZE(arr)
						if ( i_end == -1 ) then
							if ( abs(arr(i) - end) < delta_coord ) i_end = i
						else
							exit
						end if
					end do
				else
					i_end = size(arr)
				end if
			else
				i_end = size(arr)
			end if
		end if

	END SUBROUTINE array_extents

END MODULE util

!**************************************************************
!****************************************************************

MODULE bt_subs

	IMPLICIT NONE

	CONTAINS

!***********************************************************************

	SUBROUTINE new_out_file(outncid,wvcid,wvc2id,xlocid,ylocid,dayid,opreid,daynum,lat2d,lon2d)
	!----------------------------------------------
	!create the output netcdf file and prepare it to accept data
	!--------------------------------------------------------

		USE global_data
		USE util
		USE netcdf

		IMPLICIT NONE

		INTEGER, INTENT(INOUT) :: outncid,wvcid,wvc2id,xlocid,ylocid,dayid,opreid
		!REAL, INTENT(IN) :: daynum
		INTEGER, INTENT(IN) :: daynum
		REAL,INTENT(IN),DIMENSION(:,:) :: lat2d,lon2d

		INTEGER :: status,jdimid,idimid,gwvcdimid,latid,lonid


		!
		!create the file
		!
		!differentiate whether we are doing whole days or around storm peaks
		if (peak) then
			print *,'we are doing peaks here!'
			if (mon<10) then
				status = nf90_create(TRIM(diro)//"bt."//TRIM(int_to_string(year))//"0" &
					//TRIM(int_to_string(mon))//"_"//TRIM(real_to_string(daynum))// &
					".nc",nf90_clobber,outncid)
				if (status /= NF90_NOERR) call handle_err(status)
			else
				status = nf90_create(TRIM(diro)//"bt."//TRIM(int_to_string(year)) &
					//TRIM(int_to_string(mon))//"_"//TRIM(real_to_string(daynum))// &
					".nc",nf90_clobber,outncid)
					if (status /= NF90_NOERR) call handle_err(status)
			end if
		else
			if (mon<10) then
				status = nf90_create(TRIM(diro)//"bt."//TRIM(int_to_string(year))//"0" &
				//TRIM(int_to_string(mon))//"_"//TRIM(int_to_string(INT(daynum)))// &
					".nc",nf90_clobber,outncid)
				if (status /= NF90_NOERR) call handle_err(status)
			else
				status = nf90_create(TRIM(diro)//"bt."//TRIM(int_to_string(year)) &
		  			//TRIM(int_to_string(mon))//"_"//TRIM(int_to_string(INT(daynum)))// &
					".nc",nf90_clobber,outncid)
				if (status /= NF90_NOERR) call handle_err(status)
			end if
		end if

		print *,'outfile=',TRIM(diro)//"bt."//TRIM(int_to_string(year))//"0" &
				//TRIM(int_to_string(mon))//"_"//TRIM(int_to_string(INT(daynum)))// &
				".nc"

		!
		!define dimensions
		!
		status = nf90_def_dim(outncid,"j_cross",dim_j,jdimid)
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_def_dim(outncid,"i_cross",dim_i,idimid)
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_def_dim(outncid,"gridcell_wvc",nf90_unlimited,gwvcdimid)
		if (status /= NF90_NOERR) call handle_err(status)

		!
		!define the variable
		!
		status = nf90_def_var(outncid,"wv_cont",nf90_float,(/jdimid,idimid,gwvcdimid/),wvcid)
		if (status /= NF90_NOERR) call handle_err(status)
		!turning off apbl output
                !status = nf90_def_var(outncid,"wv_cont_apbl",nf90_float,(/jdimid,idimid,gwvcdimid/),wvc2id)
		!if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_def_var(outncid,"x_loc",nf90_int,(/gwvcdimid/),xlocid)
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_def_var(outncid,"y_loc",nf90_int,(/gwvcdimid/),ylocid)
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_def_var(outncid,"day",nf90_float,(/gwvcdimid/),dayid)
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_def_var(outncid,"pre",nf90_float,(/gwvcdimid/),opreid)
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_def_var(outncid,"latitcrs",nf90_float,(/jdimid,idimid/),latid)
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_def_var(outncid,"longicrs",nf90_float,(/jdimid,idimid/),lonid)
		if (status /= NF90_NOERR) call handle_err(status)


		!
		!define attributes
		!
		status = nf90_put_att(outncid,wvcid,"long_name","Water Vapor Contribution")
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_put_att(outncid,wvcid,"units","proportion of precipitation")
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_put_att(outncid,wvcid,"num_boundary_layers",bdy)
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_put_att(outncid,wvcid,"parcels_per_grid_point",nparcels)
		if (status /= NF90_NOERR) call handle_err(status)

		!turn off apbl output
                !status = nf90_put_att(outncid,wvc2id,"long_name","Water Vapor Contribution above PBL")
		!if (status /= NF90_NOERR) call handle_err(status)
		!status = nf90_put_att(outncid,wvc2id,"units","proportion of precipitation")
		!if (status /= NF90_NOERR) call handle_err(status)
		!status = nf90_put_att(outncid,wvc2id,"num_boundary_layers",bdy)
		!if (status /= NF90_NOERR) call handle_err(status)
		!status = nf90_put_att(outncid,wvc2id,"parcels_per_grid_point",nparcels)
		!if (status /= NF90_NOERR) call handle_err(status)

		status = nf90_put_att(outncid,xlocid,"long_name","x index location of precipitation (from 0)")
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_put_att(outncid,ylocid,"long_name","y index location of precipitation (from 0)")
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_put_att(outncid,dayid,"long_name","days since "// &
			TRIM(int_to_string(sday))//"/"//TRIM(int_to_string(smon))//"/"// &
			TRIM(int_to_string(syear)))
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_put_att(outncid,opreid,"long_name","precipitation")
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_put_att(outncid,opreid,"units","mm")
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_put_att(outncid,latid,"long_name","LATITUDE (SOUTH NEGATIVE)")
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_put_att(outncid,latid,"units","degrees")
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_put_att(outncid,lonid,"long_name","LONGITUDE (WEST NEGATIVE)")
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_put_att(outncid,lonid,"units","degrees")
		if (status /= NF90_NOERR) call handle_err(status)


		!
		!leave define mode
		!
		status = nf90_enddef(outncid)


		status = nf90_put_var(outncid,latid,lat2d,start=(/1,1/),count=(/dim_j,dim_i/))
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_put_var(outncid,lonid,lon2d,start=(/1,1/),count=(/dim_j,dim_i/))
		if(status /= nf90_NoErr) call handle_err(status)

	END SUBROUTINE new_out_file

	!***********************************************************************

    

     

	!***********************************************************************  

	REAL FUNCTION lin_interp(var,fac)
	!---------------------------------------
	!linearly interpolate between the values of var
	!fac is the proporational distance from the first value
	!------------------------------------------

		IMPLICIT NONE

		REAL, INTENT(IN), DIMENSION(2) :: var
		REAL, INTENT(IN) :: fac

		lin_interp = var(1)*(1-fac) + var(2)*fac

	END FUNCTION lin_interp

	!***********************************************************************

	FUNCTION lin_interp2D(var,fac)
	!---------------------------------------
	!linearly interpolate between the values of var (last dimension must have size 2)
	!fac is the proporational distance from the first value
	!------------------------------------------

		IMPLICIT NONE

		REAL, INTENT(IN), DIMENSION(:,:,:) :: var
		REAL, INTENT(IN) :: fac

		REAL, DIMENSION(SIZE(var,1),SIZE(var,2)):: lin_interp2D

		lin_interp2D = var(:,:,1)*(1-fac) + var(:,:,2)*fac

	END FUNCTION lin_interp2D

	!***********************************************************************

	FUNCTION lin_interp3D(var,fac)
	!---------------------------------------
	!linearly interpolate between the values of var (last dimension must have size 2)
	!fac is the proporational distance from the first value
	!------------------------------------------

		IMPLICIT NONE

		REAL, INTENT(IN), DIMENSION(:,:,:,:) :: var
		REAL, INTENT(IN) :: fac

		REAL, DIMENSION(SIZE(var,1),SIZE(var,2),SIZE(var,3)) :: lin_interp3D

		lin_interp3D = var(:,:,:,1)*(1-fac) + var(:,:,:,2)*fac

	END FUNCTION lin_interp3D

	!***********************************************************************

	SUBROUTINE parcel_release_time(precip,npar,par_release)
	!---------------------------------------------------
	! here we calculate the times of day to release our parcels
	! based on a random precipitation weighted sampling
	!-----------------------------------------------------

		USE global_data

		IMPLICIT NONE

		REAL, DIMENSION(:), INTENT(IN) :: precip
		INTEGER, DIMENSION(:), INTENT(OUT) :: par_release
		INTEGER, INTENT(IN) :: npar

		REAL, DIMENSION(SIZE(precip)*indatatsteps) :: cumm_precip
		REAL, DIMENSION(npar) :: rand_nums
		INTEGER :: tt,rr,ss,rec


		par_release = 0

		call RANDOM_NUMBER(rand_nums)
		cumm_precip = 0.

		rec = 0

		do tt = 1,SIZE(precip)
			do ss = 1,indatatsteps
				rec = rec + 1
				if (rec==1) then
					cumm_precip(1) = precip(1)/indatatsteps
				else
					cumm_precip(rec) = cumm_precip(rec-1) + precip(tt)/indatatsteps
				end if
			end do
		end do

		cumm_precip = cumm_precip/cumm_precip(SIZE(cumm_precip))

		do rr = 1,npar
			do tt = 1,SIZE(cumm_precip)
				if (cumm_precip(tt)>rand_nums(rr)) then
					par_release(tt) = par_release(tt) + 1
					EXIT
				end if
			end do
		end do


	END SUBROUTINE parcel_release_time

	!***********************************************************************

	SUBROUTINE parcel_release_height(pw,par_lev)
	!----------------------------------------------
	! calculate the height to release the parcel from
	! based on precipitable water weighted random sampling
	!-----------------------------------------------

		IMPLICIT NONE

		REAL, INTENT(IN), DIMENSION(:) :: pw ! This is the precipitable water, accumulated from the ground up, in the column at that point in time.

		INTEGER, INTENT(OUT) :: par_lev

		REAL :: rand_num
		INTEGER :: kk

		call RANDOM_NUMBER(rand_num)

		! Take random number as a random proportion of the total pw in the column at that time; pw(1) is the pw at the top of the atm column, which represents the accumulated pw over the column below it (same as TPW).
		rand_num = rand_num*pw(1)

		do kk = SIZE(pw),1,-1 ! kk is then between 29 and 1
			if (pw(kk)>rand_num) then
				par_lev = kk
				EXIT
			end if
		end do

                !print *,"release height,pw, ",par_lev,pw

		! For testing purposes only: take random number as a purely random model level, not weighted by pw.
		!rand_num = 1 + FLOOR(size(pw)*rand_num)
		!par_lev = rand_num

	END SUBROUTINE parcel_release_height

	!***********************************************************************

	SUBROUTINE lin_interp_inMM5tsteps(var)
	!------------------------------------------
	!linearly interpolate through time inside MM5 time steps
	!----------------------------------------------

		USE global_data

		IMPLICIT NONE

		REAL, INTENT(INOUT), DIMENSION(:,:,:,:) :: var

		INTEGER :: i

		do i = 1,indatatsteps-1
		  var(:,:,:,i+1::indatatsteps) = (1-(i*1./indatatsteps))*var(:,:,:,1:datadaysteps+1-indatatsteps:indatatsteps) &
		                 & + (i*1./indatatsteps)*var(:,:,:,1+indatatsteps::indatatsteps)
		end do


	END SUBROUTINE lin_interp_inMM5tsteps

	!***********************************************************************

	SUBROUTINE calc_pw(mix,pres,surf_pres,ptop,pw)
	!------------------------------------------
	! calculate the precipitable water from input data fields
	! only for the day of current interest
	! save as accumulated field from the ground up (4D field)
	! This is used to calc parcel initial height.
	!-------------------------------------------------

		USE global_data

		IMPLICIT NONE

		REAL, INTENT(IN), DIMENSION(:,:,:,:) :: mix,pres
		REAL, INTENT(IN), DIMENSION(:,:,:) :: surf_pres
		REAL, INTENT(OUT), DIMENSION(:,:,:,:) :: pw

		REAL, DIMENSION(dim_j,dim_i,dim_k,SIZE(mix,4)) :: dp
		INTEGER :: k

		REAL, INTENT(IN) :: ptop

		!
		! calculate the change in pressure (Pa) represented by each point
		!
		!for highest level
		dp(:,:,1,:) = SUM(pres(:,:,:2,:),3)/2. - ptop

		
                !need to account for posibility that pressure levels go below the ground
                !for the middle levels
		do k = 2,dim_k-1
                        where (pres(:,:,k+1,:) <= surf_pres(:,:,:)) 
			        dp(:,:,k,:) = (pres(:,:,k+1,:) - pres(:,:,k-1,:)) /2. !dp(:,:,k,:) = SUM(pres(:,:,k-1:k+1:2,:),3)/2.
                        elsewhere (pres(:,:,k,:) <= surf_pres(:,:,:))
                                !for the lowest level above surface
                                dp(:,:,k,:) = surf_pres(:,:,:) - (pres(:,:,k,:) + pres(:,:,k-1,:))/2.
                        elsewhere
                                dp(:,:,k,:) = 0.
                        end where

		end do

		!for the lowest level
                where (pres(:,:,dim_k,:) <= surf_pres(:,:,:))
		        dp(:,:,dim_k,:) = surf_pres(:,:,:) - SUM(pres(:,:,dim_k-1:,:),3)/2.
                elsewhere
                        dp(:,:,dim_k,:) = 0.
                end where

		!mass in mm
		pw(:,:,:,::indatatsteps) = dp*mix/g

		!interpolate inside input data time steps
		call lin_interp_inMM5tsteps(pw)


		!accumulate from the bottom up. The precipitable water is then the total moisture in the column below it.
		do k = dim_k-1,1,-1             ! i.e. from level 28 to 1
			!pw(:,:,k,2:) = pw(:,:,k+1,2:) + pw(:,:,k,2:)! THE PW IS ACCUMULATED FROM THE SECOND TS ON, SO THE FIRST 10MIN IS NOT ACCUMULATED. WHY?? This only matters if tt=1. Here I change it to do all timesteps.
			pw(:,:,k,:) = pw(:,:,k+1,:) + pw(:,:,k,:)
		end do
		! print *,shape(pw)
		! print *,"pw ",pw(1,1,dim_k,:),surf_pres(1,1,1),ptop

	END SUBROUTINE calc_pw

	!***********************************************************************

	SUBROUTINE calc_tpw(mix,pres,surf_pres,ptop,tpw)
	!------------------------------------------
	! calculate the total precipitable water from input data fields
	! at every level and time (3D field)
	!-------------------------------------------------

		USE global_data

		IMPLICIT NONE

		REAL, INTENT(IN), DIMENSION(:,:,:,:) :: mix,pres
		REAL, INTENT(IN), DIMENSION(:,:,:) :: surf_pres
		REAL, INTENT(OUT), DIMENSION(:,:,:) :: tpw

		REAL, DIMENSION(dim_j,dim_i,dim_k,datatotsteps) :: dp
		INTEGER :: j,i,k,t

		REAL, INTENT(IN) :: ptop

		!
		! calculate the change in pressure (Pa) represented by each point
		!
		!for highest level
		dp(:,:,1,:) = SUM(pres(:,:,:2,:),3)/2. - ptop

		!for the middle levels
		!do k = 2,dim_k-1
		!	dp(:,:,k,:) = (pres(:,:,k+1,:) - pres(:,:,k-1,:)) /2.
		!	! equiv to (p2+p3)/2 - (p1+p2)/2 = (p3-p1)/2
		!end do

		!for the lowest level
		!dp(:,:,dim_k,:) = surf_pres(:,:,:) - SUM(pres(:,:,dim_k-1:,:),3)/2.

                !need to account for posibility that pressure levels go below the ground
                !for the middle levels
                do k = 2,dim_k-1
                        where (pres(:,:,k+1,:) <= surf_pres(:,:,:))
                                dp(:,:,k,:) = (pres(:,:,k+1,:) - pres(:,:,k-1,:)) /2. !dp(:,:,k,:) = SUM(pres(:,:,k-1:k+1:2,:),3)/2.
                        elsewhere (pres(:,:,k,:) <= surf_pres(:,:,:))
                                !for the lowest level above surface
                                dp(:,:,k,:) = surf_pres(:,:,:) - (pres(:,:,k,:) + pres(:,:,k-1,:))/2.
                        elsewhere
                                dp(:,:,k,:) = 0.
                        end where

                end do

                !for the lowest level also accounting for possibility of being below ground
                where (pres(:,:,dim_k,:) <= surf_pres(:,:,:))
                        dp(:,:,dim_k,:) = surf_pres(:,:,:) - SUM(pres(:,:,dim_k-1:,:),3)/2.
                elsewhere
                        dp(:,:,dim_k,:) = 0.
                end where

		!mass in mmtpw
		do j = 1,dim_j
			do i = 1,dim_i
				do t = 1,datatotsteps
					tpw(j,i,t) = SUM(dp(j,i,:,t)*mix(j,i,:,t)/g)
				end do
			end do
		end do

	END SUBROUTINE calc_tpw

	!***********************************************************************

	SUBROUTINE calc_tpw_pbl(mix,pres,surf_pres,tpw,pbl_lev)
	!------------------------------------------
	! calculate the total precipitable water in the pbl from MM5 fields
	! at every level and time

     ! pw = 1/g.rho * integral(q.dp) over p
     ! units: pw [in meters] s-2/m . m-3/kg * kg/kg*kg/(m.s-2) recalling 1 Pa = 1 kg/(m.s-2)
	!-------------------------------------------------

		USE global_data

		IMPLICIT NONE

		REAL, INTENT(IN), DIMENSION(:,:,:,:) :: mix,pres
		REAL, INTENT(IN), DIMENSION(:,:,:) :: surf_pres
		INTEGER, INTENT(IN), DIMENSION(:,:,:) :: pbl_lev
		REAL, INTENT(OUT), DIMENSION(:,:,:) :: tpw

		REAL, DIMENSION(dim_j,dim_i,dim_k,datatotsteps) :: dp
		INTEGER :: j,i,k,t


		!
		! calculate the change in pressure (Pa) represented by each point
		!
		!for highest level
		dp(:,:,1,:) = SUM(pres(:,:,:2,:),3)/2.

		!for the middle levels
		!do k = 2,dim_k-1
		!	!dp(:,:,k,:) = SUM(pres(:,:,k-1:k+1:2,:),3)/2.
		!	dp(:,:,k,:) = (pres(:,:,k+1,:) - pres(:,:,k-1,:)) /2.
		!end do

		!for the lowest level
		!dp(:,:,dim_k,:) = surf_pres(:,:,:) - SUM(pres(:,:,dim_k-1:,:),3)/2.

                !need to account for posibility that pressure levels go below the ground
                !for the middle levels
                do k = 2,dim_k-1
                        where (pres(:,:,k+1,:) <= surf_pres(:,:,:))
                                dp(:,:,k,:) = (pres(:,:,k+1,:) - pres(:,:,k-1,:)) /2. !dp(:,:,k,:) = SUM(pres(:,:,k-1:k+1:2,:),3)/2.
                        elsewhere (pres(:,:,k,:) <= surf_pres(:,:,:))
                                !for the lowest level above surface
                                dp(:,:,k,:) = surf_pres(:,:,:) - (pres(:,:,k,:) + pres(:,:,k-1,:))/2.
                        elsewhere
                                dp(:,:,k,:) = 0.
                        end where

                end do

                !for the lowest level
                where (pres(:,:,dim_k,:) <= surf_pres(:,:,:))
                        dp(:,:,dim_k,:) = surf_pres(:,:,:) - SUM(pres(:,:,dim_k-1:,:),3)/2.
                elsewhere
                        dp(:,:,dim_k,:) = 0.
                end where

		!mass in mm
		do j = 1,dim_j
			do i = 1,dim_i
				do t = 1,datatotsteps
					tpw(j,i,t) = SUM(dp(j,i,pbl_lev(j,i,t):,t)*mix(j,i,pbl_lev(j,i,t):,t)/g)
				end do
			end do
		end do

  print *, 'mix(1,1,:,2)',mix(1,1,:,2)
  print *, 'dp(1,1,:,2)',dp(1,1,:,2)


	END SUBROUTINE calc_tpw_pbl

	!***********************************************************************

	SUBROUTINE calc_pot_temp(temp,pres,pot_temp)
	!------------------------------------------------
	! SUBROUTINE UNUSED

	! calculate the potential temperature at every level and time
	!-----------------------------------------------------

		USE global_data

		IMPLICIT NONE

		REAL, INTENT(IN), DIMENSION(:,:,:,:) :: temp,pres

		REAL, INTENT(OUT), DIMENSION(:,:,:,:) :: pot_temp


		!
		! calculate the potential temperature
		!
		pot_temp = (temp+300) * ((P0/pres)**(Rd/Cp))

	END SUBROUTINE calc_pot_temp

	!***********************************************************************

	SUBROUTINE calc_actual_temp(temp,pres,act_temp)
	!------------------------------------------------
	! calculate the actual temperature at every level and time,
	! given the input perturbation potential temperature.
	!-----------------------------------------------------

		USE global_data

		IMPLICIT NONE

		REAL, INTENT(IN), DIMENSION(:,:,:,:) :: temp,pres

		REAL, INTENT(OUT), DIMENSION(:,:,:,:) :: act_temp


		!
		! Calculate the actual temperature [K] from potential temperature.
		! Need to add 300K since wrfout gives *pertubation* potential temperature as temp T.
		!
		act_temp = (temp + 300) * ((P0/pres)**(-Rd/Cp))

	END SUBROUTINE calc_actual_temp

	!***********************************************************************

	SUBROUTINE calc_eq_pot_temp(mix,mixtot,temp,pres,eq_pot_temp)
	!------------------------------------------------
	! SUBROUTINE UNUSED

	! calculate the equivalent potential temperature at every level and time
	!-----------------------------------------------------

		USE global_data

		IMPLICIT NONE

		REAL, INTENT(IN), DIMENSION(:,:,:,:) :: mix,mixtot,temp,pres

		REAL, INTENT(OUT), DIMENSION(:,:,:,:) :: eq_pot_temp


		REAL, DIMENSION(dim_j,dim_i,dim_k,datatotsteps) :: es,mix_s,pot_temp

		!
		! use Teten's formula to calculate the saturation vapor pressure (in stull)
		!
		es = 611 * exp((17.2694*((temp+300) - 273.16))/((temp+300) - 35.86))

		!
		! calculate the saturated mixing ratio everywhere
		!
		mix_s = (Rd/Rv)*es/(pres - es)

		!
		! calculate the equivalent potential temperature (in atmospheric convection, Emanuel)
		!
		eq_pot_temp = (temp+300) * ((P0/pres)**(Rd/(Cp+Cl*mix))) * &
				mix_s**(-1.*mix*Rv/(Cp+Cl*mixtot)) * &
				exp(Lv*mix/((Cp+Cl*mixtot)*(temp+300)))

		!
		!calculate the equivalent potential temperature (in atmospheric science..., Wallace & Hobbs)
		!
		!woops this isn't right - need to know mix_s at the
		!lifting condensation level!!
		!
		!call calc_pot_temp(temp,pres,pot_temp)

		!eq_pot_temp = pot_temp*exp(Lv*mix_s/(Cp*(temp+300)))


	END SUBROUTINE calc_eq_pot_temp

	!***********************************************************************

	SUBROUTINE calc_pbl_lev(pbl_hgt,pres,surf_pres,pbl_lev)
	!------------------------------------------------
	! SUBROUTINE UNUSED

	! calculate the model level just above the pbl height
	!-----------------------------------------------------

	USE global_data

		IMPLICIT NONE

		REAL, INTENT(IN), DIMENSION(:,:,:,:) :: pres
		REAL, INTENT(IN), DIMENSION(:,:,:) ::pbl_hgt,surf_pres

		INTEGER, INTENT(OUT), DIMENSION(:,:,:) :: pbl_lev


		REAL, DIMENSION(dim_j,dim_i,datatotsteps) :: pbl_pres
		INTEGER :: j,i,t
		INTEGER,DIMENSION(1) :: dummy_min


		!
		! calculate pressure at the pbl height using the hydrostatic equation
		! here I assume that the density averages 1kg m-3 in the pbl
		!
		pbl_pres = -1*pbl_hgt*g + surf_pres        

		!
		! calculate the model level just above the pbl height
		! also add the level above that as it gains moisture by detrainment from the
		! PBL and so this moisture can also be associated with the current
		! location
		!
		do j = 1,dim_j
			do i = 1,dim_i
				do t = 1,datatotsteps
					dummy_min = MINLOC(abs(pbl_pres(j,i,t) - pres(j,i,:,t)))
					if ((pbl_pres(j,i,t) - pres(j,i,dummy_min(1),t)) < 0.) then
						pbl_lev(j,i,t) = dummy_min(1) - 2
					else
						pbl_lev(j,i,t) = dummy_min(1) - 1
					end if
				end do
			end do
		end do

	END SUBROUTINE calc_pbl_lev

	!***********************************************************************

	SUBROUTINE near_pt(lon2d,lat2d,lon,lat,x,y)
	!---------------------------------------------------------
	!calculate the grid point nearest the lat and lon location
	!------------------------------------------------------

		USE global_data

		IMPLICIT NONE

		REAL, INTENT(IN), DIMENSION(:,:) :: lon2d,lat2d
		REAL, INTENT(IN) :: lon,lat
		INTEGER, INTENT(OUT) :: x,y

		REAL, DIMENSION(SIZE(lon2d(:,1)),SIZE(lon2d(1,:))) :: dist
		INTEGER, DIMENSION(2) :: loc

		REAL, DIMENSION(SIZE(lon2d(:,1)),SIZE(lon2d(1,:))) :: lcos ! --svetlana

		!
		!calculate the distance from the parcel location to every grid point
		!must account for changing distance between longitude lines as latitude changes
		!
		!call vsCos(SIZE(lat2d(:,1))*SIZE(lat2d(1,:)), lat2d*pi/180, lcos) ! -- svetlana
		lcos=cos(lat2d*pi/180)
		dist = sqrt((lat2d-lat)**2 + (lcos*(lon2d-lon))**2) ! --svetlana
		!  dist = (lat2d-lat)**2 + cos(lat2d*pi/180)*(lon2d-lon)**2 ! --svetlana

		loc = MINLOC(dist)

		x = loc(1)
		y = loc(2)

	END SUBROUTINE near_pt

	!***********************************************************************

	SUBROUTINE bilin_interp(var2d,lon2d,lat2d,x,y,par_lon,par_lat,var)
	!------------------------------------------------------------------
	! find the bi-linearly interpolated value at par_lon,par_lat
	! lon and lat are not regularly spaced grids
	!------------------------------------------------------------------

		USE global_data

		IMPLICIT NONE

		REAL, INTENT(IN), DIMENSION(:,:) :: var2d,lon2d,lat2d
		REAL, INTENT(IN) :: par_lon,par_lat
		REAL, INTENT(OUT) :: var

		REAL :: fac,t,u
		INTEGER :: xx,yy,xbdy,ybdy,x,y
		LOGICAL :: changex,changey

		changex = .FALSE.
		changey = .FALSE.
		xbdy = 0
		ybdy = 0

		! Find what xx,yy is in the subgrid
		!call near_pt(lon2d,lat2d,par_lon,par_lat,xx,yy)
		! Instead of calling near_pt every time you do bilin_interp, just give bilin_interp the xx and yy
		xx=x
		yy=y

		!
		!check if we are currently exactly on a grid pt
		! ..where lon/lat2d are the subgrids
		! The initial call to bilin_interp in the implicit_back_traj_w will have the parcel on a grid point, as this is the initial location of the parcel when released (par_lat,par_lon) before entering the back_traj routine. Parcel lat,lon may not be on a cell centre after the parcel has been advected.
		If (lon2d(xx,yy)==par_lon.AND.lat2d(xx,yy)==par_lat) then
			var = var2d(xx,yy)
			RETURN
		end if

		!
		!get indices of closest grid value to south and west
		!be careful of boundary
		! If you are in the bottom corner of the subgrid:
		if (xx==1) xbdy = -1
		if (yy==1) ybdy = -1

		! If you're not in the bottom corner of the subgrid:
		! If the nearest cell point is further east than the advected parcel, take x position as xx-1, i.e. move it west.
		if (lon2d(xx,yy)>par_lon.AND.xbdy>-1) then
			changex = .TRUE.
		end if
		! If the nearest cell point is further north than the advected parcel, take y position as yy-1, i.e. move it south.
		if (lat2d(xx,yy)>par_lat.AND.ybdy>-1) then
			changey = .TRUE.
		end if

		! What about case where xx,yy need to increase, not decrease?

		if (changex) then
			xx = xx-1
		end if
		if (changey) then
			yy = yy-1
		end if


		!
		!if we are at the top or right boundary
		!
		if (xx==ssdim) then
			xbdy = 1
		end if
		if (yy==ssdim) then
			ybdy = 1
		end if


		!
		!check to see if point in inside lower and left boundaries
		!
		if (xbdy<0.AND.lon2d(xx,yy)<par_lon) xbdy = 0
		if (ybdy<0.AND.lat2d(xx,yy)<par_lat) ybdy = 0

		!
		!calculate the t and u weights
		!account for possibility of being outside the boundaries
		!even though this should never happen
		!if outside a boundary use the value at the boundary
		!
		if ((xbdy/=0.AND.ybdy/=0)) then
			var = var2d(xx,yy)
		else if (xbdy/=0) then
			fac = (par_lat - lat2d(xx,yy))/(lat2d(xx,yy+1)-lat2d(xx,yy))
			var = lin_interp(var2d(xx,yy:yy+1),fac)
		else if (ybdy/=0) then
			fac = (par_lon - lon2d(xx,yy))/(lon2d(xx+1,yy)-lon2d(xx,yy))
			var = lin_interp(var2d(xx:xx+1,yy),fac)
		else
			t = (par_lon - lon2d(xx,yy))/(lon2d(xx+1,yy)-lon2d(xx,yy))
			u = (par_lat - lat2d(xx,yy))/(lat2d(xx,yy+1)-lat2d(xx,yy))
			var = (1-t)*(1-u)*var2d(xx,yy) + (1-t)*u*var2d(xx,yy+1) + &
			       t*u*var2d(xx+1,yy+1) + t*(1-u)*var2d(xx+1,yy)
		end if

	END SUBROUTINE bilin_interp

	!***********************************************************************

	SUBROUTINE new_parcel_level_w(par_pres,pres,w,temp,mix,lev,psfc)
	!-------------------------------------------------------------------------
	!calculate the new parcel level given w at this location
	!--------------------------------------------------------------------------

		USE global_data

		IMPLICIT NONE

		REAL, INTENT(IN) :: w,temp,mix,psfc
		REAL, INTENT(IN), DIMENSION(:) :: pres
		REAL, INTENT(INOUT) :: par_pres
		INTEGER, INTENT(OUT) :: lev

		INTEGER, DIMENSION(1) :: dummy_lev

                !If w is in ms-1 then use this
                !
		! Here I use the hydrostatic eqn to calculate the change in pressure given w.
		! deltaP = rho*g*deltaz when in hydrostatic equilibrium
		! Note that "(1+0.61*mix)*temp" is the virtual temp. See p80 Wallace & Hobbs.
		!

		!par_pres = par_pres + -1.*(par_pres/(Rd*(1+0.61*mix)*temp))*g*w*tstep*60

                !If w is in Pas-1 (so it is really omega) then use this
                par_pres = par_pres + w*tstep*60

                !if the parcel is below the surface pressure then move it to 5hPa above the surface
                if (par_pres > psfc) par_pres = psfc - 5. 

		! Find the model level where the difference in pressure between the parcel
		! and the atmosphere is the smallest, i.e. which height in pres does the
		! smallest difference occur, where pres dims are (lat,lon,height).
		dummy_lev = MINLOC(ABS(pres - par_pres))

		lev = dummy_lev(1)

		!if the parcel is below the lowest model level then set it to the lowest level
		!if (par_pres > MAXVAL(pres)) par_pres = MAXVAL(pres)
                
                !make sure the level used is above the surface pressure (not underground)
                if (pres(lev) > psfc) lev = lev - 1

		! if (lev==0) then
		!   print *,'par_lev_w - pres_dis',(pres - par_pres),temp,w
		!   print *,'par_lev_w -',par_pres,pres
		! end if

	END SUBROUTINE new_parcel_level_w

	!***********************************************************************

	SUBROUTINE new_parcel_level_pt(par_pot_temp,pot_temp,par_lev,lev)
	!-------------------------------------------------------------------------
	! SUBROUTINE UNUSED

	!calculate what level has the parcel potential temperature at this location
	!--------------------------------------------------------------------------

		USE global_data

		IMPLICIT NONE

		REAL, INTENT(IN), DIMENSION(:) :: pot_temp
		INTEGER, INTENT(IN) :: par_lev
		REAL, INTENT(INOUT) :: par_pot_temp
		INTEGER, INTENT(OUT) :: lev

		REAL, DIMENSION(dim_k) :: pot_dist
		REAL :: pot_min
		INTEGER :: xx,yy,kk
		INTEGER, DIMENSION(1) :: lev_dummy
		INTEGER, DIMENSION(2) :: lev_dis
		LOGICAL :: getdownmin, getupmin


		getdownmin = .TRUE.
		getupmin = .TRUE.


		!
		!adjust parcel potential temperature if required (ie. driven into ground)
		!
		!print *,'1',par_pot_temp,xx,yy
		pot_min = MINVAL(pot_temp)
		par_pot_temp = MAX(par_pot_temp,pot_min)
		!print *,'2',pot_temp(xx,yy,:)
		!
		!calculate nearest potential temperature in vertical column
		!
		pot_dist = pot_temp - par_pot_temp

		!
		!since equivalent pot temperature is not monotonic I need
		!to find the level closest to previous level with right potential temp
		!
		lev_dis = dim_k*2

		do kk = 1, dim_k
			if (par_lev-kk>0 .AND. getdownmin) then
				if (pot_dist(par_lev-kk)<0.AND.pot_dist(par_lev-kk+1)>0.OR. &
						pot_dist(par_lev-kk)>0.AND.pot_dist(par_lev-kk+1)<0.) then
					lev_dummy = MINLOC(ABS(pot_dist(par_lev-kk:par_lev-kk+1)))
					lev_dis(1) = -kk-1+lev_dummy(1)
					getdownmin = .FALSE.
				end if
			end if

			if (par_lev+kk<dim_k+1 .AND. getupmin) then
				if (pot_dist(par_lev+kk)<0.AND.pot_dist(par_lev+kk-1)>0.OR. &
						pot_dist(par_lev+kk)>0.AND.pot_dist(par_lev+kk-1)<0.) then
					lev_dummy = MINLOC(ABS(pot_dist(par_lev+kk-1:par_lev+kk)))
					lev_dis(2) = kk-2+lev_dummy(1)
					getupmin = .FALSE.
				end if
			end if
		end do

		!print *,lev_dis,SUM(lev_dis),par_pot_temp

		if (SUM(lev_dis)==dim_k*4) then
			lev_dummy = MINLOC(ABS(pot_dist))
			lev = lev_dummy(1)
		else
			lev_dummy = MINLOC(ABS(lev_dis))
			lev = lev_dis(lev_dummy(1)) + par_lev
		end if

		if (lev==0) then
			print *,"new_parcel_pt - pot dist",pot_dist
			print *,"new_parcel_pt - par_lev,lev",par_lev,lev
		end if

	END SUBROUTINE new_parcel_level_pt

	!***********************************************************************

	SUBROUTINE advect(u,v,lon,lat)
	!-----------------------------------------------
	!linear advection in direction given by u and v
	!u and v are m/s
	!lon and lat are in degrees east and north
	!time step is given by tstep from global_data
	!-----------------------------------------------

		USE global_data

		IMPLICIT NONE

		REAL, INTENT(IN) :: u,v
		REAL, INTENT(INOUT) :: lon,lat


		!
		!calculate the new lat
		!
		lat = lat + v*tstep*60/(deg_dist*1000)

		!
		!calculate new lon
		!
		lon = lon + u*tstep*60/(cos(lat*pi/180)*deg_dist*1000)


	END SUBROUTINE advect

	!***********************************************************************

	SUBROUTINE implicit_back_traj(u,v,w,temp,pbl_lev,pot_temp,pres,psfc,lon2d,lat2d, &
					par_lon,par_lat,par_lev, &
					par_pot_temp,par_pres,par_q,thread)
	!-------------------------------------------------------------------------------
	! SUBROUTINE UNUSED

	! Using Merrill's fully implicit isentropic technique
	! calculate the parcels position one time step before
	!
	!u,v,w should only have 2 time steps in them
	!pot_temp & pres should only have the end time step
	!--------------------------------------------------------------------------

		USE global_data

		IMPLICIT NONE

		REAL, INTENT(IN), DIMENSION(:,:,:,:) :: u,v,w
		REAL, INTENT(IN), DIMENSION(:,:,:) :: pot_temp,pres,temp
		REAL, INTENT(IN), DIMENSION(:,:) :: lon2d,lat2d,psfc
		INTEGER, INTENT(IN), DIMENSION(:,:) :: pbl_lev
		REAL, INTENT(INOUT) :: par_lon,par_lat,par_pot_temp,par_pres
		REAL, INTENT(IN) :: par_q
		INTEGER, INTENT(INOUT) :: par_lev
		INTEGER, INTENT(IN) :: thread

		INTEGER :: xx,yy,ll,lev
		REAL :: lon,lat,u_back,v_back,w_back,temp_back,u_for,v_for,w_for,pr
		REAL :: pt1,pt2,vfac,pr1,pr2
		INTEGER, DIMENSION(1) :: dummy_lev


		!print *,'1st',par_pres,par_pot_temp,par_lon,par_lat,par_lev,thread

		!
		!get u and v at parcel location
		!
		lon = par_lon
		lat = par_lat
		call near_pt(lon2d,lat2d,lon,lat,xx,yy)
		call bilin_interp(u(:,:,par_lev,2),lon2d,lat2d,xx,yy,lon,lat,u_back)
		call bilin_interp(v(:,:,par_lev,2),lon2d,lat2d,xx,yy,lon,lat,v_back)


		!
		!find lat and lon after advecting back in time
		!
		call advect(-1.*u_back,-1.*v_back,lon,lat)

		!
		!calculate which vertical level has correct potential temperature
		!at new location or that w moves us to
		!
		call near_pt(lon2d,lat2d,lon,lat,xx,yy)

		!print *,'par_lev,pbl_lev',par_lev,pbl_lev(xx,yy),xx,yy,thread

		call bilin_interp(temp(:,:,par_lev),lon2d,lat2d,xx,yy,par_lon,par_lat,temp_back)

		!if (par_lev >= pbl_lev(xx,yy)) then
		if (.TRUE.) then
			call new_parcel_level_pt(par_pot_temp,pot_temp(xx,yy,:),par_lev,lev)
		else
			pr = par_pres
			call bilin_interp(w(:,:,par_lev,2),lon2d,lat2d,xx,yy,lon,lat,w_back)
                        call new_parcel_level_w(pr,pres(xx,yy,:),w_back,temp_back,par_q,lev,psfc(xx,yy))
		end if

		!print *,'2nd',par_pres,par_pot_temp,par_lon,par_lat,par_lev,thread


		!
		!get u and v at new location
		!
		call bilin_interp(u(:,:,lev,1),lon2d,lat2d,xx,yy,lon,lat,u_for)
		call bilin_interp(v(:,:,lev,1),lon2d,lat2d,xx,yy,lon,lat,v_for)

		!
		!find new location of parcel as mean location given by back and forward trajectory
		!
		call advect(-1.*(u_back+u_for)/2.,-1.*(v_back+v_for)/2.,par_lon,par_lat)


		!
		!find final parcel potential temperature and level
		!
		call near_pt(lon2d,lat2d,par_lon,par_lat,xx,yy)

		!print *,'par_lev,pbl_lev',par_lev,pbl_lev(xx,yy),xx,yy,thread


		!if (par_lev >= pbl_lev(xx,yy)) then
		if (.TRUE.) then
			call new_parcel_level_pt(par_pot_temp,pot_temp(xx,yy,:),par_lev,lev)

			!print *,'lev_pt1',par_pres,par_pot_temp,pot_temp(xx,yy,lev-1:lev+1)

			!
			!need to calculate the new parcel pressure
			!need to be extra careful as pot_temp may not be monotonic
			!
			call bilin_interp(pres(:,:,lev),lon2d,lat2d,xx,yy,par_lon,par_lat,pr1)
			if (lev == dim_k .OR. lev == 1 .OR. par_pot_temp == pot_temp(xx,yy,lev)) then
				par_pres = pr1
			else
				!
				!in case this level is a min or max in pot_temp
				!
				if (par_pot_temp>pot_temp(xx,yy,lev).AND.par_pot_temp<pot_temp(xx,yy,lev-1).AND.par_pot_temp<pot_temp(xx,yy,lev+1)) then

					dummy_lev = MINLOC(ABS(par_pres - pres(xx,yy,lev-1:lev+1:2)))
					if (dummy_lev(1)==1) then
						dummy_lev(1) = lev-1
					else
						dummy_lev(1) = lev+1
					end if
					call bilin_interp(pres(:,:,dummy_lev(1)),lon2d,lat2d,xx,yy,par_lon,par_lat,pr2)
					vfac = (pot_temp(xx,yy,dummy_lev(1))-par_pot_temp)/(pot_temp(xx,yy,dummy_lev(1))-pot_temp(xx,yy,lev))
					par_pres = exp((1-vfac)*log(pr2) + vfac*log(pr1))

				else if (par_pot_temp<pot_temp(xx,yy,lev).AND.par_pot_temp>pot_temp(xx,yy,lev-1).AND.par_pot_temp>pot_temp(xx,yy,lev+1)) then

					dummy_lev = MINLOC(ABS(par_pres - pres(xx,yy,lev-1:lev+1:2)))
					if (dummy_lev(1)==1) then
						dummy_lev(1) = lev-1
					else
						dummy_lev(1) = lev+1
					end if
					call bilin_interp(pres(:,:,dummy_lev(1)),lon2d,lat2d,xx,yy,par_lon,par_lat,pr2)
					vfac = (pot_temp(xx,yy,lev)-par_pot_temp)/(pot_temp(xx,yy,lev)-pot_temp(xx,yy,dummy_lev(1)))
					par_pres = exp((1-vfac)*log(pr1) + vfac*log(pr2))

				!
				!in other cases
				!
				else if (par_pot_temp > pot_temp(xx,yy,lev) .AND. par_pot_temp < pot_temp(xx,yy,lev-1)) then

					call bilin_interp(pres(:,:,lev-1),lon2d,lat2d,xx,yy,par_lon,par_lat,pr2)
					vfac = (pot_temp(xx,yy,lev-1)-par_pot_temp)/(pot_temp(xx,yy,lev-1)-pot_temp(xx,yy,lev))
					par_pres = exp((1-vfac)*log(pr2) + vfac*log(pr1))

				else if (par_pot_temp < pot_temp(xx,yy,lev) .AND. par_pot_temp > pot_temp(xx,yy,lev+1)) then

					call bilin_interp(pres(:,:,lev+1),lon2d,lat2d,xx,yy,par_lon,par_lat,pr2)
					vfac = (pot_temp(xx,yy,lev)-par_pot_temp)/(pot_temp(xx,yy,lev)-pot_temp(xx,yy,lev+1))
					par_pres = exp((1-vfac)*log(pr1) + vfac*log(pr2))

				else if (par_pot_temp > pot_temp(xx,yy,lev) .AND. par_pot_temp < pot_temp(xx,yy,lev+1)) then

					call bilin_interp(pres(:,:,lev+1),lon2d,lat2d,xx,yy,par_lon,par_lat,pr2)
					vfac = (pot_temp(xx,yy,lev+1)-par_pot_temp)/(pot_temp(xx,yy,lev+1)-pot_temp(xx,yy,lev))
					par_pres = exp((1-vfac)*log(pr2) + vfac*log(pr1))

				else if (par_pot_temp < pot_temp(xx,yy,lev) .AND. par_pot_temp > pot_temp(xx,yy,lev-1)) then

					call bilin_interp(pres(:,:,lev-1),lon2d,lat2d,xx,yy,par_lon,par_lat,pr2)
					vfac = (pot_temp(xx,yy,lev)-par_pot_temp)/(pot_temp(xx,yy,lev)-pot_temp(xx,yy,lev-1))
					par_pres = exp((1-vfac)*log(pr1) + vfac*log(pr2))

				end if
			end if
  
		!print *,'lev_pt2',par_pres,par_pot_temp,pot_temp(xx,yy,lev-1:lev+1)

		else
			call bilin_interp(w(:,:,par_lev,1),lon2d,lat2d,xx,yy,lon,lat,w_for)
			call new_parcel_level_w(par_pres,pres(xx,yy,:),(w_back+w_for)/2.,temp_back,par_q,lev,psfc(xx,yy))

			!need to calculate the new parcel potential temperature
			call bilin_interp(pot_temp(:,:,lev),lon2d,lat2d,xx,yy,par_lon,par_lat,pt1)
			if (lev == dim_k .OR. lev == 1 .OR. par_pres == pres(xx,yy,lev)) then
				par_pot_temp = pt1
			else
				if (par_pres > pres(xx,yy,lev)) then
					call bilin_interp(pot_temp(:,:,lev+1),lon2d,lat2d,xx,yy,par_lon,par_lat,pt2)
					vfac = (log(pres(xx,yy,lev+1))-log(par_pres))/(log(pres(xx,yy,lev+1))-log(pres(xx,yy,lev)))
					par_pot_temp = (1-vfac)*pt2 + vfac*pt1
				else
					call bilin_interp(pot_temp(:,:,lev-1),lon2d,lat2d,xx,yy,par_lon,par_lat,pt2)
					vfac = (log(pres(xx,yy,lev))-log(par_pres))/(log(pres(xx,yy,lev))-log(pres(xx,yy,lev-1)))
					par_pot_temp = (1-vfac)*pt1 + vfac*pt2
				end if
			end if
		end if


		if (lev==0) then
		  print *,'L2389, ',par_lev,lev,par_pres,par_pot_temp,temp_back,thread
		  STOP
		end if

		par_lev = lev

	END SUBROUTINE implicit_back_traj

	!***********************************************************************

	SUBROUTINE implicit_back_traj_w(u,v,w,temp,pres,psfc,lon2d,lat2d, &
					par_lon,par_lat,par_lev, &
					par_pres,par_q,thread)
	!-------------------------------------------------------------------------------
	! Using Merrill's fully implicit  technique
	! calculate the parcels position one time step before
	!
	! u,v,w should only have 2 time steps in them
	! pres should only have the end time step

	! Output parcel lat,lon, height and pressure
	!--------------------------------------------------------------------------

		USE global_data

		IMPLICIT NONE

		REAL, INTENT(IN), DIMENSION(:,:,:,:) :: u,v,w
		!INTEGER, INTENT(IN), DIMENSION(:,:) :: pbl_lev
		REAL, INTENT(IN), DIMENSION(:,:,:) :: pres,temp
		REAL, INTENT(IN), DIMENSION(:,:) :: psfc,lon2d,lat2d
		REAL, INTENT(INOUT) :: par_lon,par_lat,par_pres
		REAL, INTENT(IN) :: par_q
		INTEGER, INTENT(INOUT) :: par_lev
		INTEGER, INTENT(IN) :: thread

		INTEGER :: xx,yy,lev !ll
		REAL :: lon,lat,u_back,v_back,w_par,temp_par,u_for,v_for,pr

		! Get u and v at parcel location, by interpolating in time (current and previous parcel timestep), and space (parcel lat/lon and lat/lon of the nearest grid point).
		lon = par_lon
		lat = par_lat

		call near_pt(lon2d,lat2d,lon,lat,xx,yy)

		call bilin_interp(u(:,:,par_lev,2),lon2d,lat2d,xx,yy,lon,lat,u_back) ! where lon2d/lat2d are the subgrids
		call bilin_interp(v(:,:,par_lev,2),lon2d,lat2d,xx,yy,lon,lat,v_back)


		!find lat and lon after advecting back in time. Reverse the wind directions (make negative) as you're going back in time.
		call advect(-1.*u_back,-1.*v_back,lon,lat)

		!calculate which vertical level that w moves us to
		call near_pt(lon2d,lat2d,lon,lat,xx,yy)

                !print *,'par_pres,psfc,pres',par_pres,psfc(xx,yy),pres(xx,yy,:)
		pr = par_pres
		call bilin_interp(temp(:,:,par_lev),lon2d,lat2d,xx,yy,lon,lat,temp_par)
		call bilin_interp(w(:,:,par_lev,2),lon2d,lat2d,xx,yy,lon,lat,w_par)
		! Reverse vertical wind direction as you're going back in time.
		call new_parcel_level_w(pr,pres(xx,yy,:),-1.*w_par,temp_par,par_q,lev,psfc(xx,yy))

		!get u and v at new lon/lat found using first advect call above
		call bilin_interp(u(:,:,lev,1),lon2d,lat2d,xx,yy,lon,lat,u_for)
		call bilin_interp(v(:,:,lev,1),lon2d,lat2d,xx,yy,lon,lat,v_for)

		!
		!find new location of parcel as mean location given by back and forward trajectory
		call advect(-1.*(u_back+u_for)/2.,-1.*(v_back+v_for)/2.,par_lon,par_lat)

		!
		!find final parcel level
		call near_pt(lon2d,lat2d,par_lon,par_lat,xx,yy)

		call bilin_interp(temp(:,:,par_lev),lon2d,lat2d,xx,yy,par_lon,par_lat,temp_par)
		call bilin_interp(w(:,:,par_lev,1),lon2d,lat2d,xx,yy,par_lon,par_lat,w_par)
		call new_parcel_level_w(par_pres,pres(xx,yy,:),-1.*w_par,temp_par,par_q,lev,psfc(xx,yy))

		if (lev==0) then
		  print *,'parcel lev=0',par_lev,lev,par_pres,temp_par,thread
		  STOP
		end if

		par_lev = lev
                !print *,'parvel_lev=',par_lev

	END SUBROUTINE implicit_back_traj_w

	!***********************************************************************

END MODULE bt_subs

!***********************************************************************
!***********************************************************************

#ifndef ERA5
MODULE input_data_handling_wrf

	IMPLICIT NONE

	CONTAINS

	SUBROUTINE get_filename(d,mn,yr,filename_ext_atm,filename_ext_RAIN,filename_ext_LH,filename_ext_P)
	!-----------------------------------------------
	! given the month and year get the filename extension string
	!---------------------------------------------------

		USE global_data
		USE util

		IMPLICIT NONE

		INTEGER, INTENT(IN) :: d
		INTEGER, INTENT(IN) :: mn, yr
		CHARACTER(LEN=100), INTENT(OUT) :: filename_ext_atm,filename_ext_RAIN,filename_ext_LH,filename_ext_P

		if (mn<10) then
			if (d<10) then
				filename_ext_atm = "wrfout_d01_"//TRIM(int_to_string(yr))//"-0"//TRIM(int_to_string(mn))//"-0"//TRIM(int_to_string(d))//"_00:00:00"
				filename_ext_RAIN = "wrfhrly_d01_"//TRIM(int_to_string(yr))//"-0"//TRIM(int_to_string(mn))//"-0"//TRIM(int_to_string(d))//"_00:00:00_RAIN.nc"
				filename_ext_LH = "wrfhrly_d01_"//TRIM(int_to_string(yr))//"-0"//TRIM(int_to_string(mn))//"-0"//TRIM(int_to_string(d))//"_00:00:00_LH.nc"
				filename_ext_P = "wrfhrly_d01_"//TRIM(int_to_string(yr))//"-0"//TRIM(int_to_string(mn))//"-0"//TRIM(int_to_string(d))//"_00:00:00_PSFC.nc"
			else
				filename_ext_atm = "wrfout_d01_"//TRIM(int_to_string(yr))//"-0"//TRIM(int_to_string(mn))//"-"//TRIM(int_to_string(d))//"_00:00:00"
				filename_ext_RAIN = "wrfhrly_d01_"//TRIM(int_to_string(yr))//"-0"//TRIM(int_to_string(mn))//"-"//TRIM(int_to_string(d))//"_00:00:00_RAIN.nc"
				filename_ext_LH = "wrfhrly_d01_"//TRIM(int_to_string(yr))//"-0"//TRIM(int_to_string(mn))//"-"//TRIM(int_to_string(d))//"_00:00:00_LH.nc"
				filename_ext_P = "wrfhrly_d01_"//TRIM(int_to_string(yr))//"-0"//TRIM(int_to_string(mn))//"-"//TRIM(int_to_string(d))//"_00:00:00_PSFC.nc"
			end if
		else
			if (d<10) then
				filename_ext_atm = "wrfout_d01_"//TRIM(int_to_string(yr))//"-"//TRIM(int_to_string(mn))//"-0"//TRIM(int_to_string(d))//"_00:00:00"
				filename_ext_RAIN = "wrfhrly_d01_"//TRIM(int_to_string(yr))//"-"//TRIM(int_to_string(mn))//"-0"//TRIM(int_to_string(d))//"_00:00:00_RAIN.nc"
				filename_ext_LH = "wrfhrly_d01_"//TRIM(int_to_string(yr))//"-"//TRIM(int_to_string(mn))//"-0"//TRIM(int_to_string(d))//"_00:00:00_LH.nc"
				filename_ext_P = "wrfhrly_d01_"//TRIM(int_to_string(yr))//"-"//TRIM(int_to_string(mn))//"-0"//TRIM(int_to_string(d))//"_00:00:00_PSFC.nc"
			else
				filename_ext_atm = "wrfout_d01_"//TRIM(int_to_string(yr))//"-"//TRIM(int_to_string(mn))//"-"//TRIM(int_to_string(d))//"_00:00:00"
				filename_ext_RAIN = "wrfhrly_d01_"//TRIM(int_to_string(yr))//"-"//TRIM(int_to_string(mn))//"-"//TRIM(int_to_string(d))//"_00:00:00_RAIN.nc"
				filename_ext_LH = "wrfhrly_d01_"//TRIM(int_to_string(yr))//"-"//TRIM(int_to_string(mn))//"-"//TRIM(int_to_string(d))//"_00:00:00_LH.nc"
				filename_ext_P = "wrfhrly_d01_"//TRIM(int_to_string(yr))//"-"//TRIM(int_to_string(mn))//"-"//TRIM(int_to_string(d))//"_00:00:00_PSFC.nc"
			end if
		end if

		filename_ext_atm = ADJUSTL(filename_ext_atm)
		filename_ext_RAIN = ADJUSTL(filename_ext_RAIN)
		filename_ext_LH = ADJUSTL(filename_ext_LH)
		filename_ext_P = ADJUSTL(filename_ext_P)

		print *,'get_filename:'
		print *,'filename_ext_atm= ',filename_ext_atm
		print *,'filename_ext_RAIN= ',filename_ext_RAIN
		print *,'filename_ext_LH= ',filename_ext_LH

	END SUBROUTINE get_filename

	!***********************************************************************

	SUBROUTINE open_netcdf_files(ncid,prencid,lhncid,psfcncid,preid,lhid,uid,vid,wid,tid,qid,ppid,pbid,pblid,psfcid,filename_ext_atm,filename_ext_RAIN,filename_ext_LH,filename_ext_P)
		!----------------------------------------------------------------
		! open all the netcdf data files and get the variable ids
		!------------------------------------------------------------------

		USE netcdf
		USE util
		USE global_data

		IMPLICIT NONE

		INTEGER, INTENT(OUT) :: ncid,prencid,lhncid,psfcncid !,uncid,vncid,wncid,tncid,qncid,ppncid,pblncid
		INTEGER, INTENT(OUT) :: preid,lhid,uid,vid,wid,tid,qid,ppid,pbid,pblid,psfcid
		CHARACTER(LEN=100), INTENT(IN) :: filename_ext_atm,filename_ext_RAIN,filename_ext_LH,filename_ext_P

		INTEGER :: status

		! open the netcdf files - ATMOSPHERIC VARIABLES
		status = NF90_OPEN(TRIM(dirdata_atm)//TRIM(filename_ext_atm), NF90_NOWRITE, ncid)
		if (status /= NF90_NOERR) call handle_err(status)

		! open the netcdf files - PRECIP
		status = NF90_OPEN(TRIM(dirdata_land)//TRIM(filename_ext_RAIN), NF90_NOWRITE, prencid)
		if (status /= NF90_NOERR) call handle_err(status)

		! open the netcdf files - EVAP
		status = NF90_OPEN(TRIM(dirdata_land)//TRIM(filename_ext_LH), NF90_NOWRITE, lhncid)
		if (status /= NF90_NOERR) call handle_err(status)

		! open the netcdf files - SURFACE PRESSURE
		status = NF90_OPEN(TRIM(dirdata_land)//TRIM(filename_ext_P), NF90_NOWRITE, psfcncid)
		if (status /= NF90_NOERR) call handle_err(status)

		!
		!get ids for each variable
		!
		status = nf90_inq_varid(prencid, "RAIN", preid) 	! [mm]
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inq_varid(lhncid, "LH", lhid)			! [Wm-2] > converted to mm at end of get_data subroutine
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inq_varid(ncid, "U", uid)			! [ms-1]
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inq_varid(ncid, "V", vid)			! [ms-1]
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inq_varid(ncid, "W", wid)			! [ms-1]
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inq_varid(ncid, "T", tid) 			! [K]
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inq_varid(ncid, "QVAPOR", qid)			! [kgkg-1]
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inq_varid(ncid, "P", ppid) 		! [Pa]
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inq_varid(ncid, "PB", pbid) 		! [Pa]
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inq_varid(ncid, "PBLH", pblid)		! [m]
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inq_varid(psfcncid, "PSFC", psfcid)		! [Pa]
		if(status /= nf90_NoErr) call handle_err(status)

	END SUBROUTINE open_netcdf_files

	!***********************************************************************

	SUBROUTINE get_data(precip,evap,u,v,w,t,q,qc,qt,pp,pb,pbl_hgt,psfc,tcw)
	!-----------------------------------------------
	! read in the data for the first time
	!-----------------------------------------------

		USE global_data
		USE util
		USE netcdf

		IMPLICIT NONE

		REAL, DIMENSION(:,:,:) :: precip,evap,pbl_hgt,psfc
		REAL, DIMENSION(:,:,:,:) :: u,v,w,t,q,qc,qt,pp,pb
		REAL, DIMENSION(SIZE(u,1),SIZE(u,2),SIZE(u,3),datadaysteps) :: temp

		!!! Not used for WRF
		REAL, DIMENSION(:,:,:) :: tcw

		CHARACTER(LEN=100) :: filename_ext_atm,filename_ext_RAIN,filename_ext_LH,filename_ext_P

		INTEGER :: ncid,prencid,lhncid,psfcncid
		INTEGER :: preid,lhid,uid,vid,wid,tid,qid,ppid,pbid,pblid,psfcid
		INTEGER :: sind,status,sind2,i,getsteps,getsteps2

		REAL :: dayend

		INTEGER :: jd_today,jd_before,new_y,new_m,new_d

		!first get the qt
		call get_data_mixtot(qc,qt)

		call get_filename(day,mon,year,filename_ext_atm,filename_ext_RAIN,filename_ext_LH,filename_ext_P)

		!call open_netcdf_files(pncid,preid,lhid,uid,vid,wid,tid,qid,ppid,pbliqd,filename_ext)
		call open_netcdf_files(ncid,prencid,lhncid,psfcncid,preid,lhid,uid,vid,wid,tid,qid,ppid,pbid,pblid,psfcid,filename_ext_atm,filename_ext_RAIN,filename_ext_LH,filename_ext_P)

		!if this is a day around a storm peak we want the half day after as well
		if (peak) then
			dayend = day + 0.5
		else
			dayend = day
		end if

		! Since our input files only consist of one day, open all timesteps (datadaysteps) in file (i.e. remove sind2, make it 1)

		!!! SIM DAY SHOULD BE AT THE END OF THE ARRAY, DAY BEFORE JUST BEFORE THAT, ETC.
		!!! LAST BACK-TRACKED DAY SHOULD BE AT THE START OF THE ARRAY.
		!!! THE LAST TIME POSITION IN THE ARRAY SHOULD BE THE FIRST TIMESTEP OF SIM DAY + 1.

		if (totbtadays>1) then
			! Open the first day input file
			status = nf90_get_var(prencid, preid, precip, &
			start=(/bdy,bdy,1/),count=(/dim_j,dim_i,datadaysteps/))
			if(status /= nf90_NoErr) call handle_err(status)

			status = nf90_get_var(lhncid, lhid, evap(:,:,(datatotsteps-datadaysteps):(datatotsteps-1)), &
			start=(/bdy,bdy,1/),count=(/dim_j,dim_i,datadaysteps/))
			if(status /= nf90_NoErr) call handle_err(status)

			status = nf90_get_var(ncid, qid, temp(:,:,:,:), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
			if(status /= nf90_NoErr) call handle_err(status)

			q(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)) = temp(:,:,dim_k:1:-1,:)

			status = nf90_get_var(ncid, uid, temp(:,:,:,:), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
			if(status /= nf90_NoErr) call handle_err(status)

			u(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)) = temp(:,:,dim_k:1:-1,:)

			status = nf90_get_var(ncid, vid, temp(:,:,:,:), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
			if(status /= nf90_NoErr) call handle_err(status)

			v(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)) = temp(:,:,dim_k:1:-1,:)

			status = nf90_get_var(ncid, wid, temp(:,:,:,:), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
			if(status /= nf90_NoErr) call handle_err(status)

			w(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)) = temp(:,:,dim_k:1:-1,:)

			status = nf90_get_var(ncid, tid, temp(:,:,:,:), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
			if(status /= nf90_NoErr) call handle_err(status)

			t(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)) = temp(:,:,dim_k:1:-1,:)

			status = nf90_get_var(ncid, ppid, temp(:,:,:,:), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
			if(status /= nf90_NoErr) call handle_err(status)

			pp(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)) = temp(:,:,dim_k:1:-1,:)

			status = nf90_get_var(ncid, pbid, temp(:,:,:,:), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
			if(status /= nf90_NoErr) call handle_err(status)

			pb(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)) = temp(:,:,dim_k:1:-1,:)

			status = nf90_get_var(ncid, pblid, pbl_hgt(:,:,(datatotsteps-datadaysteps):), &
			start=(/bdy,bdy,1/),count=(/dim_j,dim_i,datadaysteps/))
			if(status /= nf90_NoErr) call handle_err(status)

			status = nf90_get_var(psfcncid, psfcid, psfc(:,:,(datatotsteps-datadaysteps):), &
			start=(/bdy,bdy,1/),count=(/dim_j,dim_i,datadaysteps/))
			if(status /= nf90_NoErr) call handle_err(status)

			! close the netcdf files
			status = nf90_close(ncid)
			status = nf90_close(prencid)
			status = nf90_close(lhncid)
			status = nf90_close(psfcncid)

			print *,'L948, Input file of first day loaded successfully:',filename_ext_atm

			! Get julian day of current day
			jd_today = julian(year,mon,day)
			!print *,'L918, jd_today=',jd_today

			! Get julian day for all other totbtadays and open the corresponding input files
			do i = 1,totbtadays
				jd_before = jd_today-i
				! Convert julidan day to gregorian
				call gregorian(jd_before,new_y,new_m,new_d)
				!print *,'L909, jd_before,new_y,new_m,new_d=',jd_before,new_y,new_m,new_d
				call get_filename(new_d,new_m,new_y,filename_ext_atm,filename_ext_RAIN,filename_ext_LH,filename_ext_P)
				call open_netcdf_files(ncid,prencid,lhncid,psfcncid,preid,lhid,uid,vid,wid,tid,qid,ppid,pbid,pblid,psfcid,filename_ext_atm,filename_ext_RAIN,filename_ext_LH,filename_ext_P)

				status = nf90_get_var(lhncid, lhid, evap(:,:,datatotsteps-(datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)), &
				start=(/bdy,bdy,1/),count=(/dim_j,dim_i,datadaysteps/))
				if(status /= nf90_NoErr) call handle_err(status)

				status = nf90_get_var(ncid, qid, temp(:,:,:,:), &
				start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
				if(status /= nf90_NoErr) call handle_err(status)

				q(:,:,:,datatotsteps-(datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)) = temp(:,:,dim_k:1:-1,:)

				status = nf90_get_var(ncid, uid, temp(:,:,:,:), &
				start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
				if(status /= nf90_NoErr) call handle_err(status)

				u(:,:,:,datatotsteps-(datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)) = temp(:,:,dim_k:1:-1,:)

				status = nf90_get_var(ncid, vid, temp(:,:,:,:), &
				start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
				if(status /= nf90_NoErr) call handle_err(status)

				v(:,:,:,datatotsteps-(datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)) = temp(:,:,dim_k:1:-1,:)

				status = nf90_get_var(ncid, wid, temp(:,:,:,:), &
				start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
				if(status /= nf90_NoErr) call handle_err(status)

				w(:,:,:,datatotsteps-(datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)) = temp(:,:,dim_k:1:-1,:)

				status = nf90_get_var(ncid, tid, temp(:,:,:,:), &
				start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
				if(status /= nf90_NoErr) call handle_err(status)

				t(:,:,:,datatotsteps-(datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)) = temp(:,:,dim_k:1:-1,:)

				status = nf90_get_var(ncid, ppid, temp(:,:,:,:), &
				start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
				if(status /= nf90_NoErr) call handle_err(status)

				pp(:,:,:,datatotsteps-(datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)) = temp(:,:,dim_k:1:-1,:)

				status = nf90_get_var(ncid, pbid, temp(:,:,:,:), &
				start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
				if(status /= nf90_NoErr) call handle_err(status)

				pb(:,:,:,datatotsteps-(datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)) = temp(:,:,dim_k:1:-1,:)

				status = nf90_get_var(ncid, pblid, pbl_hgt(:,:,datatotsteps-(datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)), &
				start=(/bdy,bdy,1/),count=(/dim_j,dim_i,datadaysteps/))
				if(status /= nf90_NoErr) call handle_err(status)

				status = nf90_get_var(psfcncid, psfcid, psfc(:,:,datatotsteps-(datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)), &
				start=(/bdy,bdy,1/),count=(/dim_j,dim_i,datadaysteps/))
				if(status /= nf90_NoErr) call handle_err(status)

				print *,'L1018, Input file of previous day loaded successfully:',i,filename_ext_atm

				! close the netcdf files
				status = nf90_close(ncid)
				status = nf90_close(prencid)
				status = nf90_close(lhncid)
				status = nf90_close(psfcncid)

			end do

			! Get julian day for day after sim day (1st timestep needed) and open the corresponding input file
			jd_before = jd_today+1
			call gregorian(jd_before,new_y,new_m,new_d)
			call get_filename(new_d,new_m,new_y,filename_ext_atm,filename_ext_RAIN,filename_ext_LH,filename_ext_P)
			call open_netcdf_files(ncid,prencid,lhncid,psfcncid,preid,lhid,uid,vid,wid,tid,qid,ppid,pbid,pblid,psfcid,filename_ext_atm,filename_ext_RAIN,filename_ext_LH,filename_ext_P)

			status = nf90_get_var(lhncid, lhid, evap(:,:,datatotsteps), &
			start=(/bdy,bdy,1/),count=(/dim_j,dim_i,1/))
			if(status /= nf90_NoErr) call handle_err(status)

			status = nf90_get_var(ncid, qid, temp(:,:,:,1), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,1/))
			if(status /= nf90_NoErr) call handle_err(status)

			q(:,:,:,datatotsteps) = temp(:,:,dim_k:1:-1,1)

			status = nf90_get_var(ncid, uid, temp(:,:,:,1), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,1/))
			if(status /= nf90_NoErr) call handle_err(status)

			u(:,:,:,datatotsteps) = temp(:,:,dim_k:1:-1,1)

			status = nf90_get_var(ncid, vid, temp(:,:,:,1), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,1/))
			if(status /= nf90_NoErr) call handle_err(status)

			v(:,:,:,datatotsteps) = temp(:,:,dim_k:1:-1,1)

			status = nf90_get_var(ncid, wid, temp(:,:,:,1), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,1/))
			if(status /= nf90_NoErr) call handle_err(status)

			w(:,:,:,datatotsteps) = temp(:,:,dim_k:1:-1,1)

			status = nf90_get_var(ncid, tid, temp(:,:,:,1), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,1/))
			if(status /= nf90_NoErr) call handle_err(status)

			t(:,:,:,datatotsteps) = temp(:,:,dim_k:1:-1,1)

			status = nf90_get_var(ncid, ppid, temp(:,:,:,1), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,1/))
			if(status /= nf90_NoErr) call handle_err(status)

			pp(:,:,:,datatotsteps) = temp(:,:,dim_k:1:-1,1)

			status = nf90_get_var(ncid, pbid, temp(:,:,:,1), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,1/))
			if(status /= nf90_NoErr) call handle_err(status)

			pb(:,:,:,datatotsteps) = temp(:,:,dim_k:1:-1,1)

			status = nf90_get_var(ncid, pblid, pbl_hgt(:,:,datatotsteps), &
			start=(/bdy,bdy,1/),count=(/dim_j,dim_i,1/))
			if(status /= nf90_NoErr) call handle_err(status)

			status = nf90_get_var(psfcncid, psfcid, psfc(:,:,datatotsteps), &
			start=(/bdy,bdy,1/),count=(/dim_j,dim_i,1/))
			if(status /= nf90_NoErr) call handle_err(status)

			! close the netcdf files
			status = nf90_close(ncid)
			status = nf90_close(prencid)
			status = nf90_close(lhncid)
			status = nf90_close(psfcncid)

			print *,'L1100, Input file of next day (1st time step) loaded successfully:',filename_ext_atm

		else
			print*, 'If you only want to back-track for one day, must change how input data is retrieved.'

		end if

		!evap converted to mm > Unit conversion checked and OK 18/7/17 :)
		evap = evap*(1440/datadaysteps)*60/Lv

		qt = qt + q ! i.e. SUM(QCLD,QRAIN,QSNOW,QICE) + QVAPOUR
		!qt = q
		qc = qt

	END SUBROUTINE get_data

	!***********************************************************************

	SUBROUTINE open_mixtot_netcdf_files(ncid,clwid,rnwid,snowid,iceid,filename_ext_atm)
	!----------------------------------------------------------------
	! open all the netcdf data files and get the variable ids
	!------------------------------------------------------------------

		USE netcdf
		USE util
		USE global_data

		IMPLICIT NONE

		INTEGER, INTENT(OUT) :: ncid !clwncid,rnwncid,snowncid,icencid
		INTEGER, INTENT(OUT) :: clwid,rnwid,snowid,iceid
		CHARACTER(LEN=100), INTENT(IN) :: filename_ext_atm

		INTEGER :: status

		! open the netcdf files - ATMOSPHERIC VARIABLES
		status = NF90_OPEN(TRIM(dirdata_atm)//TRIM(filename_ext_atm), NF90_NOWRITE, ncid)
		if (status /= NF90_NOERR) call handle_err(status)

		!get ids for each variable
		status = nf90_inq_varid(ncid, "QCLOUD", clwid)		! [kgkg-1]  ! QCLOUD
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inq_varid(ncid, "QRAIN", rnwid)		! [kgkg-1] ! QRAIN
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inq_varid(ncid, "QSNOW", snowid)		! [kgkg-1] ! QSNOW
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inq_varid(ncid, "QICE", iceid)		! [kgkg-1] ! QICE
		if(status /= nf90_NoErr) call handle_err(status)

	END SUBROUTINE open_mixtot_netcdf_files

	!***********************************************************************

	SUBROUTINE get_data_mixtot(qc,qt)
	!-----------------------------------------------
	! read in the data for the first time
	!-----------------------------------------------

		USE global_data
		USE util
		USE netcdf

		IMPLICIT NONE

		REAL, DIMENSION(:,:,:,:) :: qc,qt

		CHARACTER(LEN=100) :: filename_ext_atm,filename_ext_RAIN,filename_ext_LH,filename_ext_P

		REAL, DIMENSION(SIZE(qt,1),SIZE(qt,2),SIZE(qt,3),SIZE(qt,4)) :: clw,rnw,snow,ice
		REAL, DIMENSION(SIZE(qt,1),SIZE(qt,2),SIZE(qt,3),datadaysteps) :: temp

		INTEGER :: ncid
		INTEGER :: clwid,rnwid,snowid,iceid
		INTEGER :: sind,status,sind2,i,getsteps,getsteps2

		REAL :: dayend

		INTEGER :: jd_today,jd_before,new_y,new_m,new_d

		call get_filename(day,mon,year,filename_ext_atm,filename_ext_RAIN,filename_ext_LH,filename_ext_P)

		call open_mixtot_netcdf_files(ncid,clwid,rnwid,snowid,iceid,filename_ext_atm)

		!if this is a day around a storm peak we want the half day after as well
		if (peak) then
			dayend = day + 0.5
		else
			dayend = day
		end if

		!!! SIM DAY SHOULD BE AT THE END OF THE ARRAY, DAY BEFORE JUST BEFORE THAT, ETC.
		!!! LAST BACK-TRACKED DAY SHOULD BE AT THE START OF THE ARRAY.
		!!! THE LAST TIME POSITION IN THE ARRAY SHOULD BE THE FIRST TIMESTEP OF SIM DAY + 1.

		! Since our input files only consist of one day, open all timesteps (datadaysteps) in file (i.e. remove sind2, make it 1)

		! We want the event day + totbtadays before it

		if (totbtadays>1) then
			! Open the first day input file
			status = nf90_get_var(ncid, clwid, temp(:,:,:,:), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
			if(status /= nf90_NoErr) call handle_err(status)

			clw(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)) = temp(:,:,dim_k:1:-1,:)

			status = nf90_get_var(ncid, rnwid, temp(:,:,:,:), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
			if(status /= nf90_NoErr) call handle_err(status)

			rnw(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)) = temp(:,:,dim_k:1:-1,:)

			status = nf90_get_var(ncid, snowid, temp(:,:,:,:), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
			if(status /= nf90_NoErr) call handle_err(status)

			snow(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)) = temp(:,:,dim_k:1:-1,:)

			status = nf90_get_var(ncid, iceid, temp(:,:,:,:), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
			if(status /= nf90_NoErr) call handle_err(status)

			ice(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)) = temp(:,:,dim_k:1:-1,:)

			! close the netcdf file
			status = nf90_close(ncid)

			! Get julian day of current day
			jd_today = julian(year,mon,day)

			! Get julian/gregrorian day for all other totbtadays and open the corresponding input files
			do i = 1,totbtadays
				jd_before = jd_today-i
				! Convert julian day to gregorian
				call gregorian(jd_before,new_y,new_m,new_d)
				call get_filename(new_d,new_m,new_y,filename_ext_atm,filename_ext_RAIN,filename_ext_LH,filename_ext_P)
				call open_mixtot_netcdf_files(ncid,clwid,rnwid,snowid,iceid,filename_ext_atm)

				status = nf90_get_var(ncid, clwid, temp(:,:,:,:), &
				start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
				if(status /= nf90_NoErr) call handle_err(status)

				clw(:,:,:,datatotsteps-(datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)) = temp(:,:,dim_k:1:-1,:)

				status = nf90_get_var(ncid, rnwid, temp(:,:,:,:), &
				start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
				if(status /= nf90_NoErr) call handle_err(status)

				rnw(:,:,:,datatotsteps-(datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)) = temp(:,:,dim_k:1:-1,:)

				status = nf90_get_var(ncid, snowid, temp(:,:,:,:), &
				start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
				if(status /= nf90_NoErr) call handle_err(status)

				snow(:,:,:,datatotsteps-(datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)) = temp(:,:,dim_k:1:-1,:)

				status = nf90_get_var(ncid, iceid, temp(:,:,:,:), &
				start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,datadaysteps/))
				if(status /= nf90_NoErr) call handle_err(status)

				ice(:,:,:,datatotsteps-(datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)) = temp(:,:,dim_k:1:-1,:)

				! close the netcdf file
				status = nf90_close(ncid)
			end do

			! Get julian day for day after sim day (1st timestep needed) and open the corresponding input file
			jd_before = jd_today+1
			call gregorian(jd_before,new_y,new_m,new_d)
			call get_filename(new_d,new_m,new_y,filename_ext_atm,filename_ext_RAIN,filename_ext_LH,filename_ext_P)
			call open_mixtot_netcdf_files(ncid,clwid,rnwid,snowid,iceid,filename_ext_atm)

			status = nf90_get_var(ncid, clwid, temp(:,:,:,1), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,1/))
			if(status /= nf90_NoErr) call handle_err(status)

			clw(:,:,:,datatotsteps) = temp(:,:,dim_k:1:-1,1)

			status = nf90_get_var(ncid, rnwid, temp(:,:,:,1), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,1/))
			if(status /= nf90_NoErr) call handle_err(status)

			rnw(:,:,:,datatotsteps) = temp(:,:,dim_k:1:-1,1)

			status = nf90_get_var(ncid, snowid, temp(:,:,:,1), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,1/))
			if(status /= nf90_NoErr) call handle_err(status)

			snow(:,:,:,datatotsteps) = temp(:,:,dim_k:1:-1,1)

			status = nf90_get_var(ncid, iceid, temp(:,:,:,1), &
			start=(/bdy,bdy,1,1/),count=(/dim_j,dim_i,dim_k,1/))
			if(status /= nf90_NoErr) call handle_err(status)

			ice(:,:,:,datatotsteps) = temp(:,:,dim_k:1:-1,1)

			! close the netcdf file
			status = nf90_close(ncid)

			print *,'L1100, Input file of next day (1st time step) loaded successfully:',filename_ext_atm

		else
			print*, 'If you only want to back-track for one day, must change how input data is retrieved.'
		end if

		qc = clw + rnw + snow + ice
		qt = qc

	END SUBROUTINE get_data_mixtot

	SUBROUTINE get_grid_data(ptop, delx, datatstep, lat2d, lon2d, extents)

		USE global_data, ONLY: syear, smon, sday, dirdata_atm, totpts, bdy, dim_i, dim_j, dim_k, dim_i_start, dim_j_start, dim_k_start
		USE util, ONLY: int_to_string, handle_err, all_positive_longitude
		USE netcdf

		IMPLICIT NONE

		REAL,INTENT(OUT)              :: ptop, delx
		INTEGER, INTENT(OUT)          :: datatstep
		REAL,ALLOCATABLE,DIMENSION(:,:), INTENT(OUT) :: lat2d,lon2d
		!!! extents does nothing for this verison of the subroutine
		REAL,DIMENSION(6), INTENT(IN),OPTIONAL :: extents

		!!! Locals
		CHARACTER(LEN=100):: fname
		INTEGER :: status, headncid, ptopid, delxid, latcrsid, loncrsid, tstepid
		INTEGER :: fdim_i, fdim_j
		REAL,ALLOCATABLE,DIMENSION(:,:) :: lon2d_corrected

		write(fname,'(a,i4.4,a,i2.2,a,i2.2,a)') "wrfout_d01_",syear,"-",smon,"-",sday,"_00:00:00"
		print *,'Get header info from first input file: ',fname
		status = NF90_OPEN(TRIM(dirdata_atm)//fname, NF90_NOWRITE, headncid)
		if (status /= NF90_NOERR) call handle_err(status)

		!----------------------------------------------------------------
		! Get ids for required variables from header

		status = nf90_inq_varid(headncid, "P_TOP", ptopid)  !top pressure in model (Pa)
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inquire_attribute(headncid, nf90_global, "DX", delxid)  !grid distance (m)
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inq_varid(headncid, "XLAT", latcrsid)  !latitudes of grid points (degrees)
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inq_varid(headncid, "XLONG", loncrsid)  !longitudes of grid points (degrees)
		if(status /= nf90_NoErr) call handle_err(status)
		! status = nf90_inq_varid(headncid, "HGT", terid)  !model terrain (m)
		! if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inq_dimid(headncid, "Time", tstepid)  !number of time steps in file
		if(status /= nf90_NoErr) call handle_err(status)

		!----------------------------------------------------------------
		! Read in 1d variables

		status = nf90_get_var(headncid, ptopid, ptop)
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_get_att(headncid, NF90_GLOBAL, "DX",delx)
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_inquire_dimension(headncid, tstepid,len = datatstep)
		datatstep=1440/datatstep ! Value must be 1440/8=180, where 8 is number of timesteps in the file (it was set up this way based on MM5 input files, where MM5 model timestep was 180mins)
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_get_att(headncid, NF90_GLOBAL, "SOUTH-NORTH_GRID_DIMENSION", fdim_i)
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_get_att(headncid, NF90_GLOBAL, "WEST-EAST_GRID_DIMENSION", fdim_j)
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_get_att(headncid, NF90_GLOBAL, "BOTTOM-TOP_GRID_DIMENSION", dim_k)
		if(status /= nf90_NoErr) call handle_err(status)

		dim_k=dim_k-1

		!switch from dots to crosses
		fdim_i = fdim_i-1
		fdim_j = fdim_j-1

		!get i and j dimensions when ignoring the boundaries
		dim_i = fdim_i - 2*(bdy-1)
		dim_j = fdim_j - 2*(bdy-1)

		!Total number of grid pts inside boundaries
		totpts = (dim_j-2)*(dim_i-2)

		! Allocate the required arrays
		ALLOCATE( lon2d(dim_j,dim_i),lat2d(dim_j,dim_i), STAT = status)
		!sigma(dim_k),pstar(dim_j,dim_i,datadaysteps), terrain(dim_j,dim_i)

		!
		! Read in more variables
		!
		status = nf90_get_var(headncid, latcrsid, lat2d,start=(/bdy,bdy/),count=(/dim_j,dim_i/))
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_get_var(headncid, loncrsid, lon2d,start=(/bdy,bdy/),count=(/dim_j,dim_i/))
		if(status /= nf90_NoErr) call handle_err(status)
		! status = nf90_get_var(headncid, terid, terrain,start=(/bdy,bdy/),count=(/dim_j,dim_i/))
		! if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_close(headncid)

		!--------------------------------------------------------
		!Model expects data to range between 0deg and 360deg. Narclim/WRF 2d longitude ranges between -180deg and +180deg. Where the longitude is negative, add 360deg. Replace the raw longitude 2d grid with the corrected one.
		ALLOCATE(lon2d_corrected(dim_j,dim_i))

		call all_positive_longitude(lon2d,lon2d_corrected)

		lon2d=lon2d_corrected

		dim_i_start = bdy
		dim_j_start = bdy
		dim_k_start = 1

	END SUBROUTINE get_grid_data

	SUBROUTINE get_watershed(wsmask)

		USE global_data, ONLY: bdy, diri, fwshed, dim_i, dim_j, dim_i_start, dim_j_start
		USE util, ONLY: handle_err
		USE netcdf

		IMPLICIT NONE

		INTEGER, ALLOCATABLE, DIMENSION(:,:), INTENT(OUT) :: wsmask

		!!! Locals
		CHARACTER(len=100) :: fname
		INTEGER            :: status
		INTEGER            :: wsncid, wsid

		fname=TRIM(diri)//"watershed/"//TRIM(fwshed)

		print *,'using wshed from',fname
		ALLOCATE( wsmask(dim_j,dim_i), STAT = status )
		status = NF90_OPEN(fname, NF90_NOWRITE, wsncid)
		if (status /= NF90_NOERR) call handle_err(status)

		status = nf90_inq_varid(wsncid, "wsmask", wsid)  !watershed mask
		if(status /= nf90_NoErr) call handle_err(status)

		status = nf90_get_var(wsncid, wsid, wsmask,start=(/dim_j_start,dim_i_start/),count=(/dim_j,dim_i/))
		if(status /= nf90_NoErr) call handle_err(status)

		status = nf90_close(wsncid)

	END SUBROUTINE

END MODULE input_data_handling_wrf
#endif
!***********************************************************************
!***********************************************************************
#if defined ERA5
MODULE input_data_handling_era5

	IMPLICIT NONE

	INTERFACE get_era5_field
		MODULE PROCEDURE :: get_era5_field_r1, get_era5_field_r2, get_era5_field_r3, get_era5_field_r4
	END INTERFACE

	CONTAINS

	FUNCTION era5_var_k_v_store(k)

		CHARACTER(LEN=*), INTENT(IN) :: k
		CHARACTER(LEN=5) :: era5_var_k_v_store

		SELECT CASE (k)
		CASE ("RAIN")
			era5_var_k_v_store = "tp"
		CASE ("LH")
			 era5_var_k_v_store = "mslhf"
		CASE ("Psfc")
			era5_var_k_v_store = "sp"
		!CASE ("u")
		!	write(fn,'(a,i4.4,a)') "pressure-levels/reanalysis/u/",yr,"/u_era5_oper_pl_"//suffix               ! CHECKED (assuming v,w also ok)
		!!! Get pressure levels from the coords of one of these files
		!!filename_ext_Plev = "ERA5_4D_pressure.nc"                                               ! Talk to Jason about this
		!CASE ("v")
		!	write(fn,'(a,i4.4,a)') "pressure-levels/reanalysis/v/",yr,"/v_era5_oper_pl_"//suffix
		!CASE ("w")
		!	write(fn,'(a,i4.4,a)') "pressure-levels/reanalysis/w/",yr,"/w_era5_oper_pl_"//suffix
		CASE ("T")
			era5_var_k_v_store = "t"
		!CASE ("q")
		!	write(fn,'(a,i4.4,a)') "pressure-levels/reanalysis/q/",yr,"/q_era5_oper_pl_"//suffix         ! CHECKED
		!CASE ("clwc")
		!	write(fn,'(a,i4.4,a)') "pressure-levels/reanalysis/clwc/",yr,"/clwc_era5_oper_pl_"//suffix
		!CASE ("ciwc")
		!	write(fn,'(a,i4.4,a)') "pressure-levels/reanalysis/ciwc/",yr,"/ciwc_era5_oper_pl_"//suffix
		!CASE ("cswc")
		!	write(fn,'(a,i4.4,a)') "pressure-levels/reanalysis/cswc/",yr,"/cswc_era5_oper_pl_"//suffix
		!CASE ("crwc")
		!	write(fn,'(a,i4.4,a)') "pressure-levels/reanalysis/crwc/",yr,"/crwc_era5_oper_pl_"//suffix
		CASE ("PBLH")
			era5_var_k_v_store = "blh"
		CASE DEFAULT
			era5_var_k_v_store = k
		END SELECT

	END FUNCTION

	!!! This series of functions assumes you've already worked out how
	!!! big these fields are going to be
	SUBROUTINE get_era5_field_r1(d,m,y,field,out,start,count)

		USE netcdf
		USE global_data, ONLY: dirdata_era5, fdim_j, dim_j_start, dim_j_end
		USE util, ONLY: handle_err

		IMPLICIT NONE

		INTEGER, INTENT(IN) :: d,m,y
		CHARACTER(len=*), INTENT(IN) :: field
		REAL, DIMENSION(:) :: out
		INTEGER, OPTIONAL, INTENT(IN) :: start, count

		!!! Locals
		CHARACTER(len=100) :: fn
		INTEGER :: fid, vid
		INTEGER :: status
		REAL    :: scale_factor, add_offset
		INTEGER, DIMENSION(NF90_MAX_VAR_DIMS) :: dimids
		CHARACTER(len=NF90_MAX_NAME) :: dim_name
		INTEGER :: lon_idx = -1

		call get_filename(d,m,y,field,fn)

		status = NF90_OPEN(TRIM(fn),NF90_NOWRITE,fid)
		if (status /= NF90_NOERR) call handle_err(status)

		status = nf90_inq_varid(fid, trim(era5_var_k_v_store(field)), vid)
		if(status /= nf90_NoErr) call handle_err(status)

		!!! Are any of our variable's dimensions longitude?
		status = nf90_inquire_variable(fid,vid,dimids=dimids)
		if(status /= nf90_NoErr) call handle_err(status)

		status = nf90_inquire_dimension(fid,dimids(1),name=dim_name)
		if(status /= nf90_NoErr) call handle_err(status)

		if ( TRIM(dim_name) == "longitude" ) then
			lon_idx = 1
		endif

		if(PRESENT(start)) then
			if(PRESENT(count)) then
				!!! If these conditions are true we're going to cross a periodic boundary
				if( lon_idx > 0 .and. start + count > fdim_j ) then
					status = nf90_get_var(fid,vid,out(:fdim_j-dim_j_start+1),start=(/dim_j_start/),count=(/fdim_j - dim_j_start + 1/))
					if(status /= nf90_NoErr) call handle_err(status)
					status = nf90_get_var(fid,vid,out(fdim_j-dim_j_start+2:),start=(/1/),count=(/dim_j_end/))
				else
					status = nf90_get_var(fid,vid,out,start=(/start/),count=(/count/))
				end if
			else
				status = nf90_get_var(fid,vid,out,start=(/start/))
			end if
		else
			if(PRESENT(count)) then
				status = nf90_get_var(fid,vid,out,count=(/count/))
			else
				status = nf90_get_var(fid,vid,out)
			end if
		end if
		if(status /= nf90_NoErr) call handle_err(status)

		!!! Get scale_factor and add_offset (if any)
    status = nf90_get_att(fid, vid, "scale_factor", scale_factor)
    if( status /= nf90_NoErr ) then
      !!! OK if attribute not found - set it to 1.0
      if ( status /= nf90_eNotAtt ) call handle_err(status)
      scale_factor = 1.0
    endif

    status = nf90_get_att(fid, vid, "add_offset", add_offset)
    if( status /= nf90_NoErr ) then
      !!! OK if attribute not found - set it to 0.0
      if ( status /= nf90_eNotAtt ) call handle_err(status)
      add_offset = 0.0
    endif

		out = scale_factor * out + add_offset

	END SUBROUTINE

	SUBROUTINE get_era5_field_r2(d,m,y,field,out,starts,counts)

		USE netcdf
		USE global_data, ONLY: dirdata_era5, fdim_j, dim_j_start, dim_j_end
		USE util, ONLY: handle_err

		IMPLICIT NONE

		INTEGER, INTENT(IN) :: d,m,y
		CHARACTER(len=*), INTENT(IN) :: field
		REAL, DIMENSION(:,:) :: out
		INTEGER, OPTIONAL, DIMENSION(2), INTENT(IN) :: starts, counts

		!!! Locals
		CHARACTER(len=100) :: fn
		INTEGER :: fid, vid
		INTEGER :: status
		REAL    :: scale_factor, add_offset
		INTEGER, DIMENSION(NF90_MAX_VAR_DIMS) :: dimids
		CHARACTER(len=NF90_MAX_NAME) :: dim_name
		INTEGER :: lon_idx = -1
		INTEGER :: idim

		INTEGER, DIMENSION(2) :: temp_starts
		INTEGER, DIMENSION(2) :: temp_counts
		INTEGER, DIMENSION(2,2) :: read_bounds !!! (/ (/ end1, start2 /), (/ end1, start2 /) /)

		call get_filename(d,m,y,field,fn)

		status = NF90_OPEN(TRIM(fn),NF90_NOWRITE,fid)
		if (status /= NF90_NOERR) call handle_err(status)

		status = nf90_inq_varid(fid, trim(era5_var_k_v_store(field)), vid)
		if(status /= nf90_NoErr) call handle_err(status)

		!!! Are any of our variable's dimensions longitude?
		status = nf90_inquire_variable(fid,vid,dimids=dimids)
		if(status /= nf90_NoErr) call handle_err(status)

		do idim=1,2
			status = nf90_inquire_dimension(fid,dimids(idim),name=dim_name)
			if(status /= nf90_NoErr) call handle_err(status)

			if ( TRIM(dim_name) == "longitude" ) then
				lon_idx = idim
				read_bounds(:,idim) = (/ fdim_j-dim_j_start+1, fdim_j-dim_j_start+2  /)
			else
				read_bounds(:,idim) = (/ size(out,dim=idim),1 /)
			endif
		end do

		if(PRESENT(starts)) then
			if(PRESENT(counts)) then
				if( lon_idx > 0 .and. starts(lon_idx) + counts(lon_idx) > fdim_j ) then
					temp_starts = starts
					temp_counts = counts
					temp_starts(lon_idx) = dim_j_start
					temp_counts(lon_idx) = fdim_j - dim_j_start + 1
					status = nf90_get_var(fid,vid,out(:read_bounds(1,1),:read_bounds(1,2)),start=temp_starts,count=temp_counts)
					if(status /= nf90_NoErr) call handle_err(status)
					temp_starts(lon_idx) = 1
					temp_counts(lon_idx) = dim_j_end
					status = nf90_get_var(fid,vid,out(read_bounds(2,1):,read_bounds(2,2):),start=temp_starts,count=temp_counts)
				else
					status = nf90_get_var(fid,vid,out,start=starts,count=counts)
				end if
			else
				status = nf90_get_var(fid,vid,out,start=starts)
			end if
		else
			if(PRESENT(counts)) then
				status = nf90_get_var(fid,vid,out,count=counts)
			else
				status = nf90_get_var(fid,vid,out)
			end if
		end if
		if(status /= nf90_NoErr) call handle_err(status)

		!!! Get scale_factor and add_offset (if any)
    status = nf90_get_att(fid, vid, "scale_factor", scale_factor)
    if( status /= nf90_NoErr ) then
      !!! OK if attribute not found - set it to 1.0
      if ( status /= nf90_eNotAtt ) call handle_err(status)
      scale_factor = 1.0
    endif

    status = nf90_get_att(fid, vid, "add_offset", add_offset)
    if( status /= nf90_NoErr ) then
      !!! OK if attribute not found - set it to 0.0
      if ( status /= nf90_eNotAtt ) call handle_err(status)
      add_offset = 0.0
    endif

		out = scale_factor * out + add_offset

	END SUBROUTINE

	SUBROUTINE get_era5_field_r3(d,m,y,field,out,starts,counts)

		USE netcdf
		USE global_data, ONLY: dirdata_era5, fdim_j, dim_j_start, dim_j_end
		USE util, ONLY: handle_err

		IMPLICIT NONE

		INTEGER, INTENT(IN) :: d,m,y
		CHARACTER(len=*), INTENT(IN) :: field
		REAL, DIMENSION(:,:,:) :: out
		INTEGER, OPTIONAL, DIMENSION(3), INTENT(IN) :: starts, counts

		!!! Locals
		CHARACTER(len=100) :: fn
		INTEGER :: fid, vid
		INTEGER :: status
		REAL    :: scale_factor, add_offset
		INTEGER, DIMENSION(NF90_MAX_VAR_DIMS) :: dimids
		CHARACTER(len=NF90_MAX_NAME) :: dim_name
		INTEGER :: lon_idx = -1
		INTEGER :: idim

		INTEGER, DIMENSION(3) :: temp_starts
		INTEGER, DIMENSION(3) :: temp_counts
		INTEGER, DIMENSION(2,3) :: read_bounds !!! (/ (/ end1, start2 /), (/ end1, start2 /), (/ end1, start2 /) /)

		call get_filename(d,m,y,field,fn)

		status = NF90_OPEN(TRIM(fn),NF90_NOWRITE,fid)
		if (status /= NF90_NOERR) call handle_err(status)

		status = nf90_inq_varid(fid, trim(era5_var_k_v_store(field)), vid)
		if(status /= nf90_NoErr) call handle_err(status)

		!!! Are any of our variable's dimensions longitude?
		status = nf90_inquire_variable(fid,vid,dimids=dimids)
		if(status /= nf90_NoErr) call handle_err(status)

		do idim=1,3
			status = nf90_inquire_dimension(fid,dimids(idim),name=dim_name)
			if(status /= nf90_NoErr) call handle_err(status)

			if ( TRIM(dim_name) == "longitude" ) then
				lon_idx = idim
				read_bounds(:,idim) = (/ fdim_j-dim_j_start+1, fdim_j-dim_j_start+2  /)
			else
				read_bounds(:,idim) = (/ size(out,dim=idim),1 /)
			endif
		end do

		if(PRESENT(starts)) then
			if(PRESENT(counts)) then
				if( lon_idx > 0 .and. starts(lon_idx) + counts(lon_idx) > fdim_j ) then
					temp_starts = starts
					temp_counts = counts
					temp_starts(lon_idx) = dim_j_start
					temp_counts(lon_idx) = fdim_j - dim_j_start + 1
					status = nf90_get_var(fid,vid,out(:read_bounds(1,1),:read_bounds(1,2),:read_bounds(1,3)),start=temp_starts,count=temp_counts)
					if(status /= nf90_NoErr) call handle_err(status)
					temp_starts(lon_idx) = 1
					temp_counts(lon_idx) = dim_j_end
					status = nf90_get_var(fid,vid,out(read_bounds(2,1):,read_bounds(2,2):,read_bounds(2,3):),start=temp_starts,count=temp_counts)
				else
					status = nf90_get_var(fid,vid,out,start=starts,count=counts)
				end if
			else
				status = nf90_get_var(fid,vid,out,start=starts)
			end if
		else
			if(PRESENT(counts)) then
				status = nf90_get_var(fid,vid,out,count=counts)
			else
				status = nf90_get_var(fid,vid,out)
			end if
		end if
		if(status /= nf90_NoErr) call handle_err(status)

		!!! Get scale_factor and add_offset (if any)
		status = nf90_get_att(fid, vid, "scale_factor", scale_factor)
		if( status /= nf90_NoErr ) then
		  !!! OK if attribute not found - set it to 1.0
		  if ( status /= nf90_eNotAtt ) call handle_err(status)
		  scale_factor = 1.0
		endif

		status = nf90_get_att(fid, vid, "add_offset", add_offset)
		if( status /= nf90_NoErr ) then
		  !!! OK if attribute not found - set it to 0.0
		  if ( status /= nf90_eNotAtt ) call handle_err(status)
		  add_offset = 0.0
		endif

		out = scale_factor * out + add_offset

	END SUBROUTINE

	SUBROUTINE get_era5_field_r4(d,m,y,field,out,starts,counts)

		USE netcdf
		USE global_data, ONLY: dirdata_era5, fdim_j, dim_j_start, dim_j_end, dim_i, dim_j
		USE util, ONLY: handle_err

		IMPLICIT NONE

		INTEGER, INTENT(IN) :: d,m,y
		CHARACTER(len=*), INTENT(IN) :: field
		REAL, DIMENSION(:,:,:,:) :: out
		INTEGER, OPTIONAL, DIMENSION(4), INTENT(IN) :: starts, counts

		!!! Locals
		CHARACTER(len=100) :: fn
		INTEGER :: fid, vid
		INTEGER :: status
		REAL    :: scale_factor, add_offset
		INTEGER, DIMENSION(NF90_MAX_VAR_DIMS) :: dimids
		CHARACTER(len=NF90_MAX_NAME) :: dim_name
		INTEGER :: lon_idx = -1
		INTEGER :: idim

		INTEGER, DIMENSION(4) :: temp_starts
		INTEGER, DIMENSION(4) :: temp_counts
		INTEGER, DIMENSION(2,4) :: read_bounds !!! (/ (/ end1, start2 /), (/ end1, start2 /), (/ end1, start2 /), (/ end1, start2 /) /)

		INTEGER :: latid,lonid,vlatid,vlonid, stat

		call get_filename(d,m,y,field,fn)

		status = NF90_OPEN(TRIM(fn),NF90_NOWRITE,fid)
		if (status /= NF90_NOERR) call handle_err(status)

		status = nf90_inq_varid(fid, trim(era5_var_k_v_store(field)), vid)
		if(status /= nf90_NoErr) call handle_err(status)

				!!! Are any of our variable's dimensions longitude?
		status = nf90_inquire_variable(fid,vid,dimids=dimids)
		if(status /= nf90_NoErr) call handle_err(status)

		do idim=1,4
			status = nf90_inquire_dimension(fid,dimids(idim),name=dim_name)
			if(status /= nf90_NoErr) call handle_err(status)

			if ( TRIM(dim_name) == "longitude" ) then
				lon_idx = idim
				read_bounds(:,idim) = (/ fdim_j-dim_j_start+1, fdim_j-dim_j_start+2  /)
			else
				read_bounds(:,idim) = (/ size(out,dim=idim),1 /)
			endif
		end do

		if(PRESENT(starts)) then
			if(PRESENT(counts)) then
				if( lon_idx > 0 .and. starts(lon_idx) + counts(lon_idx) > fdim_j ) then
					temp_starts = starts
					temp_counts = counts
					temp_starts(lon_idx) = dim_j_start
					temp_counts(lon_idx) = fdim_j - dim_j_start + 1
					status = nf90_get_var(fid,vid,out(:read_bounds(1,1),:read_bounds(1,2),:read_bounds(1,3),:read_bounds(1,4)),start=temp_starts,count=temp_counts)
					if(status /= nf90_NoErr) call handle_err(status)
					temp_starts(lon_idx) = 1
					temp_counts(lon_idx) = dim_j_end
					status = nf90_get_var(fid,vid,out(read_bounds(2,1):,read_bounds(2,2):,read_bounds(2,3):,read_bounds(2,4):),start=temp_starts,count=temp_counts)
				else
					status = nf90_get_var(fid,vid,out,start=starts,count=counts)
				end if
			else
				status = nf90_get_var(fid,vid,out,start=starts)
			end if
		else
			if(PRESENT(counts)) then
				status = nf90_get_var(fid,vid,out,count=counts)
			else
				status = nf90_get_var(fid,vid,out)
			end if
		end if
		if(status /= nf90_NoErr) call handle_err(status)

		!!! Get scale_factor and add_offset (if any)
    status = nf90_get_att(fid, vid, "scale_factor", scale_factor)
    if( status /= nf90_NoErr ) then
      !!! OK if attribute not found - set it to 1.0
      if ( status /= nf90_eNotAtt ) call handle_err(status)
      scale_factor = 1.0
    endif

    status = nf90_get_att(fid, vid, "add_offset", add_offset)
    if( status /= nf90_NoErr ) then
      !!! OK if attribute not found - set it to 0.0
      if ( status /= nf90_eNotAtt ) call handle_err(status)
      add_offset = 0.0
    endif

		out = scale_factor * out + add_offset

	END SUBROUTINE

	SUBROUTINE get_filename(d,mn,yr,field,fn)

		!-----------------------------------------------
		! given the month and year get the filename extension string
		!---------------------------------------------------

		USE global_data, ONLY: dirdata_era5
		USE util, ONLY: month_end, to_iso_date

		IMPLICIT NONE

		INTEGER, INTENT(IN) :: d
		INTEGER, INTENT(IN) :: mn, yr
		CHARACTER(LEN=*), INTENT(IN) :: field
		CHARACTER(LEN=100), INTENT(OUT) :: fn
		! len('YYYYMMDD-YYYYMMDD.nc') = 20
		CHARACTER(LEN=20) :: suffix
		CHARACTER(LEN=5)  :: era5_field

		suffix = to_iso_date(yr,mn,1)//"-"//to_iso_date(yr,mn,month_end(yr,mn))//".nc"
		era5_field = era5_var_k_v_store(field)

		SELECT CASE(trim(era5_field))
		CASE("tp","mslhf","sp","blh","tcw")
			write(fn,'(a,i4.4,a)') TRIM(dirdata_era5)//"single-levels/reanalysis/"//trim(era5_field)//"/",yr,"/"//trim(era5_field)//"_era5_oper_sfc_"//suffix   ! CHECKED
		CASE DEFAULT
			write(fn,'(a,i4.4,a)') TRIM(dirdata_era5)//"pressure-levels/reanalysis/"//trim(era5_field)//"/",yr,"/"//trim(era5_field)//"_era5_oper_pl_"//suffix   ! CHECKED
		fn = ADJUSTL(fn)
		END SELECT

	END SUBROUTINE get_filename

	SUBROUTINE get_grid_data(ptop, delx, datatstep, lat2d, lon2d, extents)

		USE global_data, ONLY: syear, smon, sday, dirdata_era5, totpts, bdy, datansteps, dim_i_start, dim_j_start, dim_k_start, dim_i, dim_j, dim_k, fdim_i, fdim_j, dim_i_end, dim_j_end, dim_k_end
		USE util, ONLY: int_to_string, handle_err, all_positive_longitude, to_iso_date, month_end, array_extents
		USE netcdf

		IMPLICIT NONE

		REAL,INTENT(OUT)                             :: ptop, delx
		INTEGER, INTENT(OUT)                         :: datatstep
		REAL,ALLOCATABLE,DIMENSION(:,:), INTENT(OUT) :: lat2d,lon2d
		REAL,DIMENSION(6), INTENT(IN),OPTIONAL       :: extents

		!!! Locals
		INTEGER :: status
		INTEGER :: headncid, tstepid, latcrsid, loncrsid, levelid
		INTEGER :: fdim_k
		INTEGER :: idim
		REAL, ALLOCATABLE, DIMENSION(:) :: lat1d, lon1d, levels

		REAL, DIMENSION(2)              :: input_timeseries
		CHARACTER(len=100) :: fname

		write(fname,'(a,i4.4,a)') TRIM(dirdata_era5)//"pressure-levels/reanalysis/q/",syear,"/q_era5_oper_pl_"//to_iso_date(syear,smon,1)//"-"//to_iso_date(syear,smon,month_end(syear,smon))//".nc"
		print *,'using header from',fname
		status = NF90_OPEN(fname, NF90_NOWRITE, headncid)
		if (status /= NF90_NOERR) call handle_err(status)

		! Read the length of each dimension of input data
		status = nf90_inq_dimid(headncid, "time", tstepid)  ! number of time steps in file
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_inq_dimid(headncid, "latitude", latcrsid)  !latitudes of grid points (degrees)
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_inq_dimid(headncid, "longitude", loncrsid)  !longitudes of grid points (degrees)
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_inq_dimid(headncid, "level", levelid)  ! pressure levels of dataset
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_inquire_dimension(headncid, tstepid, len = datansteps)
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_inquire_dimension(headncid, latcrsid, len = fdim_i)
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_inquire_dimension(headncid, loncrsid, len = fdim_j)
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_inquire_dimension(headncid, levelid, len = fdim_k)
		if (status /= NF90_NOERR) call handle_err(status)

		allocate(lat1d(fdim_i),lon1d(fdim_j),levels(fdim_k))

		status = nf90_inq_varid(headncid, "latitude", latcrsid)
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_get_var(headncid, latcrsid, lat1d)
		if(status /= nf90_NoErr) call handle_err(status)

		status = nf90_inq_varid(headncid, "longitude", loncrsid)
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_get_var(headncid, loncrsid, lon1d)
		if(status /= nf90_NoErr) call handle_err(status)

		status = nf90_inq_varid(headncid, "level", levelid)
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_get_var(headncid, levelid, levels)
		if(status /= nf90_NoErr) call handle_err(status)

		status = nf90_inq_varid(headncid, "time", tstepid)
		if(status /= nf90_NoErr) call handle_err(status)

		! Time dimension - just take the difference between the first two values as the file timestep
		status = nf90_get_var(headncid, tstepid, input_timeseries, start=(/1/), count=(/2/))
		if(status /= nf90_NoErr) call handle_err(status)
  !!! Future TO-DO - This could be automated to read units of time from header file
		datatstep = 60*(input_timeseries(2) - input_timeseries(1)) ! model expects timestep in minutes


		if( present(extents) ) then
			call array_extents(lat1d, extents(1),extents(2),dim_i_start,dim_i_end,reverse=.true.)
			call array_extents(lon1d, extents(3),extents(4),dim_j_start,dim_j_end,periodic=.true.)
			call array_extents(levels,extents(5),extents(6),dim_k_start,dim_k_end)
			dim_i_start = dim_i_start + bdy
			dim_j_start = dim_j_start + bdy
			dim_i_end   = dim_i_end - bdy
			dim_j_end   = dim_j_end - bdy
		else
			!!! extents not present, must want global grid
			dim_i_end  = fdim_i - bdy
			dim_j_end  = fdim_j - bdy
			dim_k_end  = fdim_k
			dim_i_start = 1 + bdy
			dim_j_start = 1 + bdy
			dim_k_start = 1
		endif

		dim_i = dim_i_end - dim_i_start + 1
		!!! dim_j is longitude and is periodic
		if ( dim_j_end > dim_j_start ) then
			dim_j = dim_j_end - dim_j_start + 1
		else
			dim_j = fdim_j - dim_j_start + dim_j_end + 1
		end if
		dim_k = dim_k_end - dim_k_start + 1

		allocate(lat2d(dim_j,dim_i))
		allocate(lon2d(dim_j,dim_i))

		do idim = 1,dim_j
			lat2d(idim,:) = lat1d(dim_i_start:dim_i_end)
		end do

		!!! Handle periodicity in longitude
		if ( dim_j_start < dim_j_end ) then
			do idim = 1,dim_i
				lon2d(:,idim) = lon1d(dim_j_start:dim_j_end)
			end do
		else
			do idim = 1,dim_i
				lon2d(1:fdim_j-dim_j_start+1,idim) = lon1d(dim_j_start:fdim_j)
				lon2d(fdim_j-dim_j_start+2:dim_j,idim) = lon1d(1:dim_j_end)
			end do
		end if

		call all_positive_longitude(lon2d,lon2d)

		!! mBar -> Pa
		ptop = levels(dim_k_start)*100.0

		!!! TESTING - THIS NEEDS TO BE AUTOMATED
		! Calculation of ssdim requires delx of the grid.
		delx=25202.112430956095



print *, 'dim_k_start,dim_k_end,ptop',dim_k_start,dim_k_end,ptop

  

	END SUBROUTINE

	SUBROUTINE get_watershed(wsmask)

		USE global_data, ONLY: diri_era5, fwshed_era5,dim_i,dim_j,dim_i_start, dim_j_start, dim_j_end, fdim_j
		USE util, ONLY: handle_err
		USE netcdf

		IMPLICIT NONE

		INTEGER, ALLOCATABLE, DIMENSION(:,:), INTENT(OUT) :: wsmask

		!!! Locals
		INTEGER :: wsncid, wsid, status
		CHARACTER(len=100) :: fname
		INTEGER :: stat

		fname=TRIM(diri_era5)//TRIM(fwshed_era5)

		print *,'using wshed from',fname
		ALLOCATE( wsmask(dim_j,dim_i), STAT = status )

		status = NF90_OPEN(fname, NF90_NOWRITE, wsncid)
		if (status /= NF90_NOERR) call handle_err(status)

		status = nf90_inq_varid(wsncid, "wsmask", wsid)  !watershed mask
		if(status /= nf90_NoErr) call handle_err(status)

		if ( dim_j_start < dim_j_end ) then
			status = nf90_get_var(wsncid, wsid, wsmask,start=(/dim_j_start, dim_i_start/), count=(/dim_j, dim_i/))
		else
			status = nf90_get_var(wsncid, wsid, wsmask(1:fdim_j-dim_j_start+1,:),start=(/dim_j_start, dim_i_start/), count=(/fdim_j-dim_j_start+1, dim_i/))
			if(status /= nf90_NoErr) call handle_err(status)
			status = nf90_get_var(wsncid, wsid, wsmask(fdim_j-dim_j_start+2:dim_j,:),start=(/1, dim_i_start/), count=(/dim_j_end, dim_i/))
		end if
  	if(status /= nf90_NoErr) call handle_err(status)

		status = nf90_close(wsncid)
		if(status /= nf90_NoErr) call handle_err(status)

	END SUBROUTINE

	!!! Future TO-DO - rewrite this and get_data to open each era5 file only once
	!!! Future TO-DO - rewrite this to use a rolling window to avoid re-reading over
	!!!                back trajectory days
	SUBROUTINE get_data_mixtot(qc,qt)

		USE global_data, ONLY: peak, datatotsteps, datadaysteps, dim_i, dim_j, dim_k, dim_i_start, dim_j_start, dim_k_start, day, mon, year, water_density, totbtadays, sday
		USE util, ONLY: julian, gregorian, month_end

		IMPLICIT NONE

		REAL, DIMENSION(:,:,:,:) :: qc,qt

		!!! Locals
		REAL, DIMENSION(SIZE(qt,1),SIZE(qt,2),SIZE(qt,3),SIZE(qt,4)) :: clw,rnw,snow,ice
		INTEGER :: jd_today, jd_before
		INTEGER :: new_y, new_m, new_d
		INTEGER :: i
		REAL    :: dayend

		ice = 9999.0

		if (peak) then
			dayend = day + 0.5
		else
			dayend = day
		end if

		if (totbtadays>1) then

			call get_era5_field(day, mon, year, "clwc",  clw(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)), starts=(/dim_j_start, dim_i_start, dim_k_start,(day-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))
			call get_era5_field(day, mon, year, "crwc",  rnw(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)), starts=(/dim_j_start, dim_i_start, dim_k_start,(day-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))
			call get_era5_field(day, mon, year, "cswc", snow(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)), starts=(/dim_j_start, dim_i_start, dim_k_start,(day-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))
			call get_era5_field(day, mon, year, "ciwc",  ice(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)), starts=(/dim_j_start, dim_i_start, dim_k_start,(day-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))

			jd_today = julian(year,mon,day)

			do i = 1,totbtadays
				jd_before = jd_today-i
				call gregorian(jd_before,new_y,new_m,new_d)

				call get_era5_field(new_d, new_m, new_y, "clwc",  clw(:,:,:,(datatotsteps-datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)), starts=(/dim_j_start, dim_i_start, dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))
				call get_era5_field(new_d, new_m, new_y, "crwc",  rnw(:,:,:,(datatotsteps-datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)), starts=(/dim_j_start, dim_i_start, dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))
				call get_era5_field(new_d, new_m, new_y, "cswc", snow(:,:,:,(datatotsteps-datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)), starts=(/dim_j_start, dim_i_start, dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))
				call get_era5_field(new_d, new_m, new_y, "ciwc",  ice(:,:,:,(datatotsteps-datadaysteps*(i+1)):(datatotsteps-(datadaysteps*i)-1)), starts=(/dim_j_start, dim_i_start, dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))
			end do

			jd_before = jd_today+1
			call gregorian(jd_before,new_y,new_m,new_d)

			call get_era5_field(new_d, new_m, new_y, "clwc",  clw(:,:,:,datatotsteps:datatotsteps), starts=(/dim_j_start, dim_i_start, dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,1/))
			call get_era5_field(new_d, new_m, new_y, "crwc",  rnw(:,:,:,datatotsteps:datatotsteps), starts=(/dim_j_start, dim_i_start, dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,1/))
			call get_era5_field(new_d, new_m, new_y, "cswc", snow(:,:,:,datatotsteps:datatotsteps), starts=(/dim_j_start, dim_i_start, dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,1/))
			call get_era5_field(new_d, new_m, new_y, "ciwc",  ice(:,:,:,datatotsteps:datatotsteps), starts=(/dim_j_start, dim_i_start, dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,1/))

			print *,'Input mixtot file of next day (1st time step) loaded successfully'
		else
			print*, 'If you only want to back-track for one day, must change how input data is retrieved.'
		end if

		qc = clw + rnw + snow + ice
		qt = qc

		print *, 'finished getting data mixtot'
		!print *, 'ice(1,1,1,:)', ice(1,1,1,:)

	END SUBROUTINE

	SUBROUTINE get_data(precip,evap,u,v,w,t,q,qc,qt,pp,pb,pbl_hgt,psfc,tcw)

		USE global_data, ONLY: day, mon, year, dim_i, dim_j, dim_k, dim_i_start, dim_j_start, dim_k_start, sday, datadaysteps, totbtadays, datatotsteps, sday, syear, smon, peak, water_density, Lv, dirdata_era5
		USE util, ONLY: julian, gregorian, to_iso_date, month_end, handle_err
		USE netcdf

		IMPLICIT NONE

		REAL, DIMENSION(:,:,:) :: precip,evap,pbl_hgt,psfc,tcw
		REAL, DIMENSION(:,:,:,:) :: u,v,w,t,q,qc,qt,pp
		!REAL, DIMENSION(SIZE(u,1),SIZE(u,2),SIZE(u,3),datadaysteps) :: temp

		!!! Not used for ERA5
		REAL, DIMENSION(:,:,:,:) :: pb

		!!! Locals
		INTEGER :: jd_today, jd_before, new_y, new_m, new_d
		INTEGER :: i, ik, it
		INTEGER :: status, headncid, levelid, fdim_k
		REAL :: dayend
		CHARACTER(len=100) :: fname
		REAL, ALLOCATABLE, DIMENSION(:) :: levels

		call get_data_mixtot(qc,qt)

		!if this is a day around a storm peak we want the half day after as well
		if (peak) then
		  dayend = day + 0.5
		else
		  dayend = day
		end if

		print *, 'up to start of loading get data'

		if (totbtadays>1) then

			call get_era5_field(day, mon, year, "RAIN", precip, starts=(/dim_j_start, dim_i_start, (day-1)*datadaysteps+1/), counts=(/dim_j,dim_i,datadaysteps/))

			call get_era5_field(day, mon, year,  "LH",   evap(:,:,(datatotsteps-datadaysteps):(datatotsteps-1)), starts=(/dim_j_start, dim_i_start, (day-1)*datadaysteps+1/), counts=(/dim_j,dim_i,datadaysteps/))
			call get_era5_field(day, mon, year,"Psfc",   psfc(:,:,(datatotsteps-datadaysteps):(datatotsteps-1)), starts=(/dim_j_start, dim_i_start, (day-1)*datadaysteps+1/), counts=(/dim_j,dim_i,datadaysteps/))
			call get_era5_field(day, mon, year,"PBLH",pbl_hgt(:,:,(datatotsteps-datadaysteps):(datatotsteps-1)), starts=(/dim_j_start, dim_i_start, (day-1)*datadaysteps+1/), counts=(/dim_j,dim_i,datadaysteps/))
			call get_era5_field(day, mon, year, "tcw",    tcw(:,:,(datatotsteps-datadaysteps):(datatotsteps-1)), starts=(/dim_j_start, dim_i_start, (day-1)*datadaysteps+1/), counts=(/dim_j,dim_i,datadaysteps/))

			call get_era5_field(day, mon, year,"q",q(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)), starts=(/dim_j_start, dim_i_start,dim_k_start,(day-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))
			call get_era5_field(day, mon, year,"u",u(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)), starts=(/dim_j_start, dim_i_start,dim_k_start,(day-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))
			call get_era5_field(day, mon, year,"v",v(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)), starts=(/dim_j_start, dim_i_start,dim_k_start,(day-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))
			call get_era5_field(day, mon, year,"w",w(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)), starts=(/dim_j_start, dim_i_start,dim_k_start,(day-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))
			call get_era5_field(day, mon, year,"T",t(:,:,:,(datatotsteps-datadaysteps):(datatotsteps-1)), starts=(/dim_j_start, dim_i_start,dim_k_start,(day-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))

			! Get julian day of current day
			jd_today = julian(year,mon,day)
			print *,'jd_today=',jd_today

			do i = 1,totbtadays
				jd_before = jd_today-i
				call gregorian(jd_before,new_y,new_m,new_d)

				call get_era5_field(new_d, new_m, new_y,   "LH",   evap(:,:,(datatotsteps-(datadaysteps*(i+1))):(datatotsteps-(datadaysteps*i)-1)), starts=(/dim_j_start, dim_i_start, (new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,datadaysteps/))
				call get_era5_field(new_d, new_m, new_y, "Psfc",   psfc(:,:,(datatotsteps-(datadaysteps*(i+1))):(datatotsteps-(datadaysteps*i)-1)), starts=(/dim_j_start, dim_i_start, (new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,datadaysteps/))
				call get_era5_field(new_d, new_m, new_y, "PBLH",pbl_hgt(:,:,(datatotsteps-(datadaysteps*(i+1))):(datatotsteps-(datadaysteps*i)-1)), starts=(/dim_j_start, dim_i_start, (new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,datadaysteps/))
				call get_era5_field(new_d, new_m, new_y,  "tcw",    tcw(:,:,(datatotsteps-(datadaysteps*(i+1))):(datatotsteps-(datadaysteps*i)-1)), starts=(/dim_j_start, dim_i_start, (new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,datadaysteps/))

				call get_era5_field(new_d, new_m, new_y,"q",q(:,:,:,(datatotsteps-(datadaysteps*(i+1))):(datatotsteps-(datadaysteps*i)-1)), starts=(/dim_j_start, dim_i_start,dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))
				call get_era5_field(new_d, new_m, new_y,"u",u(:,:,:,(datatotsteps-(datadaysteps*(i+1))):(datatotsteps-(datadaysteps*i)-1)), starts=(/dim_j_start, dim_i_start,dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))
				call get_era5_field(new_d, new_m, new_y,"v",v(:,:,:,(datatotsteps-(datadaysteps*(i+1))):(datatotsteps-(datadaysteps*i)-1)), starts=(/dim_j_start, dim_i_start,dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))
				call get_era5_field(new_d, new_m, new_y,"w",w(:,:,:,(datatotsteps-(datadaysteps*(i+1))):(datatotsteps-(datadaysteps*i)-1)), starts=(/dim_j_start, dim_i_start,dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))
				call get_era5_field(new_d, new_m, new_y,"T",t(:,:,:,(datatotsteps-(datadaysteps*(i+1))):(datatotsteps-(datadaysteps*i)-1)), starts=(/dim_j_start, dim_i_start,dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,datadaysteps/))

				print *,'Input files of days to be back-tracked loaded successfully'
			end do

			jd_before = jd_today+1
			call gregorian(jd_before,new_y,new_m,new_d)

			call get_era5_field(new_d, new_m, new_y,   "LH",   evap(:,:,datatotsteps:datatotsteps), starts=(/dim_j_start, dim_i_start, (new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,1/))
			call get_era5_field(new_d, new_m, new_y, "Psfc",   psfc(:,:,datatotsteps:datatotsteps), starts=(/dim_j_start, dim_i_start, (new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,1/))
			call get_era5_field(new_d, new_m, new_y, "PBLH",pbl_hgt(:,:,datatotsteps:datatotsteps), starts=(/dim_j_start, dim_i_start, (new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,1/))
			call get_era5_field(new_d, new_m, new_y, "tcw" ,    tcw(:,:,datatotsteps:datatotsteps), starts=(/dim_j_start, dim_i_start, (new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,1/))

			call get_era5_field(new_d, new_m, new_y,"q",q(:,:,:,datatotsteps:datatotsteps), starts=(/dim_j_start, dim_i_start,dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,1/))
			call get_era5_field(new_d, new_m, new_y,"u",u(:,:,:,datatotsteps:datatotsteps), starts=(/dim_j_start, dim_i_start,dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,1/))
			call get_era5_field(new_d, new_m, new_y,"v",v(:,:,:,datatotsteps:datatotsteps), starts=(/dim_j_start, dim_i_start,dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,1/))
			call get_era5_field(new_d, new_m, new_y,"w",w(:,:,:,datatotsteps:datatotsteps), starts=(/dim_j_start, dim_i_start,dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,1/))
			call get_era5_field(new_d, new_m, new_y,"T",t(:,:,:,datatotsteps:datatotsteps), starts=(/dim_j_start, dim_i_start,dim_k_start,(new_d-1)*datadaysteps+1/), counts=(/dim_j,dim_i,dim_k,1/))

			print *,'Input file of next day (1st time step) loaded successfully'
		else
			print*, 'If you only want to back-track for one day, must change how input data is retrieved.'
		end if

		! ERA5 mean surface latent heat flux (mslhf) is given in W/m2. The ECMWF convention for vertical fluxes is positive downwards. https://codes.ecmwf.int/grib/param-db/235034
		! J/s/m2 * kg/J [1/Lv] * m3/kg [1/water density] * 60*60 [sec] * 1000 [mm] >> mm over the hourly data timestep
		evap = evap*1/Lv*1/water_density*60*60*1000 ! mm over the hour data timestep

		qt = qt + q ! i.e. SUM(QCLD,QRAIN,QSNOW,QICE) + QVAPOUR
		!qt = q
		qc = qt

		!!! Pressure is special, derive it from a coordinate
		write(fname,'(a,i4.4,a)') TRIM(dirdata_era5)//"pressure-levels/reanalysis/q/",syear,"/q_era5_oper_pl_"//to_iso_date(syear,smon,1)//"-"//to_iso_date(syear,smon,month_end(syear,smon))//".nc"
		print *,'using header from',fname
		status = NF90_OPEN(fname, NF90_NOWRITE, headncid)
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_inq_dimid(headncid, "level", levelid)  ! pressure levels of dataset
		if (status /= NF90_NOERR) call handle_err(status)
		status = nf90_inquire_dimension(headncid, levelid, len = fdim_k)
		if (status /= NF90_NOERR) call handle_err(status)
		allocate(levels(fdim_k))
		status = nf90_inq_varid(headncid, "level", levelid)
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_get_var(headncid, levelid, levels)
		if(status /= nf90_NoErr) call handle_err(status)
		status = nf90_close(headncid)
		if(status /= nf90_NoErr) call handle_err(status)

  print *,'dim_k_start',dim_k_start
  print *,'levels',levels
  print *,'levels(1)',levels(1)
  print *,'levels(dim_k)',levels(dim_k)
  

		do it = 1,datatotsteps
			do ik = 1,dim_k
				!! mBar -> Pa
				!pp(:,:,ik,it) = levels(dim_k_start-1)*100.0
                pp(:,:,ik,it) = levels(dim_k_start - 1 + ik)*100.0
			end do
		end do

  print *, 'pp(1,1,:,1)', pp(1,1,:,1)



	END SUBROUTINE

END MODULE input_data_handling_era5
#endif

PROGRAM back_traj

	USE netcdf
	USE util
	USE global_data
	USE bt_subs
	USE omp_lib

#if defined ERA5
	USE input_data_handling_era5, ONLY: get_grid_data, get_data, get_watershed
#else
	USE input_data_handling_wrf, ONLY: get_grid_data, get_data, get_watershed
#endif

	IMPLICIT NONE

	!
	!netcdf id variables
	!
	INTEGER :: status
	INTEGER :: outncid,wvcid,wvc2id,xlocid,ylocid,dayid,opreid
	!
	!data variables
	!
	INTEGER :: par_lev
	REAL :: ptop,delx,par_lat,par_lon,par_pres,par_q,new_par_q,end_precip
	INTEGER :: datatstep
	REAL,ALLOCATABLE,DIMENSION(:,:) :: lat2d,lon2d
	REAL,ALLOCATABLE,DIMENSION(:,:) :: terrain,WV_cont,WV_cont_day
	REAL,ALLOCATABLE,DIMENSION(:,:) :: WV_cont_apbl,WV_cont_day_apbl
	REAL,ALLOCATABLE,DIMENSION(:,:,:) :: precip
	REAL,ALLOCATABLE,DIMENSION(:,:,:) :: evap,tpw,pbl_hgt,surf_pres,pstar,psfc,tcw
	REAL,ALLOCATABLE,DIMENSION(:,:,:,:) :: u,v,w,temp,act_temp,mix,pp,pb,pw,mixcld,mixtot,pres
	!REAL,ALLOCATABLE,DIMENSION(:,:,:,:) :: pot_temp !
	REAL,ALLOCATABLE,DIMENSION(:,:,:,:) :: unow,vnow,wnow
	REAL,ALLOCATABLE,DIMENSION(:,:,:) :: pres_then,tempnow
	!REAL,ALLOCATABLE,DIMENSION(:,:,:) :: pot_temp_then !
	REAL,ALLOCATABLE,DIMENSION(:,:) :: psfc_then
        INTEGER,ALLOCATABLE,DIMENSION(:,:,:) :: pbl_lev

	INTEGER,ALLOCATABLE,DIMENSION(:) :: par_release
	INTEGER :: xx,yy,tt,nn,mm,npar,orec,x,y,ttdata,nnMM5,ttdataday
	INTEGER :: xx_omp,threadnum,torec
	REAL :: ttfac,nnfac,precip_here,qfac,wv_fac

	INTEGER,ALLOCATABLE,DIMENSION(:,:) :: wsmask

	INTEGER :: ssx,ssy

	INTEGER :: iii,jjj,ttt

	LOGICAL :: print_test

	!I want dd and totpts to persist inside and outside parallel regions and subroutines
	!so they have been added to the global_data module and declared threadprivate

	!for outputting the parcel stats for each parcel
	REAL,ALLOCATABLE,DIMENSION(:,:) :: parcel_stats


	!----------------------------------------------------------------
	! Retrieve simulation start and end dates, and output directory, from the command line input

	INTEGER :: num_args
	character(len=100), dimension(:), allocatable :: args
	num_args = command_argument_count()
	allocate(args(num_args))  ! I've omitted checking the return status of the allocation

	call get_command_argument(1,args(1))
	sday = string_to_int(args(1))
	call get_command_argument(2,args(2))
	smon = string_to_int(args(2))
	call get_command_argument(3,args(3))
	syear = string_to_int(args(3))
	call get_command_argument(4,args(4))
	edday = string_to_int(args(4))
	call get_command_argument(5,args(5))
	edmon = string_to_int(args(5))
	call get_command_argument(6,args(6))
	edyear = string_to_int(args(6))
	call get_command_argument(7,args(7))
	diro = args(7)

	print *,"Results saved to: ",diro

	! Find total number of days to run simulation for, given input start and end dates
	totdays=simlength(sday,smon,syear,edday,edmon,edyear)

	print *,"Total days to run analysis=",totdays
	print *,"Total number of back-track days=",totbtadays
	print *,"Number of parcels=",nparcels
	print *,"Simulation time step (mins)=",tstep


	!----------------------------------------------------------------
	! Get header info from first input file
	!!! Note that values in the extents array MUST match coord points in the data       
        !!! extents = (/ start_lat, end_lat, start_lon, end_lon, start_level, end_level /) levels in hPa
        !Australia Case 
	!call get_grid_data(ptop, delx, datatstep, lat2d, lon2d, (/ -50.5, 0.5, 89.75, -130.0, 100.0, 1000.0 /) )
        !Pakistan case
        call get_grid_data(ptop, delx, datatstep, lat2d, lon2d, (/ -40., 60., 20., -150., 100.,1000. /) )
        !Scotland case
        !call get_grid_data(ptop, delx, datatstep, lat2d, lon2d, (/ 20., 85., -180., 120., 100., 1000. /) )
	!--------------------------------------------------------

     print *,"dim_j, dim_i, dim_k",dim_j,dim_i, dim_k
     !print *, 'lat2d(1,:)',lat2d(1,:)
     !print *, 'lon2d(:,1)',lon2d(:,1)


	!
	! Calculate the number of trajectory time steps in a day and in input file time step
	!
	daytsteps = 1440/tstep                ! number of sub-daily simulation time steps
	indatatsteps = datatstep/tstep          ! divide input file time step by the number of simulation time steps, as they may differ
	totsteps = daytsteps*(totbtadays+1)   ! total number of simulation data time steps to remember

	datadaysteps = 1440/datatstep           ! number of input file time steps in day
	datatotsteps = (datadaysteps*(totbtadays+1)) + 1 ! total number of input file time steps over the back-track period


    
    print *,'simulation time step [mins] (tstep): ',tstep
    print *,'input data timestep [mins] (datatstep): ',datatstep
    print *,'no. of time intervals per daily file (datadaysteps): ',datadaysteps
    !print *,'no. of simulation timesteps per input file (daytsteps): ',daytsteps
    print *, 'no. of simulation timesteps per day (daytsteps): ', daytsteps
    print *,'no. of simulation timesteps per input file time interval (indatatsteps): ',indatatsteps
    print *,'total no. of back-track simulation timesteps to remember (totsteps): ',totsteps
    print *,'total no. of back-track input file time intervals (datatotsteps): ',datatotsteps
    print *, 'datansteps', datansteps


	! Allocate the variable arrays
	ALLOCATE( precip(dim_j,dim_i,datadaysteps), &
	          evap(dim_j,dim_i,datatotsteps),   &
						 tpw(dim_j,dim_i,datatotsteps),   &
		   surf_pres(dim_j,dim_i,datatotsteps),   &
			   pbl_hgt(dim_j,dim_i,datatotsteps),   &
			   pbl_lev(dim_j,dim_i,datatotsteps),   &
            psfc(dim_j,dim_i,datatotsteps),   &
						 tcw(dim_j,dim_i,datatotsteps),   &

						   u(dim_j,dim_i,dim_k,datatotsteps), &
	             v(dim_j,dim_i,dim_k,datatotsteps), &
							 w(dim_j,dim_i,dim_k,datatotsteps), &
						temp(dim_j,dim_i,dim_k,datatotsteps), &
	      act_temp(dim_j,dim_i,dim_k,datatotsteps), &
	! pot_temp(dim_j,dim_i,dim_k,datatotsteps), &
	           mix(dim_j,dim_i,dim_k,datatotsteps), &
						  pp(dim_j,dim_i,dim_k,datatotsteps), &
							pb(dim_j,dim_i,dim_k,datatotsteps), &
	        mixtot(dim_j,dim_i,dim_k,datatotsteps), &
					     pw(dim_j,dim_i,dim_k,daytsteps+1), &
	        mixcld(dim_j,dim_i,dim_k,datatotsteps), &
					  pres(dim_j,dim_i,dim_k,datatotsteps), &
	                                    STAT = status )

	!
	! Read in watershed mask if required
	!
	if (wshed) then
		call get_watershed(wsmask)
	end if

	! Total number of grid pts inside boundaries
	totpts = (dim_j-2)*(dim_i-2)

	! Set the number of threads to use in the parallel sections
	call OMP_SET_NUM_THREADS(numthreads)

	!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	! FOR EVERY DAY OF THE SIMULATION PERIOD
	!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	do dd = 1, totdays
		orec = 0

		!Get date to open correct input file
		call day_month_year(dd)
		print *,"day,mon,year",day,mon,year

		! Create output file (will create empty file even if it didn't rain anywhere in the domain on that day)
		call new_out_file(outncid,wvcid,wvc2id,xlocid,ylocid,dayid,opreid,day,lat2d,lon2d)
		print *,'created new out file'

		! Get the variables required for back trajectory calculations for the current day
		call get_data(precip,evap,u,v,w,temp,mix,mixcld,mixtot,pp,pb,pbl_hgt,psfc,tcw)

		print *,'got data...'

		! Calculate the pressure field and surface pressure
		! In previous (MM5-based) model, surface pressure had to be calculated - not so here, it is output from wrf.
		! Pressure at heights is calculated by adding the base state pressure to the perturbation pressure at each level.
		! pp="P"(4d)perturbation pressure. pb="PB"(4d)base state pressure. psfc="PSFC"(3d) surface pressure.
#if defined ERA5
		! ERA5 gives total precipitation in m. Multiply by 1000 to get it in mm as model expects.
		precip = precip * 1000
		! ERA5 takes vertical fluxes as positive downwards. This means that evaporation (upwards away from the surface) will often be negative.
		! I'm going to reverse the sign here:
		evap = -evap
		pres = pp ! No need to add a perturbation pressure with ERA5 data
		surf_pres = psfc

		!calculate the model level just above the boundary layer height
		!call calc_pbl_lev(pbl_hgt,pres,surf_pres,pbl_lev)
  
		! wrfout gives T as pertubation potential temperature. Model expects actual temperature, so convert it:
		! No need with ERA5 data
		! call calc_actual_temp(temp,pres,act_temp)
		act_temp = temp

		! Calculate the precipitable water accumulated from the ground up on day of interest (lat,lon,height,time). 
		! This is used to determine the parcel initial height.
		! Note that pw has an extra timestep in length, to allow the lin_interp_inMM5tsteps(pw) to interpolate between 2 values at the end.
		call calc_pw(mixtot(:,:,:,datatotsteps-datadaysteps:),pres(:,:,:,datatotsteps-datadaysteps:),surf_pres(:,:,datatotsteps-datadaysteps:),ptop,pw)


		! Calculate the total precipitable water (lat,lon,time).
		call calc_tpw(mixtot,pres,surf_pres,ptop,tpw)

        ! Check how tpw in the PBL differs
        !call calc_tpw_pbl(mixtot,pres,surf_pres,tpw,pbl_lev)

        !print *, 'evap(1,1,:10)',evap(1,1,:10)
        !print *, 'tpw(1,1,:10)',tpw(1,1,:10)
        !print *, 'pres(1,1,:,2)',pres(1,1,:,2)
        !print *, 'psfc(1,1,2)',psfc(1,1,2)
        !print *, 'tcw(1,1,:10)',tcw(1,1,:10)
        !print *, 'pw(1,1,:,2)',pw(1,1,:,2)
        !print *, 'u(1,1,:,2)',u(1,1,:,2)
        !print *, 'v(1,1,:,2)',v(1,1,:,2)
        !print *, 'w(1,1,:,2)',w(1,1,:,2)
        !print *, 'pbl_lev(1,1,:10)',pbl_lev(1,1,:10)
        !print *, 'lon2d(:,1)',lon2d(:,1)

#else
		pres = pp + pb
		surf_pres = psfc


		! *Potential temperature and equivalent potential temperature can be calculated here.*

		!calculate the model level just above the boundary layer height
		call calc_pbl_lev(pbl_hgt,pres,surf_pres,pbl_lev)

		! wrfout gives T as pertubation potential temperature. Model expects actual temperature, so convert it:
		call calc_actual_temp(temp,pres,act_temp)

		! Calculate the precipitable water accumulated from the ground up on day of interest (lat,lon,height,time). 
		! This is used to determine the parcel initial height.
		! Note that pw has an extra timestep in length, to allow the lin_interp_inMM5tsteps(pw) to interpolate between 2 values at the end.
		call calc_pw(mixtot(:,:,:,datatotsteps-datadaysteps:),pres(:,:,:,datatotsteps-datadaysteps:),surf_pres(:,:,datatotsteps-datadaysteps:),ptop,pw)

		! Calculate the total precipitable water (lat,lon,time).
		call calc_tpw(mixtot,pres,surf_pres,ptop,tpw)

#endif



		! Calculate the subsection x & y dimensions, based on the max distance a parcel can travel in the sim timestep
		ssdim = (ceiling((sqrt(maxval(u)**2+maxval(v)**2)*tstep*60)/delx) *2) + 1

		!loop over x and y grid points
		!

		!parallelize over the grid points
		!ie each grid point will be sent to a new thread
		!program will wait until all grid points are complete before
		!moving on to next day

		!it remains unclear to me but it seems that I have to include
		!all calls to subroutines in critical sections even when they
		!don't do anything like changing values of shared variables etc
		!I can't actually find documentation to confirm this but it doesn't
		!seem to work otherwise!!!????

		print *, 'Starting parallelisation'
!$OMP PARALLEL DEFAULT(PRIVATE) SHARED(pw,tpw,u,v,w,pres,act_temp,surf_pres,evap,precip,mix,mixtot,pbl_lev,lat2d,lon2d,orec,outncid,wvcid,wvc2id,xlocid,ylocid,dayid,opreid,wsmask,daytsteps,totsteps,indatatsteps,datadaysteps,datatotsteps,dim_i,dim_j,dim_k,sday,smon,syear,mon,year,day,dd,totpts,ssdim)
		!allocate these arrays for each thread
		ALLOCATE( WV_cont(dim_j,dim_i),WV_cont_day(dim_j,dim_i), &
				WV_cont_apbl(dim_j,dim_i),WV_cont_day_apbl(dim_j,dim_i), &
				unow(ssdim,ssdim,dim_k,2),vnow(ssdim,ssdim,dim_k,2), &
				par_release(daytsteps), &
				!pot_temp_then(ssdim,ssdim,dim_k), &
				pres_then(ssdim,ssdim,dim_k),wnow(ssdim,ssdim,dim_k,2), &
				psfc_then(ssdim,ssdim),tempnow(ssdim,ssdim,dim_k), &
				STAT = status)

if (eachParcel) then
    ALLOCATE(parcel_stats(14,totsteps), STAT = status)
end if

  
!$OMP DO &
!$OMP SCHEDULE (DYNAMIC)
		!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		! FOR EVERY POINT IN THE GRID
		!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		do xx_omp = 0, totpts-1

			xx = 2 + AINT(xx_omp*1./(dim_i-2))
			yy = 2 + (xx_omp - (xx-2)*(dim_i-2))

			threadnum = OMP_GET_THREAD_NUM()
			!threadnum = 0

			! Only do something if within watershed, if we care about the watershed
			if (wshed) then
				if (wsmask(xx,yy)==0) CYCLE
			end if

			! Only do something if rain fell at this point on this day
			if (SUM(precip(xx,yy,:))>minpre) then

				!$OMP CRITICAL (output_index)
				orec = orec + 1
				torec = orec
    
				! *Output results per parcel can be specified here.*
         	if (eachParcel) then
         	  OPEN(unit=threadnum+10,file=TRIM(diro)//"parcel"//TRIM(int_to_string(dd))//"_"//TRIM(int_to_string(orec)), &
         	  	form="UNFORMATTED",status="REPLACE") 
         	  !print *,threadnum+10
         	end if 

				!$OMP END CRITICAL (output_index)
    

				WV_cont_day = 0.
				!WV_cont_day_apbl = 0.


				!
				! Determine how many parcels to release today and use precip
				! distribution to determine when to release parcels.
				! The globally set nparcels is just a maximum number of parcels
				! to release in each data timestep. We release at least one parcel
				! per simulation timestep within a data time step when it rained.
				! npar calculates how many parcels to release that day. parcel_release_time
				! spreads that number of parcels out of the 144 timesteps depending on
				! when it rained.
				!

				par_release = 0

				!$OMP CRITICAL (par_rel_time)
				if (COUNT(MASK = precip(xx,yy,:)>0.)<(nparcels/indatatsteps)) then
					npar = COUNT(MASK = precip(xx,yy,:)>0.) * indatatsteps
					call parcel_release_time(precip(xx,yy,:),npar,par_release)
				else
					npar = nparcels
					call parcel_release_time(precip(xx,yy,:),npar,par_release)
				end if
				!$OMP END CRITICAL (par_rel_time)
	

				! * Parcel release height can be set here if you want to remove randomness.*

				!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
				! FOR EVERY SIMULATION SUB-DAILY TIMESTEP
				!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
				do tt = 1, daytsteps
					if (par_release(tt)==0) then
						CYCLE
					end if

					!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
					! FOR EVERY LOT OF PARCELS
					!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
					do mm = 1, par_release(tt)

						WV_cont = 0.
						!WV_cont_apbl = 0.
						qfac = 1.
						wv_fac = 1.
						x = xx
						y = yy

						!the input data time step before this parcel time step on the rain day
						ttdataday = INT((tt-1)/indatatsteps) + 1

						!the input data time step from the beginning of the loaded files
						ttdata = datatotsteps - datadaysteps - 1 + ttdataday

						!factor for linear interpolation to parcel time step
						ttfac = MOD(tt,indatatsteps)*1./indatatsteps

						!the precip produced here at this parcel time step
						end_precip = precip(xx,yy,ttdataday)/indatatsteps


						!determine model level from which to release parcel
						!$OMP CRITICAL (par_rel_height)
						call parcel_release_height(pw(xx,yy,:,tt),par_lev)
						print *,'psfc ',surf_pres(xx,yy,tt)
                                                !par_lev = 35 ! this is 950hPa when loading all ERA5 model levels
						!$OMP END CRITICAL (par_rel_height)

						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						!release the parcel and track the back trajectory
						!until all of initial precipitable water is accounted for
						!or the parcel leaves the domain
						!or the user specified time to calculate the back trajectory runs out
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						!
						! We always release parcels from the centre of the grid cell. I think this differs to D&B: See D&B 2007 Figure 1.
						par_lat = lat2d(xx,yy)
						par_lon = lon2d(xx,yy)

						!$OMP CRITICAL (par_q1)
						! Calculate the parcel mixing ratio. This is used in the calculation of new parcel level in new_parcel_level_w.
						par_q = lin_interp(mixtot(xx,yy,par_lev,ttdata:ttdata+1),ttfac)
						!$OMP END CRITICAL (par_q1)

						! * Parcel potential temperature was calculated here.*

						!$OMP CRITICAL (par_pres1)
						! Calculate parcel pressure.This is used in the calculation of new parcel level in new_parcel_level_w.
						par_pres = lin_interp(pres(xx,yy,par_lev,ttdata:ttdata+1),ttfac)
						!$OMP END CRITICAL (par_pres1)

						!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
						! FOR EACH PARCEL RELEASE TIME, FOR EACH SIMULATION TIME STEP IN THE
						! WHOLE BACK-TRACK PERIOD
						!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
						do nn = totsteps-daytsteps+tt, 2, -1
							!
							!advect the parcel back in time one step
							!

                            !current parcel stats
                            if (eachParcel) then
                                !print *,"nn ",nn,threadnum,par_lev
                                parcel_stats(1,totsteps-daytsteps+tt+1-nn) = nn*1.
                                parcel_stats(2,totsteps-daytsteps+tt+1-nn) = xx
                                parcel_stats(3,totsteps-daytsteps+tt+1-nn) = yy
                                parcel_stats(4,totsteps-daytsteps+tt+1-nn) = par_lon
                                parcel_stats(5,totsteps-daytsteps+tt+1-nn) = par_lat
                                parcel_stats(6,totsteps-daytsteps+tt+1-nn) = par_pres
                                parcel_stats(7,totsteps-daytsteps+tt+1-nn) = par_lev
                                parcel_stats(8,totsteps-daytsteps+tt+1-nn) = par_q
                                parcel_stats(9,totsteps-daytsteps+tt+1-nn) = u(x,y,par_lev,ttdata)
                                parcel_stats(10,totsteps-daytsteps+tt+1-nn) = v(x,y,par_lev,ttdata)
                                parcel_stats(11,totsteps-daytsteps+tt+1-nn) = w(x,y,par_lev,ttdata)
                            end if
							!
							!calculate the lower left location for the subsection
							!
							if (x+floor(ssdim/2.)>dim_j) then
								ssx = dim_j - ssdim + 1
							else
								ssx = max(x-floor(ssdim/2.),1)
							end if

							if (y+floor(ssdim/2.)>dim_i) then
								ssy = dim_i - ssdim + 1
							else
								ssy = max(y-floor(ssdim/2.),1)
							end if

							! Find where you are in the simlength 3-hourly timeseries
							nnMM5 = INT(nn/indatatsteps) + 1
							nnfac = MOD(nn,indatatsteps)*1./indatatsteps

							!
							!get u,v and temp for this and the previous parcel time step (just subsection)
							!

							!$OMP CRITICAl (unow1)
							unow(:,:,:,2) = lin_interp3D(u(ssx:ssx+ssdim-1,ssy:ssy+ssdim-1,:,nnMM5:nnMM5+1),nnfac)
							!$OMP END CRITICAl (unow1)

							!$OMP CRITICAl (vnow1)
							vnow(:,:,:,2) = lin_interp3D(v(ssx:ssx+ssdim-1,ssy:ssy+ssdim-1,:,nnMM5:nnMM5+1),nnfac)
							!$OMP END CRITICAl (vnow1)

							!$OMP CRITICAl (wnow1)
							wnow(:,:,:,2) = lin_interp3D(w(ssx:ssx+ssdim-1,ssy:ssy+ssdim-1,:,nnMM5:nnMM5+1),nnfac)
							!$OMP END CRITICAl (wnow1)

							!$OMP CRITICAl (tempnow1)
							! The temperature (now) is used to determine the temperature of the parcel before it's advected. (The initial pressure of the parcel was already calculated before nn. Subsequent parcel pressures, as the parcel is moved backward in each time step, are determined within the back-trajectory routine, or more specifically, during the routine to determine the parcel's new height (i.e. pressure).)
							tempnow(:,:,:) = lin_interp3D(act_temp(ssx:ssx+ssdim-1,ssy:ssy+ssdim-1,:,nnMM5:nnMM5+1),nnfac)
							!$OMP END CRITICAl (tempnow1)

							! Find where you are in the nn timeseries
							nnMM5 = INT((nn-1)/indatatsteps) + 1
							nnfac = MOD(nn-1,indatatsteps)*1./indatatsteps

							!$OMP CRITICAl (unow2)
							unow(:,:,:,1) = lin_interp3D(u(ssx:ssx+ssdim-1,ssy:ssy+ssdim-1,:,nnMM5:nnMM5+1),nnfac)
							!$OMP END CRITICAl (unow2)

							!$OMP CRITICAl (vnow2)
							vnow(:,:,:,1) = lin_interp3D(v(ssx:ssx+ssdim-1,ssy:ssy+ssdim-1,:,nnMM5:nnMM5+1),nnfac)
							!$OMP END CRITICAl (vnow2)

							!$OMP CRITICAl (wnow2)
							wnow(:,:,:,1) = lin_interp3D(w(ssx:ssx+ssdim-1,ssy:ssy+ssdim-1,:,nnMM5:nnMM5+1),nnfac)
							!$OMP END CRITICAl (wnow2)

							!!$OMP CRITICAl (pot_temp2)
							!pot_temp_then(:,:,:) = lin_interp3D(pot_temp(ssx:ssx+ssdim,ssy:ssy+ssdim,:,nnMM5:nnMM5+1),nnfac)
							!!$OMP END CRITICAl (pot_temp2)

							!$OMP CRITICAl (presthen2)
							pres_then(:,:,:) = lin_interp3D(pres(ssx:ssx+ssdim-1,ssy:ssy+ssdim-1,:,nnMM5:nnMM5+1),nnfac)
							!$OMP END CRITICAl (presthen2)

							!$OMP CRITICAl (psfcthen)
							psfc_then(:,:) = lin_interp2D(surf_pres(ssx:ssx+ssdim-1,ssy:ssy+ssdim-1,nnMM5:nnMM5+1),nnfac)
							!$OMP END CRITICAl (psfcthen)


							! SPECIFY WHICH VERSION OF THE BACK-TRAJECTORY YOU WANT TO USE
							! Here parcels move with vertical wind speed (w) and have their new pressures calculated using actual temp

							!$OMP CRITICAL (trajw)
							call implicit_back_traj_w(unow,vnow,wnow,tempnow,pres_then,psfc_then,lon2d(ssx:ssx+ssdim-1,ssy:ssy+ssdim-1),lat2d(ssx:ssx+ssdim-1,ssy:ssy+ssdim-1),par_lon,par_lat,par_lev,par_pres,par_q,threadnum)
							!$OMP END CRITICAL (trajw)

							! Find the grid cell nearest the new lat,lon of the parcel
							!$OMP CRITICAL (near)
							! While in the first time step the parcel x,y may be the same cell as the parcel was released from, as you back-track that parcel in time the x,y will change.
							call near_pt(lon2d,lat2d,par_lon,par_lat,x,y)
							!$OMP END CRITICAL (near)

							! Find the water mass contribution of the new grid square, at this time	      !
							!$OMP CRITICAL (new_par_q1)
							new_par_q = lin_interp(mixtot(x,y,par_lev,nnMM5:nnMM5+1),nnfac)
							!$OMP END CRITICAL (new_par_q1)
							!
							!adjust the q reduction factor if we had a decrease in q
							!so long as it isn't the first time step.
							! i.e. If the amount of water in the atmosphere at the parcel position decreases backward in time, then the parcel q at the current time step must not have come from the cell evap...maybe from some other process like convection.
							!
							if (nn < totsteps-daytsteps+tt) then
								if (new_par_q+min_del_q < par_q) then
									qfac = MAX(qfac*(1-(par_q-new_par_q)/par_q),0.)
								end if
							end if

#if defined ERA5

                            !! TO DO - create user setting whether you want to split the PBL or not
                            
                            !was moisture contributed to the parcel?
							!is the parcel in the pbl?
                            ! Unlike WRF, ERA5 evap and twp units are consistent, so no need to divde by indatatsteps.   
							!$OMP CRITICAL (wv_cont1)
							!if (par_lev >= pbl_lev(x,y,nnMM5+1)) then
    							if (lin_interp(evap(x,y,nnMM5:nnMM5+1),nnfac) > 0.) then
    								WV_cont(x,y) = WV_cont(x,y) + (lin_interp(evap(x,y,nnMM5:nnMM5+1),nnfac) &
    										/ (indatatsteps*lin_interp(tpw(x,y,nnMM5:nnMM5+1),nnfac))) * wv_fac
									wv_fac = qfac * (1-(lin_interp(evap(x,y,nnMM5:nnMM5+1),nnfac) &
									/ (indatatsteps*lin_interp(tpw(x,y,nnMM5:nnMM5+1),nnfac))) )
    							end if
							!else
    						!	if (par_q < new_par_q-min_del_q) then
    						!	    WV_cont_apbl(x,y) = WV_cont_apbl(x,y) + ((new_par_q - par_q)/par_q)*qfac
    						!	end if
							!end if
							!$OMP END CRITICAL (wv_cont1)

#else

							!was moisture contributed to the parcel?
							!is the parcel in the pbl?
							! NOTE: Evap is mm/3hr, whereas tpw is mm. So we divide tpw by indatatsteps to make the units consistent.
							!$OMP CRITICAL (wv_cont1)
							if (par_lev >= pbl_lev(x,y,nnMM5+1)) then
    							if (lin_interp(evap(x,y,nnMM5:nnMM5+1),nnfac) > 0.) then
    								WV_cont(x,y) = WV_cont(x,y) + (lin_interp(evap(x,y,nnMM5:nnMM5+1),nnfac) &
    										/ (indatatsteps*lin_interp(tpw(x,y,nnMM5:nnMM5+1),nnfac)))
    							end if
							else
    							if (par_q < new_par_q-min_del_q) then
    							    WV_cont_apbl(x,y) = WV_cont_apbl(x,y) + ((new_par_q - par_q)/par_q)*qfac
    							end if
							end if
							!$OMP END CRITICAL (wv_cont1)

#endif

							par_q = new_par_q

                            !saving parcel stats
                            if (eachParcel) then
                                parcel_stats(12,totsteps-daytsteps+tt+1-nn) = evap(x,y,ttdata)
                                parcel_stats(13,totsteps-daytsteps+tt+1-nn) = tpw(x,y,ttdata)
                                parcel_stats(14,totsteps-daytsteps+tt+1-nn) = WV_cont(x,y)
                            end if
              

							!
							!if we have accounted for all the precip  then go to next parcel
							!
							!if (SUM(WV_cont + WV_cont_apbl)>=1.) then
							if (SUM(WV_cont)>=1.) then
								!print *,"all precip accounted (torec,wv_cont) ",torec,SUM(WV_cont + WV_cont_apbl)
								!if (par_lev >= pbl_lev(x,y,nnMM5+1)) then
								WV_cont(x,y) = WV_cont(x,y) - (SUM(WV_cont) - 1)
    							!	WV_cont(x,y) = WV_cont(x,y) - (SUM(WV_cont+WV_cont_apbl) - 1)
								!else
    							!	WV_cont_apbl(x,y) = WV_cont_apbl(x,y) - (SUM(WV_cont+WV_cont_apbl) - 1)
								!end if
								EXIT
							end if

							!
							!if qfac = 0 then all of the increases in the water vapor
							!further back along the trajectory are lost before reaching
							!the end precipitation point so they don't contribute and
							!there is no need to continue
							!
							!the water not accounted for must have come from convection
							!or some other process that remains unaccounted for
							!
							if (qfac==0) then
								EXIT
							end if

							!if we have left the domain then assign the remaining precip to
							!outside and go to next parcel

       !!! This sction needs modifying if splitting PBL
							!
							if (x<2) then
								WV_cont(1,y) = 1. - SUM(WV_cont)
								EXIT
							else if (x>dim_j-2) then
								WV_cont(dim_j,y) = 1. - SUM(WV_cont)
								EXIT
							end if
							if (y<2) then
								WV_cont(x,1) = 1. - SUM(WV_cont)
								EXIT
							else if (y>dim_i-2) then
								WV_cont(x,dim_i) = 1. - SUM(WV_cont)
								EXIT
							end if

							!
							!if we have reached here and nn=2 then we have neither left the
							!domain nor acounted for the precip in the allocated back-track period (didn't go back far enough in time).
							!
							if (nn==2) then
								if (SUM(WV_cont)<0) then
									write(*,*) "SUM(WV_cont)<0"
									STOP
								end if
								!if (SUM(WV_cont+WV_cont_apbl)<0) STOP
							end if

						end do   !nn loop

						! wv_cont(x,y) is a 2d grid of E/TPW values. The grid is added to for every nn parcel back-track. E.g. in one 10min daytstep, we might release 1 parcel. This parcel will calculate the contribution from every cell in the grid. However we could release more, like 5 parcels. The contribution from the grid should be the same no matter how many parcels we release. So we take the average grid contribution per parcel released.
						WV_cont_day = WV_cont_day + WV_cont/npar
						!WV_cont_day_apbl = WV_cont_day_apbl + WV_cont_apbl/npar

						if (par_lev==0) then
							write(*,*) "par_lev==0"
							STOP
						end if

                        !if keeping track of each parcel
                        if (eachParcel) then
                            !print *,"output",threadnum+10
                            WRITE(threadnum+10) parcel_stats
                            CLOSE(threadnum+10)
                        end if

                        !print *, 'parcel_stats(:,:10)', parcel_stats(:,:2)

					end do  !mm loop

				end do  !tt loop

				!
				!write output to netcdf file
				!
				!$OMP CRITICAL (output)
				status = nf90_put_var(outncid,wvcid,WV_cont_day,start=(/1,1,torec/),count=(/dim_j,dim_i,1/))
				if(status /= nf90_NoErr) call handle_err(status)
				!status = nf90_put_var(outncid,wvc2id,WV_cont_day_apbl,start=(/1,1,torec/),count=(/dim_j,dim_i,1/))
				!if(status /= nf90_NoErr) call handle_err(status)
				status = nf90_put_var(outncid,xlocid,xx,start=(/torec/))
				if(status /= nf90_NoErr) call handle_err(status)
				status = nf90_put_var(outncid,ylocid,yy,start=(/torec/))
				if(status /= nf90_NoErr) call handle_err(status)
				status = nf90_put_var(outncid,dayid,dd,start=(/torec/))
				if(status /= nf90_NoErr) call handle_err(status)
				status = nf90_put_var(outncid,opreid,SUM(precip(xx,yy,:)),start=(/torec/))
				if(status /= nf90_NoErr) call handle_err(status)
				!$OMP END CRITICAL (output)

			! 	else
			! 	print *,'No rain in the domain on this day'
			end if

		end do   !xx_omp loop
		!$OMP END DO NOWAIT
		!$OMP END PARALLEL

		status = nf90_close(outncid)
		if(status /= nf90_NoErr) call handle_err(status)

	end do !! dd loop

END PROGRAM back_traj
