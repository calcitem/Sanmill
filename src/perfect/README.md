# How to Use

## Download database

Download [MuehleWin_Database_ver1.0.zip](https://www.mad-weasel.de/download/MuehleWin_Database_ver1.0.zip) (Version 1.0, 1. Jan 2019, 8.3GB) on [Nine Men's Morris Game - The perfect playing computer](https://www.mad-weasel.de/morris.html).

Extract the zip file.

## Load and run

Use Microsoft Visual Studio to open `millgame.sln`.

Specify database path in `include/config.h` -> PERFECT_AI_DATABASE_DIR.

Enable `MADWEASEL_MUEHLE_PERFECT_AI` in `include/config.h` .

Build and run.

Select `Rules -> Nine men's morris`.

Select `AI -> Perfect AI`.

Now you can play with the Perfect AI.

## Note

Currently, the game rule of Nine men's morris is not standard. Search`MADWEASEL_MUEHLE_RULE` to see detail.

## Thanks

Perfect AI was developed by [Thomas Weber](https://www.mad-weasel.de/index_eng.html) initially.
