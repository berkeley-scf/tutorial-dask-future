---
layout: default
title: Parallel processing using the Dask packge in Python
---

<script
  src="https://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML"
  type="text/javascript">
</script>

# Parallel processing using the Dask packge in Python

## 1. Overview of Dask

The Dask package provides a variety of tools for managing parallel computations.

In particular, some of the key ideas/features of Dask are:

  - Separate what to parallelize from how and where the parallelization is actually carried out.
  - Different users can run the same code on different computational resources (without touching the actual code that does the computation).
  - Dask provides distributed data structures that can be treated as a single data structures when runnig operations on them (like Spark and pbdR). 

The idea of a 'future' or 'delayed' operation is to tag operations such that they run lazily. Multiple operations can then be pipelined together and Dask can figure out how best to compute them in parallel on the computational resources available to a given user (which may be different than the resources available to a different user). 

Let's import dask to get started.

```python
import dask
```


## 2. Overview of parallel schedulers

One specifies a "scheduler" to control how parallelization is done, including what machine(s) to use and how many cores on each machine to use.

For example,

```python
import dask.multiprocessing
# spread work across multiple cores, one worker per core
dask.config.set(scheduler='processes', num_workers = 4)  
```


This table gives an overview of the different scheduler. 


|Type|Description|Multi-node|Copies of objects made?|
|----|-----------|----------|-----------------------|
|synchronous|not in parallel|no|no|
|threaded|threads within current Python session|no|no|
|processes|background Python sessions|no|yes|
|distributed|Python sessions across multiple nodes|yes or no|yes|

Note that because of Python's Global Interpreter Lock (GIL), many computations done in pure Python code won't be parallelized using the 'threaded' scheduler; however computations on numeric data in numpy arrays, Pandas dataframes and other C/C++/Cython-based code will parallelize.

For the next section (Section 3), we'll just assume use of the 'processes' schduler and will provide more details on the other schedulers in the following section (Section 4).


## 3. Implementing operations in parallel "by hand"

Dask has a large variety of patterns for how you might parallelize a computation.

We'll simply parallelize computation of the mean of a large number of random numbers across multiple replicates as can be seen in `calc_mean.py`.

```python
from calc_mean import *
```

(Note the code in calc_mean.py is not safe in terms of parallel random number generation - see Section 8 later in this document.)


### 3.1. Using a 'future' via 'delayed'

The basic pattern for setting up a parallel loop is:

#### 3.1.1 For loop

```python
import dask.multiprocessing
dask.config.set(scheduler='processes', num_workers = 4)  

futures = []
n = 10000000
p = 10
for i in range(p):
    futures.append(dask.delayed(calc_mean)(i, n))  # add lazy task

futures
results = dask.compute(futures)  # compute all in parallel
```

#### 3.1.2 List comprehension

```python
import dask.multiprocessing
dask.config.set(scheduler='processes', num_workers = 4)  

n = 10000000
p = 10
futures = [dask.delayed(calc_mean)(i, n) for i in range(p)]
futures
results = dask.compute(futures)
```

You could set the scheduler in the `compute` call:

```python
results = dask.compute(futures, scheduler = 'processes')
```

However, it is best practice to separate what is parallelized from where the parallelization is done, specifying the scheduler at the start of your code.

### 3.2. Parallel maps

We can do parallel map operations (i.e., a *map* in the map-reduce or functional programming sense, akin to `lapply` in R).

For this we need to use the *distributed* scheduler, which we'll discuss more later.
Note that the distributed scheduler can work on one node or on multiple nodes.

```python
# Ignore this setup for now; we'll see it again later
from dask.distributed import Client, LocalCluster
cluster = LocalCluster(n_workers = 4)
c = Client(cluster)

# Set up and execute the parallel map
# We need the input for each function call to be a single object,
# so use the vectorized version of calc_mean
inputs = [(i, n) for i in range(p)]
# execute the function across the array of input values
future = c.map(calc_mean_vargs, inputs)
results = c.gather(future)
results
```

The map operation appears to cache results. If you rerun the above with the same inputs, you get the same result back essentially instantaneously (even if one removes the setting of the seed from `calc_mean_vargs`). HOWEVER, that means that if there is randomness in the results of your function for a given input, Dask will just continue to return the original output.


### 3.3. Delayed evaluation and task graphs

You can use `delayed` in more complicated situations than the simple iterations shown above.

```python
def inc(x):
    return x + 1

def add(x, y):
    return x + y

x = dask.delayed(inc)(1)
y = dask.delayed(inc)(2)
z = dask.delayed(add)(x, y)
z.compute()

z.visualize(filename = 'task_graph.svg')
```

`visualize()` uses the `graphviz` package to illustrate the task graph (similar to a directed acyclic graph in a statistical model and to how Tensorflow organizes its computations).

One can also tell Dask to always delay evaluation of a given function:

```python
@dask.delayed
def inc(x):
    return x + 1

@dask.delayed
def add(x, y):
    return x + y

x = inc(1)
y = inc(2)
z = add(x, y)
z.compute()
```


### 3.4. The Futures interface

You can also control evaluation of tasks using the [Futures interface for managing tasks](https://docs.dask.org/en/latest/futures.html). Unlike use of `delayed`, the evaluation occurs immediately instead of via lazy evaluation.

## 4. Dask distributed datastructures and "automatic" parallel operations on them

Dask provides the ability to work on data structures that are split (sharded/chunked) across workers. There are two big advantages of this:

  - You can do calculations in parallel because each worker will work on a piece of the data.
  - When the data is split across machines, you can use the memory of multiple machines to handle much larger datasets than would be possible in memory on one machine. That said, Dask processes the data in chunks, so one often doesn't need a lot of memory, even just on one machine.

Because computations are done in external compiled code (e.g., via numpy) it's effective to use the threaded scheduler when operating on one node to avoid having to copy and move the data. 


### 4.1. Dataframes (pandas)

Dask dataframes are Pandas-like dataframes where each dataframe is split into groups of rows, stored as  smaller Pandas dataframes.

One can do a lot of the kinds of computations that you would do on a Pandas dataframe on a Dask dataframe, but many operations are not possible, as discussed in the [Dask dataframe API](http://docs.dask.org/en/latest/dataframe-api.html).

By default dataframes are handled by the threads scheduler.

Here's an example of reading from a dataset of flight delays (about 11 GB data).
You can get [the flight delay data](https://www.stat.berkeley.edu/share/paciorek/1987-2008.csvs.tgz).


```python
import dask
dask.config.set(scheduler='threads', num_workers = 4)  
import dask.dataframe as ddf
air = ddf.read_csv('/scratch/users/paciorek/243/AirlineData/csvs/*.csv.bz2',
      compression = 'bz2',
      encoding = 'latin1',   # (unexpected) latin1 value(s) 2001 file TailNum field
      dtype = {'Distance': 'float64', 'CRSElapsedTime': 'float64',
      'TailNum': 'object', 'CancellationCode': 'object'})
# specify dtypes so Pandas doesn't complain about column type heterogeneity
      
air.DepDelay.max().compute()   # this takes a while (6 minutes with 8 cores on an SCF server)
sub = air[(air.UniqueCarrier == 'UA') & (air.Origin == 'SFO')]
byDest = sub.groupby('Dest').DepDelay.mean()
byDest.compute()               # this takes a while too
```

You should see this:

```python
Dest
ACV    26.200000
BFL     1.000000
BOI    12.855069
BOS     9.316795
CLE     4.000000
...
```

### 4.2. Bags

Bags are like lists but there is no particular ordering, so it doesn't make sense to ask for the i'th element.

You can think of operations on Dask bags as being like parallel map operations on lists in Python or R.

By default bags are handled via the multiprocessing scheduler.

Let's see some basic operations on a large dataset of Wikipedia log files.
You can get a [subset of the Wikipedia data](https://www.stat.berkeley.edu/share/paciorek/wikistats_example.tar.gz).


```python
import dask.multiprocessing
dask.config.set(scheduler='processes', num_workers = 4)  # multiprocessing is the default
import dask.bag as db
wiki = db.read_text('/scratch/users/paciorek/wikistats/dated_2017/part-0000*gz')
import time
t0 = time.time()
wiki.count().compute()
time.time() - t0   # 136 sec.

import re
def find(line, regex = "Obama", language = "en"):
    vals = line.split(' ')
    if len(vals) < 6:
        return(False)
    tmp = re.search(regex, vals[3])
    if tmp is None or (language != None and vals[2] != language):
        return(False)
    else:
        return(True)
    

obama = wiki.filter(find).compute()
obama[0:5]
```

That should look like this:

```python
['20081113 100000 en Image:Flickr_Obama_Springfield_01.jpg 25 306083\n', '20081004 130000 en Special:FilePath/Opinion_polling_for_the_United_States_presidential_election,_2008,_Barack_Obama_Fred_Thompson.png 1 1224\n', '20081004 130000 en Special:FilePath/Opinion_polling_for_the_United_States_presidential_election,_2008,_Barack_Obama_Rudy_Giuliani.png 1 1212\n', '20081217 160000 en File:Michelle,_Malia_and_Sasha_Obama_at_DNC.jpg 7 97330\n', '20081217 160000 en File:Michelle,_Oprah_Winfrey_and_Barack_Obama.jpg 6 120260\n']
```

Note that it is quite inefficient to do the `find()` (and therefore necessarily reading
the data in) and then compute on top of that intermediate result in
two separate calls to `compute()`. More in Section 6.

Also you would not want to do `data = wiki.compute()` as that would pull the entire dataset into your main Python session as a single (very large) list.

### 4.3. Arrays (numpy)

Dask arrays are numpy-like arrays where each array is split up by both rows and columns into smaller numpy arrays.

One can do a lot of the kinds of computations that you would do on a numpy array on a Dask array, but many operations are not possible, as discussed in the [Dask array API](http://docs.dask.org/en/latest/array-api.html).

By default arrays are handled via the threads scheduler.

#### 4.3.1 Arrays on a single node/machine

Let's first see operations on a single node, using a single 13 GB 2-d array. Note that Dask uses lazy evaluation, so creation of the array doesn't happen until an operation requiring output is done.

Here we specify that the chunks (the sub-arrays) are 10000 by 10000.

```python
import dask
dask.config.set(scheduler = 'threads', num_workers = 4) 
import dask.array as da
x = da.random.normal(0, 1, size=(40000,40000), chunks=(10000, 10000))
# square 10k x 10k chunks
mycalc = da.mean(x, axis = 1)  # by row
import time
t0 = time.time()
rs = mycalc.compute()
time.time() - t0  # 41 sec.
```

For a row-based operation, we would presumably only want to chunk things up by row,
but this doesn't seem to actually make a difference, presumably because the
mean calculation can be done in pieces and only a small number of summary statistics
moved between workers.

```python
import dask
dask.config.set(scheduler='threads', num_workers = 4)  
import dask.array as da
# Set so that each chunk has 2500 rows and all columns
# x = da.from_array(x, chunks=(2500, 40000))  # how to adjust chunk size of existing array
x = da.random.normal(0, 1, size=(40000,40000), chunks=(2500, 40000))  
mycalc = da.mean(x, axis = 1)  # row means
import time
t0 = time.time()
rs = mycalc.compute()
time.time() - t0   # 42 sec.
```

Of course, given the lazy evaluation, this timing comparison is not just timing the
actual row mean calculations.

But this doesn't really clarify the story...

```python
import dask
dask.config.set(scheduler='threads', num_workers = 4)  
import dask.array as da
import numpy as np
import time
t0 = time.time()
rng = np.random.default_rng()
x = rng.normal(0, 1, size=(40000,40000))
time.time() - t0   # 110 sec.
# for some reason the from_array and da.mean calculations are not done lazily here
t0 = time.time()
dx = da.from_array(x, chunks=(2500, 40000))
time.time() - t0   # 27 sec.
t0 = time.time()
mycalc = da.mean(x, axis = 1)  # what is this doing given .compute() also takes time?
time.time() - t0   # 28 sec.
t0 = time.time()
rs = mycalc.compute()
time.time() - t0   # 21 sec.
```

Dask will avoid storing all the chunks in memory. (It appears to just generate them on the fly.)
Here we have an 80 GB array but we never use more than a few GB of memory (based on `top` or `free -h`).


```python
import dask
dask.config.set(scheduler='threads', num_workers = 4)  
import dask.array as da
x = da.random.normal(0, 1, size=(100000,100000), chunks=(10000, 10000))
mycalc = da.mean(x, axis = 1)  # row means
import time
t0 = time.time()
rs = mycalc.compute()
time.time() - t0   # 205 sec.
rs[0:5]
```


#### 4.3.2 Arrays split across multiple nodes/machines

This should be straightforward based on using Dask distributed. However, one would want to
be careful about creating arrays by distributing the data from a single Python process
as that would involve copying between machines.

## 5. Using different schedulers

### 5.1. Using threads (no copying)

```python
dask.config.set(scheduler='threads', num_workers = 4)  
n = 100000000
p = 4

## Using current numpy random number generator
futures = [dask.delayed(calc_mean)(i, n) for i in range(p)]

t0 = time.time()
results = dask.compute(futures)
time.time() - t0    # 3.4 sec.

def calc_mean_old(i, n):
    import numpy as np
    data = np.random.normal(size = n)
    return([np.mean(data), np.std(data)])

## Using deprecated numpy random number generator
futures = [dask.delayed(calc_mean_old)(i, n) for i in range(p)]

t0 = time.time()
results = dask.compute(futures)
time.time() - t0    # 21 sec.
```

The computation here effectively parallelizes. However, if instead of using the `default_rng` Generator consturctor, one uses the old numpy syntax of `np.random.normal(size = n)`, one would see it takes four times as long, so is not parallelizing.

The problem is presumably occurring because of Python's Global Interpreter Lock (GIL): any computations done in pure Python code can not be parallelized using the 'threaded' scheduler. However, computations on numeric data in numpy arrays, pandas dataframes and other C/C++/Cython-based code would parallelize.

Exactly why one form of numpy code encounters the GIL and the other is not clear to me.

### 5.2. Multi-process parallelization via Dask Multiprocessing

We can effectively parallelize regardless of the GIL by using multiple Python processes. 

```python
import dask.multiprocessing
dask.config.set(scheduler='processes', num_workers = 4)  
n = 100000000
p = 4
futures = [dask.delayed(calc_mean)(i, n) for i in range(p)]


t0 = time.time()
results = dask.compute(futures)
time.time() - t0  # 4.0 sec.
```

IMPORTANT: The above code will work when run in an interactive Python
session. However, if you want to run it within a Python script (i.e., in a background/batch job),
you'll need to configure the scheduler and run the code within an `if __name__ == '__main__'` block:

```python
import dask.multiprocessing

if __name__ == '__main__':
    dask.config.set(scheduler='processes', num_workers = 4)
    n = 100000000
    p = 4
    futures = [dask.delayed(calc_mean)(i, n) for i in range(p)]
    
    t0 = time.time()
    results = dask.compute(futures)
    time.time() - t0  # 4.0 sec.
```

### 5.3. Multi-process parallelization via Dask Distributed (local)

According to the Dask documentation, using `Distributed` on a local machine
has advantages over multiprocessing, including the diagnostic dashboard
(see Section 7) and better handling of when copies need to be made.  As we saw previously,
using Distributed also allows us to use the handy `map()` operation.

```python
from dask.distributed import Client, LocalCluster
cluster = LocalCluster(n_workers = 4)
c = Client(cluster)

futures = [dask.delayed(calc_mean)(i, n) for i in range(p)]
t0 = time.time()
results = dask.compute(futures)
time.time() - t0   # 3.4 sec.
```

IMPORTANT: The above code will work when run in an interactive Python
session. However, if you want to run it within a Python script (i.e., in a background/batch job),
you'll need to set up the cluster and run the code within an `if __name__ == '__main__'` block:

```python
from dask.distributed import Client, LocalCluster

if __name__ == '__main__':
	from calc_mean import *

	cluster = LocalCluster(n_workers = 4)
	c = Client(cluster)

	futures = [dask.delayed(calc_mean)(i, n) for i in range(p)]
	t0 = time.time()
	results = dask.compute(futures)
	time.time() - t0   # 7 sec.
```

### 5.4. Distributed processing across multiple machines via an ad hoc cluster

We need to set up a scheduler on one machine (possibly the machine we are on)
and workers on whatever machines we want to do the computation on.


One option is to use the `dask-ssh` command to start up the scheduler and workers.
(Note that for this to work we need to have password-less SSH working to connect
to the various machines.)

```bash
export SCHED=$(hostname)
dask-ssh --scheduler ${SCHED} radagast.berkeley.edu radagast.berkeley.edu arwen.berkeley.edu arwen.berkeley.edu &
## or:
## echo -e "radagast.berkeley.edu radagast.berkeley.edu arwen.berkeley.edu arwen.berkeley.edu" > .hosts
## dask-ssh --scheduler ${SCHED} --hostfile .hosts
```

Then in Python, connect to the cluster via the scheduler.

```python
from dask.distributed import Client
import os
c = Client(address = os.getenv('SCHED') + ':8786')
c.upload_file('calc_mean.py')  # make module accessible to workers
n = 100000000
p = 4

futures = [dask.delayed(calc_mean)(i, n) for i in range(p)]
results = dask.compute(futures)
# The following seems to work to kill the worker processes, but errors are reported...
c.shutdown()
```

Alternatively, you can start the workers from within Python:

```python
from dask.distributed import Client, SSHCluster
# first host is the scheduler
cluster = SSHCluster(
    ["gandalf.berkeley.edu", "radagast.berkeley.edu", "radagast.berkeley.edu", "arwen.berkeley.edu", "arwen.berkeley.edu"]
)
c = Client(cluster)

# now do your computations....

c.shutdown()
```

### 5.5. Distributed processing using multiple machines within a SLURM scheduler job

To run within a SLURM job we can use `dask-ssh` or a combination of `dask-scheduler`
and `dask-worker`.. 

Provided that we have used --ntasks or --nodes and --ntasks-per-node to set the
number of CPUs desired (and not --cpus-per-task), we can use `srun` to
enumerate where the workers should run.

First we'll start the scheduler and the workers.

```bash
export SCHED=$(hostname):8786
dask-scheduler&
sleep 50   
# On Savio, I've gotten issues with the local directory being in my home directory, so use /tmp
srun dask-worker tcp://${SCHED} --local-directory /tmp &   # might need machinename.berkeley.edu:8786
sleep 100   # might need even more time to make sure workers start up fully
```

Then in Python, connect to the cluster via the scheduler.

```python
import os, time, dask
from dask.distributed import Client
c = Client(address = os.getenv('SCHED'))
c.upload_file('calc_mean.py')  # make module accessible to workers
n = 100000000
p = 24

futures = [dask.delayed(calc_mean)(i, n) for i in range(p)]
t0 = time.time()
results = dask.compute(futures)
time.time() - t0
```

Let's process the 500 GB of Wikipedia log data on Savio. (Note that
when I tried this on the SCF I had some errors that might be related
to the SCF not being set up for fast parallel I/O.)

```python
import os
from dask.distributed import Client
c = Client(address = os.getenv('SCHED'))
import dask.bag as db
wiki = db.read_text('/global/scratch/paciorek/wikistats_full/dated/part*')
import time
t0 = time.time()
wiki.count().compute()
time.time() - t0   # 153 sec. using 96 cores on Savio

import re
def find(line, regex = "Obama", language = "en"):
    vals = line.split(' ')
    if len(vals) < 6:
        return(False)
    tmp = re.search(regex, vals[3])
    if tmp is None or (language != None and vals[2] != language):
        return(False)
    else:
        return(True)
    

wiki.filter(find).count().compute()
# obama = wiki.filter(find).compute()
# obama[0:5]
```


Alternatively, we can use dask-ssh, but I've had problems sometimes with
using SSH to connect between nodes of a SLURM job, so the approach above
is likely to be more robust as it relies on SLURM itself to connect
between nodes.

```bash
export SCHED=$(hostname)
srun hostname > .hosts
dask-ssh --scheduler ${SCHED} --hostfile .hosts
```

## 6. Effective parallelization and common issues

### 6.1. Nested parallelization and pipelines

We can set up nested parallelization (or an arbitrary set of computations) and just have Dask's delayed functionality figure out how to do the parallelization, provided there is a single call to the compute() method.

```python
import time, dask.multiprocessing
dask.config.set(scheduler = 'processes', num_workers = 4)  

@dask.delayed
def calc_mean_vargs2(inputs, nobs):
    import numpy as np
    rng = np.random.default_rng()
    data = rng.normal(inputs[0], inputs[1], nobs)
    return([np.mean(data), np.std(data)])

params = zip([0,0,1,1],[1,2,1,2])
m = 20
n = 10000000
out = list()
for param in params:
    out_single_param = list()
    for i in range(m):
        out_single_param.append(calc_mean_vargs2(param, n))
    out.append(out_single_param)

t0 = time.time()
output = dask.compute(out)  # 7 sec. on 4 cores
time.time() - t0
```


### 6.2. Load-balancing and static vs. dynamic task allocation

When using `delayed`, Dask starts up each delayed evaluation separately (i.e., dynamic allocation).
This is good for load-balancing, but each task induces
some overhead (a few hundred microseconds).  

Even with a distributed `map()` it doesn't appear possible to ask that the tasks
be broken up into batches.

So if you have many quick tasks, you probably
want to break them up into batches manually, to reduce the impact of the overhead.

### 6.3. Avoid repeated calculations by embedding tasks within one call to compute

As far as I can tell, Dask avoids keeping all the pieces of a distributed object or
computation in memory.  However, in many cases this can mean repeating
computations or re-reading data if you need to do multiple operations on a dataset.

For example, if you are create a Dask distributed dataset from data on disk, I think this means that
every distinct set of computations (each computational graph) will involve reading
the data from disk again.

One implication is that if you can include all computations
on a large dataset within a single computational graph (i.e., a call to `compute`)
that may be much more efficient than making separate calls.

Here's an example with Dask dataframe on the airline delay data, where we make sure to
do all our computations as part of one graph:

```python
import dask
dask.config.set(scheduler='processes', num_workers = 6)  
import dask.dataframe as ddf
air = ddf.read_csv('/scratch/users/paciorek/243/AirlineData/csvs/*.csv.bz2',
      compression = 'bz2',
      encoding = 'latin1',   # (unexpected) latin1 value(s) 2001 file TailNum field
      dtype = {'Distance': 'float64', 'CRSElapsedTime': 'float64',
      'TailNum': 'object', 'CancellationCode': 'object'})
# specify dtypes so Pandas doesn't complain about column type heterogeneity

import time
t0 = time.time()
air.DepDelay.min().compute()   # about 200 seconds.
t1 = time.time()-t0
t0 = time.time()
air.DepDelay.max().compute()   # about 200 seconds.
t2 = time.time()-t0
t0 = time.time()
(mn, mx) = dask.compute(air.DepDelay.max(), air.DepDelay.min())  # about 200 seconds
t3 = time.time()-t0
print(t1)
print(t2)
print(t3)
```

However, I also tried the above where I added `air.count()` to the `dask.compute` call and something went wrong - the computation time increased a lot and there was a lot of memory use. I'm not sure what is going on.

Note that when reading from disk, disk caching by the operating system (saving files that are used repeatedly in memory) can also greatly speed up I/O. (Note this can very easily confuse you in terms of timing your code..., e.g., simply copying the data to your machine can put them in the cache, so subsequent reading into Python can take advantage of that.)

### 6.4. Copies are usually made 

Except for the 'threads' scheduler, copies will be made of all objects passed to the workers.

In general you want to delay the input objects. There are a couple reasons why:

  - Dask hashes the object to create a name, and if you pass the same object as an argument multiple times, it will repeat that hashing.
  - When using the distributed scheduler *only*, delaying the inputs will prevent sending the data separately for every task (rather it should send the data separately for each worker).

In this example, most of the "computational" time is actually spent transferring the data
rather than computing the mean. Whether there is a copy per task or a copy per process seems to depend on exactly what the parallelized code is doing (perhaps based on whether there is random number generation in the code).


```python
dask.config.set(scheduler = 'processes', num_workers = 4)  

import numpy as np
rng = np.random.default_rng()
x = rng.normal(size = 40000000)
x = dask.delayed(x)   # here we delay the data

def calc(x, i):
    return(np.mean(x))

out = [dask.delayed(calc)(x, i) for i in range(20)]
t0 = time.time()
output = dask.compute(out)
time.time() - t0   # about 20 sec. = 80 total sec. across 4 workers, so ~4 sec. per task


## Actual computation is much faster than 4 sec. per task
t0 = time.time()
calc(x, 1)
time.time() - t0
```

Here's an example of using  the Distributed (local) scheduler.
Copies have to be made, but if we delay the data object, there is only one copy per worker.
Note that with the Dask distributed scheduler, it is complicated to assess what is going on, because the scheduler seems to try to optimize assignment of tasks to workers in a way that may cause an imbalance in the number of tasks assigned to each worker. In this example, all the tasks are assigned to a single worker.


```python
from dask.distributed import Client, LocalCluster
cluster = LocalCluster(n_workers = 4)
c = Client(cluster)

import numpy as np
rng = np.random.default_rng()
x = rng.normal(size = 40000000)
x = dask.delayed(x)  # here we delay the data

def calc(x, i):
    return(np.mean(x))

out = [dask.delayed(calc)(x, i) for i in range(20)]
t0 = time.time()
output = dask.compute(out)
time.time() - t0    # 3.6 sec. 
```

That took a few seconds if we delay the data but takes ~20 seconds if we don't.

Also, Dask gives a warning about sending the data to the workers in advance. I’m not sure of the distinction between what it is recommending and use of `dask.delayed(x)`. When I tried to use `scatter()` in various ways, I wasn't able to silence the warning.

Note that in either case, we incur the memory usage of the original 'x' plus copies of 'x' on the workers.

### 6.5. Parallel I/O

For this to make the most sense we want to be on a system where we can read multiple files
without having the bottleneck of accessing a single spinning hard disk. For example the
Savio filesystem is set up for fast parallel I/O.

On systems with a single spinning hard disk or a single SSD, you might experiment
to see how effectively things scale as you read (or write) multiple files in parallel.

Here we'll demo on Savio to take advantage of the fast, parallel I/O.

```python
import dask.multiprocessing
dask.config.set(scheduler = 'processes', num_workers = 24) 


## define a function that reads data but doesn't need to return entire
## dataset back to master process to avoid copying cost
def readfun(yr):
    import pandas as pd
    out = pd.read_csv('/global/scratch/paciorek/airline/' + str(yr) + '.csv.bz2',
                      header = 0, encoding = 'latin1',
                      dtype = {'Distance': 'float64', 'CRSElapsedTime': 'float64',
                      'TailNum': 'object', 'CancellationCode': 'object'})
                      # specify dtypes so Pandas doesn't complain about column type heterogeneity
    return(len(out))   # just return length

results = []
for yr in range(1988, 2009):  
    results.append(dask.delayed(readfun)(yr))


import time
t0 = time.time()
output = dask.compute(results)  # parallel I/O
time.time() - t0   ## 120 seconds for 21 files

## Contrast with the time to read a single file:
t0 = time.time()
readfun(1988)
time.time() - t0   ## 28 seconds for one file
```

I'm not sure why that didn't scale perfectly (i.e., that 21 files on 21 or more workers would take only 28 seconds),
but we do see that it was quite a bit faster than sequentially reading the data would be.

### 6.6. Adaptive scaling

With a resource manager like Kubernetes, Dask can scale the number of workers up and down to adapt to the computational needs of a workflow. Similarly, if submitting jobs to SLURM via Dask, it will scale up and down automatically - see Section 9.

## 7. Monitoring jobs

Dask distributed provides a web interface showing the status of your work.
(Unfortunately I've been having some problems viewing the interface on SCF machines, but hopefully this will work for you.)

By default Dask uses port 8787 for the web interface.

```python
from dask.distributed import Client, LocalCluster
cluster = LocalCluster(n_workers = 4)
c = Client(cluster)

## open a browser to localhost:8787, then watch the progress
## as the computation proceeds

n = 100000000
p = 40

futures = [dask.delayed(calc_mean)(i, n) for i in range(p)]
t0 = time.time()
results = dask.compute(futures)
time.time() - t0
```

If your Python session is not running on your local machine, you can set up port forwarding to view the web interface in the browser on your local machine, e.g.,

```bash
ssh -L 8787:localhost:8787 name_of_remote_machine
```

Then go to `localhost:8787` in your local browser.

## 8. Reliable random number generation (RNG)

In the code above, I was cavalier about the seeds for the random number generation in the different parallel computations.

The general problem is that we want the random numbers generated on each worker to not overlap with the random numbers generated on other workers. But random number generation involves numbers from a periodic sequence. Simply setting different seeds on different workers does not guarantee non-overlapping blocks of random numbers (though in most cases they probably would not overlap). 

Using the basic numpy RNG, one can simply set different seeds for each task, but as mentioned above that doesn't guarantee non-overlapping random numbers.

We can use functionality with numpy's PCG64 or MT19937 generators to be completely safe in our parallel random number generation. Each provide a `jumped()` function that moves the RNG ahead as if one had generated a very large number of random variables ($2^{128}$ for the Mersenne Twister and nearly that for the PCG64).

Here’s how we can set up the use of the PCG64 generator:

```python
bitGen = np.random.PCG64(1)
rng = np.random.Generator(bitGen)
rng.random(size = 3)
```

Now let’s see how to jump forward. And then verify that jumping forward two increments is the same as making two separate jumps.

```python
bitGen = np.random.PCG64(1)
bitGen = bitGen.jumped(1)
rng = np.random.Generator(bitGen)
rng.normal(size = 3)

bitGen = np.random.PCG64(1)
bitGen = bitGen.jumped(2)
rng = np.random.Generator(bitGen)
rng.normal(size = 3)

bitGen = np.random.PCG64(1)
bitGen = bitGen.jumped(1)
bitGen = bitGen.jumped(1)
rng = np.random.Generator(bitGen)
rng.normal(size = 3)
```

We can also use `jumped()` with the Mersenne Twister.

```python
bitGen = np.random.MT19937(1)
bitGen = bitGen.jumped(1)
rng = np.random.Generator(bitGen)
rng.normal(size = 3)
```


So the strategy to parallelize across tasks (or potentially workers if random number generation is done sequentially for tasks done by a single worker) is to give each task the same seed and use `jumped(i)` where `i` indexes the tasks (or workers).

```python
def myrandomfun(i):
    bitGen = np.random.PCG(1)
    bitGen = bitGen.jumped(i)
    # insert code with random number generation
```

One caution is that it appears that the period for PCG64 is $2^{128}$ and that `jumped(1)` jumps forward by nearly that many random numbers. That seems quite strange, and I don’t understand it.

Alternatively as [recommended in the docs](https://numpy.org/doc/stable/reference/random/bit_generators/pcg64.html):

```python
n_tasks = 10
sg = np.random.SeedSequence(1)
rngs = [Generator(PCG64(s)) for s in sg.spawn(n_tasks)]
## Now pass elements of `rngs` into your function that is being computed in parallel

def myrandomfun(rng):
    # insert code with random number generation, such as:
    z = rng.normal(size = 5)
```



## 9. Submitting SLURM jobs from Dask

One can submit jobs to a scheduler such as SLURM from within Python. In general I don't recommend
this as it requires you to be running Python within a stand-alone server while the SLURM
job is running, but here is how one can do it.

Note that the SLURMCluster() call defines the parameters of a single SLURM job, but
`scale()` is what starts one or more jobs. If you ask for more workers than there are
processes defined in your job definition, more than one SLURM job will be launched.

Be careful to request as many processes as cores; if you leave out `processes`, it will
assume only one Python process (i.e., Dask worker) per job. (Also the memory argument
is required.)

The `queue` argument is the SLURM partition you want to submit to.

```python
import dask_jobqueue
## Each job will include 16 Dask workers and a total of 16 cores (1 per worker)
cluster = dask_jobqueue.SLURMCluster(processes=16, cores=16, memory = '24GB',
                                     queue='low', walltime = '3:00:00')

## The following will now start 32 Dask workers in job(s) on the 'low' partition.
## In this case, that requires two SLURM jobs of 16 workers each.
cluster.scale(32)  
from dask.distributed import Client
c = Client(cluster)

## carry out your parallel computations

cluster.close()
```

Dask is requiring the specification of 'memory' though this is not always required by the underlying cluster.

On a cluster like Savio where you may need to provide an account (-A flag), you pass
that via the `project` argument to `SLURMCluster`.

If you'd like to see the SLURM job script that Dask constructs and submits, you can run:

```python
cluster.job_script()
```

### 9.1. Adaptive scaling

If you use `cluster.adapt()` in place of `cluster.scale()`, Dask will start and stop SLURM jobs to start and stop workers as needed.  Note that on a shared cluster, you will almost certainly want to set a maximum number of workers to run at once so you don't accidentally submit 100s or 1000s of jobs.

I'm still figuring out how this works. It seems to work well when having each SLURM job control one worker on one core - in that case Dask starts a set of workers and uses those workers to iterate through the tasks. However when I try to use 16 workers per SLURM job, Dask submits a series of single 16-core jobs rather than using two 16-core jobs that stay active while working through the tasks.

```python
import dask_jobqueue
## Each job will include 16 Dask workers and a total of 16 cores (1 per worker)
## This should now start up to 32 Dask workers, but only one set of 16 workers seems to start
## and SLURM jobs start and stop in quick succession.
## cluster = dask_jobqueue.SLURMCluster(processes=16, cores=16, memory='24 GB',
## queue='low', walltime = '3:00:00')  

## In contrast, this seems to work well.
cluster = dask_jobqueue.SLURMCluster(cores = 1, memory = '24 GB',
                                     queue='low', walltime = '3:00:00')

cluster.adapt(minimum=0, maximum=32)

from dask.distributed import Client
c = Client(cluster)

## carry out your parallel computations
p=200
n=10000000
inputs = [(i, n) for i in range(p)]
# execute the function across the array of input values
future = c.map(calc_mean_vargs, inputs)
results = c.gather(future)

cluster.close()
```
