module dython;

import std.algorithm;
import std.array;
import std.range;
import std.uni;

pure @safe:

pragma(inline, true) {
    ///
    S dythonize(S: const(char)[ ] = string)(const(char)[ ] source) {
        return parser(source).parse();
    }

    ///
    string dythonizeFile(string fileName)() {
        return dythonizeFile!(string, fileName);
    }

    /// ditto
    S dythonizeFile(S: const(char)[ ], string fileName)() {
        auto p = parser(import(fileName));
        p.sink ~= "#line 1 \"" ~ fileName ~ "\"\n";
        return p.parse();
    }
}

private:

pragma(inline, true)
bool isIdent(dchar c) nothrow @nogc {
    return c == '_' || isAlphaNum(c);
}

enum {
    //Emit static assertions (instead of, for example, throwing exceptions while parsing) so that
    //a compiler reports an error in the user code and not in the library.
    indentationError = q{static assert(false, "Indentation error");},
    mixedIndentationError =
        q{static assert(false, "Indentation error: tabs and spaces can't be mixed together");},
}

enum Emit: ubyte {
    closingBraceOnly,
    braceOnly,
    everything,
}

struct BracedBlock {
    nothrow pure @safe:

    int[ ] levels;
    int lTop;
    int parenCount;//Brackets (but not braces) are included too.
    int curLineIndentation;

    pragma(inline, true)
    @property ref int level() @nogc {
        return levels[lTop];
    }

    void pushLevel(int value)
    in {
        assert(value > level, "Indentation does not increase");
    }
    body {
        if (++lTop == levels.length)
            levels ~= value;
        else
            level = value;
    }
}

struct Parser {
    pure @safe:

    const(char)[ ] s, checkpoint;
    Appender!(char[ ]) sink;
    Appender!(char[ ]) stringMarker;//for q"EOF ... EOF".
    char indentChar = '\0';//' ' or '\t'.
    bool bol = true;
    Emit now, delayed;
    int qBraceCount;
    int bTop = -1;
    BracedBlock[ ] blocks;

    //Utility functions:
    pragma(inline, true)
    @property ref BracedBlock block() nothrow @nogc {
        return blocks[bTop];
    }

    void skip1() @nogc {
        if (!s.empty)
            s.popFront();
    }

    void skipAscii1() nothrow @nogc {
        if (!s.empty)
            s = s[1 .. $];
    }

    void pushBlock() nothrow {
        if (++bTop == blocks.length)
            blocks ~= BracedBlock(uninitializedArray!(int[ ])(16));
        else
            block.lTop = block.parenCount = block.curLineIndentation = 0;
        block.level = -1;
    }

    void skipTillEol() {
        s = s.find!(c => c.among!('\n', '\r', '\u2028', '\u2029'));
    }

    //Grammar functions:
    void processNewline() nothrow {
        if (bol || block.parenCount || qBraceCount)
            return;
        sink ~= checkpoint[0 .. $ - s.length - 1];
        checkpoint = checkpoint[$ - s.length - 1 .. $];
        delayed = now;
        now = Emit.closingBraceOnly;
        bol = true;
    }

    void processSignificantWhitespace() {
        if (block.parenCount || qBraceCount)
            return;
        else if (s.empty) {
            block.curLineIndentation = 0;
            return;
        }
        dchar c = s.front;
        if (!c.among!(' ', '\t'))
            block.curLineIndentation = 0;
        else {
            if (indentChar) {
                if (c != indentChar)
                    sink ~= mixedIndentationError;
            } else
                indentChar = cast(char)c;//Remember the first seen whitespace character in the file.
            const temp = s;
            s = s[1 .. $].find!q{a != b}(indentChar);
            if (!s.empty && s.front.among!(' ', '\t'))
                sink ~= mixedIndentationError;
            block.curLineIndentation = cast(int)(temp.length - s.length);
        }
    }

    void processFirstWord() nothrow {
        if (!bol || block.parenCount || qBraceCount)
            return;
        if (block.level < 0) {
            //Initialize the level with that of the first line in the block.
            block.level = block.curLineIndentation;
            assert(delayed == Emit.closingBraceOnly);
        }
        if (block.curLineIndentation == block.level) {
            if (delayed == Emit.everything)
                sink ~= ';';//The most common case.
        } else if (block.curLineIndentation > block.level) {
            if (delayed != Emit.closingBraceOnly) {
                sink ~= '{';
                block.pushLevel(block.curLineIndentation);
            }
        } else {
            if (delayed == Emit.everything)
                sink ~= ';';
            auto found = (
                block.levels[0 .. block.lTop]
                .retro()
                .find!(level => level <= block.curLineIndentation)
            );
            if (found.empty) {
                //Dedented past the zeroth level, silently allow.
                sink ~= repeat('}', block.lTop);
                block.lTop = 0;
            } else {
                if (found.front < block.curLineIndentation)
                    sink ~= indentationError;
                sink ~= repeat('}', block.lTop - (found.length - 1));
                block.lTop = cast(int)found.length - 1;
            }
        }
        delayed = Emit.closingBraceOnly;
    }

    void processSeparator() nothrow {
        processFirstWord();
        now = Emit.closingBraceOnly;
        bol = false;
    }

    void processTerminator() nothrow {
        processFirstWord();
        now = Emit.braceOnly;
        bol = false;
    }

    void processBackslash() nothrow {
        if (qBraceCount)
            return;
        sink ~= checkpoint[0 .. $ - s.length - 1];
        checkpoint = s;
        now = Emit.closingBraceOnly;
        bol = false;
    }

    void processParen() nothrow {
        if (qBraceCount)
            return;
        processFirstWord();
        block.parenCount++;
    }

    void processCloseParen() nothrow @nogc {
        if (qBraceCount)
            return;
        if (block.parenCount)
            block.parenCount--;
        now = Emit.everything;
        bol = false;
    }

    void processBrace() nothrow {
        if (qBraceCount)
            qBraceCount++;
        else {
            processFirstWord();
            pushBlock();
            now = Emit.closingBraceOnly;
            bol = true;
        }
    }

    void processCloseBrace() nothrow {
        if (qBraceCount)
            qBraceCount--;
        else {
            if (delayed == Emit.everything)
                sink ~= ';';
            sink ~= checkpoint[0 .. $ - s.length - 1];
            checkpoint = checkpoint[$ - s.length - 1 .. $];
            if (now == Emit.everything)
                sink ~= ';';
            if (bTop) {
                sink ~= repeat('}', block.lTop);//Close everything in a block.
                bTop--;
            }
            now = Emit.braceOnly;
            bol = false;
        }
    }

    void processSomeString(alias handler)() {
        processFirstWord();
        handler();
        now = Emit.everything;
        bol = false;
    }

    void skipString(char delimiter)() {
        while (!s.empty) {
            const dchar c = s.front;
            s.popFront();
            if (c == delimiter)
                return;
            if (c == '\\')
                skip1();
        }
    }

    //r"\d+:\d+"
    void skipRawString(char delimiter)() {
        s = s.find(delimiter);
        skipAscii1();
    }

    void skipDelimitedString() {
        if (s.empty)
            return;
        const dchar delim = s.front;
        dchar closeDelim;
        s.popFront();
        switch (delim) {
            case '(': closeDelim = ')'; break;
            case '[': closeDelim = ']'; break;
            case '{': closeDelim = '}'; break;
            case '<': closeDelim = '>'; break;
            default:
                if (isIdent(delim)) {
                    //q"EOF ... EOF"
                    const temp = s;
                    s = s.find!(c => !isIdent(c));

                    stringMarker.clear();
                    stringMarker.reserve(temp.length - s.length + 2);
                    stringMarker ~= '\n';
                    stringMarker ~= temp[0 .. $ - s.length];
                    stringMarker ~= '"';

                    s = s.find(stringMarker.data);
                    if (!s.empty)
                        s = s[stringMarker.data.length .. $];
                } else {
                    //q"/just a "test" string/"
                    s = s.find(delim);
                    if (!s.empty) {
                        s.popFront();
                        skip1();//'"'
                    }
                }
                return;
        }

        //q"(ab(cd)ef)"
        int depth = 1;
        while (!s.empty) {
            const dchar c = s.front;
            s.popFront();
            if (c == delim)
                depth++;
            else if (c == closeDelim && !--depth) {
                skip1();//'"'
                return;
            }
        }
    }

    //q{a > b}
    void processTokenString() nothrow {
        processFirstWord();
        qBraceCount++;
    }

    void processSlash() {
        if (s.empty) {
            now = Emit.everything;
            bol = false;
            return;
        }
        dchar c = s.front;
        if (c == '/') {
            processNewline();
            skipTillEol();
            skip1();
            processSignificantWhitespace();
        } else if (c == '*') {
            s = s[1 .. $].find(`*/`);
            if (!s.empty)
                s = s[2 .. $];
        } else if (c == '+') {
            int depth = 1;
            s = s[1 .. $];
            while (!s.empty) {
                c = s.front;
                s.popFront();
                if (c == '+') {
                    if (!s.empty && s.front == '/') {
                        s = s[1 .. $];
                        if (!--depth)
                            return;
                    }
                } else if (c == '/')
                    if (!s.empty && s.front == '+') {
                        s = s[1 .. $];
                        depth++;
                    }
            }
        } else {
            processFirstWord();
            now = Emit.everything;
            bol = false;
        }
    }

    //#line 123 "main.dy"
    void processHash() {
        skipTillEol();
        skip1();
        //Does not affect the parser state at all.
    }

    char[ ] parse() {
        processSignificantWhitespace();

        parseLoop:
        while (!s.empty) {
            const dchar c = s.front;
            s.popFront();
            if (isIdent(c)) {
                if (c == 'r') {
                    if (!s.empty && s.front == '"') {
                        s.popFront();
                        processSomeString!(skipRawString!'"');
                        continue;
                    }
                } else if (c == 'q') {
                    if (!s.empty) {
                        const dchar c2 = s.front;
                        if (c2 == '"') {
                            s.popFront();
                            processSomeString!skipDelimitedString();
                            continue;
                        } else if (c2 == '{') {
                            s.popFront();
                            processTokenString();
                            continue;
                        }
                    }
                } else if (c == '_' && s.skipOver(`_EOF__`) && (s.empty || !isIdent(s.front))) {
                    checkpoint.length -= s.length;//Trim the source.
                    break parseLoop;
                }
                processFirstWord();
                s = s.find!(c => !isIdent(c));
                now = Emit.everything;
                bol = false;
            } else
                switch (c) {
                    case ' ', '\t', '\v', '\f':
                        break;

                    case '\n', '\r', '\u2028', '\u2029':
                        processNewline();
                        processSignificantWhitespace();
                        break;

                    case ',', '=', '>':
                        processSeparator();
                        break;

                    case ':', ';':
                        processTerminator();
                        break;

                    case '\\':
                        processBackslash();
                        break;

                    case '(', '[':
                        processParen();
                        break;

                    case ')', ']':
                        processCloseParen();
                        break;

                    case '/':
                        processSlash();
                        break;

                    case '"':
                        processSomeString!(skipString!'"');
                        break;

                    case '\'':
                        processSomeString!(skipString!'\'');
                        break;

                    case '`':
                        processSomeString!(skipRawString!'`');
                        break;

                    case '{':
                        processBrace();
                        break;

                    case '}':
                        processCloseBrace();
                        break;

                    case '#':
                        processHash();
                        break;

                    case '\0', '\x1A'://Treated as EOF.
                        checkpoint.length -= s.length;//Trim the source.
                        break parseLoop;

                    default:
                        processFirstWord();
                        now = Emit.everything;
                        bol = false;
                }
        }
        if (delayed == Emit.everything)
            sink ~= ';';
        sink ~= checkpoint;
        if (now == Emit.everything)
            sink ~= ';';
        sink ~= repeat('}', bTop + sum(blocks[0 .. bTop + 1].map!q{a.lTop}));
        return sink.data;
    }
}

auto parser(const(char)[ ] source) nothrow {
    Parser p = { source, };
    with (p) {
        sink.reserve(s.length + (s.length >> 4));//Reserve 1/16 of source for syntactic garbage.
        blocks = minimallyInitializedArray!(BracedBlock[ ])(4);
        foreach (ref b; blocks)
            b.levels = uninitializedArray!(int[ ])(16);
        pushBlock();
        checkpoint = s;
    }
    return p;
}
