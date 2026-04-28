-- Copyright 2011-2012 Nils Nordman <nino at nordman.org>
-- Copyright 2012-2014 Robert Gieseke <rob.g@web.de>
-- License: MIT (see LICENSE)

--[[--
The color module provides utility functions for color handling.

@module textredux.util.color
]]

local M = {}

---
-- Convert color in '#rrggbb' (or 'rrggbb') format to the internal 'bbggrr'
-- integer representation used by Scintilla.
-- @param rgb A color string in '#rrggbb' or 'rrggbb' format.
-- @return The color as a 'bbggrr' integer.
function M.string_to_color(rgb)
  if not rgb then return nil end
  local r, g, b = rgb:match('^#?(%x%x)(%x%x)(%x%x)$')
  if not r then error("Invalid color specification '" .. rgb .. "'", 2) end
  return tonumber(b .. g .. r, 16)
end

---
-- Convert color in the internal hex 'bbggrr' integer format to a '#rrggbb' string.
-- @param color A color as a 'bbggrr' integer.
-- @return The color as a '#rrggbb' string.
function M.color_to_string(color)
  if not color then return nil end
  local hex = string.format('%06x', color)
  local b, g, r = hex:match('^(%x%x)(%x%x)(%x%x)$')
  if not r then error('Invalid color value ' .. tostring(color), 2) end
  return '#' .. r .. g .. b
end

return M
