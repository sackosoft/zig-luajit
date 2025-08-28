# simple-repl

This sample application is provided to demonstrate the functionality of the the `zig-luajit` bindings.
It creates a Read-Evaluate-Print Loop (REPL) which reads a line of Lua code as input from the user,
evaluates the expression and prints the result to the output.

## Version

Last tested with Zig version `0.15.1`.

## Usage

Usage instructions:

* Ensure your current working directory is `zig-luajit/examples/simple-repl`.
* Use `zig build run` to run the application.
* Use `print()` to write Lua values to standard output. The REPL does not do any output itself.
* Use `exit` or `quit` or `Ctrl+C` to stop.

## Example Output

Here's a sample of running the interpreter:

```
~/repos/zig-luajit/examples/simple-repl > zig build run
> print('Hello, world!')
Hello, world!
> print(1 + 1)
2
> f = function() print("Yes, even functions work too") end
> f()
Yes, even functions work too
> exit
~/repos/zig-luajit/examples/simple-repl > 
```
