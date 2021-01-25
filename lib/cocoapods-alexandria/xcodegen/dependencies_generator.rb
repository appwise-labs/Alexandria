require 'yaml'

module PodAlexandria
  class XcodeGen
    # Generate the project dependencies file, adding frameworks to the right targets
    # and also checking if they are linked dynamically or not.
    def self.generate_dependencies(installer_context, outputFile, configurations)
      targets = installer_context.umbrella_targets.map { |target|
        generate_for_target(installer_context, target, configurations)
      }.to_h

      File.open(outputFile, 'w') { |file|
        YAML::dump({ 'targets' => targets }, file)
      }
    end

    private

    def self.generate_for_target(installer_context, target, configurations)
      target_name = target.cocoapods_target_label.sub(/^Pods-/, '')
      xcconfig = config_file_for_target(installer_context, target)

      [
        target_name,
        {
          'configFiles' => configurations,
          'dependencies' => get_dependencies_from_xcconfig(xcconfig).map { |dependency|
            if dependency.exists?
              { 'framework' => dependency.path, 'embed' => dependency.is_dynamic? }
            else
              { 'sdk' => dependency.sdk }
            end
          }
        }
      ]
    end

    def self.config_file_for_target(installer_context, target)
      Dir["#{installer_context.sandbox_root}/Target Support Files/#{target.cocoapods_target_label}/#{target.cocoapods_target_label}.*.xcconfig"]
        .first
    end

    def self.get_dependencies_from_xcconfig(file)
      File.readlines(file).select { |line| line.start_with?('OTHER_LDFLAGS') }.first
        .split('=')[1].tr('"', '') # get value (and remove quotes)
        .gsub('-framework', '').gsub('-ObjC', '') # remove unneeded flags
        .split.drop(1) # remove inherited
        .map { |d| Dependency.new(d) }
    end
  end
end
