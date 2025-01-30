// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// uci.h

#ifndef UCI_H_INCLUDED
#define UCI_H_INCLUDED

#include <map>
#include <string>
#include <utility>

#include "types.h"

class Position;

namespace UCI {

class Option;

/// Custom comparator because UCI options should be case insensitive
struct CaseInsensitiveLess
{
    bool operator()(const std::string &, const std::string &) const;
};

/// Our options container is actually a std::map
using OptionsMap = std::map<std::string, Option, CaseInsensitiveLess>;

/// Option class implements an option as defined by UCI protocol
class Option
{
    using OnChange = void (*)(const Option &);

public:
    explicit Option(OnChange = nullptr);
    explicit Option(bool v, OnChange = nullptr);
    explicit Option(const char *v, OnChange = nullptr);
    Option(double v, int minv, int maxv, OnChange = nullptr);
    Option(const char *v, const char *cur, OnChange = nullptr);

    Option &operator=(const std::string &);
    void operator<<(const Option &);
    operator double() const;
    operator std::string() const;
    bool operator==(const char *) const;

private:
    friend std::ostream &operator<<(std::ostream &, const OptionsMap &);

    std::string defaultValue, currentValue, type;
    int min, max;
    size_t idx {0};
    OnChange on_change;
};

void init(OptionsMap &);
void loop(int argc, char *argv[]);
std::string value(Value v);
std::string square(Square s);
std::string move(Move m);
Move to_move(Position *pos, const std::string &str);

} // namespace UCI

extern UCI::OptionsMap Options;

#endif // #ifndef UCI_H_INCLUDED
