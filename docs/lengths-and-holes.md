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

## Why `#` is never trusted internally

Once a Luau table contains holes, the result of `#chunk` is undefined. InfArray
therefore tracks a per-chunk logical length explicitly (`_lens`) and always scans
to that length. Your code should do the same when working with raw chunks. Never
call `#` on a value returned by [`GetChunk`](/api/InfArray#GetChunk). Instead, use the
`len` handed to you by [`IterateChunks`](/api/InfArray#IterateChunks).

## Never write holes into a raw chunk

Alongside `_lens`, InfArray tracks per chunk whether that chunk is known to be
hole-free. Hole-free chunks take faster paths where [`Find`](/api/InfArray#Find)
drops to a single `table.find` call, and [`Iterate`](/api/InfArray#Iterate) skips
its per-element `nil` check.

A raw chunk handed to you by
[`GetChunk`](/api/InfArray#GetChunk) or [`IterateChunks`](/api/InfArray#IterateChunks)
does not: writing `nil` into one behind InfArray's back leaves the chunk marked
hole-free, and `Find` will then stop at your hole and miss everything after it in
that chunk. Read freely from raw chunks; to clear a slot, go through
[`RemoveIndex`](/api/InfArray#RemoveIndex) or [`Set`](/api/InfArray#Set).

## Iteration skips holes

Both `for..in` iteration and [`Iterate`](/api/InfArray#Iterate) skip holes
automatically, so you only ever see present elements:

```lua
for index, value in arr do
    print(index, value) --> 1 a  |  3 c   (index 2 is skipped)
end
```
