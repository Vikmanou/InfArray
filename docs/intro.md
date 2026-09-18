---
sidebar_position: 1
---

# Getting Started

**InfArray** is a chunked Luau array that bypasses Luau's internal table size
limit of 2^26. Values are stored across fixed-size chunks, so a single logical
array can hold up to 2^53 elements which is the largest exact integer a Luau `number`
can represent.

## Installation

Copy `InfArray.luau` into your project and require it:

```lua
local InfArray = require(path.to.InfArray)
```

## Basic usage

```lua
local arr = InfArray.new()

arr:PushBack("a")
arr:PushBack("b")

print(arr:Get(1)) --> "a"
print(#arr)       --> 2  (highest assigned index)
print(arr:Count()) --> 2 (present, non-nil elements)
```

## Holes

Removing an element leaves a `nil` hole rather than shifting later elements.
`Length()` still reports the highest assigned index, while `Count()` reports how
many elements are actually present:

```lua
arr:RemoveIndex(1)

print(arr:Length()) --> 2
print(arr:Count())  --> 1
```

## Iteration

Use generalized `for..in` iteration, the `Iterate` callback, or for the best
bulk throughput, use `IterateChunks`, which hands you raw chunks:

```lua
for index, value in arr do
    print(index, value)
end

arr:IterateChunks(function(chunk, base, len)
    for j = 1, len do
        local value = chunk[j]
        if value ~= nil then
            -- global index is base + j
        end
    end
end)
```

## Performance

The hot paths are hand-tuned against the
[Luau optimizing compiler](https://luau.org/performance): index arithmetic is
inlined at every call site and field reads are hoisted into locals. A cleared
slot stores a tombstone rather than `nil`, so a chunk is never a holey table and
`Find` is always a single `table.find` fastcall and slots never migrate into the
table's hash part. The module compiles under `--!native` and `--!optimize 2`.
The README lists the full set, and `benchmark/` has the numbers behind it.

See the [API reference](/api/InfArray) for the full list of methods.
