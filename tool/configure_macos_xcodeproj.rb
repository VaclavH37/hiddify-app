#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Applies the macOS port's Phase 3 changes to macos/Runner.xcodeproj.
#
#   ruby tool/configure_macos_xcodeproj.rb          # from the repo root, on the Mac
#
# Why a script: the project file cannot be edited or checked on the Windows dev
# machine, and a hand-edited project.pbxproj fails in ways Xcode reports poorly.
# This uses the xcodeproj gem, which CocoaPods is built on, so the result is what
# Xcode itself would write. Review it in Xcode afterwards (MACOS_PHASE3_TASKS.md §6).
#
# Idempotent: every step checks before it adds, so a second run changes nothing
# and a run after a partial failure finishes the job.
#
# What it does:
#   Runner      - drops the upstream hiddify-core.dylib; product "Rayn VPN.app";
#                 manual signing (Apple Development / mac.dev.* for Debug and
#                 Profile, Apple Distribution / mac.dist.* for Release); links
#                 RaynCore.xcframework + NetworkExtension; compiles the Swift
#                 shared with iOS in place from ../ios; embeds RaynTunnel.appex.
#   RaynTunnel  - new packet-tunnel app extension, sources from ../ios/RaynTunnel
#                 and ../ios/Shared, never linking Flutter or any pod.
#   everywhere  - macOS 12.0 deployment target; Hiddify names removed; the
#                 LaunchAtLogin package pinned to the revision already resolved.

begin
  require 'xcodeproj'
rescue LoadError
  abort <<~MSG
    The xcodeproj gem is not available to this Ruby. It ships with CocoaPods; if
    `pod --version` works but this does not, install it for your user:
      gem install --user-install xcodeproj
  MSG
end
require 'pathname'

REPO = Pathname.new(File.expand_path('..', __dir__))
PROJECT_PATH = REPO.join('macos', 'Runner.xcodeproj')
abort "not found: #{PROJECT_PATH} (run from the repo root)" unless PROJECT_PATH.exist?

TEAM = 'RPD5KQ8YA7'
DEPLOYMENT_TARGET = '12.0'
APP_NAME = 'Rayn VPN'
LAUNCH_AT_LOGIN_REVISION = '9a894d799269cb591037f9f9cb0961510d4dca81'

# Swift compiled in place from ios/. Paths are relative to macos/ (SOURCE_ROOT).
SHARED_CORE = %w[
  ../ios/Shared/FilePath.swift
  ../ios/Shared/ConfigCipher.swift
  ../ios/Shared/ConfigKey.swift
  ../ios/Shared/GrpcSecret.swift
].freeze

RUNNER_SHARED = (SHARED_CORE + %w[
  ../ios/Runner/Handlers/MethodHandler.swift
  ../ios/Runner/Handlers/PlatformMethodHandler.swift
  ../ios/Runner/Handlers/StatusEventHandler.swift
  ../ios/Runner/Handlers/AlertsEventHandler.swift
  ../ios/Runner/VPN/VPNManager.swift
  ../ios/Runner/VPN/VPNConfig.swift
  ../ios/Runner/VPN/Helpers/Stored.swift
  ../ios/Runner/Extensions/Bundle+Properties.swift
  ../ios/Runner/Billing/RaynBilling.g.swift
  ../ios/Runner/Billing/RaynBillingHandler.swift
]).freeze

# Exactly the iOS RaynTunnel target's sources.
TUNNEL_SOURCES = (SHARED_CORE + %w[
  ../ios/RaynTunnel/PacketTunnelProvider.swift
  ../ios/RaynTunnel/Logger.swift
  ../ios/RaynTunnel/Core/ExtensionProvider.swift
  ../ios/RaynTunnel/Core/ExtensionPlatformInterface.swift
  ../ios/RaynTunnel/Core/Extension+RunBlocking.swift
]).freeze

missing = (RUNNER_SHARED + TUNNEL_SOURCES + %w[
  ../ios/Runner/PrivacyInfo.xcprivacy
  ../ios/RaynTunnel/PrivacyInfo.xcprivacy
  RaynTunnel/Info.plist
  RaynTunnel/RaynTunnel.entitlements
  RaynTunnel/RaynTunnel.xcconfig
  Runner/Configs/Rayn.xcconfig
]).uniq.reject { |p| REPO.join('macos', p).exist? }
abort "missing files (pull first?):\n  #{missing.join("\n  ")}" unless missing.empty?

project = Xcodeproj::Project.open(PROJECT_PATH.to_s)
MACOS_DIR = Pathname.new(project.project_dir.to_s)

def log(msg)
  puts "  - #{msg}"
end

def target_named(project, name)
  project.targets.find { |t| t.name == name }
end

# A file reference with sourceTree SOURCE_ROOT (macos/), reused if one already
# points at the same file. Built by hand rather than with group.new_reference,
# so the stored path is exactly the one written here and never re-derived from
# the group hierarchy.
def file_ref(project, group, relative, file_type: nil)
  wanted = MACOS_DIR.join(relative).cleanpath
  existing = project.files.find do |f|
    f.source_tree == 'SOURCE_ROOT' && MACOS_DIR.join(f.path.to_s).cleanpath == wanted
  end
  return existing if existing

  ref = project.new(Xcodeproj::Project::Object::PBXFileReference)
  ref.path = relative
  ref.name = File.basename(relative)
  ref.source_tree = 'SOURCE_ROOT'
  if file_type
    ref.last_known_file_type = file_type
  else
    ref.set_last_known_file_type
  end
  group.children << ref
  ref
end

def add_to_phase(phase, ref)
  phase.add_file_reference(ref, true)
end

runner = target_named(project, 'Runner') or abort 'no Runner target'
tests = target_named(project, 'RunnerTests')

puts "Configuring #{PROJECT_PATH.relative_path_from(REPO)}"

# --- Upstream leftovers -------------------------------------------------------

project.files.select { |f| f.path.to_s.end_with?('hiddify-core.dylib') }.each do |ref|
  ref.build_files.each(&:remove_from_project)
  ref.remove_from_project
  log 'removed hiddify-core.dylib (the FFI core is retired on macOS)'
end

if runner.product_reference.path != "#{APP_NAME}.app"
  runner.product_reference.path = "#{APP_NAME}.app"
  log "product reference -> #{APP_NAME}.app"
end

# --- Project-level settings ---------------------------------------------------

project.build_configurations.each do |config|
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
end
log "project deployment target #{DEPLOYMENT_TARGET}"

target_attributes = (project.root_object.attributes['TargetAttributes'] ||= {})

# --- Groups and shared references ---------------------------------------------

shared_group = project.main_group.find_subpath('Shared with iOS', true)
tunnel_group = project.main_group.find_subpath('RaynTunnel', true)
frameworks_group = project.frameworks_group
configs_group = project.main_group.find_subpath('Runner/Configs', false) || project.main_group

rayn_xcconfig = file_ref(project, configs_group, 'Runner/Configs/Rayn.xcconfig')
raycore = file_ref(project, frameworks_group, 'Frameworks/RaynCore.xcframework',
                   file_type: 'wrapper.xcframework')

# SDKROOT-relative, which is how Xcode itself records a system framework: it
# resolves against whichever SDK the build uses. (xcodeproj's own
# add_system_framework writes a path naming one specific SDK version.)
def network_extension_ref(project)
  existing = project.files.find do |f|
    f.source_tree == 'SDKROOT' && f.path.to_s == 'System/Library/Frameworks/NetworkExtension.framework'
  end
  return existing if existing

  ref = project.new(Xcodeproj::Project::Object::PBXFileReference)
  ref.path = 'System/Library/Frameworks/NetworkExtension.framework'
  ref.name = 'NetworkExtension.framework'
  ref.source_tree = 'SDKROOT'
  ref.last_known_file_type = 'wrapper.framework'
  project.frameworks_group.children << ref
  ref
end
network_extension = network_extension_ref(project)

# --- Runner -------------------------------------------------------------------

runner.build_configurations.each do |config|
  s = config.build_settings
  distribution = config.name == 'Release'
  s.delete('INFOPLIST_KEY_CFBundleDisplayName') # "Hiddify"; the name comes from PRODUCT_NAME
  s['MACOSX_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  s['DEVELOPMENT_TEAM'] = TEAM
  s['CODE_SIGN_STYLE'] = 'Manual'
  s['CODE_SIGN_IDENTITY'] = distribution ? 'Apple Distribution' : 'Apple Development'
  s['PROVISIONING_PROFILE_SPECIFIER'] = distribution ? 'mac.dist.com.raynlabs.app' : 'mac.dev.com.raynlabs.app'
  # -lresolv as on iOS: the Go core's resolver calls into libresolv.
  s['OTHER_LDFLAGS'] = ['$(inherited)', '-lresolv']
end
log 'Runner: manual signing, macOS 12.0, -lresolv'

runner_attrs = (target_attributes[runner.uuid] ||= {})
runner_attrs.delete('SystemCapabilities') # claimed a sandbox the entitlements then disabled
runner_attrs['ProvisioningStyle'] = 'Manual'
runner_attrs['DevelopmentTeam'] = TEAM

RUNNER_SHARED.each { |path| add_to_phase(runner.source_build_phase, file_ref(project, shared_group, path)) }
log "Runner: #{RUNNER_SHARED.size} shared Swift files"

runner_privacy = file_ref(project, shared_group, '../ios/Runner/PrivacyInfo.xcprivacy', file_type: 'text.xml')
add_to_phase(runner.resources_build_phase, runner_privacy)

add_to_phase(runner.frameworks_build_phase, raycore)
add_to_phase(runner.frameworks_build_phase, network_extension)
log 'Runner: links RaynCore.xcframework (static) and NetworkExtension'

# --- RaynTunnel ---------------------------------------------------------------

tunnel = target_named(project, 'RaynTunnel')
unless tunnel
  tunnel = project.new_target(:app_extension, 'RaynTunnel', :osx, DEPLOYMENT_TARGET, nil, :swift)
  # new_target links Cocoa through a path that names one specific SDK version
  # (…/MacOSX<n>.sdk/…), which need not exist under the Xcode that builds this.
  # The extension imports Foundation and NetworkExtension only; drop it.
  tunnel.frameworks_build_phase.files.select { |bf| bf.display_name == 'Cocoa.framework' }.each do |bf|
    ref = bf.file_ref
    bf.remove_from_project
    ref.remove_from_project if ref && ref.build_files.empty?
  end
  log 'created the RaynTunnel app-extension target'
end
tunnel.add_build_configuration('Profile', :release) unless tunnel.build_configurations.any? { |c| c.name == 'Profile' }

tunnel_xcconfig = file_ref(project, tunnel_group, 'RaynTunnel/RaynTunnel.xcconfig')
file_ref(project, tunnel_group, 'RaynTunnel/Info.plist')
file_ref(project, tunnel_group, 'RaynTunnel/RaynTunnel.entitlements')

tunnel.build_configurations.each do |config|
  s = config.build_settings
  distribution = config.name == 'Release'
  config.base_configuration_reference = tunnel_xcconfig
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = '$(BASE_BUNDLE_IDENTIFIER).RaynTunnel'
  s['INFOPLIST_FILE'] = 'RaynTunnel/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'YES'
  s['INFOPLIST_KEY_CFBundleDisplayName'] = 'Rayn VPN Tunnel'
  s['INFOPLIST_KEY_NSHumanReadableCopyright'] = ''
  s['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  s['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  s['CODE_SIGN_ENTITLEMENTS'] = 'RaynTunnel/RaynTunnel.entitlements'
  s['DEVELOPMENT_TEAM'] = TEAM
  s['CODE_SIGN_STYLE'] = 'Manual'
  s['CODE_SIGN_IDENTITY'] = distribution ? 'Apple Distribution' : 'Apple Development'
  s['PROVISIONING_PROFILE_SPECIFIER'] = distribution ? 'mac.dist.com.raynlabs.app.rayntunnel' : 'mac.dev.com.raynlabs.app.rayntunnel'
  s['MACOSX_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  s['SDKROOT'] = 'macosx'
  s['SWIFT_VERSION'] = '5.0'
  # Deliberately WITHOUT $(inherited). The project-level configurations include
  # the Pods-Runner settings (Configs/Debug.xcconfig -> Flutter/Flutter-Debug.xcconfig),
  # and inheriting their OTHER_LDFLAGS would link FlutterMacOS and every plugin
  # into an extension that must contain neither. The iOS extension does the same.
  s['OTHER_LDFLAGS'] = '-lresolv'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../Frameworks', '@executable_path/../../../../Frameworks']
  s['SKIP_INSTALL'] = 'YES'
  s['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = config.name == 'Debug' ? 'DEBUG $(inherited)' : '$(inherited)'
end

tunnel_attrs = (target_attributes[tunnel.uuid] ||= {})
tunnel_attrs['DevelopmentTeam'] = TEAM
tunnel_attrs['ProvisioningStyle'] = 'Manual'

TUNNEL_SOURCES.each { |path| add_to_phase(tunnel.source_build_phase, file_ref(project, shared_group, path)) }
tunnel_privacy = file_ref(project, shared_group, '../ios/RaynTunnel/PrivacyInfo.xcprivacy', file_type: 'text.xml')
add_to_phase(tunnel.resources_build_phase, tunnel_privacy)
add_to_phase(tunnel.frameworks_build_phase, raycore)
add_to_phase(tunnel.frameworks_build_phase, network_extension)
log "RaynTunnel: #{TUNNEL_SOURCES.size} sources, links RaynCore + NetworkExtension, no Flutter"

# Embed the extension in the app's Contents/PlugIns, before the first script
# phase: Flutter's embed script and the Pods scripts run after it, and Xcode
# reports a dependency cycle when an embed phase sits behind a script phase
# that declares no outputs.
embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
unless embed
  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins
  log 'Runner: added "Embed Foundation Extensions"'
end
unless embed.files_references.include?(tunnel.product_reference)
  build_file = embed.add_file_reference(tunnel.product_reference, true)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end
first_script = runner.build_phases.index do |p|
  p.is_a?(Xcodeproj::Project::Object::PBXShellScriptBuildPhase) && p.name != '[CP] Check Pods Manifest.lock'
end
embed_at = runner.build_phases.index(embed)
if first_script && embed_at > first_script
  runner.build_phases.move(embed, first_script)
end

runner.add_dependency(tunnel) unless runner.dependencies.any? { |d| d.target == tunnel }
log 'Runner: embeds RaynTunnel.appex and depends on it'

# --- Tests, package pin -------------------------------------------------------

if tests
  tests.build_configurations.each do |config|
    config.build_settings['TEST_HOST'] = "$(BUILT_PRODUCTS_DIR)/#{APP_NAME}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/#{APP_NAME}"
  end
  log 'RunnerTests: TEST_HOST points at the renamed app'
end

launch_at_login = project.root_object.package_references.find { |p| p.repositoryURL.to_s.include?('LaunchAtLogin') }
if launch_at_login
  # Was `branch = main`: every package resolution could move the login-item
  # helper, a component App Review looks at, to whatever upstream pushed last.
  launch_at_login.requirement = { 'kind' => 'revision', 'revision' => LAUNCH_AT_LOGIN_REVISION }
  log "LaunchAtLogin pinned to #{LAUNCH_AT_LOGIN_REVISION[0, 7]}"
end

project.save
puts 'Saved. Next: MACOS_PHASE3_TASKS.md §6 (pod install, review in Xcode, compile).'
