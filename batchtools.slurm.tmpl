#!/bin/bash

## Job Resource Interface Definition
##
## ntasks [integer(1)]:       Number of required tasks,
##                            Set larger than 1 if you want to further parallelize
##                            with MPI within your job.
## ncpus [integer(1)]:        Number of required cpus per task,
##                            Set larger than 1 if you want to further parallelize
##                            with multicore/parallel within each task.
## walltime [integer(1)]:     Walltime for this job, in minutes.
##                            Must be at least 1 minute.
##
## Default resources can be set in your .batchtools.conf.R by defining the variable
## 'default.resources' as a named list.

<%
# relative paths are not handled well by Slurm
log.file = fs::path_expand(log.file)
-%>


#SBATCH --job-name=<%= job.name %>
#SBATCH --output=<%= log.file %>
#SBATCH --error=<%= log.file %>
#SBATCH --time=<%= resources$walltime %>
<%= if (!is.null(resources$partition)) sprintf(paste0("#SBATCH --partition='", resources$partition, "'")) %>
<%= if (!is.null(resources$ntasks)) sprintf(paste0("#SBATCH --ntasks='", resources$ntasks, "'")) %>
<%= if (!is.null(resources$cpus_per_task)) sprintf(paste0("#SBATCH --cpus-per-task='", resources$cpus_per_task, "'")) %>
<%= if (!is.null(resources$nodes)) sprintf(paste0("#SBATCH --nodes='", resources$nodes, "'")) %>

## Initialize work environment like
## source /etc/profile
## module add ...

## Run R:
## we merge R output with stdout from SLURM, which gets then logged via --output option
Rscript -e 'batchtools::doJobCollection("<%= uri %>")'
