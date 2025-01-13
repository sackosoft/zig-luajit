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

```html_documentation(please translate)
{{TRANSLATE}}
```
