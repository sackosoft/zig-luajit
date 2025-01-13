Hello, you're going to be assisting me with the translation of Lua's C API to clean and idiomatic
Zig. We are building Zig language bindings for the C API and need to ensure that every type and
function represented in the Lua API is accessible to developers using the Zig API. I'm going
to ask you to perform a translation task for a particular language element. Please respond to the
prompt with the structure described below. Please do not provide any explanation, description, or
any other discussion other than filling in the requested information with the appropriate structured
response.

Response Format: Please extract the requested details and provide your response as well-formated Zig
code following the pattern described below. Note, <descriptions in angle brackets> (<, >) are instructions
for you to fill in with details from the documentation content. Plain text or symbols should be
copied directly. E.g. the forward slashes (/) and `Stack Behavior` text should appear exactly (when
relevant).

```zig
/// <Documented language element description (you will need to reformat links to be proper https hyper links)
///
/// From: <Original of C API language element>
/// Refer to: https://www.lua.org/manual/5.1/manual.html#<Fragment>
/// Stack Behavior: [-o, +p, x]
<Languge element translated to Zig>
```

In order for you to fill in the requested details you will be given the HTML segment from the Lua
documentation. Please copy over (and reformat as necessary) all description except C-Language specific
details (such as example code). You'll also need to know the convention for stack behavior, here is how
the Lua documentation describes the stack behavior text convention:

> The first field, o, is how many elements the function pops from the stack. The second field, p, is how many elements
the function pushes onto the stack. (Any function always pushes its results after popping its arguments.) A field in the form
x|y means the function can push (or pop) x or y elements, depending on the situation; an interrogation mark '?' means
that we cannot know how many elements the function pops/pushes by looking only at its arguments (e.g., they may depend
on what is on the stack). The third field, x, tells whether the function may throw errors: '-' means the function never
throws any error; 'm' means the function may throw an error only due to not enough memory; 'e' means the function may
throw other kinds of errors; 'v' means the function may throw an error on purpose.

Here's an example input:

```html_example(please learn from but do not translate)
<hr><h3><a name="lua_gettable"><code>lua_gettable</code></a></h3><p>
<span class="apii">[-1, +1, <em>e</em>]</span>
<pre>void lua_gettable (lua_State *L, int index);</pre>

<p>
Pushes onto the stack the value <code>t[k]</code>,
where <code>t</code> is the value at the given valid index
and <code>k</code> is the value at the top of the stack.


<p>
This function pops the key from the stack
(putting the resulting value in its place).
As in Lua, this function may trigger a metamethod
for the "index" event (see <a href="#2.8">&sect;2.8</a>).
```

And what I'm expecting you to produce:

```zig
/// Pushes onto the stack the value t[k], where t is the value at the given valid index and k is the value
/// at the top of the stack. This function pops the key from the stack (putting the resulting value in its place).
/// As in Lua, this function may trigger a metamethod for the "index" event (see https://www.lua.org/manual/5.1/manual.html#2.8).
///
/// From: void lua_gettable(lua_State *L, int index);
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_gettable
/// Stack Behavior: [-1, +1, e]
pub fn getTable(lua: *Lua, index: i32) LuaType;
```

Some final thoughts to help clarify what I'm asking of you:
* Do not implement the functions. Simplify document and translate the languge element as idiomatically as you can.
* Translate links in the HTML to absolute URI and document fragment links in plain text.
* Convert the language elements to the format described above for functions.

Below are a set of language elements and their associated documentation that I want you to translate.
Please provide the translated output in the expected format with no  other discussion, explanation or output.
Please attempt to translate every single language element you encounter below.

```html_documentation(please translate)
<hr><h3><a name="lua_Alloc"><code>lua_Alloc</code></a></h3>
<pre>typedef void * (*lua_Alloc) (void *ud,
                             void *ptr,
                             size_t osize,
                             size_t nsize);</pre>

<p>
The type of the memory-allocation function used by Lua states.
The allocator function must provide a
functionality similar to <code>realloc</code>,
but not exactly the same.
Its arguments are
<code>ud</code>, an opaque pointer passed to <a href="#lua_newstate"><code>lua_newstate</code></a>;
<code>ptr</code>, a pointer to the block being allocated/reallocated/freed;
<code>osize</code>, the original size of the block;
<code>nsize</code>, the new size of the block.
<code>ptr</code> is <code>NULL</code> if and only if <code>osize</code> is zero.
When <code>nsize</code> is zero, the allocator must return <code>NULL</code>;
if <code>osize</code> is not zero,
it should free the block pointed to by <code>ptr</code>.
When <code>nsize</code> is not zero, the allocator returns <code>NULL</code>
if and only if it cannot fill the request.
When <code>nsize</code> is not zero and <code>osize</code> is zero,
the allocator should behave like <code>malloc</code>.
When <code>nsize</code> and <code>osize</code> are not zero,
the allocator behaves like <code>realloc</code>.
Lua assumes that the allocator never fails when
<code>osize &gt;= nsize</code>.<p>
Here is a simple implementation for the allocator function.
It is used in the auxiliary library by <a href="#luaL_newstate"><code>luaL_newstate</code></a>.

<pre>
     static void *l_alloc (void *ud, void *ptr, size_t osize,
                                                size_t nsize) {
       (void)ud;  (void)osize;  /* not used */
       if (nsize == 0) {
         free(ptr);
         return NULL;
       }
       else
         return realloc(ptr, nsize);
     }
</pre><p>
This code assumes
that <code>free(NULL)</code> has no effect and that
<code>realloc(NULL, size)</code> is equivalent to <code>malloc(size)</code>.
ANSI&nbsp;C ensures both behaviors.
<hr><h3><a name="lua_atpanic"><code>lua_atpanic</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>lua_CFunction lua_atpanic (lua_State *L, lua_CFunction panicf);</pre>

<p>
Sets a new panic function and returns the old one.<p>
If an error happens outside any protected environment,
Lua calls a <em>panic function</em>
and then calls <code>exit(EXIT_FAILURE)</code>,
thus exiting the host application.
Your panic function can avoid this exit by
never returning (e.g., doing a long jump).<p>
The panic function can access the error message at the top of the stack.
<hr><h3><a name="lua_call"><code>lua_call</code></a></h3><p>
<span class="apii">[-(nargs + 1), +nresults, <em>e</em>]</span>
<pre>void lua_call (lua_State *L, int nargs, int nresults);</pre>

<p>
Calls a function.<p>
To call a function you must use the following protocol:
first, the function to be called is pushed onto the stack;
then, the arguments to the function are pushed
in direct order;
that is, the first argument is pushed first.
Finally you call <a href="#lua_call"><code>lua_call</code></a>;
<code>nargs</code> is the number of arguments that you pushed onto the stack.
All arguments and the function value are popped from the stack
when the function is called.
The function results are pushed onto the stack when the function returns.
The number of results is adjusted to <code>nresults</code>,
unless <code>nresults</code> is <a name="pdf-LUA_MULTRET"><code>LUA_MULTRET</code></a>.
In this case, <em>all</em> results from the function are pushed.
Lua takes care that the returned values fit into the stack space.
The function results are pushed onto the stack in direct order
(the first result is pushed first),
so that after the call the last result is on the top of the stack.<p>
Any error inside the called function is propagated upwards
(with a <code>longjmp</code>).<p>
The following example shows how the host program can do the
equivalent to this Lua code:

<pre>
     a = f("how", t.x, 14)
</pre><p>
Here it is in&nbsp;C:

<pre>
     lua_getfield(L, LUA_GLOBALSINDEX, "f"); /* function to be called */
     lua_pushstring(L, "how");                        /* 1st argument */
     lua_getfield(L, LUA_GLOBALSINDEX, "t");   /* table to be indexed */
     lua_getfield(L, -1, "x");        /* push result of t.x (2nd arg) */
     lua_remove(L, -2);                  /* remove 't' from the stack */
     lua_pushinteger(L, 14);                          /* 3rd argument */
     lua_call(L, 3, 1);     /* call 'f' with 3 arguments and 1 result */
     lua_setfield(L, LUA_GLOBALSINDEX, "a");        /* set global 'a' */
</pre><p>
Note that the code above is "balanced":
at its end, the stack is back to its original configuration.
This is considered good programming practice.
<hr><h3><a name="lua_CFunction"><code>lua_CFunction</code></a></h3>
<pre>typedef int (*lua_CFunction) (lua_State *L);</pre>

<p>
Type for C&nbsp;functions.<p>
In order to communicate properly with Lua,
a C&nbsp;function must use the following protocol,
which defines the way parameters and results are passed:
a C&nbsp;function receives its arguments from Lua in its stack
in direct order (the first argument is pushed first).
So, when the function starts,
<code>lua_gettop(L)</code> returns the number of arguments received by the function.
The first argument (if any) is at index 1
and its last argument is at index <code>lua_gettop(L)</code>.
To return values to Lua, a C&nbsp;function just pushes them onto the stack,
in direct order (the first result is pushed first),
and returns the number of results.
Any other value in the stack below the results will be properly
discarded by Lua.
Like a Lua function, a C&nbsp;function called by Lua can also return
many results.<p>
As an example, the following function receives a variable number
of numerical arguments and returns their average and sum:

<pre>
     static int foo (lua_State *L) {
       int n = lua_gettop(L);    /* number of arguments */
       lua_Number sum = 0;
       int i;
       for (i = 1; i &lt;= n; i++) {
         if (!lua_isnumber(L, i)) {
           lua_pushstring(L, "incorrect argument");
           lua_error(L);
         }
         sum += lua_tonumber(L, i);
       }
       lua_pushnumber(L, sum/n);        /* first result */
       lua_pushnumber(L, sum);         /* second result */
       return 2;                   /* number of results */
     }
</pre>


<hr><h3><a name="lua_checkstack"><code>lua_checkstack</code></a></h3><p>
<span class="apii">[-0, +0, <em>m</em>]</span>
<pre>int lua_checkstack (lua_State *L, int extra);</pre>

<p>
Ensures that there are at least <code>extra</code> free stack slots in the stack.
It returns false if it cannot grow the stack to that size.
This function never shrinks the stack;
if the stack is already larger than the new size,
it is left unchanged.
<hr><h3><a name="lua_close"><code>lua_close</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>void lua_close (lua_State *L);</pre>

<p>
Destroys all objects in the given Lua state
(calling the corresponding garbage-collection metamethods, if any)
and frees all dynamic memory used by this state.
On several platforms, you may not need to call this function,
because all resources are naturally released when the host program ends.
On the other hand, long-running programs,
such as a daemon or a web server,
might need to release states as soon as they are not needed,
to avoid growing too large.
<hr><h3><a name="lua_concat"><code>lua_concat</code></a></h3><p>
<span class="apii">[-n, +1, <em>e</em>]</span>
<pre>void lua_concat (lua_State *L, int n);</pre>

<p>
Concatenates the <code>n</code> values at the top of the stack,
pops them, and leaves the result at the top.
If <code>n</code>&nbsp;is&nbsp;1, the result is the single value on the stack
(that is, the function does nothing);
if <code>n</code> is 0, the result is the empty string.
Concatenation is performed following the usual semantics of Lua
(see <a href="#2.5.4">&sect;2.5.4</a>).
<hr><h3><a name="lua_cpcall"><code>lua_cpcall</code></a></h3><p>
<span class="apii">[-0, +(0|1), <em>-</em>]</span>
<pre>int lua_cpcall (lua_State *L, lua_CFunction func, void *ud);</pre>

<p>
Calls the C&nbsp;function <code>func</code> in protected mode.
<code>func</code> starts with only one element in its stack,
a light userdata containing <code>ud</code>.
In case of errors,
<a href="#lua_cpcall"><code>lua_cpcall</code></a> returns the same error codes as <a href="#lua_pcall"><code>lua_pcall</code></a>,
plus the error object on the top of the stack;
otherwise, it returns zero, and does not change the stack.
All values returned by <code>func</code> are discarded.
<hr><h3><a name="lua_createtable"><code>lua_createtable</code></a></h3><p>
<span class="apii">[-0, +1, <em>m</em>]</span>
<pre>void lua_createtable (lua_State *L, int narr, int nrec);</pre>

<p>
Creates a new empty table and pushes it onto the stack.
The new table has space pre-allocated
for <code>narr</code> array elements and <code>nrec</code> non-array elements.
This pre-allocation is useful when you know exactly how many elements
the table will have.
Otherwise you can use the function <a href="#lua_newtable"><code>lua_newtable</code></a>.
<hr><h3><a name="lua_dump"><code>lua_dump</code></a></h3><p>
<span class="apii">[-0, +0, <em>m</em>]</span>
<pre>int lua_dump (lua_State *L, lua_Writer writer, void *data);</pre>

<p>
Dumps a function as a binary chunk.
Receives a Lua function on the top of the stack
and produces a binary chunk that,
if loaded again,
results in a function equivalent to the one dumped.
As it produces parts of the chunk,
<a href="#lua_dump"><code>lua_dump</code></a> calls function <code>writer</code> (see <a href="#lua_Writer"><code>lua_Writer</code></a>)
with the given <code>data</code>
to write them.<p>
The value returned is the error code returned by the last
call to the writer;
0&nbsp;means no errors.<p>
This function does not pop the Lua function from the stack.
<hr><h3><a name="lua_equal"><code>lua_equal</code></a></h3><p>
<span class="apii">[-0, +0, <em>e</em>]</span>
<pre>int lua_equal (lua_State *L, int index1, int index2);</pre>

<p>
Returns 1 if the two values in acceptable indices <code>index1</code> and
<code>index2</code> are equal,
following the semantics of the Lua <code>==</code> operator
(that is, may call metamethods).
Otherwise returns&nbsp;0.
Also returns&nbsp;0 if any of the indices is non valid.
<hr><h3><a name="lua_error"><code>lua_error</code></a></h3><p>
<span class="apii">[-1, +0, <em>v</em>]</span>
<pre>int lua_error (lua_State *L);</pre>

<p>
Generates a Lua error.
The error message (which can actually be a Lua value of any type)
must be on the stack top.
This function does a long jump,
and therefore never returns.
(see <a href="#luaL_error"><code>luaL_error</code></a>).
<hr><h3><a name="lua_gc"><code>lua_gc</code></a></h3><p>
<span class="apii">[-0, +0, <em>e</em>]</span>
<pre>int lua_gc (lua_State *L, int what, int data);</pre>

<p>
Controls the garbage collector.<p>
This function performs several tasks,
according to the value of the parameter <code>what</code>:

<ul>

<li><b><code>LUA_GCSTOP</code>:</b>
stops the garbage collector.
</li>

<li><b><code>LUA_GCRESTART</code>:</b>
restarts the garbage collector.
</li>

<li><b><code>LUA_GCCOLLECT</code>:</b>
performs a full garbage-collection cycle.
</li>

<li><b><code>LUA_GCCOUNT</code>:</b>
returns the current amount of memory (in Kbytes) in use by Lua.
</li>

<li><b><code>LUA_GCCOUNTB</code>:</b>
returns the remainder of dividing the current amount of bytes of
memory in use by Lua by 1024.
</li>

<li><b><code>LUA_GCSTEP</code>:</b>
performs an incremental step of garbage collection.
The step "size" is controlled by <code>data</code>
(larger values mean more steps) in a non-specified way.
If you want to control the step size
you must experimentally tune the value of <code>data</code>.
The function returns 1 if the step finished a
garbage-collection cycle.
</li>

<li><b><code>LUA_GCSETPAUSE</code>:</b>
sets <code>data</code> as the new value
for the <em>pause</em> of the collector (see <a href="#2.10">&sect;2.10</a>).
The function returns the previous value of the pause.
</li>

<li><b><code>LUA_GCSETSTEPMUL</code>:</b>
sets <code>data</code> as the new value for the <em>step multiplier</em> of
the collector (see <a href="#2.10">&sect;2.10</a>).
The function returns the previous value of the step multiplier.
</li>

</ul>


<hr><h3><a name="lua_getallocf"><code>lua_getallocf</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>lua_Alloc lua_getallocf (lua_State *L, void **ud);</pre>

<p>
Returns the memory-allocation function of a given state.
If <code>ud</code> is not <code>NULL</code>, Lua stores in <code>*ud</code> the
opaque pointer passed to <a href="#lua_newstate"><code>lua_newstate</code></a>.
<hr><h3><a name="lua_getfenv"><code>lua_getfenv</code></a></h3><p>
<span class="apii">[-0, +1, <em>-</em>]</span>
<pre>void lua_getfenv (lua_State *L, int index);</pre>

<p>
Pushes onto the stack the environment table of
the value at the given index.
<hr><h3><a name="lua_getfield"><code>lua_getfield</code></a></h3><p>
<span class="apii">[-0, +1, <em>e</em>]</span>
<pre>void lua_getfield (lua_State *L, int index, const char *k);</pre>

<p>
Pushes onto the stack the value <code>t[k]</code>,
where <code>t</code> is the value at the given valid index.
As in Lua, this function may trigger a metamethod
for the "index" event (see <a href="#2.8">&sect;2.8</a>).
<hr><h3><a name="lua_getglobal"><code>lua_getglobal</code></a></h3><p>
<span class="apii">[-0, +1, <em>e</em>]</span>
<pre>void lua_getglobal (lua_State *L, const char *name);</pre>

<p>
Pushes onto the stack the value of the global <code>name</code>.
It is defined as a macro:

<pre>
     #define lua_getglobal(L,s)  lua_getfield(L, LUA_GLOBALSINDEX, s)
</pre>


<hr><h3><a name="lua_getmetatable"><code>lua_getmetatable</code></a></h3><p>
<span class="apii">[-0, +(0|1), <em>-</em>]</span>
<pre>int lua_getmetatable (lua_State *L, int index);</pre>

<p>
Pushes onto the stack the metatable of the value at the given
acceptable index.
If the index is not valid,
or if the value does not have a metatable,
the function returns&nbsp;0 and pushes nothing on the stack.
<hr><h3><a name="lua_gettable"><code>lua_gettable</code></a></h3><p>
<span class="apii">[-1, +1, <em>e</em>]</span>
<pre>void lua_gettable (lua_State *L, int index);</pre>

<p>
Pushes onto the stack the value <code>t[k]</code>,
where <code>t</code> is the value at the given valid index
and <code>k</code> is the value at the top of the stack.<p>
This function pops the key from the stack
(putting the resulting value in its place).
As in Lua, this function may trigger a metamethod
for the "index" event (see <a href="#2.8">&sect;2.8</a>).
<hr><h3><a name="lua_gettop"><code>lua_gettop</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>int lua_gettop (lua_State *L);</pre>

<p>
Returns the index of the top element in the stack.
Because indices start at&nbsp;1,
this result is equal to the number of elements in the stack
(and so 0&nbsp;means an empty stack).
<hr><h3><a name="lua_insert"><code>lua_insert</code></a></h3><p>
<span class="apii">[-1, +1, <em>-</em>]</span>
<pre>void lua_insert (lua_State *L, int index);</pre>

<p>
Moves the top element into the given valid index,
shifting up the elements above this index to open space.
Cannot be called with a pseudo-index,
because a pseudo-index is not an actual stack position.
<hr><h3><a name="lua_Integer"><code>lua_Integer</code></a></h3>
<pre>typedef ptrdiff_t lua_Integer;</pre>

<p>
The type used by the Lua API to represent integral values.<p>
By default it is a <code>ptrdiff_t</code>,
which is usually the largest signed integral type the machine handles
"comfortably".
<hr><h3><a name="lua_isboolean"><code>lua_isboolean</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>int lua_isboolean (lua_State *L, int index);</pre>

<p>
Returns 1 if the value at the given acceptable index has type boolean,
and 0&nbsp;otherwise.
<hr><h3><a name="lua_iscfunction"><code>lua_iscfunction</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>int lua_iscfunction (lua_State *L, int index);</pre>

<p>
Returns 1 if the value at the given acceptable index is a C&nbsp;function,
and 0&nbsp;otherwise.
<hr><h3><a name="lua_isfunction"><code>lua_isfunction</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>int lua_isfunction (lua_State *L, int index);</pre>

<p>
Returns 1 if the value at the given acceptable index is a function
(either C or Lua), and 0&nbsp;otherwise.
<hr><h3><a name="lua_islightuserdata"><code>lua_islightuserdata</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>int lua_islightuserdata (lua_State *L, int index);</pre>

<p>
Returns 1 if the value at the given acceptable index is a light userdata,
and 0&nbsp;otherwise.
<hr><h3><a name="lua_isnil"><code>lua_isnil</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>int lua_isnil (lua_State *L, int index);</pre>

<p>
Returns 1 if the value at the given acceptable index is <b>nil</b>,
and 0&nbsp;otherwise.
<hr><h3><a name="lua_isnone"><code>lua_isnone</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>int lua_isnone (lua_State *L, int index);</pre>

<p>
Returns 1 if the given acceptable index is not valid
(that is, it refers to an element outside the current stack),
and 0&nbsp;otherwise.
<hr><h3><a name="lua_isnoneornil"><code>lua_isnoneornil</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>int lua_isnoneornil (lua_State *L, int index);</pre>

<p>
Returns 1 if the given acceptable index is not valid
(that is, it refers to an element outside the current stack)
or if the value at this index is <b>nil</b>,
and 0&nbsp;otherwise.
<hr><h3><a name="lua_isnumber"><code>lua_isnumber</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>int lua_isnumber (lua_State *L, int index);</pre>

<p>
Returns 1 if the value at the given acceptable index is a number
or a string convertible to a number,
and 0&nbsp;otherwise.
<hr><h3><a name="lua_isstring"><code>lua_isstring</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>int lua_isstring (lua_State *L, int index);</pre>

<p>
Returns 1 if the value at the given acceptable index is a string
or a number (which is always convertible to a string),
and 0&nbsp;otherwise.
<hr><h3><a name="lua_istable"><code>lua_istable</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>int lua_istable (lua_State *L, int index);</pre>

<p>
Returns 1 if the value at the given acceptable index is a table,
and 0&nbsp;otherwise.
<hr><h3><a name="lua_isthread"><code>lua_isthread</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>int lua_isthread (lua_State *L, int index);</pre>

<p>
Returns 1 if the value at the given acceptable index is a thread,
and 0&nbsp;otherwise.
<hr><h3><a name="lua_isuserdata"><code>lua_isuserdata</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>int lua_isuserdata (lua_State *L, int index);</pre>

<p>
Returns 1 if the value at the given acceptable index is a userdata
(either full or light), and 0&nbsp;otherwise.
<hr><h3><a name="lua_lessthan"><code>lua_lessthan</code></a></h3><p>
<span class="apii">[-0, +0, <em>e</em>]</span>
<pre>int lua_lessthan (lua_State *L, int index1, int index2);</pre>

<p>
Returns 1 if the value at acceptable index <code>index1</code> is smaller
than the value at acceptable index <code>index2</code>,
following the semantics of the Lua <code>&lt;</code> operator
(that is, may call metamethods).
Otherwise returns&nbsp;0.
Also returns&nbsp;0 if any of the indices is non valid.
<hr><h3><a name="lua_load"><code>lua_load</code></a></h3><p>
<span class="apii">[-0, +1, <em>-</em>]</span>
<pre>int lua_load (lua_State *L,
              lua_Reader reader,
              void *data,
              const char *chunkname);</pre>

<p>
Loads a Lua chunk.
If there are no errors,
<a href="#lua_load"><code>lua_load</code></a> pushes the compiled chunk as a Lua
function on top of the stack.
Otherwise, it pushes an error message.
The return values of <a href="#lua_load"><code>lua_load</code></a> are:

<ul>

<li><b>0:</b> no errors;</li>

<li><b><a name="pdf-LUA_ERRSYNTAX"><code>LUA_ERRSYNTAX</code></a>:</b>
syntax error during pre-compilation;</li>

<li><b><a href="#pdf-LUA_ERRMEM"><code>LUA_ERRMEM</code></a>:</b>
memory allocation error.</li>

</ul>

<p>
This function only loads a chunk;
it does not run it.<p>
<a href="#lua_load"><code>lua_load</code></a> automatically detects whether the chunk is text or binary,
and loads it accordingly (see program <code>luac</code>).<p>
The <a href="#lua_load"><code>lua_load</code></a> function uses a user-supplied <code>reader</code> function
to read the chunk (see <a href="#lua_Reader"><code>lua_Reader</code></a>).
The <code>data</code> argument is an opaque value passed to the reader function.<p>
The <code>chunkname</code> argument gives a name to the chunk,
which is used for error messages and in debug information (see <a href="#3.8">&sect;3.8</a>).
<hr><h3><a name="lua_newstate"><code>lua_newstate</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>lua_State *lua_newstate (lua_Alloc f, void *ud);</pre>

<p>
Creates a new, independent state.
Returns <code>NULL</code> if cannot create the state
(due to lack of memory).
The argument <code>f</code> is the allocator function;
Lua does all memory allocation for this state through this function.
The second argument, <code>ud</code>, is an opaque pointer that Lua
simply passes to the allocator in every call.
<hr><h3><a name="lua_newtable"><code>lua_newtable</code></a></h3><p>
<span class="apii">[-0, +1, <em>m</em>]</span>
<pre>void lua_newtable (lua_State *L);</pre>

<p>
Creates a new empty table and pushes it onto the stack.
It is equivalent to <code>lua_createtable(L, 0, 0)</code>.
<hr><h3><a name="lua_newthread"><code>lua_newthread</code></a></h3><p>
<span class="apii">[-0, +1, <em>m</em>]</span>
<pre>lua_State *lua_newthread (lua_State *L);</pre>

<p>
Creates a new thread, pushes it on the stack,
and returns a pointer to a <a href="#lua_State"><code>lua_State</code></a> that represents this new thread.
The new state returned by this function shares with the original state
all global objects (such as tables),
but has an independent execution stack.<p>
There is no explicit function to close or to destroy a thread.
Threads are subject to garbage collection,
like any Lua object.
<hr><h3><a name="lua_newuserdata"><code>lua_newuserdata</code></a></h3><p>
<span class="apii">[-0, +1, <em>m</em>]</span>
<pre>void *lua_newuserdata (lua_State *L, size_t size);</pre>

<p>
This function allocates a new block of memory with the given size,
pushes onto the stack a new full userdata with the block address,
and returns this address.<p>
Userdata represent C&nbsp;values in Lua.
A <em>full userdata</em> represents a block of memory.
It is an object (like a table):
you must create it, it can have its own metatable,
and you can detect when it is being collected.
A full userdata is only equal to itself (under raw equality).<p>
When Lua collects a full userdata with a <code>gc</code> metamethod,
Lua calls the metamethod and marks the userdata as finalized.
When this userdata is collected again then
Lua frees its corresponding memory.
<hr><h3><a name="lua_next"><code>lua_next</code></a></h3><p>
<span class="apii">[-1, +(2|0), <em>e</em>]</span>
<pre>int lua_next (lua_State *L, int index);</pre>

<p>
Pops a key from the stack,
and pushes a key-value pair from the table at the given index
(the "next" pair after the given key).
If there are no more elements in the table,
then <a href="#lua_next"><code>lua_next</code></a> returns 0 (and pushes nothing).<p>
A typical traversal looks like this:

<pre>
     /* table is in the stack at index 't' */
     lua_pushnil(L);  /* first key */
     while (lua_next(L, t) != 0) {
       /* uses 'key' (at index -2) and 'value' (at index -1) */
       printf("%s - %s\n",
              lua_typename(L, lua_type(L, -2)),
              lua_typename(L, lua_type(L, -1)));
       /* removes 'value'; keeps 'key' for next iteration */
       lua_pop(L, 1);
     }
</pre>

<p>
While traversing a table,
do not call <a href="#lua_tolstring"><code>lua_tolstring</code></a> directly on a key,
unless you know that the key is actually a string.
Recall that <a href="#lua_tolstring"><code>lua_tolstring</code></a> <em>changes</em>
the value at the given index;
this confuses the next call to <a href="#lua_next"><code>lua_next</code></a>.
<hr><h3><a name="lua_Number"><code>lua_Number</code></a></h3>
<pre>typedef double lua_Number;</pre>

<p>
The type of numbers in Lua.
By default, it is double, but that can be changed in <code>luaconf.h</code>.<p>
Through the configuration file you can change
Lua to operate with another type for numbers (e.g., float or long).
<hr><h3><a name="lua_objlen"><code>lua_objlen</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>size_t lua_objlen (lua_State *L, int index);</pre>

<p>
Returns the "length" of the value at the given acceptable index:
for strings, this is the string length;
for tables, this is the result of the length operator ('<code>#</code>');
for userdata, this is the size of the block of memory allocated
for the userdata;
for other values, it is&nbsp;0.
<hr><h3><a name="lua_pcall"><code>lua_pcall</code></a></h3><p>
<span class="apii">[-(nargs + 1), +(nresults|1), <em>-</em>]</span>
<pre>int lua_pcall (lua_State *L, int nargs, int nresults, int errfunc);</pre>

<p>
Calls a function in protected mode.<p>
Both <code>nargs</code> and <code>nresults</code> have the same meaning as
in <a href="#lua_call"><code>lua_call</code></a>.
If there are no errors during the call,
<a href="#lua_pcall"><code>lua_pcall</code></a> behaves exactly like <a href="#lua_call"><code>lua_call</code></a>.
However, if there is any error,
<a href="#lua_pcall"><code>lua_pcall</code></a> catches it,
pushes a single value on the stack (the error message),
and returns an error code.
Like <a href="#lua_call"><code>lua_call</code></a>,
<a href="#lua_pcall"><code>lua_pcall</code></a> always removes the function
and its arguments from the stack.<p>
If <code>errfunc</code> is 0,
then the error message returned on the stack
is exactly the original error message.
Otherwise, <code>errfunc</code> is the stack index of an
<em>error handler function</em>.
(In the current implementation, this index cannot be a pseudo-index.)
In case of runtime errors,
this function will be called with the error message
and its return value will be the message returned on the stack by <a href="#lua_pcall"><code>lua_pcall</code></a>.<p>
Typically, the error handler function is used to add more debug
information to the error message, such as a stack traceback.
Such information cannot be gathered after the return of <a href="#lua_pcall"><code>lua_pcall</code></a>,
since by then the stack has unwound.<p>
The <a href="#lua_pcall"><code>lua_pcall</code></a> function returns 0 in case of success
or one of the following error codes
(defined in <code>lua.h</code>):

<ul>

<li><b><a name="pdf-LUA_ERRRUN"><code>LUA_ERRRUN</code></a>:</b>
a runtime error.
</li>

<li><b><a name="pdf-LUA_ERRMEM"><code>LUA_ERRMEM</code></a>:</b>
memory allocation error.
For such errors, Lua does not call the error handler function.
</li>

<li><b><a name="pdf-LUA_ERRERR"><code>LUA_ERRERR</code></a>:</b>
error while running the error handler function.
</li>

</ul>


<hr><h3><a name="lua_pop"><code>lua_pop</code></a></h3><p>
<span class="apii">[-n, +0, <em>-</em>]</span>
<pre>void lua_pop (lua_State *L, int n);</pre>

<p>
Pops <code>n</code> elements from the stack.
<hr><h3><a name="lua_pushboolean"><code>lua_pushboolean</code></a></h3><p>
<span class="apii">[-0, +1, <em>-</em>]</span>
<pre>void lua_pushboolean (lua_State *L, int b);</pre>

<p>
Pushes a boolean value with value <code>b</code> onto the stack.
<hr><h3><a name="lua_pushcclosure"><code>lua_pushcclosure</code></a></h3><p>
<span class="apii">[-n, +1, <em>m</em>]</span>
<pre>void lua_pushcclosure (lua_State *L, lua_CFunction fn, int n);</pre>

<p>
Pushes a new C&nbsp;closure onto the stack.<p>
When a C&nbsp;function is created,
it is possible to associate some values with it,
thus creating a C&nbsp;closure (see <a href="#3.4">&sect;3.4</a>);
these values are then accessible to the function whenever it is called.
To associate values with a C&nbsp;function,
first these values should be pushed onto the stack
(when there are multiple values, the first value is pushed first).
Then <a href="#lua_pushcclosure"><code>lua_pushcclosure</code></a>
is called to create and push the C&nbsp;function onto the stack,
with the argument <code>n</code> telling how many values should be
associated with the function.
<a href="#lua_pushcclosure"><code>lua_pushcclosure</code></a> also pops these values from the stack.<p>
The maximum value for <code>n</code> is 255.
<hr><h3><a name="lua_pushcfunction"><code>lua_pushcfunction</code></a></h3><p>
<span class="apii">[-0, +1, <em>m</em>]</span>
<pre>void lua_pushcfunction (lua_State *L, lua_CFunction f);</pre>

<p>
Pushes a C&nbsp;function onto the stack.
This function receives a pointer to a C function
and pushes onto the stack a Lua value of type <code>function</code> that,
when called, invokes the corresponding C&nbsp;function.<p>
Any function to be registered in Lua must
follow the correct protocol to receive its parameters
and return its results (see <a href="#lua_CFunction"><code>lua_CFunction</code></a>).<p>
<code>lua_pushcfunction</code> is defined as a macro:

<pre>
     #define lua_pushcfunction(L,f)  lua_pushcclosure(L,f,0)
</pre>


<hr><h3><a name="lua_pushfstring"><code>lua_pushfstring</code></a></h3><p>
<span class="apii">[-0, +1, <em>m</em>]</span>
<pre>const char *lua_pushfstring (lua_State *L, const char *fmt, ...);</pre>

<p>
Pushes onto the stack a formatted string
and returns a pointer to this string.
It is similar to the C&nbsp;function <code>sprintf</code>,
but has some important differences:

<ul>

<li>
You do not have to allocate space for the result:
the result is a Lua string and Lua takes care of memory allocation
(and deallocation, through garbage collection).
</li>

<li>
The conversion specifiers are quite restricted.
There are no flags, widths, or precisions.
The conversion specifiers can only be
'<code>%%</code>' (inserts a '<code>%</code>' in the string),
'<code>%s</code>' (inserts a zero-terminated string, with no size restrictions),
'<code>%f</code>' (inserts a <a href="#lua_Number"><code>lua_Number</code></a>),
'<code>%p</code>' (inserts a pointer as a hexadecimal numeral),
'<code>%d</code>' (inserts an <code>int</code>), and
'<code>%c</code>' (inserts an <code>int</code> as a character).
</li>

</ul>


<hr><h3><a name="lua_pushinteger"><code>lua_pushinteger</code></a></h3><p>
<span class="apii">[-0, +1, <em>-</em>]</span>
<pre>void lua_pushinteger (lua_State *L, lua_Integer n);</pre>

<p>
Pushes a number with value <code>n</code> onto the stack.
<hr><h3><a name="lua_pushlightuserdata"><code>lua_pushlightuserdata</code></a></h3><p>
<span class="apii">[-0, +1, <em>-</em>]</span>
<pre>void lua_pushlightuserdata (lua_State *L, void *p);</pre>

<p>
Pushes a light userdata onto the stack.<p>
Userdata represent C&nbsp;values in Lua.
A <em>light userdata</em> represents a pointer.
It is a value (like a number):
you do not create it, it has no individual metatable,
and it is not collected (as it was never created).
A light userdata is equal to "any"
light userdata with the same C&nbsp;address.
<hr><h3><a name="lua_pushliteral"><code>lua_pushliteral</code></a></h3><p>
<span class="apii">[-0, +1, <em>m</em>]</span>
<pre>void lua_pushliteral (lua_State *L, const char *s);</pre>

<p>
This macro is equivalent to <a href="#lua_pushlstring"><code>lua_pushlstring</code></a>,
but can be used only when <code>s</code> is a literal string.
In these cases, it automatically provides the string length.
<hr><h3><a name="lua_pushlstring"><code>lua_pushlstring</code></a></h3><p>
<span class="apii">[-0, +1, <em>m</em>]</span>
<pre>void lua_pushlstring (lua_State *L, const char *s, size_t len);</pre>

<p>
Pushes the string pointed to by <code>s</code> with size <code>len</code>
onto the stack.
Lua makes (or reuses) an internal copy of the given string,
so the memory at <code>s</code> can be freed or reused immediately after
the function returns.
The string can contain embedded zeros.
<hr><h3><a name="lua_pushnil"><code>lua_pushnil</code></a></h3><p>
<span class="apii">[-0, +1, <em>-</em>]</span>
<pre>void lua_pushnil (lua_State *L);</pre>

<p>
Pushes a nil value onto the stack.
<hr><h3><a name="lua_pushnumber"><code>lua_pushnumber</code></a></h3><p>
<span class="apii">[-0, +1, <em>-</em>]</span>
<pre>void lua_pushnumber (lua_State *L, lua_Number n);</pre>

<p>
Pushes a number with value <code>n</code> onto the stack.
<hr><h3><a name="lua_pushstring"><code>lua_pushstring</code></a></h3><p>
<span class="apii">[-0, +1, <em>m</em>]</span>
<pre>void lua_pushstring (lua_State *L, const char *s);</pre>

<p>
Pushes the zero-terminated string pointed to by <code>s</code>
onto the stack.
Lua makes (or reuses) an internal copy of the given string,
so the memory at <code>s</code> can be freed or reused immediately after
the function returns.
The string cannot contain embedded zeros;
it is assumed to end at the first zero.
<hr><h3><a name="lua_pushthread"><code>lua_pushthread</code></a></h3><p>
<span class="apii">[-0, +1, <em>-</em>]</span>
<pre>int lua_pushthread (lua_State *L);</pre>

<p>
Pushes the thread represented by <code>L</code> onto the stack.
Returns 1 if this thread is the main thread of its state.
<hr><h3><a name="lua_pushvalue"><code>lua_pushvalue</code></a></h3><p>
<span class="apii">[-0, +1, <em>-</em>]</span>
<pre>void lua_pushvalue (lua_State *L, int index);</pre>

<p>
Pushes a copy of the element at the given valid index
onto the stack.
<hr><h3><a name="lua_pushvfstring"><code>lua_pushvfstring</code></a></h3><p>
<span class="apii">[-0, +1, <em>m</em>]</span>
<pre>const char *lua_pushvfstring (lua_State *L,
                              const char *fmt,
                              va_list argp);</pre>

<p>
Equivalent to <a href="#lua_pushfstring"><code>lua_pushfstring</code></a>, except that it receives a <code>va_list</code>
instead of a variable number of arguments.
<hr><h3><a name="lua_rawequal"><code>lua_rawequal</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>int lua_rawequal (lua_State *L, int index1, int index2);</pre>

<p>
Returns 1 if the two values in acceptable indices <code>index1</code> and
<code>index2</code> are primitively equal
(that is, without calling metamethods).
Otherwise returns&nbsp;0.
Also returns&nbsp;0 if any of the indices are non valid.
<hr><h3><a name="lua_rawget"><code>lua_rawget</code></a></h3><p>
<span class="apii">[-1, +1, <em>-</em>]</span>
<pre>void lua_rawget (lua_State *L, int index);</pre>

<p>
Similar to <a href="#lua_gettable"><code>lua_gettable</code></a>, but does a raw access
(i.e., without metamethods).
<hr><h3><a name="lua_rawgeti"><code>lua_rawgeti</code></a></h3><p>
<span class="apii">[-0, +1, <em>-</em>]</span>
<pre>void lua_rawgeti (lua_State *L, int index, int n);</pre>

<p>
Pushes onto the stack the value <code>t[n]</code>,
where <code>t</code> is the value at the given valid index.
The access is raw;
that is, it does not invoke metamethods.
<hr><h3><a name="lua_rawset"><code>lua_rawset</code></a></h3><p>
<span class="apii">[-2, +0, <em>m</em>]</span>
<pre>void lua_rawset (lua_State *L, int index);</pre>

<p>
Similar to <a href="#lua_settable"><code>lua_settable</code></a>, but does a raw assignment
(i.e., without metamethods).
<hr><h3><a name="lua_rawseti"><code>lua_rawseti</code></a></h3><p>
<span class="apii">[-1, +0, <em>m</em>]</span>
<pre>void lua_rawseti (lua_State *L, int index, int n);</pre>

<p>
Does the equivalent of <code>t[n] = v</code>,
where <code>t</code> is the value at the given valid index
and <code>v</code> is the value at the top of the stack.<p>
This function pops the value from the stack.
The assignment is raw;
that is, it does not invoke metamethods.
<hr><h3><a name="lua_Reader"><code>lua_Reader</code></a></h3>
<pre>typedef const char * (*lua_Reader) (lua_State *L,
                                    void *data,
                                    size_t *size);</pre>

<p>
The reader function used by <a href="#lua_load"><code>lua_load</code></a>.
Every time it needs another piece of the chunk,
<a href="#lua_load"><code>lua_load</code></a> calls the reader,
passing along its <code>data</code> parameter.
The reader must return a pointer to a block of memory
with a new piece of the chunk
and set <code>size</code> to the block size.
The block must exist until the reader function is called again.
To signal the end of the chunk,
the reader must return <code>NULL</code> or set <code>size</code> to zero.
The reader function may return pieces of any size greater than zero.
<hr><h3><a name="lua_register"><code>lua_register</code></a></h3><p>
<span class="apii">[-0, +0, <em>e</em>]</span>
<pre>void lua_register (lua_State *L,
                   const char *name,
                   lua_CFunction f);</pre>

<p>
Sets the C function <code>f</code> as the new value of global <code>name</code>.
It is defined as a macro:

<pre>
     #define lua_register(L,n,f) \
            (lua_pushcfunction(L, f), lua_setglobal(L, n))
</pre>


<hr><h3><a name="lua_remove"><code>lua_remove</code></a></h3><p>
<span class="apii">[-1, +0, <em>-</em>]</span>
<pre>void lua_remove (lua_State *L, int index);</pre>

<p>
Removes the element at the given valid index,
shifting down the elements above this index to fill the gap.
Cannot be called with a pseudo-index,
because a pseudo-index is not an actual stack position.
<hr><h3><a name="lua_replace"><code>lua_replace</code></a></h3><p>
<span class="apii">[-1, +0, <em>-</em>]</span>
<pre>void lua_replace (lua_State *L, int index);</pre>

<p>
Moves the top element into the given position (and pops it),
without shifting any element
(therefore replacing the value at the given position).
<hr><h3><a name="lua_resume"><code>lua_resume</code></a></h3><p>
<span class="apii">[-?, +?, <em>-</em>]</span>
<pre>int lua_resume (lua_State *L, int narg);</pre>

<p>
Starts and resumes a coroutine in a given thread.<p>
To start a coroutine, you first create a new thread
(see <a href="#lua_newthread"><code>lua_newthread</code></a>);
then you push onto its stack the main function plus any arguments;
then you call <a href="#lua_resume"><code>lua_resume</code></a>,
with <code>narg</code> being the number of arguments.
This call returns when the coroutine suspends or finishes its execution.
When it returns, the stack contains all values passed to <a href="#lua_yield"><code>lua_yield</code></a>,
or all values returned by the body function.
<a href="#lua_resume"><code>lua_resume</code></a> returns
<a href="#pdf-LUA_YIELD"><code>LUA_YIELD</code></a> if the coroutine yields,
0 if the coroutine finishes its execution
without errors,
or an error code in case of errors (see <a href="#lua_pcall"><code>lua_pcall</code></a>).
In case of errors,
the stack is not unwound,
so you can use the debug API over it.
The error message is on the top of the stack.
To restart a coroutine, you put on its stack only the values to
be passed as results from <code>yield</code>,
and then call <a href="#lua_resume"><code>lua_resume</code></a>.
<hr><h3><a name="lua_setallocf"><code>lua_setallocf</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>void lua_setallocf (lua_State *L, lua_Alloc f, void *ud);</pre>

<p>
Changes the allocator function of a given state to <code>f</code>
with user data <code>ud</code>.
<hr><h3><a name="lua_setfenv"><code>lua_setfenv</code></a></h3><p>
<span class="apii">[-1, +0, <em>-</em>]</span>
<pre>int lua_setfenv (lua_State *L, int index);</pre>

<p>
Pops a table from the stack and sets it as
the new environment for the value at the given index.
If the value at the given index is
neither a function nor a thread nor a userdata,
<a href="#lua_setfenv"><code>lua_setfenv</code></a> returns 0.
Otherwise it returns 1.
<hr><h3><a name="lua_setfield"><code>lua_setfield</code></a></h3><p>
<span class="apii">[-1, +0, <em>e</em>]</span>
<pre>void lua_setfield (lua_State *L, int index, const char *k);</pre>

<p>
Does the equivalent to <code>t[k] = v</code>,
where <code>t</code> is the value at the given valid index
and <code>v</code> is the value at the top of the stack.<p>
This function pops the value from the stack.
As in Lua, this function may trigger a metamethod
for the "newindex" event (see <a href="#2.8">&sect;2.8</a>).
<hr><h3><a name="lua_setglobal"><code>lua_setglobal</code></a></h3><p>
<span class="apii">[-1, +0, <em>e</em>]</span>
<pre>void lua_setglobal (lua_State *L, const char *name);</pre>

<p>
Pops a value from the stack and
sets it as the new value of global <code>name</code>.
It is defined as a macro:

<pre>
     #define lua_setglobal(L,s)   lua_setfield(L, LUA_GLOBALSINDEX, s)
</pre>


<hr><h3><a name="lua_setmetatable"><code>lua_setmetatable</code></a></h3><p>
<span class="apii">[-1, +0, <em>-</em>]</span>
<pre>int lua_setmetatable (lua_State *L, int index);</pre>

<p>
Pops a table from the stack and
sets it as the new metatable for the value at the given
acceptable index.
<hr><h3><a name="lua_settable"><code>lua_settable</code></a></h3><p>
<span class="apii">[-2, +0, <em>e</em>]</span>
<pre>void lua_settable (lua_State *L, int index);</pre>

<p>
Does the equivalent to <code>t[k] = v</code>,
where <code>t</code> is the value at the given valid index,
<code>v</code> is the value at the top of the stack,
and <code>k</code> is the value just below the top.<p>
This function pops both the key and the value from the stack.
As in Lua, this function may trigger a metamethod
for the "newindex" event (see <a href="#2.8">&sect;2.8</a>).
<hr><h3><a name="lua_settop"><code>lua_settop</code></a></h3><p>
<span class="apii">[-?, +?, <em>-</em>]</span>
<pre>void lua_settop (lua_State *L, int index);</pre>

<p>
Accepts any acceptable index, or&nbsp;0,
and sets the stack top to this index.
If the new top is larger than the old one,
then the new elements are filled with <b>nil</b>.
If <code>index</code> is&nbsp;0, then all stack elements are removed.
<hr><h3><a name="lua_State"><code>lua_State</code></a></h3>
<pre>typedef struct lua_State lua_State;</pre>

<p>
Opaque structure that keeps the whole state of a Lua interpreter.
The Lua library is fully reentrant:
it has no global variables.
All information about a state is kept in this structure.<p>
A pointer to this state must be passed as the first argument to
every function in the library, except to <a href="#lua_newstate"><code>lua_newstate</code></a>,
which creates a Lua state from scratch.
<hr><h3><a name="lua_status"><code>lua_status</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>int lua_status (lua_State *L);</pre>

<p>
Returns the status of the thread <code>L</code>.<p>
The status can be 0 for a normal thread,
an error code if the thread finished its execution with an error,
or <a name="pdf-LUA_YIELD"><code>LUA_YIELD</code></a> if the thread is suspended.
<hr><h3><a name="lua_toboolean"><code>lua_toboolean</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>int lua_toboolean (lua_State *L, int index);</pre>

<p>
Converts the Lua value at the given acceptable index to a C&nbsp;boolean
value (0&nbsp;or&nbsp;1).
Like all tests in Lua,
<a href="#lua_toboolean"><code>lua_toboolean</code></a> returns 1 for any Lua value
different from <b>false</b> and <b>nil</b>;
otherwise it returns 0.
It also returns 0 when called with a non-valid index.
(If you want to accept only actual boolean values,
use <a href="#lua_isboolean"><code>lua_isboolean</code></a> to test the value's type.)
<hr><h3><a name="lua_tocfunction"><code>lua_tocfunction</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>lua_CFunction lua_tocfunction (lua_State *L, int index);</pre>

<p>
Converts a value at the given acceptable index to a C&nbsp;function.
That value must be a C&nbsp;function;
otherwise, returns <code>NULL</code>.
<hr><h3><a name="lua_tointeger"><code>lua_tointeger</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>lua_Integer lua_tointeger (lua_State *L, int index);</pre>

<p>
Converts the Lua value at the given acceptable index
to the signed integral type <a href="#lua_Integer"><code>lua_Integer</code></a>.
The Lua value must be a number or a string convertible to a number
(see <a href="#2.2.1">&sect;2.2.1</a>);
otherwise, <a href="#lua_tointeger"><code>lua_tointeger</code></a> returns&nbsp;0.<p>
If the number is not an integer,
it is truncated in some non-specified way.
<hr><h3><a name="lua_tolstring"><code>lua_tolstring</code></a></h3><p>
<span class="apii">[-0, +0, <em>m</em>]</span>
<pre>const char *lua_tolstring (lua_State *L, int index, size_t *len);</pre>

<p>
Converts the Lua value at the given acceptable index to a C&nbsp;string.
If <code>len</code> is not <code>NULL</code>,
it also sets <code>*len</code> with the string length.
The Lua value must be a string or a number;
otherwise, the function returns <code>NULL</code>.
If the value is a number,
then <a href="#lua_tolstring"><code>lua_tolstring</code></a> also
<em>changes the actual value in the stack to a string</em>.
(This change confuses <a href="#lua_next"><code>lua_next</code></a>
when <a href="#lua_tolstring"><code>lua_tolstring</code></a> is applied to keys during a table traversal.)<p>
<a href="#lua_tolstring"><code>lua_tolstring</code></a> returns a fully aligned pointer
to a string inside the Lua state.
This string always has a zero ('<code>\0</code>')
after its last character (as in&nbsp;C),
but can contain other zeros in its body.
Because Lua has garbage collection,
there is no guarantee that the pointer returned by <a href="#lua_tolstring"><code>lua_tolstring</code></a>
will be valid after the corresponding value is removed from the stack.
<hr><h3><a name="lua_tonumber"><code>lua_tonumber</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>lua_Number lua_tonumber (lua_State *L, int index);</pre>

<p>
Converts the Lua value at the given acceptable index
to the C&nbsp;type <a href="#lua_Number"><code>lua_Number</code></a> (see <a href="#lua_Number"><code>lua_Number</code></a>).
The Lua value must be a number or a string convertible to a number
(see <a href="#2.2.1">&sect;2.2.1</a>);
otherwise, <a href="#lua_tonumber"><code>lua_tonumber</code></a> returns&nbsp;0.
<hr><h3><a name="lua_topointer"><code>lua_topointer</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>const void *lua_topointer (lua_State *L, int index);</pre>

<p>
Converts the value at the given acceptable index to a generic
C&nbsp;pointer (<code>void*</code>).
The value can be a userdata, a table, a thread, or a function;
otherwise, <a href="#lua_topointer"><code>lua_topointer</code></a> returns <code>NULL</code>.
Different objects will give different pointers.
There is no way to convert the pointer back to its original value.<p>
Typically this function is used only for debug information.
<hr><h3><a name="lua_tostring"><code>lua_tostring</code></a></h3><p>
<span class="apii">[-0, +0, <em>m</em>]</span>
<pre>const char *lua_tostring (lua_State *L, int index);</pre>

<p>
Equivalent to <a href="#lua_tolstring"><code>lua_tolstring</code></a> with <code>len</code> equal to <code>NULL</code>.
<hr><h3><a name="lua_tothread"><code>lua_tothread</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>lua_State *lua_tothread (lua_State *L, int index);</pre>

<p>
Converts the value at the given acceptable index to a Lua thread
(represented as <code>lua_State*</code>).
This value must be a thread;
otherwise, the function returns <code>NULL</code>.
<hr><h3><a name="lua_touserdata"><code>lua_touserdata</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>void *lua_touserdata (lua_State *L, int index);</pre>

<p>
If the value at the given acceptable index is a full userdata,
returns its block address.
If the value is a light userdata,
returns its pointer.
Otherwise, returns <code>NULL</code>.
<hr><h3><a name="lua_type"><code>lua_type</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>int lua_type (lua_State *L, int index);</pre>

<p>
Returns the type of the value in the given acceptable index,
or <code>LUA_TNONE</code> for a non-valid index
(that is, an index to an "empty" stack position).
The types returned by <a href="#lua_type"><code>lua_type</code></a> are coded by the following constants
defined in <code>lua.h</code>:
<code>LUA_TNIL</code>,
<code>LUA_TNUMBER</code>,
<code>LUA_TBOOLEAN</code>,
<code>LUA_TSTRING</code>,
<code>LUA_TTABLE</code>,
<code>LUA_TFUNCTION</code>,
<code>LUA_TUSERDATA</code>,
<code>LUA_TTHREAD</code>,
and
<code>LUA_TLIGHTUSERDATA</code>.
<hr><h3><a name="lua_typename"><code>lua_typename</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>const char *lua_typename  (lua_State *L, int tp);</pre>

<p>
Returns the name of the type encoded by the value <code>tp</code>,
which must be one the values returned by <a href="#lua_type"><code>lua_type</code></a>.
<hr><h3><a name="lua_Writer"><code>lua_Writer</code></a></h3>
<pre>typedef int (*lua_Writer) (lua_State *L,
                           const void* p,
                           size_t sz,
                           void* ud);</pre>

<p>
The type of the writer function used by <a href="#lua_dump"><code>lua_dump</code></a>.
Every time it produces another piece of chunk,
<a href="#lua_dump"><code>lua_dump</code></a> calls the writer,
passing along the buffer to be written (<code>p</code>),
its size (<code>sz</code>),
and the <code>data</code> parameter supplied to <a href="#lua_dump"><code>lua_dump</code></a>.<p>
The writer returns an error code:
0&nbsp;means no errors;
any other value means an error and stops <a href="#lua_dump"><code>lua_dump</code></a> from
calling the writer again.
<hr><h3><a name="lua_xmove"><code>lua_xmove</code></a></h3><p>
<span class="apii">[-?, +?, <em>-</em>]</span>
<pre>void lua_xmove (lua_State *from, lua_State *to, int n);</pre>

<p>
Exchange values between different threads of the <em>same</em> global state.<p>
This function pops <code>n</code> values from the stack <code>from</code>,
and pushes them onto the stack <code>to</code>.
<hr><h3><a name="lua_yield"><code>lua_yield</code></a></h3><p>
<span class="apii">[-?, +?, <em>-</em>]</span>
<pre>int lua_yield  (lua_State *L, int nresults);</pre>

<p>
Yields a coroutine.<p>
This function should only be called as the
return expression of a C&nbsp;function, as follows:

<pre>
     return lua_yield (L, nresults);
</pre><p>
When a C&nbsp;function calls <a href="#lua_yield"><code>lua_yield</code></a> in that way,
the running coroutine suspends its execution,
and the call to <a href="#lua_resume"><code>lua_resume</code></a> that started this coroutine returns.
The parameter <code>nresults</code> is the number of values from the stack
that are passed as results to <a href="#lua_resume"><code>lua_resume</code></a>.


<hr><h3><a name="luaL_addchar"><code>luaL_addchar</code></a></h3><p>
<span class="apii">[-0, +0, <em>m</em>]</span>
<pre>void luaL_addchar (luaL_Buffer *B, char c);</pre>

<p>
Adds the character <code>c</code> to the buffer <code>B</code>
(see <a href="#luaL_Buffer"><code>luaL_Buffer</code></a>).
<hr><h3><a name="luaL_addlstring"><code>luaL_addlstring</code></a></h3><p>
<span class="apii">[-0, +0, <em>m</em>]</span>
<pre>void luaL_addlstring (luaL_Buffer *B, const char *s, size_t l);</pre>

<p>
Adds the string pointed to by <code>s</code> with length <code>l</code> to
the buffer <code>B</code>
(see <a href="#luaL_Buffer"><code>luaL_Buffer</code></a>).
The string may contain embedded zeros.
<hr><h3><a name="luaL_addsize"><code>luaL_addsize</code></a></h3><p>
<span class="apii">[-0, +0, <em>m</em>]</span>
<pre>void luaL_addsize (luaL_Buffer *B, size_t n);</pre>

<p>
Adds to the buffer <code>B</code> (see <a href="#luaL_Buffer"><code>luaL_Buffer</code></a>)
a string of length <code>n</code> previously copied to the
buffer area (see <a href="#luaL_prepbuffer"><code>luaL_prepbuffer</code></a>).
<hr><h3><a name="luaL_addstring"><code>luaL_addstring</code></a></h3><p>
<span class="apii">[-0, +0, <em>m</em>]</span>
<pre>void luaL_addstring (luaL_Buffer *B, const char *s);</pre>

<p>
Adds the zero-terminated string pointed to by <code>s</code>
to the buffer <code>B</code>
(see <a href="#luaL_Buffer"><code>luaL_Buffer</code></a>).
The string may not contain embedded zeros.
<hr><h3><a name="luaL_addvalue"><code>luaL_addvalue</code></a></h3><p>
<span class="apii">[-1, +0, <em>m</em>]</span>
<pre>void luaL_addvalue (luaL_Buffer *B);</pre>

<p>
Adds the value at the top of the stack
to the buffer <code>B</code>
(see <a href="#luaL_Buffer"><code>luaL_Buffer</code></a>).
Pops the value.<p>
This is the only function on string buffers that can (and must)
be called with an extra element on the stack,
which is the value to be added to the buffer.
<hr><h3><a name="luaL_argcheck"><code>luaL_argcheck</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>void luaL_argcheck (lua_State *L,
                    int cond,
                    int narg,
                    const char *extramsg);</pre>

<p>
Checks whether <code>cond</code> is true.
If not, raises an error with the following message,
where <code>func</code> is retrieved from the call stack:

<pre>
     bad argument #&lt;narg&gt; to &lt;func&gt; (&lt;extramsg&gt;)
</pre>


<hr><h3><a name="luaL_argerror"><code>luaL_argerror</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>int luaL_argerror (lua_State *L, int narg, const char *extramsg);</pre>

<p>
Raises an error with the following message,
where <code>func</code> is retrieved from the call stack:

<pre>
     bad argument #&lt;narg&gt; to &lt;func&gt; (&lt;extramsg&gt;)
</pre>

<p>
This function never returns,
but it is an idiom to use it in C&nbsp;functions
as <code>return luaL_argerror(<em>args</em>)</code>.
<hr><h3><a name="luaL_Buffer"><code>luaL_Buffer</code></a></h3>
<pre>typedef struct luaL_Buffer luaL_Buffer;</pre>

<p>
Type for a <em>string buffer</em>.<p>
A string buffer allows C&nbsp;code to build Lua strings piecemeal.
Its pattern of use is as follows:

<ul>

<li>First you declare a variable <code>b</code> of type <a href="#luaL_Buffer"><code>luaL_Buffer</code></a>.</li>

<li>Then you initialize it with a call <code>luaL_buffinit(L, &amp;b)</code>.</li>

<li>
Then you add string pieces to the buffer calling any of
the <code>luaL_add*</code> functions.
</li>

<li>
You finish by calling <code>luaL_pushresult(&amp;b)</code>.
This call leaves the final string on the top of the stack.
</li>

</ul>

<p>
During its normal operation,
a string buffer uses a variable number of stack slots.
So, while using a buffer, you cannot assume that you know where
the top of the stack is.
You can use the stack between successive calls to buffer operations
as long as that use is balanced;
that is,
when you call a buffer operation,
the stack is at the same level
it was immediately after the previous buffer operation.
(The only exception to this rule is <a href="#luaL_addvalue"><code>luaL_addvalue</code></a>.)
After calling <a href="#luaL_pushresult"><code>luaL_pushresult</code></a> the stack is back to its
level when the buffer was initialized,
plus the final string on its top.
<hr><h3><a name="luaL_buffinit"><code>luaL_buffinit</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>void luaL_buffinit (lua_State *L, luaL_Buffer *B);</pre>

<p>
Initializes a buffer <code>B</code>.
This function does not allocate any space;
the buffer must be declared as a variable
(see <a href="#luaL_Buffer"><code>luaL_Buffer</code></a>).
<hr><h3><a name="luaL_callmeta"><code>luaL_callmeta</code></a></h3><p>
<span class="apii">[-0, +(0|1), <em>e</em>]</span>
<pre>int luaL_callmeta (lua_State *L, int obj, const char *e);</pre>

<p>
Calls a metamethod.<p>
If the object at index <code>obj</code> has a metatable and this
metatable has a field <code>e</code>,
this function calls this field and passes the object as its only argument.
In this case this function returns 1 and pushes onto the
stack the value returned by the call.
If there is no metatable or no metamethod,
this function returns 0 (without pushing any value on the stack).
<hr><h3><a name="luaL_checkany"><code>luaL_checkany</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>void luaL_checkany (lua_State *L, int narg);</pre>

<p>
Checks whether the function has an argument
of any type (including <b>nil</b>) at position <code>narg</code>.
<hr><h3><a name="luaL_checkint"><code>luaL_checkint</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>int luaL_checkint (lua_State *L, int narg);</pre>

<p>
Checks whether the function argument <code>narg</code> is a number
and returns this number cast to an <code>int</code>.
<hr><h3><a name="luaL_checkinteger"><code>luaL_checkinteger</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>lua_Integer luaL_checkinteger (lua_State *L, int narg);</pre>

<p>
Checks whether the function argument <code>narg</code> is a number
and returns this number cast to a <a href="#lua_Integer"><code>lua_Integer</code></a>.
<hr><h3><a name="luaL_checklong"><code>luaL_checklong</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>long luaL_checklong (lua_State *L, int narg);</pre>

<p>
Checks whether the function argument <code>narg</code> is a number
and returns this number cast to a <code>long</code>.
<hr><h3><a name="luaL_checklstring"><code>luaL_checklstring</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>const char *luaL_checklstring (lua_State *L, int narg, size_t *l);</pre>

<p>
Checks whether the function argument <code>narg</code> is a string
and returns this string;
if <code>l</code> is not <code>NULL</code> fills <code>*l</code>
with the string's length.<p>
This function uses <a href="#lua_tolstring"><code>lua_tolstring</code></a> to get its result,
so all conversions and caveats of that function apply here.
<hr><h3><a name="luaL_checknumber"><code>luaL_checknumber</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>lua_Number luaL_checknumber (lua_State *L, int narg);</pre>

<p>
Checks whether the function argument <code>narg</code> is a number
and returns this number.
<hr><h3><a name="luaL_checkoption"><code>luaL_checkoption</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>int luaL_checkoption (lua_State *L,
                      int narg,
                      const char *def,
                      const char *const lst[]);</pre>

<p>
Checks whether the function argument <code>narg</code> is a string and
searches for this string in the array <code>lst</code>
(which must be NULL-terminated).
Returns the index in the array where the string was found.
Raises an error if the argument is not a string or
if the string cannot be found.<p>
If <code>def</code> is not <code>NULL</code>,
the function uses <code>def</code> as a default value when
there is no argument <code>narg</code> or if this argument is <b>nil</b>.<p>
This is a useful function for mapping strings to C&nbsp;enums.
(The usual convention in Lua libraries is
to use strings instead of numbers to select options.)
<hr><h3><a name="luaL_checkstack"><code>luaL_checkstack</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>void luaL_checkstack (lua_State *L, int sz, const char *msg);</pre>

<p>
Grows the stack size to <code>top + sz</code> elements,
raising an error if the stack cannot grow to that size.
<code>msg</code> is an additional text to go into the error message.
<hr><h3><a name="luaL_checkstring"><code>luaL_checkstring</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>const char *luaL_checkstring (lua_State *L, int narg);</pre>

<p>
Checks whether the function argument <code>narg</code> is a string
and returns this string.<p>
This function uses <a href="#lua_tolstring"><code>lua_tolstring</code></a> to get its result,
so all conversions and caveats of that function apply here.
<hr><h3><a name="luaL_checktype"><code>luaL_checktype</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>void luaL_checktype (lua_State *L, int narg, int t);</pre>

<p>
Checks whether the function argument <code>narg</code> has type <code>t</code>.
See <a href="#lua_type"><code>lua_type</code></a> for the encoding of types for <code>t</code>.
<hr><h3><a name="luaL_checkudata"><code>luaL_checkudata</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>void *luaL_checkudata (lua_State *L, int narg, const char *tname);</pre>

<p>
Checks whether the function argument <code>narg</code> is a userdata
of the type <code>tname</code> (see <a href="#luaL_newmetatable"><code>luaL_newmetatable</code></a>).
<hr><h3><a name="luaL_dofile"><code>luaL_dofile</code></a></h3><p>
<span class="apii">[-0, +?, <em>m</em>]</span>
<pre>int luaL_dofile (lua_State *L, const char *filename);</pre>

<p>
Loads and runs the given file.
It is defined as the following macro:

<pre>
     (luaL_loadfile(L, filename) || lua_pcall(L, 0, LUA_MULTRET, 0))
</pre><p>
It returns 0 if there are no errors
or 1 in case of errors.
<hr><h3><a name="luaL_dostring"><code>luaL_dostring</code></a></h3><p>
<span class="apii">[-0, +?, <em>m</em>]</span>
<pre>int luaL_dostring (lua_State *L, const char *str);</pre>

<p>
Loads and runs the given string.
It is defined as the following macro:

<pre>
     (luaL_loadstring(L, str) || lua_pcall(L, 0, LUA_MULTRET, 0))
</pre><p>
It returns 0 if there are no errors
or 1 in case of errors.
<hr><h3><a name="luaL_error"><code>luaL_error</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>int luaL_error (lua_State *L, const char *fmt, ...);</pre>

<p>
Raises an error.
The error message format is given by <code>fmt</code>
plus any extra arguments,
following the same rules of <a href="#lua_pushfstring"><code>lua_pushfstring</code></a>.
It also adds at the beginning of the message the file name and
the line number where the error occurred,
if this information is available.<p>
This function never returns,
but it is an idiom to use it in C&nbsp;functions
as <code>return luaL_error(<em>args</em>)</code>.
<hr><h3><a name="luaL_getmetafield"><code>luaL_getmetafield</code></a></h3><p>
<span class="apii">[-0, +(0|1), <em>m</em>]</span>
<pre>int luaL_getmetafield (lua_State *L, int obj, const char *e);</pre>

<p>
Pushes onto the stack the field <code>e</code> from the metatable
of the object at index <code>obj</code>.
If the object does not have a metatable,
or if the metatable does not have this field,
returns 0 and pushes nothing.
<hr><h3><a name="luaL_getmetatable"><code>luaL_getmetatable</code></a></h3><p>
<span class="apii">[-0, +1, <em>-</em>]</span>
<pre>void luaL_getmetatable (lua_State *L, const char *tname);</pre>

<p>
Pushes onto the stack the metatable associated with name <code>tname</code>
in the registry (see <a href="#luaL_newmetatable"><code>luaL_newmetatable</code></a>).
<hr><h3><a name="luaL_gsub"><code>luaL_gsub</code></a></h3><p>
<span class="apii">[-0, +1, <em>m</em>]</span>
<pre>const char *luaL_gsub (lua_State *L,
                       const char *s,
                       const char *p,
                       const char *r);</pre>

<p>
Creates a copy of string <code>s</code> by replacing
any occurrence of the string <code>p</code>
with the string <code>r</code>.
Pushes the resulting string on the stack and returns it.
<hr><h3><a name="luaL_loadbuffer"><code>luaL_loadbuffer</code></a></h3><p>
<span class="apii">[-0, +1, <em>m</em>]</span>
<pre>int luaL_loadbuffer (lua_State *L,
                     const char *buff,
                     size_t sz,
                     const char *name);</pre>

<p>
Loads a buffer as a Lua chunk.
This function uses <a href="#lua_load"><code>lua_load</code></a> to load the chunk in the
buffer pointed to by <code>buff</code> with size <code>sz</code>.<p>
This function returns the same results as <a href="#lua_load"><code>lua_load</code></a>.
<code>name</code> is the chunk name,
used for debug information and error messages.
<hr><h3><a name="luaL_loadfile"><code>luaL_loadfile</code></a></h3><p>
<span class="apii">[-0, +1, <em>m</em>]</span>
<pre>int luaL_loadfile (lua_State *L, const char *filename);</pre>

<p>
Loads a file as a Lua chunk.
This function uses <a href="#lua_load"><code>lua_load</code></a> to load the chunk in the file
named <code>filename</code>.
If <code>filename</code> is <code>NULL</code>,
then it loads from the standard input.
The first line in the file is ignored if it starts with a <code>#</code>.<p>
This function returns the same results as <a href="#lua_load"><code>lua_load</code></a>,
but it has an extra error code <a name="pdf-LUA_ERRFILE"><code>LUA_ERRFILE</code></a>
if it cannot open/read the file.<p>
As <a href="#lua_load"><code>lua_load</code></a>, this function only loads the chunk;
it does not run it.
<hr><h3><a name="luaL_loadstring"><code>luaL_loadstring</code></a></h3><p>
<span class="apii">[-0, +1, <em>m</em>]</span>
<pre>int luaL_loadstring (lua_State *L, const char *s);</pre>

<p>
Loads a string as a Lua chunk.
This function uses <a href="#lua_load"><code>lua_load</code></a> to load the chunk in
the zero-terminated string <code>s</code>.<p>
This function returns the same results as <a href="#lua_load"><code>lua_load</code></a>.<p>
Also as <a href="#lua_load"><code>lua_load</code></a>, this function only loads the chunk;
it does not run it.
<hr><h3><a name="luaL_newmetatable"><code>luaL_newmetatable</code></a></h3><p>
<span class="apii">[-0, +1, <em>m</em>]</span>
<pre>int luaL_newmetatable (lua_State *L, const char *tname);</pre>

<p>
If the registry already has the key <code>tname</code>,
returns 0.
Otherwise,
creates a new table to be used as a metatable for userdata,
adds it to the registry with key <code>tname</code>,
and returns 1.<p>
In both cases pushes onto the stack the final value associated
with <code>tname</code> in the registry.
<hr><h3><a name="luaL_newstate"><code>luaL_newstate</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>lua_State *luaL_newstate (void);</pre>

<p>
Creates a new Lua state.
It calls <a href="#lua_newstate"><code>lua_newstate</code></a> with an
allocator based on the standard&nbsp;C <code>realloc</code> function
and then sets a panic function (see <a href="#lua_atpanic"><code>lua_atpanic</code></a>) that prints
an error message to the standard error output in case of fatal
errors.<p>
Returns the new state,
or <code>NULL</code> if there is a memory allocation error.
<hr><h3><a name="luaL_openlibs"><code>luaL_openlibs</code></a></h3><p>
<span class="apii">[-0, +0, <em>m</em>]</span>
<pre>void luaL_openlibs (lua_State *L);</pre>

<p>
Opens all standard Lua libraries into the given state.
<hr><h3><a name="luaL_optint"><code>luaL_optint</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>int luaL_optint (lua_State *L, int narg, int d);</pre>

<p>
If the function argument <code>narg</code> is a number,
returns this number cast to an <code>int</code>.
If this argument is absent or is <b>nil</b>,
returns <code>d</code>.
Otherwise, raises an error.
<hr><h3><a name="luaL_optinteger"><code>luaL_optinteger</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>lua_Integer luaL_optinteger (lua_State *L,
                             int narg,
                             lua_Integer d);</pre>

<p>
If the function argument <code>narg</code> is a number,
returns this number cast to a <a href="#lua_Integer"><code>lua_Integer</code></a>.
If this argument is absent or is <b>nil</b>,
returns <code>d</code>.
Otherwise, raises an error.
<hr><h3><a name="luaL_optlong"><code>luaL_optlong</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>long luaL_optlong (lua_State *L, int narg, long d);</pre>

<p>
If the function argument <code>narg</code> is a number,
returns this number cast to a <code>long</code>.
If this argument is absent or is <b>nil</b>,
returns <code>d</code>.
Otherwise, raises an error.
<hr><h3><a name="luaL_optlstring"><code>luaL_optlstring</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>const char *luaL_optlstring (lua_State *L,
                             int narg,
                             const char *d,
                             size_t *l);</pre>

<p>
If the function argument <code>narg</code> is a string,
returns this string.
If this argument is absent or is <b>nil</b>,
returns <code>d</code>.
Otherwise, raises an error.<p>
If <code>l</code> is not <code>NULL</code>,
fills the position <code>*l</code> with the results's length.
<hr><h3><a name="luaL_optnumber"><code>luaL_optnumber</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>lua_Number luaL_optnumber (lua_State *L, int narg, lua_Number d);</pre>

<p>
If the function argument <code>narg</code> is a number,
returns this number.
If this argument is absent or is <b>nil</b>,
returns <code>d</code>.
Otherwise, raises an error.
<hr><h3><a name="luaL_optstring"><code>luaL_optstring</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>const char *luaL_optstring (lua_State *L,
                            int narg,
                            const char *d);</pre>

<p>
If the function argument <code>narg</code> is a string,
returns this string.
If this argument is absent or is <b>nil</b>,
returns <code>d</code>.
Otherwise, raises an error.
<hr><h3><a name="luaL_prepbuffer"><code>luaL_prepbuffer</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>char *luaL_prepbuffer (luaL_Buffer *B);</pre>

<p>
Returns an address to a space of size <a name="pdf-LUAL_BUFFERSIZE"><code>LUAL_BUFFERSIZE</code></a>
where you can copy a string to be added to buffer <code>B</code>
(see <a href="#luaL_Buffer"><code>luaL_Buffer</code></a>).
After copying the string into this space you must call
<a href="#luaL_addsize"><code>luaL_addsize</code></a> with the size of the string to actually add 
it to the buffer.
<hr><h3><a name="luaL_pushresult"><code>luaL_pushresult</code></a></h3><p>
<span class="apii">[-?, +1, <em>m</em>]</span>
<pre>void luaL_pushresult (luaL_Buffer *B);</pre>

<p>
Finishes the use of buffer <code>B</code> leaving the final string on
the top of the stack.
<hr><h3><a name="luaL_ref"><code>luaL_ref</code></a></h3><p>
<span class="apii">[-1, +0, <em>m</em>]</span>
<pre>int luaL_ref (lua_State *L, int t);</pre>

<p>
Creates and returns a <em>reference</em>,
in the table at index <code>t</code>,
for the object at the top of the stack (and pops the object).<p>
A reference is a unique integer key.
As long as you do not manually add integer keys into table <code>t</code>,
<a href="#luaL_ref"><code>luaL_ref</code></a> ensures the uniqueness of the key it returns.
You can retrieve an object referred by reference <code>r</code>
by calling <code>lua_rawgeti(L, t, r)</code>.
Function <a href="#luaL_unref"><code>luaL_unref</code></a> frees a reference and its associated object.<p>
If the object at the top of the stack is <b>nil</b>,
<a href="#luaL_ref"><code>luaL_ref</code></a> returns the constant <a name="pdf-LUA_REFNIL"><code>LUA_REFNIL</code></a>.
The constant <a name="pdf-LUA_NOREF"><code>LUA_NOREF</code></a> is guaranteed to be different
from any reference returned by <a href="#luaL_ref"><code>luaL_ref</code></a>.
<hr><h3><a name="luaL_Reg"><code>luaL_Reg</code></a></h3>
<pre>typedef struct luaL_Reg {
  const char *name;
  lua_CFunction func;
} luaL_Reg;</pre>

<p>
Type for arrays of functions to be registered by
<a href="#luaL_register"><code>luaL_register</code></a>.
<code>name</code> is the function name and <code>func</code> is a pointer to
the function.
Any array of <a href="#luaL_Reg"><code>luaL_Reg</code></a> must end with an sentinel entry
in which both <code>name</code> and <code>func</code> are <code>NULL</code>.
<hr><h3><a name="luaL_register"><code>luaL_register</code></a></h3><p>
<span class="apii">[-(0|1), +1, <em>m</em>]</span>
<pre>void luaL_register (lua_State *L,
                    const char *libname,
                    const luaL_Reg *l);</pre>

<p>
Opens a library.<p>
When called with <code>libname</code> equal to <code>NULL</code>,
it simply registers all functions in the list <code>l</code>
(see <a href="#luaL_Reg"><code>luaL_Reg</code></a>) into the table on the top of the stack.<p>
When called with a non-null <code>libname</code>,
<code>luaL_register</code> creates a new table <code>t</code>,
sets it as the value of the global variable <code>libname</code>,
sets it as the value of <code>package.loaded[libname]</code>,
and registers on it all functions in the list <code>l</code>.
If there is a table in <code>package.loaded[libname]</code> or in
variable <code>libname</code>,
reuses this table instead of creating a new one.<p>
In any case the function leaves the table
on the top of the stack.
<hr><h3><a name="luaL_typename"><code>luaL_typename</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>const char *luaL_typename (lua_State *L, int index);</pre>

<p>
Returns the name of the type of the value at the given index.
<hr><h3><a name="luaL_typerror"><code>luaL_typerror</code></a></h3><p>
<span class="apii">[-0, +0, <em>v</em>]</span>
<pre>int luaL_typerror (lua_State *L, int narg, const char *tname);</pre>

<p>
Generates an error with a message like the following:

<pre>
     <em>location</em>: bad argument <em>narg</em> to '<em>func</em>' (<em>tname</em> expected, got <em>rt</em>)
</pre><p>
where <code><em>location</em></code> is produced by <a href="#luaL_where"><code>luaL_where</code></a>,
<code><em>func</em></code> is the name of the current function,
and <code><em>rt</em></code> is the type name of the actual argument.
<hr><h3><a name="luaL_unref"><code>luaL_unref</code></a></h3><p>
<span class="apii">[-0, +0, <em>-</em>]</span>
<pre>void luaL_unref (lua_State *L, int t, int ref);</pre>

<p>
Releases reference <code>ref</code> from the table at index <code>t</code>
(see <a href="#luaL_ref"><code>luaL_ref</code></a>).
The entry is removed from the table,
so that the referred object can be collected.
The reference <code>ref</code> is also freed to be used again.<p>
If <code>ref</code> is <a href="#pdf-LUA_NOREF"><code>LUA_NOREF</code></a> or <a href="#pdf-LUA_REFNIL"><code>LUA_REFNIL</code></a>,
<a href="#luaL_unref"><code>luaL_unref</code></a> does nothing.
<hr><h3><a name="luaL_where"><code>luaL_where</code></a></h3><p>
<span class="apii">[-0, +1, <em>m</em>]</span>
<pre>void luaL_where (lua_State *L, int lvl);</pre>

<p>
Pushes onto the stack a string identifying the current position
of the control at level <code>lvl</code> in the call stack.
Typically this string has the following format:

<pre>
     <em>chunkname</em>:<em>currentline</em>:
</pre><p>
Level&nbsp;0 is the running function,
level&nbsp;1 is the function that called the running function,
etc.<p>
This function is used to build a prefix for error messages.

```
