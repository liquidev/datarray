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
## Note that this package is quite experimental and uses the experimental
## dot operator overloading feature of Nim. It is possible to use `{}` instead,
## which may not be as convenient, but is actually supported.
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

  Element*[T] = object
    ## A short-lived pointer to an element in a datarray.
    ## Note that this must not outlive the datarray. In practice this is not
    ## hard to enforce - simply make sure that the element is not written to
    ## any variable that can outlive the datarray this element points to.
    # once view types become stable, this may be enforced a little bit more
    # easily, by using openArray instead of ptr UncheckedArray.
    # right now view types don't work all that well.
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

proc mem[N, T](arr: Datarray[N, T]): ptr UncheckedArray[byte] =
  cast[ptr UncheckedArray[byte]](arr.data[0].unsafeAddr)

#
# info
#

proc low*[N, T](arr: Datarray[N, T]): int =
  ## Returns the lower bound of the datarray (always 0).
  0

proc high*[N, T](arr: Datarray[N, T]): int =
  ## Returns the upper bound of the datarray (always N).
  N

proc len*[N, T](arr: Datarray[N, T]): int =
  ## Returns the length of the datarray (always N).
  N

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
      return
    size += sizeof(x) * arrlen
  size

template nthIndex[T, F](arrlen: int, field: untyped, i: int): int =
  firstIndex[T](arrlen, field) + sizeof(F) * i

template ith*[N, T](arr: Datarray[N, T], index: int, field: untyped): auto =
  ## Indexes into a field of an object in the datarray, and returns it.

  type F = T.default.`field`.typeof
  rangeCheck index, 0..<N
  let x = cast[ptr F](arr.mem[nthIndex[T, F](N, field, index)].unsafeAddr)[]
  x

template ith*[N, T](arr: var Datarray[N, T],
                    index: int, field: untyped{ident}): auto =

  type F = T.default.`field`.typeof
  rangeCheck index, 0..<N
  cast[ptr F](arr.mem[nthIndex[T, F](N, field, index)].unsafeAddr)[]

proc `[]`*[N, T](arr: Datarray[N, T], index: int): Element[T] =
  ## Indexes into the array and returns an `Element[T]` for an object with the
  ## given index.

  rangeCheck index, 0..<N
  Element[T](mem: arr.mem, arrlen: N, index: index)

proc `[]`*[N, T](arr: var Datarray[N, T], index: int): VarElement[T] =
  ## Indexes into the array and returns a `VarElement[T]` for an object with the
  ## given index. Unlike the non-var version, `VarElement` allows for mutation
  ## of the object's fields.

  rangeCheck index, 0..<N
  VarElement[T](mem: arr.mem, arrlen: N, index: index)

iterator items*[N, T](arr: Datarray[N, T]): Element[T] =
  ## Iterates through the elements in the datarray.

  for i in 0..<N:
    yield arr[i]

iterator items*[N, T](arr: var Datarray[N, T]): VarElement[T] =
  ## Mutably iterates through the elements in the datarray.

  for i in 0..<N:
    yield arr[i]

#
# elements
#

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

  type
    Ant = object
      name: string
      color: string
      isWarrior: bool
      age: int32

  var antColony = default Datarray[1000, Ant]

  proc testDirectAccess() =
    var numberOfWarriors: int

    for i in 0..<antColony.len:
      if antColony.ith(i, isWarrior):
        antColony.ith(i, isWarrior) = true
        inc numberOfWarriors

    echo numberOfWarriors

  proc testAccessThroughElement() =
    var numberOfWarriors: int

    for ant in antColony:
      if ant{isWarrior}:
        ant{isWarrior} = true
        inc numberOfWarriors

    echo numberOfWarriors

  proc testAccessThroughElementWithDotOperator() =
    var numberOfWarriors: int

    for ant in antColony:
      if ant.isWarrior:
        ant.isWarrior = true
        inc numberOfWarriors

    echo numberOfWarriors

  testAccessThroughElementWithDotOperator()
  testDirectAccess()
  testAccessThroughElement()

