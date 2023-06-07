-- title:   TODO
-- author:  Wojciech Graj
-- desc:    TODO
-- site:    TODO
-- license: AGPL-3.0-or-later
-- version: 0.0
-- script:  lua

--[[
   TODO
   Copyright (C) 2023  Wojciech Graj

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU Affero General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU Affero General Public License for more details.

   You should have received a copy of the GNU Affero General Public License
   along with this program.  If not, see <https://www.gnu.org/licenses/>.
--]]

--- Conventions
-- VARIABLE delta: time since last frame (ms)
-- VARIABLE g_*: global variable
-- VARIABLE c_*: constant variable
-- VARIABLE p_*: co-ordinate relative to piece

--- Map usage
-- xE[210,225] yE[0,20]: piece patterns
-- x=209 yE[21,135]: piece row allocation data
-- xE[210,239] yE[21,135]: allocated pieces

gc_directions = {
   {0, -1},  -- Up
   {1, 0},  -- Right
   {0, 1},  -- Down
   {-1, 0},  -- Left
}

----------------------------------------
-- utility functions -------------------
----------------------------------------

--- Remove lines of matching tiles and generate pieces for floating/connected tiles
function resolve_tiles(tiles)
   local table_insert = table.insert
   local phys_tiles = {}
   local c_directions = gc_directions

   for _, tile in ipairs(tiles) do
      tile[3] = mget(tile[1], tile[2])
      if tile[3] ~= 0 then  -- If tile hasn't been resolved
         for i_dir = 1, 2 do
            -- Find sequence length
            local dir = c_directions[i_dir]
            local color_idx = tile[3] // 16
            local seq_start = 0
            while (mget(tile[1] + dir[1] * (seq_start - 1), tile[2] + dir[2] * (seq_start - 1)) // 16 == color_idx) do
               seq_start = seq_start - 1
            end
            local seq_end = 0
            while (mget(tile[1] + dir[1] * (seq_end + 1), tile[2] + dir[2] * (seq_end + 1)) // 16 == color_idx) do
               seq_end = seq_end + 1
            end

            local seq_len = seq_end - seq_start + 1
            if seq_len >= g_min_seq_len then  -- If sequence is long enough
               g_clears = g_clears + 1
               if g_clears % 10 == 0 then
                  g_level = g_level + 1
               end
               g_score = g_score + (g_level + 1) * (seq_len * (seq_len + 1) // 2)
               g_drop_timer_max = calc_drop_timer()

               -- Clear tiles in sequence
               for i = seq_start, seq_end do
                  local x = tile[1] + dir[1] * i
                  local y = tile[2] + dir[2] * i
                  local data = mget(x, y)

                  -- Unlink tiles
                  local p2bit = 1
                  for j = 1, 4 do
                     if data & p2bit ~= 0 then
                        local direction = c_directions[j]
                        local nbor_x = x + direction[1]
                        local nbor_y = y + direction[2]

                        mset(nbor_x, nbor_y, mget(nbor_x, nbor_y) & ((~(2 ^ ((j + 1) % 4))) | 0xF0)) -- TODO
                        table_insert(phys_tiles, {nbor_x, nbor_y})
                     end
                     p2bit = p2bit * 2
                  end

                  table_insert(phys_tiles, {x, y - 1})

                  mset(x, y, 0)
               end
            end
         end
      end
   end

   local math_max = math.max
   local math_min = math.min

   -- Transform potentially-floating tiles into pieces
   for _, tile in ipairs(phys_tiles) do
      local tile_data = mget(tile[1], tile[2])
      if tile_data ~= 0 then  -- If not already converted into piece
         -- Piece extents
         local l = 1e9
         local r = -1e9
         local t = 1e9
         local b = -1e9

         local linked = {{tile[1], tile[2], -1}}

         -- Get all linked tiles constituting the piece
         for _, tl in ipairs(linked) do
            local x = tl[1]
            local y = tl[2]
            local data = mget(x, y)
            tl[4] = data

            local p2bit = 1
            for j = 0, 3 do
               if data & p2bit ~= 0 and j ~= tl[3] then
                  local direction = c_directions[j + 1]
                  local nbor_x = x + direction[1]
                  local nbor_y = y + direction[2]
                  table_insert(linked, {nbor_x, nbor_y, (j + 2) % 4})
               end
               p2bit = p2bit * 2
            end

            l = math_min(l, x)
            r = math_max(r, x)
            b = math_max(b, y)
            t = math_min(t, y)

            mset(x, y, 0)

            table_insert(phys_tiles, {x, y - 1})
         end

         pc = Piece.new(l, t, math_max(r - l , b - t) + 1, 0, 0)
         pc:calloc()

         for _, tl in ipairs(linked) do
            mset(pc.rot_map_x + tl[1] - l, pc.rot_map_y + tl[2] - t, tl[4])
            if tl[y] == t then
               table_insert(phys_tiles, {tl[1], tl[2] - 1})
            end
         end

         table_insert(g_dropping_pieces, pc)
      end
   end

   return next(phys_tiles) ~= nil
end

function next_piece()
   g_piece = g_piece_nxt

   if not g_piece:validate() then
      g_state = 5
   end

   g_piece_nxt = Piece.new_random()

   g_piece_nxt_offset = 0
   for y = 0, g_piece_nxt.size - 1 do
      for x = 0, g_piece_nxt.size - 1 do
         if mget(x + g_piece_nxt.rot_map_x, y + g_piece_nxt.rot_map_y) ~= 0 then
            g_piece_nxt_offset = y
            return
         end
      end
   end
end

function calc_drop_timer()
   local level = g_level
   if level == 0 then
      return 800
   elseif level == 1 then
      return 717
   elseif level == 2 then
      return 633
   elseif level == 3 then
      return 550
   elseif level == 4 then
      return 467
   elseif level == 5 then
      return 383
   elseif level == 6 then
      return 300
   elseif level == 7 then
      return 217
   elseif level == 8 then
      return 133
   elseif level == 9 then
      return 100
   elseif level <= 12 then
      return 83
   elseif level <= 15 then
      return 67
   elseif level <= 18 then
      return 50
   elseif level <= 28 then
      return 33
   else
      return 17
   end
end

----------------------------------------
-- Piece -------------------------------
----------------------------------------

Piece = {
   x = 0,
   y = 0,
   variant = 0,
   size = 0,
   rot_map_x = 0,
   rot_map_y = 0,
}
Piece.__index = Piece

function Piece.new(x, y, size, rot_map_x, rot_map_y)
   local self = setmetatable({}, Piece)
   self.x = x
   self.y = y
   self.size = size
   self.rot_map_x = rot_map_x
   self.rot_map_y = rot_map_y
   return self
end

function Piece.new_from_template(piece)
   local self = setmetatable({}, Piece)
   self.x = piece.x
   self.y = piece.y
   self.size = piece.size

   local math_random = math.random
   local color_map = {}
   for i = 1, 4 do
      color_map[i] = math_random(4) * 16
   end

   self:calloc()
   for y = 0, self.size - 1 do
      for x = 0, self.size * 4 - 1 do
         local tile_data = mget(piece.rot_map_x + x, piece.rot_map_y + y)
         if tile_data ~= 0 then
            mset(self.rot_map_x + x, self.rot_map_y + y, tile_data % 16 + color_map[tile_data // 16])
         end
      end
   end

   return self
end

function Piece.new_random()
   return Piece.new_from_template(gc_pieces[math.random(#gc_pieces)])
end

--- Allocate map space
function Piece:alloc()
   for i = 21, 135 do
      for j = i, i + self.size do
         if mget(209, j) ~= 0 then
            i = j
            goto continue
         end
      end

      for j = i, i + self.size - 1 do
         mset(209, j, 1)
      end

      self.rot_map_x = 210
      self.rot_map_y = i
      do
         return nil
      end

      ::continue::
   end

   trace("Error: OOM")
   exit()
end

--- Allocate map space and clear it
function Piece:calloc()
   self:alloc()

   for y = self.rot_map_y, self.rot_map_y + self.size - 1 do
      for x = self.rot_map_x, self.rot_map_x + self.size * 4 - 1 do
         mset(x, y, 0)
      end
   end
end

--- Free map space
function Piece:free()
   for i = self.rot_map_y, self.rot_map_y + self.size - 1 do
      mset(209, i, 0)
   end
end

function Piece:draw()
   local width = g_width
   local x_start = 120 - width * 4

   map(self.rot_map_x + self.variant * self.size, self.rot_map_y, self.size, self.size, x_start + self.x * 8, self.y * 8, 0)
end

function Piece:can_drop()
   self.y = self.y + 1
   local can_drop = self:validate()
   self.y = self.y - 1
   return can_drop
end

--- Drop a piece without checking validity of destination position
function Piece:drop_unchecked()
   self.y = self.y + 1
end

--- Place a piece and delete it
-- @param new_tiles table: newly placed tiles are appended to this table
function Piece:place(new_tiles)
   local table_insert = table.insert

   for p_y = 0, self.size - 1 do
      for p_x = 0, self.size - 1 do
         local tile_data = mget(self.rot_map_x + self.variant * self.size + p_x, self.rot_map_y + p_y)
         if tile_data ~= 0 then
            local x = self.x + p_x
            local y = self.y + p_y
            table_insert(new_tiles, {x, y})
            mset(x, y, tile_data)
         end
      end
   end

   self:free()
end

function Piece:validate()
   for y = 0, self.size - 1 do
      for x = 0, self.size - 1 do
         if mget(x + self.rot_map_x + self.variant * self.size, y + self.rot_map_y) ~= 0
            and (mget(self.x + x, self.y + y) ~= 0
               or self.x + x < 0
               or self.x + x >= 10
               or self.y + y >= 17
         ) then
            return false
         end
      end
   end

   return true
end

function Piece:rotate_cw()
   self.variant = (self.variant + 1) % 4
   if not self:validate() then
      self.variant = (self.variant + 3) % 4
   end
end

function Piece:rotate_ccw()
   self.variant = (self.variant + 3) % 4
   if not self:validate() then
      self.variant = (self.variant + 1) % 4
   end
end

function Piece:move_left()
   self.x = self.x - 1
   if not self:validate() then
      self.x = self.x + 1
   end
end

function Piece:move_right()
   self.x = self.x + 1
   if not self:validate() then
      self.x = self.x - 1
   end
end

gc_pieces = {
   Piece.new(3, -2, 4, 210, 0, 2),  -- I
   Piece.new(4, 0, 2, 210, 4, 1),  -- O
   Piece.new(4, -1, 3, 210, 6, 4),  -- J
   Piece.new(4, -1, 3, 210, 9, 4),  -- L
   Piece.new(4, -1, 3, 210, 12, 2),  -- S
   Piece.new(4, -1, 3, 210, 15, 4),  -- T
   Piece.new(4, -1, 3, 210, 18, 2),  -- Z
}

----------------------------------------
-- Input -------------------------------
----------------------------------------

--- action_idx:
-- 1: move R
-- 2: rotate CW

Input = {
   action_idx = 0,
   dir = 0,
   btn = 0,
   btn_reverse = 0,
   cnt = 0,
   stage_rem_t = 0,
}
Input.__index = Input

function Input.new(action_idx)
   local self = setmetatable({}, Input)
   self.action_idx = action_idx
   if self.action_idx == 1 then
      self.btn = 3
      self.btn_reverse = 2
   else  -- if self.action_idx == 2 then
      self.btn = 5
      self.btn_reverse = 4
   end
   return self
end

function Input:process(delta)
   local dir = (btn(self.btn) and 1 or 0) - (btn(self.btn_reverse) and 1 or 0)
   if dir == 0 then
      self.stage_rem_t = 0
      self.cnt = 0
   elseif dir == self.dir then
      self.stage_rem_t = self.stage_rem_t - delta
   else
      self.stage_rem_t = -1
      self.cnt = 0
      self.dir = dir
   end

   if self.stage_rem_t < 0 then
      if self.cnt == 0 then
         self.stage_rem_t = 267
      else
         self.stage_rem_t = 133
      end
      self.cnt = self.cnt + 1

      if self.action_idx == 1 then
         if dir == 1 then
            g_piece:move_right()
         else
            g_piece:move_left()
         end
      else  -- if self.action_idx == 2 then
         if dir == 1 then
            g_piece:rotate_cw()
         else
            g_piece:rotate_ccw()
         end
      end
   end
end

----------------------------------------
-- Option ------------------------------
----------------------------------------

Option = {
   name = nil,
   idx = 0,
   vals = nil,
}
Option.__index = Option

function Option.new(name, vals, idx)
   local self = setmetatable({}, Option)
   self.name = name
   self.vals = vals
   self.idx = idx
   return self
end

function Option:draw(y, active)
   print(self.name, 16, y, 15, true)

   local width = print(self.vals[self.idx], 192, y, 15, true)

   if active then
      spr(2, 184, y)
      spr(3, 192 + width, y)
   end
end

function Option:change(dir)
   self.idx = (self.idx - 1 + dir) % #(self.vals) + 1
end

----------------------------------------
-- Option ------------------------------
----------------------------------------

Start = {
}
Start.__index = Start

function Start.new()
   local self = setmetatable({}, Start)
   return self
end

function Start:draw(y, active)
   local width = print("START", 16, y, 15, true)

   if active then
      spr(3, 8, y)
      spr(2, 16 + width, y)
   end
end

function Start:change(dir)
   g_state = 4
   g_init()
end

----------------------------------------
-- main --------------------------------
----------------------------------------

--- g_state:
-- 1: title screen
-- 2: highscores
-- 3: options
-- 4: game
-- 5: end screen

function g_init()
   -- Clear board
   for y = 0, g_height do
      for x = 0, g_width do
         mset(x, y, 0)
      end
   end

   g_dropping_pieces = {}
   g_piece_nxt = Piece.new_random()
   next_piece()
   g_drop_timer = 0
   g_clears = 0
   g_level = g_options[2].vals[g_options[2].idx]
   g_drop_timer_max = calc_drop_timer()
   g_score = 0
   g_min_seq_len = g_options[1].vals[g_options[1].idx]

   g_inputs = {
      Input.new(1),
      Input.new(2),
   }
end

function BOOT()
   g_prev_time = 0
   g_state = 3
   g_width = 10
   g_height = 17

   g_options = {
      Option.new("LINE LENGTH", {2, 3, 4, 5}, 2),
      Option.new("LEVEL", {0, 1, 2, 3, 4, 5, 6, 7, 8, 9}, 1),
      Option.new("MUSIC", {"1", "2", "3", "OFF"}, 1),
      Start.new(),
   }
   g_active_opt_idx = 1

   g_init()
end

function game_process(delta)
   local width = g_width
   local height = g_height

   local x_start = 120 - width * 4

   map(0, 0, width, height, x_start, 0)
   map(239, 0, 1, 17, x_start - 8, 0)
   map(239, 0, 1, 17, x_start + width * 8, 0)

   local string_format = string.format

   print("NEXT", 176, 8, 15, true)
   local piece = g_piece_nxt
   map(piece.rot_map_x + piece.variant * piece.size, piece.rot_map_y, piece.size, piece.size, 176, 16 - g_piece_nxt_offset * 8, 0)

   print(string.format("LEVEL\n  %02d", g_level), 176, 40, 15, true)

   print(string.format("CLEARS\n  %03d", g_clears), 176, 64, 15, true)

   print(string.format("SCORE\n%09d", g_score), 176, 92, 15, true)

   g_drop_timer = g_drop_timer + delta

   if next(g_dropping_pieces) ~= nil then
      if g_drop_timer >= g_drop_timer_max then
         g_drop_timer = 0

         local table_insert = table.insert
         repeat
            local new_tiles = {}
            repeat
               local placed = false
               local g_dropping_pieces_old = g_dropping_pieces
               g_dropping_pieces = {}
               for k, pc in ipairs(g_dropping_pieces_old) do
                  if pc:can_drop() then
                     table_insert(g_dropping_pieces, pc)
                  else
                     placed = true
                     pc:place(new_tiles)
                  end
               end
            until not placed
         until not resolve_tiles(new_tiles)

         for k, pc in pairs(g_dropping_pieces) do
            pc:drop_unchecked()
         end
      end
   else
      if btn(1) then
         g_drop_timer = g_drop_timer + delta
      end

      for _, inp in ipairs(g_inputs) do
         inp:process(delta)
      end

      if g_drop_timer >= g_drop_timer_max then
         g_drop_timer = 0
         if g_piece:can_drop() then
            g_piece:drop_unchecked()
         else
            local new_tiles = {}
            g_piece:place(new_tiles)
            resolve_tiles(new_tiles)
            next_piece()
         end
      end

      g_piece:draw()
   end

   for k, pc in pairs(g_dropping_pieces) do
      pc:draw()
   end
end

function options_process(delta)
   if btnp(0) then
      g_active_opt_idx = (g_active_opt_idx + #g_options - 2) % #g_options + 1
   end
   if btnp(1) then
      g_active_opt_idx = (g_active_opt_idx) % #g_options + 1
   end
   if btnp(2) then
      g_options[g_active_opt_idx]:change(-1)
   end
   if btnp(3) then
      g_options[g_active_opt_idx]:change(1)
   end

   local y = 48
   for i, opt in ipairs(g_options) do
      opt:draw(y, i == g_active_opt_idx)
      y = y + 16
   end
end

function end_screen_process(delta)
   g_state = 3
end

gc_processes = {
   [3] = options_process,
   [4] = game_process,
   [5] = end_screen_process,
}

function TIC()
   local t = time()
   g_t = t
   local delta = t - g_prev_time
   g_prev_time = t

   cls()

   gc_processes[g_state](delta)
end

-- <TILES>
-- 001:00000000ff0fffffff0fffffff0fffff00000000ffff0fffffff0fffffff0fff
-- 002:0000000f000000ff00000fff000000ff0000000f000000000000000000000000
-- 003:f0000000ff000000fff00000ff000000f0000000000000000000000000000000
-- 016:0000000000222000024222002422222024222220222222200222220000222000
-- 017:0000000022222220242222202422222024222220222222200222220000222000
-- 018:0000000000222220024444202422222022222220222222200222222000222220
-- 019:0000000022222220244444202222222022222220222222200222222000222220
-- 020:0000000000222000024222002422222024222220242222202422222022222220
-- 021:0000000022222220242222200242220002422200024222002422222022222220
-- 022:0000000000222220024444202422222024222220242222202422222022222220
-- 023:0000000022222220242222200242222002422220024222202422222022222220
-- 024:0000000022222000244442002222222022222220222222202222220022222000
-- 025:0000000022222220244444202222222022222220222222202222220022222000
-- 026:0000000022000220242224202244422022222220222222202222222022000220
-- 027:0000000022222220222222202222222022222220224442202422242022000220
-- 028:0000000022222000244422002222222022222220222222202222222022222220
-- 029:0000000022222220222224202222420022224200222242002222242022222220
-- 030:0000000022000220242224202244422022222220222222202222222022222220
-- 031:0000000022222220222222202222222022222220222222202222222022222220
-- 032:0000000000999000024999009499999094999990999999900999990000999000
-- 033:0000000099999990949999909499999094999990999999900999990000999000
-- 034:0000000000999990024444909499999099999990999999900999999000999990
-- 035:0000000099999990944444909999999099999990999999900999999000999990
-- 036:0000000000999000024999009499999094999990949999909499999099999990
-- 037:0000000099999990949999900249990002499900024999009499999099999990
-- 038:0000000000999990024444909499999094999990949999909499999099999990
-- 039:0000000099999990949999900249999002499990024999909499999099999990
-- 040:0000000099999000944449009999999099999990999999909999990099999000
-- 041:0000000099999990944444909999999099999990999999909999990099999000
-- 042:0000000099000990942224909944499099999990999999909999999099000990
-- 043:0000000099999990999999909999999099999990994449909422249099000990
-- 044:0000000099999000944499009999999099999990999999909999999099999990
-- 045:0000000099999990999994909999420099994200999942009999949099999990
-- 046:0000000099000990942224909944499099999990999999909999999099999990
-- 047:0000000099999990999999909999999099999990999999909999999099999990
-- 048:0000000000eee000024eee00e4eeeee0e4eeeee0eeeeeee00eeeee0000eee000
-- 049:00000000eeeeeee0e4eeeee0e4eeeee0e4eeeee0eeeeeee00eeeee0000eee000
-- 050:0000000000eeeee0024444e0e4eeeee0eeeeeee0eeeeeee00eeeeee000eeeee0
-- 051:00000000eeeeeee0e44444e0eeeeeee0eeeeeee0eeeeeee00eeeeee000eeeee0
-- 052:0000000000eee000024eee00e4eeeee0e4eeeee0e4eeeee0e4eeeee0eeeeeee0
-- 053:00000000eeeeeee0e4eeeee0024eee00024eee00024eee00e4eeeee0eeeeeee0
-- 054:0000000000eeeee0024444e0e4eeeee0e4eeeee0e4eeeee0e4eeeee0eeeeeee0
-- 055:00000000eeeeeee0e4eeeee0024eeee0024eeee0024eeee0e4eeeee0eeeeeee0
-- 056:00000000eeeee000e4444e00eeeeeee0eeeeeee0eeeeeee0eeeeee00eeeee000
-- 057:00000000eeeeeee0e44444e0eeeeeee0eeeeeee0eeeeeee0eeeeee00eeeee000
-- 058:00000000ee000ee0e42224e0ee444ee0eeeeeee0eeeeeee0eeeeeee0ee000ee0
-- 059:00000000eeeeeee0eeeeeee0eeeeeee0eeeeeee0ee444ee0e42224e0ee000ee0
-- 060:00000000eeeee000e444ee00eeeeeee0eeeeeee0eeeeeee0eeeeeee0eeeeeee0
-- 061:00000000eeeeeee0eeeee4e0eeee4200eeee4200eeee4200eeeee4e0eeeeeee0
-- 062:00000000ee000ee0e42224e0ee444ee0eeeeeee0eeeeeee0eeeeeee0eeeeeee0
-- 063:00000000eeeeeee0eeeeeee0eeeeeee0eeeeeee0eeeeeee0eeeeeee0eeeeeee0
-- 064:0000000000666000024666006466666064666660666666600666660000666000
-- 065:0000000066666660646666606466666064666660666666600666660000666000
-- 066:0000000000666660024444606466666066666660666666600666666000666660
-- 067:0000000066666660644444606666666066666660666666600666666000666660
-- 068:0000000000666000024666006466666064666660646666606466666066666660
-- 069:0000000066666660646666600246660002466600024666006466666066666660
-- 070:0000000000666660024444606466666064666660646666606466666066666660
-- 071:0000000066666660646666600246666002466660024666606466666066666660
-- 072:0000000066666000644446006666666066666660666666606666660066666000
-- 073:0000000066666660644444606666666066666660666666606666660066666000
-- 074:0000000066000660642224606644466066666660666666606666666066000660
-- 075:0000000066666660666666606666666066666660664446606422246066000660
-- 076:0000000066666000644466006666666066666660666666606666666066666660
-- 077:0000000066666660666664606666420066664200666642006666646066666660
-- 078:0000000066000660642224606644466066666660666666606666666066666660
-- 079:0000000066666660666666606666666066666660666666606666666066666660
-- </TILES>

-- <MAP>
-- 000:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000410000000000000044000000000000000000000000000010
-- 001:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000520000000000000053000000000000000000000000000010
-- 002:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000021a2a3840000530024a3a281000052000000000000000000000000000010
-- 003:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000140000000000000011000000000000000000000000000010
-- 004:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000061c263c164c362c400000000000000000000000000000000000000000010
-- 005:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000339434923291319300000000000000000000000000000000000000000010
-- 006:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004100440000006384000000000000000000000000000000000010
-- 007:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000021a2c300520033a281005200000000000000000000000000000000000010
-- 008:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014249300000000001100000000000000000000000000000000000010
-- 009:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000021c200000041004400000000000000000000000000000000000010
-- 010:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000062a38400530024a392005300000000000000000000000000000000000010
-- 011:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000110000001400000000003281000000000000000000000000000000000010
-- 012:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004300000000004200000000000000000000000000000000000010
-- 013:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000061820034c10064830031c4000000000000000000000000000000000010
-- 014:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000239400000012229100000013000000000000000000000000000000000010
-- 015:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004100004400004300000000000000000000000000000000000010
-- 016:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000021e28324d20023b281007284000000000000000000000000000000000010
-- 017:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001400001300000000001100000000000000000000000000000000000000
-- 018:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000041000000000044000000000000000000000000000000000000
-- 019:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000021c20000639224c300006293000000000000000000000000000000000000
-- 020:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003384001400003281001100000000000000000000000000000000000000
-- </MAP>

-- <WAVES>
-- 000:00000000ffffffff00000000ffffffff
-- 001:0123456789abcdeffedcba9876543210
-- 002:0123456789abcdef0123456789abcdef
-- </WAVES>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>
