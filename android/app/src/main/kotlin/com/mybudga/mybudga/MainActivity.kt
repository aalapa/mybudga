package com.mybudga.mybudga

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private var eventSink: EventChannel.EventSink? = null
    private var smsReceiver: BroadcastReceiver?    = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mybudga/sms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePending" -> {
                        val prefs = getSharedPreferences(SmsReceiver.PREFS_NAME, Context.MODE_PRIVATE)
                        val json  = prefs.getString(SmsReceiver.KEY_PENDING, "[]") ?: "[]"
                        prefs.edit().putString(SmsReceiver.KEY_PENDING, "[]").apply()
                        result.success(json)
                    }
                    "getInitialRoute" -> {
                        val route = intent.getStringExtra("route")
                        intent.removeExtra("route")
                        result.success(route)
                    }
                    "setSmsEnabled" -> {
                        val enabled = call.arguments as Boolean
                        getSharedPreferences(SmsReceiver.PREFS_NAME, Context.MODE_PRIVATE)
                            .edit().putBoolean(SmsReceiver.KEY_SMS_ENABLED, enabled).apply()
                        result.success(null)
                    }
                    "isSmsEnabled" -> {
                        val enabled = getSharedPreferences(SmsReceiver.PREFS_NAME, Context.MODE_PRIVATE)
                            .getBoolean(SmsReceiver.KEY_SMS_ENABLED, false)
                        result.success(enabled)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "mybudga/sms_stream")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    eventSink = sink
                    smsReceiver = object : BroadcastReceiver() {
                        override fun onReceive(ctx: Context, intent: Intent) {
                            val body   = intent.getStringExtra("body")   ?: return
                            val sender = intent.getStringExtra("sender") ?: ""
                            sink.success(mapOf("body" to body, "sender" to sender))
                        }
                    }
                    val filter = IntentFilter(SmsReceiver.ACTION_NEW_SMS)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(smsReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        @Suppress("UnspecifiedRegisterReceiverFlag")
                        registerReceiver(smsReceiver, filter)
                    }
                }

                override fun onCancel(args: Any?) {
                    smsReceiver?.let { unregisterReceiver(it) }
                    smsReceiver = null
                    eventSink   = null
                }
            })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
}
