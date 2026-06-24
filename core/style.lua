-- Copyright 2011-2012 Nils Nordman <nino at nordman.org>
-- Copyright 2012-2014 Robert Gieseke <rob.g@web.de>
-- License: MIT (see LICENSE)

--[[--
The style module lets you define and use custom, non-lexer-based styles.

## What's a style?

Textredux styling provides an abstraction layer over the lexer based style
creation. A style is thus just a table with certain properties, almost exactly
the same as for style created for a lexer or theme. Please see the documentation
for
[lexer.style](https://orbitalquark.github.io/textadept/api/lexer.html#Styles.and.Styling)
for information about the available fields. Colors should be defined in the
standard `'#rrggbb'` notation.

## Defining styles

You define a new style by assigning a table with its properties to the module:

    local reduxstyle = require 'textredux.core.style'
    reduxstyle.foo_header = { italics = true, fore = '#680000' }

As has been previously said, it's often a good idea to base your custom styles
on an existing default style. Similarly to defining a lexer style in Textadept
you can achieve this by concatenating styles:

    reduxstyle.foo_header = style.string .. { underlined = true }

*NB:* Watch out for the mistake of assigning the style to a local variable:

    local header = reduxstyle.string .. { underlined = true }

This will _not_ work, as the style is not correctly defined with the style
module, necessary to ensure styles are correctly defined when new buffers
are created.

In order to avoid name clashes, it's suggested that you name any custom styles
by prefixing their name with the name of your module. E.g. if your module is
named `awesome`, then name your style something like `style.awesome_style`.

## Updating styles

To make them fit better with your theme or preferences you can change styles
already set by overwriting their properties in your `init.lua`:

    local textredux = require('textredux')
    local reduxstyle = textredux.core.style
    reduxstyle.list_match_highlight.fore = reduxstyle.class.fore
    reduxstyle.fs_directory.italics = true

## Using styles

You typically use a style by inserting text through
@{textredux.core.buffer}'s text insertion methods, specifying the style.
Please see also the example in `examples/buffer_styling.lua`.

    reduxbuffer:add_text('Foo header text', reduxstyle.foo_header)

## The default styles

Textredux piggybacks on the default lexer styles defined by a user's theme,
and makes them available for your Textredux interfaces. The big benefit of this
is that by using those styles or basing your custom styles on them, your
interface stands a much higher chance of blending in well with the color scheme
used. As an example, your custom style with cyan foreground text might look
great with your own dark theme, but may be pretty near invisible for some user
with a light blue background.

You can read more about the default lexer styles in the
[Textadept lexer documentation](https://orbitalquark.github.io/textadept/api/lexer.html).
You access a default style (or any style for that matter), by indexing the
style module, like so: `style.<name>`. For reference, the default styles
available are these:

- style.nothing
- style.whitespace
- style.comment
- style.string
- style.number
- style.keyword
- style.identifier
- style.operator
- style.error
- style.preproc
- style.constant
- style.variable
- style.function
- style.class
- style.type
- style.default
- style.line_number
- style.bracelight
- style.bracebad
- style.controlchar
- style.indentguide
- style.calltip

@module textredux.core.style
]]

local M = {}

local color = require('textredux.util.color')
local string_to_color = color.string_to_color
local color_to_string = color.color_to_string

local STYLE_LASTPREDEFINED = buffer.STYLE_LASTPREDEFINED
local STYLE_MAX = buffer.STYLE_MAX

---
-- Applies a style.
-- Attached to each style defined in the module.
-- @param self The Style
-- @param start_pos The start position
-- @param length The number of chars to style
local function apply(self, start_pos, length)
  local buf = buffer
  buf:start_styling(start_pos, 0xff)
  buf:set_styling(length, self.number)
end

-- Copy a table.
local function table_copy(tbl)
  local new = {}
  for k, v in pairs(tbl) do
    new[k] = v
  end
  return new
end

-- Overwrite fields in first style table with fields from second style table.
local function style_merge(s1, s2)
  local new = table_copy(s1)
  for k, v in pairs(s2) do
    new[k] = v
  end
  new.number = nil
  return new
end

-- Set a property if it is set.
local function set_style_property(t, number, value)
  if value ~= nil then t[number] = value end
end

-- Normalize a theme color value to the '#rrggbb' form textredux stores.
-- Theme colors may be Scintilla BGR integers or '0xBBGGRR' strings (the latter from color.rgb2bgr);
-- both convert via tonumber + color_to_string.
local function to_hex(color)
  if type(color) == 'number' then return color_to_string(color) end
  local numeric = tonumber(color) -- handles '0xBBGGRR' (and decimal) strings
  return numeric and color_to_string(numeric) or color -- fall back to an existing '#rrggbb'/'rrggbb'
end

-- Resolve a style's fore/back color. An explicit value (set on the style or via a derivation/override) wins;
-- otherwise the color is looked up from the active theme via the style's `_theme` key in `view.styles`.
-- This lookup happens here, at apply time (on buffer events, after the theme is applied), rather than when the module loads
-- under Textadept 13 `view.styles` is not yet populated at module-load time, so resolving eagerly would yield no color.
local function resolve_color(value, side)
  if value[side] then return string_to_color(value[side]) end
  if value._theme and view.styles then
    local style = view.styles[value._theme]
    local color = style and style[side]
    if color then return string_to_color(to_hex(color)) end
  end
end

-- Activate Textredux styles in a buffer.
function M.activate_styles()
  if not buffer._textredux then return end
  for _, v in pairs(M) do
    if type(v) == 'table' then
      if v.number > STYLE_LASTPREDEFINED then
        set_style_property(buffer.style_size, v.number, v.size)
        set_style_property(buffer.style_bold, v.number, v.bold)
        set_style_property(buffer.style_italic, v.number, v.italics)
        set_style_property(buffer.style_underline, v.number, v.underlined)
        set_style_property(buffer.style_fore, v.number, resolve_color(v, 'fore'))
        set_style_property(buffer.style_back, v.number, resolve_color(v, 'back'))
        set_style_property(buffer.style_eol_filled, v.number, v.eolfilled)
        set_style_property(buffer.style_character_set, v.number, v.characterset)
        set_style_property(buffer.style_case, v.number, v.case)
        set_style_property(buffer.style_visible, v.number, v.visible)
        set_style_property(buffer.style_changeable, v.number, v.changeable)
        set_style_property(buffer.style_hot_spot, v.number, v.hotspot)
        set_style_property(buffer.style_font, v.number, v.font)
      end
    end
  end
end

-- Predefined Scintilla styles.
-- These keep their fixed Scintilla style numbers, which the theme colors directly, so applying them as-is works.
-- The number doubles as the `view.styles` lookup key.
local predefined_styles = {
  default = buffer.STYLE_DEFAULT,
  line_number = buffer.STYLE_LINENUMBER,
  bracelight = buffer.STYLE_BRACELIGHT,
  bracebad = buffer.STYLE_BRACEBAD,
  controlchar = buffer.STYLE_CONTROLCHAR,
  indentguide = buffer.STYLE_INDENTGUIDE,
  calltip = buffer.STYLE_CALLTIP,
}

-- Lexer-tag styles. Under Textadept 13 the theme colors these via lexer tag names rather than fixed Scintilla slots,
-- so we assign them fresh style numbers (above STYLE_LASTPREDEFINED) that @{activate_styles} colorizes.
-- This makes both, direct use (`style.number`) and derivations (`style.number .. {...}`) work.
-- They are looked up in `view.styles` by tag name; `preproc` is the only name that differs from its tag.
local tag_styles = {
  'nothing',
  'whitespace',
  'comment',
  'string',
  'number',
  'keyword',
  'identifier',
  'operator',
  'error',
  'preproc',
  'constant',
  'variable',
  'function',
  'class',
  'type',
}
local tag_lookup = { preproc = 'preprocessor' }

-- Read a base style's visual properties eagerly from the active theme.
-- This is a best-effort fast path: under Textadept 13 `view.styles` is usually empty at module-load time,
-- in which case nothing is returned and colors are resolved later by @{resolve_color}.
-- Older Textadept used `style.*` buffer properties, which serve as a fallback.
local function read_base_style(lookup_key, legacy_name)
  if view.styles then
    local style = view.styles[lookup_key]
    if style then
      local props = {}
      if style.fore then props.fore = to_hex(style.fore) end
      if style.back then props.back = to_hex(style.back) end
      if style.font then props.font = style.font end
      if style.size then props.size = tonumber(style.size) end
      if style.bold then props.bold = true end
      if style.italic then props.italics = true end
      if style.underline then props.underlined = true end
      if style.eol_filled then props.eolfilled = true end
      return props
    end
  end
  -- Legacy fallback: parse the `style.<name>` buffer property string.
  local props = {}
  local legacy_style = buffer.property['style.' .. legacy_name]:gsub('[$%%]%b()', function(key)
    return buffer.property[key:sub(3, -2)]
  end)
  local fore = legacy_style:match('fore:(%d+)')
  if fore then props.fore = color_to_string(tonumber(fore)) end
  local back = legacy_style:match('back:(%d+)')
  if back then props.back = color_to_string(tonumber(back)) end
  local font = legacy_style:match('font:([%a ]+)')
  if font then props.font = font end
  local size = legacy_style:match('size:(%d+)')
  if size then props.size = tonumber(size) end
  -- Assuming "notbold" etc. are never used in default styles.
  if legacy_style:match('italics') then props.italics = true end
  if legacy_style:match('bold') then props.bold = true end
  if legacy_style:match('underlined') then props.underlined = true end
  if legacy_style:match('eolfilled') then props.eolfilled = true end
  return props
end

-- Build the predefined base styles (fixed style numbers).
for name, number in pairs(predefined_styles) do
  local style = read_base_style(number, name)
  style.number = number
  style._theme = number
  style.apply = apply
  M[name] = setmetatable(style, { __concat = style_merge })
end

-- Build the lexer-tag base styles (fresh, colorizable style numbers).
local next_number = STYLE_LASTPREDEFINED
for _, name in ipairs(tag_styles) do
  next_number = next_number + 1
  local lookup = tag_lookup[name] or name
  local style = read_base_style(lookup, name)
  style.number = next_number
  style._theme = lookup
  style.apply = apply
  M[name] = setmetatable(style, { __concat = style_merge })
end

-- Defines a new style using the given table of style properties.
-- @param name The style name that should be used for the style
-- @param properties The table describing the style
local function define_style(t, name, properties)
  local new_properties = table_copy(properties)
  -- If this name already maps to a style, reuse its slot number. Allocating a
  -- fresh number would leave the old slot permanently unreferenced (leaked)
  -- and eventually cause collisions with subsequent new style definitions.
  local existing = rawget(t, name)
  if existing and type(existing) == 'table' then
    new_properties.number = existing.number
  else
    local count = 0
    for _, v in pairs(M) do
      if type(v) == 'table' then count = count + 1 end
    end
    local number = STYLE_LASTPREDEFINED + count + 1
    if number > STYLE_MAX then error('Maximum style number exceeded') end
    new_properties.number = number
  end
  new_properties.apply = apply
  rawset(t, name, new_properties)
end

setmetatable(M, { __newindex = define_style })

-- Ensure Textredux styles are defined after switching buffers or views.
events.connect(events.BUFFER_NEW, M.activate_styles)
events.connect(events.BUFFER_AFTER_SWITCH, M.activate_styles)
events.connect(events.VIEW_NEW, M.activate_styles)
events.connect(events.VIEW_AFTER_SWITCH, M.activate_styles)

return M
