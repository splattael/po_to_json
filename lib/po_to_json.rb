# -*- coding: UTF-8 -*-
# frozen_string_literal: true
#
# Copyright (c) 2012-2015 Dropmysite.com <https://dropmyemail.com>
# Copyright (c) 2015 Webhippie <http://www.webhippie.de>
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

gem "json", version: ">= 1.6.0"
require "json"

class PoToJson
  autoload :Version, File.expand_path("../po_to_json/version", __FILE__)

  attr_accessor :files
  attr_accessor :glue
  attr_accessor :options
  attr_accessor :errors
  attr_accessor :values
  attr_accessor :buffer
  attr_accessor :lastkey
  attr_accessor :trans

  def initialize(files, glue = "|")
    @files = files
    @glue = glue
  end

  def generate_for_jed(language, overwrite = {})
    @options = parse_options(overwrite.merge(language: language))
    @parsed ||= inject_meta(parse_document)

    generated = build_json_for(build_jed_for(@parsed))

    [
      @options[:variable_locale_scope] ? 'var' : '',
      "#{@options[:variable]} = #{@options[:variable]} || {};",
      "#{@options[:variable]}['#{@options[:language]}'] = #{generated};"
    ].join(" ")
  end

  def generate_for_json(language, overwrite = {})
    @options = parse_options(overwrite.merge(language: language))
    @parsed ||= inject_meta(parse_document)

    generated = build_json_for(build_json_for(@parsed))

    fail "Not implemented yet, current value is #{generated}!"
  end

  def parse_document
    reset_buffer
    reset_result

    File.foreach(files) do |line|
      matches_values_for(line.chomp! || line)
    end

    flush_buffer
    parse_header

    values
  end

  def flush_buffer
    return unless buffer["msgid"]

    build_trans
    assign_trans

    reset_buffer
  end

  def parse_header
    return if reject_header

    values[""][0].split("\\n").each do |line|
      next if line.empty?
      build_header_for(line)
    end

    values[""] = headers
  end

  def reject_header
    if values[""].nil? || values[""][0].nil?
      values[""] = {}
      true
    else
      false
    end
  end

  protected

  def trans
    @trans ||= []
  end

  def errors
    @errors ||= []
  end

  def values
    @values ||= {}
  end

  def buffer
    @buffer ||= {}
  end

  def headers
    @headers ||= {}
  end

  def lastkey
    @lastkey ||= ""
  end

  def reset_result
    @values = {}
    @errors = []
  end

  def reset_buffer
    @buffer = {}
    @trans = []
    @lastkey = ""
  end

  def detect_ctxt
    msgctxt = buffer["msgctxt"]
    msgid = buffer["msgid"]

    if msgctxt && msgctxt.size > 0
      [msgctxt, glue, msgid].join("")
    else
      msgid
    end
  end

  def detect_plural
    plural = buffer["msgid_plural"]
    plural if plural && plural.size > 0
  end

  def build_trans
    buffer.each do |key, string|
      trans[$1.to_i] = string if /^msgstr_(\d+)/.match(key)
    end

    # trans.unshift(detect_plural) if detect_plural
  end

  def assign_trans
    values[detect_ctxt] = trans if trans.size > 0
  end

  def push_buffer(value, key)
    if key.nil?
      buffer[lastkey] = [
        buffer[lastkey],
        value
      ].join("")
    else
      buffer[key] = value
      @lastkey = key
    end
  end

  def parse_options(options)
    defaults = {
      pretty: false,
      domain: "app",
      variable: "locales",
      variable_locale_scope: true
    }

    defaults.merge(options)
  end

  def inject_meta(hash)
    hash[""]["lang"] ||= options[:language]
    hash[""]["domain"] ||= options[:domain]
    hash[""]["plural_forms"] ||= hash[""]["Plural-Forms"]

    hash
  end

  def build_header_for(line)
    if line =~ /(.*?):(.*)/
      key = $1
      value = $2

      if headers.key? key
        errors.push "Duplicate header: #{line}"
      elsif key =~ /#-#-#-#-#/
        errors.push "Marked header: #{line}"
      else
        headers[key] = value.strip
      end
    else
      errors.push "Malformed header: #{line}"
    end
  end

  def build_json_for(hash)
    if options[:pretty]
      JSON.pretty_generate(hash)
    else
      JSON.generate(hash)
    end
  end

  def build_jed_for(hash)
    {
      domain: options[:domain],
      locale_data: {
        options[:domain] => hash
      }
    }
  end

  def matches_values_for(line)
    return if generic_rejects? line
    return if iterate_detects_for(line)

    errors.push "Strange line #{line}"
  end

  REGEXP = %r{
    ^(?:\#~ )?
    (?:
      (?<key>
        msgctxt         |
        msgid           |
        msgid_plural    |
        msgstr          |
        msgstr\[(?<index>\d+)\]
      )
      \s+
    )?
    "(?<value>.*)"
  }x

  def iterate_detects_for(line)
    match = REGEXP.match(line)
    return false unless match
    if match[:key]&.start_with?("msgstr")
      index = match[:index] || 0
      push_buffer(match[:value], "msgstr_#{index}")
    else
      push_buffer(match[:value], match[:key])
    end

    true
  end

  def generic_rejects?(line)
    if line.empty? || /^(#[^~]|[#]$)/.match?(line)
      flush_buffer && true
    else
      false
    end
  end
end
