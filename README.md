Dython
======

```d
import dython;

mixin(dythonizeFile!"main.dy");

//Or:
mixin(dythonize(q{

import std.stdio

int main()
    int a, b
    readf(" %s %s", &a, &b)
    if (a + b != 0)
        writeln(a + b)
        return 0
    else
        writeln("Isn't it awesome?")
        return 1

}));
```


What it is
----------

**Dython** is a **D** source preprocessor that makes your code look like P**ython**. Actually, all
that it does is inserting semicolons and braces where DMD wants to see them.

### Advantages ###

+ Much cleaner syntax.
+ More code fits on the screen.
+ The compiler will blame you on sloppy indentation.
+ Compilation errors are addressed to the correct source location.
+ Either tabs or spaces can be used, but mixing them is prohibited.
+ Zero run-time cost.
+ Compatible with DMD and LDC (and maybe also GDC — was not tested).

### Drawbacks ###

- Compilation is slower. Not terribly slow, but the difference is clearly visible. Things should
  go better when a [compile-time bytecode interpreter][new-ctfe] is merged into DMD.
- [DCD][dcd] just gets stuck.
- `case` and `goto` labels (and attribute like `private:`) *must* be indented:

```d
final switch (x)
    case 0:
    doSomething()
    break

    case 1:
        //You can indent the block even more if you'd like.
        doSomethingElse()
        break
```

  This issue can be overcome (at some extent) by placing extra braces:

```d
struct Thing {
nothrow pure @safe @nogc
    //...
}
```

- Sometimes you still *have* to put braces and even semicolons (most notably, with delegates and
  struct initializers). Also, a trailing comma in a struct initializer is *required*
  (`Thing th = { x, y, };`).
- And sometimes backslash line splicing has to be done (usually, in long function definitions):

```d
auto joiner(RoR, Separator)(RoR r, Separator sep) \
if (isInputRange!RoR && isInputRange!(ElementType!RoR) &&
    isForwardRange!Separator &&
    is(ElementType!Separator: ElementType!(ElementType!RoR)))
    //body
```

  Unfortunately, `\` isn't a valid D token and thus is unavailable in `q{}`-strings. I'm looking for
  a replacement (maybe `//\` or `@`? Submit an issue if you have an idea on that question).

[new-ctfe]: https://dlang.org/blog/2017/04/10/the-new-ctfe-engine/
[dcd]:      https://github.com/dlang-community/DCD


How to use it
-------------

```d
module dython

pure @safe
    S dythonize(S: const(char)[ ] = string)(const(char)[ ] source)
    S dythonizeFile(S: const(char)[ ], string fileName)()
    string dythonizeFile(string fileName)()
```

`dythonize` processes source code passed as an argument and `dythonizeFile` string-`import`s a file
with the given name. Both may be asked to return a `char[ ]` instead of `string`:

```d
//`enum` to force compile-time evaluation.
enum header      = dythonize!(char[ ])(q{import std.algorithm, std.range});
char[ ] contents = dythonizeFile!(char[ ], "contents.dy");
```


How it works
------------

The parser is intentionally kept quite simple to make it faster. It follows a few rules:

1. If the indentation increases, a brace is opened on the previous line, unless it ends with one of
   `=>,\{`.
2. If the indentation decreases or stays consistent, a semicolon is appended to the previous line,
   unless it ends with one of `=>,:;\{}`, and then needed amount of braces are closed.
3. `\` is erased from the resulting code.
4. Code rewriting is disabled in parentheses and brackets and re-enabled in user-placed braces.

Of course, comments and strings are properly skipped.

Dython passes the [three-stage bootstrapping][dython3] (a standard self-hosting compiler stress
test), so the possibility of a nasty bug in it is rather small. Some [sed scripting][preprocess.sh]
is required to turn it into a self-hosting one, though.

[dython3]:       https://github.com/SirNickolas/Dython/blob/master/test/dython3.d
[preprocess.sh]: https://github.com/SirNickolas/Dython/blob/master/test/preprocess.sh


Conclusion
----------

Even if you won't use it at all, I hope you've got as much fun reading this as much I've got
implementing this.
