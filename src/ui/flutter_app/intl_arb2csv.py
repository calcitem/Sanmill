import csv
import json
import os

cmd_path = os.path.dirname(__file__)

# Init file
intl_name = 'intl_en'
arb_file_path = cmd_path + '/' + 'lib/l10n/' + intl_name + '.arb'
csv_file_path = cmd_path + '/' + 'lib/l10n/' + intl_name + '.csv'

# Read arb
with open(arb_file_path, 'r', encoding='utf8') as f:
    intl_dict = json.load(f)
for key in list(intl_dict):
    if key.startswith('@') and key != '@@locale':
        del intl_dict[key]
# Write to csv
with open(csv_file_path, mode='w', encoding='utf8') as csv_file:
    fieldnames = ['key', 'string']
    writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
    for key in list(intl_dict):
        writer.writerow({'key': key, 'string': intl_dict[key]})
