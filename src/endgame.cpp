// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// endgame.cpp

#include "endgame.h"
#include <string>

using std::string;

#ifdef ENDGAME_LEARNING
static constexpr int endgameHashSize = 0x1000000; // 16M
HashMap<Key, Endgame> endgameHashMap(endgameHashSize);

// Function to probe the endgame hash map
bool probeEndgameHash(Key posKey, Endgame &endgame)
{
    return endgameHashMap.find(posKey, endgame);
}

// Function to save an endgame entry to the hash map
int saveEndgameHash(Key posKey, const Endgame &endgame)
{
    Key hashValue = endgameHashMap.insert(posKey, endgame);
    unsigned addr = hashValue * (sizeof(posKey) + sizeof(endgame));

    debugPrintf("[endgame] Record 0x%08I32x (%d) to Endgame hash map, TTEntry: "
                "0x%08I32x, Address: 0x%08I32x\n",
                posKey, static_cast<int>(endgame.type), hashValue, addr);

    return 0;
}

// Function to clear the endgame hash map
void clearEndgameHashMap()
{
    endgameHashMap.clear();
}

// Function to save the endgame hash map to a file
void saveEndgameHashMapToFile()
{
    const string filename = "endgame.txt";
    endgameHashMap.dump(filename);

    debugPrintf("[endgame] Dump hash map to file\n");
}

// Function to load the endgame hash map from a file
void loadEndgameFileToHashMap()
{
    const string filename = "endgame.txt";
    endgameHashMap.load(filename);
}

// Optional: Function to merge two endgame files into a merged file
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

// Optional: Main function to merge multiple endgame files
int mergeEndgameFile_main()
{
    string filename;

    for (char ch = '0'; ch <= '9'; ch++) {
        filename = string(1, ch) + "/endgame.txt";
        mergeEndgameFile("endgame.txt", filename, "endgame.txt");
    }

#ifdef _WIN32
    system("pause");
#endif

    return 0;
}

#endif // ENDGAME_LEARNING
