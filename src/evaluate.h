// evaluate.h

#ifndef EVALUATE_H_INCLUDED
#define EVALUATE_H_INCLUDED

#include <string>

#include "types.h"

class Position;

namespace Eval {

Value evaluate(Position &pos);

}

#endif // #ifndef EVALUATE_H_INCLUDED
