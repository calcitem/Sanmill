/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <sstream>

//#include "misc.h"
#include "thread.h"
#include "uci.h"
#include "option.h"

using std::string;

UCI::OptionsMap Options; // Global object

extern struct Rule rule;

namespace UCI
{

/// 'On change' actions, triggered by an option's value change
void on_clear_hash(const Option &)
{
    Search::clear();
}

void on_hash_size(const Option &o)
{
#ifdef TRANSPOSITION_TABLE_ENABLE
    TT.resize((size_t)o);
#endif
}

void on_logger(const Option &o)
{
    start_logger(o);
}

void on_threads(const Option &o)
{
    Threads.set((size_t)o);
}

void on_skill_level(const Option &o)
{
    gameOptions.setSkillLevel((int)o);
}

void on_move_time(const Option &o)
{
    gameOptions.setMoveTime((int)o);
}

void on_aiIsLazy(const Option &o)
{
    gameOptions.setAiIsLazy((bool)o);
}

void on_random_move(const Option &o)
{
    gameOptions.setShufflingEnabled((bool)o);
}

void on_drawOnHumanExperience(const Option &o)
{
    gameOptions.setDrawOnHumanExperience((bool)o);
}

void on_developerMode(const Option &o)
{
    gameOptions.setDeveloperMode((bool)o);
}

// Rules

void on_piecesCount(const Option &o)
{
    rule.piecesCount = (int)o;
}

void on_flyPieceCount(const Option &o)
{
    rule.flyPieceCount = (int)o;
}

void on_piecesAtLeastCount(const Option &o)
{
    rule.piecesAtLeastCount = (int)o;
}

void on_hasDiagonalLines(const Option &o)
{
    rule.hasDiagonalLines = (bool)o;
}

void on_hasBannedLocations(const Option &o)
{
    rule.hasBannedLocations = (bool)o;
}

void on_isDefenderMoveFirst(const Option &o)
{
    rule.isDefenderMoveFirst = (bool)o;
}

void on_mayRemoveMultiple(const Option &o)
{
    rule.mayRemoveMultiple = (bool)o;
}

void on_mayRemoveFromMillsAlways(const Option &o)
{
    rule.mayRemoveFromMillsAlways = (bool)o;
}

void on_isWhiteLoseButNotDrawWhenBoardFull(const Option &o)
{
    rule.isWhiteLoseButNotDrawWhenBoardFull = (bool)o;
}

void on_isLoseButNotChangeSideWhenNoWay(const Option &o)
{
    rule.isLoseButNotChangeSideWhenNoWay = (bool)o;
}

void on_mayFly(const Option &o)
{
    rule.mayFly = (bool)o;
}

void on_maxStepsLedToDraw(const Option &o)
{
    rule.maxStepsLedToDraw = (size_t)o;
}

/// Our case insensitive less() function as required by UCI protocol
bool CaseInsensitiveLess::operator() (const string &s1, const string &s2) const
{

    return std::lexicographical_compare(s1.begin(), s1.end(), s2.begin(), s2.end(),
                                        [](char c1, char c2) noexcept { return tolower(c1) < tolower(c2); });
}


/// UCI::init() initializes the UCI options to their hard-coded default values

void init(OptionsMap &o)
{
    constexpr int MaxHashMB = Is64Bit ? 33554432 : 2048;

    o["Debug Log File"] << Option("", on_logger);
    o["Contempt"] << Option(24, -100, 100);
    o["Analysis Contempt"] << Option("Both var Off var White var Black var Both", "Both");
    o["Threads"] << Option(1, 1, 512, on_threads);
    o["Hash"] << Option(16, 1, MaxHashMB, on_hash_size);
    o["Clear Hash"] << Option(on_clear_hash);
    o["Ponder"] << Option(false);
    o["MultiPV"] << Option(1, 1, 500);
    o["SkillLevel"] << Option(1, 0, 20, on_skill_level);
    o["MoveTime"] << Option(1, 0, 60, on_move_time);
    o["AiIsLazy"] << Option(false, on_aiIsLazy);
    o["Move Overhead"] << Option(10, 0, 5000);
    o["Slow Mover"] << Option(100, 10, 1000);
    o["nodestime"] << Option(0, 0, 10000);
    o["UCI_AnalyseMode"] << Option(false);
    o["UCI_LimitStrength"] << Option(false);
    o["UCI_Elo"] << Option(1350, 1350, 2850);

    o["Shuffling"] << Option(true, on_random_move);
    o["DrawOnHumanExperience"] << Option(true, on_drawOnHumanExperience);
    o["DeveloperMode"] << Option(true, on_developerMode);

    // Rules
    o["PiecesCount"] << Option(9, 9, 12, on_piecesCount);
    o["flyPieceCount"] << Option(3, 3, 4, on_flyPieceCount);
    o["PiecesAtLeastCount"] << Option(3, 3, 5, on_piecesAtLeastCount);
    o["HasDiagonalLines"] << Option(false, on_hasDiagonalLines);
    o["HasBannedLocations"] << Option(false, on_hasBannedLocations);
    o["IsDefenderMoveFirst"] << Option(false, on_isDefenderMoveFirst);
    o["MayRemoveMultiple"] << Option(false, on_mayRemoveMultiple);
    o["MayRemoveFromMillsAlways"] << Option(false, on_mayRemoveFromMillsAlways);
    o["IsWhiteLoseButNotDrawWhenBoardFull"] << Option(true, on_isWhiteLoseButNotDrawWhenBoardFull);
    o["IsLoseButNotChangeSideWhenNoWay"] << Option(true, on_isLoseButNotChangeSideWhenNoWay);
    o["MayFly"] << Option(true, on_mayFly);
    o["MaxStepsLedToDraw"] << Option(50, 30, 50, on_maxStepsLedToDraw);

}


/// operator<<() is used to print all the options default values in chronological
/// insertion order (the idx field) and in the format defined by the UCI protocol.

std::ostream &operator<<(std::ostream &os, const OptionsMap &om)
{
    for (size_t idx = 0; idx < om.size(); ++idx)
        for (const auto &it : om)
            if (it.second.idx == idx) {
                const Option &o = it.second;
                os << "\noption name " << it.first << " type " << o.type;

                if (o.type == "string" || o.type == "check" || o.type == "combo")
                    os << " default " << o.defaultValue;

                if (o.type == "spin")
                    os << " default " << int(stof(o.defaultValue))
                    << " min " << o.min
                    << " max " << o.max;

                break;
            }

    return os;
}


/// Option class constructors and conversion operators

Option::Option(const char *v, OnChange f) : type("string"), min(0), max(0), on_change(f)
{
    defaultValue = currentValue = v;
}

Option::Option(bool v, OnChange f) : type("check"), min(0), max(0), on_change(f)
{
    defaultValue = currentValue = (v ? "true" : "false");
}

Option::Option(OnChange f) : type("button"), min(0), max(0), on_change(f)
{
}

Option::Option(double v, int minv, int maxv, OnChange f) : type("spin"), min(minv), max(maxv), on_change(f)
{
    defaultValue = currentValue = std::to_string(v);
}

Option::Option(const char *v, const char *cur, OnChange f) : type("combo"), min(0), max(0), on_change(f)
{
    defaultValue = v; currentValue = cur;
}

Option::operator double() const
{
    assert(type == "check" || type == "spin");
    return (type == "spin" ? stof(currentValue) : currentValue == "true");
}

Option::operator std::string() const
{
    assert(type == "string");
    return currentValue;
}

bool Option::operator==(const char *s) const
{
    assert(type == "combo");
    return   !CaseInsensitiveLess()(currentValue, s)
        && !CaseInsensitiveLess()(s, currentValue);
}


/// operator<<() inits options and assigns idx in the correct printing order

void Option::operator<<(const Option &o)
{
    static size_t insert_order = 0;

    *this = o;
    idx = insert_order++;
}


/// operator=() updates currentValue and triggers on_change() action. It's up to
/// the GUI to check for option's limits, but we could receive the new value
/// from the user by console window, so let's check the bounds anyway.

Option &Option::operator=(const string &v)
{
    assert(!type.empty());

    if ((type != "button" && v.empty())
        || (type == "check" && v != "true" && v != "false")
        || (type == "spin" && (stof(v) < min || stof(v) > max)))
        return *this;

    if (type == "combo") {
        OptionsMap comboMap; // To have case insensitive compare
        string token;
        std::istringstream ss(defaultValue);
        while (ss >> token)
            comboMap[token] << Option();
        if (!comboMap.count(v) || v == "var")
            return *this;
    }

    if (type != "button")
        currentValue = v;

    if (on_change)
        on_change(*this);

    return *this;
}

} // namespace UCI
