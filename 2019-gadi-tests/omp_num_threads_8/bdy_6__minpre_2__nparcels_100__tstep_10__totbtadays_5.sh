#!/bin/bash
#PBS -q normal
#PBS -l walltime=10:00:00
#PBS -l ncpus=8
#PBS -l mem=64GB
#PBS -l storage=gdata/hh5
#
cd $PBS_O_WORKDIR
ulimit -s unlimited

#
# Compile the program
#
cp ../../QIBT_exp10.f90 .
#sed -i '1647,1648d' QIBT_exp10.f90
#sed -i 's/^!  dist =/dist =/' QIBT_exp10.f90
#sed -i 's/INTEGER, PARAMETER :: numthreads.*/INTEGER, PARAMETER :: numthreads = 8/g' QIBT_exp10.f90
module load intel-compiler/2019.3.199
module load netcdf/4.7.1
ifort -O3 -fopenmp -c QIBT_exp10.f90
ifort -O3 -fopenmp -L/apps/netcdf/4.7.1/lib -lnetcdff QIBT_exp10.o -o main
chmod u+x main
mkdir -p $PBS_O_WORKDIR/outputs/$PBS_JOBID

#
# Run the program and output timing
#
time ./main 11 01 1981 15 01 1981 ./outputs/$PBS_JOBID/
