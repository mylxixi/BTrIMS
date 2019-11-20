#!/bin/bash
# Submit this script using this command:
#   qsub -v ver=nothing submitjob.sh
# ...where you replace 'nothing' with the name of the binary ('openmp', 
# 'parallel', or anything else that it is named)
# Then 'ver' (short for version) becomes an environment 
# variable, available to this script as '$ver' below.

#PBS -P w28
#PBS -q normalsl
# -l other=hyperthread
#PBS -l ncpus=8
#PBS -l mem=16GB
#PBS -l walltime=2:00:00
#PBS -l wd
#PBS -l jobfs=2GB
#PBS -M svetlana.tkachenko@unsw.edu.au
#PBS -m abe

ulimit -s unlimited
export OMP_NUM_THREADS=8 # <-- Important
export DIROUT=`pwd`/OutputV8.$PBS_JOBID #  <-- Dir where to put the results

mkdir $DIROUT
module load intel-fc/2019.3.199
module load netcdf
module load intel-mkl

##cd $PBS_JOBFS

cp QIBT_exp04_*.f90 $DIROUT
cp $ver.sh $DIROUT
cp Comp*.sh $DIROUT
./$ver 1 2 1979 2 2 1979 $PBS_JOBFS/ # drier day
#./$ver 5 2 2011 6 2 2011 $PBS_JOBFS/ # rainy day

gprof -l ./$ver > $ver.prof.1.out
cp $PBS_JOBFS/* $DIROUT
mv $ver.prof.1.out $DIROUT

mv gmon.out $DIROUT
mv $ver.prof.1.out $DIROUT
