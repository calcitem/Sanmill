#!/usr/bin/env python3
"""
Script to inspect saved model architecture
"""
import torch

def inspect_model(model_path):
    print(f"Inspecting model: {model_path}")
    
    # Load checkpoint
    checkpoint = torch.load(model_path, map_location='cpu')
    
    print(f"Checkpoint keys: {list(checkpoint.keys())}")
    
    if 'model_state_dict' in checkpoint:
        state_dict = checkpoint['model_state_dict']
    else:
        state_dict = checkpoint
    
    print(f"\nTotal parameters: {len(state_dict)}")
    
    # Analyze architecture from state_dict keys
    residual_blocks = set()
    input_channels = None
    num_filters = None
    
    for key in state_dict.keys():
        if key.startswith('residual_blocks.'):
            block_num = int(key.split('.')[1])
            residual_blocks.add(block_num)
        elif key == 'input_conv.conv.weight':
            # Shape is [out_channels, in_channels, kernel_h, kernel_w]
            shape = state_dict[key].shape
            num_filters = shape[0]
            input_channels = shape[1]
            print(f"Input conv weight shape: {shape}")
            print(f"  -> Input channels: {input_channels}")
            print(f"  -> Num filters: {num_filters}")
    
    num_residual_blocks = len(residual_blocks)
    print(f"Number of residual blocks: {num_residual_blocks}")
    print(f"Residual block indices: {sorted(residual_blocks)}")
    
    # Check policy and value heads
    policy_shape = None
    value_shape = None
    
    if 'policy_conv.conv.weight' in state_dict:
        policy_shape = state_dict['policy_conv.conv.weight'].shape
        print(f"Policy head conv shape: {policy_shape}")
    
    if 'policy_head.weight' in state_dict:
        policy_linear_shape = state_dict['policy_head.weight'].shape
        print(f"Policy head linear shape: {policy_linear_shape}")
        action_size = policy_linear_shape[0]
        print(f"  -> Action size: {action_size}")
    
    if 'value_conv.conv.weight' in state_dict:
        value_shape = state_dict['value_conv.conv.weight'].shape
        print(f"Value head conv shape: {value_shape}")
    
    if 'value_head.weight' in state_dict:
        value_linear_shape = state_dict['value_head.weight'].shape
        print(f"Value head linear shape: {value_linear_shape}")
    
    # Print suggested configuration
    print(f"\n" + "="*50)
    print("SUGGESTED MODEL CONFIGURATION:")
    print("="*50)
    print(f"input_channels = {input_channels}")
    print(f"num_filters = {num_filters}")
    print(f"num_residual_blocks = {num_residual_blocks}")
    if 'policy_head.weight' in state_dict:
        action_size = state_dict['policy_head.weight'].shape[0]
        print(f"action_size = {action_size}")
    else:
        print("action_size = 1000  # Default, couldn't determine from model")
    print("dropout_rate = 0.3  # Default")

if __name__ == '__main__':
    model_path = "G:/models_from_npz/epochs/chunked_checkpoint_epoch_2.tar"
    inspect_model(model_path)
