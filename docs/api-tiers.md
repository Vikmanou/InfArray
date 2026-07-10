---
sidebar_position: 3
---

# API Tiers

The API is split into two tiers. Pick the tier per call site.

## Safe tier

[`Get`](/api/InfArray#Get), [`Set`](/api/InfArray#Set),
[`PushBack`](/api/InfArray#PushBack), [`RemoveIndex`](/api/InfArray#RemoveIndex),
[`Iterate`](/api/InfArray#Iterate), [`Transform`](/api/InfArray#Transform).

These maintain `Count`/`Length`, skip holes, and are safe to reach for by
default.

## Raw tier

[`GetChunk`](/api/InfArray#GetChunk), [`SetChunk`](/api/InfArray#SetChunk),
[`IterateChunks`](/api/InfArray#IterateChunks),
[`GetChunkAndPosition`](/api/InfArray#GetChunkAndPosition), and the exported
[`InfArray.locate`](/api/InfArray). These are the fastest path for bulk work, but
**you** are responsible for nil-checking and respecting per-chunk lengths.

```lua
-- Safe: pays a callback + hole-skip per element
arr:Iterate(function(index, value) end)

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

Reach for the raw tier only in the inner loops where per-element overhead
actually shows up in a profile. For measured numbers, see the
[Benchmarks](/benchmarks) tab.
