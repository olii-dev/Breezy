import re
import os

path = '/Users/olimebberson/Documents/Miscellaneous/iPhone Apps/Breezy/Breezy/Views/TimeMachineView.swift'
with open(path, 'r', encoding='utf-8', errors='ignore') as f: text = f.read()
text = re.sub(r'glas
\s+\d+[-:]\s+sOpacity', 'glassOpacity', text)
lines = text.split('
')
cleaned = []
for l in lines: 
  if re.search(r'\s{10,}\d+[-:]', l): l = re.split(r'\s{10,}', l)[0]
  cleaned.append(l)
with open(path, 'w', encoding='utf-8') as f: f.write('
'.join(cleaned))
