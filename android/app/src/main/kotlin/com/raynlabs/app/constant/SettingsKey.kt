package com.raynlabs.app.constant

object SettingsKey {
    private const val KEY_PREFIX = "flutter."

    const val SERVICE_MODE = "${KEY_PREFIX}service-mode"
    const val ACTIVE_CONFIG_PATH = "${KEY_PREFIX}active_config_path"
    const val ACTIVE_PROFILE_NAME = "${KEY_PREFIX}active_profile_name"

    const val DEBUG_MODE = "${KEY_PREFIX}debug_mode"
    const val DISABLE_MEMORY_LIMIT = "${KEY_PREFIX}disable_memory_limit"
    const val DYNAMIC_NOTIFICATION = "${KEY_PREFIX}dynamic_notification"
    const val SYSTEM_PROXY_ENABLED = "${KEY_PREFIX}system_proxy_enabled"

    // cache

    const val CONFIG_OPTIONS = "config_options_json"

    const val START_CORE_ON_STARTING_SERVICE = "${KEY_PREFIX}starting_core_on_starting_service"

    const val WORKING_DIR = "working_dir"
    const val BASE_DIR = "base_dir"
    const val TMP_DIR = "tmp_dir"

    const val GRPC_PORT = "grpc_port"
    const val GRPC_FLUTTER_PUBLIC_KEY = "grpc_flutter_public_key"
}