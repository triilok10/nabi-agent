package com.trilok.nabi.nabi_agent

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.trilok.nabi/app_intents"
        private const val INSTAGRAM_PACKAGE = "com.instagram.android"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAndroidSdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "launchApp" -> {
                        val packageName = call.argument<String>("packageName")
                        if (packageName != INSTAGRAM_PACKAGE) {
                            result.error(
                                "unsupported_app",
                                "This app is not in Nabi's local launch allowlist.",
                                null,
                            )
                            return@setMethodCallHandler
                        }

                        val launchIntent =
                            packageManager.getLaunchIntentForPackage(INSTAGRAM_PACKAGE)
                        if (launchIntent == null) {
                            result.error(
                                "app_not_installed",
                                "The requested app is not installed.",
                                null,
                            )
                            return@setMethodCallHandler
                        }

                        try {
                            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(launchIntent)
                            result.success(null)
                        } catch (error: ActivityNotFoundException) {
                            result.error(
                                "app_not_launchable",
                                "The requested app has no launchable activity.",
                                error.message,
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
