# Datarray

> Data oriented design made easy.

Datarray is a struct-of-arrays data structure that tries its best to emulate
an object oriented-style array of structs.

```nim
type
  Ant = object
    name: string
    color: string
    isWarrior: bool
    age: int32

var antColony = default Datarray[1000, Ant]

# multiple styles of iteration:

# a) use the fields directly
for i in 0..<antColony.len:
  antColony.ith(i, name) = "joe"
  if antColony.ith(i, isWarrior):
    inc numberOfWarriors

# b.1) use Element[T] as a proxy for easier access
for ant in antColony:
  ant{name} = "joe"
  if ant{isWarrior}:
    inc numberOfWarriors

# b.2) use Element[T] with dot operators
for ant in antColony:
  ant.name = "joe"
  if ant.isWarrior:
    inc numberOfWarriors
```

In all of these examples, datarray does some memory magic to turn `Ant` into
the following:

```nim
type
  AntColony = object
    names: array[1000, string]
    colors: array[1000, string]
    isWarrior: array[1000, bool]
    age: array[1000, int32]
```

while still retaining easy, OOP-like field access using the dot operator.

## Benchmarks

`nim r --passC:-march=native -d:danger src/datarray.nim`

Running on an AMD Ryzen 5 1600

```
name ............................... min time      avg time    std dv   runs
array of ref Ant ................... 2.455 ms      2.518 ms    ±0.038  x1000
array of Ant ....................... 1.283 ms      1.309 ms    ±0.016  x1000
AntColony .......................... 0.371 ms      0.396 ms    ±0.006  x1000
Datarray ith() ..................... 0.364 ms      0.396 ms    ±0.005  x1000
Datarray Element[T] ................ 2.056 ms      2.225 ms    ±0.069  x1000
```

The results with `Element[T]` are kind of disappointing, but I feel like there's
still room for optimization here.
