```sh
python easy_train.py --config quick_config.json --fresh-start

python easy_train.py --quick --fresh-start --max-moves 200 --temperature 0.8 --workers 2

python pit_gui.py --model output/katamill_quick/best_model.pth --mcts-sims 200 --gui

python loss_analyzer.py --report output/katamill_quick/training_report.json --plot
```
