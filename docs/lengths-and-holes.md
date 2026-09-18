---
sidebar_position: 2
---

# Lengths & Holes

InfArray tracks **two distinct sizes**.

| Method | Meaning |
| ------ | ------- |
| [`Length()`](/api/InfArray#Length) | The highest assigned index, holes included. What `#arr` returns. |
| [`Count()`](/api/InfArray#Count) | The number of present (non-`nil`) elements. |

## Removals leave holes

[`RemoveIndex`](/api/InfArray#RemoveIndex) clears a slot rather than shifting
everything after it down. This keeps removal `O(1)`, but it means the slot
becomes a `nil` **hole**:

```lua
local arr = InfArray.new()
arr:PushBack("a") -- index 1
arr:PushBack("b") -- index 2
arr:PushBack("c") -- index 3

arr:RemoveIndex(2)

print(arr:Length()) --> 3  (highest index is unchanged)
print(arr:Count())  --> 2  (only "a" and "c" remain)
print(arr:Get(2))   --> nil
```

## A hole is a tombstone, not a `nil`

Clearing a slot writes the `InfArray.EMPTY` sentinel into it. Nothing in the safe
tier surfaces that: [`Get`](/api/InfArray#Get) returns `nil` for a hole, and
iteration skips it. The point is that a chunk is never a holey Luau
table, no matter how it has been mutated.

That keeps two things true permanently rather than conditionally:

* [`Find`](/api/InfArray#Find) is always a single `table.find` fastcall. A real
  `nil` would end that scan early, forcing a fallback interpreted loop (around
  **2.5× slower** with as little as one hole in the chunk).
* Slots never migrate into the table's hash part, so random access stays on the
  array fast path.

Searching for `nil` therefore always returns `nil`. Pass `InfArray.EMPTY` to
locate the first hole.

## When to use `EMPTY` and when to use `nil`

**Use `EMPTY` only when you index a chunk table yourself. Everywhere else use
`nil`.**

| Doing | Use |
| ----- | --- |
| `Set(i, nil)`, `PushBack(nil)`, `Transform` returning nil | `nil` |
| A table with gaps passed to `SetChunk` | `nil`, rewritten for you |
| Reading `Get(i)` | `nil` |
| `Transform` callback's value argument | `nil` |
| `Iterate` or `for..in` value | neither, holes are skipped |
| `chunk[j]` from a raw chunk | `EMPTY` |

Three functions hand back a raw chunk: [`GetChunk`](/api/InfArray#GetChunk),
[`GetChunkAndPosition`](/api/InfArray#GetChunkAndPosition) and
[`IterateChunks`](/api/InfArray#IterateChunks). Never call them and you never
meet `EMPTY`.

## Working with raw chunks

Inside a chunk's tracked length a slot is a value or `EMPTY`, never `nil`, so one
test covers a scan:

```lua
local EMPTY = InfArray.EMPTY

arr:IterateChunks(function(chunk, base, len)
    for j = 1, len do
        local value = chunk[j]
        if value ~= EMPTY then
            -- global index is base + j
        end
    end
end)
```

Two rules:

* **Never call `#` on a raw chunk.** It is padded past its logical length. Use
  the `len` handed to you by `IterateChunks`, or the tracked length. InfArray
  itself never relies on `#chunk`.
* **Never clear a slot yourself.** Writing `nil` or `EMPTY` into a raw chunk
  desyncs the per-chunk hole count that `Count` and `SetChunk` depend on, and a
  raw `nil` reintroduces exactly the holey table the tombstone exists to prevent.
  Read freely; to clear a slot go through [`RemoveIndex`](/api/InfArray#RemoveIndex)
  or [`Set`](/api/InfArray#Set).

## Iteration skips holes

Both `for..in` iteration and [`Iterate`](/api/InfArray#Iterate) skip holes
automatically, so you only ever see present elements:

```lua
for index, value in arr do
    print(index, value) --> 1 a  |  3 c   (index 2 is skipped)
end
```
