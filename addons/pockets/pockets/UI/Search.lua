--[[
    UI/Search.lua - Case-insensitive item-name search (TDD §15, PRD §3.7)

    Operates over already-resolved item/aggregate records; never rescans
    bags. Used by the panel's search strip (All Items).
]]

local _, Pockets = ...

Pockets.UI.Search = Pockets.UI.Search or {}
local Search = Pockets.UI.Search

-- True if `record.name` contains `query` as a case-insensitive substring.
-- nil/empty query always matches (TDD §15) - callers can pass this
-- straight through without special-casing "no active search".
function Search:Matches(record, query)
    if not query or query == "" then
        return true
    end
    local name = record and record.name and record.name:lower()
    return name ~= nil and name:find(query:lower(), 1, true) ~= nil
end
