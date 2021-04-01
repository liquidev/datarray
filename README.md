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

**TODO:** Benchmarks
