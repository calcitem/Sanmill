import json
import pandas as pd

# Specify your .arb file and output .csv file here
input_arb_file = "/path/to/your/input.arb"
output_csv_file = "/path/to/your/output.csv"

# Load the .arb file
with open(input_arb_file) as f:
    arb_file_contents = json.load(f)

# Create a new DataFrame to store keys, descriptions and values separately
df_new = pd.DataFrame(columns=["Key", "Description", "Value"])

for key, value in arb_file_contents.items():
    if key.startswith("@"):
        continue
    description = arb_file_contents.get("@" + key, {}).get('description', '')
    df_new = df_new.append({
        "Key": key,
        "Description": description,
        "Value": str(value).replace("{", "").replace("}", "").replace("'", "").replace('"', '')
    }, ignore_index=True)

# Save the new DataFrame to a CSV file
df_new.to_csv(output_csv_file, index=False)
