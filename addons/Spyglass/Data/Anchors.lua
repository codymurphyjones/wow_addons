-- The shared history that decides which SpyGlass clients trust each other when
-- they sync discoveries (Sync.lua). Tools/export_anchors.py rewrites the
-- developer's part from the developer's saved commits.
local _, ns = ...
ns.Anchors = {
    -- Version 1 (SIMPLE_TRUST in Sync.lua): every client has these three.
    seeds = { "7767ae0a62afef5d", "c5261023b7fb839f", "07b841d9cbc469e8" },
    -- Version 2: the developer's commits, by sequence number ([seq] = hash).
    dev = {
    },
}
