require 'pry'
require './lib'

fin = './testdata/ForceMap001.ARDF'
raw = File.open(fin, 'rb').read
ptr = 0
objects = []

while ptr < raw.size-1
  new_obj = ARDF.new(raw, ptr)
  ptr += new_obj.size
  objects.push new_obj
end

binding.pry