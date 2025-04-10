def calc_mean(i, n):
    import numpy as np
    rng = np.random.default_rng(i)
    data = rng.normal(size = n)
    return([np.mean(data), np.std(data)])


# We need a version of calc_mean() that takes a single input.
def calc_mean_vargs(inputs):
    import numpy as np
    rng = np.random.default_rng(inputs[0])
    data = rng.normal(size = inputs[1])
    return([np.mean(data), np.std(data)])

