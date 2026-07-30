package com.raynlabs.app

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Owns the 32-byte per-install key that seals `configs/<id>.enc`.
 *
 * The data key is wrapped by an AES key held in AndroidKeyStore (hardware-backed
 * where the device offers it, and non-exportable either way), and only the
 * wrapped blob is written to SharedPreferences. The `:bg` VPN service process
 * needs the same key to start a tunnel from the quick-settings tile with no
 * Flutter engine alive, which is why this lives in Kotlin rather than inside
 * `flutter_secure_storage` — reaching into that plugin's own
 * EncryptedSharedPreferences from another process would couple us to its
 * internals across plugin upgrades.
 *
 * Creation happens only in [getOrCreate], which is reached exclusively from the
 * main process over the `com.raynlabs.app/platform` channel. `:bg` calls [peek],
 * which never creates — otherwise a background start could race the app into
 * generating a second key and orphan every config already on disk.
 *
 * The key is expendable by design: AndroidKeyStore entries do not survive a
 * restore to a new device and some OEMs invalidate them when the lock screen
 * changes. Losing it means every `.enc` becomes unreadable, and the recovery is
 * simply to discard them and re-fetch the subscription.
 */
object ConfigKey {
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val KEK_ALIAS = "rayn_config_kek"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_TAG_BITS = 128
    private const val KEY_LENGTH = 32

    private val preferences by lazy {
        Application.application.applicationContext
            .getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
    }

    /**
     * Returns the data key, generating and persisting one on first call.
     * Main process only.
     */
    @Synchronized
    fun getOrCreate(): ByteArray {
        peek()?.let { return it }
        val dataKey = ByteArray(KEY_LENGTH).also { java.security.SecureRandom().nextBytes(it) }
        store(dataKey)
        return dataKey
    }

    /**
     * Returns the data key, or null if it has not been created yet or the
     * AndroidKeyStore entry is gone. Never creates. Safe to call from `:bg`.
     *
     * Note on cross-process reads: SharedPreferences is not multi-process-safe
     * in general, but the wrapped blob is written once by the main process
     * before any profile can exist, and `:bg` loads preferences fresh when the
     * service starts — so it observes the value. A null here is handled by the
     * caller as "cannot start", not by generating a replacement.
     */
    @Synchronized
    fun peek(): ByteArray? {
        val stored = preferences.getString(SettingsKeyConfigKey, null) ?: return null
        return try {
            val blob = Base64.decode(stored, Base64.NO_WRAP)
            if (blob.size <= GCM_IV_LENGTH) return null
            val kek = loadKek() ?: return null
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                kek,
                GCMParameterSpec(GCM_TAG_BITS, blob, 0, GCM_IV_LENGTH)
            )
            val key = cipher.doFinal(blob, GCM_IV_LENGTH, blob.size - GCM_IV_LENGTH)
            if (key.size == KEY_LENGTH) key else null
        } catch (e: Exception) {
            // Keystore wiped, entry invalidated by a lock-screen change, or the
            // blob is corrupt. Never log the exception body.
            android.util.Log.w(TAG, "config key unwrap failed: ${e.javaClass.simpleName}")
            null
        }
    }

    private fun store(dataKey: ByteArray) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, createKek())
        val iv = cipher.iv
        require(iv.size == GCM_IV_LENGTH) { "unexpected GCM IV length ${iv.size}" }
        val wrapped = cipher.doFinal(dataKey)
        val blob = ByteArray(iv.size + wrapped.size)
        System.arraycopy(iv, 0, blob, 0, iv.size)
        System.arraycopy(wrapped, 0, blob, iv.size, wrapped.size)
        preferences.edit()
            .putString(SettingsKeyConfigKey, Base64.encodeToString(blob, Base64.NO_WRAP))
            .commit() // commit, not apply: :bg may read this very soon after.
    }

    private fun loadKek(): SecretKey? {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        return keyStore.getKey(KEK_ALIAS, null) as? SecretKey
    }

    private fun createKek(): SecretKey {
        loadKek()?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEK_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                // No user authentication: the VPN service must be able to start
                // from the quick-settings tile on a locked device.
                .setUserAuthenticationRequired(false)
                .build()
        )
        return generator.generateKey()
    }

    private const val TAG = "A/ConfigKey"
    private const val GCM_IV_LENGTH = 12
    private const val SettingsKeyConfigKey = "wrapped_config_key"
}
