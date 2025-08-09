import os
import sys
import time
import random
import numpy as np
from tqdm import tqdm

sys.path.append('../../')
from utils import *
from NeuralNet import NeuralNet

import torch
import torch.optim as optim
import torch.nn as nn

from .GameNNet import GameNNet as snnet


class NNetWrapper(NeuralNet):
    def __init__(self, game, args):
        self.args = args
        self.board_x, self.board_y = game.getBoardSize()
        # Allow delayed init with optional period1 valids loaded from checkpoint
        self._period1_valids = None
        self.game = game
        self.nnet = snnet(game, args, period1_valids=self._period1_valids)
        if args.cuda:
            self.nnet.cuda()

    def train(self, examples):
        """
        examples: list of examples, each example is of form (board, pi, v, period)
        """
        best_loss, best_epoch = torch.inf, -1
        optimizer = optim.Adam(self.nnet.parameters(), lr=self.args.lr)

        for epoch in range(self.args.epochs):
            print('EPOCH ::: ' + str(epoch + 1))
            self.nnet.train()
            pi_losses = AverageMeter()
            v_losses = AverageMeter()

            random.shuffle(examples)
            split_idx = int(len(examples) * 0.8)
            train_examples = examples[:split_idx]
            valid_examples = examples[split_idx:]
            batch_count = int(len(train_examples) / self.args.batch_size)

            t = tqdm(range(batch_count), desc='Training Net')
            for _ in t:
                sample_ids = np.random.choice(len(train_examples), size=self.args.batch_size, replace=False)
                boards, pis, vs, periods = list(zip(*[train_examples[i] for i in sample_ids]))
                boards = torch.tensor(boards, dtype=torch.float32)
                target_pis = torch.tensor(pis, dtype=torch.float32)
                target_vs = torch.tensor(vs, dtype=torch.float32)
                periods = torch.tensor(periods, dtype=torch.int)

                if self.args.cuda:
                    boards = boards.contiguous().cuda()
                    target_pis = target_pis.contiguous().cuda()
                    target_vs = target_vs.contiguous().cuda()
                    periods = periods.contiguous().cuda()

                # compute output
                target_pis += 1e-8
                device = boards.device
                out_pi = torch.zeros(target_pis.size(), device=device)
                out_v = torch.zeros(target_vs.size(), device=device)
                for i in range(5):
                    if (periods == i).any():
                        pi, v = self.nnet(boards[periods == i], i)
                        out_pi[periods == i] = pi.view(-1, target_pis.size(1))
                        out_v[periods == i] = v.view(-1)
                l_pi = self.loss_pi(target_pis, out_pi)
                l_v = self.loss_v(target_vs, out_v)
                total_loss = l_pi + l_v

                # record loss
                pi_losses.update(l_pi.item(), boards.size(0))
                v_losses.update(l_v.item(), boards.size(0))
                t.set_postfix(Loss_pi=pi_losses, Loss_v=v_losses)

                # compute gradient and do SGD step
                optimizer.zero_grad()
                total_loss.backward()
                torch.nn.utils.clip_grad_norm_(self.nnet.parameters(), 5)
                optimizer.step()

            # validation
            val_loss = self.valid(valid_examples)
            print(f'Epoch {epoch+1} Validation loss: {val_loss}')
            if val_loss < best_loss:
                best_loss = val_loss
                best_epoch = epoch
                self.save_checkpoint(folder=self.args.checkpoint, filename='best_epoch.pth.tar')
        self.load_checkpoint(folder=self.args.checkpoint, filename='best_epoch.pth.tar')

    def valid(self, val_examples):
        self.nnet.eval()
        val_dataset = GameDataset(val_examples)
        val_dataloader = torch.utils.data.DataLoader(val_dataset, batch_size=self.args.batch_size)
        total_loss = AverageMeter()

        for boards, target_pis, target_vs, periods in tqdm(val_dataloader, desc='Validation Net'):
            # compute output
            target_pis += 1e-8
            if self.args.cuda:
                boards = boards.contiguous().cuda()
                target_pis = target_pis.contiguous().cuda()
                target_vs = target_vs.contiguous().cuda()
                periods = periods.contiguous().cuda()
            device = boards.device
            out_pi = torch.zeros(target_pis.size(), device=device)
            out_v = torch.zeros(target_vs.size(), device=device)
            for i in range(5):
                if (periods == i).any():
                    pi, v = self.nnet(boards[periods == i], i)
                    out_pi[periods == i] = pi.view(-1, target_pis.size(1))
                    out_v[periods == i] = v.view(-1)
            l_pi = self.loss_pi(target_pis, out_pi)
            l_v = self.loss_v(target_vs, out_v)
            total_loss.update(l_pi.item() + l_v.item(), boards.size(0))
        return total_loss.avg

    def predict(self, canonicalBoard):
        """
        board: Board with attributes (pieces, period, count)
        Returns (pi, v)
        """
        start = time.time()

        if canonicalBoard.period == 2 and canonicalBoard.count(1) > 3:
            real_period = 4
        else:
            real_period = canonicalBoard.period
        board = torch.tensor(canonicalBoard.pieces, dtype=torch.float)
        real_period = torch.tensor(real_period, dtype=torch.int8)
        if self.args.cuda:
            board = board.contiguous().cuda()
        board = board.view(1, self.board_x, self.board_y)
        self.nnet.eval()
        with torch.no_grad():
            pi, v = self.nnet(board, real_period)
            if 'eat_factor' in self.args.keys() and real_period == 3:
                v = max(min(1, self.args.eat_factor * v), -1)
                v = torch.tensor([v], dtype=torch.float32)

        return torch.exp(pi).data.cpu().numpy()[0], v.data.cpu().numpy()[0]

    def loss_pi(self, targets, outputs):
        return -torch.sum(targets * outputs) / targets.size()[0]

    def loss_v(self, targets, outputs):
        return torch.sum((targets - outputs.view(-1)) ** 2) / targets.size()[0]

    def save_checkpoint(self, folder='checkpoint', filename='checkpoint.pth.tar'):
        filepath = os.path.join(folder, filename)
        if not os.path.exists(folder):
            print("Checkpoint Directory does not exist! Making directory {}".format(folder))
            os.mkdir(folder)
        else:
            print("Checkpoint Directory exists! ")
        # Extract period-1 valid action mapping from model if available
        period1_valids = None
        try:
            # Branch index 1 and 4 correspond to period-1/4 heads
            if hasattr(self.nnet, 'branch') and len(self.nnet.branch) > 1:
                if hasattr(self.nnet.branch[1], 'valids'):
                    period1_valids = list(map(int, self.nnet.branch[1].valids))
        except Exception:
            pass

        # Serialize args as a plain dict for portability
        try:
            args_dict = dict(self.args)
        except Exception:
            # Fallback: manually pick commonly used keys
            args_dict = {
                'lr': getattr(self.args, 'lr', None),
                'dropout': getattr(self.args, 'dropout', None),
                'epochs': getattr(self.args, 'epochs', None),
                'batch_size': getattr(self.args, 'batch_size', None),
                'cuda': getattr(self.args, 'cuda', None),
                'num_channels': getattr(self.args, 'num_channels', None),
            }

        payload = {
            'state_dict': self.nnet.state_dict(),
            'args': args_dict,
            'period1_valids': period1_valids,
        }
        torch.save(payload, filepath)

        # Also write a sidecar JSON for easy inspection/migration
        try:
            import json
            with open(filepath + '.config.json', 'w', encoding='utf-8') as f:
                json.dump({'args': args_dict, 'period1_valids': period1_valids}, f)
        except Exception:
            pass

    def load_checkpoint(self, folder='checkpoint', filename='checkpoint.pth.tar'):
        filepath = os.path.join(folder, filename)
        if not os.path.exists(filepath):
            print("No model in path {}".format(filepath))
            exit(1)
        map_location = None if self.args.cuda else 'cpu'
        checkpoint = torch.load(filepath, map_location=map_location)

        # If checkpoint contains model/training config, apply it before building the net
        ckpt_args = checkpoint.get('args') if isinstance(checkpoint, dict) else None
        period1_valids = checkpoint.get('period1_valids') if isinstance(checkpoint, dict) else None

        # If not embedded, try sidecar JSON
        if ckpt_args is None or period1_valids is None:
            try:
                import json
                with open(filepath + '.config.json', 'r', encoding='utf-8') as f:
                    cfg = json.load(f)
                    ckpt_args = ckpt_args or cfg.get('args')
                    period1_valids = period1_valids or cfg.get('period1_valids')
            except Exception:
                pass

        reinit = False
        if ckpt_args:
            # Overwrite critical structural args if present
            for key in ['num_channels', 'dropout']:
                if key in ckpt_args and getattr(self.args, key, None) != ckpt_args[key]:
                    setattr(self.args, key, ckpt_args[key])
                    reinit = True
        if period1_valids is not None:
            self._period1_valids = period1_valids
            reinit = True

        if reinit:
            # Recreate network with aligned structure/mappings
            self.nnet = snnet(self.game, self.args, period1_valids=self._period1_valids)
            if self.args.cuda:
                self.nnet.cuda()

        # Allow non-strict load to survive architectural diffs
        incompatible = self.nnet.load_state_dict(checkpoint['state_dict'], strict=False)
        missing = list(incompatible.missing_keys) if hasattr(incompatible, 'missing_keys') else []
        unexpected = list(incompatible.unexpected_keys) if hasattr(incompatible, 'unexpected_keys') else []
        if missing or unexpected:
            print("[Warning] Loaded checkpoint with non-strict matching.")
            if missing:
                print(" - Missing keys:", missing)
            if unexpected:
                print(" - Unexpected keys:", unexpected)


