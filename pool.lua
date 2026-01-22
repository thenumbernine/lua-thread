require 'ext.gc'
local ffi = require 'ffi'
local template = require 'template'
local class = require 'ext.class'
local assert = require 'ext.assert'
local pthread = require 'ffi.req' 'c.pthread'
local Thread = require 'thread'
local Semaphore = require 'thread.semaphore'
local Mutex = require 'thread.mutex'

local numThreads = Thread.numThreads()

local ThreadPoolTypeCode = [[
struct {
	// each thread arg has its own thread arg, for the user
	// alternatively I could allow overloading & extending this struct ...
	void * userdata;

	pthread_mutex_t* poolMutex;

	// starts at 0, only access through poolMutex, threads get poolMutex then increment this
	// if it's at taskCount then set 'gotEmpty' so we can post to our semDone
	size_t taskIndex;

	// max # tasks
	size_t taskCount;

	// set this to end thread execution
	bool done;
}
]]
local ThreadPoolType = ffi.typeof(ThreadPoolTypeCode)

local ThreadPoolType_1 = ffi.typeof('$[1]', ThreadPoolType)

-- save code separately so the threads can cdef this too
-- TODO change design to be like Parallel: http://github.com/thenumbernine/Parallel
-- with critsec-mutex to access job pool, another mutex to notify when done
-- and only one semaphore-per-thread to notify to wakeup
local ThreadArgTypeCode = [[
struct {
	size_t threadIndex;

	//pointer to the shared threadpool info
	$ * pool;	// ThreadPoolType

	//each thread sets this when they are done
	sem_t *semDone;

	//tell each thread to wake up when pool:ready() is called
	sem_t *semReady;
}
]]
local ThreadArgType = ffi.typeof(ThreadArgTypeCode, ThreadPoolType)


-- TODO should semaphore be created here?
-- TODO how to override ThreadArgType?
local Worker = class()


local Pool = class()

Pool.Worker = Worker

local function getcode(self, code, i)
	local codetype = type(code)
	if codetype == 'nil' then
		return nil
	elseif codetype == 'string' then
	elseif codetype == 'table' then
		code = code[i]
	elseif codetype == 'function' then
		code = code(self, i-1)
	else
		error("can't interpret code of type "..codetype)
	end
	assert.type(code, 'string')
	return code
end

--[[
args:
	size = pool size, defaults to Thread.numThreads()
	code / initcode / donecode
		= string to provide worker code
			= table to provide worker code per index (1-based)
			= function(pool, index) to provide worker code per worker (0-based)
				where i is the 0-based index
	userdata = user defined cdata ptr or nil

-or-
args = function or string for it to be handled as args.code would be
--]]
function Pool:init(args)
	if type(args) ~= 'table' then args = {code = args} end
	self.size = self.size or Thread.numThreads()

	-- don't assign poolMutex until after all threads are ctor'd
	-- that will tell the closed()/__gc() that it's been fully init'd
	local poolMutex = Mutex()
	self.poolArg = ThreadPoolType_1()
	self.poolArg[0].poolMutex = poolMutex.id
	self.poolArg[0].done = false
	local userdata = args.userdata
	assert(type(userdata) == 'nil' or type(userdata) == 'cdata')
	self.poolArg[0].userdata = userdata

	for i=1,self.size do
		local worker = Worker()
		worker.semReady = Semaphore()
		worker.semDone = Semaphore()

		-- TODO how to allow the caller to override this
		local threadArg = ThreadArgType()
		threadArg.pool = self.poolArg
		threadArg.semDone = worker.semDone.id
		threadArg.semReady = worker.semReady.id
		threadArg.threadIndex = i-1
		worker.arg = threadArg

		local initcode = getcode(self, args.initcode, i)
		local code = getcode(self, args.code, i)
		local donecode = getcode(self, args.donecode, i)

		-- TODO in lua-lua, change the pcalls to use error handlers, AND REPORT THE ERRORS
		-- TODO how to separate init code vs update code and make it modular ...
		worker.thread = Thread(template([===[
local ffi = require 'ffi'
local assert = require 'ext.assert'
local Mutex = require 'thread.mutex'
local Semaphore = require 'thread.semaphore'

-- will ffi.C carry across?
-- because its the same luajit process?
-- nope, ffi.C is unique per lua-state
local ThreadPoolType = ffi.typeof[[<?=ThreadPoolTypeCode?>]]
local ThreadArgType = ffi.typeof([[<?=ThreadArgTypeCode?>]], ThreadPoolType)
local ThreadArgPtrType = ffi.typeof('$*', ThreadArgType)

-- holds semaphores etc of the thread
assert(arg, 'expected thread argument')
assert.type(arg, 'cdata')
arg = ffi.cast(ThreadArgPtrType, arg)
local pool = arg.pool
local threadIndex = arg.threadIndex
local userdata = pool.userdata

local poolMutex = Mutex:wrap(pool.poolMutex)
local semReady = Semaphore:wrap(arg.semReady)
local semDone = Semaphore:wrap(arg.semDone)

<?=initcode or ''?>

-- xpcall here and not inside the loop so we don't xpcall() multiple times
local results = table.pack(xpcall(function()
	while true do
		-- wait til 'pool:ready()' is called
		semReady:wait()

		local gotEmpty
		repeat
			poolMutex:lock()
			if pool.done then
				poolMutex:unlock()
				return
			end
			local task
			if pool.taskIndex < pool.taskCount then
				task = pool.taskIndex
				pool.taskIndex = pool.taskIndex + 1
			end
			if pool.taskIndex >= pool.taskCount then
				gotEmpty = true
			end
			poolMutex:unlock()

			if task then
				<?=code or ''?>
			end
		until gotEmpty

		-- tell 'pool:wait()' to finish
		semDone:post()
	end
end, function(err)
	return err..'\n'..debug.traceback()
end))

-- if `code` error'd then we still need to post semDone ...
if not results[1] then
	semDone:post()
	error(results[2])
end

-- should this be 'finally' code or nah?
-- or maybe let the caller clean up and donecode is a bad idea?
<?=donecode or ''?>

return table.unpack(results, 2, results.n)
]===],			{
					ThreadPoolTypeCode = ThreadPoolTypeCode,
					ThreadArgTypeCode = ThreadArgTypeCode,
					initcode = initcode,
					code = code,
					donecode = donecode,
				}),
			threadArg)

		self[i] = worker
	end

	-- only now asisgn poolMutex
	self.poolMutex = poolMutex
end

function Pool:ready(size)
	self.poolMutex:lock()
	self.poolArg[0].taskIndex = 0
	self.poolArg[0].taskCount = size or self.size
	self.poolMutex:unlock()

	for _,worker in ipairs(self) do
		worker.semReady:post()
	end
end

function Pool:wait()
	for _,worker in ipairs(self) do
		worker.semDone:wait()
	end
end

function Pool:cycle(size)
	self:ready(size)
	self:wait()
end

-- pool's closed
function Pool:closed()
	-- if we don't have the poolMutex then we can't really talk to the threads anymore
	-- so assume it's already closed
	if not self.poolMutex then return end

	-- set thread done flag so they will end and we can join them
	self.poolMutex:lock()
	self.poolArg[0].done = true
	self.poolMutex:unlock()

	for _,worker in ipairs(self) do
		-- resume so we can shut down
		worker.semReady:post()

		-- join <-> wait for it to return
		worker.thread:join()

		-- destroy semaphores
		worker.semDone:destroy()
		worker.semDone = nil
		worker.semReady:destroy()
		worker.semReady = nil

		-- destroy thread Lua state?
		-- nah. don't erase worker.thread so soon, the caller might want to examine thread.lua.global.results
		--worker.thread:close()
		--worker.thread = nil

		worker.arg.semReady = nil
		worker.arg.semDone = nil
		worker.arg.pool = nil
	end

	self.poolMutex:destroy()
	self.poolMutex = nil
end

function Pool:__gc()
	self:closed()
end

return Pool
