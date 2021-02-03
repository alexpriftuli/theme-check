# frozen_string_literal: true

module ThemeCheck
  class Config
    DOTFILE = '.theme-check.yml'
    DEFAULT_CONFIG = "#{__dir__}/../../config/default.yml"
    BOOLEAN = [true, false]

    attr_reader :root
    attr_accessor :only_categories, :exclude_categories, :auto_correct

    class << self
      def from_path(path)
        if (filename = find(path))
          new(filename.dirname, load_file(filename))
        else
          # No configuration file
          new(path)
        end
      end

      def find(root, needle = DOTFILE)
        Pathname.new(root).descend.reverse_each do |path|
          pathname = path.join(needle)
          return pathname if pathname.exist?
        end
        nil
      end

      def load_file(absolute_path)
        YAML.load_file(absolute_path)
      end

      def default
        @default ||= load_file(DEFAULT_CONFIG)
      end
    end

    def initialize(root, configuration = nil)
      @configuration = if configuration
        validate_configuration(configuration)
      else
        {}
      end
      merge_with_default_configuration!(@configuration)

      @root = Pathname.new(root)
      if @configuration.key?("root")
        @root = @root.join(@configuration["root"])
      end

      @only_categories = []
      @exclude_categories = []
      @auto_correct = false

      resolve_requires
    end

    def [](name)
      @configuration[name]
    end

    def to_h
      @configuration
    end

    def check_configurations
      @check_configurations ||= @configuration.select { |name, _| check_name?(name) }
    end

    def enabled_checks
      @enabled_checks ||= check_configurations.map do |check_name, options|
        next unless options["enabled"]

        check_class = ThemeCheck.const_get(check_name)

        next if exclude_categories.include?(check_class.category)
        next if only_categories.any? && !only_categories.include?(check_class.category)

        options_for_check = options.transform_keys(&:to_sym)
        options_for_check.delete(:enabled)
        check = if options_for_check.empty?
          check_class.new
        else
          check_class.new(**options_for_check)
        end
        check.options = options_for_check
        check
      end.compact
    end

    def ignored_patterns
      self["ignore"] || []
    end

    private

    def check_name?(name)
      name.to_s.start_with?(/[A-Z]/)
    end

    def validate_configuration(configuration, default_configuration = self.class.default, parent_keys = [])
      valid_configuration = {}

      configuration.each do |key, value|
        # No validation possible unless we have a default to compare to
        unless default_configuration
          valid_configuration[key] = value
          next
        end

        default = default_configuration[key]
        keys = parent_keys + [key]
        name = keys.join(".")

        if check_name?(key)
          if value.is_a?(Hash)
            valid_configuration[key] = validate_configuration(value, default, keys)
          else
            warn("bad configuration type for #{name}: expected a Hash, got #{value.inspect}")
          end
        elsif default.nil?
          warn("unknown configuration: #{name}")
        elsif BOOLEAN.include?(default) && !BOOLEAN.include?(value)
          warn("bad configuration type for #{name}: expected true or false, got #{value.inspect}")
        elsif !BOOLEAN.include?(default) && default.class != value.class
          warn("bad configuration type for #{name}: expected a #{default.class}, got #{value.inspect}")
        else
          valid_configuration[key] = value
        end
      end

      valid_configuration
    end

    def merge_with_default_configuration!(configuration, default_configuration = self.class.default)
      default_configuration.each do |key, default|
        value = configuration[key]

        case value
        when Hash
          merge_with_default_configuration!(value, default)
        when nil
          configuration[key] = default
        end
      end
      configuration
    end

    def resolve_requires
      self["require"]&.each do |path|
        require(File.join(@root, path))
      end
    end
  end
end
