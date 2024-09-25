#!/bin/bash
#PBS -N test0_GPU
#PBS -P w40
#PBS -q gpuvolta
#PBS -l walltime=10:00:00
#PBS -l ncpus=12
#PBS -l ngpus=1
#PBS -l mem=300GB
#PBS -l jobfs=100MB
#PBS -l storage=gdata/hh5+gdata/w28+gdata/rt52+gdata/w40+gdata/w97+scratch/w40
#PBS -l wd


ulimit -s unlimited 
module load nvidia-hpc-sdk/22.11
module load netcdf/4.9.2


#nvfortran -stdpar=gpu -Mpreprocess -DERA5 -Minfo=all -Mneginfo -g BTrIMS.f90  -lnetcdff -lnetcdf -o main
nvfortran -acc -Minfo=all -gpu=cc70 -gpu=deepcopy -Mvect=simd:512  BTrIMS.f90  -lnetcdff -lnetcdf -o main
./main 25 02 2022 26 02 2022 /scratch/w40/ym7079/BTrIMS_openacc/ > terminal_output.txt


###ifort -O3 -c -DERA5 -fpp /home/603/cxh603/CLEX/QIBT_ERA5/Model/B-TrIMS/QIBT_exp10.f90 -lnetcdff -lnetcdf -qopenmp -traceback
###ifort -O3 -lnetcdff -lnetcdf -qopenmp /home/603/cxh603/CLEX/QIBT_ERA5/Model/B-TrIMS/QIBT_exp10.o -o /home/603/cxh603/CLEX/QIBT_ERA5/Model/B-TrIMS/main
###/home/603/cxh603/CLEX/QIBT_ERA5/Model/B-TrIMS/main 25 02 2022 26 02 2022 /g/data/w97/cxh603/QIBT_ERA5/outputs/era5_testing/ > /home/603/cxh603/CLEX/QIBT_ERA5/Model/terminal_output.txt

###ifort -DERA5 -fpp /home/603/cxh603/CLEX/QIBT_ERA5/Model/B-TrIMS/QIBT_exp10.f90 -lnetcdff -lnetcdf -qopenmp
###/home/603/cxh603/CLEX/QIBT_ERA5/Model/B-TrIMS/a.out 25 02 2022 26 02 2022 /g/data/w97/cxh603/QIBT_ERA5/outputs/era5_testing/ > /home/603/cxh603/CLEX/QIBT_ERA5/Model/terminal_output.txt
