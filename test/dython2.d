//The second generation of the Dython "compiler".
module dython2;

import dython;

enum source = dythonizeFile!"dython.dy";

mixin(source);
