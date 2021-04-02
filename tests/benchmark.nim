# example taken from:
# https://blog.royalsloth.eu/posts/the-compiler-will-optimize-that-away/

import std/random

import benchy
import datarray

include ant

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

