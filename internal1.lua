--[[

	Tube Library 2
	==============

	Copyright (C) 2018 Joachim Stolberg

	LGPLv2.1+
	See LICENSE.txt for more information

	internal1.lua
	
	First level functions behind the API

]]--

-- for lazy programmers
local S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local P = minetest.string_to_pos
local M = minetest.get_meta

-- Load support for intllib.
local MP = minetest.get_modpath("tubelib2")
local I,IS = dofile(MP.."/intllib.lua")

local Tube = tubelib2.Tube
local Turn180Deg = tubelib2.Turn180Deg
local Dir6dToVector = tubelib2.Dir6dToVector
local encode_param2 = tubelib2.encode_param2
local tValidNum = {[0] = true, true, true}  -- 0..2 are valid

-- format and return given data as table
local function get_tube_data(pos, dir1, dir2, num_tubes)
	local param2, tube_type = encode_param2(dir1, dir2, num_tubes)
	return pos, param2, tube_type, num_tubes
end	

local function fdir(self, player)
	local pitch = player:get_look_pitch()
	if pitch > 1.0 and self.valid_dirs[6] then -- up?
		return 6
	elseif pitch < -1.0 and self.valid_dirs[5] then -- down?
		return 5
	elseif not self.valid_dirs[1] then
		return 6
	else
		return minetest.dir_to_facedir(player:get_look_dir()) + 1
	end
end

local function get_player_data(self, placer, pointed_thing)
	if placer and pointed_thing and pointed_thing.type == "node" then
		if placer:get_player_control().sneak then
			return pointed_thing.under, fdir(self, placer)
		else
			return nil, fdir(self, placer)
		end
	end
end


-- Used to determine the node side to the tube connection.
-- Function returns the first found dir value
-- to a primary node.
-- Only used by convert.set_pairing()
function Tube:get_primary_dir(pos)
	-- Check all valid positions
	for dir = 1,6 do
		if self:primary_node(pos, dir) then
			return dir
		end
	end
end

-- pos/dir are the pos of the stable secondary node pointing to the head tube node.
function Tube:del_from_cache(pos, dir)
	local key = S(pos)
	if self.connCache[key] and self.connCache[key][dir] then
		local pos2 = self.connCache[key][dir].pos2
		local dir2 = self.connCache[key][dir].dir2
		local key2 = S(pos2)
		if self.connCache[key2] and self.connCache[key2][dir2] then
			self.connCache[key2][dir2] = nil
		end
		self.connCache[key][dir] = nil
	end
end

-- pos/dir are the pos of the secondary nodes pointing to the head tube nodes.
function Tube:add_to_cache(pos1, dir1, pos2, dir2)
	local key = S(pos1)
	if not self.connCache[key] then
		self.connCache[key] = {}
	end
	self.connCache[key][dir1] = {pos2 = pos2, dir2 = dir2}
end

-- pos/dir are the pos of the secondary nodes pointing to the head tube nodes.
function Tube:update_secondary_node(pos1, dir1, pos2, dir2)
	local _, node = self:get_node(pos1)
	if self.secondary_node_names[node.name] then
		if minetest.registered_nodes[node.name].tubelib2_on_update then
			minetest.registered_nodes[node.name].tubelib2_on_update(node, pos1, dir1, pos2, Turn180Deg[dir2])			
		elseif self.clbk_update_secondary_node then
			self.clbk_update_secondary_node(node, pos1, dir1, pos2, Turn180Deg[dir2])
		end
	end
end

function Tube:infotext(pos1, pos2)
	if self.show_infotext then
		if vector.equals(pos1, pos2) then
			M(pos1):set_string("infotext", I("Not connected!"))
		else
			M(pos1):set_string("infotext", I("Connected with ")..S(pos2))
		end
	end
end

--------------------------------------------------------------------------------------
-- pairing functions
--------------------------------------------------------------------------------------

-- Pairing helper function
function Tube:store_teleport_data(pos, peer_pos)		
	local meta = M(pos)
	meta:set_string("tele_pos", S(peer_pos))
	meta:set_string("channel", nil)
	meta:set_string("formspec", nil)
	meta:set_string("infotext", I("Paired with ")..S(peer_pos))
	return meta:get_int("tube_dir")
end

-------------------------------------------------------------------------------
-- update-after/get-dir functions
-------------------------------------------------------------------------------

function Tube:update_after_place_node(pos, dirs)
	-- Check all valid positions
	local lRes= {}
	dirs = dirs or self.dirs_to_check
	for _,dir in ipairs(dirs) do
		local npos, d1, d2, num = self:add_tube_dir(pos, dir)
		if npos and self.valid_dirs[d1] and self.valid_dirs[d2] and tValidNum[num]then
			self.clbk_after_place_tube(get_tube_data(npos, d1, d2, num))
			lRes[#lRes+1] = dir
		end
	end
	return lRes
end

function Tube:update_after_dig_node(pos, dirs)
	-- Check all valid positions
	local lRes= {}
	dirs = dirs or self.dirs_to_check
	for _,dir in ipairs(dirs) do
		local npos, d1, d2, num = self:del_tube_dir(pos, dir)
		if npos and self.valid_dirs[d1] and self.valid_dirs[d2] and tValidNum[num]then
			self.clbk_after_place_tube(get_tube_data(npos, d1, d2, num))
			lRes[#lRes+1] = dir
		end
	end
	return lRes
end

function Tube:update_after_place_tube(pos, placer, pointed_thing)
	local preferred_pos, fdir = get_player_data(self, placer, pointed_thing)
	local dir1, dir2, num_tubes = self:determine_tube_dirs(pos, preferred_pos, fdir)
	if dir1 == nil then
		return false
	end
	if self.valid_dirs[dir1] and self.valid_dirs[dir2] and tValidNum[num_tubes]then
		self.clbk_after_place_tube(get_tube_data(pos, dir1, dir2, num_tubes))
	end
	
	if num_tubes >= 1 then
		local npos, d1, d2, num = self:add_tube_dir(pos, dir1)
		if npos and self.valid_dirs[d1] and self.valid_dirs[d2] and tValidNum[num]then
			self.clbk_after_place_tube(get_tube_data(npos, d1, d2, num))
		end
	end
	
	if num_tubes >= 2 then
		local npos, d1, d2, num = self:add_tube_dir(pos, dir2)
		if npos and self.valid_dirs[d1] and self.valid_dirs[d2] and tValidNum[num]then
			self.clbk_after_place_tube(get_tube_data(npos, d1, d2, num))
		end
	end
	return true, dir1, dir2, num_tubes
end	
	
function Tube:update_after_dig_tube(pos, param2)
	local dir1, dir2 = self:decode_param2(pos, param2)
	
	local npos, d1, d2, num = self:del_tube_dir(pos, dir1)
	if npos and self.valid_dirs[d1] and self.valid_dirs[d2] and tValidNum[num]then
		self.clbk_after_place_tube(get_tube_data(npos, d1, d2, num))
	else
		dir1 = nil
	end
	
	npos, d1, d2, num = self:del_tube_dir(pos, dir2)
	if npos and self.valid_dirs[d1] and self.valid_dirs[d2] and tValidNum[num]then
		self.clbk_after_place_tube(get_tube_data(npos, d1, d2, num))
	else
		dir2 = nil
	end
	
	return dir1, dir2
end
