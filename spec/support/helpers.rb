module Spec
  module Helpers
    def run_in_context(cmd)
      env = bundled_app("vendor", "gems", "environment")
      ruby "-r #{env}", cmd
    end

    def ruby(opts, ruby = nil)
      ruby, opts = opts, nil unless ruby
      ruby.gsub!(/(?=")/, "\\")
      lib = File.join(File.dirname(__FILE__), '..', '..', 'lib')
      %x{#{Gem.ruby} -I#{lib} #{opts} -e "#{ruby}"}.strip
    end

    def gem_command(command, args = "")
      if command == :exec
        args = args.gsub(/(?=")/, "\\")
        args = %["#{args}"]
      end
      lib  = File.join(File.dirname(__FILE__), '..', '..', 'lib')
      %x{#{Gem.ruby} -I#{lib} -rubygems -S gem #{command} #{args}}.strip
    end

    def build_manifest_file(*args)
      path = bundled_app("Gemfile")
      path = args.shift if args.first.is_a?(Pathname)
      str  = args.shift || ""
      FileUtils.mkdir_p(path.dirname)
      File.open(path, 'w') do |f|
        f.puts str
      end
    end

    def build_manifest(*args)
      path = bundled_app("Gemfile")
      path = args.shift if args.first.is_a?(Pathname)
      str  = args.shift || ""
      FileUtils.mkdir_p(path.dirname)
      Dir.chdir(path.dirname) do
        build_manifest_file(path, str)
        Bundler::Environment.load(path)
      end
    end

    def install_manifest(*args)
      m = build_manifest(*args)
      m.install
      m
    end

    def build_git_repo(name, options = {})
      name = name.to_s
      with = options[:with] or raise "Omg, need to specify :with"
      path = tmp_path.join("git", name)
      path.parent.mkdir_p
      with.cp_r(path)
      if spec = options[:spec]
        File.open(path.join("#{name}.gemspec"), 'w') do |file|
          file.puts spec.to_ruby
        end
      end
      Dir.chdir(path) do
        `git init`
        `git add *`
        `git commit -m "OMG GITZ"`
        `git checkout -b alt`
        path.join("lib", name).mkdir_p
        File.open(path.join("lib", name, "in_a_branch.rb"), 'w') do |file|
          file.puts "OMG_IN_A_BRANCH = 'tagged'"
        end
        `git add *`
        `git commit -m "OMG TAGGING"`
        `git tag tagz`
        File.open(path.join("lib", name, "in_a_branch.rb"), 'w') do |file|
          file.puts "OMG_IN_A_BRANCH = 'branch'"
        end
        `git add *`
        `git commit -m "OMG BRANCHING"`
        `git checkout master`
      end
      path
    end

    def gitify(path)
      Dir.chdir(path) do
        `git init && git add * && git commit -m "OMG GITZ"`
      end
    end

    class LibBuilder
      def initialize(name, version)
        @spec = Gem::Specification.new do |s|
          s.name = name
          s.version = version
        end
        @files = { "lib/#{name}.rb" => "#{name.upcase} = 'required'" }
      end

      def method_missing(*args, &blk)
        @spec.send(*args, &blk)
      end

      def write(file, source)
        @files[file] = source
      end

      def _build(path)
        path ||= tmp_path('dirs', name)
        @files["#{name}.gemspec"] = @spec.to_ruby
        @files.each do |file, source|
          file = path.join(file)
          file.dirname.mkdir_p
          File.open(file, 'w') { |f| f.puts source }
        end
        path
      end
    end

    def lib_builder(name, version, options = {})
      spec = LibBuilder.new(name, version)
      yield spec if block_given?
      spec._build(options[:path] || tmp_path('dirs', name))
    end

    def reset!
      tmp_path.rmtree if tmp_path.exist?
      tmp_path.mkdir
    end
  end
end