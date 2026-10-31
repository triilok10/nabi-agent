package com.trilok.nabi.nabi_agent

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.nabi.agent/system_actions"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAndroidSdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "executeAction" -> {
                        val arguments = call.arguments as? Map<*, *>
                        val action = arguments?.get("action") as? String
                        val target = arguments?.get("target") as? String
                        val params = arguments?.get("params") as? Map<*, *>
                        if (action == null || target == null || params == null) {
                            result.error(
                                "invalid_arguments",
                                "An action, target, and params object are required.",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            val message = when (action) {
                                "launch_app" -> launchInstalledApp(params)
                                "toggle_torch" -> toggleTorch(params)
                                "open_camera" -> openCamera(params)
                                "open_settings" -> openSettings(params)
                                else -> throw ActionException(
                                    "unsupported_action",
                                    "The requested action is not supported.",
                                )
                            }
                            result.success(mapOf("status" to "success", "message" to message))
                        } catch (error: ActionException) {
                            result.error(error.code, error.message, null)
                        } catch (error: SecurityException) {
                            result.error(
                                "camera_permission_required",
                                "Grant camera permission before using the flashlight.",
                                null,
                            )
                        } catch (error: ActivityNotFoundException) {
                            result.error(
                                "action_not_available",
                                "No application can handle this action.",
                                null,
                            )
                        } catch (error: Exception) {
                            result.error(
                                "action_failed",
                                error.message ?: "The system action failed.",
                                null,
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun launchInstalledApp(params: Map<*, *>): String {
        val requestedName = (params["name"] as? String)?.trim()
        if (requestedName.isNullOrEmpty()) {
            throw ActionException("invalid_arguments", "An app name is required.")
        }
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val matches = packageManager.queryIntentActivities(launcherIntent, 0)
            .mapNotNull { resolveInfo ->
                val label = resolveInfo.loadLabel(packageManager).toString().trim()
                if (label.equals(requestedName, ignoreCase = true)) {
                    resolveInfo.activityInfo.packageName to label
                } else {
                    null
                }
            }
            .distinctBy { it.first }
        if (matches.isEmpty()) {
            throw ActionException("app_not_found", "No installed app has that exact name.")
        }
        if (matches.size > 1) {
            throw ActionException("ambiguous_app", "Several installed apps share that name.")
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(matches.single().first)
            ?: throw ActionException("app_not_found", "That app has no launch activity.")
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(launchIntent)
        return "Opened ${matches.single().second}."
    }

    private fun toggleTorch(params: Map<*, *>): String {
        val state = params["state"] as? String
        if (state != "on" && state != "off") {
            throw ActionException("invalid_arguments", "Torch state must be on or off.")
        }
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            throw ActionException(
                "camera_permission_required",
                "Camera permission is needed to control the flashlight.",
            )
        }
        val cameraManager = getSystemService(CAMERA_SERVICE) as CameraManager
        val cameraId = cameraManager.cameraIdList.firstOrNull { id ->
            cameraManager.getCameraCharacteristics(id)
                .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        } ?: throw ActionException("action_not_available", "No flashlight is available.")
        cameraManager.setTorchMode(cameraId, state == "on")
        return if (state == "on") "Flashlight turned on." else "Flashlight turned off."
    }

    private fun openCamera(params: Map<*, *>): String {
        val intent = Intent("android.media.action.IMAGE_CAPTURE")
        if (params["mode"] == "selfie") {
            intent.putExtra("android.intent.extras.CAMERA_FACING", 1)
            intent.putExtra("android.intent.extras.LENS_FACING_FRONT", 1)
        }
        if (intent.resolveActivity(packageManager) == null) {
            throw ActionException("action_not_available", "No camera app is available.")
        }
        startActivity(intent)
        return "Opened the camera. Review and capture using the camera app."
    }

    private fun openSettings(params: Map<*, *>): String {
        val section = params["section"] as? String
        val intent = when (section) {
            "system" -> Intent(Settings.ACTION_SETTINGS)
            "notifications" -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
            "app" -> Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", packageName, null),
            )
            else -> throw ActionException("invalid_arguments", "Unsupported settings section.")
        }
        startActivity(intent)
        return "Opened $section settings."
    }

    private class ActionException(val code: String, message: String) : Exception(message)
}
