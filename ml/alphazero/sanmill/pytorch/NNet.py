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

from .SanmillNNet import SanmillNNet as snnet

class NNetWrapper(NeuralNet):
    def __init__(self, game, args):
        self.args = args
        self.board_x, self.board_y = game.getBoardSize()
        self.nnet = snnet(game, args)
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
            split_idx = int(len(examples)*0.8)
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
                    # boards, target_pis, target_vs = boards.contiguous().cuda(), target_pis.contiguous().cuda(), target_vs.contiguous().cuda()
                    boards = boards.contiguous().cuda()
                    target_pis = target_pis.contiguous().cuda()
                    target_vs = target_vs.contiguous().cuda()
                    periods = periods.contiguous().cuda()

                # compute output
                target_pis += 1e-8
                out_pi = torch.zeros(target_pis.size()).cuda()
                out_v = torch.zeros(target_vs.size()).cuda()
                for i in range(5):
                    if (periods==i).any():
                        pi, v = self.nnet(boards[periods==i], i)
                        out_pi[periods==i] = pi.view(-1, target_pis.size(1))
                        out_v[periods==i] = v.view(-1)
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
        val_dataset = SanmillDataset(val_examples)
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
            out_pi = torch.zeros(target_pis.size()).to('cuda')
            out_v = torch.zeros(target_vs.size()).to('cuda')
            for i in range(5):
                if (periods==i).any():
                    pi, v = self.nnet(boards[periods==i], i)
                    out_pi[periods==i] = pi.view(-1, target_pis.size(1))
                    out_v[periods==i] = v.view(-1)
            l_pi = self.loss_pi(target_pis, out_pi)
            l_v = self.loss_v(target_vs, out_v)
            total_loss.update(l_pi.item() + l_v.item(), boards.size(0))
        return total_loss.avg

    def predict(self, canonicalBoard):
        """
        board: np array with board
        """
        # timing
        start = time.time()

        # preparing input
        if canonicalBoard.period == 2 and canonicalBoard.count(1) > 3:
            real_period = 4
        else:
            real_period = canonicalBoard.period
        board = torch.tensor(canonicalBoard.pieces, dtype=torch.float)
        real_period = torch.tensor(real_period, dtype=torch.int8)
        if self.args.cuda: board = board.contiguous().cuda()
        board = board.view(1, self.board_x, self.board_y)
        self.nnet.eval()
        with torch.no_grad():
            pi, v = self.nnet(board, real_period)
            if 'eat_factor' in self.args.keys() and real_period == 3:
                v = max(min(1, self.args.eat_factor*v), -1)
                v = torch.tensor([v], dtype=torch.float32)

        # print('PREDICTION TIME TAKEN : {0:03f}'.format(time.time()-start))
        return torch.exp(pi).data.cpu().numpy()[0], v.data.cpu().numpy()[0]

    def loss_pi(self, targets, outputs):
        return -torch.sum(targets * outputs) / targets.size()[0]
        # alpha = 0.25

        # positive = (targets>1e-3).float()

        # alpha_w = alpha * positive + (1-alpha) * positive
        # p_t = positive * torch.exp(outputs) + (1-positive) * (1-torch.exp(outputs))
        # focal_loss = -torch.sum(alpha_w * targets * (1-p_t)**2 * torch.log(p_t)) / targets.size()[0]
        # return focal_loss

    def loss_v(self, targets, outputs):
        return torch.sum((targets - outputs.view(-1)) ** 2) / targets.size()[0]

    def save_checkpoint(self, folder='checkpoint', filename='checkpoint.pth.tar'):
        filepath = os.path.join(folder, filename)
        if not os.path.exists(folder):
            print("Checkpoint Directory does not exist! Making directory {}".format(folder))
            os.mkdir(folder)
        else:
            print("Checkpoint Directory exists! ")
        torch.save({
            'state_dict': self.nnet.state_dict(),
        }, filepath)

    def load_checkpoint(self, folder='checkpoint', filename='checkpoint.pth.tar'):
        # https://github.com/pytorch/examples/blob/master/imagenet/main.py#L98
        filepath = os.path.join(folder, filename)
        if not os.path.exists(filepath):
            # raise ("No model in path {}".format(filepath))
            print("No model in path {}".format(filepath))
            exit(1)
        map_location = None if self.args.cuda else 'cpu'
        checkpoint = torch.load(filepath, map_location=map_location)
        self.nnet.load_state_dict(checkpoint['state_dict'])