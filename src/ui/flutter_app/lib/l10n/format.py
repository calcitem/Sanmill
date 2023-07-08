import json

# Load the file
with open("./intl_is.arb", 'r', encoding='utf-8') as f:
    data = json.load(f)

# Reformat the JSON with 2-space indentation
formatted_data = json.dumps(data, ensure_ascii=False, indent=2)

# Save the formatted data to a new file
formatted_file_path = "./formatted_intl_is.arb"
with open(formatted_file_path, 'w', encoding='utf-8') as f:
    f.write(formatted_data)

formatted_file_path
