#!/bin/bash
#PBS -N BTrIMS_ERA5
#PBS -P x77
#PBS -q normal
#PBS -l walltime=05:00:00
#PBS -l ncpus=48
#PBS -l mem=15GB
#PBS -l jobfs=10MB
#PBS -l storage=gdata/tp28+gdata/hh5+gdata/w28+gdata/w35+gdata/ks32+gdata/eg3+gdata/rt52+gdata/zv2+gdata/w97

ulimit -s unlimited 
module load intel-compiler netcdf
export OMP_STACKSIZE=2G
export OMP_NUM_THREADS=48

ifort -DERA5 -fpp /home/603/cxh603/CLEX/QIBT_ERA5/Model/BTrIMS/BTrIMS.f90 -lnetcdff -lnetcdf -qopenmp -o /home/603/cxh603/CLEX/QIBT_ERA5/Model/BTrIMS/main
/home/603/cxh603/CLEX/QIBT_ERA5/Model/BTrIMS/main 25 02 2022 26 02 2022 /g/data/w97/cxh603/QIBT_ERA5/outputs/era5_testing/ > /home/603/cxh603/CLEX/QIBT_ERA5/Model/terminal_output.txt


###ifort -O3 -c -DERA5 -fpp /home/603/cxh603/CLEX/QIBT_ERA5/Model/BTrIMS/BTrIMS.f90 -lnetcdff -lnetcdf -qopenmp -traceback
###ifort -O3 -lnetcdff -lnetcdf -qopenmp /home/603/cxh603/CLEX/QIBT_ERA5/Model/BTrIMS/BTrIMS.o -o /home/603/cxh603/CLEX/QIBT_ERA5/Model/BTrIMS/main
###/home/603/cxh603/CLEX/QIBT_ERA5/Model/BTrIMS/main 25 02 2022 26 02 2022 /g/data/w97/cxh603/QIBT_ERA5/outputs/era5_testing/ > /home/603/cxh603/CLEX/QIBT_ERA5/Model/terminal_output.txt

###ifort -DERA5 -fpp /home/603/cxh603/CLEX/QIBT_ERA5/Model/BTrIMS/BTrIMS.f90 -lnetcdff -lnetcdf -qopenmp
###/home/603/cxh603/CLEX/QIBT_ERA5/Model/B-TrIMS/a.out 25 02 2022 26 02 2022 /g/data/w97/cxh603/QIBT_ERA5/outputs/era5_testing/ > /home/603/cxh603/CLEX/QIBT_ERA5/Model/terminal_output.txt
