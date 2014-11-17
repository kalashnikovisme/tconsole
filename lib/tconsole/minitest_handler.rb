# -*- coding: utf-8 -*-
require 'minitest'
module TConsole
  class MiniTestHandler
    def self.setup(config)
      @reporter = ::TConsole::MinitestReporter.new
      @reporter.tc_results.suite_counts = config.cached_suite_counts
      @reporter.tc_results.elements = config.cached_elements
    end

    def self.match_and_run(match_patterns, config)

      suites = Minitest::Runnable.runnables

      suites.each do |suite|
        suite_id = @reporter.tc_results.elements[suite.to_s]

        suite_printed = false
        suite.methods_matching(/^test/).map do |method|
          id = @reporter.tc_results.add_element(suite, method)

          unless match_patterns.nil?
            match = match_patterns.find do |pattern|
              pattern == suite.to_s ||
                pattern == "#{suite.to_s}##{method.to_s}" ||
                pattern == suite_id.to_s ||
                pattern == id
            end
          end

          if !suite_printed && (match_patterns.nil? || match_patterns.empty? || !match.nil?)
            print(::Term::ANSIColor.cyan, suite, ::Term::ANSIColor.reset,
                  ::Term::ANSIColor.magenta, " #{suite_id} \n")
            suite_printed = true
          end

          if match_patterns.nil? || match_patterns.empty? || !match.nil?
            @reporter.current_element_id = id
            # TODO мб понтово свой метод run в минитест захуярить,
            # который список suites принимать будет
            Minitest::Runnable.run_one_method(suite, method, @reporter)
          end
        end

        if suite_printed
          puts
        end
      end

      @reporter.tc_results
    end

    # Preloads our element cache for autocompletion. Assumes tests are already loaded
    def self.preload_elements
      patch_minitest
      results = TConsole::TestResult.new
      suites = Minitest::Runnable.runnables
      suites.each do |suite|
        suite.methods_matching(/^test/).map do |method|
          id = results.add_element(suite, method)
        end
      end

      results
    end

    # We're basically breaking Minitest autorun here, since we want to manually run our
    # tests and Rails relies on autorun
    # A big reason for the need for this is that we're trying to work in the Rake environment
    # rather than rebuilding all of the code in Rake just to get test prep happening
    # correctly.
    def self.patch_minitest
      Minitest.class_eval do
        class << self
          alias_method :old_run, :run
          def run(args = [])
          end
        end
      end
      return assertions.select { |n| !n.nil? }.size, assertions.inject(0) { |sum, n| n.nil? ? sum + 0 : sum + n }
    end

    def puke(klass, meth, e)
      id = results.elements["#{klass}##{meth}"]

      e = case e
          when MiniTest::Skip then
            @skips += 1
            results.skip_count += 1
            ["S", COLOR_MAP["S"] + "Skipped:\n#{klass}##{meth} (#{id})" + ::Termin::ANSIColor.reset + " [#{location e}]:\n#{e.message}\n"]
          when MiniTest::Assertion then
            @failures += 1
            results.failure_count += 1
            ["F", COLOR_MAP["F"] + "Failure:\n#{klass}##{meth} (#{id})" + ::Termin::ANSIColor.reset + " [#{location e}]:\n#{e.message}\n"]
          else
            @errors += 1
            results.error_count += 1

            filtered_backtrace = Util.filter_backtrace(e.backtrace)
            backtrace_text = MiniTest::filter_backtrace(filtered_backtrace).join "\n    "

            ["E", COLOR_MAP["E"] + "Error:\n#{klass}##{meth} (#{id}):\n" + ::Termin::ANSIColor.reset + "#{e.class}: #{e.message}\n    #{backtrace_text}\n"]
          end
      @report << e[1]
      e[0]
    end
  end
end

# Make sure that output is only colored when it should be
Termin::ANSIColor::coloring = STDOUT.isatty
