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
