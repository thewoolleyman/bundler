# Extending Gem classes to add necessary tracking information
module Gem
  class Dependency
    def required_by
      @required_by ||= []
    end
  end
  class Specification
    def required_by
      @required_by ||= []
    end
  end
end

module Bundler

  class Resolver

    attr_reader :errors

    def self.resolve(requirements, index = Gem.source_index)
      result = catch(:success) do
        resolver = new(index)
        resolver.resolve(requirements, {})
        puts "ERRORS:"
        puts "======="
        resolver.errors.each do |k,v|
          puts "  #{k}"
        end
        nil
      end
      result && result.values
    end

    def initialize(index)
      @errors = {}
      @stack  = []
      @index  = index
    end
    
    def debug(str = "", nl = true)
      return unless ENV['DEBUG']
      if nl
        puts str
      else
        print str
      end
    end
    
    def wait
      STDIN.getc if ENV['DEBUG']
    end

    def resolve(reqs, activated)
      throw :success, activated if reqs.empty?

      reqs = reqs.sort_by do |req|
        activated[req.name] ? 0 : @index.search(req).size
      end
      
      wait
      debug "\e[2J\e[f", true
      debug "Requirements:"
      reqs.each do |r|
        debug "  * #{r}"
      end
      debug
      debug "Activated:"
      activated.each do |k,v|
        debug "  * #{v.full_name}"
      end
      debug
      debug "-----"

      activated = activated.dup
      current   = reqs.shift
      
      debug "Attempting: #{current}"

      if existing = activated[current.name]
        if current.version_requirements.satisfied_by?(existing.version)
          debug "  Existing: #{existing.full_name} -- SUCCESS"
          @errors.delete(existing.name)
          resolve(reqs, activated)
        else
          @errors[existing.name] = { :gem => existing, :requirement => current }
          parent = current.required_by.last || existing.required_by.last
          debug "  Existing: #{existing.full_name} -- FAIL"
          debug "  BACKTRACK: #{parent.name}"
          throw parent.name, existing.required_by.last.name
        end
      else
        fail = []
        @index.search(current).reverse_each do |spec|
          fail << resolve_requirement(spec, current, reqs.dup, activated.dup)
        end
        fail.compact!
        fail.uniq!
        # If this is a root level dependency, then backtrack to the highest
        # point on the stack that caused a conflict
        if current.required_by.last.nil? && fail.any?
          spot = @stack.reverse.detect { |i| fail.include?(i) }
          throw spot
        end
      end
    end

    def resolve_requirement(spec, requirement, reqs, activated)
      spec.required_by.replace requirement.required_by
      activated[spec.name] = spec
      
      debug "  Activating: #{spec.full_name}"
      debug "  Requirements: #{spec.dependencies.select { |d| d.type!=:development}.map{|d|d.to_s}.join(", ")}"

      spec.dependencies.each do |dep|
        next if dep.type == :development
        dep.required_by << requirement
        reqs << dep
      end

      debug "  SAVEPOINT: #{requirement.name}"
      @stack << requirement.name
      retval = catch(requirement.name) do
        resolve(reqs, activated)
      end
      @stack.pop
      retval
    end

  end
end