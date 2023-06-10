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
   {x = 0, y = -1},  -- Up
   {x = 1, y = 0},  -- Right
   {x = 0, y = 1},  -- Down
   {x = -1, y = 0},  -- Left
}

gc_colors = {
   3,
   9,
   14,
   6,
   1
}

----------------------------------------
-- utility functions -------------------
----------------------------------------

function set_state(state)
   g_state = state

   if state == 1 then
      g_colors = 5
      g_drop_timer = 0
      g_dropping_pieces = {}
   elseif state == 3 then
      g_active_opt_idx = 1
   elseif state == 4 then
      for y = 0, 16 do
         for x = 0, 9 do
            mset(x, y, 0)
         end
      end

      g_min_seq_len = g_options[1]:get()
      g_colors = g_options[2]:get()
      g_level = g_options[3]:get()

      g_stats_pcs = Stats.new(7, 24, 112, 88, {12, 12, 12, 12, 12, 12, 12})
      g_stats_color = Stats.new(g_colors, 45, 112, 88, gc_colors)

      g_dropping_pieces = {}
      g_piece_nxt = Piece.new_random()
      next_piece()
      g_drop_timer = 0
      g_clears = 0
      g_drop_timer_max = calc_drop_timer()
      g_score = 0

      local mus = g_options[4]:get()
      if mus ~= "OFF" then
         if mus == "KOROBEINIKI" then
            sync(16, 0)
         elseif mus == "TROIKA" then
            sync(16, 1)
         end
         music(0, 0, 0, true, true)
      end

      g_inputs = {
         Input.new(1),
         Input.new(2),
      }
   elseif state == 5 then
      music()
   end
end

function draw_game()
   poke(0x03FF8, 8)  -- Set border color
   map(0, 0, 10, 17, 80, 0)  -- Draw board

   -- Draw left pane
   map(230, 0, 10, 17)
   map(225, 11 + g_colors, 5, 1, 24, 112)
   print("STATS", 24, 16, 15, true)
   g_stats_color:draw()
   g_stats_pcs:draw()

   -- Draw right pane
   local string_format = string.format
   map(230, 0, 10, 17, 160, 0)
   print("NEXT", 188, 16, 15, true)
   local piece_nxt = g_piece_nxt
   map(piece_nxt.rot_map_x + piece_nxt.variant * piece_nxt.size, piece_nxt.rot_map_y, piece_nxt.size, piece_nxt.size, 200 - piece_nxt.size * 4, 24 - g_piece_nxt_offset * 8, 0)
   print(string.format("LEVEL\n  %02d", g_level), 180, 48, 15, true)
   print(string.format("CLEARS\n  %03d", g_clears), 180, 72, 15, true)
   print(string.format("SCORE\n%07d", g_score), 180, 100, 15, true)
end

--- Remove lines of matching tiles and generate pieces for floating/connected tiles
function resolve_tiles(tiles)
   local table_insert = table.insert
   local phys_tiles = {}
   local c_directions = gc_directions

   for _, tile in ipairs(tiles) do
      local tile_data = mget(tile.x, tile.y)
      if tile_data ~= 0 then  -- If tile hasn't been resolved
         local color_idx = tile_data // 16
         for i_dir = 1, 2 do
            -- Find sequence length
            local dir = c_directions[i_dir]
            local seq_start = 0
            while (mget(tile.x + dir.x * (seq_start - 1), tile.y + dir.y * (seq_start - 1)) // 16 == color_idx) do
               seq_start = seq_start - 1
            end
            local seq_end = 0
            while (mget(tile.x + dir.x * (seq_end + 1), tile.y + dir.y * (seq_end + 1)) // 16 == color_idx) do
               seq_end = seq_end + 1
            end
            local seq_len = seq_end - seq_start + 1

            if seq_len >= g_min_seq_len then
               g_clears = g_clears + 1
               if g_clears % 10 == 0 then
                  g_level = g_level + 1
               end
               g_score = g_score + (g_level + 1) * (seq_len * (seq_len + 1) // 2) * (g_colors - 2)
               g_drop_timer_max = calc_drop_timer()

               -- Clear tiles in sequence
               for i = seq_start, seq_end do
                  local x = tile.x + dir.x * i
                  local y = tile.y + dir.y * i
                  local tile_data_seq = mget(x, y)

                  -- Unlink tiles
                  local p2bit = 1
                  for j = 1, 4 do
                     if tile_data_seq & p2bit ~= 0 then
                        local direction = c_directions[j]
                        local nbor_x = x + direction.x
                        local nbor_y = y + direction.y

                        mset(nbor_x, nbor_y, mget(nbor_x, nbor_y) & ((~(2 ^ ((j + 1) % 4))) | 0xF0))
                        table_insert(phys_tiles, {x = nbor_x, y = nbor_y})
                     end
                     p2bit = p2bit * 2
                  end

                  table_insert(phys_tiles, {x = x, y = y - 1})

                  mset(x, y, 0)
               end
            end
         end
      end
   end

   if next(phys_tiles) == nil then
      return false
   end

   local math_max = math.max
   local math_min = math.min

   -- Transform potentially-floating tiles into pieces
   local phys_tile_idx = 1
   while phys_tile_idx <= #phys_tiles do
      local tile = phys_tiles[phys_tile_idx]
      local tile_data = mget(tile.x, tile.y)
      if tile_data ~= 0 then  -- If not already converted into piece
         -- Piece extents
         local l = 1e9
         local r = -1e9
         local t = 1e9
         local b = -1e9

         local linked = {{x = tile.x, y = tile.y}}

         -- Get all linked tiles constituting the piece
         local linked_idx = 1
         while linked_idx <= #linked do
            local tile_linked = linked[linked_idx]
            local x = tile_linked.x
            local y = tile_linked.y
            tile_linked.data = mget(x, y)

            local p2bit = 1
            for j = 1, 4 do
               if tile_linked.data & p2bit ~= 0 then
                  local direction = c_directions[j]
                  local nbor_x = x + direction.x
                  local nbor_y = y + direction.y

                  -- Check for duplicates in case of loop
                  for i = 1, #linked do
                     local t = linked[i]
                     if t.y == nbor_y and t.x == nbor_x then
                        goto continue
                     end
                  end
                  table_insert(linked, {x = nbor_x, y = nbor_y})
                  ::continue::
               end
               p2bit = p2bit * 2
            end

            l = math_min(l, x)
            r = math_max(r, x)
            b = math_max(b, y)
            t = math_min(t, y)

            mset(x, y, 0)

            table_insert(phys_tiles, {x = x, y = y - 1})

            linked_idx = linked_idx + 1
         end

         pc = Piece.new(l, t, math_max(r - l, b - t) + 1, 0, 0)
         pc:calloc()

         for _, tile_linked in ipairs(linked) do
            mset(pc.rot_map_x + tile_linked.x - l, pc.rot_map_y + tile_linked.y - t, tile_linked.data)
         end

         table_insert(g_dropping_pieces, pc)
      end
      phys_tile_idx = phys_tile_idx + 1
   end

   return true
end

--- Get new piece after placing current one
function next_piece()
   local piece = g_piece_nxt
   g_piece = piece

   if not piece:validate() then
      piece:free()
      set_state(2)
   end

   local piece_nxt = Piece.new_random()
   g_piece_nxt = piece_nxt

   g_piece_nxt_offset = 0
   for y = 0, piece_nxt.size - 1 do
      for x = 0, piece_nxt.size - 1 do
         if mget(x + piece_nxt.rot_map_x, y + piece_nxt.rot_map_y) ~= 0 then
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
   local stats_color = g_stats_color
   local colors = g_colors
   local color_map = {}
   for i = 1, 4 do
      local color_idx = math_random(colors)
      color_map[i] = color_idx * 16
      if stats_color ~= nil then
         stats_color:inc(color_idx)
      end
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
   local idx = math.random(#gc_pieces)
   local stats_pcs = g_stats_pcs
   if stats_pcs ~= nil then
      stats_pcs:inc(idx)
   end
   return Piece.new_from_template(gc_pieces[idx])
end

--- Allocate map space
function Piece:alloc()
   for i = 21, 135 do
      -- Find consecutive empty rows
      for j = i, i + self.size - 1 do
         if mget(209, j) ~= 0 then
            i = j
            goto continue
         end
      end

      -- Claim rows
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
   map(self.rot_map_x + self.variant * self.size, self.rot_map_y, self.size, self.size, 80 + self.x * 8, self.y * 8, 0)
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
            table_insert(new_tiles, {x = x, y = y})
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
   local variant = self.variant
   self.variant = (self.variant + 1) % 4
   if not self:validate() then
      self.variant = variant
   end
end

function Piece:rotate_ccw()
   local variant = self.variant
   self.variant = (self.variant + 3) % 4
   if not self:validate() then
      self.variant = variant
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
   Piece.new(4, -1, 3, 210, 15, 4),  -- T
   Piece.new(4, 0, 2, 210, 4, 1),  -- O
   Piece.new(4, -1, 3, 210, 6, 4),  -- J
   Piece.new(4, -1, 3, 210, 9, 4),  -- L
   Piece.new(4, -1, 3, 210, 12, 2),  -- S
   Piece.new(4, -1, 3, 210, 18, 2),  -- Z
}

----------------------------------------
-- Input -------------------------------
----------------------------------------

--- action_idx:
-- 1: move R
-- 2: rotate CW

--- Input handler with DAS
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
   print(self.name, 24, y, 15, true)

   local width = print(self.vals[self.idx], 144, y, 15, true)

   if active then
      spr(2, 135, y)
      spr(3, 144 + width, y)
   end
end

function Option:change(dir)
   self.idx = (self.idx - 1 + dir) % #(self.vals) + 1
end

function Option:get()
   return self.vals[self.idx]
end

----------------------------------------
-- Start -------------------------------
----------------------------------------

Start = {
}
Start.__index = Start

function Start.new()
   local self = setmetatable({}, Start)
   return self
end

function Start:draw(y, active)
   local width = print("START", 24, y, 15, true)

   if active then
      spr(3, 15, y)
      spr(2, 24 + width, y)
   end
end

function Start:change(dir)
   set_state(4)
end

----------------------------------------
-- Stats -------------------------------
----------------------------------------

Stats = {
   vals = nil,
   max = 0,
   x = 0,
   y = 0,
   height = 0,
}
Stats.__index = Stats

function Stats.new(n, x, y, height, colors)
   local self = setmetatable({}, Stats)
   self.vals = {}
   self.colors = colors
   for i = 1, n do
      self.vals[i] = 0
   end
   self.x = x - 3
   self.y = y
   self.height = height
   return self
end

function Stats:draw()
   local sf = self.height / self.max
   for i, v in ipairs(self.vals) do
      rect(self.x + i * 3, self.y - v * sf // 1, 2, v * sf // 1, self.colors[i])
   end
end

function Stats:inc(idx)
   local v = self.vals[idx] + 1
   self.vals[idx] = v
   self.max = math.max(self.max, v)
end

----------------------------------------
-- process -----------------------------
----------------------------------------

function curtain_process(delta)
   draw_game()

   local drop_timer = g_drop_timer + delta
   g_drop_timer = drop_timer

   if drop_timer > 2000 then
      set_state(1)
      return
   end

   local colors = gc_colors
   for y = 0, drop_timer * 34 // 2000 do
      rect(80, y * 4, 80, 4, colors[y % #colors])
   end
end

function game_process(delta)
   local drop_timer = g_drop_timer + delta
   g_drop_timer = drop_timer

   if next(g_dropping_pieces) ~= nil then
      if drop_timer >= g_drop_timer_max // 2 then
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

      draw_game()
   else
      if g_piece == nil then
         next_piece()
      end

      if btn(1) then
         drop_timer = drop_timer + delta
         g_drop_timer = drop_timer
      end

      for _, inp in ipairs(g_inputs) do
         inp:process(delta)
      end

      if drop_timer >= g_drop_timer_max then
         g_drop_timer = 0
         if g_piece:can_drop() then
            g_piece:drop_unchecked()
         else
            local new_tiles = {}
            g_piece:place(new_tiles)
            resolve_tiles(new_tiles)
            g_piece = nil
         end
      end

      draw_game()


      if g_piece ~= nil then
         g_piece:draw()
      end
   end

   for k, pc in pairs(g_dropping_pieces) do
      pc:draw()
   end
end

function options_process(delta)
   map(180, 0)

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

   local y = 32
   for i, opt in ipairs(g_options) do
      opt:draw(y, i == g_active_opt_idx)
      y = y + 16
   end
end

function end_screen_process(delta)
   set_state(1)
end

function title_process(delta)
   local dropping_pieces_old = g_dropping_pieces

   local table_insert = table.insert
   if math.random() < .15 then
      local math_random = math.random
      local pc = Piece.new_random()
      pc.variant = math_random(1, 3)
      pc.x = math_random(-8, 18 - pc.size)
      table_insert(dropping_pieces_old, pc)
   end

   for _, pc in ipairs(dropping_pieces_old) do
      pc:draw()
   end

   g_drop_timer = g_drop_timer + delta
   if g_drop_timer >= 50 then
      g_drop_timer = 0
      local dropping_pieces = {}
      g_dropping_pieces = dropping_pieces
      for _, pc in ipairs(dropping_pieces_old) do
         pc:drop_unchecked()
         if pc.y > 16 then
            pc:free()
         else
            table_insert(dropping_pieces, pc)
         end
      end
   end

   map(180, 0, 30, 17, 0, 0, 0)
   map(150, 0, 23, 6, 28, 16, 0)
   if (g_t // 500) % 2 == 0 then
      print("PRESS ANY BUTTON TO BEGIN", 52, 96, 2)
   end
   print("(c) Wojciech Graj 2023", 62, 112, 4)

   if btn() ~= 0 then
      for _, pc in ipairs(g_dropping_pieces) do
         pc:free()
      end
      set_state(3)
   end
end

gc_processes = {
   [1] = title_process,
   [2] = curtain_process,
   [3] = options_process,
   [4] = game_process,
   [5] = end_screen_process,
}

----------------------------------------
-- main --------------------------------
----------------------------------------

function BOOT()
   set_state(1)

   g_prev_time = 0

   g_options = {
      Option.new("LINE LENGTH", {2, 3, 4, 5}, 2),
      Option.new("COLORS", {3, 4, 5}, 2),
      Option.new("LEVEL", {0, 1, 2, 3, 4, 5, 6, 7, 8, 9}, 3),
      Option.new("MUSIC", {"KOROBEINIKI", "TROIKA", "OFF"}, 1),
      Start.new(),
   }
end

function TIC()
   local t = time()
   g_t = t
   local delta = t - g_prev_time
   g_prev_time = t

   cls()

   gc_processes[g_state](delta)
end

-- <TILES>
-- 001:2222222222222222222222222222222222222222222222222222222222222222
-- 002:0000000f000000ff00000fff000000ff0000000f000000000000000000000000
-- 003:f0000000ff000000fff00000ff000000f0000000000000000000000000000000
-- 016:0000000000333000024333003433333034333330333333300333330000333000
-- 017:0000000033333330343333303433333034333330333333300333330000333000
-- 018:0000000000333330024444303433333033333330333333300333333000333330
-- 019:0000000033333330344444303333333033333330333333300333333000333330
-- 020:0000000000333000024333003433333034333330343333303433333033333330
-- 021:0000000033333330343333300243330002433300024333003433333033333330
-- 022:0000000000333330024444303433333034333330343333303433333033333330
-- 023:0000000033333330343333300243333002433330024333303433333033333330
-- 024:0000000033333000344443003333333033333330333333303333330033333000
-- 025:0000000033333330344444303333333033333330333333303333330033333000
-- 026:0000000033000330342224303344433033333330333333303333333033000330
-- 027:0000000033333330333333303333333033333330334443303422243033000330
-- 028:0000000033333000344433003333333033333330333333303333333033333330
-- 029:0000000033333330333334303333420033334200333342003333343033333330
-- 030:0000000033000330342224303344433033333330333333303333333033333330
-- 031:0000000033333330333333303333333033333330333333303333333033333330
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
-- 080:0000000000111000024111001411111014111110111111100111110000111000
-- 081:0000000011111110141111101411111014111110111111100111110000111000
-- 082:0000000000111110024444101411111011111110111111100111111000111110
-- 083:0000000011111110144444101111111011111110111111100111111000111110
-- 084:0000000000111000024111001411111014111110141111101411111011111110
-- 085:0000000011111110141111100241110002411100024111001411111011111110
-- 086:0000000000111110024444101411111014111110141111101411111011111110
-- 087:0000000011111110141111100241111002411110024111101411111011111110
-- 088:0000000011111000144441001111111011111110111111101111110011111000
-- 089:0000000011111110144444101111111011111110111111101111110011111000
-- 090:0000000011000110142224101144411011111110111111101111111011000110
-- 091:0000000011111110111111101111111011111110114441101422241011000110
-- 092:0000000011111000144411001111111011111110111111101111111011111110
-- 093:0000000011111110111114101111420011114200111142001111141011111110
-- 094:0000000011000110142224101144411011111110111111101111111011111110
-- 095:0000000011111110111111101111111011111110111111101111111011111110
-- 097:cccccccccccccccccccccccccccccccc0ccccc00cccccc0cccccc00cccccc00c
-- 098:ccc00000cccc0000ccccc000ccccc000ccccc000ccccc000cccc00cccccc00cc
-- 099:000000000000000000000000000000000000000000000000ccccccc0cccccccc
-- 101:00000000000000000000000000000000000000000000000000000000c0000000
-- 102:00cccccc00cccccc00cccccc00cccccc000000cc00000ccc00000ccc00000ccc
-- 103:ccccccccccccccc0ccccccc0ccccccc0ccc00000ccc00000cc000000cc000000
-- 104:000000000000000000000000000000000000000000000000000ccccc0ccccccc
-- 105:000000000000000000000000000000000000000000000000cc0000ccccc000cc
-- 106:000000000000000000000000000000000cccc000ccccc000cccccccccccccccc
-- 107:000000000000000000000000000000000000000000000000cc0000cccc0000cc
-- 108:000000000000000000000000000000000000000000000000ccccccc0cccccccc
-- 109:00000000000000000000000000000000000000000000000000000000000000cc
-- 110:000000000000000000000000000000000000000000000000cccccc00ccccccc0
-- 111:000000000000000000000000000000000000000000000000000cccc0000ccccc
-- 112:00000000000000000000000c0000000c0000000c0000000c0000000c000000cc
-- 113:ccccc00cccccc00cccccc0cccccc00cccccc00cccccc00cccccc00cccccc0ccc
-- 114:cccc00cccccc00cccccc0cccccc00cccccc00cccccc00cccccc00cccccc0cccc
-- 115:cccccccccccccccccc00ccccc000ccccc000ccccc000ccccc000ccccc00ccccc
-- 116:c0000000c0000000c00000000000000000000000000000000000000000000000
-- 117:cc000000cc000000cc000000c0000000c0000000c0000000c0000000c0000000
-- 118:00000ccc00000ccc0000cccc0000cccc0000cccc0000cccc0000cccc000ccccc
-- 119:cc000000cc000000cc00000cc000000cc000000cc000000cc000000cc00000cc
-- 120:cccccccccccccccccccc000cccc0000cccc0000cccc0000cccc0000cccc000cc
-- 121:cccc00cccccc00cccccc000cccc0000cccc0000cccc0000cccc0000cccc000cc
-- 122:cccccccccccccccccccc0000ccc00000ccc00000ccc00000ccc00000ccc00000
-- 123:cc0000cccc0000cc00000ccc00000ccc00000ccc00000ccc00000ccc0000cccc
-- 124:cccccccccccccccccc00ccccc000ccccc000ccccc000ccccc000ccccc00ccccc
-- 125:c0000cccc0000cccc000cccc0000cccc0000cccc0000cccc0000cccc000ccccc
-- 126:ccccccccccccccccc00ccccc000cccc0000cccc0000cccc0000cccc000ccccc0
-- 127:000ccccc000ccccc00ccccc000cccc0000cccc0000cccc0000cccc000ccccc00
-- 128:000000cc000000cc000000cc000000cc00000ccc00000ccc00000ccc00000ccc
-- 129:ccc00cccccc00cccccc00cccccc00cccccc0cccccc00cccccc00cccccc00cccc
-- 130:cc00cccccc00cccccc00cccccc00cccccc0cccccc00cccc0c00cccc0c00cccc0
-- 131:00cccc0000cccc0000cccc000ccccc000cccc0000cccc0000cccc0000cccc000
-- 132:0cccc0000cccc0000cccc000ccccc000cccc0000cccc0000cccc0000cccc0000
-- 134:000ccccc000ccccc000ccccc000ccccc00cccccc00ccccc000ccccc000ccccc0
-- 135:000000cc000000cc000000cc000000cc00000ccc00000ccc00000ccc00000ccc
-- 136:cc0000cccc0000cccc0000cccc0000cccccccccccccccccccccccccccccccccc
-- 137:cc0000cccc0000cccc0000cccc0000cccc000cccc0000cccc0000cccc0000ccc
-- 138:cc000000cc000000cc000000cc000000cc000000c0000000c0000000c0000000
-- 139:0000cccc0000cccc0000cccc0000cccc000ccccc000cccc0000cccc0000cccc0
-- 141:000cccc0000cccc0000cccc0000cccc000ccccc000cccc0000cccc0000cccc00
-- 142:00cccc0000cccc0000cccc0000cccc000ccccc000cccc0000cccc0000cccc000
-- 143:0cccc0000cccc0000cccc0000cccc000ccccc000cccc0000cccc0000cccc0000
-- 144:00000ccc0000cccc0000cccc0000cccc0000cccc0000cccc000ccccc000ccccc
-- 145:cc00cccccc0cccccc00cccccc00cccccc00cccccc00cccccc0cccccc00ccccc0
-- 146:c00cccc0c0ccccc000cccc0000cccc0000cccc0000cccc000ccccc000cccc000
-- 147:ccccc00ccccc000ccccc000ccccc000ccccc00cccccccccccccccccc00ccccc0
-- 148:cccc0000ccc00000ccc00000ccc00000ccc00000cc000000c000000000000000
-- 150:00ccccc00cccccc00ccccc000ccccc000ccccc000ccccc00cccccc00ccccc000
-- 151:00000ccc0000cccc0000cccc0000cccc0000cccc0000cccc000ccccc000cccc0
-- 152:c0000000c0000000000000000000000000000000000000000000000000000000
-- 153:00000ccc0000cccc0000cccc0000cccc0000cccc0000cccc000ccccc000cccc0
-- 154:c0000000c0000000000000000000000000000000000000000000000000000000
-- 155:000cccc000ccccc000cccc0000cccc0000cccc0000cccc000ccccc000cccc000
-- 157:00cccc000ccccc000cccc0000cccc0000cccc0000cccc000ccccc00ccccc000c
-- 158:0cccc000ccccc00ccccc000ccccc000ccccc000ccccc000ccccc00ccccc000cc
-- 159:cccc0000cccc000cccc0000cccc0000cccc0000cccc0000cccc000cccc0000cc
-- 160:000ccccc000ccccc000ccccc00cccccc00ccccc000ccccc000ccccc000ccccc0
-- 161:00ccccc000ccccc000ccccc00cccccc00ccccc000ccccc000ccccc000ccccc00
-- 162:0cccc0000cccc0000cccc000ccccc000cccc0000cccc0000cccc0000cccc0000
-- 165:0000000000000000000000000000000c0000000c0000000c0000000c0000000c
-- 166:ccccc000ccccc000ccccc000ccccc000cccc0000cccc0000cccc0000cccc0000
-- 167:000cccc0000cccc0000cccc000ccccc000cccc0000cccc0000cccc0000cccc00
-- 168:000000000000000000000000000000000000000000cccc0000cccc000ccccc00
-- 169:000cccc0000cccc0000cccc000ccccc000cccc0000cccc0000cccc0000cccc00
-- 170:000000000000000000000000000000000000000000000000000000000ccccc00
-- 171:0cccc0000cccc0000cccc000ccccc000cccc0000cccc0000cccc0000cccc0000
-- 172:0000000000000000000000000000000c0000000c0000000c0000000c0000000c
-- 173:cccc000ccccc000ccccc000ccccc00ccccc000ccccc000ccccc000ccccc000cc
-- 174:ccc000ccccc000ccccc000ccccc00ccccc000ccccc000ccccc000ccccc000ccc
-- 175:cc0000cccc0000cccc0000cccc000cccc0000cccc0000cccc0000cccc0000ccc
-- 176:0cccccc00ccccc000ccccc000ccccc000ccccccccccccccccccccccccccccccc
-- 177:cccccc0cccccc00cccccc00cccccc00cccccc00ccccc00ccccc000ccc00000cc
-- 178:cccc0000ccc00000ccc00000ccc00000ccc00000ccc00000cc000000cc000000
-- 179:0000000000000000000000000000000000000ccc0000cccc000ccccc0000ccc0
-- 181:000000cc000000cc000000cc000000cc000000cc00000ccc00000ccc00000ccc
-- 182:cccc0000ccc00000ccc00000ccc00000ccc00000ccc00000cc000000cc000000
-- 183:0ccccc000cccc0000cccc0000cccc0000ccccccc0ccccccc0ccccccc000ccccc
-- 184:0ccccc000cccc0000cccc000ccccc000ccccc000cccc0000ccc00000cc000000
-- 185:0ccccc000cccc0000cccc0000cccc0000cccc0000ccccccc0ccccccc0ccccccc
-- 186:cccccc0cccccc00cccccc00cccccc00cccccc00ccccc00cccccc00ccccc000cc
-- 187:cccc0000ccc00000ccc00000ccc00000ccc00000ccc00000cc000000cc000000
-- 188:000000cc000000cc000000cc000000cc000000cc000000cc000000cc00000000
-- 189:ccc00ccccc000ccccc000ccccc000ccccc00ccccccccccccccccccc0ccccc000
-- 190:cc00ccccc000ccccc000ccccc000ccccc000cccc000ccccc000cccc0000cccc0
-- 191:c000cccc0000cccc0000cccc0000cccc0000cccc000ccccc000cccc0000cccc0
-- 192:000000000000000000000000000000000000000000000000ccccc00ccccccccc
-- 193:000000000000000000000000000000000000000000000000cccc0000ccccc000
-- 194:000ccc0000ccccc000cccc0000ccc00000000000000000000cccc0000cccc000
-- 195:0000000000000000000000000000000000000000000000000ccccccc0ccccccc
-- 196:000000000000000000000000000000000000000000000000cc000000ccc00000
-- 197:00000000000000000000000000000000000000000000000000cccccccccccccc
-- 198:0cccc0000cccc0000cccc0000cccc000ccccc00ccccc000ccccc000ccccc000c
-- 199:cccc000ccccc000ccccc000ccccc000ccccc00ccccc000ccccc000ccccc000cc
-- 200:ccc0000cccc0000cccc0000cccc0000cccc000cccc0000cccc0000cccc0000cc
-- 201:ccc000ccccc000ccccc000ccccc000ccccc00ccccc000ccccc000ccccc000ccc
-- 202:cc000ccccc000ccccc000ccccc000ccccc00ccccc000ccccc000ccccc000cccc
-- 203:c000ccccc000ccccc000ccccc000ccccc00ccccc000cccc0000cccc0000cccc0
-- 204:cc000ccccc000ccccc000ccccc00ccccc000ccccc000ccccc000ccccc000cccc
-- 205:c000ccccc000ccccc000ccccc00ccccc000cccc0000cccc0000cccc0000cccc0
-- 206:0000cccc0000cccc0000cccc000ccccc000cccc0000cccc0000cccc0000cccc0
-- 207:000cccc0000cccc0000cccc000ccccc000cccc0000cccc0000cccc0000cccc00
-- 208:cccccccccccccccc00ccccc000cccc0000cccc0000cccc0000cccc000ccccc00
-- 209:cccccc00cccccc000ccccc000cccc0000cccc0000cccc0000cccc000ccccc00c
-- 210:0cccc0000cccc000ccccc000cccc0000cccc0000cccc0000cccc0000cccc000c
-- 211:0ccccccc0cccccccccccc00ccccc000ccccc000ccccc000ccccc000ccccc00cc
-- 212:cccc000ccccc000ccccc00ccccc000ccccc000ccccc000ccccc000ccccc00ccc
-- 213:ccccccccccccccccccc00ccccc000ccccc000ccccc000ccccc000ccccc00cccc
-- 214:cccc000ccccc00ccccc000ccccc000ccccc000ccccc000ccccc00ccccc000ccc
-- 215:ccc000ccccc00ccccc000ccccc000ccccc000ccccc000ccccc00ccccc000cccc
-- 216:cc0000cccc000cccc0000cccc0000cccc0000cccc0000cccc000cccc0000cccc
-- 217:cc000ccccc00ccccc000ccccc000ccccc000ccccc000ccccc00ccccc000cccc0
-- 218:c000ccccc00ccccc000cccc0000cccc0000cccc0000cccc000ccccc000cccc00
-- 219:000cccc000ccccc000cccc0000cccc0000cccc0000cccc000ccccc000cccc000
-- 220:c00ccccc000cccc0000cccc0000cccc0000cccc000ccccc000cccc0000cccc00
-- 221:00ccccc000cccc0000cccc0000cccc0000cccc000ccccc000cccc0000cccc000
-- 222:00ccccc000cccc0000cccc0000cccc0000cccc000ccccc000cccc0000cccc000
-- 223:0ccccc000cccc0000cccc0000cccc0000cccc000ccccc000cccc0000cccc0000
-- 225:0088999900889999008899990088999900889999008899990088999900889999
-- 226:0000000000000000aaaaaaaaaaaaaaaa99999999999999999999999999999999
-- 227:9999aa009999aa009999aaaa9999aaaa99999999999999999999999999999999
-- 229:9999aa009999aa009999aa009999aa009999aa009999aa009999aa009999aa00
-- 230:99999999999999999999999999999999999988889999a8889999aa009999aa00
-- 231:0000000000000000000c0300c0cc0300c0c00000000000000000000000000000
-- 232:0000000000000000010000000100000000000000000000000000000000000000
-- 233:0088999900889999aaa89999aaaa999999999999999999999999999999999999
-- 234:9999999999999999999999999999999988888888888888880000000000000000
-- 235:0000000000000000900e0000900e000000000000000000000000000000000000
-- 236:9999999999999999999999999999999988889999888899990088999900889999
-- 241:99aa9988888a9988a8889988aa999988aa999988aaaa9988aaaa998899aa9988
-- 242:9a8888899aa888898aa9988888a9988899999999999999998888888888888888
-- 243:8899889988998899889988888899888888999999889999998888888888888888
-- 245:88998899889988888899888888999988889999888899aaa888998aaa88998899
-- 246:888888888888888888999999889999998899aaaa88998aaa8899889988998899
-- 247:0000000000000000c00c00ccc00cc0ccc00c0000c00000000000000000000000
-- 248:000000000000000000c0c00c00c0c00c0cc0cc00000000000000000000000000
-- 249:99aa998899aa9988888a99888888998899999988999999888888888888888888
-- 250:88888888888888889999999999999999aaa998aaaaa9988a9aaaa8899aaaaa89
-- 251:0000000000000000900e0060900e006000000000000000000000000000000000
-- 252:88888888888888889999998899999988aaaa9988aaaa998899aa998899aa9988
-- </TILES>

-- <MAP>
-- 000:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000162636000066768696a6b6c6d6e6f60c1c2c3c4c5c56000000000000006fafafafafafafafafafafafafafafafafafafafafafafafafafafafafcf00000000000041000000000000004400000000006fafafafafafafafafcf
-- 001:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007172737000067778797a7b7c7d7e7f70d1d2d3d4d5d57000000000000005f6eaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaece1f00000000000052000000000000005300000000005f6eaeaeaeaeaeaece1f
-- 002:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008182800000068788898a8b8c8d8e8f86c7c8c9cacbc00000000000000005f5e00000000000000000000000000000000000000000000000000001e1f21a2a3840000530024a3a28100005200000000005f5e0000000000001e1f
-- 003:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009192900005969798999a9b9c9d9e9f96d7d8d9dadbd00000000000000005f5e00000000000000000000000000000000000000000000000000001e1f00000000000014000000000000001100000000005f5e0000000000001e1f
-- 004:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a1a2a00005a6a7a8a9aaabacadaeafaccdcecfc384800000000000000005f5e00000000000000000000000000000000000000000000000000001e1f61c263c164c362c40000000000000000000000005f5e0000000000001e1f
-- 005:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b1b2b3b005b6b7b8b9babbbcbdbebfbcdddedfd394900000000000000005f5e00000000000000000000000000000000000000000000000000001e1f33943492329131930000000000000000000000005f5e0000000000001e1f
-- 006:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005f5e00000000000000000000000000000000000000000000000000001e1f00000000410044000000638400000000000000005f5e0000000000001e1f
-- 007:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005f5e00000000000000000000000000000000000000000000000000001e1f21a2c300520033a28100520000000000000000005f5e0000000000001e1f
-- 008:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005f5e00000000000000000000000000000000000000000000000000001e1f00001424930000000000110000000000000000005f5e0000000000001e1f
-- 009:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005f5e00000000000000000000000000000000000000000000000000001e1f00000021c20000004100440000000000000000005f5e0000000000001e1f
-- 010:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005f5e00000000000000000000000000000000000000000000000000001e1f62a38400530024a39200530000000000000000005f5e0000000000001e1f
-- 011:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005f5e00000000000000000000000000000000000000000000000000001e1f11000000140000000000328100000000000000005f5e0000000000001e1f
-- 012:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005f5e00000000000000000000000000000000000000000000000000001e1f00000000430000000000420000000000000000005f5e0000000000001e1f
-- 013:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005f5e00000000000000000000000000000000000000000000000000001e1f0061820034c10064830031c400000000000000005f5e0000000000001e1f
-- 014:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005f5e00000000000000000000000000000000000000000000000000001e1f2394000000122291000000130000007f8f7ebe005f5e0000000000001e1f
-- 015:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005f3e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e9e1f0000000041000044000043000000007f8f7ebf005f3e2e2e2e2e2e2e9e1f
-- 016:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f9f21e28324d20023b2810072840000007f8f7ebf8e3f2f2f2f2f2f2f2f2f9f
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

-- <PATTERNS>
-- 000:866112000000866114000000f66116000000d66116000000866112000000866114000000d66116000000f66116000000866116000000000000000000866116000000466118000000466118000000000000000000d66112000000d66116000000c66112000000c66114000000c66116000000466118000000866112000000866114000000866112000000866114000000d66112000000d66114000000866116000000000000000000d66112000000d66114000000d66112000000d66114000000
-- 001:f66116000000000000000000866112000000866114000000666118000000866118666118466118000000866114000000d66112000000d66114000000d66116000000d66114000000d66112000000d66114000000666118000000466118000000c66116000000000000000000c66112000000c66114000000f66116000000000000000000f66116000000000000000000466118000000000000000000d66116000000000000000000866116000000000000000000000000000000000000000000
-- 002:866118000000000000000000c66116000000466118000000f66116000000c66116000000866112000000c66116000000d66116000000000000000000d66112000000d66116000000866118000000000000000000f66116000000d66114000000f66116000000000000000000f66116000000d66116000000666118000000000000000000866118000000000000000000d66116000000000000000000d66112000000d66114000000d66116000000000000000000000000000000000000000000
-- 003:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f66112000000466114000000
-- 004:666114000000666118000000000000000000666114000000966118000000000000000000b66118000000666118000000466118000000000000000000000000000000d66116000000866118000000000000000000f66116000000466118000000c66116000000000000000000c66112000000c66114000000866112000000866114000000866112000000866114000000d66112000000d66114000000d66112000000d66114000000d66116000000000000000000000000000000000000000000
-- 005:666112000000d66116000000000000000000666118000000d66118000000000000000000866118000000966118000000d66112000000d66114000000d66112000000d66114000000d66116000000000000000000666118000000d66114000000f66116000000000000000000c66116000000466118000000666118000000000000000000866118000000000000000000466118000000000000000000866116000000000000000000866116000000000000000000000000000000000000000000
-- 006:000000000000666114000000666112000000966118000000666112000000666114000000666112000000666114000000866118000000000000000000000000000000466118000000d66112000000d66114000000d66112000000d66116000000c66112000000c66114000000f66116000000d66116000000f66116000000000000000000f66116000000000000000000d66116000000000000000000d66116000000000000000000d66112000000d66114000000d66112000000d66114000000
-- 007:f66116000000000000000000866112000000d66116000000666118000000866118666118866112000000f66116000000d66116000000000000000000d66112000000466118000000866118000000000000000000666118000000d66114000000f66116000000000000000000c66116000000d66116000000f66116000000000000000000866118000000000000000000d66112000000d66114000000866116000000000000000000d66112000000d66114000000d66112000000466114000000
-- 008:866118000000000000000000c66116000000466118000000866112000000866114000000466118000000c66116000000866116000000000000000000d66116000000d66116000000466118000000000000000000d66112000000d66116000000c66112000000c66114000000c66112000000466118000000866112000000866114000000f66116000000000000000000d66116000000000000000000d66116000000000000000000d66116000000000000000000000000000000000000000000
-- 009:866112000000866114000000f66116000000866114000000f66116000000c66116000000d66116000000866114000000d66112000000d66114000000866116000000d66114000000d66112000000d66114000000f66116000000466118000000c66116000000000000000000f66116000000c66114000000666118000000000000000000866112000000866114000000466118000000000000000000d66112000000d66114000000866116000000000000000000000000000000000000000000
-- 010:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f66112000000d66114000000
-- 011:666112000000d66116000000000000000000966118000000d66118000000000000000000b66118000000966118000000d66112000000d66114000000d66112000000d66116000000d66116000000000000000000666118000000d66114000000c66112000000c66114000000f66116000000d66116000000866112000000866114000000866112000000866114000000d66112000000d66114000000d66116000000000000000000d66112000000d66114000000d66112000000d66114000000
-- 012:666114000000666114000000666112000000666114000000666112000000666114000000866118000000666114000000866118000000000000000000000000000000466118000000866118000000000000000000d66112000000466118000000c66116000000000000000000c66112000000c66114000000f66116000000000000000000866118000000000000000000d66116000000000000000000866116000000000000000000d66116000000000000000000000000000000000000000000
-- 013:000000000000666118000000000000000000666118000000966118000000000000000000666112000000666118000000466118000000000000000000000000000000d66114000000d66112000000d66114000000f66116000000d66116000000f66116000000000000000000c66116000000466118000000666118000000000000000000f66116000000000000000000466118000000000000000000d66112000000d66114000000866116000000000000000000000000000000000000000000
-- 014:466116000000000000000000000000000000000000000000d66114000000000000000000000000000000000000000000c66112000000866114000000c66112000000866114000000c66112000000866114000000c66112000000866114000000d66114000000000000000000000000000000000000000000d66112000000866114000000d66112000000866114000000c66112000000866114000000c66112000000866114000000c66112000000866114000000c66112000000866114000000
-- 015:866116000000000000000000000000000000000000000000466116000000000000000000000000000000000000000000666116000000000000000000000000000000000000000000c66114000000000000000000000000000000000000000000d66112000000866114000000d66112000000866114000000d66114000000000000000000000000000000000000000000c66114000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:d66112000000866114000000d66112000000866114000000d66112000000866114000000d66112000000866114000000c66114000000000000000000000000000000000000000000f66114000000000000000000000000000000000000000000466116000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 017:466116000000000000000000000000000000000000000000466116000000000000000000000000000000000000000000c66112000000866114000000c66112000000866114000000c66112000000866114000000c66112000000866114000000d66112000000866114000000466116000000000000000000d66112000000866114000000d66112000000866114000000866116000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 018:866116000000000000000000000000000000000000000000d66114000000000000000000000000000000000000000000666116000000000000000000000000000000000000000000c66114000000000000000000000000000000000000000000d66114000000000000000000d66112000000866114000000866116000000000000000000000000000000000000000000c66116000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 019:d66112000000866114000000d66112000000866114000000d66112000000866114000000d66112000000866114000000c66114000000000000000000000000000000000000000000f66114000000000000000000000000000000000000000000466116000000000000000000866116000000000000000000d66116000000000000000000000000000000000000000000c66112000000866114000000c66112000000866114000000c66112000000866114000000c66112000000866114000000
-- 020:f66116000000000000000000c66116000000466118000000866112000000866118666118466118000000866114000000d66112000000d66114000000866116000000d66114000000d66112000000d66114000000f66116000000466118000000f66116000000000000000000c66116000000c66114000000666118000000000000000000866112000000866114000000d66116000000000000000000866116000000000000000000d66116000000000000000000000000000000000000000000
-- 021:866112000000866114000000866112000000866114000000f66116000000866114000000d66116000000f66116000000d66116000000000000000000d66116000000466118000000866118000000000000000000d66112000000d66114000000c66112000000c66114000000f66116000000d66116000000f66116000000000000000000f66116000000000000000000466118000000000000000000d66116000000000000000000866116000000000000000000000000000000000000000000
-- 022:866118000000000000000000f66116000000d66116000000666118000000c66116000000866112000000c66116000000866116000000000000000000d66112000000d66116000000466118000000000000000000666118000000d66116000000c66116000000000000000000c66112000000466118000000866112000000866114000000866118000000000000000000d66112000000d66114000000d66112000000d66114000000d66112000000d66114000000d66112000000d66114000000
-- 023:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f66112000000466114000000
-- 024:666112000000666114000000666112000000666114000000d66118000000000000000000866118000000666114000000d66112000000d66114000000d66112000000d66116000000d66116000000000000000000f66116000000d66116000000f66116000000000000000000c66112000000c66114000000866112000000866114000000866118000000000000000000466118000000000000000000d66112000000d66114000000d66112000000d66114000000d66112000000d66114000000
-- 025:666114000000d66116000000000000000000966118000000966118000000000000000000b66118000000966118000000466118000000000000000000000000000000466118000000866118000000000000000000d66112000000d66114000000c66116000000000000000000c66116000000d66116000000f66116000000000000000000f66116000000000000000000d66112000000d66114000000d66116000000000000000000d66116000000000000000000000000000000000000000000
-- 026:000000000000666118000000000000000000666118000000666112000000666114000000666112000000666118000000866118000000000000000000000000000000d66114000000d66112000000d66114000000666118000000466118000000c66112000000c66114000000f66116000000466118000000666118000000000000000000866112000000866114000000d66116000000000000000000866116000000000000000000866116000000000000000000000000000000000000000000
-- 027:866118000000000000000000f66116000000d66116000000866112000000c66116000000d66116000000f66116000000d66112000000d66114000000d66112000000d66114000000866118000000000000000000666118000000d66114000000f66116000000000000000000f66116000000466118000000866112000000866114000000f66116000000000000000000d66112000000d66114000000d66116000000000000000000d66112000000d66114000000f66112000000466114000000
-- 028:f66116000000000000000000c66116000000466118000000666118000000866118666118866112000000866114000000d66116000000000000000000866116000000466118000000d66112000000d66114000000f66116000000466118000000c66116000000000000000000c66116000000c66114000000666118000000000000000000866118000000000000000000466118000000000000000000d66112000000d66114000000866116000000000000000000000000000000000000000000
-- 029:866112000000866114000000866112000000866114000000f66116000000866114000000466118000000c66116000000866116000000000000000000d66116000000d66116000000466118000000000000000000d66112000000d66116000000c66112000000c66114000000c66112000000d66116000000f66116000000000000000000866112000000866114000000d66116000000000000000000866116000000000000000000d66116000000000000000000000000000000000000000000
-- 030:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d66112000000d66114000000
-- 031:666114000000d66116000000000000000000966118000000666112000000666114000000866118000000666114000000d66112000000d66114000000d66112000000d66114000000866118000000000000000000f66116000000466118000000c66112000000c66114000000c66116000000c66114000000666118000000000000000000866118000000000000000000d66112000000d66114000000d66116000000000000000000d66112000000d66114000000d66112000000d66114000000
-- 032:666112000000666114000000666112000000666118000000966118000000000000000000b66118000000666118000000466118000000000000000000000000000000d66116000000d66116000000000000000000d66112000000d66114000000f66116000000000000000000c66112000000466118000000f66116000000000000000000f66116000000000000000000d66116000000000000000000866116000000000000000000866116000000000000000000000000000000000000000000
-- 033:000000000000666118000000000000000000666114000000d66118000000000000000000666112000000966118000000866118000000000000000000000000000000466118000000d66112000000d66114000000666118000000d66116000000c66116000000000000000000f66116000000d66116000000866112000000866114000000866112000000866114000000466118000000000000000000d66112000000d66114000000d66116000000000000000000000000000000000000000000
-- 034:866118000000000000000000f66116000000d66116000000666118000000866118666118d66116000000f66116000000d66116000000000000000000d66112000000d66116000000d66112000000d66114000000666118000000466118000000c66116000000000000000000f66116000000466118000000666118000000000000000000f66116000000000000000000466118000000000000000000d66112000000d66114000000d66116000000000000000000000000000000000000000000
-- 035:f66116000000000000000000c66116000000466118000000866112000000866114000000466118000000866114000000d66112000000d66114000000d66116000000d66114000000466118000000000000000000f66116000000d66114000000f66116000000000000000000c66112000000d66116000000f66116000000000000000000866118000000000000000000d66112000000d66114000000866116000000000000000000866116000000000000000000000000000000000000000000
-- 036:866112000000866114000000866112000000866114000000f66116000000c66116000000866112000000c66116000000866116000000000000000000866116000000466118000000866118000000000000000000d66112000000d66116000000c66112000000c66114000000c66116000000c66114000000866112000000866114000000866112000000866114000000d66116000000000000000000d66116000000000000000000d66112000000d66114000000d66112000000466114000000
-- 037:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f66112000000d66114000000
-- 038:666114000000666114000000666112000000666118000000d66118000000000000000000b66118000000966118000000466118000000000000000000000000000000d66114000000d66112000000d66114000000666118000000d66114000000c66112000000c66114000000c66116000000d66116000000866112000000866114000000f66116000000000000000000d66112000000d66114000000d66116000000000000000000d66112000000d66114000000d66112000000d66114000000
-- 039:666112000000666118000000000000000000666114000000666112000000666114000000866118000000666114000000d66112000000d66114000000d66112000000d66116000000866118000000000000000000f66116000000466118000000c66116000000000000000000f66116000000466118000000f66116000000000000000000866112000000866114000000d66116000000000000000000866116000000000000000000866116000000000000000000000000000000000000000000
-- 040:000000000000d66116000000000000000000966118000000966118000000000000000000666112000000666118000000866118000000000000000000000000000000466118000000d66116000000000000000000d66112000000d66116000000f66116000000000000000000c66112000000c66114000000666118000000000000000000866118000000000000000000466118000000000000000000d66112000000d66114000000d66116000000000000000000000000000000000000000000
-- 041:866116000000000000000000000000000000000000000000d66114000000000000000000000000000000000000000000c66112000000866114000000c66112000000866114000000c66112000000866114000000c66112000000866114000000d66112000000866114000000d66112000000866114000000d66112000000866114000000d66112000000866114000000c66112000000866114000000c66112000000866114000000c66112000000866114000000c66112000000866114000000
-- 042:466116000000000000000000000000000000000000000000d66112000000866114000000d66112000000866114000000c66114000000000000000000000000000000000000000000c66114000000000000000000000000000000000000000000d66114000000000000000000000000000000000000000000d66114000000000000000000000000000000000000000000c66114000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 043:d66112000000866114000000d66112000000866114000000466116000000000000000000000000000000000000000000666116000000000000000000000000000000000000000000f66114000000000000000000000000000000000000000000466116000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 044:d66112000000866114000000d66112000000866114000000466116000000000000000000000000000000000000000000c66112000000866114000000c66112000000866114000000f66114000000000000000000000000000000000000000000d66112000000866114000000466116000000000000000000d66112000000866114000000d66112000000866114000000c66116000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 045:866116000000000000000000000000000000000000000000d66112000000866114000000d66112000000866114000000666116000000000000000000000000000000000000000000c66112000000866114000000c66112000000866114000000d66114000000000000000000866116000000000000000000d66116000000000000000000000000000000000000000000866116000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 046:466116000000000000000000000000000000000000000000d66114000000000000000000000000000000000000000000c66114000000000000000000000000000000000000000000c66114000000000000000000000000000000000000000000466116000000000000000000d66112000000866114000000866116000000000000000000000000000000000000000000c66112000000866114000000c66112000000866114000000c66112000000866114000000c66112000000866114000000
-- 047:866112000000866114000000c66116000000466118000000666118000000866114000000466118000000866114000000d66112000000d66114000000866116000000466118000000d66112000000d66114000000d66112000000466118000000f66116000000000000000000f66116000000466118000000f66116000000000000000000866112000000866114000000d66116000000000000000000d66112000000d66114000000866116000000000000000000000000000000000000000000
-- 048:866118000000000000000000866112000000866114000000866112000000c66116000000d66116000000f66116000000d66116000000000000000000d66116000000d66116000000866118000000000000000000f66116000000d66114000000c66112000000c66114000000c66112000000c66114000000866112000000866114000000f66116000000000000000000466118000000000000000000866116000000000000000000d66112000000d66114000000d66112000000d66114000000
-- 049:f66116000000000000000000f66116000000d66116000000f66116000000866118666118866112000000c66116000000866116000000000000000000d66112000000d66114000000466118000000000000000000666118000000d66116000000c66116000000000000000000c66116000000d66116000000666118000000000000000000866118000000000000000000d66112000000d66114000000d66116000000000000000000d66116000000000000000000000000000000000000000000
-- 050:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f66112000000466114000000
-- 051:666112000000d66116000000000000000000966118000000d66118000000000000000000866118000000966118000000466118000000000000000000000000000000d66116000000866118000000000000000000f66116000000d66116000000f66116000000000000000000c66116000000c66114000000666118000000000000000000866118000000000000000000466118000000000000000000d66112000000d66114000000d66112000000d66114000000d66112000000d66114100000
-- 052:666114000000666118000000000000000000666118000000966118000000000000000000b66118000000666118000000d66112000000d66114000000d66112000000d66114000000d66116000000000000000000d66112000000d66114000000c66112000000c66114000000f66116000000d66116000000866112000000866114000000f66116000000000000000000d66112000000d66114000000d66116000000000000000000d66116000000000000000000000000000000000000100000
-- 053:000000000000666114000000666112000000666114000000666112000000666114000000666112000000666114000000866118000000000000000000000000000000466118000000d66112000000d66114000000666118000000466118000000c66116000000000000000000c66112000000466118000000f66116000000000000000000866112000000866114000000d66116000000000000000000866116000000000000000000866116000000000000000000000000000000000000100000
-- 059:100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </PATTERNS>

-- <PATTERNS1>
-- 000:d66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000d66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000866118000000000000000000000000000000000000000000d66112000000100000000000466114000000100000000000c66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000
-- 001:000000000000000000000000466114000000100000000000c66112000000100000000000666114000000100000000000000000000000000000000000466114000000100000000000d66112000000100000000000466114000000100000000000d66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000666118000000000000000000000000000000000000000000c66112000000100000000000666114000000100000000000
-- 002:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000466114000000100000000000466118000000000000000000000000000000000000000000100000000000000000000000666114000000100000000000f66116000000000000000000000000000000000000000000
-- 003:d66112000000866114000000100000000000f66116000000100000000000966114000000100000000000466118000000c66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000d66112000000100000000000466114000000100000000000d66112000000100000000000f66116000000100000000000d66112000000966114000000100000000000966114000000100000000000966114000000100000000000f66116000000
-- 004:466118000000100000000000466114000000100000000000466118000000100000000000666114000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000466114000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000966114000000
-- 005:000000000000c66116000000100000000000866114000000100000000000d66116000000100000000000966114000000666118000000000000000000000000000000000000000000c66116000000000000000000000000000000000000000000100000000000866114000000100000000000866114000000100000000000d66116000000100000000000866114000000666118000000000000000000000000000000000000000000000000000000000000000000466118000000100000000000
-- 006:000000000000000000000000d66116000000100000000000d66112000000100000000000f66116000000100000000000000000000000000000000000666114000000100000000000c66112000000100000000000666114000000100000000000866118000000000000000000000000000000000000000000000000000000866114000000100000000000466118000000100000000000000000000000666114000000100000000000d66112000000100000000000666114000000100000000000
-- 007:d66116000000000000000000000000000000000000000000c66116000000000000000000000000000000000000000000100000000000866114000000100000000000866114000000100000000000c66116000000100000000000f66116000000d66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000666118000000000000000000000000000000000000000000c66112000000100000000000666114000000100000000000
-- 008:d66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000d66112000000100000000000466114000000100000000000d66112000000100000000000d66116000000100000000000d66116000000000000000000d66116000000000000000000166116000000000000000000466114000000100000000000c66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000
-- 009:000000000000000000000000466114000000100000000000c66112000000100000000000666114000000100000000000d66116000000000000000000000000000000000000000000a66116000000100000000000466114000000100000000000866118000000000000000000000000000000000000000000466118000000000000000000000000000000000000000000100000000000000000000000866116000000000000000000166116000000000000000000166116000000000000000000
-- 010:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000866114000000100000000000866114000000100000000000000000000000466114000000100000000000d66112000000100000000000166116000000000000000000866116000000000000000000666114000000100000000000f66116000000000000000000000000000000000000000000
-- 011:466118000000c66116000000100000000000866114000000d66112000000d66116000000f66116000000100000000000c66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000866118000000000000000000000000000000000000000000000000000000d66116000000166116000000866114000000d66112000000966114000000100000000000966114000000100000000000966114000000100000000000f66116000000
-- 012:d66116000000000000000000466114000000100000000000966116000000000000000000166116000000966114000000866116000000000000000000666114000000100000000000c66112000000100000000000666114000000100000000000d66116000000000000000000d66116000000000000000000100000000000866114000000100000000000466118000000666116000000000000000000666114000000100000000000d66112000000100000000000466118000000100000000000
-- 013:d66112000000866114000000100000000000f66116000000100000000000966114000000100000000000466118000000666118000000000000000000000000000000000000000000c66116000000000000000000000000000000000000000000100000000000866114000000100000000000866114000000100000000000000000000000f66116000000100000000000666118000000000000000000000000000000000000000000000000000000000000000000666114000000100000000000
-- 014:000000000000000000000000d66116000000000000000000466118000000100000000000666114000000100000000000000000000000000000000000866116000000000000000000166116000000000000000000166116000000000000000000d66112000000100000000000466114000000100000000000d66112000000100000000000466114000000100000000000000000000000000000000000666116000000000000000000166116000000000000000000166116000000966114000000
-- 015:d66116000000000000000000000000000000000000000000c66116000000000000000000000000000000000000000000100000000000000000000000466114000000100000000000a66116000000100000000000166116000000866114000000d66112000000866114000000100000000000866114000000100000000000d66118100000466114000000100000000000f66118000000000000000000000000000000866114000000100000000000000000000000666114000000100000000000
-- 016:d66112000000866114000000100000000000866114000000100000000000000000000000666114000000100000000000000000000000000000000000d66116000000000000000000166116000000866114000000100000000000000000000000000000000000000000000000466114000000100000000000d66118100000866114000000100000000000866114000000100000000000000000000000666114000000100000000000c66112000000100000000000000000000000000000000000
-- 017:866116000000000000000000866116000000000000000000166116000000866114000000100000000000866114000000d66112000000866114000000100000000000866114000000100000000000c66116000000100000000000f66116000000d66118000000000000000000000000000000000000000000d66112000000100000000000c66118100000d66118100000c66112000000866114000000100000000000c66118000000100000000000866114000000100000000000866114000000
-- 018:000000000000000000000000466114000000100000000000c66112000000100000000000166116000000000000000000000000000000000000000000000000000000000000000000d66112000000100000000000466114000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000866118000000000000000000000000000000000000000000
-- 019:d66112000000866114000000100000000000866114000000100000000000966114000000100000000000966114000000c66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000d66118000000000000000000000000000000f6611810000046611a100000866114000000100000000000866118100000666118000000000000000000000000000000966118000000100000000000966114000000100000000000d66118100000
-- 020:46611a000000000000000000466114000000100000000000466118000000000000000000100000000000000000000000866118000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d66112000000866114000000100000000000866114000000100000000000f66118100000466114000000100000000000d66112000000966114000000100000000000966114000000100000000000000000000000f66118000000100000000000
-- 021:000000000000000000000000d66118000000000000000000100000000000000000000000666118000000000000000000100000000000000000000000666114000000100000000000c66112000000100000000000666114000000100000000000000000000000000000000000466114000000100000000000d66112000000100000000000d66118100000866114000000100000000000000000000000666114000000100000000000d66112000000100000000000666114000000100000000000
-- 022:000000000000000000000000000000000000000000000000d66112000000100000000000666114000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d66118000000000000000000100000000000966114000000
-- 023:d66112000000866114000000100000000000966118000000100000000000866114000000100000000000466118100000d66116000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d66118000000000000000000000000000000000000000000d66118100000d66118100000466114000000100000000000f66118000000000000000000000000000000c66118000000100000000000866114000000100000000000866114000000
-- 024:866118000000000000000000000000000000866114000000100000000000666118100000f66116100000866114000000d66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000d66112000000866114000000100000000000866114000000100000000000866114000000100000000000d66118100000c66112000000866114000000100000000000866114000000100000000000000000000000666114000000100000000000
-- 025:000000000000000000000000466114000000100000000000866118100000000000000000666114000000100000000000000000000000000000000000466114000000100000000000d66112000000100000000000466114000000100000000000000000000000000000000000466114000000100000000000d66112000000100000000000c66118100000866114000000100000000000000000000000666114000000100000000000866118000000000000000000000000000000000000000000
-- 026:000000000000000000000000000000000000000000000000c66112000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c66112000000100000000000000000000000000000000000
-- 027:46611a000000000000000000466114000000100000000000d66112000000100000000000666114000000100000000000866118000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d66112000000866114000000100000000000866114000000100000000000866114000000100000000000866118100000d66112000000966114000000100000000000966114000000100000000000966114000000100000000000d66118100000
-- 028:d66112000000866114000000100000000000866114000000100000000000966114000000100000000000966114000000c66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000d66118000000000000000000000000000000f6611810000046611a100000f66118100000466114000000100000000000666118000000000000000000000000000000966118000000100000000000000000000000f66118000000100000000000
-- 029:000000000000000000000000d66118000000000000000000100000000000000000000000666118000000000000000000100000000000000000000000666114000000100000000000c66112000000100000000000666114000000100000000000000000000000000000000000466114000000100000000000d66112000000100000000000d66118100000866114000000100000000000000000000000666114000000100000000000d66112000000100000000000666114000000100000000000
-- 030:000000000000000000000000000000000000000000000000466118000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d66118000000000000000000100000000000966114000000
-- 031:866118000000000000000000000000000000966118000000100000000000666118100000f66116100000866114000000d66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000d66112000000866114000000100000000000f66118000000100000000000f66118100000d66118100000866114000000d66112000000966114000000100000000000966114000000100000000000966114000000100000000000d66118100000
-- 032:d66112000000866114000000100000000000866114000000100000000000866114000000100000000000466118100000d66116000000000000000000000000000000000000000000000000000000000000000000000000000000866118000000d66118000000000000000000000000000000866114000000100000000000866114000000100000000000866118100000666118000000000000000000000000000000966118000000100000000000000000000000666114000000100000000000
-- 033:000000000000000000000000466114000000100000000000866118100000000000000000666114000000100000000000000000000000000000000000466114000000100000000000d6611200000010000000000046611400000010000000000000000000000000000000000046611400000010000000000046611a100000000000000000466114000000100000000000000000000000000000000000666114000000100000000000d66112000000100000000000f66118000000100000000000
-- 034:000000000000000000000000000000000000000000000000c66112000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d66112000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000d66118000000000000000000100000000000966114000000
-- 035:d66112000000866114000000100000000000966118000000100000000000866114000000100000000000466118100000d66116000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000c66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000
-- 036:866118000000000000000000000000000000866114000000100000000000666118100000f66116100000866114000000d66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000866118000000000000000000000000000000000000000000466118000000000000000000000000000000000000000000100000000000000000000000666114000000100000000000f66116000000000000000000000000000000000000000000
-- 037:000000000000000000000000466114000000100000000000866118100000000000000000666114000000100000000000000000000000000000000000466114000000100000000000d66112000000100000000000466114000000100000000000000000000000000000000000466114000000100000000000d66112000000100000000000466114000000100000000000666118000000000000000000000000000000000000000000c66112000000100000000000666114000000100000000000
-- 038:000000000000000000000000000000000000000000000000c66112000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 039:d66112000000c66116000000100000000000f66116000000100000000000d66116000000100000000000466118000000c66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000d66112000000866114000000100000000000866114000000100000000000d66116000000100000000000466118000000d66112000000966114000000100000000000966114000000100000000000966114000000100000000000f66116000000
-- 040:466118000000100000000000466114000000100000000000466118000000100000000000666114000000100000000000000000000000000000000000666114000000100000000000c66112000000100000000000666114000000100000000000866118000000000000000000000000000000000000000000000000000000866114000000100000000000866114000000100000000000000000000000666114000000100000000000d66112000000100000000000466118000000100000000000
-- 041:000000000000866114000000100000000000866114000000100000000000966114000000100000000000966114000000666118000000000000000000000000000000000000000000c66116000000000000000000000000000000000000000000100000000000000000000000466114000000100000000000d66112000000100000000000f66116000000100000000000666118000000000000000000000000000000000000000000000000000000000000000000666114000000100000000000
-- 042:000000000000000000000000d66116000000100000000000d66112000000100000000000f66116000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000466114000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000966114000000
-- 043:d66116000000000000000000000000000000000000000000c66116000000000000000000000000000000000000000000100000000000866114000000100000000000866114000000100000000000c66116000000100000000000866114000000d66116000000000000000000466114000000100000000000466118000000000000000000000000000000000000000000100000000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000
-- 044:d66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000d66112000000100000000000466114000000100000000000a66116000000100000000000466114000000100000000000866118000000000000000000000000000000000000000000d66112000000100000000000166116000000866114000000866116000000000000000000666114000000100000000000c66112000000100000000000666114000000100000000000
-- 045:000000000000000000000000466114000000100000000000c66112000000100000000000666114000000100000000000d66116000000000000000000000000000000000000000000d66112000000100000000000d66116000000100000000000d66112000000866114000000100000000000866114000000100000000000866114000000100000000000000000000000c66112000000100000000000866116000000000000000000166116000000000000000000166116000000000000000000
-- 046:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000866114000000100000000000f66116000000100000000000000000000000d66116000000000000000000166116000000000000000000466114000000100000000000666118000000000000000000000000000000000000000000f66116000000000000000000000000000000000000000000
-- 047:d66112000000c66116000000100000000000866114000000966116000000966114000000666114000000100000000000666118000000000000000000000000000000000000000000c66116000000000000000000000000000000000000000000100000000000866114000000100000000000866114000000100000000000d66116000000166116000000866114000000d66112000000966114000000100000000000966114000000100000000000966114000000100000000000f66116000000
-- 048:d66116000000000000000000d66116000000000000000000466118000000100000000000f66116000000100000000000866116000000000000000000666114000000100000000000c66112000000100000000000166116000000866114000000d66112000000100000000000466114000000100000000000d66112000000100000000000466114000000100000000000666118000000000000000000000000000000000000000000000000000000000000000000466118000000100000000000
-- 049:466118000000866114000000100000000000f66116000000100000000000d66116000000100000000000966114000000c66112000000866114000000100000000000866114000000100000000000866114000000100000000000000000000000d66116000000000000000000d66116000000000000000000100000000000866114000000100000000000466118000000666116000000000000000000666114000000100000000000d66112000000100000000000666114000000100000000000
-- 050:000000000000000000000000466114000000100000000000d66112000000100000000000166116000000466118000000100000000000000000000000866116000000000000000000166116000000000000000000666114000000100000000000866118000000000000000000000000000000000000000000000000000000100000000000f66116000000100000000000000000000000000000000000666116000000000000000000166116000000000000000000166116000000966114000000
-- 051:d66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000d66112000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000d66112000000866114000000100000000000866114000000100000000000d66118100000466114000000100000000000c66112000000866114000000100000000000c66118000000100000000000866114000000100000000000866114000000
-- 052:866116000000000000000000466114000000100000000000c66112000000100000000000166116000000000000000000000000000000000000000000466114000000100000000000a66116000000100000000000166116000000f66116000000d66118000000000000000000000000000000000000000000d66118100000866114000000100000000000d66118100000f66118000000000000000000000000000000866114000000100000000000000000000000666114000000100000000000
-- 053:d66116000000000000000000000000000000000000000000c66116000000000000000000000000000000000000000000100000000000000000000000d66116000000000000000000166116000000c66116000000100000000000000000000000000000000000000000000000466114000000100000000000d66112000000100000000000c66118100000866114000000100000000000000000000000666114000000100000000000c66112000000100000000000000000000000000000000000
-- 054:000000000000000000000000866116000000000000000000166116000000000000000000666114000000100000000000000000000000000000000000000000000000000000000000d66112000000100000000000466114000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000866118000000000000000000000000000000000000000000
-- 055:d66112000000866114000000100000000000866114000000100000000000966114000000100000000000966114000000866118000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d66112000000866114000000100000000000f66118100000d66112000000100000000000d66118100000866118100000d66112000000966114000000100000000000966118000000100000000000966114000000100000000000d66118100000
-- 056:46611a000000000000000000466114000000100000000000d66112000000100000000000666118000000000000000000100000000000866114000000100000000000866114000000100000000000866114000000100000000000866114000000d66118000000000000000000000000000000866114000000100000000000866114000000100000000000866114000000666118000000000000000000000000000000966114000000100000000000000000000000f66118000000100000000000
-- 057:000000000000000000000000d66118000000000000000000100000000000000000000000666114000000100000000000c66112000000100000000000666114000000100000000000c6611200000010000000000066611400000010000000000000000000000000000000000046611400000010000000000046611a100000f66118100000466114000000100000000000000000000000000000000000666114000000100000000000d66112000000100000000000666114000000100000000000
-- 058:000000000000000000000000000000000000000000000000466118000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d66118000000000000000000100000000000966114000000
-- 059:166118000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </PATTERNS1>

-- <TRACKS>
-- 000:180301581700842ac2c43e00f041102d4410595716996b10c57ed70682203295a972a920aeac20dabf2007c2fc47d6306f0000
-- </TRACKS>

-- <TRACKS1>
-- 000:180300601741842ac2c43ec32141d44556d5856ad6c57ed70682e84696e98aa9eac6beeb07c2fc47d6fd87eafec30000cf0000
-- </TRACKS1>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>
