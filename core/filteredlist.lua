-- Copyright 2011-2012 Nils Nordman <nino at nordman.org>
-- Copyright 2012-2014 Robert Gieseke <rob.g@web.de>
-- License: MIT (see LICENSE)

--[[--
Filtered list wrapper, hijacking `ui.dialogs.list`.

@module textredux.core.filteredlist
]]

local list = require('textredux.core.list')

local M = {}

local ui_filteredlist = ui.dialogs.list
local current_coroutine

local function convert_multi_column_table(nr_columns, items)
  local _items, _item = {}, {}
  for i, item in ipairs(items) do
    _item[#_item + 1] = item
    if i % nr_columns == 0 then
      _items[#_items + 1] = _item
      _item = {}
    end
  end
  return _items
end

local function index_of(element, tbl)
  for i, e in ipairs(tbl) do
    if e == element then return i end
  end
end

ui.dialogs.list = function(options)
  if not current_coroutine then return ui_filteredlist(options) end
  local co = current_coroutine
  local title = options.title or ''
  local columns = options.columns
  local items = options.items or {}
  if columns then
    columns = type(columns) == 'string' and { columns } or columns
    if #columns > 1 then items = convert_multi_column_table(#columns, items) end
  end

  local new_list = list.new(title, items)
  if columns then new_list.headers = columns end
  new_list.on_selection = function(list_arg, item)
    local value = index_of(item, items)
    list_arg:close()
    if options.multiple then value = { value } end
    if options.return_button then
      coroutine.resume(co, value, 1)
    else
      coroutine.resume(co, value)
    end
  end
  new_list:show()
  return coroutine.yield()
end

-- Wrap
function M.wrap(func)
  return function(...)
    if current_coroutine then
      -- A wrapped call is already in progress.
      -- Invoking a second one would silently overwrite current_coroutine, permanently leaking the first coroutine.
      -- Fall back to calling func directly without the override.
      return func(...)
    end
    current_coroutine = coroutine.create(func)
    local status, val = coroutine.resume(current_coroutine)
    current_coroutine = nil
    if not status then events.emit(events.ERROR, val) end
  end
end

return M
