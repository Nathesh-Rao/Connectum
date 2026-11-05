package com.agile.connectum

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "connectum/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "model" -> result.success(Build.MODEL)
                    "appVersion" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        val build = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
                        result.success("${info.versionName} ($build)")
                    }
                    "installReferrer" -> readInstallReferrer(result)
                    "openSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // One read per call: {status, referrer?}. Status is the client's answer.
    private fun readInstallReferrer(result: MethodChannel.Result) {
        var isDone = false
        fun finish(status: String, referrer: String? = null) {
            if (isDone) return
            isDone = true
            result.success(mapOf("status" to status, "referrer" to referrer))
        }
        val client = try {
            InstallReferrerClient.newBuilder(this).build()
        } catch (e: Exception) {
            finish("error")
            return
        }
        try {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(code: Int) {
                    when (code) {
                        InstallReferrerClient.InstallReferrerResponse.OK -> try {
                            finish("ok", client.installReferrer.installReferrer)
                        } catch (e: Exception) {
                            finish("error")
                        }
                        InstallReferrerClient.InstallReferrerResponse.FEATURE_NOT_SUPPORTED -> finish("unsupported")
                        InstallReferrerClient.InstallReferrerResponse.SERVICE_UNAVAILABLE -> finish("unavailable")
                        InstallReferrerClient.InstallReferrerResponse.DEVELOPER_ERROR -> finish("developer_error")
                        else -> finish("error")
                    }
                    try { client.endConnection() } catch (e: Exception) {}
                }

                override fun onInstallReferrerServiceDisconnected() = finish("disconnected")
            })
        } catch (e: Exception) {
            finish("error")
        }
    }
}
