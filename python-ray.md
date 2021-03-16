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
## alternatively, to specify a specific number of cores:
ray.init(num_cpus = 4)
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

Make sure to request multiple cores per node via --cpus-per-task (on Savio you'd generally set this equal to the number of cores per node).

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
    --num-cpus "${SLURM_CPUS_PER_TASK}" --block &

# optional, though may be useful in certain versions of Ray < 1.0.
sleep 10

# number of nodes other than the head node
worker_num=$((SLURM_JOB_NUM_NODES - 1))

for ((i = 1; i <= worker_num; i++)); do
    node_i=${nodes_array[$i]}
    echo "Starting WORKER $i at $node_i"
    srun --nodes=1 --ntasks=1 -w "$node_i" \
        ray start --address "$ip_head" \
        --num-cpus "${SLURM_CPUS_PER_TASK}" --block &
    sleep 5
done
```

Then in Python, we need to connect to the Ray head node process:

```python
import ray, os
ray.init(address = os.getenv('ip_head'))
```

You should see something like this:

```
2021-03-16 14:39:48,520	INFO worker.py:654 -- Connecting to existing Ray cluster at address: 128.32.135.190:6379
{'node_ip_address': '128.32.135.190', 'raylet_ip_address': '128.32.135.190', 'redis_address': '128.32.135.190:6379', 'object_store_address': '/tmp/ray/session_2021-03-16_14-39-26_045290_3521776/sockets/plasma_store', 'raylet_socket_name': '/tmp/ray/session_2021-03-16_14-39-26_045290_3521776/sockets/raylet', 'webui_url': 'localhost:8265', 'session_dir': '/tmp/ray/session_2021-03-16_14-39-26_045290_3521776', 'metrics_export_port': 63983, 'node_id': '2a3f113e2093d8a8abe3e0ddc9730f8cf6b4478372afe489208b2dcf'}
```


# 4. Using the Ray object store

The object store allows one to avoid making copies of data for each worker process on a node. All workers on a node can share the same data (this also avoids extra copying of data to the workers). And on top of this the object store allows one to use data in the form of numpy arrays directly using the memory allocated for the array in the object store, without any copying into a data structuer specific to the worker process.

Let's try this out.

```
ray.init(num_cpus = 4)   # four worker processes on the local machine

@ray.remote
def calc(i, data):
    import numpy as np  
    return([np.mean(data), np.std(data)])

import numpy as np
rng = np.random.default_rng()
## 'y' is an 800 MB object
n = 100000000
y = rng.normal(0, 1, size=(n))


y_ref = ray.put(y) # put the data in the object store

p = 50

## One can pass the reference to the object in the object store as an argument
futures = [calc.remote(i, y_ref) for i in range(p)]
ray.get(futures)
```

We'll watch memory use via `free -h` while running the test above.

Unfortunately when I test this on a single machine, memory use seems to be equivalent to four copies of the 'y' object, so something seems to be wrong. And trying it on a multi-node Ray cluster doesn't seem to clarify what is going on.

One can also run `ray memory` from the command line (not from within Python) to examine memory use in the object store. (In the case above, it simply reports the 800 MB usage.)

One can also create the object via a remote call and then use it.

```
@ray.remote
def create(n):
    import numpy as np
    rng = np.random.default_rng()
    y = rng.normal(0, 1, size=(100000000))
    return(y)
    
y_ref = create.remote(n)
futures = [calc.remote(i, y_ref) for i in range(p)]
ray.get(futures)
```
