class ARDF
  attr_reader :pos, :type, :size, :misc, :entries, :data
  def initialize(raw, pos) # Stupidly preserving the whole raw as pointer is used
    @data = {}

    @pos = pos
    null, @size, @type, @misc = header(raw, pos)
    pos += 16
    raise "Size zero at #{pos}" unless @size > 0
    # puts "#{@name} at #{@pos} with size #{@size}"

    case @type
    when 'ARDF'
      # puts "ARDF begins"
    when 'FTOC', 'TTOC', 'VOLM', 'VTOC', 'IBOX' # is_an? TOC
      @size, entries_n, entry_size = raw[pos..pos+15].unpack "QLL"
      pos += 16
      @entries = Array.new(entries_n)
      raise "size mismatch" unless @size == entries_n * entry_size + 32
      # fill @entries with entries
      (0..entries_n-1).each do |i|
        begin
        @entries[i] = ARDF.new(raw, pos)
        rescue RuntimeError => err
          puts "blank table entry" if err.message == "Size zero"
        end
        pos += entry_size
      end
      # puts "end of #{@name} TOC at #{pos}"

    when 'TEXT'
      pos += 4 # For some reason there is a 4B blank before text length ui32
      content_size = raw[pos..pos+3].unpack1 "L"
      pos += 4
      raise "size < contentsize +  in TEXT, @size was #{@size} and content size was #{content_size}" unless @size >= content_size + 24
      @data[:text] = raw[pos..pos+content_size-1].split("\r")

    when 'THMB'
      if @size == 24
        @data[:ptr] = raw[pos..pos+7].unpack "q"
        # puts "This is just a pointer pointing at #{@data[:ptr]}"
        @size = 72
      else
        thumbx, thumby, couldbesize = raw[pos..pos+15].unpack "LLq"
        # puts "An actuall thumbnail with size of #{@size}. dimension #{thumbx} x #{thumby}, with each pixel having #{couldbesize} bits"
        @size = 32 + thumbx * thumby
      end

    when 'IMAG'
      if @size == 24 # tag
        @data[:ptr] = raw[pos..pos+7].unpack1 "q"
        pos += 8
        # puts "  image pointing at: #{@data[:ptr]}"
      elsif @size == 32 # TOC...
        # pasted from TOC case, seek elegance later
        @size, entries_n, entry_size = raw[pos..pos+15].unpack "QLL"
        pos += 16
        @entries = Array.new(entries_n)
        raise "size mismatch" unless @size == entries_n * entry_size + 32
        # fill @entries with entries
        (0..entries_n-1).each do |i|
          begin
          @entries[i] = ARDF.new(raw, pos)
          rescue RuntimeError => err
            # puts "blank table entry" if err.message == "Size zero"
          end
          pos += entry_size
        end
        # puts "end of #{name} TOC at #{pos}"
        # End of copy-paste
      else
        # puts "??? IMAG size of #{size}???"
      end

    when 'GAMI'
      # Do nothing, just end of IMAG - GAMI
    when 'MLOV'
      # End of VOLM

    # Volume definition?
    when 'VDEF'
      @data[:dim] = raw[pos..pos+7].unpack "LL"
      pos += 8
      pos += 24 # blank
      @data[:unknown] = raw[pos..pos+23].unpack "ddd" # 3x 64b float, xyz grid size?
      pos += 24
      @data[:unknown] += raw[pos..pos+95].unpack "q*" # 3x32B blocks
      pos += 96
      @data[:fields] = raw[pos..pos+31].split(";") # Voxel description? Extention, retraction, away?
      pos += 32
      @data[:channels_n] = raw[pos..7].unpack1 "q" # Guess to be no. of channels

    # Volume channel?
    when 'VCHN'
      @data[:title] = raw[pos..pos+31].gsub("\x0", "")
      pos += 32
      @data[:unknown] = raw[pos .. @pos+@size-1]

    when 'XDEF'
      pos += 4 # \0 x4
      string_length = raw[pos..pos+3].unpack1 "L"
      pos +=4
      @data[:fields] = raw[pos..pos+string_length-1].split(";") # Guess this is listing the data fields. And the delimitor changes again...

    when 'NEXT'
      @data[:ptr] = raw[pos..pos+7].unpack1 "q"
      # puts "  NEXT ptr: #{@data[:ptr]}"

    when 'IDEF'
      @data[:dim] = raw[pos..pos+7].unpack1 "LL"
      pos += 8
      pos += 96
      @data[:title] = raw[pos..pos+31]

    when 'XDAT'
      raise "not of size 80!" unless @size == 80
      pixel_n, row, col, dbfl_n, x, y, mystery1, mystery2, nan1, nan2 = raw[pos..pos+63].unpack("LLLLDDDDDD")
      # Consult XDEF to understand these better
      @data[:xdat] = [pixel_n, row, col, dbfl_n, x, y, mystery1, mystery2, nan1, nan2]
      pos += size
    
    # Looks like "Image data"
    when 'IDAT'
      @data[:line] = raw[pos..pos+@size-17].unpack "F*"

    # Volume offset?
    when 'VOFF'
      @data[:leading_pt], @data[:line], @data[:first_pt_x], @data[:vset_ptr] = raw[pos..pos+23].unpack "LLqq"

    when 'VSET'
      @data[:ptnum], @data[:y], @data[:x], @data[:unknown], @data[:last], @data[:next] = raw[pos..pos+31].unpack "LLLLqq"
      # The unknown seems to be always 2

    when 'VNAM'
      @data[:ptnum], @data[:y], @data[:x], text_length = raw[pos..pos+15].unpack "LLLL"
      pos += 16
      @data[:title] = raw[pos..pos+text_length-1]

    when 'VDAT'
      @data[:ptnum], @data[:y], @data[:x], datasize, @data[:channel], pt0, pt1, pt2 = raw[pos..pos+39].unpack "LLLLqLLL@@@@"
      pos += 40
      # puts "pt012: #{pt0} #{pt1} #{pt2}"
      @data[:segments] = Array.new(3)
      @data[:segments][0] = raw[pos+0..pos+pt0*4+3].unpack "F*"
      @data[:segments][1] = raw[pos+pt0*4+4..pos+pt1*4+3].unpack "F*"
      @data[:segments][2] = raw[pos+pt1*4+4..pos+pt2*4+3].unpack "F*"
      raise unless datasize * 4 == @size -56
      #puts raw[pos..pos+39].bytes.map{|i| "%02X"%i}.join(" ")


    else
      raise "#{@type} unrecognized at #{pos}! \n #{raw[pos..pos+15]}"
    end
  end

  def header(raw, pos)
    raw[pos .. pos+15].unpack("LLA4L")
    # Returns [crc, size, type, misc]
  end
  private :header

  def inspect
#  attr_reader :pos, :name, :size, :misc, :entries, :data
    report = "#{@type} at position #{@pos} size #{@size}"
    if @entries.is_a? Array
      report += ", containing #{@entries.size} entries\n" 
      report += (@entries.map{|entry| "  #{entry.inspect}"}).join("\n") # Get nesty
    end
    report += ", data hash keys: [#{@data.keys.join(", ")}]" if @data.size > 0 
    report
  end
end


class ForceMap
  attr_accessor :name
  attr_reader :channels, :width, :height
  def initialize(fin)
    raw = File.open(fin, 'rb').read.freeze
    ptr = 0

    @ardf = []
    while ptr < raw.size-1
      new_obj = ARDF.new(raw, ptr)
      ptr += new_obj.size
      @ardf.push new_obj
    end
    raw = nil # Trash it
    
    @mlov_index = @ardf.index {|o| o.type == 'MLOV'}
    
    @width, @height = @ardf.find{|o| o.type == 'VDEF'}.data[:dim]
    @channels = @ardf.filter {|o| o.type == 'VCHN'}.map {|o| o.data[:title]}

  end

  def at(x, y, segment = nil, ch = nil)
    # Brute search for now
    data = @ardf.filter {|o| o.type == 'VDAT' && o.data[:x] == x && o.data[:y] == y}
    data.filter! {|o| o.data[:channel] == ch} if ch
      if segment
        return data.map{|o| o.data[:segments][segment]}
      else
        return data.map{|o| o.data[:segments]}
      end
  end
end