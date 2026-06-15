// Minimal stubs for the perfect-DB symbols referenced by the core engine.
// Only needed to LINK a console build; never executed because the harness
// keeps UsePerfectDatabase disabled.  Signatures mirror perfect_adaptor.h /
// perfect_api.h.
#include "types.h"
#include <string>

// Defined in perfect_common.cpp in the full build; provided here for the
// console harness that excludes the perfect tree.
std::string ruleVariantName;

class Position;

Value perfect_search(const Position *, Move &)
{
    return VALUE_NONE;
}

struct PerfectEvaluation
{
    Value value;
    int stepCount;
    bool isValid;
    PerfectEvaluation()
        : value(VALUE_NONE)
        , stepCount(-1)
        , isValid(false)
    { }
};

namespace PerfectAPI {
PerfectEvaluation getDetailedEvaluation(const Position &)
{
    return PerfectEvaluation();
}
} // namespace PerfectAPI

class MalomSolutionAccess
{
public:
    static void deinitialize_if_needed();
};

void MalomSolutionAccess::deinitialize_if_needed() { }
