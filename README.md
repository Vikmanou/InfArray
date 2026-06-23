# InfArray

[![Tests](https://github.com/Vikmanou/InfArray/actions/workflows/test.yml/badge.svg)](https://github.com/Vikmanou/InfArray/actions/workflows/test.yml)

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

local function locate(index)
    local i = index - 1
    local chunkIndex = i // LIMIT
    return chunkIndex + 1, i - chunkIndex * LIMIT + 1
end
```

The instance keeps four fields:

| Field      | Meaning                                                        |
| ---------- | ------------------------------------------------------------- |
| `_chunks`  | Array of backing tables; each holds up to `LIMIT` elements.   |
| `_lens`    | Per-chunk logical length (holes included).                    |
| `_length`  | Logical span of the whole array — the highest assigned index. |
| `_count`   | Number of present (non-`nil`) elements.                       |

Because removals leave `nil` holes, the code **never** relies on `#chunk` (which is undefined once a table has holes). Every length is tracked explicitly.

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
* **Raw tier** — `GetChunk`, `SetChunk`, `IterateChunks`, `GetChunkAndPosition`,  and the exported `InfArray.locate`.
  They are the fastest path for bulk work, but **you** are responsible for
  nil-checking and respecting per-chunk lengths.

```lua
-- Safe: pays a callback + hole-skip per element
arr:Iterate(function(index, value) ... end)

-- Raw: fastest bulk throughput; you nil-check chunk[j] yourself
arr:IterateChunks(function(chunk, base, len)
    for j = 1, len do
        local v = chunk[j]
        if v ~= nil then
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
| `Set`                  | Overwrite an index inside an existing chunk. Does **not** allocate past the end — use `PushBack` to grow. | `index: number, value: any?`                                  | `nil`                         | `O(1)`      |
| `PushBack`             | Append a value to the end.                                                                     | `value: any`                                                            | `index: number` (where it landed) | `O(1)`  |
| `RemoveIndex`          | Clear an index, leaving a `nil` hole (does not shift; `Length` unchanged).                     | `index: number`                                                         | `nil`                         | `O(1)`      |
| `Count`                | Number of present (non-`nil`) elements.                                                        | —                                                                       | `number`                      | `O(1)`      |
| `Length`               | Logical span: highest assigned index, holes included.                                         | —                                                                       | `number`                      | `O(1)`      |
| `Find`                 | First global index whose value equals `needle`.                                               | `needle: any`                                                           | `number?`                     | `O(n)`      |
| `Iterate`              | Visit present elements in order; return `true` from the callback to stop.                      | `callback: (index: number, value: any) -> boolean?`                    | `nil`                         | `O(n)`      |
| `IterateChunks`        | Hand raw chunks to the caller for bulk work; caller nil-checks. Return `true` to stop.         | `callback: (chunk: { any }, base: number, len: number) -> boolean?`    | `nil`                         | `O(chunks)` |
| `Transform`            | Apply `updateFunc` over `[start, stop]` by `step`; maintains `Count`.                          | `start, stop, step: number, updateFunc: (index: number, value: any) -> any` | `nil`                    | `O(range)`  |
| `GetChunk`             | The backing chunk table at a chunk index.                                                      | `chunkIndex: number`                                                    | `{ any }?`                    | `O(1)`      |
| `SetChunk`             | Replace a whole chunk; pass `len` for sparse data (defaults to `#value`).                      | `chunkIndex: number, value: { any }, len: number?`                     | `nil`                         | `O(chunk)`  |
| `GetChunkAndPosition`  | The chunk and 1-based local position for a global index.                                       | `index: number`                                                        | `{ any }?, number`            | `O(1)`      |

The array also supports `#arr` (via `__len`, equals `Length()`) and
`for index, value in arr` (via `__iter`, skips holes, but prefer
`IterateChunks` for bulk throughput).

Also exported:

* `InfArray.LIMIT` — elements per chunk (`2^26`).
* `InfArray.locate(index)` — maps a global index to `chunkIndex, posInChunk`.

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
* **`Set` does not grow the array.** It only writes inside an existing chunk; use  `PushBack`, `new(size)` or `SetChunk` to allocate.
* **Removals leave holes.** `RemoveIndex` does not shift elements. The slot becomes `nil`. This keeps removal `O(1)`.
* **Large pre-allocation is slow.** Initializing beyond `2^24` elements via
  `new(size, value)` may be significantly slower. This is due to Luau's `table.create` function taking longer for initializing larger counts (with `table.create(2^26)` taking ~0.5s).

---

— [@Vikmanou](https://github.com/Vikmanou)
