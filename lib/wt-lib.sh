# wt-lib.sh is now jay-lib.sh (jay was wt-hub). Scripts of an older install that still run
# source this path; it loads jay-lib.sh from its own folder (through the link of a --link
# install). ./install.sh --no-compat removes it.
_jay_lib=${BASH_SOURCE[0]}
[[ -L "$_jay_lib" ]] && _jay_lib=$(readlink "$_jay_lib")
source "${_jay_lib%/*}/jay-lib.sh"
unset _jay_lib
