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
from torch.amp import autocast, GradScaler

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
        # Mixed precision configuration: enable only when CUDA is available
        # Default behavior: use AMP if 'use_amp' is True in args; otherwise, disable
        self.use_amp = bool(getattr(self.args, 'use_amp', False)) and bool(self.args.cuda)
        # Fail fast if user forces AMP without CUDA
        assert (not bool(getattr(self.args, 'use_amp', False))) or self.args.cuda, "AMP requires CUDA to be available"
        self.scaler: GradScaler = GradScaler('cuda', enabled=self.use_amp)

    def train(self, examples):
        """
        examples: list of examples, each example is of form (board, pi, v, period)
        """
        best_loss, best_epoch = torch.inf, -1

        # Curriculum / head-specific training configuration
        current_stage = int(getattr(self.args, 'curriculum_current_stage', 3))
        head_training_mode = str(getattr(self.args, 'head_training_mode', 'auto')).lower()
        # Map stage -> allowed period head indices
        # period: 0->branch[0], 1->branch[1], 2->branch[2], 3->branch[3], 4->branch[4]
        stage_to_allowed = {
            1: {0, 3},  # placing/capture heads
            2: {1, 4},  # moving heads
            3: {2},     # flying head
        }
        if head_training_mode == 'stage_heads' or (head_training_mode == 'auto' and current_stage in (1, 2)):
            allowed_head_indices = stage_to_allowed.get(current_stage, {0, 3})
        else:
            # all_heads or auto at stage 3 for joint fine-tuning
            allowed_head_indices = {0, 1, 2, 3, 4}

        freeze_backbone = bool(getattr(self.args, 'curriculum_freeze_backbone', False))
        head_lr_mult = float(getattr(self.args, 'curriculum_head_lr_mult', 1.0))
        filter_examples = bool(getattr(self.args, 'head_stage_filter_examples', False)) and allowed_head_indices != {0,1,2,3,4}

        # Stage-3 gradual unfreezing schedule (optional)
        stage3_gradual_unfreeze = bool(getattr(self.args, 'stage3_gradual_unfreeze', False)) and current_stage == 3
        unfreeze_order_cfg = getattr(self.args, 'stage3_unfreeze_order', ['mlp', 'attension', 'conv', 'main'])
        if isinstance(unfreeze_order_cfg, str):
            unfreeze_order = [x.strip() for x in unfreeze_order_cfg.split(',') if x.strip()]
        else:
            unfreeze_order = list(unfreeze_order_cfg)
        valid_names = {'mlp', 'attension', 'conv', 'main'}
        unfreeze_order = [x for x in unfreeze_order if x in valid_names]
        if not unfreeze_order:
            unfreeze_order = ['mlp', 'attension', 'conv', 'main']
        milestones_cfg = getattr(self.args, 'stage3_unfreeze_epochs', [2, 3, 4, 5])
        if isinstance(milestones_cfg, (list, tuple)):
            unfreeze_milestones = [int(x) for x in milestones_cfg]
        else:
            unfreeze_milestones = [2, 3, 4, 5]
        backbone_lr_mult = float(getattr(self.args, 'stage3_backbone_lr_mult', 1.0))

        # Module registry for selective unfreeze
        backbone_modules = {
            'main': self.nnet.main,
            'attension': self.nnet.attension,
            'mlp': self.nnet.mlp,
            'conv': self.nnet.conv,
        }
        head_modules = list(self.nnet.branch) if hasattr(self.nnet, 'branch') else []

        def _set_requires(module, flag: bool):
            for p in module.parameters():
                p.requires_grad = flag

        def _collect_params(modules):
            params = []
            for m in modules:
                params += list(m.parameters())
            return params
        final_train_loss = None

        for epoch in range(self.args.epochs):
            print('EPOCH ::: ' + str(epoch + 1))
            self.nnet.train()
            # Determine trainable modules for this epoch
            trainable_backbone_names = set()
            if stage3_gradual_unfreeze:
                # Heads always trainable; backbone released by milestones
                unfrozen_steps = sum(1 for m in unfreeze_milestones if (epoch + 1) >= m)
                trainable_backbone_names = set(unfreeze_order[:unfrozen_steps])
            else:
                if not freeze_backbone:
                    trainable_backbone_names = {'main', 'attension', 'mlp', 'conv'}
                else:
                    trainable_backbone_names = set()

            # Apply requires_grad
            for name, module in backbone_modules.items():
                _set_requires(module, name in trainable_backbone_names)
            for idx, m in enumerate(head_modules):
                _set_requires(m, idx in allowed_head_indices)

            # Rebuild optimizer with current trainable groups
            head_params = _collect_params([head_modules[i] for i in range(len(head_modules)) if i in allowed_head_indices])
            backbone_selected = [backbone_modules[n] for n in ['main','attension','mlp','conv'] if n in trainable_backbone_names]
            backbone_params = _collect_params(backbone_selected)
            if hasattr(self.nnet, 'attension_b') and 'attension' in trainable_backbone_names:
                backbone_params.append(self.nnet.attension_b)

            param_groups = []
            if backbone_params:
                param_groups.append({'params': [p for p in backbone_params if p.requires_grad], 'lr': float(self.args.lr) * float(backbone_lr_mult)})
            if head_params:
                param_groups.append({'params': [p for p in head_params if p.requires_grad], 'lr': float(self.args.lr) * float(head_lr_mult)})
            if not param_groups:
                param_groups = [{'params': self.nnet.parameters(), 'lr': self.args.lr}]
            optimizer = optim.Adam(param_groups)

            pi_losses = AverageMeter()
            v_losses = AverageMeter()

            # Optionally filter examples to only those matching allowed head periods
            if filter_examples:
                # Period->head index mapping is identity (0..4)
                examples = [ex for ex in examples if len(ex) >= 4 and int(ex[3]) in allowed_head_indices]
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

                # compute output under autocast (if enabled)
                with autocast(device_type='cuda', enabled=self.use_amp):
                    target_pis = target_pis + 1e-8
                    device = boards.device
                    # Use the same dtype as targets to avoid AMP dtype mismatch
                    out_pi = torch.zeros(target_pis.size(), device=device, dtype=target_pis.dtype)
                    out_v = torch.zeros(target_vs.size(), device=device, dtype=target_vs.dtype)
                    period_set = sorted(list(allowed_head_indices)) if filter_examples else list(range(5))
                    for i in period_set:
                        mask = (periods == i)
                        if mask.any():
                            pi, v = self.nnet(boards[mask], i)
                            out_pi[mask] = pi.view(-1, target_pis.size(1)).to(target_pis.dtype)
                            out_v[mask] = v.view(-1).to(target_vs.dtype)
                    l_pi = self.loss_pi(target_pis, out_pi)
                    l_v = self.loss_v(target_vs, out_v)
                    total_loss = l_pi + l_v

                # record loss
                pi_losses.update(l_pi.item(), boards.size(0))
                v_losses.update(l_v.item(), boards.size(0))
                t.set_postfix(Loss_pi=pi_losses, Loss_v=v_losses)

                # compute gradient and do SGD step
                optimizer.zero_grad(set_to_none=True)
                if self.use_amp:
                    # Scale, unscale for clipping, then step
                    self.scaler.scale(total_loss).backward()
                    self.scaler.unscale_(optimizer)
                    torch.nn.utils.clip_grad_norm_(
                        [p for p in self.nnet.parameters() if p.requires_grad], 5
                    )
                    self.scaler.step(optimizer)
                    self.scaler.update()
                else:
                    total_loss.backward()
                    torch.nn.utils.clip_grad_norm_(
                        [p for p in self.nnet.parameters() if p.requires_grad], 5
                    )
                    optimizer.step()

            # validation
            val_loss = self.valid(valid_examples)
            print(f'Epoch {epoch+1} Validation loss: {val_loss}')
            if val_loss < best_loss:
                best_loss = val_loss
                best_epoch = epoch
                self.save_checkpoint(folder=self.args.checkpoint, filename='best_epoch.pth.tar')
            # record last epoch training loss (sum of pi+v)
            try:
                final_train_loss = float(pi_losses.avg + v_losses.avg)
            except Exception:
                final_train_loss = None
        self.load_checkpoint(folder=self.args.checkpoint, filename='best_epoch.pth.tar')
        # return metrics for logging
        return {
            'train_loss': final_train_loss,
            'val_loss': float(best_loss) if best_loss is not None else None,
            'best_epoch': int(best_epoch),
        }

    def valid(self, val_examples):
        self.nnet.eval()
        # Respect head-stage filtering during validation as well (if enabled)
        current_stage = int(getattr(self.args, 'curriculum_current_stage', 3))
        head_training_mode = str(getattr(self.args, 'head_training_mode', 'auto')).lower()
        stage_to_allowed = {1: {0, 3}, 2: {1, 4}, 3: {2}}
        if head_training_mode == 'stage_heads' or (head_training_mode == 'auto' and current_stage in (1, 2)):
            allowed_head_indices = stage_to_allowed.get(current_stage, {0, 3})
        else:
            allowed_head_indices = {0, 1, 2, 3, 4}
        filter_examples = bool(getattr(self.args, 'head_stage_filter_examples', False)) and allowed_head_indices != {0,1,2,3,4}
        if filter_examples:
            val_examples = [ex for ex in val_examples if len(ex) >= 4 and int(ex[3]) in allowed_head_indices]
        val_dataset = GameDataset(val_examples)
        val_dataloader = torch.utils.data.DataLoader(val_dataset, batch_size=self.args.batch_size)
        total_loss = AverageMeter()

        for boards, target_pis, target_vs, periods in tqdm(val_dataloader, desc='Validation Net'):
            if self.args.cuda:
                boards = boards.contiguous().cuda()
                target_pis = target_pis.contiguous().cuda()
                target_vs = target_vs.contiguous().cuda()
                periods = periods.contiguous().cuda()
            with torch.no_grad():
                with autocast(device_type='cuda', enabled=self.use_amp):
                    target_pis = target_pis + 1e-8
                    device = boards.device
                    # Use the same dtype as targets to avoid AMP dtype mismatch
                    out_pi = torch.zeros(target_pis.size(), device=device, dtype=target_pis.dtype)
                    out_v = torch.zeros(target_vs.size(), device=device, dtype=target_vs.dtype)
                    period_set = sorted(list(allowed_head_indices)) if filter_examples else list(range(5))
                    for i in period_set:
                        mask = (periods == i)
                        if mask.any():
                            pi, v = self.nnet(boards[mask], i)
                            out_pi[mask] = pi.view(-1, target_pis.size(1)).to(target_pis.dtype)
                            out_v[mask] = v.view(-1).to(target_vs.dtype)
                    l_pi = self.loss_pi(target_pis, out_pi)
                    l_v = self.loss_v(target_vs, out_v)
                    loss = (l_pi + l_v).item()
            total_loss.update(loss, boards.size(0))
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
            with autocast(device_type='cuda', enabled=self.use_amp):
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


