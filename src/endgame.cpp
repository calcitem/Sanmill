// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

#include "endgame.h"
#include <string>

using std::string;

#ifdef ENDGAME_LEARNING
static constexpr int endgameHashSize = 0x1000000; // 16M
HashMap<Key, Endgame> endgameHashMap(endgameHashSize);

void mergeEndgameFile(const string &file1, const string &file2,
                      const string &mergedFile)
{
    HashMap<Key, Endgame> map1(endgameHashSize);
    HashMap<Key, Endgame> map2(endgameHashSize);

    map1.load(file1);
    map2.load(file2);

    map1.merge(map2);

    map1.dump(mergedFile);

    debugPrintf("[endgame] Merge %s to %s and save to %s\n", file2.c_str(),
                file1.c_str(), mergedFile.c_str());
}

int mergeEndgameFile_main()
{
    string filename;

    for (char ch = '0'; ch <= '9'; ch++) {
        filename = ch + "/endgame.txt";
        mergeEndgameFile("endgame.txt", filename, "endgame.txt");
    }

#ifdef _WIN32
    system("pause");
#endif

    return 0;
}

#endif // ENDGAME_LEARNING
