<div align="center">

# InfArray

<img src="https://img.shields.io/badge/InfArray-v1.0.0-7aa2f7?style=for-the-badge&logoColor=white" alt="version" />
<img src="https://img.shields.io/badge/Luau-Roblox-00A2FF?style=for-the-badge&logoColor=white" alt="luau" />
<a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-9ece6a?style=for-the-badge" alt="license" /></a>
<a href="https://github.com/Vikmanou/InfArray/actions/workflows/test.yml"><img src="https://img.shields.io/badge/Tests-44%20passing-1abc9c?style=for-the-badge" alt="tests" /></a>

</div>

> A Luau array that holds more than `2^26` elements by chunking the data across many backing tables. Indices stay valid up to `2^53` — the largest exact integer a Luau `number` can represent.

InfArray exists because a single Luau table cannot grow past `2^26`
(`67,108,864`) elements. It splits storage into fixed-size chunks and maps a
global index onto `(chunkIndex, positionInChunk)` with integer math, so the array behaves like one contiguous sequence while never asking any individual table to exceed the engine's limit.

```lua
local InfArray = require(path.to.InfArray)

local arr = InfArray.new()
for i = 1, 100_000_000 do   -- 10^8 > 2^26: a native table errors here
    arr:PushBack(i)
end

print(arr:Length(), arr:Count()) --> 100000000  100000000
```

---

## What is InfArray?

Luau's table upper bound seems to be `2^26`, defined in
the official [Luau source](https://github.com/luau-lang/luau/blob/master/VM/src/ltable.cpp#L36-L38):

```cpp
// Luau caps the array portion of a table at 2^MAXBITS
#define MAXBITS 26
#define MAXSIZE (1 << MAXBITS)
```

InfArray bypasses this.

## How it works

A global 1-based `index` maps to a chunk and a 1-based position inside it:

```lua
local LIMIT = 2 ^ 26 -- 67,108,864 elements per chunk

local i = index - 1
local chunkIndex = i // LIMIT
local pos = i - chunkIndex * LIMIT + 1
chunkIndex += 1
```

That arithmetic is written out at each call site rather than kept in a helper, so
the hot paths never pay a call.

The instance keeps five fields:

| Field      | Meaning                                                        |
| ---------- | ------------------------------------------------------------- |
| `_chunks`  | Array of backing tables; each holds up to `LIMIT` elements.   |
| `_lens`    | Per-chunk logical length (holes included).                    |
| `_holes`   | Per-chunk count of tombstoned slots below that length.        |
| `_length`  | Logical span of the whole array — the highest assigned index. |
| `_count`   | Number of present (non-`nil`) elements.                       |

### Holes are tombstones, not `nil`

Clearing a slot stores a private `EMPTY` sentinel rather than `nil`. A chunk is
therefore never a holey Luau table, whatever sequence of removals it has been
through:

* `Find` is always a single `table.find` fastcall. A `nil` would end that scan
  early, so with real holes it would have to fall back to an interpreted loop —
  measured at **2.5× slower** with as little as one hole in the chunk.
* Slots never migrate into the table's hash part, so random access stays on the
  array fast path and pre-sizing is never wasted.

Lengths are still tracked explicitly in `_lens` rather than read from `#chunk`,
since a chunk is padded past its logical length.

#### When to use `EMPTY` and when to use `nil`

The sentinel is exported as `InfArray.EMPTY`. **Use it only when you index a
chunk table yourself. Everywhere else use `nil`.**

| Doing | Use |
| ----- | --- |
| `Set(i, nil)`, `PushBack(nil)`, `Transform` returning nil | `nil` |
| A table with gaps passed to `SetChunk` | `nil`, rewritten for you |
| Reading `Get(i)` | `nil` |
| `Transform` callback's value argument | `nil` |
| `Iterate` or `for .. in` value | neither, holes are skipped |
| `chunk[j]` from a raw chunk | `EMPTY` |

Three functions hand back a raw chunk: `GetChunk`, `GetChunkAndPosition` and
`IterateChunks`. Never call them and you never meet `EMPTY`. Inside a chunk's
tracked length a slot is a value or `EMPTY`, never `nil`.

### Two lengths

An InfArray tracks two distinct sizes:

* **`Length()`** — the *logical span*: the highest assigned index, holes
  included.
* **`Count()`** — the number of *present* (non-`nil`) elements.

After `arr:RemoveIndex(i)` in the middle of the array, `Count()` drops by one but `Length()` is unchanged. The slot becomes a `nil` hole rather than shifting everything after it down (`O(1)` removal instead of `O(n)`).

---

## The core design tension: performance vs. ease of use

The hardest part of building InfArray was balancing **raw performance** against a **safe, ergonomic API**. Every safety convenience (nil-checking, count maintenance, hole-skipping) costs cycles on a hot path that runs billions of times in a workload.

InfArray resolves this with a **two-tier API**:

* **Safe tier** — `Get`, `Set`, `PushBack`, `RemoveIndex`, `Iterate`,
  `Transform`. 
* **Raw tier** — `GetChunk`, `SetChunk`, `IterateChunks`, `GetChunkAndPosition`.
  They are the fastest path for bulk work, but **you** are responsible for
  skipping tombstones and respecting per-chunk lengths. Read freely; clearing a
  slot in a raw chunk yourself desyncs the hole count. Use `RemoveIndex` or
  `Set` for that. See [Lengths & Holes](docs/lengths-and-holes.md).

```lua
-- Safe: pays a callback + hole-skip per element
arr:Iterate(function(index, value) ... end)

-- Raw: fastest bulk throughput; you skip holes yourself
local EMPTY = InfArray.EMPTY

arr:IterateChunks(function(chunk, base, len)
    for j = 1, len do
        local v = chunk[j]
        if v ~= EMPTY then
            -- global index is base + j
        end
    end
end)
```

Pick the tier per call site: reach for the raw tier only in the inner loops
where the per-element overhead actually shows up in a profile.

---

## API

`InfArray.new([size: number], [value: any])` creates a new instance. Think of it as `table.create`. See [Limitations](#limitations) for sizes beyond `2^24`.

| Method                 | Description                                                                                   | Argument(s)                                                              | Returns                       | Time        |
| ---------------------- | --------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- | ----------------------------- | ----------- |
| `Get`                  | Value at a global index (`nil` if absent or out of range).                                      | `index: number`                                                         | `any?`                        | `O(1)`      |
| `Set`                  | Overwrite an index inside an existing chunk. Does **not** allocate past the end — use `PushBack` to grow. Returns whether the write happened. | `index: number, value: any?`                                  | `boolean` (`true` if written, `false` if no-op) | `O(1)`      |
| `PushBack`             | Append a value to the end.                                                                     | `value: any`                                                            | `index: number` (where it landed) | `O(1)`  |
| `RemoveIndex`          | Clear an index, leaving a hole (does not shift; `Length` unchanged).                           | `index: number`                                                         | `nil`                         | `O(1)`      |
| `Count`                | Number of present (non-`nil`) elements.                                                        | —                                                                       | `number`                      | `O(1)`      |
| `Length`               | Logical span: highest assigned index, holes included.                                         | —                                                                       | `number`                      | `O(1)`      |
| `Find`                 | First global index whose value equals `needle`.                                               | `needle: any`                                                           | `number?`                     | `O(n)`      |
| `Iterate`              | Visit present elements in order; return `true` from the callback to stop.                      | `callback: (index: number, value: any) -> boolean?`                    | `nil`                         | `O(n)`      |
| `IterateChunks`        | Hand raw chunks to the caller for bulk work; caller skips `EMPTY`. Return `true` to stop.      | `callback: (chunk: { any }, base: number, len: number) -> boolean?`    | `nil`                         | `O(chunks)` |
| `Transform`            | Apply `updateFunc` over `[start, stop]` by `step`; maintains `Count`.                          | `start, stop, step: number, updateFunc: (index: number, value: any) -> any` | `nil`                    | `O(range)`  |
| `GetChunk`             | The backing chunk table at a chunk index.                                                      | `chunkIndex: number`                                                    | `{ any }?`                    | `O(1)`      |
| `SetChunk`             | Replace a whole chunk; pass `len` for sparse data (defaults to `#value`).                      | `chunkIndex: number, value: { any }, len: number?`                     | `nil`                         | `O(chunk)`  |
| `GetChunkAndPosition`  | The chunk and 1-based local position for a global index.                                       | `index: number`                                                        | `{ any }?, number`            | `O(1)`      |

The array also supports `#arr` (via `__len`, equals `Length()`) and
`for index, value in arr` (via `__iter`, skips holes, but prefer
`IterateChunks` for bulk throughput).

Also exported:

* `InfArray.LIMIT` — elements per chunk (`2^26`).
* `InfArray.EMPTY` — the tombstone stored in a cleared slot. Compare against it
  when reading a raw chunk. `Get` never returns it.

###### *n is the number of elements.*

### Legacy names

These older names remain as aliases for forward compatibility, but new code
should prefer the primary names above:

`get` / `GetValueAtIndex` → `Get` · `set` / `Replace` → `Set` ·
`InsertBack` → `PushBack` · `GetTotalLen` → `Count` · `GetLength` → `Length` ·
`TransformRange` → `Transform`

---

## Installation

InfArray is a single file: [`InfArray.luau`](InfArray.luau). Drop it into your
project and require it.

---

## Usage example

```lua
local InfArray = require(game.ReplicatedStorage.InfArray)

local t = InfArray.new(10)

local limit = 30

print(t:Count())
print(t:Get(5))

local i = 0
while i < limit do
    i += 1
    t:PushBack(i)
end

t:Iterate(function(index: number, value: any)
    print(index, value)
end)

-- Double every element in [1, t:Length()]
t:Transform(1, t:Length(), 1, function(index, value)
    return value * 2
end)

print(t:Find(8))
print(t:Count())
print(t:Get(5))
t:Set(5, 'replace thing')
print(t:Get(5))
```

More complete, real-world programs live in [`examples/`](examples/):

* [`examples/DivisorsCountSieve.luau`](examples/DivisorsCountSieve.luau) — a sieve that records the number of divisors of every integer up to `n`, using `Transform` to accumulate prime-power contributions across an InfArray-backed table.
* [`examples/TotientsToN.luau`](examples/TotientsToN.luau) — computes Euler's totient `φ(i)` for every `i` up to `n` with a nested `Transform` sieve.

---

## Benchmarks

InfArray trades a little per-element speed for the ability to hold more than a
single Luau table can. Every benchmark below stays *under* `2^26` so a regular table is a fair baseline. These measure the chunking overhead, **not** the cases where a native table can't compete.

Run them yourself with [Lute](https://github.com/luau-lang/lute) on your PATH:

```sh
lute run benchmark/run.luau            # print results
```

Latest numbers (`n = 4,194,304` (`2^22`); AMD Ryzen 9 9950X, Windows; machine-specific —
treat as relative ratios):

| Workload                          | InfArray   | Luau table | InfArray vs table |
| --------------------------------- | ---------- | ---------- | ----------------- |
| `PushBack` — append N             | 48.4 ns    | 8.0 ns     | 6.07× slower      |
| `Set` — overwrite N in-range      | 32.4 ns    | 3.3 ns     | 9.73× slower      |
| `Get` — sequential read           | 26.8 ns    | 3.3 ns     | 8.08× slower      |
| `Get` — random-access read        | 108.6 ns   | 36.7 ns    | 2.96× slower      |
| `Iterate` — visit every element   | 13.7 ns    | 2.6 ns     | 5.38× slower      |
| `for .. in arr` (`__iter`)        | 28.7 ns    | 2.5 ns     | 11.37× slower     |
| `Find` — linear search (needle at end) | 3.9 ns  | 1.9 ns    | 2.10× slower      |

See [benchmark/README.md](benchmark/README.md) for full output, methodology and how to add your own cases.

---

## Testing

Tests live in [`tests/`](tests/) and use Lute's built-in test runner:

```sh
lute test
```

---

## Limitations

* **Built for arrays, not dictionaries.** InfArray is a sequence keyed by
  contiguous integer indices. There is no hashed-key storage.
* **Slower per element than a native table.** Every access pays an extra chunk lookup. Use InfArray when you need capacity past `2^26`, not for small arrays that already fit.
* **`Set` does not allocate new chunks.** It writes only inside a chunk that already exists, returning `true` when the write lands and `false` (a no-op) when the target index maps to an unallocated chunk. Within an existing chunk it *can* fill a hole past the current `Length()` and extend it; it just won't create the next chunk — use `PushBack`, `new(size)` or `SetChunk` for that.
* **Removals leave holes.** `RemoveIndex` does not shift elements. The slot reads back as `nil` and is skipped by iteration; internally it holds the `InfArray.EMPTY` tombstone. This keeps removal `O(1)`.
* **Large pre-allocation is slow.** Initializing beyond `2^24` elements via
  `new(size, value)` may be significantly slower. This is due to Luau's `table.create` function taking longer for initializing larger counts (with `table.create(2^26)` taking ~0.5s).

---

## Further reading

I wrote up the design decisions, the `2^26` limit, and the performance
trade-offs behind InfArray in a blog post:

* **[The story behind InfArray](https://viken.games/blog/infarray)** — why a
  single Luau table caps out, how the chunking scheme works, and the
  performance-vs-ergonomics tension that brought the two-tier API.

---

— [@Vikmanou](https://github.com/Vikmanou)
