# Sanmill Programmer's Guide

Sanmill is a mill game program.

Usage of the source code is governed by the GPL license: see `Copying.txt` for details.

Sanmill includes a console-based mill game engine that be used with separately available interface for mill game programs, or with UCI-like interface programs. In addition, two custom Flutter/Qt user interface programs for Sanmill are available; the Flutter frontend communicates with the mill game engine using a channel.

Sanmill is written in C++ and Dart. The Sanmill mill game engine supports both Windows (32- or 64-bit versions) and other platforms such as Linux.

Sanmill has mostly been tested on Intel & AMD processors but the code is designed to be portable to other processors.

The remainder of this file contains information for use by programmers reading or working on Sanmill source code. I assume that you have a working familiarity with C++. Also, if you have no background in computer board game, you should probably start by reading some of the reference material mentioned at the end of this document.

## Building Sanmill

See the BUILD.md file for current build instructions.

## Learning

Sanmill has positional learning (a.k.a "permanent brain"). It is basically a persistent hash table. If a search returns an unexpectedly high or low score, the position and its score are stored in a text file called `endgame.txt`, which is located in the same directory as the Sanmill executable. When the next game is started, stored positions from this file are read into memory and stored in the hash table, enabling the program to detect danger or opportunity sooner than it did previously.

## Testing support

Sanmill includes several features to aid debugging. If you compile the source for [**AddressSanitizer**](https://clang.llvm.org/docs/AddressSanitizer.html) (with `--fsanitize`), checks are inserted for accessing arrays past their boundaries, as well as some other sanity checks. If any of these checks fail, an error message will be displayed.

The mill game engine supports a couple of commands to aid with testing.

## Algorithms and data structures

### The mill game board

Following is some information about the algorithms and data structures used by Sanmill.

The mill game board in Sanmill is represented by an array of `24` squares (points), laid out so that square `A1` has the value `8` and square `C8` has the value `31`.

Each square contains `SQ_NONE` if it is empty, or a piece identifier if it is occupied. White pieces have identifier values between `W_PIECE_1` and `W_PIECE_12`, while Black pieces have values between `B_PIECE_1` and `B_PIECE_12`. A special value (`MARKED_PIECE`) is used to represent a square that is marked.

The Board class also maintains several "bit boards" or quantities that hold 32 bits. The Bitboard class in the source encapsulates a bit board. For example, the occupied bit board has one bit set for every piece that is on the board (there are actually three such bit boards, one for White, one for Black, and one for Marked).

Each type of piece has its own bit board that has one bit set for each piece of that type (for example, there is a `byTypeBB[MARKED]` Bitboard to hold marked locations).

Besides the bit boards, there is some other information in the Board structure. The `StarSquareBB` variable holds the 'star' square position.

Each board position also has a hash code associated with it. The hash code is 32 bits and is computed by fetching, for each piece and square combination, a unique 32-bit code from a table of random numbers, and computing the exclusive or of these codes. (This hashing mechanism was invented by Zobrist - see references). The high-order 2 bits of the hash code are then set to identify how many pieces can be removed.

### Moves

Sanmill uses a 32-bit word to store move information. Each move contains a start square and destination square. If the start square is 0, the move type is placement, and if the 32-bit word is negative, the move type is removal.

### Move Generator

The move generation logic is mostly contained in the `generate` functions.

The  `generate<LEGAL>` functions has separate routines to find all moves.

Move generation occurs in a specific order, see `movegen.cpp`.

### Searching

Sanmill uses an alpha-beta search algorithm with a variety of search extensions. The search namespace is the largest single module in the program, and is necessarily rather complicated, but I have tried to structure it and comment it so that it is understandable. I will assume that the reader knows the basics of the alpha-beta algorithm, and will concentrate on describing this implementation of it.

In general, the search routine tries to terminate a search tree, or some portion of one, as soon as possible, and will defer as much work as possible until it is certain that no earlier and quicker termination can be done. The techniques for doing this are mostly well-known and there is nothing very original about the search algorithms used by Sanmill. However, as with most chess programs, there is a fine balance between terminating a search too soon and extending it into unprofitable and very unlikely lines of play. The precise nature of this balance depends not only on the search algorithms used, but also the relative efficiency of operations such as move generation, position evaluation and move ordering. Each program therefore strikes this balance in a somewhat different way.

The entry point for a search is a routine called `Thread::search()`. This function does some initialization, and then calls `MTDF()`, which implements the [MTD(f)](https://www.chessprogramming.org/MTD(f)) search algorithm. In order to work, MTD(f) needs a *first guess* as to where the minimax value will turn out to be. The better than first guess is, the more efficient the algorithm will be, on average, since the better it is, the less passes the repeat-until loop will have to do to converge on the minimax value. If you feed MTD(f) the minimax value to start with, it will only do two passes, the bare minimum: one to find an [upper bound](https://www.chessprogramming.org/Upper_Bound) of value x, and one to find a [lower bound](https://www.chessprogramming.org/Lower_Bound) of the same value. The `MTDF()` function calls `search()`, which implements the alpha-beta search algorithm. The search proceeds one ply (half move, i.e. move by one side) at a time. That is, first a one-ply search is done, then a two-ply search, then three, etc. until either the maximum ply limit has been reached or the time control has been exceeded. Each search uses the results of the preceding search. The variable "`originDepth`" holds the current nominal ply depth for the search. However, the presence of search extensions means that some nodes may be searched to a greater or shallower depth than this.

`search()` does some other special processing because it is at the top of the search tree. This function then calls `search()` to recursively process lower-depth nodes.

The first step in search() is to check if the current board position is drawn, due to a 3-fold repetition of moves, or the N-move rule.

Sanmill will also terminate the search immediately if the absolute maximum ply depth is reached. This is quite unlikely.

If no draw is present and the maximum depth hasn't been reached, the next step is to look in the hash table (further described in the next section), in order to see if an identical position has been visited before. This may happen due to a transposition of moves that lead to the same position, or because a previous search to a shallower depth visited the same node. If a hash table entry is found and if it contains a valid value (i.e. one that did not cause cutoff), then that value is returned immediately and no further searching from that node occurs. In other cases, the hash table may not contain an exact value, but may hold an upper or lower bound that can be used to narrow the alpha-beta window.

### The hash table

The search routine uses a hash table for storing the results of evaluating previously visited positions. This table is implemented in several static functions defined in `tt.cpp`. The hash table is basically an array of lists. Each list contains a series of nodes, each of which contains some data. Each list holds entries that hash, modulo the hash table size, to the same value. Each node contains the whole hash code, so that finding a given node to match a given hash code consists of indexing into the hash table, then following the list until the full 32-bit hash codes match.

Besides the hash code, each hash entry also contains the score for the node, a set of flags indicating whether the value is exact, an upper bound or a lower bound, the depth of search used to evaluate the node.

The hash table is limited in size and may fill up during a long search. In this case, we have a choice: when a new position is encountered, we can overwrite an existing entry in the hash table with the new position, or we can discard the information for the new position and not put it into the hash table.

Sanmill will generally only replace entries that have greater depth than existing entries, or entries that came from an earlier search (i.e. whose "`age`" field does not match the current search).

The size of the main hash table defaults to 128 Megabytes. Standard UCI option commands can also be used to alter the hash table size at runtime.

### Position Scoring

There are roughly three main components to the positional score used by Sanmill:

1. Number of pieces in hand
2. Number of pieces on board
3. Number of pieces can be removed

The positional score is typically within the range of plus or minus the value of a piece (5), but can be greater in some circumstances.

Pawn structure scoring is done in two stages. First, the hash table is probed to get the score for the position. If the position is not found in the hash table, then the `Evaluation::value()` routine is called. This routine only computes scoring parameters that depend only on the count of pieces.

## Flutter user interface

The mill game engine is now run as a separate process that communicates with the user interface through a channel.

Compared to Qt UI, the Flutter UI lacks some features: for example, it cannot be used to communicate with a mill game server.

The Flutter user interface is a pretty standard Dart program.

## Support

While no formal support is offered for this software, if you do find bugs in it, or discover a way to improve it, I would like to hear from you.

Contact information and additional information about Sanmill can be found at https://github.com/calcitem/Sanmill

## Deploy

### Android

Use [GitHub Actions](https://github.com/calcitem/Sanmill/actions) to build.

Download `aab` file and upload to [Play Console](https://play.google.com/console).

Download `apk` from `Bundle Explorer Selector` and upload to [Cafe Bazaar](https://pishkhan.cafebazaar.ir/apps/com.calcitem.sanmill/releases) and other app stores.

### iOS

```shell
./flutter-init.sh
cd src/ui/flutter_app
flutter build ios --release -v
```

Use `Xcode -> Product -> Archive` to archive and upload ipa.

Wait for a while, open [App Store Connect](https://appstoreconnect.apple.com/apps/1662297339/appstore/ios/version/deliverable), add the new version and publish.

### Linux

[Snapcraft](https://snapcraft.io/mill/):

```shell
cd Sanmill
rm *.snap
snapcraft --use-lxd
sudo snap remove mill
sudo snap install --dangerous mill*.snap
sudo snap remove mill
snapcraft login
snapcraft upload --release=stable mill*.snap
```

### Windows

```shell
./flutter-windows-init.sh
cd src/ui/flutter_app
flutter pub run msix:create
```

Use `Windows App Cert Kit` to verify `src\ui\flutter_app\build\windows\runner\Release\sanmill.msix`.

Open [Microsoft Partner](https://partner.microsoft.com/), and upload the msix file.

## References

[Arasan Programmer's Guide - version 22.0](https://www.arasanchess.org/programr.html)

Chess Programming Wiki, topic [Magic Bitboards](http://chessprogramming.org/Magic_Bitboards).

[Stockfish source code](https://github.com/official-stockfish).

Donninger, Ch. (1993). "Null Move and Deep Search" ICCA Journal, v. 16 no. 3.

Duchi, John, Hazan, Elad and Singer, Yoram. "Adaptive Subgradient Methods for Online Learning and Stochastic Optimization" Journal of Machine Learning Research, Volume 12, 2/1/2011, pp. 2121-2159.

Ebeling, Carl. (1987). All The Right Moves: A VLSI Architecture for Chess. MIT Press.

Frey, Peter W. (ed.) (1983). Chess Skill in Man and Machine. New York: Springer-Verlag.

Hoki, Kunihuto and Kaneko, Tomoyuki "Large-Scale Optimization for Evaluation Functions with Minimax Search," Journal of Artificial Intelligence Research 49 (2014) 527-568.

Kingman, Diederik P. and Ba, Jimmy Lei [ADAM: A Method For Stochastic Optimization](https://arxiv.org/pdf/1412.6980v8.pdf), ICLR 2015.

Lai, Matthew (2015) [Giraffe: Using Deep Reinforcement Learning to Play Chess](https://arxiv.org/abs/1509.01549). MSc Dissertation, Imperial College, London.

Marsand, T. Anthony and Schaeffer, Jonathan (1990). Computers, Chess and Cognition. New York: Springer-Verlag.

Thompson, William R. "On the likelihood that one unknown probability exceeds another in view of the evidence of two samples". Biometrika, 25(3–4):285–294, 1933

Wegner, Zach (2011) [Haswell New Instructions](http://www.talkchess.com/forum/viewtopic.php?topic_view=threads&p=423024&t=40333&sid=7048574dbf26d14dfc7479d6fe9c2f23).

Zobrist, A. L. (1970). "A new hashing method with applications for game playing," Technical report 88, Computer Science Department, University of Wisconsin.
