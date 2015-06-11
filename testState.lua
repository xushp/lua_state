require("./state")
local bor, band, bxor = bit.bor, bit.band, bit.bxor
local rshift, lshift = bit.rshift, bit.lshift
local STATE_STAND = 0
local STATE_RUN = 1
local STATE_ACCTACK = 2
local STATE_BUF = 3
local STATE_DEATH = 4
local MAX_BIT_CNT = 32
local STATE_MAX = 50
local MAX_MSG = 12
local MSG_DESTROY = 1
local MSG_INITIAL = 2
local SYS_SET_STATE = 1
local SYS_DEL_STATE = 2
local RT_NO,RT_ER,RT_DE,RT_OK = 0,-1,-2,1
local DENY = 0
local DELY = 3


local function stand(_self, _index, _msg)
	if _msg == MSG_INITIAL then
		print("stand init")
	elseif _msg == MSG_DESTROY	then
		print("stand destroy")
	end
end
local function run(_self, _index, _msg)
	if _msg == MSG_INITIAL then
		print("run init")
	elseif _msg == MSG_DESTROY	then
		print("run destroy")
	end
end
local function acctack(_self, _index, _msg)
	if _msg == MSG_INITIAL then
		print("acctack init")
	elseif _msg == MSG_DESTROY	then
		print("acctack destroy")
	end
end
local function death(_self, _index, _msg)
	if _msg == MSG_INITIAL then
		print("death init")
	elseif _msg == MSG_DESTROY	then
		print("death destroy")
	end
end
local function buf(_self, _index, _msg)
	if _msg == MSG_INITIAL then
		print("buf init")
	elseif _msg == MSG_DESTROY	then
		print("buf destroy")
	end
end
local function create_msg(_data, _msgid)
	return lshift(_data, 8) + _msgid
end

local rule = {
	[STATE_STAND+1] = 		{{1, 1, 1, 2, 1},["handler_"] = stand},
	[STATE_RUN+1] = 		{{1, 1, 1, 2, 1},["handler_"] = run},
	[STATE_ACCTACK+1] = 	{{3, 3, 1, 2, 1},["handler_"] = acctack},
	[STATE_BUF+1] = 		{{2, 2, 2, 2, 1},["handler_"] = buf},
	[STATE_DEATH+1] = 		{{0, 0, 0, 0, 0},["handler_"] = death},
}


local state = State:new()
state:init_state(rule)


state:post_message(create_msg(STATE_RUN, SYS_SET_STATE))
state:post_message(create_msg(STATE_ACCTACK,SYS_SET_STATE))
state:post_message(create_msg(STATE_STAND,SYS_SET_STATE))
state:process(1)
state:process(2)
state:post_message(create_msg(STATE_RUN, SYS_SET_STATE))
state:post_message(create_msg(STATE_BUF, SYS_SET_STATE))

state:process(3)
state:post_message(create_msg(STATE_RUN, SYS_SET_STATE))
state:del_state(STATE_ACCTACK)
state:process(4)

state:post_message(create_msg(STATE_DEATH, SYS_SET_STATE))

