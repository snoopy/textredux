-- Copyright 2011-2012 Nils Nordman <nino at nordman.org>
-- Copyright 2012-2014 Robert Gieseke <rob.g@web.de>
-- License: MIT (see LICENSE)

--[[--
textredux.fs provides a text based file browser and file system related
functions for Textadept.

It features traditional directory browsing, snapopen functionality, completely
keyboard driven interaction, and provides powerful narrow to search
functionality.

## Some tips on using the file browser

*Switching between traditional browsing and snapopen*

As said above the file browser allows both traditional browsing as well as
snapopen functionality. But it also allows you to seamlessly switch between
the two modes (by default, `Ctrl + S` is assigned for this).

*Quickly moving up one directory level*

In traditional browsing mode, you can always select `..` to move up one
directory level. But a quicker way of doing the same is to press `<backspace>`
when you have an empty search. This also works when in snapopen mode.
Additionally, `Alt + Up` will always go up one directory level
even if the search is not empty.
While the file selection dialog is active it is also possible to quickly select
either the filesystem root or user home directory. To do so press `/` or `~`
respectively.

*Opening a sub directory in snapopen mode*

In contrast with Textadept snapopen, you will in snapopen mode also see sub
directories in the listing. This is by design - you can select a sub directory
to snapopen that directory.

*Opening a file forcefully*
The open function can be used to create new files. However, sometimes
this will not work because the query matches an existing item.
In that case it is possible to force the creation of the file
by using `Ctrl + Enter`.

*Changing the styles used for different file types*

If you don't like the default styles (colors, etc.) used by the file browser,
you can easily change these by customizing any of the `reduxstyle_<foo>` entries
using the Textredux style module. As an example, to make directory entries
underlined you would do something like the following:

    textredux.core.style.fs_directory = {underlined = true}

Please see the documentation for the [Textredux style
module](./textredux.core.style.html) for instructions on how to define styles.

@module textredux.fs
]]

local reduxlist = require 'textredux.core.list'
local reduxstyle = require 'textredux.core.style'

local string_match, string_sub = string.match, string.sub

local user_home = os.getenv('HOME') or os.getenv('UserProfile')
local fs_attributes = WIN32 and lfs.attributes or lfs.symlinkattributes
local separator = WIN32 and '\\' or '/'
local updir_pattern = '%.%.?$'

local M = {}

--- The style used for directory entries.
reduxstyle.fs_directory = reduxstyle.operator

--- The style used for ordinary file entries.
reduxstyle.fs_file = reduxstyle.string

---  The style used for link entries.
reduxstyle.fs_link = reduxstyle.operator

--- The style used for socket entries.
reduxstyle.fs_socket = reduxstyle.error

--- The style used for pipe entries.
reduxstyle.fs_pipe = reduxstyle.error

--- The style used for pipe entries.
reduxstyle.fs_device = reduxstyle.error

local file_styles = {
  directory = reduxstyle.fs_directory,
  file = reduxstyle.fs_file,
  link = reduxstyle.fs_link,
  socket = reduxstyle.fs_socket,
  ['named pipe'] = reduxstyle.fs_pipe,
  ['char device'] = reduxstyle.fs_device,
  ['block device'] = reduxstyle.fs_device,
  other = reduxstyle.default
}

local DEFAULT_DEPTH = 99

-- Splits a path into its components
local function split_path(path)
  local parts = {}
  for part in path:gmatch('[^' .. separator .. ']+') do
    parts[#parts + 1] = part
  end
  return parts
end

-- Joins path components into a path
local function join_path(components)
  local start = WIN32 and '' or separator
  return start .. table.concat(components, separator)
end

-- Returns the dir part of path
local function dirname(path)
  local parts = split_path(path)
  table.remove(parts)
  local dir = join_path(parts)
  if #dir == 0 then return path end -- win32 root
  return dir
end

-- Normalizes the path. This will deconstruct and reconstruct the
-- path's components, while removing any relative parent references
local function normalize_path(path)
  local parts = split_path(path)
  local normalized = {}
  for _, part in ipairs(parts) do
    if part == '..' then
      table.remove(normalized)
    else
      normalized[#normalized + 1] = part
    end
  end
  if #normalized == 1 and WIN32 then -- TODO: win hack
    normalized[#normalized + 1] = ''
  end
  return join_path(normalized)
end

-- Normalizes a path denoting a directory. This will do the same as
-- normalize_path, but will in addition ensure that the path ends
-- with a trailing separator
local function normalize_dir_path(directory)
  local path = normalize_path(directory)
  return path:gsub("[\\/]?%.?[\\/]?$", separator)
end

local function file(path, name, parent)
  local file, error = fs_attributes(path)
  if error then file = { mode = 'error' } end
  local suffix = file.mode == 'directory' and separator or ''
  file.path = path
  file.hidden = name and string_sub(name, 1, 1) == '.'
  if parent then
    file.rel_path = parent.rel_path .. name .. suffix
    file.depth = parent.depth + 1
  else
    file.rel_path = ''
    file.depth = 1
  end
  file[1] = file.rel_path
  return file
end

local function is_filtered(filepath, filter)
  if filepath:match('.+[/\\]' .. updir_pattern) then
    return true
  end
  for _, filter_value in ipairs(filter) do
    local pattern = filter_value
    pattern = pattern:gsub('!', '')
    pattern = pattern:gsub('%.', '%%.')

    if pattern:find('^/') and not pattern:find('/$') then
      pattern = pattern .. '/'
    end
    pattern = pattern:gsub('/', '[/\\]')

    if not pattern:find('/') then
      pattern = pattern .. '$'
    end

    if filepath:find(pattern) then
      return true
    end
  end
  return false
end

local function find_files(directory, filter, depth, max_files)
  if not directory then error('Missing argument #1 (directory)', 2) end
  if not depth then error('Missing argument #3 (depth)', 2) end

  local files = {}

  directory = normalize_path(directory)
  local directories = { file(directory) }
  while #directories > 0 do
    local dir = table.remove(directories)
    if dir.depth > 1 and #filter == 0 then files[#files + 1] = dir end
    if dir.depth <= depth then
      local status, entries, dir_obj = pcall(lfs.dir, dir.path)
      if status then
        for entry in entries, dir_obj do
          local file = file(dir.path .. separator .. entry, entry, dir)

          if is_filtered(file.path, filter) then
            goto continue
          end

          if file.mode == 'directory' and entry ~= '..' and entry ~= '.' then
            table.insert(directories, 1, file)
          else
            if max_files and #files == max_files then return files, false end
            -- Workaround check for top-level (virtual) Windows drive
            if not (WIN32 and #dir.path == 3 and entry == '..') then
              files[#files + 1] = file
            end
          end

          ::continue::
        end
      end
    end
  end
  return files, true
end

local function sort_items(items)
  table.sort(items, function (a, b)
    local self_path = '.' .. separator
    local parent_path = '..' .. separator
    if a.rel_path == self_path then return true
    elseif b.rel_path == self_path then return false
    elseif a.rel_path == parent_path then return true
    elseif b.rel_path == parent_path then return false
    elseif a.hidden ~= b.hidden then return b.hidden
    elseif b.mode == 'directory' and a.mode ~= 'directory' then return false
    elseif a.mode == 'directory' and b.mode ~= 'directory' then return true
    end
    -- Strip trailing separator from directories for correct sorting,
    -- e.g. `foo` before `foo-bar`
    local trailing = separator.."$"
    return a.rel_path:gsub(trailing, "") < b.rel_path:gsub(trailing, "")
  end)
end

local function chdir(list, directory)
  directory = normalize_path(directory)
  local data = list.data
  local items, complete = find_files(directory, data.filter, data.depth, data.max_files)
  if data.depth == 1 then sort_items(items) end
  list.title = directory:gsub(user_home, '~')
  list.items = items
  data.directory = directory
  list:show()
  if #items > 1 and items[1].rel_path:match('^%.%..?$') then
    list.buffer:line_down()
  end
  if not complete then
    local status = 'Number of entries limited to ' ..
                   data.max_files .. ' as per io.quick_open_max'
    ui.statusbar_text = status
  else
    ui.statusbar_text = ''
  end
end

local function open_selected_file(path, exists, list)
  if not exists then
    local button = ui.dialogs.message
    {
      title = 'Create new file',
      text = path .. "\ndoes not exist, do you want to create it?",
      icon = 'dialog-question',
      button1 = 'Create file',
      button2 = 'Cancel',
    }
    if button == 2 then return end

    local file, error = io.open(path, 'wb')
    if not file then
      ui.statusbar_text = 'Could not create ' .. path .. ': ' .. error
      return
    end
    file:close()
  end

  list:close()
  io.open_file(path)
end

local function get_initial_directory()
  local filename = _G.buffer.filename
  if filename then return dirname(filename) end
  return user_home
end

local function get_file_style(item, index)
  return file_styles[item.mode] or reduxstyle.default
end

local function toggle_flatten(list)
  -- Don't toggle for list of Windows drives
  if WIN32 and list.data.directory == "" then return end
  local data = list.data
  local depth = data.depth
  local search = list:get_current_search()

  if data.prev_depth then
    data.depth = data.prev_depth
  else
    data.depth = data.depth == 1 and DEFAULT_DEPTH or 1
  end

  data.prev_depth = depth
  if #data.filter == 0 then
    data.filter = lfs.default_filter
  else
    data.filter = {}
  end
  chdir(list, data.directory)
  list:set_current_search(search)
end

local function get_windows_drives()
  local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  local drives = {}
  for i=1, #letters do
    local drive = letters:sub(i, i)..":\\"
    if fs_attributes(drive) then
      drives[#drives + 1] = file(drive, drive)
      drives[#drives][1] = drive
    end
  end
  return drives
end

local function display_windows_root(list)
  list.items = get_windows_drives()
  list.data.directory = ""
  list.data.depth = 1
  list.title = "Drives"
  list:show()
end

local function updir(list)
  local parent = dirname(list.data.directory)
    if WIN32 and #list.data.directory == 3 then
      display_windows_root(list)
      return true
    elseif parent ~= list.data.directory then
      chdir(list, parent)
      return true
  end
end

local function create_list(directory, filter, depth, max_files)
  local list = reduxlist.new(directory)
  local data = list.data
  list.column_styles = {get_file_style}
  list.keys['f7'] = function()
    local foldername, button = ui.dialogs.input({
      title = 'New folder',
      button1 = 'OK',
      button2 = 'Cancel',
      return_button = true,
      })
      if button == 1 then
        foldername = foldername:gsub('^.*[/\\]', '')
        local path = list.data.directory .. '/' .. foldername
        if WIN32 then
          path = path:gsub('/', '\\')
        end
        os.spawn('mkdir ' .. path):wait()
        chdir(list, list.data.directory)
    end
  end
  list.keys["alt+f"] = toggle_flatten
  list.keys['/'] = function()
    if WIN32 then
      display_windows_root(list)
    else
      chdir(list, '/')
    end
  end
  list.keys['+'] = function()
    if user_home then chdir(list, user_home) end
  end
  list.keys['alt+up'] = function()
    updir(list)
  end
  list.keys['\b'] = function()
    local search = list:get_current_search()
    if not search then
      updir(list)
    else
      list:set_current_search(search:sub(1, -2))
    end
  end
  list.keys['\n'] = function()
    local search = list:get_current_search()
    if #list.buffer.data.matching_items > 0 then
      list.buffer._on_user_select(list.buffer, list.buffer.current_pos)
    elseif #search > 0 then
      if list.on_new_selection then
        list:on_new_selection(search)
      end
    end
  end
  list.keys["right"] = function()
    local search = list:get_current_search()
    if not search then return end
    local found = false

    for _, item in ipairs(list.buffer.data.matching_items) do
      if item[1] == search then
        found = true
        break
      end
    end

    if found then
      list.buffer._on_user_select(list.buffer, list.buffer.current_pos)
    else
      list:on_new_selection(search)
    end
  end
  list.keys['ctrl+a'] = function()
    for _, item in ipairs(list.buffer.data.matching_items) do
      if not item[1]:match('%.%.') then
        io.open_file(list.data.directory .. separator .. item[1])
      end
    end
    list:close()
    ui.statusbar_text = 'All displayed files were opened'
  end

  data.directory = directory
  data.filter = filter
  data.depth = depth
  data.max_files = max_files
  return list
end

--[[- Opens a file browser and lets the user choose a file.
@param on_selection The function to invoke when the user has choosen a file.
The function will be called with following parameters:

- `path`: The full path of the choosen file (UTF-8 encoded).
- `exists`: A boolean indicating whether the file exists or not.
- `list`: A reference to the Textredux list used by browser.

The list will not be closed automatically, so close it explicitly using
`list:close()` if desired.

@param start_directory The initial directory to open, in UTF-8 encoding. If
nil, the initial directory is determined automatically (preferred choice is to
open the directory containing the current file).
@param filter The filter to apply, if any. The structure and semantics are the
same as for Textadept's
[snapopen](http://foicica.com/textadept/api/io.html#snapopen).
@param depth The number of directory levels to display in the list. Defaults to
1 if not specified, which results in a "normal" directory listing.
@param max_files The maximum number of files to scan and display in the list.
Defaults to 10000 if not specified.
]]
function M.select_file(on_selection, start_directory, filter, depth, max_files)
  start_directory = start_directory or get_initial_directory()

  -- Prevent opening another list from an already opened Textredux buffer.
  if buffer._textredux then return false end
  local list = create_list(start_directory, filter, depth or 1,
                           max_files or 10000)

  list.on_selection = function(list, item)
    local path, mode = item.path, item.mode
      if mode == 'link' then
        mode = lfs.attributes(path, 'mode')
      end
      if mode == 'directory' then
        chdir(list, path)
      else
        on_selection(path, true, list, shift, ctrl, alt, meta)
      end
  end

  list.on_new_selection = function(list, name, shift, ctrl, alt, meta)
    local path = split_path(list.data.directory)
    path[#path + 1] = name
    on_selection(join_path(path), false, list, shift, ctrl, alt, meta)
  end

  chdir(list, start_directory)
end

function M.select_directory(on_selection, start_directory, filter, depth, max_files)
  start_directory = start_directory or get_initial_directory()

  local list = create_list(start_directory, filter, depth or 1,
                           max_files or 10000)

  list.on_selection = function(list, item)
    local path, mode = item.path, item.mode
      if mode == 'link' then
        mode = lfs.attributes(path, 'mode')
      end
      if mode == 'directory' then
        if path:match("[/\\]%.$") then
          return
        end
        chdir(list, path)
      end
  end

  list.on_new_selection = function(list, name, shift, ctrl, alt, meta)
    local path = list.data.directory .. separator .. name:gsub("[/\\]*", "")
    on_selection(normalize_dir_path(path), false, list, shift, ctrl, alt, meta)
  end

  list.keys["right"] = function()
    local selected_dir = list:get_current_selection()
    if not selected_dir then
      return
    end

    local path = selected_dir.path
    if path:match("[/\\]%.$") then
      path = path:sub(1, -2)
    elseif path:match("[/\\]%..$") then
      return
    end

    on_selection(normalize_dir_path(path), false, list, shift, ctrl, alt, meta)
  end

  chdir(list, start_directory)
end

--- Saves the current buffer under a new name.
-- Opens a browser and lets the user select a name.
function M.save_buffer_as()
  local function set_file_name(path, exists, list)
    list:close()

    if exists then
      local button = ui.dialogs.message
      {
        title = 'Save buffer as',
        text = path .. "\nexists already!\n\nDo you want to overwrite it?",
        icon = 'dialog-question',
        button1 = 'Overwrite',
        button2 = 'Cancel',
      }
      if button == 2 then return end
    end

    _G.buffer:save_as(path)
    ui.statusbar_text = 'Saved buffer as: ' .. path
  end

  local filter = {}
  M.select_file(set_file_name, nil, filter, 1)
  ui.statusbar_text = 'Save buffer as: select file name to save as...'
      .. " (RIGHT to save as current user input)"
end

--- Saves the current buffer.
-- Prompts the users for a filename if it's a new, previously unsaved buffer.
function M.save_buffer()
  local buffer = _G.buffer
  if buffer.filename then
    buffer:save()
  else
    M.save_buffer_as()
  end
end

--- Opens the specified directory for browsing.
-- @param start_directory The directory to open, in UTF-8 encoding
function M.open_file(start_directory)
  local filter = {}
  M.select_file(open_selected_file, start_directory, filter, 1, io.quick_open_max)
  ui.statusbar_text = '[/] = jump to filesystem root, [~] = jump to userhome, [ctrl+a] = open all currently displayed files'
end


--[[-
Opens a list of files in the specified directory, according to the given
parameters. This works similarily to
[Textadept snapopen](http://foicica.com/textadept/api/io.html#snapopen).
The main differences are:

- it does not support opening multiple paths at once
- filter can contain functions as well as patterns (and can be a function as well).
  Functions will be passed a file object which is the same as the return from
  [lfs.attributes](http://keplerproject.github.com/luafilesystem/manual.html#attributes),
  with the following additions:

    - `rel_path`: The path of the file relative to the currently
      displayed directory.
    - `hidden`: Whether the path denotes a hidden file.

@param directory The directory to open, in UTF-8 encoding.
@param filter The filter to apply. The format and semantics are the same as for
Textadept.
@param exclude_FILTER Same as for Textadept: unless if not true then
snapopen.FILTER will be automatically added to the filter.
to snapopen.FILTER if not specified.
@param depth The number of directory levels to scan. Defaults to DEFAULT_DEPTH
if not specified.
]]
function M.snapopen(directory, filter, exclude_FILTER, depth)
  if not directory then error('directory not specified', 2) end
  if not depth then depth = DEFAULT_DEPTH end
  local filter = lfs.default_filter
  M.select_file(open_selected_file, directory, filter, depth, io.quick_open_max)
end

return M
