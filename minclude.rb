#! /usr/bin/ruby

# == Synopsis
#
# minclude: removes unnecessary #include directives from header files
# 
# == Usage
# 
# fix_includes [OPTION] ... FILES
# 
# -h, --help:
#    show help
# 
# -b dir, --base dir:
#    treat dir as the root directory for includes
# 
# -r, --recursive:
#    find *.h files recursively
# 
# -v, --verbose:
#    print out extra information
#
# -d, --dry-run:
#    don't actually alter the files (implies -v)
# 
# FILES: A list of header files to process

require 'getoptlong'
require 'rdoc/usage'

$includes = /^#include "([a-z0-9\/]+\.h)"/i

def fix_set(files, base='', verbose=false, dry_run=false)
  includes, deleted = {}, {}
  files.each do |file|
    includes[file] = get_includes(file, base)
    deleted[file] = []
  end
  includes.each do |file,included|
    index = 0
    while index < included.size
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
    if verbose
      puts file + ':'
      includes[file].each {|f| puts "  + #{f}"}
      deleted[file].each {|f| puts  "  - #{f}"}
      puts ""
    end
    unless dry_run
      remove_includes file, deleted[file], base
    end
  end
end

def get_includes(file, base)
  includes = File.read(file).scan($includes).flatten
  includes.map {|included| base + included}
end

def remove_includes(file, removed, base)
  removed.map! do |to_remove|
    "#include \"#{to_remove[base.size..-1]}\""
  end
  fixed = File.readlines(file).reject do |line|
    removed.any? {|r| line.index r}
  end.join ''
  File.open(file, 'w') {|f| f.write(fixed)}
end

def walk(map, current, skip_first=false, stack=[], &block)
  if (idx = stack.index current)
    cycle = stack[idx..-1] + [current]
    raise "cycle detected\n#{cycle.join(' -> ')}"
  end
  yield current unless skip_first
  deeper = stack + [current]
  (map[current] || []).each do |child|
    walk(map, child, false, deeper, &block)
  end
end

if $0 == __FILE__
  opts = GetoptLong.new(
    ['--help', '-h', GetoptLong::NO_ARGUMENT],
    ['--base', '-b', GetoptLong::REQUIRED_ARGUMENT],
    ['--recursive', '-r', GetoptLong::NO_ARGUMENT],
    ['--verbose', '-v', GetoptLong::NO_ARGUMENT],
    ['--dry-run', '-d', GetoptLong::NO_ARGUMENT]
  )

  base = ''
  recursive = false
  verbose = false
  dry_run = false

  opts.each do |opt,arg|
    case opt
      when '--help'
        RDoc::usage
        exit 0
      when '--base'
        base = arg + '/'
      when '--recursive'
        recursive = true
      when '--verbose'
        verbose = true
      when '--dry-run'
        verbose = true
        dry_run = true
    end
  end

  if ARGV.size == 0
    RDoc::usage
    exit 0
  end

  input = ARGV
  if recursive
    input.map! {|root| Dir["#{root}/**/*.h"]}.flatten!
  end

  if input.size < 2
    puts "Must specify at least two files (see --help)"
    exit 0
  end

  fix_set input, base, verbose, dry_run
end
