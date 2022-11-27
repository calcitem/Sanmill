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

#include "evaluate.h"
#include "bitboard.h"
#include "option.h"
#include "thread.h"
#include "torch/script.h"

namespace {

class Evaluation
{
public:
    Evaluation() = delete;
    explicit Evaluation(Position &p, torch::jit::script::Module &module1) noexcept
        : pos(p), mod(module1)
    {}

    Evaluation &operator=(const Evaluation &) = delete;
    [[nodiscard]] Value value() const;
    [[nodiscard]] Value value_with_nnue();
    [[nodiscard]] torch::Tensor analysisfen(std::string fen);

private:
    Position &pos;
    torch::jit::script::Module &mod;
    
};

// Evaluation::value() is the main function of the class. It computes the
// various parts of the evaluation and returns the value of the position from
// the point of view of the side to move.

Value Evaluation::value() const
{
    Value value = VALUE_ZERO;
    //torch::Tensor output = torch::zeros({3, 2});
    //std::cout << "ahhahah:" << output << std::endl;
    int pieceInHandDiffCount;
    int pieceOnBoardDiffCount;
    const int pieceToRemoveCount = pos.side_to_move() == WHITE ?
                                       pos.piece_to_remove_count() :
                                       -pos.piece_to_remove_count();

    switch (pos.get_phase()) {
    case Phase::none:
    case Phase::ready:
        break;

    case Phase::placing:
        if (gameOptions.getConsiderMobility()) {
            value += pos.get_mobility_diff();
        }

        pieceInHandDiffCount = pos.piece_in_hand_count(WHITE) -
                               pos.piece_in_hand_count(BLACK);
        value += VALUE_EACH_PIECE_INHAND * pieceInHandDiffCount;

        pieceOnBoardDiffCount = pos.piece_on_board_count(WHITE) -
                                pos.piece_on_board_count(BLACK);
        value += VALUE_EACH_PIECE_ONBOARD * pieceOnBoardDiffCount;

        switch (pos.get_action()) {
        case Action::select:
        case Action::place:
            break;
        case Action::remove:
            value += VALUE_EACH_PIECE_PLACING_NEEDREMOVE * pieceToRemoveCount;
            break;
        case Action::none:
            break;
        }

        break;

    case Phase::moving:
        if (gameOptions.getConsiderMobility()) {
            value += pos.get_mobility_diff();
        }

        value += (pos.piece_on_board_count(WHITE) -
                  pos.piece_on_board_count(BLACK)) *
                 VALUE_EACH_PIECE_ONBOARD;

        switch (pos.get_action()) {
        case Action::select:
        case Action::place:
            break;
        case Action::remove:
            value += VALUE_EACH_PIECE_MOVING_NEEDREMOVE * pieceToRemoveCount;
            break;
        case Action::none:
            break;
        }

        break;

    case Phase::gameOver:
        if (pos.piece_on_board_count(WHITE) + pos.piece_on_board_count(BLACK) >=
            SQUARE_NB) {
            if (rule.isWhiteLoseButNotDrawWhenBoardFull) {
                value -= VALUE_MATE;
            } else {
                value = VALUE_DRAW;
            }
        } else if (pos.get_action() == Action::select &&
                   pos.is_all_surrounded(pos.side_to_move()) &&
                   rule.isLoseButNotChangeSideWhenNoWay) {
            const Value delta = pos.side_to_move() == WHITE ? -VALUE_MATE :
                                                              VALUE_MATE;
            value += delta;
        } else if (pos.piece_on_board_count(WHITE) < rule.piecesAtLeastCount) {
            value -= VALUE_MATE;
        } else if (pos.piece_on_board_count(BLACK) < rule.piecesAtLeastCount) {
            value += VALUE_MATE;
        }

        break;
    }

    if (pos.side_to_move() == BLACK) {
        value = -value;
    }

#ifdef EVAL_DRAW_WHEN_NOT_KNOWN_WIN_IF_MAY_FLY
    if (pos.get_phase() == Phase::moving && rule.mayFly &&
        !rule.hasDiagonalLines) {
        int piece_on_board_count_future_white = pos.piece_on_board_count(WHITE);
        int piece_on_board_count_future_black = pos.piece_on_board_count(BLACK);

        if (pos.side_to_move() == WHITE) {
            piece_on_board_count_future_black -= pos.piece_to_remove_count();
        }

        if (pos.side_to_move() == BLACK) {
            piece_on_board_count_future_white -= pos.piece_to_remove_count();
        }

        // TODO(calcitem): flyPieceCount?
        if (piece_on_board_count_future_black == 3 ||
            piece_on_board_count_future_white == 3) {
            if (abs(value) < VALUE_KNOWN_WIN) {
                value = VALUE_DRAW;
            }
        }
    }
#endif

    return value;
}


//将fen串进行split

std::vector<string> split(std::string fen) {
    vector<string> ans;
    int i = 0;
    string t = "";
    while (fen[i] != ' ') {
        t.push_back(fen[i]);
        i++;
    }
    ans.push_back(t);

    for (int j = 0; j < 10; j++) {
        i++;
        t.clear();
        t.push_back(fen[i]);
        i++;
        ans.push_back(t);
    }
    
    return ans;
}

//将棋盘表示从字符转换为数值。对应着28个特征。

torch::Tensor Evaluation::analysisfen(std::string fen)
{
    vector<string> ls1 = split(fen);
    vector<float> anst;
    bool white = true;

    for (int i = 0; i < ls1[0].size(); i++) {
        if (ls1[0][i] == '*') {
            anst.push_back(0);
        }
        else if (ls1[0][i] == '@') {
            anst.push_back(-1);
        } else if (ls1[0][i] == 'O') {
            anst.push_back(1);
        }     
    }

    if (ls1[1] == "b") {
        white = false;
        for (int i = 0; i < anst.size(); i++) {
            anst[i] = 0 - anst[i];
        }
        anst.push_back(float(ls1[6][0] - '0'));
        anst.push_back(float(ls1[7][0] - '0'));
        anst.push_back(float(ls1[4][0] - '0'));
        anst.push_back(float(ls1[5][0] - '0'));

    }
    else {
        anst.push_back(float(ls1[4][0] - '0'));
        anst.push_back(float(ls1[5][0] - '0'));
        anst.push_back(float(ls1[6][0] - '0'));
        anst.push_back(float(ls1[7][0] - '0'));
    }

    torch::Tensor ans = torch::from_blob(anst.data(), {1, 28}, torch::kFloat);

    return ans;
}

// 神经网络的估值函数

Value Evaluation::value_with_nnue()
{
    Value value = VALUE_ZERO;

    std::vector<torch::jit::IValue> inputs;
    torch::Tensor input = analysisfen(pos.fen());
    
    inputs.push_back(input);
    mod.eval();
    at::Tensor output = mod.forward(inputs).toTensor();


    auto score = output.accessor<float,2>();
    value += int(score[0][0]);
    
    return value;                                                             
}
} // namespace


/// evaluate() is the evaluator for the outer world. It returns a static
/// evaluation of the position from the point of view of the side to move.

Value Eval::evaluate(Position &pos, torch::jit::script::Module &module1)
{
    if (pos.get_phase() == Phase::gameOver) {
        Value value = VALUE_ZERO;
        if (pos.piece_on_board_count(WHITE) + pos.piece_on_board_count(BLACK) >=
            SQUARE_NB) {
            if (rule.isWhiteLoseButNotDrawWhenBoardFull) {
                value -= VALUE_MATE;
            } else {
                value = VALUE_DRAW;
            }
        } else if (pos.get_action() == Action::select &&
                   pos.is_all_surrounded(pos.side_to_move()) &&
                   rule.isLoseButNotChangeSideWhenNoWay) {
            const Value delta = pos.side_to_move() == WHITE ? -VALUE_MATE :
                                                              VALUE_MATE;
            value += delta;
        } else if (pos.piece_on_board_count(WHITE) < rule.piecesAtLeastCount) {
            value -= VALUE_MATE;
        } else if (pos.piece_on_board_count(BLACK) < rule.piecesAtLeastCount) {
            value += VALUE_MATE;
        }

        if (pos.side_to_move() == BLACK) {
            value = -value;
        }

        return value;
    }

    return Evaluation(pos, module1).value_with_nnue();
}
