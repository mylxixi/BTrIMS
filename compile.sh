#!/bin/bash
module load intel-fc/2019.3.199
module load netcdf
module load intel-mkl
module load openmp

# nothing (no mkl, no openmp, no parallel)
ifort QIBT_exp10_noopenmp_nomkl.f90     -o nothing  -lnetcdff -lnetcdf

# == One thing at a time added ==
# mkl
ifort QIBT_exp10_noopenmp_mkl.f90       -o mkl      -lnetcdff -lnetcdf -mkl
# openmp
ifort QIBT_exp10_openmp_nomkl.f90       -o openmp   -lnetcdff -lnetcdf -qopenmp
# parallel
ifort QIBT_exp10_noopenmp_nomkl.f90     -o parallel -lnetcdff -lnetcdf -parallel
