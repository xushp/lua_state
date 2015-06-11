require "bit"
local bor, band, bxor,bnot = bit.bor, bit.band, bit.bxor, bit.bnot
local rshift, lshift = bit.rshift, bit.lshift
local MAX_BIT_CNT = 32
local STATE_MAX = 50
local MAX_MSG = 12
local MSG_DESTROY = 1
local MSG_INITIAL = 2
local SYS_SET_STATE = 1
local SYS_DEL_STATE = 2
local RT_NO,RT_ER,RT_DE,RT_OK = 0,-1,-2,1
local DENY = 0
local SWAP = 1
local DELY = 3
local STATE_STAND = 0
local MAX_RETRY = 2

local function set_bit(_nr, _addr)
	local mask = lshift(1, band(_nr, 0x1f))

	local index = rshift(_nr, 5) + 1
	_addr[index] = _addr[index] or 0
	_addr[index] = bor(_addr[index], mask)
end

local function clear_bit(_nr, _addr)
	local mask = lshift(1, band(_nr, 0x1f))
	local index = rshift(_nr, 5) + 1
	_addr[index] = band(_addr[index] ,bnot(mask))
end

local function test_bit(_nr, _addr)
	local mask = lshift(1, band(_nr, 0x1f))
	local index = rshift(_nr, 5) + 1
	return band(_addr[index], mask) ~= 0
end
function get_zero_of_tail(_value)
	for i=1, MAX_BIT_CNT do
		mask = lshift(1, i-1)
		if band(mask, _value)~=0 then
			return i-1
		end
	end
	return MAX_BIT_CNT
end
local function find_next_set_bit(_addr, _offset)
	local index = rshift(_offset, 5) + 1
	local len = #_addr
	local bit = band(_offset, 31)
	if bit ~= 0 then
		local t = band(_addr[index], lshift(0xffffffff, bit))
		if t ~= 0 then
			return get_zero_of_tail(t) + lshift(index-1, 5)
		end
		index=index+1
	end
	for i = index, len do
		if _addr[i] ~= 0 then
			return get_zero_of_tail(_addr[i]) + lshift(i-1, 5)
		end
	end
end
------------------------------------------
---	State
---
---
-------------------------------------------
State = {

}
function State:new(_o)
	_o = _o or {}
	setmetatable(_o, {__index = State})
	_o:init()
	return _o
end
function State:init()
	self["run_set_"] = {}
	self["v_state_"] = {}
	self["msg_queue_"] = {}
	self["qhead_"] = 1
	self["qtail_"] = 1
	self["msg_times_"] = 0
end

function State:del_state(_index)
	local run_set = self.run_set_
	local v_state = self.v_state_
	if _index >= 0 and _index < STATE_MAX then
		if test_bit(_index, run_set) then
			clear_bit(_index, run_set)
			if (v_state[_index+1].handler_) then
				v_state[_index+1].handler_(self, index, MSG_DESTROY);
			end
			return RT_OK
		end
	end
	return RT_ER;
end

function State:post_message(_msg, _p0, _p1, _p2, _p3)
	local msg_queue = self.msg_queue_
	if self.qhead_ == self.qtail_ then
		local rt =  self:send_message(_msg, _p0, _p1, _p2, _p3)
		if rt ~= RT_DE then
			return rt
		end
	end
	if self.qtail_-self.qhead_ < MAX_MSG then
		index = (self.qtail_-1)%MAX_MSG+1
		msg_queue[index] = msg_queue[index] or {}
		msg_queue[index][1] = _msg
		msg_queue[index][2] = _p0
		msg_queue[index][3] = _p1
		msg_queue[index][4] = _p2
		msg_queue[index][5] = _p3
		self.qtail_ = self.qtail_+1
		return RT_DE
	end
	return RT_ER
end

function State:send_message(_msg, _p0, _p1, _p2, _p3)
	local msg_id = band(_msg, 0x000000ff)
	local state = band(rshift(_msg, 8), 0x0000ffff)
	local run_set = self.run_set_
	if msg_id == SYS_SET_STATE then
		if state >= 0 and state < STATE_MAX then
			local v_state = self.v_state_[state+1]
			local deny = self.v_state_[state+1].deny_
			local dely = self.v_state_[state+1].dely_
			local swap = self.v_state_[state+1].swap_
			for i, set in ipairs(deny) do
				if band(set, run_set[i]) ~= 0 then
					return RT_ER
				end
			end

			for i, set in ipairs(dely) do
				if (band(set, run_set[i])) ~= 0 then
					return RT_DE
				end
			end
			local index = -1
			while true do
				index = find_next_set_bit(run_set, index+1)
				if not index then
					break
				end
				if test_bit(index, swap) then
					clear_bit(index, run_set)
					if self.v_state_[index+1].handler_ then
						self.v_state_[index+1].handler_(self, index, MSG_DESTROY, 1, 0 ,0, 0)
					end
				end
			end
			set_bit(state, run_set)
			if v_state.handler_ then
				v_state.handler_(self, state, MSG_INITIAL, _p0, _p1, _p2, _p3)
			end

		end
	elseif msg_id == SYS_DEL_STATE then
		if state >= 0 and state < STATE_MAX then
			self:del_state(state)
		end
	end
	return RT_OK
end

function State:init_state(rule_)
	local len = #rule_
	if len > STATE_MAX then
		return nil
	end
	local n = STATE_MAX/MAX_BIT_CNT + 1
	for i = 1, n, 1 do
		self.run_set_[i] = 0

	end

	local v_state = self.v_state_
	for i = 1, #rule_ do
		if not v_state[i] then
			v_state[i] = {}
		end
		v_state[i].swap_ = {}
		v_state[i].dely_ = {}
		v_state[i].deny_ = {}
		for k = 1, n, 1 do
			v_state[i].swap_[k] = 0
			v_state[i].dely_[k] = 0
			v_state[i].deny_[k] = 0
		end
	end

	for i, row in ipairs(rule_) do
		v_state[i].handler_ = row.handler_
		for j, state in ipairs(row[1]) do
			if state == DENY then
				set_bit(i-1, v_state[j].deny_)
			elseif state == DELY then
				set_bit(i-1, v_state[j].dely_)
			elseif state == SWAP then
				set_bit(i-1, v_state[j].swap_)
			end
		end
	end
end

function State:process(_frame)
	print(string.format("--------------------- frame: %d begin -----------------", _frame ) )
	while self.qhead_ < self.qtail_ do
		local index = self.qhead_ % MAX_MSG
		local msg_info = self.msg_queue_[index]
		local rt = self:send_message(msg_info[1], msg_info[2], msg_info[3], msg_info[4], msg_info[5])
		if rt == RT_DE then
			self.msg_times_ = self.msg_times_ + 1
			if self.msg_times_ >= MAX_RETRY then
				print("retry too much time,state number:" .. msg_info[1])
				self.qhead_ = self.qhead_ + 1;
				self.msg_times_ = 0
			else
				break
			end
		else
			self.msg_times = 0
			self.qhead_ = self.qhead_ + 1
		end
	end
	local index = 0
	local stand_state = self.v_state_[STATE_STAND+1]
	local run_set = self.run_set_
	for i = 1, #stand_state.deny_ do
		if band(stand_state.deny_[i], run_set[i]) ~= 0 then
			break
		end
		if band(stand_state.dely_[i], run_set[i]) ~= 0 then
			break
		end
		if band(stand_state.swap_[i], run_set[i]) ~= 0 then
			break
		end
		index = i
	end

	if index >= #stand_state.deny_ then
		set_bit(STATE_STAND, run_set)
	end
print(string.format("--------------------- frame: %d end -----------------", _frame ) )
end



