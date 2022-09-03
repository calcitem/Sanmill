// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#include <sstream>

#include "option.h"
#include "thread.h"
#include "uci.h"

using std::string;

UCI::OptionsMap Options; // Global object

namespace UCI {

/// 'On change' actions, triggered by an option's value change
void on_clear_hash(const Option &)
{
    Search::clear();
}

void on_hash_size(const Option &o)
{
#ifdef TRANSPOSITION_TABLE_ENABLE
    TT.resize(static_cast<size_t>(o));
#endif
}

void on_logger(const Option &o)
{
    start_logger(o);
}

void on_threads(const Option &o)
{
    Threads.set(static_cast<size_t>(o));
}

void on_skill_level(const Option &o)
{
    gameOptions.setSkillLevel(static_cast<int>(o));
}

void on_move_time(const Option &o)
{
    gameOptions.setMoveTime(static_cast<int>(o));
}

void on_aiIsLazy(const Option &o)
{
    gameOptions.setAiIsLazy(static_cast<bool>(o));
}

void on_random_move(const Option &o)
{
    gameOptions.setShufflingEnabled(o);
}

void on_algorithm(const Option &o)
{
    gameOptions.setAlgorithm(static_cast<int>(o));
}

void on_drawOnHumanExperience(const Option &o)
{
    gameOptions.setDrawOnHumanExperience(o);
}

void on_considerMobility(const Option &o)
{
    gameOptions.setConsiderMobility(o);
}

void on_developerMode(const Option &o)
{
    gameOptions.setDeveloperMode(o);
}

// Rules

void on_piecesCount(const Option &o)
{
    rule.pieceCount = static_cast<int>(o);
}

void on_flyPieceCount(const Option &o)
{
    rule.flyPieceCount = static_cast<int>(o);
}

void on_piecesAtLeastCount(const Option &o)
{
    rule.piecesAtLeastCount = static_cast<int>(o);
}

void on_hasDiagonalLines(const Option &o)
{
    rule.hasDiagonalLines = static_cast<bool>(o);
}

void on_hasBannedLocations(const Option &o)
{
    rule.hasBannedLocations = static_cast<bool>(o);
}

void on_mayMoveInPlacingPhase(const Option &o)
{
    rule.mayMoveInPlacingPhase = static_cast<bool>(o);
}

void on_isDefenderMoveFirst(const Option &o)
{
    rule.isDefenderMoveFirst = static_cast<bool>(o);
}

void on_mayRemoveMultiple(const Option &o)
{
    rule.mayRemoveMultiple = static_cast<bool>(o);
}

void on_mayRemoveFromMillsAlways(const Option &o)
{
    rule.mayRemoveFromMillsAlways = static_cast<bool>(o);
}

void on_mayOnlyRemoveUnplacedPieceInPlacingPhase(const Option &o)
{
    rule.mayOnlyRemoveUnplacedPieceInPlacingPhase = static_cast<bool>(o);
}

void on_isWhiteLoseButNotDrawWhenBoardFull(const Option &o)
{
    rule.isWhiteLoseButNotDrawWhenBoardFull = static_cast<bool>(o);
}

void on_isLoseButNotChangeSideWhenNoWay(const Option &o)
{
    rule.isLoseButNotChangeSideWhenNoWay = static_cast<bool>(o);
}

void on_mayFly(const Option &o)
{
    rule.mayFly = static_cast<bool>(o);
}

void on_nMoveRule(const Option &o)
{
    rule.nMoveRule = static_cast<unsigned>(o);
}

void on_endgameNMoveRule(const Option &o)
{
    rule.endgameNMoveRule = static_cast<unsigned>(o);
}

void on_threefoldRepetitionRule(const Option &o)
{
    rule.threefoldRepetitionRule = static_cast<bool>(o);
}

/// Our case insensitive less() function as required by UCI protocol
bool CaseInsensitiveLess::operator()(const string &s1, const string &s2) const
{
    return std::lexicographical_compare(
        s1.begin(), s1.end(), s2.begin(), s2.end(),
        [](char c1, char c2) noexcept { return tolower(c1) < tolower(c2); });
}

/// UCI::init() initializes the UCI options to their hard-coded default values

void init(OptionsMap &o)
{
    constexpr int MaxHashMB = Is64Bit ? 33554432 : 2048;

    o["Debug Log File"] << Option("", on_logger);
    o["Contempt"] << Option(24, -100, 100);
    o["Analysis Contempt"] << Option("Both var Off var White var Black var "
                                     "Both",
                                     "Both");
    o["Threads"] << Option(1, 1, 512, on_threads);
    o["Hash"] << Option(16, 1, MaxHashMB, on_hash_size);
    o["Clear Hash"] << Option(on_clear_hash);
    o["Ponder"] << Option(false);
    o["MultiPV"] << Option(1, 1, 500);
    o["SkillLevel"] << Option(1, 0, 30, on_skill_level);
    o["MoveTime"] << Option(1, 0, 60, on_move_time);
    o["AiIsLazy"] << Option(false, on_aiIsLazy);
    o["Move Overhead"] << Option(10, 0, 5000);
    o["Slow Mover"] << Option(100, 10, 1000);
    o["nodestime"] << Option(0, 0, 10000);
    o["UCI_AnalyseMode"] << Option(false);
    o["UCI_LimitStrength"] << Option(false);
    o["UCI_Elo"] << Option(1350, 1350, 2850);

    o["Shuffling"] << Option(true, on_random_move);
    o["Algorithm"] << Option(2, 0, 2, on_algorithm);
    o["DrawOnHumanExperience"] << Option(true, on_drawOnHumanExperience);
    o["ConsiderMobility"] << Option(true, on_considerMobility);
    o["DeveloperMode"] << Option(true, on_developerMode);

    // Rules
    o["PiecesCount"] << Option(9, 9, 12, on_piecesCount);
    o["flyPieceCount"] << Option(3, 3, 4, on_flyPieceCount);
    o["PiecesAtLeastCount"] << Option(3, 3, 5, on_piecesAtLeastCount);
    o["HasDiagonalLines"] << Option(false, on_hasDiagonalLines);
    o["HasBannedLocations"] << Option(false, on_hasBannedLocations);
    o["MayMoveInPlacingPhase"] << Option(false, on_mayMoveInPlacingPhase);
    o["IsDefenderMoveFirst"] << Option(false, on_isDefenderMoveFirst);
    o["MayRemoveMultiple"] << Option(false, on_mayRemoveMultiple);
    o["MayRemoveFromMillsAlways"] << Option(false, on_mayRemoveFromMillsAlways);
    o["MayOnlyRemoveUnplacedPieceInPlacingPhase"]
        << Option(false, on_mayOnlyRemoveUnplacedPieceInPlacingPhase);
    o["IsWhiteLoseButNotDrawWhenBoardFull"]
        << Option(true, on_isWhiteLoseButNotDrawWhenBoardFull);
    o["IsLoseButNotChangeSideWhenNoWay"]
        << Option(true, on_isLoseButNotChangeSideWhenNoWay);
    o["MayFly"] << Option(true, on_mayFly);
    o["NMoveRule"] << Option(100, 10, 200, on_nMoveRule);
    o["EndgameNMoveRule"] << Option(100, 5, 200, on_endgameNMoveRule);
    o["ThreefoldRepetitionRule"] << Option(true, on_threefoldRepetitionRule);
}

/// operator<<() is used to print all the options default values in
/// chronological insertion order (the idx field) and in the format defined by
/// the UCI protocol.

std::ostream &operator<<(std::ostream &os, const OptionsMap &om)
{
    for (size_t idx = 0; idx < om.size(); ++idx)
        for (const auto &[fst, snd] : om)
            if (snd.idx == idx) {
                const Option &o = snd;
                os << "\noption name " << fst << " type " << o.type;

                if (o.type == "string" || o.type == "check" ||
                    o.type == "combo")
                    os << " default " << o.defaultValue;

                if (o.type == "spin")
                    os << " default " << static_cast<int>(stof(o.defaultValue))
                       << " min " << o.min << " max " << o.max;

                break;
            }

    return os;
}

/// Option class constructors and conversion operators

Option::Option(const char *v, OnChange f)
    : type("string")
    , min(0)
    , max(0)
    , on_change(f)
{
    defaultValue = currentValue = v;
}

Option::Option(bool v, OnChange f)
    : type("check")
    , min(0)
    , max(0)
    , on_change(f)
{
    defaultValue = currentValue = (v ? "true" : "false");
}

Option::Option(OnChange f)
    : type("button")
    , min(0)
    , max(0)
    , on_change(f)
{ }

Option::Option(double v, int minv, int maxv, OnChange f)
    : type("spin")
    , min(minv)
    , max(maxv)
    , on_change(f)
{
    defaultValue = currentValue = std::to_string(v);
}

Option::Option(const char *v, const char *cur, OnChange f)
    : type("combo")
    , min(0)
    , max(0)
    , on_change(f)
{
    defaultValue = v;
    currentValue = cur;
}

Option::operator double() const
{
    assert(type == "check" || type == "spin");
    return (type == "spin" ? stod(currentValue) : currentValue == "true");
}

Option::operator std::string() const
{
    assert(type == "string");
    return currentValue;
}

bool Option::operator==(const char *s) const
{
    assert(type == "combo");
    return !CaseInsensitiveLess()(currentValue, s) &&
           !CaseInsensitiveLess()(s, currentValue);
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

    if ((type != "button" && v.empty()) ||
        (type == "check" && v != "true" && v != "false") ||
        (type == "spin" && (stof(v) < min || stof(v) > max)))
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
