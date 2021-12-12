/*********************************************************************
    miniMaxWin.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#ifndef MINIMAXWIN_H_INCLUDED
#define MINIMAXWIN_H_INCLUDED

// Windows Header Files:
#include "miniMax.h"
#include <condition_variable>
#include <mutex>
#include <queue>
#include <thread>

class MiniMaxGuiField
{
public:
    virtual void setAlignment(wildWeasel::alignment &newAlignment) { }

    virtual void setVisibility(bool visible) { }

    virtual void setState(unsigned int curShowedLayer,
                          MiniMax::StateNumberVarType curShowedState)
    { }
};

class MiniMaxWinInspectDb
{
protected:
    // General Variables
    MiniMax *pMiniMax = nullptr; // pointer to perfect AI class granting the
                                 // access to the database
    MiniMaxGuiField *pGuiField = nullptr;
    bool showingInspectionControls = false;
    unsigned int curShowedLayer = 0;                // current showed layer
    MiniMax::StateNumberVarType curShowedState = 0; // current showed state
    const unsigned int scrollBarWidth = 20;

public:
    // Constructor / destructor
    MiniMaxWinInspectDb(wildWeasel::masterMind *ww, MiniMax *pMiniMax,
                        wildWeasel::alignment &amInspectDb,
                        wildWeasel::font2D *font,
                        wildWeasel::texture *textureLine,
                        MiniMaxGuiField &guiField);
    ~MiniMaxWinInspectDb();

    // Generals Functions
    bool createControls();
    bool showControls(bool visible);
    void resize(wildWeasel::alignment &rcNewArea);
};

class MiniMaxWinCalcDb
{
protected:
    // Calculation variables

    // pointer to engine
    wildWeasel::masterMind *ww = nullptr;

    // pointer to perfect AI class granting the access to the database
    MiniMax *pMiniMax = nullptr;

    // pointer to a stream for the console output of the calculation done by the
    // class MiniMax
    ostream *outputStream = nullptr;

    // buffer linked to the stream, for reading out of the stream into the
    // buffer
    stringbuf outputStringBuf;

    // for formatting the output
    locale myLocale;

    // layer numbers to be tested
    queue<unsigned int> layersToTest;

    thread hThreadSolve;
    thread hThreadTestLayer;
    bool showingCalculationControls = false;
    bool threadSolveIsRunning = false;
    bool threadTestLayerIsRunning = false;
    condition_variable threadConditionVariable;
    mutex threadMutex;

    // positions, metrics, sizes, dimensions
    unsigned int listViewRowHeight = 20; // height in pixel of a single row
    const float defPixelDist = 15;
    const float labelHeight = 30;
    const float buttonHeight = 30;

    // Calculation Functions
    void buttonFuncCalcStartOrContinue(void *pUser);
    void buttonFuncCalcCancel(void *pUser);
    void buttonFuncCalcPause(void *pUser);
    void buttonFuncCalcTest();
    void buttonFuncCalcTestAll(void *pUser);
    void buttonFuncCalcTestLayer(void *pUser);
    void lvSelectedLayerChanged(unsigned int row, unsigned int col,
                                wildWeasel::guiElemEvFol *guiElem, void *pUser);
    static void updateOutputControls(void *pUser);
    void updateListItemLayer(unsigned int layerNumber);
    void updateListItemArray(MiniMax::ArrayInfoChange infoChange);
    void threadSolve();
    void threadProcTestLayer();

public:
    // Constructor / destructor
    MiniMaxWinCalcDb(wildWeasel::masterMind *ww, MiniMax *pMiniMax,
                     wildWeasel::alignment &amCalculation,
                     wildWeasel::font2D *font,
                     wildWeasel::texture *textureLine);
    ~MiniMaxWinCalcDb();

    // Generals Functions
    bool createControls();
    void resize(wildWeasel::alignment &amNewArea);
    bool showControls(bool visible);
    bool isCalculationOngoing();
    MiniMax *getMinimaxPointer() { return pMiniMax; }
    CRITICAL_SECTION *getCriticalSectionOutput()
    {
        return &pMiniMax->csOsPrint;
    };
};

#endif // MINIMAXWIN_H_INCLUDED
