package com.echoloop.player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle

/**
 * 后台播放前台服务。
 *
 * 职责边界（刻意做窄）：
 * 本服务**不负责解码与播放**，播放始终由 Flutter 侧的 media_kit 完成。
 * 它只做两件事：
 * 1. 用前台服务 + 通知把进程优先级抬到「用户可感知」，避免锁屏后被系统回收；
 * 2. 承载锁屏 / 通知栏的媒体控制按钮，把动作通过 [actionListener] 回传给 Flutter。
 *
 * 这种「自行实现前台服务」的路线对应需求 §5 `media_kit` 的第二种方案，
 * 相比 audio_service 少一层播放器代理，状态源唯一，不容易出现双份状态不一致。
 */
class PlaybackService : Service() {

    companion object {
        const val ACTION_UPDATE = "com.echoloop.player.action.UPDATE"
        const val ACTION_STOP = "com.echoloop.player.action.STOP"
        const val ACTION_TOGGLE = "com.echoloop.player.action.TOGGLE"
        const val ACTION_PREV = "com.echoloop.player.action.PREV"
        const val ACTION_NEXT = "com.echoloop.player.action.NEXT"
        const val ACTION_SPEED = "com.echoloop.player.action.SPEED"

        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_PLAYING = "playing"
        const val EXTRA_SPEED = "speed"
        const val EXTRA_POSITION = "positionMs"
        const val EXTRA_DURATION = "durationMs"
        const val EXTRA_KEEP_AWAKE = "keepAwake"

        private const val CHANNEL_ID = "echoloop_playback"
        private const val NOTIFICATION_ID = 4610

        private const val REQUEST_PREV = 11
        private const val REQUEST_TOGGLE = 12
        private const val REQUEST_NEXT = 13
        private const val REQUEST_SPEED = 14

        /**
         * 通知栏动作回调。由 [NativeBridge] 在 Flutter 引擎就绪时注册，
         * 为空表示 Flutter 侧已不在监听（例如进程被重建），此时不应再放通知出去。
         */
        @Volatile
        var actionListener: ((String) -> Unit)? = null
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var lastTitle = "EchoLoop"
    private var lastText = "准备播放"
    private var lastPlaying = false
    private var lastSpeed = 1.0f
    private var lastPosition = 0L
    private var lastDuration = 0L
    private var keepAwake = false
    private lateinit var mediaSession: MediaSessionCompat

    override fun onCreate() {
        super.onCreate()
        mediaSession = MediaSessionCompat(this, "EchoLoop").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() { actionListener?.invoke("play") }
                override fun onPause() { actionListener?.invoke("pause") }
                override fun onSkipToPrevious() { actionListener?.invoke("prev") }
                override fun onSkipToNext() { actionListener?.invoke("next") }
                override fun onSeekTo(pos: Long) { actionListener?.invoke("seek:$pos") }
                override fun onCustomAction(action: String?, extras: Bundle?) {
                    if (action == "speed") actionListener?.invoke("speed")
                }
            })
            isActive = true
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_TOGGLE, ACTION_PREV, ACTION_NEXT, ACTION_SPEED -> {
                val listener = actionListener
                if (listener == null) {
                    // Flutter 侧已经没人接了，留着这个通知只会变成幽灵通知
                    stopSelf()
                    return START_NOT_STICKY
                }
                startForegroundCompat()
                listener.invoke(
                    when (intent.action) {
                        ACTION_TOGGLE -> "toggle"
                        ACTION_PREV -> "prev"
                        ACTION_NEXT -> "next"
                        else -> "speed"
                    },
                )
                return START_NOT_STICKY
            }

            else -> {
                intent?.let {
                    lastTitle = it.getStringExtra(EXTRA_TITLE) ?: lastTitle
                    lastText = it.getStringExtra(EXTRA_TEXT) ?: lastText
                    lastPlaying = it.getBooleanExtra(EXTRA_PLAYING, lastPlaying)
                    lastSpeed = it.getFloatExtra(EXTRA_SPEED, lastSpeed)
                    lastPosition = it.getLongExtra(EXTRA_POSITION, lastPosition)
                    lastDuration = it.getLongExtra(EXTRA_DURATION, lastDuration)
                    keepAwake = it.getBooleanExtra(EXTRA_KEEP_AWAKE, lastPlaying)
                }
                startForegroundCompat()
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        mediaSession.release()
        super.onDestroy()
    }

    // ------------------------------------------------------------------
    // 内部实现
    // ------------------------------------------------------------------

    private fun startForegroundCompat() {
        ensureChannel()
        updateMediaSession()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // 只有真正在播时才压住 CPU，暂停期间放掉，避免无谓耗电
        if (keepAwake) acquireWakeLock() else releaseWakeLock()
    }

    private fun ensureChannel() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "播放控制",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "后台播放时的锁屏与通知栏控制"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            pendingFlags(),
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_echoloop)
            .setContentTitle(lastTitle)
            .setContentText(lastText)
            .setContentIntent(contentIntent)
            .setOngoing(lastPlaying)
            .setSilent(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(
                android.R.drawable.ic_media_previous,
                "上一片段",
                servicePendingIntent(ACTION_PREV, REQUEST_PREV),
            )
            .addAction(
                if (lastPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (lastPlaying) "暂停" else "播放",
                servicePendingIntent(ACTION_TOGGLE, REQUEST_TOGGLE),
            )
            .addAction(
                android.R.drawable.ic_media_next,
                "下一片段",
                servicePendingIntent(ACTION_NEXT, REQUEST_NEXT),
            )
            .addAction(
                android.R.drawable.ic_menu_sort_by_size,
                "倍速 ${formatSpeed(lastSpeed)}",
                servicePendingIntent(ACTION_SPEED, REQUEST_SPEED),
            )
            // 折叠态只放三个按钮，展开后四个操作全部可见
            .setStyle(MediaStyle().setMediaSession(mediaSession.sessionToken).setShowActionsInCompactView(0, 1, 2))

        return builder.build()
    }

    private fun servicePendingIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, PlaybackService::class.java).setAction(action)
        return PendingIntent.getService(this, requestCode, intent, pendingFlags())
    }

    private fun pendingFlags(): Int =
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    private fun updateMediaSession() {
        mediaSession.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, lastTitle)
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, lastDuration)
                .build(),
        )
        val actions = PlaybackStateCompat.ACTION_PLAY or PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_PLAY_PAUSE or PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or PlaybackStateCompat.ACTION_SEEK_TO
        mediaSession.setPlaybackState(
            PlaybackStateCompat.Builder().setActions(actions)
                .addCustomAction("speed", "倍速 ${formatSpeed(lastSpeed)}", android.R.drawable.ic_menu_sort_by_size)
                .setState(
                if (lastPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                lastPosition.coerceAtLeast(0L),
                if (lastPlaying) lastSpeed else 0f,
            ).build(),
        )
    }

    private fun formatSpeed(speed: Float): String =
        if (speed % 1.0f == 0f) "${speed.toInt()}.0x" else "${speed}x"

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        if (wakeLock == null) {
            val manager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = manager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "echoloop:playback",
            ).apply { setReferenceCounted(false) }
        }
        runCatching { wakeLock?.acquire() }
    }

    private fun releaseWakeLock() {
        runCatching { if (wakeLock?.isHeld == true) wakeLock?.release() }
    }
}
