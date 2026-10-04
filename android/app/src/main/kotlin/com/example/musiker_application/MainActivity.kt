package com.example.musiker_application

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "marschpad/local_network")
			.setMethodCallHandler { call, result ->
				if (call.method == "openHotspotSettings" || call.method == "openWifiSettings") {
					try {
						val intent = Intent(
							if (call.method == "openWifiSettings") {
								Settings.ACTION_WIFI_SETTINGS
							} else {
								Settings.ACTION_TETHER_SETTINGS
							}
						)
						if (intent.resolveActivity(packageManager) == null) {
							intent.action = Settings.ACTION_WIRELESS_SETTINGS
						}
						startActivity(intent)
						result.success(null)
					} catch (error: Exception) {
						result.error("HOTSPOT_SETTINGS_ERROR", error.message, null)
					}
				} else {
					result.notImplemented()
				}
			}
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.signature")
			.setMethodCallHandler { call, result ->
				try {
					val packageInfo = if (call.method == "getInstalledSignature") {
						if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
							packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
						} else {
							@Suppress("DEPRECATION")
							packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
						}
					} else if (call.method == "getApkSignature") {
						val path = call.argument<String>("path")
						if (path == null) { result.error("NO_PATH", "Kein APK-Pfad angegeben", null); return@setMethodCallHandler }
						if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
							packageManager.getPackageArchiveInfo(path, PackageManager.GET_SIGNING_CERTIFICATES)
						} else {
							@Suppress("DEPRECATION")
							packageManager.getPackageArchiveInfo(path, PackageManager.GET_SIGNATURES)
						}
					} else { result.notImplemented(); return@setMethodCallHandler }

					if (packageInfo == null) { result.error("INVALID_APK", "APK konnte nicht gelesen werden", null); return@setMethodCallHandler }
					val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
						packageInfo.signingInfo?.apkContentsSigners
					} else {
						@Suppress("DEPRECATION")
						packageInfo.signatures
					}
					val signature = signatures?.firstOrNull()
					if (signature == null) { result.error("NO_SIGNATURE", "Keine Signatur gefunden", null); return@setMethodCallHandler }
					val hash = MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
						.joinToString(":") { "%02X".format(it) }
					if (call.method == "getInstalledSignature") result.success(hash)
					else result.success(mapOf("packageName" to packageInfo.packageName, "versionName" to packageInfo.versionName, "signature" to hash))
				} catch (error: Exception) {
					result.error("SIGNATURE_ERROR", error.message, null)
				}
			}
	}
}
