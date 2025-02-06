/*******************************************************************************
 * cui_interface.cpp
 *
 * A simple ncurses-based interface for the Sanmill.
 *
 * Compile and link with:
 *   g++ -o sanmill_cui main.cpp position.cpp search_engine.cpp \
 *       uci.cpp cui_interface.cpp -lncurses
 *
 * Then run:
 *   ./sanmill_cui
 *
 * This code assumes you already have your engine code (Position, SearchEngine,
 * UCI, etc.) in the same project. Adjust #include paths as necessary.
 ******************************************************************************/

#include <ncurses.h>
#include <string>
#include <vector>
#include <algorithm>
#include <cctype>
#include <sstream>
#include <iostream>

// Include the engine headers you shared previously:
#include "position.h"
#include "search_engine.h"
#include "uci.h"
#include "movegen.h"
#include "misc.h"
#include "thread.h"

/// For convenience, forward declarations of some helper functions:
static void initScreen();
static void shutdownScreen();
static void drawBoard(const Position &pos, int cursorSquare);
static void drawControls(const Position &pos);
static int getCursorFromArrowKeys(int currentCursor, int ch, const Position &pos);
static void handleUserInput(Position &pos, SearchEngine &engine);

/// Main function illustrating an ncurses-driven loop.
int run_ncurses_interface()
{
    // Initialize the engine code
    // (Your engine's normal main does something similar)
    UCI::init(Options);
    Bitboards::init();
    Position::init();
    Threads.set(static_cast<size_t>(Options["Threads"]));
    Search::clear();

    // Create position and engine objects
    Position pos;
    pos.reset();
    // Optionally start the game so we are in the "placing" phase
    pos.start();

    // Create the search engine
    SearchEngine engine;
    engine.setRootPosition(&pos);

    initScreen();

    bool running = true;
    while (running)
    {
        clear(); // Clear the ncurses screen

        // Draw the current board and controls
        drawBoard(pos, /*cursorSquare=*/-1);
        drawControls(pos);

        // Refresh the screen
        refresh();

        // Handle the user input (blocking)
        handleUserInput(pos, engine);

        // Check end conditions (just a simple placeholder; expand as needed)
        if (pos.get_phase() == Phase::gameOver) {
            // Could show a "Game over!" message here
            running = false;
        }
    }

    // Before exiting, tidy up
    shutdownScreen();
    Threads.set(0); // Shut down any worker threads from the engine
    return 0;
}

/// Helper: Initialize ncurses, set some modes, start color if supported.
static void initScreen()
{
    initscr();       // Start ncurses
    cbreak();        // Disable line buffering, pass on every keypress
    noecho();        // Don't echo typed characters
    keypad(stdscr, true);  // Enable arrow keys, F-keys, etc.
    curs_set(0);     // Hide the text cursor

    // If the terminal supports color, set up some pairs
    if (has_colors())
    {
        start_color();
        // A few example color pairs:
        init_pair(1, COLOR_WHITE, COLOR_BLACK);
        init_pair(2, COLOR_BLACK, COLOR_WHITE);
        init_pair(3, COLOR_RED,   COLOR_BLACK);
        init_pair(4, COLOR_CYAN,  COLOR_BLACK);
        // ... add more as you like
    }
}

/// Helper: Restore the screen to normal state before exiting.
static void shutdownScreen()
{
    endwin();
}

/// This function draws the 2D ASCII board in an ncurses window.
/// You can adapt the layout or add colors.
static void drawBoard(const Position &pos, int cursorSquare)
{
    // We'll offset the board's top-left corner in the ncurses window
    int startRow = 1;
    int startCol = 2;

    // Print a heading
    mvprintw(startRow - 1, startCol, "Nine Men's Morris (Sanmill Engine) Board:");

    // We'll reuse your ASCII layout from operator<<(std::ostream&, const Position&).
    // But we place them carefully on ncurses lines:
    // For each rank in [RANK_1..RANK_8], we map them onto rows of text.

    // The custom ASCII layout:
    //
    //   31 --- 24 --- 25
    //   | \    |    / |
    //   | 23 - 16 - 17 |
    //   | | \  |  / | |
    //   | | 15-08-09| |
    //   30-22-14   10-18-26
    //   | | 13-12-11| |
    //   | |/   |   \| |
    //   | 21 - 20 - 19 |
    //   |/     |     \|
    //   29 --- 28 --- 27
    //
    // This is 11 lines of text. We'll print them row by row.
    // We'll fill in the squares with piece chars.
    // We'll also highlight the cursorSquare if it's >= 0.

    // We'll define a helper lambda to get the char from the position:
    auto getChar = [&](Square s) -> char {
        Piece pc = pos.piece_on(s);
        if (pc == NO_PIECE)  return '*';
        if (pc == MARKED_PIECE) return 'X';
        if ((pc & 0xF0) == 0x10) return 'O'; // White piece
        if ((pc & 0xF0) == 0x20) return '@'; // Black piece
        return '*';
    };

    // We define a small helper to color or highlight specific squares:
    // If the square is the cursorSquare, highlight it in reverse color
    auto printSquare = [&](int row, int col, Square sq) {
        char c = getChar(sq);
        if (sq == cursorSquare) {
            attron(COLOR_PAIR(2)); // Reverse color pair
            mvprintw(row, col, "%c", c);
            attroff(COLOR_PAIR(2));
        } else {
            // Maybe color white pieces in white, black in red, etc.
            Piece pc = pos.piece_on(sq);
            if ((pc & 0xF0) == 0x10)      attron(COLOR_PAIR(1)); // White
            else if ((pc & 0xF0) == 0x20) attron(COLOR_PAIR(3)); // Black
            else if (pc == MARKED_PIECE)  attron(COLOR_PAIR(4)); // Marked
            mvprintw(row, col, "%c", c);
            if ((pc & 0xF0) == 0x10)      attroff(COLOR_PAIR(1));
            else if ((pc & 0xF0) == 0x20) attroff(COLOR_PAIR(3));
            else if (pc == MARKED_PIECE)  attroff(COLOR_PAIR(4));
        }
    };

    // We'll actually just store lines of text, but whenever we see a square number,
    // we call printSquare. For brevity, we'll manually place them:

    // Row 0
    mvprintw(startRow + 0, startCol,    "31 --- 24 --- 25");
    // Overwrite the numbers with piece symbols:
    printSquare(startRow + 0, startCol +  0, Square(31));
    printSquare(startRow + 0, startCol +  8, Square(24));
    printSquare(startRow + 0, startCol + 14, Square(25));

    // Row 1
    mvprintw(startRow + 1, startCol,    "| \\    |    / |");

    // Row 2
    mvprintw(startRow + 2, startCol,    "| 23 - 16 - 17 |");
    printSquare(startRow + 2, startCol +  2, Square(23));
    printSquare(startRow + 2, startCol +  7, Square(16));
    printSquare(startRow + 2, startCol + 11, Square(17));

    // Row 3
    mvprintw(startRow + 3, startCol,    "| | \\  |  /|  |");

    // Row 4
    mvprintw(startRow + 4, startCol,    "| | 15-08-09| |");
    printSquare(startRow + 4, startCol + 4,  Square(15));
    printSquare(startRow + 4, startCol +  7, Square(8));
    printSquare(startRow + 4, startCol + 10, Square(9));

    // Row 5
    mvprintw(startRow + 5, startCol,    "30-22-14   10-18-26");
    printSquare(startRow + 5, startCol +  0, Square(30));
    printSquare(startRow + 5, startCol +  3, Square(22));
    printSquare(startRow + 5, startCol +  6, Square(14));
    printSquare(startRow + 5, startCol + 11, Square(10));
    printSquare(startRow + 5, startCol + 14, Square(18));
    printSquare(startRow + 5, startCol + 17, Square(26));

    // Row 6
    mvprintw(startRow + 6, startCol,    "| | 13-12-11| |");
    printSquare(startRow + 6, startCol + 4, Square(13));
    printSquare(startRow + 6, startCol +  7, Square(12));
    printSquare(startRow + 6, startCol + 10, Square(11));

    // Row 7
    mvprintw(startRow + 7, startCol,    "| |/   |   \\| |");

    // Row 8
    mvprintw(startRow + 8, startCol,    "| 21 - 20 - 19 |");
    printSquare(startRow + 8, startCol +  2, Square(21));
    printSquare(startRow + 8, startCol +  7, Square(20));
    printSquare(startRow + 8, startCol + 11, Square(19));

    // Row 9
    mvprintw(startRow + 9, startCol,    "|/     |     \\|");

    // Row 10
    mvprintw(startRow + 10, startCol,   "29 --- 28 --- 27");
    printSquare(startRow + 10, startCol + 0,  Square(29));
    printSquare(startRow + 10, startCol +  8, Square(28));
    printSquare(startRow + 10, startCol + 14, Square(27));
}

/// Print instructions or status lines at the bottom of the screen.
static void drawControls(const Position &pos)
{
    int row = 14; // Just below the board
    int col = 2;

    // Show phase, side to move
    std::string phaseStr;
    switch (pos.get_phase()) {
        case Phase::none:    phaseStr = "none";       break;
        case Phase::ready:   phaseStr = "ready";      break;
        case Phase::placing: phaseStr = "placing";    break;
        case Phase::moving:  phaseStr = "moving";     break;
        case Phase::gameOver:phaseStr = "gameOver";   break;
    }

    std::string colorStr;
    switch (pos.side_to_move()) {
        case WHITE: colorStr = "WHITE"; break;
        case BLACK: colorStr = "BLACK"; break;
        default:    colorStr = "NONE";
    }

    mvprintw(row, col, "Phase: %s, Side to move: %s", phaseStr.c_str(), colorStr.c_str());
    ++row;

    // Some user instructions:
    mvprintw(row++, col, "Controls:");
    mvprintw(row++, col, "  Arrows: highlight squares");
    mvprintw(row++, col, "  [Enter]: place/move if valid, or select piece");
    mvprintw(row++, col, "  R: remove piece (if allowed)");
    mvprintw(row++, col, "  S: start the game (if in 'ready' state)");
    mvprintw(row++, col, "  Q: quit");

    // Possibly show the last move or record
    mvprintw(row++, col, "Last record: %s", pos.get_record());
}

/// Helper: Move cursor around the board using arrow keys. Return the updated square index.
static int getCursorFromArrowKeys(int currentCursor, int ch, const Position & /*pos*/)
{
    // The board squares go from 8..31 (SQUARE_BEGIN..SQUARE_END in your code).
    // We can cheat and cycle them. Or do something fancier.

    int newCursor = currentCursor;
    switch(ch)
    {
        case KEY_LEFT:
            --newCursor;
            if (newCursor < 8) newCursor = 31;
            break;
        case KEY_RIGHT:
            ++newCursor;
            if (newCursor > 31) newCursor = 8;
            break;
        case KEY_UP:
            // We do a smaller jump or some custom logic
            newCursor -= 2;
            if (newCursor < 8) newCursor = 8;
            break;
        case KEY_DOWN:
            newCursor += 2;
            if (newCursor > 31) newCursor = 31;
            break;
        default:
            break;
    }
    return newCursor;
}

/// The main input loop for a single iteration: waits for a keypress, does actions.
static void handleUserInput(Position &pos, SearchEngine &engine)
{
    // We'll track a "current cursor" for highlight. If you prefer mouse or direct
    // coordinate entry, adapt as desired. We can store static data in function
    // scope for demonstration.
    static int cursor = 8; // Start highlight on square #8

    // We re-draw the board with the highlight
    drawBoard(pos, cursor);
    drawControls(pos);
    refresh();

    int ch = getch(); // block until user hits a key

    switch(ch)
    {
        case 'q':
        case 'Q':
            // To signal upper loop to stop, we might do:
            // Or store some global or static bool. We'll just do a forced "gameOver" phase:
            pos.set_gameover(DRAW, GameOverReason::drawThreefoldRepetition);
            break;

        case 's':
        case 'S':
            // Try to start the game
            pos.start();
            break;

        case KEY_LEFT:
        case KEY_RIGHT:
        case KEY_UP:
        case KEY_DOWN:
            cursor = getCursorFromArrowKeys(cursor, ch, pos);
            break;

        case 10: // Enter key
        {
            // Attempt to place or move:
            // We'll try something simple: we call "pos.put_piece(cursor)" or "pos.move_piece(...)".
            // Because your engine code does logic for placing or selecting, we do:
            char cmd[32];
            // "put" command style: "(f,r)" => e.g., "(1,1)"
            // We must parse the file and rank from "cursor".
            // file = cursor/8, rank = cursor%8
            // but your squares are (f * RANK_NB + r).
            int f = cursor / 8;
            int r = cursor % 8;
            // for display, remember that your code uses (f, r) e.g. "(1,1)->(2,2)"

            snprintf(cmd, sizeof(cmd), "(%d,%d)", f, r);
            pos.command(cmd); // The engine attempts to interpret it as a move
        }
            break;

        case 'r':
        case 'R':
        {
            // remove piece: "-(f,r)"
            int f = cursor / 8;
            int r = cursor % 8;
            char cmd[32];
            snprintf(cmd, sizeof(cmd), "-(%d,%d)", f, r);
            pos.command(cmd);
        }
            break;

        default:
            break;
    }

    // Optionally, we can ask the AI to move if it's now the AI's turn:
    if (pos.side_to_move() == BLACK) // or whichever side is "AI"
    {
        // Here we can run a quick search
        engine.searchAborted = false;
        engine.beginNewSearch(&pos); // sets a new searchId
        Move bestM = MOVE_NONE;
        if (engine.executeSearch() != 0)
        {
            bestM = engine.bestMove;
        }
        if (bestM != MOVE_NONE) {
            // Convert the best move to string and pass to pos.command(...)
            // or we can call pos.do_move(bestM) directly.
            // For demonstration, do:
            std::string bmStr = UCI::move(bestM);
            pos.command(bmStr.c_str());
        }
    }
}
