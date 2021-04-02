##     Data oriented design made easy.
##
## Datarray provides a simple to use array of objects designed for cache
## efficiency. It can be used to build fast programs that manipulate lots of
## data, without sacrificing readability.
##
## Unlike manual solutions, indexing a datarray is done just like any old array
## or seq out there, although it cannot be passed around as an openArray as it
## breaks assumptions about the order of data in memory.
##
## The elements returned by datarrays are rather limited compared to ordinary
## objects. Because the memory layout is completely different,
## a wrapper object – `Element[T]` is used. `Element[T]` stores a pointer to
## the datarray's memory, the datarray's size, and the index of the relevant
## element. Field lookups are desugared to reading from the datarray's memory.
##
## Objects stored in datarrays cannot use UFCS out of the box, and do not have
## destructors. The object fields' destructors get run once the datarray is
## destroyed, which, depending on the allocation type, may be when it goes out
## of scope, or is swept by the GC.
##
## Note that this package is quite experimental and uses the experimental
## dot operator overloading feature of Nim. It is possible to use `{}` instead,
## which may not be as convenient, but is better supported.
##
## Use `-d:datarrayNoDots` to disable this feature and make the usage of `.`
## into an error.

import std/macros

#
# type defs
#

proc packedSize(T: type): int {.compileTime.} =
  # calculate the packed size (size with byte alignment) of a type

  for x in T.default.fields:
    result += x.sizeof

type
  Datarray*[N: static int, T] {.byref.} = object
    ## Stack-allocated datarray with a fixed size.
    ## Note that `T` **must not** be ref!
    # i tried to constrain `T` but then the compiler yells at me in packedSize
    # so whatever
    data: array[packedSize(T) * N, byte]

  DynDatarrayObj[T] = object
    mem: ptr UncheckedArray[byte]
    len: int

  DynDatarray*[T] = ref DynDatarrayObj[T]
    ## A dynamically allocated datarray with a constant size determined at
    ## runtime.

  AnyDatarray* = Datarray | DynDatarray
    ## Either a stack-allocated or dynamically allocated datarray.

  Element*[T] = object
    ## A short-lived pointer to an element in a datarray.
    ## Note that this must not outlive the datarray. In practice this is not
    ## hard to enforce - simply make sure that the element is not written to
    ## any variable that can outlive the datarray this element points to.
    ## This is partially mitigated by `=copy` being unavailable on `Element`\s.
    # once view types become stable, this may be enforced a little bit more
    # easily, by using openArray instead of ptr UncheckedArray and relying on
    # nim's borrow checker.
    # right now view types don't work all that well, so let's just not.
    mem: ptr UncheckedArray[byte]
    arrlen: int
    index: int

  VarElement*[T] = object
    ## An Element pointing to mutable data.
    mem: ptr UncheckedArray[byte]
    arrlen: int
    index: int

{.push inline.}

#
# raw operations
#

# every type of datarray must implement the mem procedure.
# mem must return a *valid, non-nil* pointer to the raw bytes backing a
# datarray.

template mem[N, T](arr: Datarray[N, T]): ptr UncheckedArray[byte] =
  cast[ptr UncheckedArray[byte]](arr.data[0].unsafeAddr)

#
# info
#

proc low*[N, T](arr: Datarray[N, T]): int =
  ## Returns the lower bound of the datarray (always 0).
  0

proc high*[N, T](arr: Datarray[N, T]): int =
  ## Returns the upper bound of the datarray (always N - 1).
  N - 1

proc len*[N, T](arr: Datarray[N, T]): int =
  ## Returns the length of the datarray (always N).
  N

proc low*[T](arr: DynDatarray[T]): int =
  ## Returns the lower bound of the datarray (always 0).
  0

proc high*[T](arr: DynDatarray[T]): int =
  ## Returns the upper bound of the datarray (always len - 1)
  arr.len - 1

proc len*[T](arr: DynDatarray[T]): int =
  ## Returns the length of the datarray.
  arr.len

#
# creation/destruction
#

proc newDynDatarray*[T](len: int): DynDatarray[T] =
  ## Creates a new dynamic datarray with the given length.

  result = DynDatarray[T](
    mem: alloc0(len * packedSize(T)),
    len: len,
  )

template cleanupElements(arr: AnyDatarray) =

  var offset = 0
  for x in T.default.fields:
    for _ in 1..arr.len:
      `=destroy`(cast[ptr typeof(x)](arr.mem[offset].addr)[])
      offset += sizeof(x)

proc `=destroy`*[N, T](arr: var Datarray[N, T]) =
  ## Cleans up the datarray and its elements.
  cleanupElements(arr)

proc `=destroy`*[T](arr: var DynDatarrayObj[T]) =
  ## Cleans up the dynamic datarray and its elements.

  if arr.data != nil:
    cleanupElements(arr)
    dealloc(arr.data)

#
# indexing
#

template rangeCheck(i: int, range: Slice[int]) =
  # system.rangeCheck but the error message doesn't suck

  when compileOption("rangeChecks"):
    if i notin range:
      raise newException(IndexDefect,
        "index " & $i & " out of bounds (" & $range & ")")

template firstIndex[T](arrlen: int, field: untyped): int =
  # returns the index of the first field

  var size = 0
  for name, x in T.default.fieldPairs:
    if name == astToStr(field):
      break
    size += sizeof(x) * arrlen
  size

template nthIndex[T, F](arrlen: int, field: untyped, i: int): int =
  firstIndex[T](arrlen, field) + sizeof(F) * i

template ithImpl(T, arr: untyped, index: int, field: untyped): auto =

  type F = T.default.`field`.typeof
  rangeCheck index, 0..<arr.len
  cast[ptr F](arr.mem[nthIndex[T, F](arr.len, field, index)].unsafeAddr)[]

template ith*[N, T](arr: Datarray[N, T], index: int, field: untyped): auto =
  ## Indexes into a field of an object in the datarray, and returns it.

  let x = ithImpl(T, arr, index, field)
  x

template ith*[N, T](arr: var Datarray[N, T],
                    index: int, field: untyped{ident}): auto =
  ithImpl(T, arr, index, field)

template ith*[T](arr: DynDatarray[T],
                 index: int, field: untyped{ident}): auto =

  let x = ithImpl(T, arr, index, field)
  x

template ith*[T](arr: var DynDatarray[T],
                 index: int, field: untyped{ident}): auto =
  ithImpl(T, arr, index, field)

template indexImpl(T, arr: untyped, i: int): Element[T] =

  rangeCheck i, 0..<arr.len
  Element[T](mem: arr.mem, arrlen: arr.len, index: i)

template varIndexImpl(T, arr: untyped, i: int): VarElement[T] =

  rangeCheck i, 0..<arr.len
  VarElement[T](mem: arr.mem, arrlen: arr.len, index: i)

template `[]`*[N, T](arr: Datarray[N, T], index: int): Element[T] =
  ## Indexes into the array and returns an `Element[T]` for an object with the
  ## given index.
  indexImpl(T, arr, index)

template `[]`*[N, T](arr: var Datarray[N, T], index: int): VarElement[T] =
  ## Indexes into the array and returns a `VarElement[T]` for an object with the
  ## given index. Unlike the non-var version, `VarElement` allows for mutation
  ## of the object's fields.
  varIndexImpl(T, arr, index)

#
# iterators
#

template itemsImpl(T, arr: untyped) =
  for i in 0..<arr.len:
    yield arr[i]

iterator items*[N, T](arr: Datarray[N, T]): Element[T] =
  ## Iterates through the elements in the datarray.
  itemsImpl(T, arr)

iterator items*[N, T](arr: var Datarray[N, T]): VarElement[T] =
  ## Mutably iterates through the elements in the datarray.
  itemsImpl(T, arr)

iterator items*[T](arr: DynDatarray[T]): Element[T] =
  itemsImpl(T, arr)

iterator items*[T](arr: var DynDatarray[T]): VarElement[T] =
  itemsImpl(T, arr)

template pairsImpl(T, arr: untyped) =
  for i in 0..<arr.len:
    yield (i, arr[i])

iterator pairs*[N, T](arr: Datarray[N, T]): (int, Element[T]) =
  ## Iterates through the elements in the datarray, also yielding their indices.
  pairsImpl(T, arr)

iterator pairs*[N, T](arr: var Datarray[N, T]): (int, VarElement[T]) =
  ## Mutably Iterates through the elements in the datarray, also yielding their
  ## indices.
  pairsImpl(T, arr)

iterator pairs*[T](arr: DynDatarray[T]): (int, Element[T]) =
  pairsImpl(T, arr)

iterator pairs*[T](arr: var DynDatarray[T]): (int, VarElement[T]) =
  pairsImpl(T, arr)

#
# elements
#

# making copies of elements is illegal
proc `=copy`*[T](dest: var Element[T], src: Element[T]) {.error.}
proc `=copy`*[T](dest: var VarElement[T], src: VarElement[T]) {.error.}

template `{}`*[T](e: Element[T], field: untyped{ident}): auto =
  ## Accesses a field in the element.

  type F = T.default.`field`.typeof
  let x =
    cast[ptr F](e.mem[nthIndex[T, F](e.arrlen, field, e.index)].unsafeAddr)[]
  x

template `{}`*[T](e: VarElement[T], field: untyped{ident}): auto =
  ## Mutably accesses a field in the var element.

  type F = T.default.`field`.typeof
  cast[ptr F](e.mem[nthIndex[T, F](e.arrlen, field, e.index)].unsafeAddr)[]

template `{}=`*[T](e: VarElement[T], field: untyped{ident}, value: sink auto) =
  ## Writes to a field in the object pointed to by the var element.

  type F = T.default.`field`.typeof
  cast[ptr F](e.mem[nthIndex[T, F](e.arrlen, field, e.index)].unsafeAddr)[] =
    value

when not defined(datarrayNoDots):
  {.push experimental: "dotOperators".}

  template `.`*[T](e: Element[T], field: untyped{ident}): auto =
    ## Dot access operator for Elements. Sugar for `e{field}`.
    e{field}

  template `.`*[T](e: VarElement[T], field: untyped{ident}): auto =
    ## Dot access operator for VarElements. Sugar for `e{field}`.
    e{field}

  template `.=`*[T](e: VarElement[T], field: untyped{ident}, value: untyped) =
    ## Dot equals operator for VarElements. Sugar for `e{field} = value`.
    e{field} = value

  {.pop.}

{.pop.}


when isMainModule:

  # example taken from:
  # https://blog.royalsloth.eu/posts/the-compiler-will-optimize-that-away/

  import std/random

  import benchy

  type
    Ant = object
      name: string
      color: string
      isWarrior: bool
      age: int32

  const size = 1000000

  #
  # array of ref Ant
  # equivalent to the OOP Java version
  #

  block:
    var antColony: array[size, ref Ant]
    for ant in antColony.mitems:
      ant = new Ant
      ant.isWarrior = rand(1.0) < 0.5

    timeIt "array of ref Ant":
      var numberOfWarriors: int
      for ant in antColony:
        if ant.isWarrior:
          inc numberOfWarriors
      writeFile("/dev/null", $numberOfWarriors)  # keep wouldn't work

  #
  # array of Ant
  # faster than the OOP Java version, as it doesn't involve an extra
  # pointer indirection
  #

  block:
    var antColony: array[size, Ant]
    for ant in antColony.mitems:
      ant.isWarrior = rand(1.0) < 0.5

    timeIt "array of Ant":
      var numberOfWarriors: int
      for ant in antColony:
        if ant.isWarrior:
          inc numberOfWarriors
      writeFile("/dev/null", $numberOfWarriors)

  #
  # AntColony
  #

  block:
    type
      AntColony = object
        names: array[size, string]
        colors: array[size, string]
        warriors: array[size, bool]
        ages: array[size, int32]

    var antColony: AntColony
    for isWarrior in antColony.warriors.mitems:
      isWarrior = rand(1.0) < 0.5

    timeIt "AntColony":
      var numberOfWarriors: int
      for i in 0..<size:
        if antColony.warriors[i]:
          inc numberOfWarriors
      writeFile("/dev/null", $numberOfWarriors)

  #
  # datarray
  #

  block:
    var antColony: Datarray[size, Ant]
    for ant in antColony:
      ant.isWarrior = rand(1.0) < 0.5

    timeIt "Datarray ith()":
      var numberOfWarriors: int
      for i in 0..<antColony.len:
        if antColony.ith(i, isWarrior):
          inc numberOfWarriors
      writeFile("/dev/null", $numberOfWarriors)

    timeIt "Datarray Element[T]":
      var numberOfWarriors: int
      for ant in antColony:
        if ant{isWarrior}:
          inc numberOfWarriors
      writeFile("/dev/null", $numberOfWarriors)

