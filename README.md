# POSIX multithreading in LuaJIT.

Using a unique `lua_State` per thread (via [lua-lua](https://github.com/thenumbernine/lua-lua) ).

I spun this off of [CapsAdmin luajit-pureffi/threads.lua](https://github.com/CapsAdmin/luajit-pureffi/blob/main/threads.lua)
but moved the Lua calls into their own [library](https://github.com/thenumbernine/lua-lua),
and replaced the convenience of function-serialization and error-handling with code-injection,
which probably makes the result of this a lot more like [LuaLanes](https://github.com/LuaLanes/lanes).

# thread.lua

- `thread = Thread(code, [arg])` = wrapper for `pthread_create`.
- `Thread.__eq()` = wrapper for `pthread_equal`
- `Thread.__gc()` = calls `thread:close()` on garbage collection to close the Lua state.  Doesn't join / exit / anything the pthread, that is on you.
- `Thread.numThreads()` = returns the hardware concurrency via `sysconf`.
- `thread:join()` = wrapper for `pthread_join`
- `thread:exit([value])` = wrapper for `pthread_exit`
- `thread:detach()` = wrapper for `pthread_detach`
- `thread:self()` = wrapper for `pthread_self`
- `thread:close()` = closes the Lua state

# semaphore.lua

- `sem = Semaphore([n], [shared])` = wrapper for `sem_init`, with arguments reversed for precedence, where 'n' is the semaphore initial value (default 1), and `shared` is whether or not the semaphore is shared between processes.
- `Semaphore.__gc()` = calls `sem:destroy()` on garbage collection.
- `sem:wait()` = wrapper for `sem_wait`.  Returns true on success, false and error code on failure.
- `sem:post()` = wrapper for `sem_post`.  Returns true on success, false and error code on failure.
- `sem:destroy()` = wrapper for `sem_destroy`.  Returns true on success.

# mutex.lua

- `mutex = Mutex()` = wrapper for `pthread_mutex_init`.  No support for mutex attributes yet.
- `Mutex.__gc()` = calls `mutex:destroy()` on garbage collection.
- `mutex:lock()` = wrapper for `pthread_mutex_lock`.  Returns true on success, false and error code on fail.
- `mutex:unlock()` = wrapper for `pthread_mutex_unlock`.  Returns true on success, false and error code on fail.
- `mutex:unlockAndReturn(...)` = shorthand for calling `mutex:unlock()` and then returning forwarded arguments.  Errors on failure.  Used by the `mutex:scope()` function.
- `mutex:scope(f, ...)` = locks mutex, calls `f(...)`, unlocks mutex, and returns results.  Errors on failure.  This call is not protected, so if an error is raised then you have to unlock the mutex yourself.
