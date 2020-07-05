/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

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

#include "endgame.h"

#ifdef ENDGAME_LEARNING
static constexpr int endgameHashsize = 0x1000000; // 16M
HashMap<key_t, Endgame> endgameHashMap(endgameHashsize);

void mergeEndgameFile(QString file1, QString file2, QString mergedFile)
{
    HashMap<key_t, Endgame> map1(endgameHashsize);
    HashMap<key_t, Endgame> map2(endgameHashsize);

    map1.load(file1);
    map2.load(file2);

    map1.merge(map2);

    map1.dump(mergedFile);

    loggerDebug("[endgame] Merge %s to %s and save to %s\n",
                file2.toStdString().c_str(),
                file1.toStdString().c_str(),
                mergedFile.toStdString().c_str());
}

int mergeEndgameFile_main()
{
    QString filename;

    for (int i = 1; i <= 12; i++) {
        filename = QString::number(i, 10) + "/endgame.txt";
        mergeEndgameFile("endgame.txt", filename, "endgame.txt");
    }

#ifdef _WIN32
    system("pause");
#endif

    return 0;
}

#endif // ENDGAME_LEARNING
