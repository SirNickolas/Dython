//The third generation of the Dython "compiler".
module dython3;

public import dython2;

static assert(
    dythonizeFile!"dython.dy" == dython2.source,
    "The second and third generation compilers do not match");
