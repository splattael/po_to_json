require 'json'

class PoToJson

  CONTEXT_GLUE = '|'

  def parse_po(path_to_po)
    @parsed_values = {}
    @buffer = {}
    @last_key_type = ""
    @errors = []
    File.foreach(path_to_po) do |line|
      line = line.chomp
      case line
        # Empty lines means we have parsed one full message
        # so far and need to flush the buffer
        when /^$/ then flush_buffer
        
        # These are the po file comments
        # The second '#' in the following regex is in square brackets
        # b/c it messed up my syntax highlighter, no other reason.
        when /^(#[^~]|[#]$)/ then next
        
        when /^(?:#~ )?msgctxt\s+(.*)/ then add_to_buffer($1, :msgctxt)

        when /^(?:#~ )?msgid\s+(.*)/ then add_to_buffer($1, :msgid)

        when /^(?:#~ )?msgid_plural\s+(.*)/ then add_to_buffer($1, :msgid_plural)

        when /^(?:#~ )?msgstr\s+(.*)/ then add_to_buffer($1, :msgstr_0)

        when /^(?:#~ )?msgstr\[0\]\s+(.*)/ then add_to_buffer($1, :msgstr_0)

        when /^(?:#~ )?msgstr\[(\d+)\]\s+(.*)/ then add_to_buffer($2, "msgstr_#{$1}".to_sym)

        when /^(?:#~ )?"/ then add_to_buffer(line)
        
        else
          @errors << ["Strange line #{line}"]
      end
    end

    # In case the file did not end with a newline, we want to flush the buffer
    # one more time to write the last message too.
    flush_buffer
    
    # This will turn the header values into a friendlier json structure too.
    parse_header_lines
  
    return @parsed_values.to_json
  end
  
  def flush_buffer
    return unless @buffer[:msgid]

    msg_ctxt_id = if @buffer[:msgctxt] && @buffer[:msgctxt].size > 0
      @buffer[:msgctxt] + CONTEXT_GLUE + @buffer[:msgid]
    else
      @buffer[:msgid]
    end
    
    msgid_plural = if @buffer[:msgid_plural] && @buffer[:msgid_plural].size > 0
      @buffer[:msgid_plural]
    end

    # find msgstr_* translations and push them on
    trans = []
    @buffer.each do |key, string|
      trans[$1.to_i] = string if key.to_s =~ /^msgstr_(\d+)/
    end
    trans.unshift(msgid_plural)

    @parsed_values[msg_ctxt_id] = trans if trans.size > 1   

    @buffer = {}
    @last_key_type = ""
  end
  
  # The buffer keeps key/value pairs for all the config options
  # defined on an entry, including the message id and value.
  # For continued lines, the key_type can be empty, so the last
  # used key type will be used. Also, the content will be appended
  # to the last key rather than assigned.
  def add_to_buffer(value, key_type = nil)
    value = $1 if value =~ /^"(.*)"/
    value.gsub(/\\"/, '"')

    if key_type.nil?
      @buffer[@last_key_type] += value
    else
      @buffer[key_type] = value
      @last_key_type = key_type
    end
  end

  # The parsed values are expected to have an empty string key ("")
  # which corresponds to the po file metadata defined in it's header.
  # the header has information like the translator, the pluralization, etc.
  # Each header line is subseqently parsed into a more usable hash.
  def parse_header_lines
    if @parsed_values[""].nil? || @parsed_values[""][1].nil?
      @parsed_values[""] = {}
      return
    end
  
    headers = {}
    # Heading lines may have escaped newlines in them
    @parsed_values[""][1].split(/\\n/).each do |line|
      next if line.size == 0 

      if line =~ /(.*?):(.*)/
        key, value = $1, $2
        if headers[key] && headers[key].size > 0
          @errors << ["Duplicate header line: #{line}"]
        elsif key =~ /#-#-#-#-#/
          @errors << ["Marker in header line: #{line}"]
        else
          headers[key] = value
        end
      else
        @errors << ["Malformed header #{line}"]
      end
    end
    
    @parsed_values[""] = headers
  end
end