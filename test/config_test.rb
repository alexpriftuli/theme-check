# frozen_string_literal: true
require "test_helper"

class ConfigTest < Minitest::Test
  def test_load_file_uses_provided_config
    theme = make_theme(".theme-check.yml" => <<~END)
      TemplateLength:
        enabled: false
    END
    config = ThemeCheck::Config.from_path(theme.root).to_h
    assert_equal(false, config.dig("TemplateLength", "enabled"))
  end

  def test_load_file_in_parent_dir
    theme = make_theme(
      ".theme-check.yml" => <<~END,
        TemplateLength:
          enabled: false
      END
      "dist/templates/index.liquid" => "",
    )
    config = ThemeCheck::Config.from_path(theme.root.join("dist")).to_h
    assert_equal(false, config.dig("TemplateLength", "enabled"))
  end

  def test_missing_file
    theme = make_theme
    config = ThemeCheck::Config.from_path(theme.root)
    assert_equal(ThemeCheck::Config.default, config.to_h)
  end

  def test_from_path_uses_empty_config_when_config_file_is_missing
    ThemeCheck::Config.expects(:new).with('theme/')
    ThemeCheck::Config.from_path('theme/')
  end

  def test_enabled_checks_excludes_disabled_checks
    config = ThemeCheck::Config.new(".", "MissingTemplate" => { "enabled" => false })
    refute(check_enabled?(config, ThemeCheck::MissingTemplate))
  end

  def test_root
    config = ThemeCheck::Config.new(".", "root" => "dist")
    assert_equal(Pathname.new("dist"), config.root)
  end

  def test_empty_file
    theme = make_theme(".theme-check.yml" => "")
    config = ThemeCheck::Config.from_path(theme.root)
    assert_equal(ThemeCheck::Config.default, config.to_h)
  end

  def test_root_from_config
    theme = make_theme(
      ".theme-check.yml" => <<~END,
        root: dist
      END
      "dist/templates/index.liquid" => "",
    )
    config = ThemeCheck::Config.from_path(theme.root)
    assert_equal(theme.root.join("dist"), config.root)
  end

  def test_picks_nearest_config
    theme = make_theme(
      ".theme-check.yml" => <<~END,
        TemplateLength:
          enabled: false
      END
      "src/.theme-check.yml" => <<~END,
        TemplateLength:
          enabled: true
      END
    )
    config = ThemeCheck::Config.from_path(theme.root.join("src"))
    assert_equal(theme.root.join("src"), config.root)
    assert(check_enabled?(config, ThemeCheck::TemplateLength))
  end

  def test_respects_provided_root
    config = ThemeCheck::Config.from_path(__dir__)
    assert_equal(Pathname.new(__dir__), config.root)
  end

  def test_enabled_checks_returns_default_checks_for_empty_config
    mock_default_config("SyntaxError" => { "enabled" => true })
    config = ThemeCheck::Config.new(".")
    assert(check_enabled?(config, ThemeCheck::SyntaxError))
  end

  def test_warn_about_unknown_config
    mock_default_config("SyntaxError" => { "enabled" => true })
    ThemeCheck::Config.any_instance
      .expects(:warn).with("unknown configuration: unknown")
    ThemeCheck::Config.any_instance
      .expects(:warn).with("unknown configuration: SyntaxError.unknown")
    ThemeCheck::Config.new(".",
      "unknown" => ".",
      "SyntaxError" => { "unknown" => false },
      "CustomCheck" => { "unknown" => false },)
  end

  def test_warn_about_type_mismatch
    mock_default_config(
      "root" => ".",
      "SyntaxError" => { "enabled" => true },
      "TemplateLength" => { "enabled" => true },
    )
    ThemeCheck::Config.any_instance
      .expects(:warn).with("bad configuration type for root: expected a String, got []")
    ThemeCheck::Config.any_instance
      .expects(:warn).with("bad configuration type for SyntaxError.enabled: expected true or false, got nil")
    ThemeCheck::Config.any_instance
      .expects(:warn).with("bad configuration type for TemplateLength: expected a Hash, got true")
    ThemeCheck::Config.new(".",
      "root" => [],
      "SyntaxError" => { "enabled" => nil },
      "TemplateLength" => true,)
  end

  def test_merge_with_default_config
    mock_default_config(
      "root": ".",
      "ignore": [
        "node_modules",
      ],
      "SyntaxError" => {
        "enabled" => true,
        "muffin_mode" => "enabled",
      },
      "EmptyCheck" => {
        "enabled" => true,
      },
      "OtherCheck" => {
        "enabled" => true,
      },
    )
    config = ThemeCheck::Config.new(".",
      "ignore": [
        "some_dir",
      ],
      "SyntaxError" => {
        "muffin_mode" => "maybe",
      },
      "EmptyCheck" => {},)
    assert_equal({
      "ignore": [
        "some_dir",
      ],
      "SyntaxError" => {
        "enabled" => true,
        "muffin_mode" => "maybe",
      },
      "EmptyCheck" => {
        "enabled" => true,
      },
      "OtherCheck" => {
        "enabled" => true,
      },
      "root": ".",
    }, config.to_h)
  end

  def test_custom_check
    theme = make_theme(
      ".theme-check.yml" => <<~END,
        require:
          - ./checks/custom_check.rb
        CustomCheck:
          enabled: true
      END
      "checks/custom_check.rb" => <<~END,
        module ThemeCheck
          class CustomCheck < Check
          end
        end
      END
    )
    config = ThemeCheck::Config.from_path(theme.root)
    assert(check_enabled?(config, ThemeCheck::CustomCheck))
  end

  def test_only_category
    config = ThemeCheck::Config.new(".")
    config.only_categories = [:liquid]
    assert(config.enabled_checks.any?)
    assert(config.enabled_checks.all? { |c| c.category == :liquid })
  end

  def test_exclude_category
    config = ThemeCheck::Config.new(".")
    config.exclude_categories = [:liquid]
    assert(config.enabled_checks.any?)
    assert(config.enabled_checks.none? { |c| c.category == :liquid })
  end

  def test_ignore
    theme = make_theme(
      ".theme-check.yml" => <<~END,
        ignore:
          - node_modules
          - dist/*.json
      END
    )
    config = ThemeCheck::Config.from_path(theme.root)
    assert_equal(["node_modules", "dist/*.json"], config.ignored_patterns)
  end

  private

  def check_enabled?(config, klass)
    config.enabled_checks.map(&:class).include?(klass)
  end

  def mock_default_config(config)
    ThemeCheck::Config.stubs(:default).returns(config)
  end
end
