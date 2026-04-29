package com.mybudga.mybudga

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject

class SmsReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_NEW_SMS = "com.mybudga.mybudga.NEW_BANK_SMS"
        const val PREFS_NAME      = "mybudga_sms_prefs"
        const val KEY_PENDING     = "pending_sms"
        const val KEY_SMS_ENABLED = "sms_enabled"
        private const val CHANNEL_ID = "sms_transactions"

        private val BANK_SENDERS = listOf(
            "HDFCBK", "ICICIB", "SBIINB", "AXISBK", "KOTAKB", "YESBNK",
            "PNBSMS", "BOIIND", "CANBNK", "UNIONB", "INDBNK", "IDBIBK",
            "SCBLNK", "CITIBK", "RBLBNK", "FEDBK", "KVBSMS", "DCBBNK",
            "AUSFIN", "HSBCIN", "STANC",  "INDUSB", "TMBLBK", "DBSBNK",
            "PAYTMB", "JUPBNK",
        )

        fun isBankSender(sender: String): Boolean =
            BANK_SENDERS.any { sender.uppercase().contains(it) }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_SMS_ENABLED, false)) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        for (msg in messages) {
            val sender = msg.originatingAddress ?: continue
            val body   = msg.messageBody       ?: continue
            if (!isBankSender(sender)) continue

            savePending(context, sender, body)
            showNotification(context, body)

            // Notify foreground activity via local broadcast
            context.sendBroadcast(Intent(ACTION_NEW_SMS).apply {
                putExtra("body",   body)
                putExtra("sender", sender)
            })
        }
    }

    private fun savePending(context: Context, sender: String, body: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val arr   = JSONArray(prefs.getString(KEY_PENDING, "[]") ?: "[]")
        arr.put(JSONObject().apply {
            put("sender", sender)
            put("body",   body)
        })
        prefs.edit().putString(KEY_PENDING, arr.toString()).apply()
    }

    private fun showNotification(context: Context, body: String) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "SMS Transactions",
                    NotificationManager.IMPORTANCE_HIGH,
                )
            )
        }

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("route", "/transactions")
        }
        val pi = PendingIntent.getActivity(
            context, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notif = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Bank transaction detected")
            .setContentText("Tap to add to MyBudga")
            .setAutoCancel(true)
            .setContentIntent(pi)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        nm.notify(body.hashCode() and 0x7FFFFFFF, notif)
    }
}
