require 'pry'
require './lib'

def raw_load(fin)
  raw = File.open(fin, 'rb').read
  ptr = 0
  objects = []

  while ptr < raw.size-1
    new_obj = ARDF.new(raw, ptr)
    ptr += new_obj.size
    objects.push new_obj
  end
  File.open("object_list.txt", "w") {|f| f.puts (0..objects.size-1).map{|i| "#{i}: #{objects[i].inspect}"}}
end

fin = './testdata/ForceMap001.ARDF'
ardf1 = ForceMap.new fin

binding.pry