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
import std/sugar

#
# type defs
#

proc packedSize(T: type): int {.compileTime.} =
  # calculate the packed size (size with byte alignment) of a type

  for x in T.default.fields:
    result += x.sizeof

type
  Mem = ptr UncheckedArray[byte]

  Datarray*[N: static int, T] {.byref.} = object
    ## Stack-allocated datarray with a fixed size.
    ## Note that `T` **must not** be ref!
    # i tried to constrain `T` but then the compiler yells at me in packedSize
    # so whatever
    mem: array[packedSize(T) * N, byte]

  DynDatarrayObj[T] = object
    mem: Mem
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
    mem: Mem
    arrlen: int
    index: int

  VarElement*[T] = object
    ## An Element pointing to mutable data.
    mem: Mem
    arrlen: int
    index: int

{.push inline.}

#
# raw operations
#

# every type of datarray must implement the mem procedure.
# mem must return a *valid, non-nil* pointer to the raw bytes backing a
# datarray.

# template mem*[N, T](arr: Datarray[N, T]): ptr UncheckedArray[byte] =
#   ## Implementation detail, do not use.
#   cast[ptr UncheckedArray[byte]](arr.data[0].unsafeAddr)

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
  Element[T](
    mem: cast[Mem](arr.mem[0].unsafeAddr),
    arrlen: arr.len,
    index: i
  )

template varIndexImpl(T, arr: untyped, i: int): VarElement[T] =

  rangeCheck i, 0..<arr.len
  VarElement[T](
    mem: cast[Mem](arr.mem[0].unsafeAddr),
    arrlen: arr.len,
    index: i
  )

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

#
# select
#

proc verify(node: NimNode, predicate: bool, error: string) =

  if not predicate:
    error(error, node)

macro select*(loop: ForLoopStmt): untyped =
  ## Selects fields from a datarray. Refer to the example for usage.
  runnableExamples:
    import std/random

    type
      Example = object
        a, b, c: int
    var arr: Datarray[10, Example]

    # there must be two loop variables:
    # 1. the index
    # 2. the fields that should get unpacked
    # the index may be _ if it's not used, but it must always be present.
    # the unpacked fields are desugared to ith() calls.
    for i, (a, b) in select arr:
      a = rand(1.0) < 0.5
      b = a div 2 + i

    # if only one field is needed, the () may be omitted:
    for _, c in select(arr):
      c += 1

  # basic checks
  loop.verify loop.len == 4, "select must have two loop variables"
  loop[2].verify loop[2].kind in {nnkCall, nnkCommand},
    "select can only be used like a normal call or a command call"
  loop[2].verify loop[2].len == 2,
    "select accepts a single argument with the datarray to select from"

  # unpack the AST
  var
    indexVar = loop[0]
    fields = loop[1]
    arr = loop[2][1]
    body = loop[3]

  # check the unpacked AST
  indexVar.verify indexVar.kind == nnkIdent,
    "the index variable's name must be an identifier"
  if fields.kind == nnkIdent:
    fields = nnkVarTuple.newTree(fields, newEmptyNode())
  fields.verify fields.kind == nnkVarTuple,
    "fields must be wrapped in parentheses"

  # generate a forvar for the index if it is _
  if $indexVar == "_":
    indexVar = genSym(nskForVar, "index")

  # generate the templates
  var iths = newStmtList()
  for field in fields[0..^2]:
    field.verify field.kind == nnkIdent,
      "every field must be a single identifier"
    let tmpl = nnkTemplateDef.newTree(
      field,           # name
      newEmptyNode(),  # patterns
      newEmptyNode(),  # generic params
      newTree(nnkFormalParams, bindSym"auto"),
      newEmptyNode(),  # pragmas
      newEmptyNode(),  # -
      quote do:
        `arr`.ith(`indexVar`, `field`)
    )
    iths.add(tmpl)

  # put it all together
  result = quote do:
    for `indexVar` in 0..<`arr`.len:
      `iths`
      `body`

  # wrap the result in a block, because better safe than sorry
  result = newBlockStmt(newEmptyNode(), result)
