import logging
from datetime import datetime
import os
import sys
import torch
import torch.multiprocessing as mp
import coloredlogs
import argparse

from Coach import Coach
from game.Game import Game as Game
from game.pytorch.NNet import NNetWrapper as nn
from utils import *
from config import merge_config_with_args

log = logging.getLogger(__name__)

# Defer final console logging level until after config load
coloredlogs.install(level='INFO')


def should_load_model(args):
    """
    Smart model loading logic:
    - If best.pth.tar doesn't exist: return False (start fresh)
    - If best.pth.tar exists: return args.load_model (respect config)
    """
    load_folder = args.load_folder_file[0] if isinstance(args.load_folder_file, (list, tuple)) else args.load_folder_file
    load_filename = args.load_folder_file[1] if isinstance(args.load_folder_file, (list, tuple)) else 'best.pth.tar'
    
    # Construct the full path to the model file
    model_path = os.path.join(load_folder, load_filename)
    
    # Check if the specific model file exists
    if not os.path.exists(model_path):
        log.info(f"📁 Model file '{model_path}' not found, starting fresh training")
        return False
    
    # Model file exists, respect the config setting
    if args.load_model:
        log.info(f"📁 Found existing checkpoint '{model_path}', will load as configured (load_model=true)")
        return True
    else:
        log.info(f"📁 Found existing checkpoint '{model_path}', but load_model=false, starting fresh")
        return False

args = dotdict({
    'numIters': 100,
    'numEps': 100,              # Number of complete self-play games to simulate during a new iteration.
    'tempThreshold': 80,        #
    'updateThreshold': 0.55,     # During arena playoff, new neural net will be accepted if threshold or more of games are won.
    'maxlenOfQueue': 200000,    # Number of game examples to train the neural networks.
    'numMCTSSims': 40,          # Number of games moves for MCTS to simulate.
    'arenaCompare': 20,         # Number of games to play during arena play to determine if new net will be accepted.
    'cpuct': 1.5,

    'checkpoint': './temp/',
    'load_model': False,
    'load_folder_file': ('temp/','best.pth.tar'),
    'numItersForTrainExamplesHistory': 5,
    'num_processes': 2,

    'lr': 0.002,
    'dropout': 0.3,
    'epochs': 10,
    'batch_size': 1024,
    'cuda': torch.cuda.is_available(),
    'num_channels': 256,
    # AMP default: enable when CUDA is available; will be reconciled after config/env overrides
    'use_amp': torch.cuda.is_available(),
    
    # Teacher (Perfect DB) mixing options
    'usePerfectTeacher': False,     # set True to mix oracle labels every iteration
    'teacherExamplesPerIter': 0,    # how many teacher examples per iteration
    'teacherBatch': 256,            # sampling batch for teacher dataset builder
    'teacherDBPath': os.environ.get('SANMILL_PERFECT_DB', None),  # or pass via env
    'teacherAnalyzeTimeout': int(os.environ.get('SANMILL_ANALYZE_TIMEOUT', '120')),  # seconds per analyze
    'teacherThreads': int(os.environ.get('SANMILL_ENGINE_THREADS', '1')),
    'pitAgainstPerfect': False,     # set True to pit new model against Perfect DB every iteration

    # Online teacher guidance during self-play
    'useOnlineTeacher': True,      # Default enable online teacher
    'teacherOnlineRatio': 0.3,     # Probability of using teacher per move (0.0-1.0)

    # Debugging and validation options
    'verbose_games': 1,  # Number of games per iteration to log detailed move history
    'log_detailed_moves': True,  # Whether to log move sequences for verification
    'enable_training_log': True,  # Whether to save training results to CSV/JSON files
    # File logging
    'log_to_file': True,          # Write detailed logs to a file with timestamps
    'log_file': None,             # If None, auto-generate under checkpoint dir
})


def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(
        description='AlphaZero Training for Nine Men\'s Morris',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate config templates
  python3 main.py --create-template
  
  # Train with config file (recommended)
  python3 main.py --config my_config.yaml
  
  # Train with default settings
  python3 main.py
  
  # Quick setup with paths
  python3 main.py --config config_examples/teacher_training.yaml \\
                  --engine /path/to/sanmill \\
                  --db /path/to/perfect/database
        """
    )
    parser.add_argument('--config', '-c', type=str, default=None,
                        help='Path to configuration file (YAML or JSON)')
    parser.add_argument('--create-template', action='store_true',
                        help='Create template configuration files and exit')
    parser.add_argument('--engine', type=str, default=None,
                        help='Path to Sanmill engine executable')
    parser.add_argument('--db', type=str, default=None,
                        help='Path to perfect database (auto-enables teacher)')
    parser.add_argument('--verbose', '-v', action='store_true', help='Enable detailed console output (DEBUG)')
    parser.add_argument('--sampling-only', action='store_true', help='Run only self-play sampling phase (CPU multi-process)')
    parser.add_argument('--training-only', action='store_true', help='Run only training phase (GPU single-process)')
    parser.add_argument('--single-phase', action='store_true', help='Use original single-phase mode (sampling + training in same process)')
    parser.add_argument('--auto-phases', action='store_true', help='Explicitly run auto phases (default behavior)')
    
    cmd_args = parser.parse_args()
    
    # Create template and exit if requested
    if cmd_args.create_template:
        print("📋 Creating configuration templates...")
        os.system('python3 create_configs.py')
        return
    
    # Load configuration
    if cmd_args.config:
        log.info(f"📋 Loading configuration from: {cmd_args.config}")
        # Use the global args as base configuration
        args = merge_config_with_args(globals()['args'], cmd_args.config)
    else:
        log.info("⚙️  Using default configuration")
        # Use the global args directly
        args = globals()['args']
    
    # Determine verbose mode (console) from CLI or config key 'console_verbose' (safe access)
    cli_verbose = bool(getattr(cmd_args, 'verbose', False))
    try:
        cfg_verbose = bool(getattr(args, 'console_verbose'))
    except Exception:
        cfg_verbose = False
    verbose_mode = cli_verbose or cfg_verbose
    
    # Adjust console logging level based on verbose mode
    if verbose_mode:
        coloredlogs.install(level='DEBUG')
        log.info("🔍 Verbose console: DEBUG level")
    else:
        coloredlogs.install(level='INFO')
        log.info("📋 Console: INFO level (concise)")
    
    # Apply command-line overrides
    if cmd_args.engine:
        os.environ['SANMILL_ENGINE'] = cmd_args.engine
        log.info(f"🔧 Engine: {cmd_args.engine}")
        
    if cmd_args.db:
        args.teacherDBPath = cmd_args.db
        args.usePerfectTeacher = True  # Auto-enable teacher
        log.info(f"🎓 Perfect DB: {cmd_args.db}")
        log.info("📚 Auto-enabled teacher mixing")
    
    # Setup file logging (timestamps) if enabled
    try:
        if getattr(args, 'log_to_file', True):
            # Ensure directories exist
            logs_dir = os.path.join(args.checkpoint, 'logs')
            stats_dir = os.path.join(args.checkpoint, 'stats')
            os.makedirs(logs_dir, exist_ok=True)
            os.makedirs(stats_dir, exist_ok=True)
            if getattr(args, 'log_file', None):
                log_path = args.log_file
                if not os.path.isabs(log_path):
                    log_path = os.path.join(logs_dir, os.path.basename(log_path))
            else:
                ts = datetime.now().strftime('%Y%m%d_%H%M%S')
                log_path = os.path.join(logs_dir, f"train_{ts}.log")
            
            # Setup comprehensive file logging
            file_handler = logging.FileHandler(log_path, mode='a', encoding='utf-8')
            file_handler.setLevel(logging.DEBUG)  # Capture ALL levels including DEBUG
            file_handler.setFormatter(logging.Formatter('%(asctime)s %(name)s[%(process)d] %(levelname)s %(message)s'))
            
            # Attach file handler to root and key loggers
            root_logger = logging.getLogger()
            root_logger.addHandler(file_handler)
            for logger_name in ['MCTS', 'Coach', '__main__', 'Arena', 'Game']:
                specific_logger = logging.getLogger(logger_name)
                specific_logger.addHandler(file_handler)
            
            log.info("Comprehensive file logging enabled: %s", log_path)
    except Exception as e:
        log.warning("Failed to setup file logging: %s", e)

    # Handle phase separation flags
    sampling_only = getattr(cmd_args, 'sampling_only', False)
    training_only = getattr(cmd_args, 'training_only', False)
    single_phase = getattr(cmd_args, 'single_phase', False)
    auto_phases = getattr(cmd_args, 'auto_phases', False)
    
    # Validate phase arguments
    phase_flags = [sampling_only, training_only, single_phase, auto_phases]
    assert sum(phase_flags) <= 1, "Only one of --sampling-only, --training-only, --single-phase, --auto-phases can be specified"
    
    # Default behavior: auto-phases if no phase flag is specified
    if sum(phase_flags) == 0:
        auto_phases = True
        log.info("🔄 DEFAULT: Using auto-phases mode (sampling then training)")
    
    # Configure phases
    if sampling_only:
        # Force CPU for sampling phase
        original_cuda = args.cuda
        args.cuda = False
        args.use_amp = False
        # Ensure multi-process for sampling efficiency
        if args.num_processes == 1:
            args.num_processes = 2  # Default to 2 processes for better efficiency
        log.info("🔍 SAMPLING PHASE: CPU multi-process mode")
    elif training_only:
        # Force single process + GPU for training phase
        args.num_processes = 1
        if not args.cuda:
            log.warning("Training phase typically benefits from CUDA. Consider setting cuda: true in config.")
        log.info("🎯 TRAINING PHASE: GPU single-process mode")
    elif single_phase:
        log.info("📋 SINGLE PHASE: Original mode (sampling + training in same process)")
    elif auto_phases:
        log.info("🔄 AUTO PHASES: Will run sampling (CPU) then training (GPU)")
    
    # Show key configuration
    log.info(f"🎯 Training config: {args.numIters} iters, {args.numEps} eps/iter, {args.num_processes} procs, CUDA: {args.cuda}")
    if args.usePerfectTeacher:
        log.info(f"📚 Teacher: {args.teacherExamplesPerIter} samples/iter from {args.teacherDBPath}")
    
    # Original args variable is now updated
    
    # Allow environment overrides so we can disable CUDA or reduce processes when needed.
    # SANMILL_TRAIN_CUDA: set to "0"/"false"/"no" to force CPU even if CUDA is available.
    # SANMILL_TRAIN_PROCESSES: set process count (>=1) to control multiprocessing.
    # SANMILL_TRAIN_ARENA_COMPARE: override arenaCompare if desired.
    env_cuda = os.environ.get("SANMILL_TRAIN_CUDA")
    if env_cuda is not None:
        args.cuda = env_cuda.strip().lower() not in ("0", "false", "no")

    env_procs = os.environ.get("SANMILL_TRAIN_PROCESSES")
    if env_procs:
        try:
            args.num_processes = max(1, int(env_procs))
        except Exception:
            pass
    # Note: Default process count is now 2 in args definition

    env_arena = os.environ.get("SANMILL_TRAIN_ARENA_COMPARE")
    if env_arena:
        try:
            args.arenaCompare = max(2, int(env_arena))
        except Exception:
            pass

    # Allow env overrides for teacher mixing
    env_use_teacher = os.environ.get('SANMILL_USE_TEACHER')
    if env_use_teacher is not None:
        args.usePerfectTeacher = env_use_teacher.strip().lower() in ("1", "true", "yes", "on")
    env_teacher_n = os.environ.get('SANMILL_TEACHER_PER_ITER')
    if env_teacher_n:
        try:
            args.teacherExamplesPerIter = max(0, int(env_teacher_n))
        except Exception:
            pass
    env_pit_perfect = os.environ.get('SANMILL_PIT_PERFECT')
    if env_pit_perfect is not None:
        args.pitAgainstPerfect = env_pit_perfect.strip().lower() in ("1", "true", "yes", "on")

    # If running on CPU, ensure CUDA context is not requested anywhere.
    if not args.cuda:
        # Hint PyTorch to avoid selecting any GPU even if present
        os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")
    
    # Set default thread counts for optimal CPU performance
    # These can be overridden by environment variables
    os.environ.setdefault("OMP_NUM_THREADS", "12")
    os.environ.setdefault("MKL_NUM_THREADS", "12")
    os.environ.setdefault("SANMILL_TRAIN_PROCESSES", "2")

    # Reconcile AMP setting with final CUDA flag.
    # If config doesn't specify 'use_amp', default to following CUDA.
    # If CUDA is disabled, force AMP off.
    try:
        has_use_amp = hasattr(args, 'use_amp')
    except Exception:
        has_use_amp = 'use_amp' in dict(args)
    if not has_use_amp or getattr(args, 'use_amp', None) is None:
        args.use_amp = bool(args.cuda)
    elif getattr(args, 'use_amp') and not args.cuda:
        log.info('Forcing use_amp=False because cuda=False')
        args.use_amp = False

    log.info("Runtime config: cuda=%s, num_processes=%d, arenaCompare=%d", args.cuda, args.num_processes, args.arenaCompare)

    log.info('Loading %s...', Game.__name__)
    g = Game()

    log.info('Loading %s...', nn.__name__)
    nnet = nn(g, args)

    # Smart model loading: auto-detect if checkpoint directory is empty
    effective_load_model = should_load_model(args)
    if effective_load_model:
        log.info('Loading checkpoint "%s/%s"...', args.load_folder_file[0], args.load_folder_file[1])
        nnet.load_checkpoint(args.load_folder_file[0], args.load_folder_file[1])
    else:
        if args.load_model and not effective_load_model:
            log.info('🔄 Model file not found, starting fresh training despite load_model=true')
        else:
            log.warning('Not loading a checkpoint!')

    if args.num_processes > 1:
        # Use a start method compatible with our device setup.
        # - For CUDA workflows, 'spawn' is recommended by PyTorch.
        # - For pure CPU on Linux, 'fork' avoids pickling overhead and tends to be faster.
        method = 'spawn'
        if not args.cuda and sys.platform.startswith('linux'):
            method = 'fork'
        try:
            mp.set_start_method(method, force=True)
        except RuntimeError:
            # Start method may already be set if main() is re-entered; ignore.
            pass

    log.info('Loading the Coach...')
    c = Coach(g, nnet, args)

    if effective_load_model:
        log.info("Loading 'trainExamples' from file...")
        c.loadTrainExamples()

    log.info('Starting the learning process 🎉')
    if args.usePerfectTeacher:
        log.info('Teacher mixing is enabled: %d examples/iter from %s', args.teacherExamplesPerIter, args.teacherDBPath)
    if args.pitAgainstPerfect:
        log.info('Perfect DB evaluation is enabled: will pit new models against Perfect DB each iteration')
    
    # Phase control execution
    if auto_phases:
        # Run sampling phase first (CPU)
        log.info('🔍 AUTO PHASES: Starting sampling phase (CPU multi-process)...')
        args_sampling = dotdict(dict(args))
        args_sampling.cuda = False
        args_sampling.use_amp = False
        args_sampling.num_processes = 2  # Default to 2 processes for better efficiency
        c_sampling = Coach(g, nn(g, args_sampling), args_sampling)
        if effective_load_model:
            c_sampling.loadTrainExamples()
        c_sampling.learn(sampling_only=True)
        
        # Run training phase (GPU)
        log.info('🎯 AUTO PHASES: Starting training phase (GPU single-process)...')
        args_training = dotdict(dict(args))
        args_training.num_processes = 1
        # args.cuda and args.use_amp keep original values from config
        c_training = Coach(g, nn(g, args_training), args_training)
        c_training.loadTrainExamples()  # Load samples from sampling phase
        c_training.learn(training_only=True)
    else:
        # Single phase execution (original behavior)
        if single_phase:
            c.learn()  # Original method signature without phase control
        else:
            # Individual phase execution
            c.learn(sampling_only=sampling_only, training_only=training_only)


if __name__ == "__main__":
    main()
