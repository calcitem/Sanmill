import argparse
import model as M
# import nnue_dataset  # Commented out - not needed for Nine Men's Morris
import pytorch_lightning as pl
import features
import os
import sys
import torch
from torch import set_num_threads as t_set_num_threads
from pytorch_lightning import loggers as pl_loggers
from pytorch_lightning.callbacks import TQDMProgressBar, Callback
from torch.utils.data import DataLoader, Dataset
import time
from datetime import timedelta

# Enable Tensor Cores optimization for better performance on CUDA devices
if torch.cuda.is_available():
    torch.set_float32_matmul_precision('high')
    print("✅ Tensor Cores optimization enabled (float32 matmul precision set to 'high')")

import warnings

warnings.filterwarnings("ignore", ".*does not have many workers.*")


class TimeLimitAfterCheckpoint(Callback):
    def __init__(self, max_time: str):
        parts = list(map(int, max_time.strip().split(":")))
        if len(parts) != 4:
            raise ValueError("max_time must be in format 'DD:HH:MM:SS'")
        days, hours, minutes, seconds = parts
        self.max_duration = timedelta(
            days=days, hours=hours, minutes=minutes, seconds=seconds
        ).total_seconds()
        self.start_time = None

    def on_fit_start(self, trainer, pl_module):
        self.start_time = time.time()

    def on_validation_end(self, trainer, pl_module):
        elapsed = time.time() - self.start_time
        if elapsed >= self.max_duration:
            trainer.should_stop = True
            print(
                f"[TimeLimit] Time limit reached ({elapsed:.1f}s), stopping after checkpoint."
            )


def make_data_loaders(
    train_filenames,
    val_filenames,
    feature_set,
    num_workers,
    batch_size,
    config=None,  # Simplified - skip config not used for Nine Men's Morris
    main_device="cpu",
    epoch_size=None,
    val_size=None,
    use_perfect_db_format=True,  # Support Perfect DB generated data
):
    # Use Nine Men's Morris data loader for training data
    from data_loader import create_mill_data_loader
    
    format_type = "Perfect Database" if use_perfect_db_format else "Legacy"
    print(f"Using Nine Men's Morris data loader with {format_type} format")
    try:
        # Create data loaders with drop_last=True for consistent batch sizes
        train_dataset = create_mill_data_loader(
            train_filenames,
            feature_set,
            batch_size=batch_size,
            shuffle=True,
            num_workers=0,  # Set to 0 for Nine Men's Morris
            use_perfect_db_format=use_perfect_db_format,
            dataset_type="training"
        )
        
        val_dataset = create_mill_data_loader(
            val_filenames,
            feature_set,
            batch_size=batch_size,
            shuffle=False,
            num_workers=0,
            use_perfect_db_format=use_perfect_db_format,
            dataset_type="validation"
        )
        
        # Recreate with drop_last=True to ensure consistent batch sizes
        from torch.utils.data import DataLoader
        from data_loader import collate_mill_batch
        
        train = DataLoader(
            train_dataset.dataset,
            batch_size=batch_size,
            shuffle=True,
            collate_fn=collate_mill_batch,
            num_workers=0,
            drop_last=True,  # Important for consistent batch sizes
            pin_memory=True
        )
        
        val = DataLoader(
            val_dataset.dataset,
            batch_size=batch_size,
            shuffle=False,
            collate_fn=collate_mill_batch,
            num_workers=0,
            drop_last=True,
            pin_memory=True
        )
        
        return train, val
    except Exception as e:
        print(f"❌ Error creating Nine Men's Morris data loaders: {e}")
        print("   Make sure your training data files are in the correct format:")
        print("   Line format: 'FEN evaluation best_move result'")
        raise


def str2bool(v):
    if isinstance(v, bool):
        return v
    if v.lower() in ("yes", "true", "t", "y", "1"):
        return True
    elif v.lower() in ("no", "false", "f", "n", "0"):
        return False
    else:
        raise argparse.ArgumentTypeError("Boolean value expected.")


def flatten_once(lst):
    return sum(lst, [])


def get_model_with_fixed_offset(model, batch_size, main_device):
    """Initialize model with fixed batch size offset."""
    model.layer_stacks.idx_offset = torch.arange(
        0,
        batch_size * model.layer_stacks.count,
        model.layer_stacks.count,
        device=main_device,
    )
    print(f"✅ Initialized model idx_offset for batch size {batch_size}")
    return model

class FixedBatchNNUE(M.NNUE):
    """NNUE model that handles fixed batch sizes for Nine Men's Morris."""
    
    def __init__(self, feature_set, batch_size=8, **kwargs):
        super().__init__(feature_set, **kwargs)
        self.fixed_batch_size = batch_size
        
    def setup(self, stage=None):
        """Initialize idx_offset when model is set up."""
        if hasattr(self, 'layer_stacks') and self.layer_stacks.idx_offset is None:
            device = next(self.parameters()).device
            self.layer_stacks.idx_offset = torch.arange(
                0,
                self.fixed_batch_size * self.layer_stacks.count,
                self.layer_stacks.count,
                device=device
            )
            print(f"✅ Model setup: initialized idx_offset for batch size {self.fixed_batch_size}")
        
    def on_train_start(self):
        """Ensure idx_offset is initialized when training starts."""
        if hasattr(self, 'layer_stacks') and self.layer_stacks.idx_offset is None:
            self.setup()
            
    def on_validation_start(self):
        """Ensure idx_offset is initialized when validation starts.""" 
        if hasattr(self, 'layer_stacks') and self.layer_stacks.idx_offset is None:
            self.setup()


def main():
    parser = argparse.ArgumentParser(description="Trains Nine Men's Morris NNUE networks.")
    parser.add_argument(
        "datasets",
        action="append",
        nargs="+",
        help="Training datasets (Nine Men's Morris training data files). Interleaved at chunk level if multiple specified. Same data is used for training and validation if not validation data is specified.",
    )
    parser.add_argument(
        "--default_root_dir",
        type=str,
        default=None,
        dest="default_root_dir",
        help="Default root directory for logs and checkpoints. Default: None (use current directory).",
    )
    parser.add_argument(
        "--gpus",
        type=str,
        default=None,
        dest="gpus",
        help="List of gpus to use, e.g. 0,1,2,3 for 4 gpus. Default: None (use all available gpus).",
    )
    parser.add_argument(
        "--max_epochs",
        default=800,
        type=int,
        dest="max_epochs",
        help="Maximum number of epochs to train for. Default 800.",
    )
    parser.add_argument(
        "--max_time",
        default="30:00:00:00",
        type=str,
        dest="max_time",
        help="The maximum time to train for. A string in the format DD:HH:MM:SS (Default 30:00:00:00).",
    )
    parser.add_argument(
        "--validation-data",
        type=str,
        action="append",
        nargs="+",
        dest="validation_datasets",
        help="Validation data to use for validation instead of the training data (Nine Men's Morris training data files).",
    )
    parser.add_argument(
        "--lambda",
        default=1.0,
        type=float,
        dest="lambda_",
        help="lambda=1.0 = train on evaluations, lambda=0.0 = train on game results, interpolates between (default=1.0).",
    )
    parser.add_argument(
        "--start-lambda",
        default=None,
        type=float,
        dest="start_lambda",
        help="lambda to use at first epoch.",
    )
    parser.add_argument(
        "--end-lambda",
        default=None,
        type=float,
        dest="end_lambda",
        help="lambda to use at last epoch.",
    )
    parser.add_argument(
        "--qp-asymmetry",
        default=0.0,
        type=float,
        dest="qp_asymmetry",
        help="Adjust to loss for those if q (prediction) > p (reference) (default=0.0)",
    )
    parser.add_argument(
        "--pow-exp",
        default=2.5,
        type=float,
        dest="pow_exp",
        help="exponent of the power law used for the mean error (default=2.5)",
    )
    parser.add_argument(
        "--in-offset",
        default=0,
        type=float,
        dest="in_offset",
        help="offset for conversion to win on input (default=0 to match ±500-scale labels)",
    )
    parser.add_argument(
        "--out-offset",
        default=0,
        type=float,
        dest="out_offset",
        help="offset for conversion to win on input (default=0 to match ±500-scale labels)",
    )
    parser.add_argument(
        "--in-scaling",
        default=300,
        type=float,
        dest="in_scaling",
        help="scaling for conversion to win on input (default=300 for ±500-scale labels)",
    )
    parser.add_argument(
        "--out-scaling",
        default=300,
        type=float,
        dest="out_scaling",
        help="scaling for conversion to win on input (default=300 for ±500-scale labels)",
    )
    parser.add_argument(
        "--gamma",
        default=0.992,
        type=float,
        dest="gamma",
        help="Multiplicative factor applied to the learning rate after every epoch.",
    )
    parser.add_argument(
        "--lr", default=8.75e-4, type=float, dest="lr", help="Initial learning rate."
    )
    parser.add_argument(
        "--num-workers",
        default=0,
        type=int,
        dest="num_workers",
        help="Number of worker threads to use for data loading. Set to 0 for Nine Men's Morris (multi-threading not currently supported).",
    )
    parser.add_argument(
        "--batch-size",
        default=-1,
        type=int,
        dest="batch_size",
        help="Number of positions per batch / per iteration. Default on GPU = 8192 on CPU = 512 (adjusted for Nine Men's Morris).",
    )
    parser.add_argument(
        "--threads",
        default=-1,
        type=int,
        dest="threads",
        help="Number of torch threads to use. Default automatic (cores) .",
    )
    parser.add_argument(
        "--compile-backend",
        default="inductor",
        choices=["inductor", "cudagraphs"],
        type=str,
        dest="compile_backend",
        help="Which backend to use for torch.compile. inductor works well with larger nets, cudagraphs with smaller nets",
    )
    parser.add_argument(
        "--seed", default=42, type=int, dest="seed", help="torch seed to use."
    )
    parser.add_argument(
        "--smart-fen-skipping",
        action="store_true",
        dest="smart_fen_skipping_deprecated",
        help="If enabled positions that are bad training targets will be skipped during loading. Default: True, kept for backwards compatibility. This option is ignored",
    )
    parser.add_argument(
        "--no-smart-fen-skipping",
        action="store_true",
        dest="no_smart_fen_skipping",
        help="If used then no smart fen skipping will be done. By default smart fen skipping is done.",
    )
    parser.add_argument(
        "--no-wld-fen-skipping",
        action="store_true",
        dest="no_wld_fen_skipping",
        help="If used then no wld fen skipping will be done. By default wld fen skipping is done.",
    )
    parser.add_argument(
        "--random-fen-skipping",
        default=3,
        type=int,
        dest="random_fen_skipping",
        help="skip fens randomly on average random_fen_skipping before using one.",
    )
    parser.add_argument(
        "--resume-from-model",
        dest="resume_from_model",
        help="Initializes training using the weights from the given .pt model",
    )
    parser.add_argument(
        "--resume-from-checkpoint",
        dest="resume_from_checkpoint",
        help="Initializes training using a given .ckpt model",
    )
    parser.add_argument(
        "--network-save-period",
        type=int,
        default=20,
        dest="network_save_period",
        help="Number of epochs between network snapshots. None to disable.",
    )
    parser.add_argument(
        "--save-last-network",
        type=str2bool,
        default=True,
        dest="save_last_network",
        help="Whether to always save the last produced network.",
    )
    parser.add_argument(
        "--epoch-size",
        type=int,
        default=100000000,
        dest="epoch_size",
        help="Number of positions per epoch.",
    )
    parser.add_argument(
        "--validation-size",
        type=int,
        default=1000000,
        dest="validation_size",
        help="Number of positions per validation step.",
    )
    parser.add_argument(
        "--param-index",
        type=int,
        default=0,
        dest="param_index",
        help="Indexing for parameter scans.",
    )
    parser.add_argument(
        "--early-fen-skipping",
        type=int,
        default=-1,
        dest="early_fen_skipping",
        help="Skip n plies from the start.",
    )
    parser.add_argument(
        "--simple-eval-skipping",
        type=int,
        default=-1,
        dest="simple_eval_skipping",
        help="Skip positions that have abs(simple_eval(pos)) < n",
    )
    features.add_argparse_args(parser)
    args = parser.parse_args()

    args.datasets = flatten_once(args.datasets)
    if args.validation_datasets:
        args.validation_datasets = flatten_once(args.validation_datasets)
    else:
        args.validation_datasets = []

    for dataset in args.datasets:
        if not os.path.exists(dataset):
            raise Exception("{0} does not exist".format(dataset))

    for val_dataset in args.validation_datasets:
        if not os.path.exists(val_dataset):
            raise Exception("{0} does not exist".format(val_dataset))

    train_datasets = args.datasets
    val_datasets = train_datasets
    if len(args.validation_datasets) > 0:
        val_datasets = args.validation_datasets

    if (args.start_lambda is not None) != (args.end_lambda is not None):
        raise Exception(
            "Either both or none of start_lambda and end_lambda must be specified."
        )

    batch_size = args.batch_size
    if batch_size <= 0:
        # Adjust default batch size for Nine Men's Morris (smaller than chess)
        batch_size = 8192 if torch.cuda.is_available() else 512
    print("Using batch size {}".format(batch_size))

    feature_set = features.get_feature_set_from_name(args.features)

    loss_params = M.LossParams(
        in_offset=args.in_offset,
        in_scaling=args.in_scaling,
        out_offset=args.out_offset,
        out_scaling=args.out_scaling,
        start_lambda=args.start_lambda or args.lambda_,
        end_lambda=args.end_lambda or args.lambda_,
        pow_exp=args.pow_exp,
        qp_asymmetry=args.qp_asymmetry,
    )
    print("Loss parameters:")
    print(loss_params)

    max_epoch = args.max_epochs or 800
    if args.resume_from_model is None:
        nnue = FixedBatchNNUE(
            feature_set=feature_set,
            batch_size=batch_size,
            loss_params=loss_params,
            max_epoch=max_epoch,
            num_batches_per_epoch=args.epoch_size / batch_size,
            gamma=args.gamma,
            lr=args.lr,
            param_index=args.param_index,
        )
    else:
        nnue = torch.load(args.resume_from_model, weights_only=False)
        nnue.set_feature_set(feature_set)
        nnue.fixed_batch_size = batch_size  # Set batch size for loaded model
        nnue.loss_params = loss_params
        nnue.max_epoch = max_epoch
        nnue.num_batches_per_epoch = args.epoch_size / batch_size
        # we can set the following here just like that because when resuming
        # from .pt the optimizer is only created after the training is started
        nnue.gamma = args.gamma
        nnue.lr = args.lr
        nnue.param_index = args.param_index

    print("Feature set: {}".format(feature_set.name))
    print("Num real features: {}".format(feature_set.num_real_features))
    print("Num virtual features: {}".format(feature_set.num_virtual_features))
    print("Num features: {}".format(feature_set.num_features))

    print("Training with: {}".format(train_datasets))
    print("Validating with: {}".format(val_datasets))

    pl.seed_everything(args.seed)
    print("Seed {}".format(args.seed))

    print("Smart fen skipping: {}".format(not args.no_smart_fen_skipping))
    print("WLD fen skipping: {}".format(not args.no_wld_fen_skipping))
    print("Random fen skipping: {}".format(args.random_fen_skipping))
    print("Skip early plies: {}".format(args.early_fen_skipping))
    print("Skip simple eval : {}".format(args.simple_eval_skipping))
    print("Param index: {}".format(args.param_index))

    if args.threads > 0:
        print("limiting torch to {} threads.".format(args.threads))
        t_set_num_threads(args.threads)

    logdir = args.default_root_dir if args.default_root_dir else "logs/"
    print("Using log dir {}".format(logdir), flush=True)

    # Try to use TensorBoard logger, fallback to None if not available
    try:
        # Test tensorboard import first
        from torch.utils.tensorboard import SummaryWriter
        tb_logger = pl_loggers.TensorBoardLogger(logdir)
        print("✅ TensorBoard logger initialized")
    except (ImportError, ModuleNotFoundError) as e:
        tb_logger = None
        print(f"⚠️  TensorBoard not available, training without logging: {e}")
        
    checkpoint_callback = pl.callbacks.ModelCheckpoint(
        save_last=args.save_last_network,
        every_n_epochs=args.network_save_period,
        save_top_k=-1,
    )

    trainer = pl.Trainer(
        default_root_dir=logdir,
        max_epochs=args.max_epochs,
        devices=[int(x) for x in args.gpus.rstrip(",").split(",") if x]
        if args.gpus
        else "auto",
        logger=tb_logger if tb_logger else False,  # Disable logging if TensorBoard not available
        callbacks=[
            checkpoint_callback,
            TQDMProgressBar(refresh_rate=300),
            TimeLimitAfterCheckpoint(args.max_time),
        ],
        enable_progress_bar=True,
        enable_checkpointing=True,
        benchmark=True,
    )

    main_device = (
        trainer.strategy.root_device
        if trainer.strategy.root_device.index is None
        else "cuda:" + str(trainer.strategy.root_device.index)
    )

    nnue = get_model_with_fixed_offset(nnue, batch_size, main_device)
    
    # Disable torch.compile for Nine Men's Morris (Triton dependency issues)
    # nnue = torch.compile(nnue, backend=args.compile_backend)
    print("⚠️  torch.compile disabled (Triton not available)")
    
    nnue.to(device=main_device)

    # Create Nine Men's Morris data loaders
    train, val = make_data_loaders(
        train_datasets,
        val_datasets,
        feature_set,
        args.num_workers,
        batch_size,
        config=None,  # Skip config not used for Nine Men's Morris
        main_device=main_device,
        epoch_size=args.epoch_size,
        val_size=args.validation_size,
    )

    if args.resume_from_checkpoint:
        trainer.fit(nnue, train, val, ckpt_path=args.resume_from_checkpoint)
    else:
        trainer.fit(nnue, train, val)

    with open(os.path.join(logdir, "training_finished"), "w"):
        pass


if __name__ == "__main__":
    main()
    if sys.platform == "win32":
        os.system(f'wmic process where processid="{os.getpid()}" call terminate >nul')
