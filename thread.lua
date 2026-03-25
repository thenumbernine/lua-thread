-- posix threads library
local ffi = require 'ffi'
local assert = require 'ext.assert'
local pthread = require 'ffi.req' 'c.pthread'
local unistd = require 'ffi.req' 'c.unistd'	-- sysconf
local LiteThread = require 'thread.lite'
local thread_assert = require 'thread.assert'

local voidp = ffi.typeof'void*'
local voidp_1 = ffi.typeof'void*[1]'
local pthread_t = ffi.typeof'pthread_t'
local pthread_t_1 = ffi.typeof'pthread_t[1]'


local Thread = LiteThread:subclass()

--[[
all args forwarded to Lite-Thread
with the addition of:
	arg = cdata to pass to the thread
--]]
function Thread:init(args)
	if type(args) == 'string' then
		args = {code=args}
	elseif type(args) == 'function' then
		args = {func=args}
	end
	assert.type(args, 'table')
	assert(args.code or args.func, "thread needs either .code or .func")

	-- do super init with empty state ...
	Thread.super.init(self)

	-- handle args.init now
	if args.init then
		args.init(self)
	end

	-- now build our wrapper ...
	self.threadFuncTypeName = args.threadFuncTypeName	-- allow override

	self.funcptr = self:createFuncPtr(
		-- threadFuncTypeName:
		self.threadFuncTypeName,
		-- initCode:
		[[
local func = ...			-- ... is func
]],
		-- function code
		[[
-- our xpcall function arg ...
local arg = ...
]]..(args.code or '')..[[
]]..(args.func and [[
do	-- separate code with a do / end block to prevent any call syntax from messing with the next statement
	func(...)
end
]] or ''),
		-- initCode ... args follow:
		args.func
	)

	-- used to access results from reg.thread_funcs[]
	self.funckey = bit.tohex(ffi.cast('uintptr_t', self.funcptr), bit.lshift(ffi.sizeof'uintptr_t', 1))

	local arg = args.arg
	self.arg = arg	-- store before cast, so nils stay nils, for ease of truth testing
	local argtype = type(arg)
	if not (argtype == 'nil' or argtype == 'cdata') then
		error("I don't know how to pass arg of type "..argtype.." into a new thread")
	end

	local id = pthread_t_1()
	thread_assert(pthread.pthread_create(
		id,
		nil,
		self.funcptr,
		ffi.cast(voidp, self.arg)
	), 'pthread_create')
	self.id = pthread_t(id[0])
end

-- wrap a previously created thread handle
-- static function
function Thread:wrap(id)
	return setmetatable({
		id = pthread_t(self.id),
		close = function() end,
	}, Thread)
end

function Thread:join()
	local result = voidp_1()
	thread_assert(pthread.pthread_join(self.id, result), 'pthread_join')
	return result[0]
end

-- should be called from the thread
function Thread:exit(value)
	pthread.pthread_exit(ffi.cast(voidp, value))
end

function Thread:detach()
	thread_assert(pthread.pthread_detach(self.id))
end

-- returns a pthread_t, not a Thread
-- I could wrap this in a Thread, but it'd still have no Lua state...
function Thread:self()
	return pthread.pthread_self()
end

function Thread.__eq(a,b)
	--[[ this seems like a nice thing for flexibility of testing Thread or pthread_t
	-- but then again LuaJIT goes and made its __index fail INTO AN ERROR INSTEAD OF JUST RETURNING NIL
	-- which I can circumvent using op.safeindex/xpcall
	-- but that'd slow things down a lot
	-- so instead this is only going to work for Thread objects
	a = a.id or a
	b = b.id or b
	--]]
	return 0 ~= pthread.pthread_equal(a.id, b.id)
end

-- TODO pthread_attr_* functions
-- TODO pthread_*sched* functions
-- TODO pthread_*cancel* functions
-- TODO pthread_*key* functions
-- TODO a lot more

function Thread.numThreads()
	return tonumber(unistd.sysconf(unistd._SC_NPROCESSORS_ONLN))
end



-- all these are a bit redundant ... why do I have this?
-- TODO any of these should verify that the pthread is no longer running first,
-- otherwise you will have two threads touching the same lua state at the same time

function Thread:getExitStatus()
	return Thread.super.getExitStatus(self, self.funckey)
end

function Thread:getErrMsg()
	return Thread.super.getErrMsg(self, self.funckey)
end

function Thread:getErr(msg)
	if self:getExitStatus() then return true end
	local errmsg = self:getErrMsg()
	return false, (msg and msg..' ' or 'thread '..tostring(self))..'error '..tostring(errmsg)
end

function Thread:showErr(msg)
	if self:getExitStatus() then return true end
	local errmsg = self:getErrMsg()
	io.stderr:write((msg and msg..' ' or 'thread '..tostring(self))..'error '..tostring(errmsg)..'\n')
end

function Thread:assertErr(msg)
	if self:getExitStatus() then return true end
	local _, errmsg = self:getErrMsg()
	error((msg and msg..' ' or 'thread '..tostring(self))..'error '..tostring(errmsg))
end


return Thread
