#!/usr/bin/env sh

cd "`dirname "$0"`/.."
exec sed                                  \
    -e '/^module /,+1d'                   \
    -e '/^\s*\(pragma\|void\)/s/)$/) \\/' \
    -e 's/ {$//'                          \
    -e '/^\s*}$/d'                        \
    -e '/^\s*} /s/} //'                   \
    -e '/};$/p'                           \
    -e '/};$/d'                           \
    -e 's!;\(//.*\)\?$!\1!'               \
    src/dython.d >views/dython.dy
