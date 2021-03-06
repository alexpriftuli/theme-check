# frozen_string_literal: true
module ThemeCheck
  class Cli
    class Abort < StandardError; end

    USAGE = <<~END
      Usage: theme-check [options] /path/to/your/theme

      Options:
        -c, [--category]          # Only run this category of checks
        -x, [--exclude-category]  # Exclude this category of checks
        -l, [--list]              # List enabled checks
        -a, [--auto-correct]      # Automatically fix offenses
        -h, [--help]              # Show this. Hi!

      Description:
        Theme Check helps you follow Shopify Themes & Liquid best practices by analyzing the
        Liquid & JSON inside your theme.

        You can configure checks in the .theme-check.yml file of your theme root directory.
    END

    def run(argv)
      path = "."

      command = :check
      only_categories = []
      exclude_categories = []
      auto_correct = false

      args = argv.dup
      while (arg = args.shift)
        case arg
        when "--help", "-h"
          raise Abort, USAGE
        when "--category", "-c"
          only_categories << args.shift.to_sym
        when "--exclude-category", "-x"
          exclude_categories << args.shift.to_sym
        when "--list", "-l"
          command = :list
        when "--auto-correct", "-a"
          auto_correct = true
        else
          path = arg
        end
      end

      @config = ThemeCheck::Config.from_path(path)
      @config.only_categories = only_categories
      @config.exclude_categories = exclude_categories
      @config.auto_correct = auto_correct

      send(command)
    end

    def run!(argv)
      run(argv)
    rescue Abort => e
      if e.message.empty?
        exit(1)
      else
        abort(e.message)
      end
    end

    def list
      puts @config.enabled_checks
    end

    def check
      puts "Checking #{@config.root} ..."
      theme = ThemeCheck::Theme.new(@config.root, ignored_patterns: @config.ignored_patterns)
      if theme.all.empty?
        raise Abort, "No templates found.\n#{USAGE}"
      end
      analyzer = ThemeCheck::Analyzer.new(theme, @config.enabled_checks, @config.auto_correct)
      analyzer.analyze_theme
      analyzer.correct_offenses
      ThemeCheck::Printer.new.print(theme, analyzer.offenses, @config.auto_correct)
      raise Abort, "" if analyzer.uncorrectable_offenses.any?
    end
  end
end
