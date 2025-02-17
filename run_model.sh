#!/bin/bash
#PBS -N test0_GPU
#PBS -P n81
#PBS -q normal   
#PBS -l walltime=01:00:00
#PBS -l ncpus=16
#PBS -l mem=100GB
#PBS -l jobfs=200MB
#PBS -l storage=gdata/hh5+gdata/w28+gdata/rt52+gdata/w40+gdata/w97+scratch/w40
#PBS -l wd


ulimit -s unlimited 
module load nvidia-hpc-sdk/24.9 
module load netcdf/4.9.2
module load cuda/12.6.2 
export NVHPC_CUDA_HOME=$CUDA_HOME
export PGI_ACC_TIME=1

# q can be gpuvolta or dgxa100, and -gpu=cc70 or -gpu=cc80,ncpus should be 12 or 16
#nvfortran -acc=gpu -mp -Minfo=accel -gpu=cc80 -Minline -gpu=deepcopy BTrIMS_GPU.f90 -lnetcdff -lnetcdf -o main_GPU
nvfortran -acc=multicore -traceback -Mbounds -mp -Minfo=accel -gpu=cc80 -Minline -gpu=deepcopy BTrIMS_GPU.f90 -lnetcdff -lnetcdf -o main_GPU
#nvfortran -acc=gpu -mp -Minfo=accel -gpu=cc80 -Minline -gpu=deepcopy BTrIMS_GPU.f90 -lnetcdff -lnetcdf -o main_GPU

#nvfortran -o main BTrIMS.f90 -lnetcdff -lnetcdf -acc=gpu -mp -gpu=deepcopy 
#nvfortran -acc=gpu -mp -Minfo=accel -gpu=cc70 -Minline -gpu=deepcopy  add_matrix_kernels.f90 -o main
#./main_GPU 25 02 2022 26 02 2022 /scratch/w40/ym7079/GPU_test1206/ > terminal_output.txt
./main_GPU 25 02 2022 26 02 2022 /scratch/w40/ym7079/GPU_test_new/GPU/ > terminal_output_GPU.txt

#nvfortran -stdpar=gpu -Mpreprocess -DERA5 -Minfo=all -Mneginfo -g BTrIMS.f90  -lnetcdff -lnetcdf -o main
#nvfortran -acc -Minfo=all -gpu=cc70 -Minline -gpu=deepcopy -Mvect=simd:512  BTrIMS.f90  -lnetcdff -lnetcdf -o main
#nvfortran -acc -Minfo=accel -gpu=cc70 -Minline -gpu=deepcopy  BTrIMS.f90  -lnetcdff -lnetcdf -o main
#nvfortran -acc=gpu -mp -Minfo=accel -gpu=cc70 -Minline -gpu=deepcopy  BTrIMS_kernels.f90 -o main
#./main 25 02 2022 26 02 2022 /scratch/w40/ym7079/BTrIMS_openacc/BTrIMS > terminal_output.txt
#./main > terminal_output.txt
#./main 


###ifort -O3 -c -DERA5 -fpp /home/603/cxh603/CLEX/QIBT_ERA5/Model/B-TrIMS/QIBT_exp10.f90 -lnetcdff -lnetcdf -qopenmp -traceback
###ifort -O3 -lnetcdff -lnetcdf -qopenmp /home/603/cxh603/CLEX/QIBT_ERA5/Model/B-TrIMS/QIBT_exp10.o -o /home/603/cxh603/CLEX/QIBT_ERA5/Model/B-TrIMS/main
###/home/603/cxh603/CLEX/QIBT_ERA5/Model/B-TrIMS/main 25 02 2022 26 02 2022 /g/data/w97/cxh603/QIBT_ERA5/outputs/era5_testing/ > /home/603/cxh603/CLEX/QIBT_ERA5/Model/terminal_output.txt

###ifort -DERA5 -fpp /home/603/cxh603/CLEX/QIBT_ERA5/Model/B-TrIMS/QIBT_exp10.f90 -lnetcdff -lnetcdf -qopenmp
###/home/603/cxh603/CLEX/QIBT_ERA5/Model/B-TrIMS/a.out 25 02 2022 26 02 2022 /g/data/w97/cxh603/QIBT_ERA5/outputs/era5_testing/ > /home/603/cxh603/CLEX/QIBT_ERA5/Model/terminal_output.txt
