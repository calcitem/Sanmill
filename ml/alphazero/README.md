## AlphaZero for Mill (Sanmill variant)
An AlphaZero training and evaluation project for the Mill (Sanmill) game, based on [alpha-zero-general](https://github.com/suragnair/alpha-zero-general). It includes multi-process self-play and a human-vs-AI mode with EMA-based dynamic difficulty.

### Rules (the variant used in this project)
- 4 diagonal lines are available for movement
- Draw after 100 plies
- When either side has only 3 pieces, it can "fly" to any vacant spot
- After forming a mill, capture an opponent piece; then continue

### Key improvements
- Multi-process speedup for self-play and pitting
- orjson for fast (de)serialization of training samples
- Reworked reward emphasizing plies and material difference
- Ignore invalid actions in loss (normalize over valid ones only)
- Validation after each epoch, auto-pick best epoch checkpoint
- ViT-like attention backbone with period-specific heads
- MCTS details adapted for rules and period changes
- EMA-based dynamic difficulty for human play

## Quick start (Windows / Linux / macOS)
### 1) Environment
- Python 3.8+ (3.10/3.11 recommended)
- Optional: CUDA and the matching PyTorch build

### 2) Clone
```bash
git clone https://github.com/yourname/AlphaZero-Sanmill.git
cd AlphaZero-Sanmill/ml/alphazero
```

### 3) Create venv and install deps
- Option A: CPU-only PyTorch
```bash
python -m venv .venv
.\.venv\Scripts\activate  # Windows PowerShell
# source .venv/bin/activate # Linux/macOS
pip install --upgrade pip
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
pip install numpy tqdm coloredlogs orjson
```
- Option B: Install GPU PyTorch per official guide, then:
```bash
pip install numpy tqdm coloredlogs orjson
```

### 4) First training run
```bash
python main.py
```
The first run will:
- Create game and NN instances (auto-detect CUDA)
- Run multi-process self-play to collect samples
- Train a new model and pit against the previous one
- If win-rate ≥ `updateThreshold`, save `./temp/best.pth.tar`
- Validate per epoch and save `best_epoch.pth.tar` (auto-loaded)

## Directory overview
- `main.py`: training entry; global `args`
- `Coach.py`: self-play, sample I/O, training, and pitting
- `MCTS.py`: Monte Carlo Tree Search (period-aware)
- `Arena.py`: match orchestration, multi-process, EMA difficulty
- `pit.py`: human-vs-AI / AI-vs-AI
- `game/`: game logic and networks (renamed from `sanmill/`)
  - `GameLogic.py`: board `Board`, rules, legal move generation, period switching
  - `Game.py`: AlphaZero game API (state, actions, symmetries, rewards)
  - `pytorch/GameNNet.py`: network (ViT-like backbone + period heads)
  - `pytorch/NNet.py`: training/validation/inference wrapper
- `utils.py`: helpers (`AverageMeter`, `EMA`, `dotdict`, `GameDataset`)
  - `engine_bridge.py`: bridge to native Sanmill engine (UCI-like) [训练中教师已不再使用]
  - `perfect_db_reader.py`: 直连 Perfect DB DLL 的轻量封装
 - `game/standard_rules.py`: standard Nine Men's Morris coordinates/adjacency/mills
 - `game/engine_adapter.py`: convert between Python move arrays and engine tokens

## Training details
### Train
```bash
python main.py
```

### Key args (see `main.py`)
- `numIters`: total iterations
- `numEps`: self-play games per iteration; must be multiple of `num_processes`
- `tempThreshold`: switch from sampling to greedy after this many plies
- `updateThreshold`: accept new model if win-rate above this
- `maxlenOfQueue`: max training examples kept per iteration
- `numMCTSSims`: MCTS simulations per move
- `arenaCompare`: pitting games; must be multiple of `2*num_processes`
- `cpuct`: exploration vs exploitation balance
- `checkpoint`: directory for models and samples (default `./temp/`)
- `load_model`: whether to resume from `load_folder_file`
- `load_folder_file`: e.g., `('temp', 'best.pth.tar')`
- `numItersForTrainExamplesHistory`: how many past iterations to keep
- `num_processes`: process count (Windows auto-sets `spawn`)
- `lr`, `dropout`, `epochs`, `batch_size`, `cuda`, `num_channels`: model/training hyperparams

### Outputs
- `./temp/best.pth.tar`: best model via pitting
- `./temp/best_epoch.pth.tar`: best epoch in a single training run
- `./temp/checkpoint_x.pth.tar.examples`: self-play samples (orjson), for resume

### Resume training
Edit `main.py`:
```python
args.load_model = True
args.load_folder_file = ('temp','best.pth.tar')
```
Then run to load model and `checkpoint_x.pth.tar.examples`.

### Multiprocessing & performance tips
- Windows uses `spawn` when `num_processes > 1`
- Ensure `numEps % num_processes == 0` and `arenaCompare % (2*num_processes) == 0`
- Increase `numMCTSSims` to get stronger play; reduce `lr` if unstable
- For more logs, change `coloredlogs.install(level='INFO')` to `DEBUG` in `main.py`

## Play & test
### Human vs AI (requires a model)
```bash
python pit.py
```
Defaults:
- `human_vs_cpu = True`
- Load `./temp/best.pth.tar`
- AI args `args1 = {numMCTSSims: 500, cpuct: 0.5, eat_factor: 2}`

Moves format:
- Placing/Capture periods (`period in [0,3]`): `x y`
- Moving/Flying periods (`period in [1,2]`): `x0 y0 x1 y1`
The script prints legal moves as hints; coordinates are 0..6 (top-left is 0,0).

Difficulty (dynamic): set `args.difficulty ∈ [-1, 1]` in `pit.py`; EMA-adjusted choices.

### AI vs AI
Set `human_vs_cpu = False` in `pit.py` and configure both sides' MCTS params.

### Optional: Use native engine as a baseline/opponent
We provide a thin UCI-like `engine_bridge.py` to interact with the C++ engine.
- Environment variable `SANMILL_ENGINE` can point to the engine executable.
- The bridge sends `uci`, `setoption` (standard rules), `position`, `go`, and
  uses `analyze` to enumerate legal moves.

## Periods and network heads
- period 0: placing
- period 1: moving
- period 2: flying (when player has only 3 pieces)
- period 3: capture (after forming a mill)
- period 4: training-only branch when opponent has 3 but we have >3

Different periods use different heads (`GameNNet.branch`); training routes samples by period.

## FAQ
- “No model in path ./temp/best.pth.tar” in `pit.py`: train once or place your model there
- Windows multi-process hangs: run `python main.py`, ensure `if __name__ == "__main__":` exists; set `num_processes = 1` if needed
- OOM/slow: reduce `num_channels`, `batch_size`, or `numMCTSSims`; reduce `epochs` or raise `tempThreshold`
- Unstable: reduce `lr`; increase `numMCTSSims`; increase `arenaCompare`

## References
- [alpha-zero-general](https://github.com/suragnair/alpha-zero-general)
- [Sanmill](https://github.com/calcitem/Sanmill)
