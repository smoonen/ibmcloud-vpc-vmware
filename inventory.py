# Serialize inventory to JSON file

import json

class Inventory :
  def __init__(self, filename = "inventory.json") :
    self.filename = filename
    self._load()

  def _load(self) :
    with open(self.filename, "r") as infile :
      self.data = json.load(infile)

  def _save(self) :
    with open(self.filename, "w") as outfile :
      json.dump(self.data, outfile, indent = 2)

  def get(self, key, default = None) :
    try :
      result = self.data
      for item in key.split('.') :
        result = result[item]
      return result
    except :
      return default

  def set(self, key, value) :
    keys = key.split('.')
    index = self.data
    while len(keys) > 1 :
      subkey = keys.pop(0)
      if subkey not in index :
        index[subkey] = { }
      index = index[subkey]
    index[keys[0]] = value
    self._save()

