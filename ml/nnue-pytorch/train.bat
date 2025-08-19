
python generate_training_data.py --perfect-db "E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted" --output training_data.txt --positions 200000 --seed 42


python generate_training_data.py --perfect-db "E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted" --output validation_data.txt --positions 20000 --seed 123

python train.py training_data.txt --validation-data validation_data.txt --features "NineMill" --batch-size 8192 --max_epochs 400 --in-offset 0 --out-offset 0 --in-scaling 300 --out-scaling 300

python nnue_pit.py --config nnue_pit_config.json --gui  

@pause