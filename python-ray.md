Brief Notes on Parallel Processing Using Python's Ray Package
=================================================================

Chris Paciorek, Department of Statistics, UC Berkeley

# 1. Overview of Ray

The Ray package provides a variety of tools for managing parallel computations.

In particular, some of the key ideas/features of Ray are:

  - Allowing users to parallelize independent computations across multiple cores on one or more machines.
  - Different users can run the same code on different computational resources (without touching the actual code that does the computation).
  - One nice feature relative to Dask is that Ray allows one to share data across all worker processes on a node, without multiple copies of hte data, using the *object store*.
  - Ray provides tools to build distributed (across multiple cores or nodes) applications where different processes interact with each other (using the notion of 'actors').

These brief notes just scratch the surface of Ray and just recapitulate basic information available in the [Ray documentation](https://docs.ray.io/en/master/).

# 2. Ray on one machine

On one machine, we can initialize Ray from within Python.

```
import ray
ray.init()
```

To run a computation in parallel, we decorate the function of interest with the `remote` tag:

```
@ray.remote
def f(x):
    return x * x

futures = [f.remote(i) for i in range(4)]
print(ray.get(futures)) # [0, 1, 4, 9]
```

# 3. Ray on multiple machines (nodes)

Here we'll follow the [Ray instructions to start up Ray processes across multiple nodes within a Slurm job](https://docs.ray.io/en/master/cluster/slurm.html).

We need to start the main Ray process (the Ray 'head node') on the head (first) node of Slurm allocation. Then we need to start one worker process for the remaining nodes (do not start a worker on the head node).


```
# Getting the node names
nodes=$(scontrol show hostnames "$SLURM_JOB_NODELIST")
nodes_array=($nodes)

head_node=${nodes_array[0]}
head_node_ip=$(srun --nodes=1 --ntasks=1 -w "$head_node" hostname --ip-address)

port=6379
ip_head=$head_node_ip:$port
export ip_head
echo "IP Head: $ip_head"

echo "Starting HEAD at $head_node"
srun --nodes=1 --ntasks=1 -w "$head_node" \
    ray start --head --node-ip-address="$head_node_ip" --port=$port \
    --num-cpus "${SLURM_CPUS_ON_NODE}" --block &

# optional, though may be useful in certain versions of Ray < 1.0.
sleep 10

# number of nodes other than the head node
worker_num=$((SLURM_JOB_NUM_NODES - 1))

for ((i = 1; i <= worker_num; i++)); do
    node_i=${nodes_array[$i]}
    echo "Starting WORKER $i at $node_i"
    srun --nodes=1 --ntasks=1 -w "$node_i" \
        ray start --address "$ip_head" \
        --num-cpus "${SLURM_CPUS_ON_NODE}" --block &
    sleep 5
done
```

Then in Python, we need to connect to the Ray head node process:

```python
import os
ray.init(address = os.getenv('head_node_ip'))
```

# 4. Using the Ray object store

The object store allows one to avoid making copies of data for each worker process on a node. All workers on a node can share the same data (this also avoids extra copying of data to the workers). And on top of this the object store allows one to use data in the form of numpy arrays directly using the memory allocated for the array in the object store, without any copying into a data structuer specific to the worker process.

Let's try this out.

```
@ray.remote
def calc(i, data):
    import numpy as np  
    return([np.mean(data), np.std(data)])

import numpy as np
rng = np.random.default_rng()
## an 800 MB object
y = rng.normal(0, 1, size=(100000000))


y_ref = ray.put(y) # put the data in the object store

## One can pass the reference to the object in the object store as an argument
futures = [mycalc.remote(i, y_ref) for i in range(p)]
```

We'll watch memory use via `free -h` while running the test above.

