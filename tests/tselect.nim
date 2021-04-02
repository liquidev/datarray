import std/random

import datarray

include ant

var antColony: Datarray[1000, Ant]
for ant in antColony:
  ant.name = sample ["joe", "josh", "dave"]
  ant.color = sample ["red", "green", "blue"]
  ant.isWarrior = rand(1.0) < 0.5
  ant.age = int32 rand(1 .. 3)

var numChosen = 0
for i, (age, color) in select antColony:
  if age > 1 and color == "red":
    inc numChosen
echo numChosen
