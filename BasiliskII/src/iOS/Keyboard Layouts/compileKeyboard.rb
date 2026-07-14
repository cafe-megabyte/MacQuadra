#!/usr/bin/env ruby

require 'rubygems'
require 'json'

raise ArgumentError.new("usage: compileKeyboard in out") unless ARGV.count == 2
input, output = ARGV
layout = JSON.parse(File.read(input))

puts "Compiling #{input} to #{output}"
puts "Loaded keyboard #{layout['name']}"

out = File.open(output, 'wb')
class String
  def pstr(encoding = Encoding::UTF_8)
    estr = self.encode(encoding)
    raise RuntimeError.new("String too long") if estr.bytesize > 255
    [estr.bytesize, estr].pack('CA*')
  end
end
# header with version, id, name, type
out.write ['NFKeyboard', 1, layout['id'].pstr, layout['name'].pstr, layout['adbType']].pack('A*vA*A*C')

# label list
labels = layout['labels']
(0..127).each do |i|
  out.write labels[i.to_s]&.pstr || "\0"
end

# names of keyplanes
number_of_keyplanes = labels.keys.count{ |k| k.to_i < 0}
puts "Layout has #{number_of_keyplanes} keyplanes"
out.write [number_of_keyplanes].pack('C')
labels.keys.select{|k| k.to_i < 0}.map(&:to_i).map(&:abs).sort.each do |i|
  out.write labels["-#{i}"].pstr
end

# index
maps = layout.keys - %w(id name adbType labels) # TODO: sort by dependency
map_name_to_id = {}
index_offset = {}
out.write [maps.count].pack('C')
maps.each do |name|
  if name.start_with?'{'
    # size
    width, height = name[1..-2].split(',').map(&:to_i)
    map_id = (width << 16) | (height)
  else
    # name
    map_id = map_name_to_id.count+1
  end
  map_name_to_id[name] = map_id
  out.write [map_id, 0xFFFF].pack('Vv') # write offset later
  index_offset[map_id] = out.tell - 2
end

def make_frame(new_frame, last_frame)
  frame = new_frame.dup
  (0..3).each { |i| frame[i] = last_frame[i] if frame[i].nil?}
  frame
end

def diff_frame(frame, last_frame)
  return [0x7FFF] if frame == last_frame
  diff = frame.dup
  (0..3).each { |i| diff[i] = 0x7FFF if diff[i] == last_frame[i]}
  3.times { diff.pop if diff.last == 0x7FFF }
  diff
end

# write maps
puts "Layout has #{maps.count} maps"
maps.each do |name|
  puts "Writing #{name} at #{out.tell}"
  map_id = map_name_to_id[name]
  # write offset to index
  offset = out.tell
  out.seek(index_offset[map_id])
  out.write [offset].pack('v')
  out.seek(offset)
  
  # write layout
  (1..number_of_keyplanes).each do |i|
    keyplane = layout[name][i-1]
    if keyplane.nil?
      out.write "\0"
      next
    end
    
    # number of items
    out.write [keyplane.count].pack('C')
    last_frame = [nil,nil,nil,nil]
    keyplane.each do |item|
      if item['key']
        # key (type 0)
        # flags: type:2, dark:1, sticky:1, font_scale:2, frame_size:2
        # scancode int8
        # frame: 2,4,6,8 bytes
        dark = item['dark'] || false
        sticky = item['sticky'] || false
        scale = item['fontScale'] || 1.0
        raise ArgumentError.new("Invalid scale for key #{item.to_json}") if scale % 0.25 != 0.0
        scale_flag = (scale / 0.25).to_i - 1
        # compute frame
        frame = item['frame']
        raise ArgumentError.new("Invalid frame for key #{item.to_json}") if frame.length > 4 || frame.empty?
        key_frame = make_frame(frame, last_frame)
        raise ArgumentError.new("Could not compute frame for key #{item.to_json}") if key_frame.any?(&:nil?)
        write_frame = diff_frame(key_frame, last_frame)
        last_frame = key_frame
        # flags
        flags = write_frame.count - 1
        flags |= scale_flag << 2
        flags |= 0x10 if sticky
        flags |= 0x20 if dark
        # scancode
        scancode = item['key']
        scancode = -128 if scancode == 'hide'
        scancode = -127 if scancode == 'shift/caps'
        raise ArgumentError.new("Invalid scancode for key #{item.to_json}") unless scancode.is_a?(Integer) && (-128..127).include?(scancode)
        out.write [flags, scancode, write_frame].flatten.pack('Ccv*')
      elsif item['include']
        # include (type 1)
        # flags: type:2, has_scale:1, has_translate:1, plane: 4
        # id: 4 bytes
        # scale: 8 bytes (two float32)
        # translate: 4 bytes (two int16)
        # skip: array of scancodes (length-prefixed)
        last_frame = [nil,nil,nil,nil]
        include_name, include_plane = item['include']
        raise ArgumentError.new("#{name} depends on #{include_name}, but it's not written yet") if maps.find_index(include_name) > maps.find_index(name)
        include_id = map_name_to_id[include_name]
        raise ArgumentError.new("Unknown include for key #{item.to_json}") if include_id.nil?
        raise ArgumentError.new("Invalid plane for key #{item.to_json}") unless (0..15).include?(include_plane)
        scale = item['scale']
        translate = item['translate']
        flags = 0x40 | include_plane
        flags |= 0x20 if scale != nil
        flags |= 0x10 if translate != nil
        out.write [flags, include_id].pack('CV')
        out.write scale.pack('ee') unless scale.nil?
        out.write translate.pack('s<s<') unless translate.nil?
        skip = item['skip'] || []
        skip.unshift(skip.count)
        out.write skip.pack('c*')
      else
        raise ArgumentError.new("Unknown item #{item.to_json}")
      end
    end
  end
end
