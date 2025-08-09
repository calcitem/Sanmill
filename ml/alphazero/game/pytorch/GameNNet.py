import torch
import torch.nn as nn

from game.GameLogic import Board


class Branch03(nn.Module):
    def __init__(self, args):
        super(Branch03, self).__init__()
        self.args = args
        self.main = nn.Sequential(
            nn.Linear(args.num_channels * 18, args.num_channels * 2),
            nn.LayerNorm(args.num_channels * 2),
            nn.ReLU(),
            nn.Dropout(args.dropout),
        )
        self.pi = nn.Sequential(
            nn.Linear(args.num_channels * 2, args.num_channels // 2),
            nn.LayerNorm(args.num_channels // 2),
            nn.ReLU(),
            nn.Dropout(args.dropout),
            nn.Linear(args.num_channels // 2, 24),
            nn.LayerNorm(24),
            nn.LogSoftmax(dim=1),
        )
        self.v = nn.Sequential(
            nn.Linear(args.num_channels * 2, args.num_channels // 2),
            nn.LayerNorm(args.num_channels // 2),
            nn.ReLU(),
            nn.Dropout(),
            nn.Linear(args.num_channels // 2, 1),
            nn.Tanh(),
        )

    def forward(self, s):
        s = self.main(s)
        # Create logits tensor on the same device as input to avoid implicit CUDA init
        pi = torch.full((s.size(0), 24 * 24), -10.0, device=s.device)
        pi[:, :24] = self.pi(s)
        v = self.v(s)
        return pi, v


class Branch14(nn.Module):
    def __init__(self, args):
        super(Branch14, self).__init__()
        # 4 means the period where the opponent has 3 pieces and you have at least 4 pieces.
        self.args = args
        self.b = Board()
        self.cache_valids()
        self.main = nn.Sequential(
            nn.Linear(args.num_channels * 18, args.num_channels * 2),
            nn.LayerNorm(args.num_channels * 2),
            nn.ReLU(),
            nn.Dropout(args.dropout),
        )
        self.pi = nn.Sequential(
            nn.Linear(args.num_channels * 2, args.num_channels),
            nn.LayerNorm(args.num_channels),
            nn.ReLU(),
            nn.Dropout(args.dropout),
            nn.Linear(args.num_channels, 80),
            nn.LayerNorm(80),
            nn.LogSoftmax(dim=1),
        )
        self.v = nn.Sequential(
            nn.Linear(args.num_channels * 2, args.num_channels // 2),
            nn.LayerNorm(args.num_channels // 2),
            nn.ReLU(),
            nn.Dropout(),
            nn.Linear(args.num_channels // 2, 1),
            nn.Tanh(),
        )

    def cache_valids(self):
        self.valids = []
        legalMoves = self.b.get_valids_in_period1()
        for move in legalMoves:
            action = self.b.get_action_from_move(move)
            self.valids.append(action)

    def forward(self, s):
        s = self.main(s)
        # Create logits tensor on the same device as input to avoid implicit CUDA init
        pi = torch.full((s.size(0), 24 * 24), -10.0, dtype=torch.float, device=s.device)
        pi[:, self.valids] = self.pi(s)
        v = self.v(s)
        return pi, v


class Branch2(nn.Module):
    def __init__(self, args):
        super(Branch2, self).__init__()
        self.main = nn.Sequential(
            nn.Linear(args.num_channels * 18, args.num_channels * 2),
            nn.LayerNorm(args.num_channels * 2),
            nn.ReLU(),
            nn.Dropout(args.dropout),
        )
        self.pi = nn.Sequential(
            nn.Linear(args.num_channels * 2, args.num_channels * 2),
            nn.LayerNorm(args.num_channels * 2),
            nn.ReLU(),
            nn.Dropout(args.dropout),
            nn.Linear(args.num_channels * 2, 24 * 24),
            nn.LayerNorm(24 * 24),
            nn.LogSoftmax(dim=1),
        )
        self.v = nn.Sequential(
            nn.Linear(args.num_channels * 2, args.num_channels // 2),
            nn.LayerNorm(args.num_channels // 2),
            nn.ReLU(),
            nn.Dropout(),
            nn.Linear(args.num_channels // 2, 1),
            nn.Tanh(),
        )

    def forward(self, s):
        s = self.main(s)
        pi = self.pi(s)
        v = self.v(s)
        return pi, v


class GameNNet(nn.Module):
    def __init__(self, game, args):
        super(GameNNet, self).__init__()
        # game params
        self.board_x, self.board_y = game.getBoardSize()
        self.args = args

        self.main = nn.Sequential(
            nn.Conv2d(1, args.num_channels, 3, stride=1, padding=1),
            nn.BatchNorm2d(args.num_channels),
            nn.ReLU(),
        )
        self.attension_b = nn.Parameter(torch.rand(self.board_x * self.board_y, args.num_channels))
        self.attension = nn.MultiheadAttention(args.num_channels, 4, batch_first=True)
        self.mlp = nn.Sequential(
            nn.Linear(self.args.num_channels, self.args.num_channels),
            nn.LayerNorm(self.args.num_channels)
        )
        self.conv = nn.Sequential(
            nn.Conv2d(args.num_channels, args.num_channels * 2, 3, stride=2),
            nn.BatchNorm2d(args.num_channels * 2),
            nn.ReLU(),
        )
        self.branch = nn.ModuleList([Branch03(args), Branch14(args), Branch2(args), Branch03(args), Branch14(args)])

    def forward(self, s, period):
        """
        s: batch_size x board_x x board_y
        period: int period id
        """
        s = s.view(-1, 1, self.board_x, self.board_y)
        s = self.main(s)
        s = s.view(-1, self.args.num_channels, self.board_x * self.board_y).permute(0, 2, 1)
        s = s + self.attension_b
        s, _ = self.attension(s, s, s)
        s = self.mlp(s) + s
        s = s.permute(0, 2, 1).view(-1, self.args.num_channels, self.board_x, self.board_y)
        s = self.conv(s)
        s = s.reshape(-1, self.args.num_channels * 18)
        pi, v = self.branch[period](s)
        return pi, v


