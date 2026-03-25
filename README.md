# POSIX multithreading in LuaJIT.

Using a unique `lua_State` per thread (via [lua-lua](https://github.com/thenumbernine/lua-lua) ).

I spun this off of [CapsAdmin luajit-pureffi/threads.lua](https://github.com/CapsAdmin/luajit-pureffi/blob/main/threads.lua)
but moved the Lua calls into their own [library](https://github.com/thenumbernine/lua-lua),
and added to the convenience of function-serialization and error-handling with an option for code-injection,
which probably makes the result of this a lot more like [LuaLanes](https://github.com/LuaLanes/lanes).

Windows compatability via [pthread4w](https://github.com/williamtu/pthread4w).

# pool.lua

This is a thread pool, made for fast repeated execution of tasks.

# lite.lua

This is a child-Lua-state that wraps and runs a function, either provided by code or by Lua function.  No threading is involved.

- `lite = Lite(arg)` = wrapper for a Lua state that accepts a string for Lua code, or a table containing `.code` or `.init`.
- `Lite.__gc()` = calls `Lite:close()` on garbage collection to close the Lua state.

- `lite:close()` = closes the Lua state.

- `lite.lua` = holds the child `lua_State`.

- `lite.funcptr` = If you passed `.code` into ctor then this holds the C function closure of the Lua function from the parent Lua state.

- `lite.lua.debug.getregistry().thread_funcs[funckey].funcptr` = holds the C function closure that the Lua function is cast to, in the child Lua state.
- `lite.lua.debug.getregistry().thread_funcs[funckey].safefunc` = holds the Lua function that is cast and run as the function in the child  Lua state.
- `lite.lua.debug.getregistry().thread_funcs[funckey].exitStatus` = upon finish, sets to `true` if succeeded and `false` if error occurred.
- `lite.lua.debug.getregistry().thread_funcs[funckey].errmsg ` = upon `exitStatus==false`, this will hold the error message.
- `lite.lua.debug.getregistry().thread_funcs[funckey].results ` = upon `exitStatus==true`, this will hold a table of all values returned from `code`.

- `lite:getExitStatus(funckey)` = gets the exit status of the function associated with `funckey`, which is a hex string of funcptr.
- `lite:getErrMsg(funckey)` = gets the error message of the function associated with `funckey`.

# thread.lua

This is an implementation of LiteThread but for pthread callbacks.

- `Thread = Lite:subclass()`

- `thread = Thread(code, [arg])` = wrapper for `pthread_create`.
- `Thread.__eq()` = wrapper for `pthread_equal`
- `Thread.numThreads()` = returns the hardware concurrency via `sysconf`.
- `thread:join()` = wrapper for `pthread_join`
- `thread:exit([value])` = wrapper for `pthread_exit`
- `thread:detach()` = wrapper for `pthread_detach`
- `thread:self()` = wrapper for `pthread_self`

- `thread.id` = holds the `pthread_t` of the thread.
- `thread.arg` = holds the `arg` passed to the ctor.
- `thread.funcptr` = holds the `funcptr` passed to the ctor.
- `thread.funckey` = holds the `funckey` of the `funcptr`

- `thread:getExitStatus()` = calls `lite:getExitStatus()` but using this function's saved `funckey`.
- `thread:getErrMsg()` = calls `lite:getErrMsg()` but using this function's saved `funckey`.
- `thread:getErr(extraMsg)` = if an error occurred in the child Lua state, returns false and any error that had occurred and captured in the lite child-Lua-state.  Returns true otherwise.
- `thread:showErr(extraMsg)` = if an error occured in the child Lua state, writes it to stderr.
- `thread:assertErr(extraMsg)` = if an error occurred in the child Lua state, throws an error in the parent Lua state.

# semaphore.lua

PThread library Semaphore wrapper class.

- `sem = Semaphore([n], [shared])` = wrapper for `sem_init`, with arguments reversed for precedence, where 'n' is the semaphore initial value (default 1), and `shared` is whether or not the semaphore is shared between processes.
- `Semaphore.__gc()` = calls `sem:destroy()` on garbage collection.
- `sem:wait()` = wrapper for `sem_wait`.  Returns true on success, false and error code on failure.
- `sem:post()` = wrapper for `sem_post`.  Returns true on success, false and error code on failure.
- `sem:destroy()` = wrapper for `sem_destroy`.  Returns true on success.
- `sem.id` = holds the `sem_t[1]`.

# mutex.lua

PThread library Mutex wrapper class.

- `mutex = Mutex()` = wrapper for `pthread_mutex_init`.  No support for mutex attributes yet.
- `Mutex.__gc()` = calls `mutex:destroy()` on garbage collection.
- `mutex:lock()` = wrapper for `pthread_mutex_lock`.  Returns true on success, false and error code on fail.
- `mutex:unlock()` = wrapper for `pthread_mutex_unlock`.  Returns true on success, false and error code on fail.
- `mutex:unlockAndReturn(...)` = shorthand for calling `mutex:unlock()` and then returning forwarded arguments.  Errors on failure.  Used by the `mutex:scope()` function.
- `mutex:scope(f, ...)` = locks mutex, calls `f(...)`, unlocks mutex, and returns results.  Errors on failure.  This call is not protected, so if an error is raised then you have to unlock the mutex yourself.
- `mutex.id` = holds the `pthread_mutex_t[1]`.
