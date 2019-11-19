## Notes for NCI (Gadi)
**November 2019**
### Quickstart
```
# Instructions Gadi

#
# Load module for netcdf
#
module load netcdf/4.7.1

#
# Clone the git repository
#
git clone https://github.com/chiaraholgate/QIBT_shared.git
cd QIBT_shared

#
# Compile with OpenMP
#
gfortran -ffree-line-length-512 -fopenmp -O3 -c QIBT_exp10.f90

#
# Link the executable
#
gfortran -fopenmp -O3 -L/apps/netcdf/4.7.1/lib -lnetcdff QIBT_exp10.o -o main

#
# Run QIBT from 11 Jan 1980 to 13 Jan 1980, storing the results in subdirectory ./outputs
#
chmod u+x main
mkdir outputs

#
# PBS jobscript for Gadi
#
cat - <<EOF >191119-qibt.sh
#!/bin/bash
#PBS -q normal
#PBS -l walltime=10:00:00
#PBS -l ncpus=48
#PBS -l mem=16GB
#PBS -l storage=gdata/hh5 
cd $PBS_O_WORKDIR
./main 11 01 1980 13 01 1980 ./outputs

EOF

#
# Submit the job to Gadi normal queue
#
qsub 191119-qibt.sh
```
### Data sources
```
$ ls -lh /g/data/hh5/tmp/w28/jpe561/back_traj/
total 4.7M
drwxrwsr-x+ 2 jpe561 hh5 4.0K Oct  5  2018 watershed
drwxrwsr-x+ 2 jpe561 hh5 3.6M Mar 15  2019 wrfhrly
drwxrwsr-x+ 2 jpe561 hh5 1.1M Dec 21  2018 wrfout
```

** Required: a brief introduction to what is the format and contents of these files
