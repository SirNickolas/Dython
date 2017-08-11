import original     = dython;
import bootstrapped = dython3;

auto test(string code)() {
    enum gen1code = original.dythonize(code);
    enum gen3code = bootstrapped.dythonize(code);
    static assert(gen1code == gen3code, "G1 != G3 for:\n" ~ code);
    mixin(gen1code);
}

void main() {
    test!q{
        import std.algorithm.iteration

        struct Point
            public:

            int x, y

        Point myPoint = {
            x: 0,
            y: 1,
        };//This semicolon is mandatory.

        auto dg = (ref Point p)
            p.x++
        ;
    //  ^ So is this one.

        auto a = [myPoint];
        a.each!dg();
        assert(myPoint.x == 0);
        assert(a[0].x == 1);
    };
    test!q{
        //Valid yet weird.
        enum six = ()
            return 2 + 2 * 2
        ()
        static assert(is(typeof(six) == int))
        static assert(six == 6)
    };
    test!q{
        import std.algorithm.sorting

        auto arr = [-2, 1, 3]
        alias predicate = (a, b) =>
            a^^2 < b^^2
        arr.sort!predicate()
        assert(arr == [1, -2, 3])
    };
    test!q{
        auto x = test!q{
            //We need to go deeper!
            auto y = test!q{
                return 123
            };
            assert(y == 123)
            return y + 1
        };
        assert(x == 124)
    };
    test!q{
        static auto takesDelegate(int x, alias f, bool b)()
            return f(x, b)

        takesDelegate!(0, (a, b) {
            assert(a == 0)
            assert(b == true)
        }, true)
    };
}
