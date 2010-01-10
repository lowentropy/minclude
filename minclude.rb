#! /usr/bin/ruby

# Copyright 2009 Nathan Matthews <lowentropy@gmail.com>
# 
# This file is part of minclude.
# 
# minclude is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# minclude is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with minclude.  If not, see <http://www.gnu.org/licenses/>.

# == Synopsis
#
# minclude: removes unnecessary #include directives from header files
# 
# == Usage
# 
# minclude.rb [OPTION] ... FILES
# 
# -h, --help:
#    show help
# 
# -b dir, --base dir:
#    treat dir as the root directory for includes
#
# -c, --allow-cycles:
#    don't treat cycles as an exception
# 
# -r, --recursive:
#    find files recursively
#
# -e ext, --extensions ext
#    use the given comma-separated extensions (defaults to just h)
#
# -v, --verbose:
#    print out debugging information
#
# -d, --dry-run:
#    don't actually alter the files (implies -v)
# 
# FILES: A list of header files to process

require 'getoptlong'
require 'rdoc/usage'

$includes = /^#include "([a-z0-9\/]+\.h)"/i

# worker class for minimizing includes
class Minclude

  # options for runtime behavior
  attr_reader :verbose, :dry_run, :allow_cycles

  # construct worker with given options
  def initialize(options={})
    @verbose = options[:verbose] || false
    @dry_run = options[:dry_run] || false
    @allow_cycles = options[:allow_cycles] || false
  end

  # take all the header files and remove unnecessary include directives
  def fix_headers(files, base)
    includes, deleted = {}, {}
    # gather includes
    files.each do |file|
      includes[file] = get_includes(file, base)
      deleted[file] = []
    end
    # process each root file
    includes.each do |file,included|
      index = 0
      while index < included.size
        # remove root includes which are also descendants
        walk(includes, included[index], true) do |subfile|
          if included.delete subfile
            deleted[file] << subfile
            index -= 1
          end
        end
        index += 1
      end
    end
    includes.keys.sort.each do |file|
      # print debugging info
      if verbose
        puts file + ':'
        includes[file].each {|f| puts "  + #{f}"}
        deleted[file].each {|f| puts  "  - #{f}"}
        puts ""
      end
      # fix the file
      unless dry_run
        remove_includes file, deleted[file], base
      end
    end
  end

  # collect all include directives from a file
  def get_includes(file, base)
    includes = File.read(file).scan($includes).flatten
    includes.map {|included| base + included}
  end

  # remove certain include directives from a file
  def remove_includes(file, removed, base)
    removed.map! do |to_remove|
      "#include \"#{to_remove[base.size..-1]}\""
    end
    fixed = File.readlines(file).reject do |line|
      removed.any? {|r| line.index r}
    end.join ''
    File.open(file, 'w') {|f| f.write(fixed)}
  end

  # walk a tree of include file dependencies
  def walk(map, current, skip_first=false, stack=[], &block)
    # check for cycles
    if (idx = stack.index current)
      cycle = stack[idx..-1] + [current]
      message = "cycle detected: #{cycle.join(' -> ')}"
      if allow_cycles
        puts message if verbose
      else
        raise message
      end
    end
    # call the block
    yield current unless skip_first
    # walk the children
    stack.push current
    (map[current] || []).each do |child|
      walk(map, child, false, stack, &block)
    end
  end
end


if $0 == __FILE__
  # get options
  opts = GetoptLong.new(
    ['--help', '-h', GetoptLong::NO_ARGUMENT],
    ['--base', '-b', GetoptLong::REQUIRED_ARGUMENT],
    ['--recursive', '-r', GetoptLong::NO_ARGUMENT],
    ['--extensions', '-e', GetoptLong::REQUIRED_ARGUMENT],
    ['--allow-cycles', '-c', GetoptLong::NO_ARGUMENT],
    ['--verbose', '-v', GetoptLong::NO_ARGUMENT],
    ['--dry-run', '-d', GetoptLong::NO_ARGUMENT]
  )

  options = {}
  base = ''
  help = false
  recursive = false
  ext = 'h'

  # collect option flags
  opts.each do |opt,arg|
    case opt
    when '--help'
      help = true
    when '--base'
      base = arg
    when '--recursive'
      recursive = true
    when '--allow-cycles'
      options[:allow_cycles] = true
    when '--verbose'
      options[:verbose] = true
    when '--dry-run'
      options[:dry_run] = true
      options[:verbose] = true
    when '--extensions'
      ext = arg
    end
  end

  # the user needs some help
  if help or ARGV.size == 0
    RDoc::usage
    exit 0
  end

  # recursively find headers
  input = ARGV
  if recursive
    input.map! {|root| Dir["#{root}/**/*.{#{ext}}"]}.flatten!
  end

  # we need a set of input files
  if input.size < 2
    puts "Must specify at least two files (see --help)"
    exit 0
  end

  # fix the base path
  base += '/' unless base =~ /\/$/

  # run worker with our options
  Minclude.new(options).fix_headers(input, base)
end
