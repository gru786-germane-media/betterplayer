package com.jhomlala.better_player
import java.util.UUID
import com.google.android.gms.ads.identifier.AdvertisingIdClient
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.jhomlala.better_player.DataSourceUtils.getUserAgent
import com.jhomlala.better_player.DataSourceUtils.isHTTP
import com.jhomlala.better_player.DataSourceUtils.getDataSourceFactory
import io.flutter.plugin.common.EventChannel
import io.flutter.view.TextureRegistry.SurfaceTextureEntry
import io.flutter.plugin.common.MethodChannel
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector
import com.google.android.exoplayer2.ui.PlayerNotificationManager
import android.support.v4.media.session.MediaSessionCompat
import com.google.android.exoplayer2.drm.DrmSessionManager
import androidx.work.WorkManager
import androidx.work.WorkInfo
import com.google.android.exoplayer2.drm.HttpMediaDrmCallback
import com.google.android.exoplayer2.upstream.DefaultHttpDataSource
import com.google.android.exoplayer2.drm.DefaultDrmSessionManager
import com.google.android.exoplayer2.drm.FrameworkMediaDrm
import com.google.android.exoplayer2.drm.UnsupportedDrmException
import com.google.android.exoplayer2.drm.DummyExoMediaDrm
import com.google.android.exoplayer2.drm.LocalMediaDrmCallback
import com.google.android.exoplayer2.source.MediaSource
import com.google.android.exoplayer2.source.ClippingMediaSource
import com.google.android.exoplayer2.ui.PlayerNotificationManager.MediaDescriptionAdapter
import com.google.android.exoplayer2.ui.PlayerNotificationManager.BitmapCallback
import androidx.work.OneTimeWorkRequest
import android.support.v4.media.session.PlaybackStateCompat
import android.support.v4.media.MediaMetadataCompat
import android.util.Log
import android.view.Surface
import androidx.annotation.RequiresApi
import androidx.lifecycle.Observer
import com.google.android.exoplayer2.source.smoothstreaming.SsMediaSource
import com.google.android.exoplayer2.source.smoothstreaming.DefaultSsChunkSource
import com.google.android.exoplayer2.source.dash.DashMediaSource
import com.google.android.exoplayer2.source.dash.DefaultDashChunkSource
import com.google.android.exoplayer2.source.hls.HlsMediaSource
import com.google.android.exoplayer2.source.ProgressiveMediaSource
import com.google.android.exoplayer2.extractor.DefaultExtractorsFactory
import io.flutter.plugin.common.EventChannel.EventSink
import androidx.work.Data
import com.google.android.exoplayer2.*
import com.google.android.exoplayer2.audio.AudioAttributes
import com.google.android.exoplayer2.drm.DrmSessionManagerProvider
import com.google.android.exoplayer2.ext.mediasession.MediaSessionConnector
import com.google.android.exoplayer2.trackselection.TrackSelectionOverride
import com.google.android.exoplayer2.upstream.DataSource
import com.google.android.exoplayer2.upstream.DefaultDataSource
import com.google.android.exoplayer2.util.Util
import java.io.File
import java.lang.Exception
import java.lang.IllegalStateException
import java.util.*
import kotlin.math.max
import kotlin.math.min

// MediaTailor and Datazoom imports
import io.datazoom.sdk.mediatailor.setupAdSession
import io.datazoom.sdk.Datazoom
import io.datazoom.sdk.Config
import io.datazoom.sdk.BaseContextFactory
import io.datazoom.sdk.BaseContext
import io.datazoom.sdk.DzAdapter
import io.datazoom.sdk.exoplayer.*
import io.datazoom.sdk.exoplayer.createContext // Extension function import
import io.datazoom.sdk.SdkEvent

import com.amazon.mediatailorsdk.logs.LogLevel as MediaTailorLogLevel
import io.datazoom.sdk.logs.LogLevel as DataZoomLogLevel

import com.amazon.mediatailorsdk.*
import com.amazon.mediatailorsdk.SessionConfiguration
import com.amazon.mediatailorsdk.MediaTailor
import com.amazon.mediatailorsdk.Session
import com.amazon.mediatailorsdk.SessionCommon
import com.amazon.mediatailorsdk.SessionError
import com.amazon.mediatailorsdk.PalConsentSettings
import com.amazon.mediatailorsdk.PalNonceRequestParams

import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.delay

import java.lang.reflect.Field
import java.lang.reflect.Modifier

import com.google.android.exoplayer2.ui.PlayerView
import com.google.android.exoplayer2.ui.R.color


internal class BetterPlayer(
    context: Context,
    private val eventChannel: EventChannel,
    private val textureEntry: SurfaceTextureEntry,
    customDefaultLoadControl: CustomDefaultLoadControl?,
    result: MethodChannel.Result,
    private val plugin: BetterPlayerPlugin? = null // Added plugin reference
) {
    private val TAG = "BetterPlayerConfig"

    private val exoPlayer: ExoPlayer?
    private val eventSink = QueuingEventSink()
    private val trackSelector: DefaultTrackSelector = DefaultTrackSelector(context)
    private val loadControl: LoadControl
    private var isInitialized = false
    private var surface: Surface? = null
    private var key: String? = null
    private var playerNotificationManager: PlayerNotificationManager? = null
    private var refreshHandler: Handler? = null
    private var refreshRunnable: Runnable? = null
    private var exoPlayerEventListener: Player.Listener? = null
    private var bitmap: Bitmap? = null
    private var mediaSession: MediaSessionCompat? = null
    private var drmSessionManager: DrmSessionManager? = null
    private val workManager: WorkManager
    private val workerObserverMap: HashMap<UUID, Observer<WorkInfo?>>
    private val customDefaultLoadControl: CustomDefaultLoadControl =
        customDefaultLoadControl ?: CustomDefaultLoadControl()
    private var lastSendBufferedPosition = 0L

    // MediaTailor and Datazoom properties
    private var dataZoomDzAdapter: DzAdapter? = null
    private var playerView: PlayerView? = null

    init {
        Log.d(TAG, "Debug: Init State 1")

        val loadBuilder = DefaultLoadControl.Builder()
        loadBuilder.setBufferDurationsMs(
            this.customDefaultLoadControl.minBufferMs,
            this.customDefaultLoadControl.maxBufferMs,
            this.customDefaultLoadControl.bufferForPlaybackMs,
            this.customDefaultLoadControl.bufferForPlaybackAfterRebufferMs
        )
        Log.d(TAG, "Debug: Init State 7")
        loadControl = loadBuilder.build()
        val renderersFactory = DefaultRenderersFactory(context)
    .setEnableDecoderFallback(true)
        exoPlayer = ExoPlayer.Builder(context, renderersFactory)
            .setTrackSelector(trackSelector)
            .setLoadControl(loadControl)
            .build()

        Log.d(TAG, "Debug: Init State 8")

        // Initialize PlayerView for Datazoom
        playerView = PlayerView(context).apply {
            useController = false
            player = exoPlayer
            useArtwork = false
        }
        Log.d(TAG, "Debug: Init State 9")

        // Initialize Datazoom adapter if plugin provides context
        initializeDatazoomAdapter(context)

        workManager = WorkManager.getInstance(context)
        workerObserverMap = HashMap()
        setupVideoPlayer(eventChannel, textureEntry, result)
        Log.d(TAG, "Debug: Init State 12")
    }

    private fun initializeDatazoomAdapter(context: Context) {
        try {
                 var baseContext =  BaseContextFactory.create()
                dataZoomDzAdapter = Datazoom.createContext(exoPlayer!!,baseContext)
                Log.d(TAG, "Debug: Datazoom adapter initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Debug: Failed to initialize Datazoom adapter: ${e.message}", e)
        }
    }

fun printObjectDetails(obj: Any, tag: String = "ObjectDetails") {
    try {
        val sb = StringBuilder()
        sb.append("\n=== ${obj.javaClass.simpleName} Details ===\n")
        
        var currentClass: Class<*>? = obj.javaClass
        while (currentClass != null && currentClass != Any::class.java) {
            sb.append("Class: ${currentClass.name}\n")
            
            val fields = currentClass.declaredFields
            for (field in fields) {
                // Skip static fields
                if (Modifier.isStatic(field.modifiers)) continue
                
                field.isAccessible = true
                try {
                    val value = field.get(obj)
                    sb.append("  ${field.name}: ${value}\n")
                } catch (e: Exception) {
                    sb.append("  ${field.name}: [Error accessing: ${e.message}]\n")
                }
            }
            sb.append("----------------------------\n")
            currentClass = currentClass.superclass
        }
        
        Log.d(tag, sb.toString())
    } catch (e: Exception) {
        Log.e(tag, "Error printing object details: ${e.message}")
    }
}

    fun setDataSource(
        context: Context,
        key: String?,
        dataSource: String?,
        formatHint: String?,
        result: MethodChannel.Result,
        headers: Map<String, String>?,
        useCache: Boolean,
        maxCacheSize: Long,
        maxCacheFileSize: Long,
        overriddenDuration: Long,
        licenseUrl: String?,
        drmHeaders: Map<String, String>?,
        cacheKey: String?,
        clearKey: String?,
        shouldEnableSSAI: Boolean = false  // New parameter with default false
    ) {
        this.key = key
        isInitialized = false

        Log.d(TAG, "Debug: setDataSource called with shouldEnableSSAI: $shouldEnableSSAI")
        Log.d(TAG, "Debug: Original dataSource: $dataSource")

        // Check if we should use MediaTailor SSAI
        if (shouldEnableSSAI && !dataSource.isNullOrEmpty()) {
            Log.d(TAG, "Debug: SSAI enabled, attempting to use MediaTailor")

            // Transform URL if needed (v1/master/* to v1/session/*)
            val transformedUrl = transformUrlForSSAI(dataSource,context)
            Log.d(TAG, "Debug: Transformed URL: $transformedUrl")

            // Create MediaTailor session
            createMediaTailorSession(context, transformedUrl, result, headers,
                useCache, maxCacheSize, maxCacheFileSize, overriddenDuration,
                licenseUrl, drmHeaders, cacheKey, clearKey, formatHint)
        } else {
            Log.d(TAG, "Debug: SSAI disabled or dataSource empty, using normal playback")
            // Use normal playback without MediaTailor
            setupNormalPlayback(context, dataSource, result, headers,
                useCache, maxCacheSize, maxCacheFileSize, overriddenDuration,
                licenseUrl, drmHeaders, cacheKey, clearKey, formatHint)
        }
    }
private fun transformUrlForSSAI(originalUrl: String, context: Context): String {
    return try {
        // Replace v1/master/ with v1/session/
        val transformed = originalUrl.replace(
            Regex("""/v1/master/"""),
            "/v1/session/"
        ) 
        transformed
    } catch (e: Exception) {
        Log.e(TAG, "Debug: Failed to transform URL: ${e.message}")
        originalUrl // Return original if transformation fails
    }
}

private fun extractUrlParameters( context: Context): Map<String, String> {
    val params = mutableMapOf<String, String>()
    
    return try {
        // Get the current app bundle ID
        val bundleId = context.packageName
        params["idtype"] = "aaid";
        params["an"] = "Swift%20TV%20-%20Live%20TV%20Streaming";
        params["msid"] = bundleId;
        // Get and add the Google Advertising ID (GAID)
        getGoogleAdvertisingId(context) { gaid ->
                params["rdid"] = gaid; 
        }
        Log.d(TAG, "Debug: Successfully extracted ${params.size} parameters from URL")
        params
    } catch (e: Exception) {
        Log.e(TAG, "Error extracting URL parameters: ${e.message}")
        emptyMap()
    }
}
 

private fun getGoogleAdvertisingId(context: Context, callback: (String) -> Unit) {
    try {
        val advertisingIdClient = AdvertisingIdClient.getAdvertisingIdInfo(context)
        val gaid = advertisingIdClient.id
        
        // If GAID is empty or null, generate a random UUID as fallback
        val finalId = if (gaid.isNullOrEmpty()) {
            Log.w(TAG, "GAID is empty, generating random UUID")
            generateRandomUUID()
        } else {
            gaid
        }
        
        callback(finalId)
    } catch (e: Exception) {
        Log.e(TAG, "Error getting Google Advertising ID: ${e.message}")
        // Generate a random UUID as fallback when error occurs
        callback(generateRandomUUID())
    }
}

private fun generateRandomUUID(): String {
    return java.util.UUID.randomUUID().toString()
}
    private fun createMediaTailorSession(
        context: Context,
        sessionUrl: String,
        result: MethodChannel.Result,
        headers: Map<String, String>?,
        useCache: Boolean,
        maxCacheSize: Long,
        maxCacheFileSize: Long,
        overriddenDuration: Long,
        licenseUrl: String?,
        drmHeaders: Map<String, String>?,
        cacheKey: String?,
        clearKey: String?,
        formatHint: String?
    ) {
        Log.d(TAG, "Debug: Creating MediaTailor session for URL: $sessionUrl")


        // Extract URL parameters from sessionUrl
        val urlParams = extractUrlParameters(context)
        Log.d(TAG, "Debug: Extracted URL parameters: $urlParams")


        // Create PAL nonce request parameters
        val palNonceRequestParams = PalNonceRequestParams.Builder()
            .adWillAutoPlay(true)
            .adWillPlayMuted(false)
            .descriptionUrl("https://playswift.tv")
            .iconsSupported(true)
            .playerType("ExoPlayer")
            .playerVersion("0.0.12")
            .ppid("12345")
            .videoHeight(1080)
            .videoWidth(1920)
            .omidPartnerName("amazon2")
            .omidPartnerVersion("1.0.0")
            .build()

        // Build session configuration
        val configBuilder = SessionConfiguration.Builder()
            .sessionInitUrl(sessionUrl)
            .palNonceRequestParams(palNonceRequestParams)
             .playerParams(urlParams) // Add extracted URL parameters

        Log.d(TAG, "Debug: MediaTailor session configuration built")

        // Create MediaTailor session
        MediaTailor.createSession(configBuilder.build()) { session, error ->
            if (error == null && session != null) {
                Log.d(TAG, "Debug: MediaTailor session created successfully")

                // Print session details for debugging
                printObjectDetails(session, "SessionDebug")

                // Use session playback URL if available, otherwise use original
                val playbackUrl = session.playbackUrl ?: sessionUrl
                Log.d(TAG, "Debug: Using playback URL: $playbackUrl")

                // Setup Datazoom ad session if adapter is available
                if (dataZoomDzAdapter != null && playerView != null) {
                    dataZoomDzAdapter!!.setupAdSession(session, playerView!!, playbackUrl)
                    Log.d(TAG, "Debug: Datazoom ad session setup completed")
                } else {
                    Log.w(TAG, "Debug: Datazoom adapter or playerView not available for ad session")
                }

                // Setup playback with the MediaTailor URL
                setupNormalPlayback(context, playbackUrl, result, headers,
                    useCache, maxCacheSize, maxCacheFileSize, overriddenDuration,
                    licenseUrl, drmHeaders, cacheKey, clearKey, formatHint)
            } else {
                Log.e(TAG, "Debug: MediaTailor session creation failed: ${error?.message}")

                // Fallback to normal playback with original URL
                Log.d(TAG, "Debug: Falling back to normal playback")
                setupNormalPlayback(context, sessionUrl, result, headers,
                    useCache, maxCacheSize, maxCacheFileSize, overriddenDuration,
                    licenseUrl, drmHeaders, cacheKey, clearKey, formatHint)
            }
        }
    }

    private fun setupNormalPlayback(
        context: Context,
        dataSource: String?,
        result: MethodChannel.Result,
        headers: Map<String, String>?,
        useCache: Boolean,
        maxCacheSize: Long,
        maxCacheFileSize: Long,
        overriddenDuration: Long,
        licenseUrl: String?,
        drmHeaders: Map<String, String>?,
        cacheKey: String?,
        clearKey: String?,
        formatHint: String?
    ) {
        if (dataSource.isNullOrEmpty()) {
            result.error("InvalidDataSource", "Data source is null or empty", null)
            return
        }

        val uri = Uri.parse(dataSource)
        var dataSourceFactory: DataSource.Factory?
        val userAgent = getUserAgent(headers)

        // Setup DRM if needed
        setupDrmSessionManager(licenseUrl, drmHeaders, clearKey)

        // Create data source factory
        if (isHTTP(uri)) {
            dataSourceFactory = getDataSourceFactory(userAgent, headers)
            if (useCache && maxCacheSize > 0 && maxCacheFileSize > 0) {
                dataSourceFactory = CacheDataSourceFactory(
                    context,
                    maxCacheSize,
                    maxCacheFileSize,
                    dataSourceFactory
                )
            }
        } else {
            dataSourceFactory = DefaultDataSource.Factory(context)
        }

        // Build and prepare media source
        val mediaSource = buildMediaSource(uri, dataSourceFactory, formatHint, cacheKey, context)
        if (overriddenDuration != 0L) {
            val clippingMediaSource = ClippingMediaSource(mediaSource, 0, overriddenDuration * 1000)
            exoPlayer?.setMediaSource(clippingMediaSource)
        } else {
            exoPlayer?.setMediaSource(mediaSource)
        }

        exoPlayer?.prepare()
        result.success(null)
        Log.d(TAG, "Debug: Normal playback setup completed")
    }

    private fun setupDrmSessionManager(
        licenseUrl: String?,
        drmHeaders: Map<String, String>?,
        clearKey: String?
    ) {
        when {
            !licenseUrl.isNullOrEmpty() -> {
                val httpMediaDrmCallback = HttpMediaDrmCallback(licenseUrl, DefaultHttpDataSource.Factory())
                drmHeaders?.forEach { (key, value) ->
                    httpMediaDrmCallback.setKeyRequestProperty(key, value)
                }

                if (Util.SDK_INT < 18) {
                    Log.e(TAG, "Protected content not supported on API levels below 18")
                    drmSessionManager = null
                } else {
                    val drmSchemeUuid = Util.getDrmUuid("widevine")
                    if (drmSchemeUuid != null) {
                        drmSessionManager = DefaultDrmSessionManager.Builder()
                            .setUuidAndExoMediaDrmProvider(drmSchemeUuid) { uuid: UUID? ->
                                try {
                                    val mediaDrm = FrameworkMediaDrm.newInstance(uuid!!)
                                    // Force L3.
                                    mediaDrm.setPropertyString("securityLevel", "L3")
                                    return@setUuidAndExoMediaDrmProvider mediaDrm
                                } catch (e: UnsupportedDrmException) {
                                    return@setUuidAndExoMediaDrmProvider DummyExoMediaDrm()
                                }
                            }
                            .setMultiSession(false)
                            .build(httpMediaDrmCallback)
                    }
                }
            }
            !clearKey.isNullOrEmpty() -> {
                drmSessionManager = if (Util.SDK_INT < 18) {
                    Log.e(TAG, "Protected content not supported on API levels below 18")
                    null
                } else {
                    DefaultDrmSessionManager.Builder()
                        .setUuidAndExoMediaDrmProvider(
                            C.CLEARKEY_UUID,
                            FrameworkMediaDrm.DEFAULT_PROVIDER
                        ).build(LocalMediaDrmCallback(clearKey.toByteArray()))
                }
            }
            else -> {
                drmSessionManager = null
            }
        }
    }

    fun setupPlayerNotification(
        context: Context, title: String, author: String?,
        imageUrl: String?, notificationChannelName: String?,
        activityName: String
    ) {
        val mediaDescriptionAdapter: MediaDescriptionAdapter = object : MediaDescriptionAdapter {
            override fun getCurrentContentTitle(player: Player): String {
                return title
            }

            @RequiresApi(Build.VERSION_CODES.M)
            @SuppressLint("UnspecifiedImmutableFlag")
            override fun createCurrentContentIntent(player: Player): PendingIntent? {
                val packageName = context.applicationContext.packageName
                val notificationIntent = Intent()
                notificationIntent.setClassName(
                    packageName,
                    "$packageName.$activityName"
                )
                notificationIntent.flags = (Intent.FLAG_ACTIVITY_CLEAR_TOP
                        or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                return PendingIntent.getActivity(
                    context, 0,
                    notificationIntent,
                    PendingIntent.FLAG_IMMUTABLE
                )
            }

            override fun getCurrentContentText(player: Player): String? {
                return author
            }

            override fun getCurrentLargeIcon(
                player: Player,
                callback: BitmapCallback
            ): Bitmap? {
                if (imageUrl == null) {
                    return null
                }
                if (bitmap != null) {
                    return bitmap
                }
                val imageWorkRequest = OneTimeWorkRequest.Builder(ImageWorker::class.java)
                    .addTag(imageUrl)
                    .setInputData(
                        Data.Builder()
                            .putString(BetterPlayerPlugin.URL_PARAMETER, imageUrl)
                            .build()
                    )
                    .build()
                workManager.enqueue(imageWorkRequest)
                val workInfoObserver = Observer { workInfo: WorkInfo? ->
                    try {
                        if (workInfo != null) {
                            val state = workInfo.state
                            if (state == WorkInfo.State.SUCCEEDED) {
                                val outputData = workInfo.outputData
                                val filePath =
                                    outputData.getString(BetterPlayerPlugin.FILE_PATH_PARAMETER)
                                //Bitmap here is already processed and it's very small, so it won't
                                //break anything.
                                bitmap = BitmapFactory.decodeFile(filePath)
                                bitmap?.let { bitmap ->
                                    callback.onBitmap(bitmap)
                                }
                            }
                            if (state == WorkInfo.State.SUCCEEDED || state == WorkInfo.State.CANCELLED || state == WorkInfo.State.FAILED) {
                                val uuid = imageWorkRequest.id
                                val observer = workerObserverMap.remove(uuid)
                                if (observer != null) {
                                    workManager.getWorkInfoByIdLiveData(uuid)
                                        .removeObserver(observer)
                                }
                            }
                        }
                    } catch (exception: Exception) {
                        Log.e(TAG, "Image select error: $exception")
                    }
                }
                val workerUuid = imageWorkRequest.id
                workManager.getWorkInfoByIdLiveData(workerUuid)
                    .observeForever(workInfoObserver)
                workerObserverMap[workerUuid] = workInfoObserver
                return null
            }
        }
        var playerNotificationChannelName = notificationChannelName
        if (notificationChannelName == null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val importance = NotificationManager.IMPORTANCE_LOW
                val channel = NotificationChannel(
                    DEFAULT_NOTIFICATION_CHANNEL,
                    DEFAULT_NOTIFICATION_CHANNEL, importance
                )
                channel.description = DEFAULT_NOTIFICATION_CHANNEL
                val notificationManager = context.getSystemService(
                    NotificationManager::class.java
                )
                notificationManager.createNotificationChannel(channel)
                playerNotificationChannelName = DEFAULT_NOTIFICATION_CHANNEL
            }
        }

        playerNotificationManager = PlayerNotificationManager.Builder(
            context, NOTIFICATION_ID,
            playerNotificationChannelName!!
        ).setMediaDescriptionAdapter(mediaDescriptionAdapter).build()

        playerNotificationManager?.apply {

            exoPlayer?.let {
                setPlayer(ForwardingPlayer(exoPlayer))
                setUseNextAction(false)
                setUsePreviousAction(false)
                setUseStopAction(false)
            }

            setupMediaSession(context)?.let {
                setMediaSessionToken(it.sessionToken)
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            refreshHandler = Handler(Looper.getMainLooper())
            refreshRunnable = Runnable {
                val playbackState: PlaybackStateCompat = if (exoPlayer?.isPlaying == true) {
                    PlaybackStateCompat.Builder()
                        .setActions(PlaybackStateCompat.ACTION_SEEK_TO)
                        .setState(PlaybackStateCompat.STATE_PLAYING, position, 1.0f)
                        .build()
                } else {
                    PlaybackStateCompat.Builder()
                        .setActions(PlaybackStateCompat.ACTION_SEEK_TO)
                        .setState(PlaybackStateCompat.STATE_PAUSED, position, 1.0f)
                        .build()
                }
                mediaSession?.setPlaybackState(playbackState)
                refreshHandler?.postDelayed(refreshRunnable!!, 1000)
            }
            refreshHandler?.postDelayed(refreshRunnable!!, 0)
        }
        exoPlayerEventListener = object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                mediaSession?.setMetadata(
                    MediaMetadataCompat.Builder()
                        .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, getDuration())
                        .build()
                )
            }
        }
        exoPlayerEventListener?.let { exoPlayerEventListener ->
            exoPlayer?.addListener(exoPlayerEventListener)
        }
        exoPlayer?.seekTo(0)
    }

    fun disposeRemoteNotifications() {
        exoPlayerEventListener?.let { exoPlayerEventListener ->
            exoPlayer?.removeListener(exoPlayerEventListener)
        }
        if (refreshHandler != null) {
            refreshHandler?.removeCallbacksAndMessages(null)
            refreshHandler = null
            refreshRunnable = null
        }
        if (playerNotificationManager != null) {
            playerNotificationManager?.setPlayer(null)
        }
        bitmap = null
    }

    private fun buildMediaSource(
        uri: Uri,
        mediaDataSourceFactory: DataSource.Factory,
        formatHint: String?,
        cacheKey: String?,
        context: Context
    ): MediaSource {
        val type: Int
        if (formatHint == null) {
            var lastPathSegment = uri.lastPathSegment
            if (lastPathSegment == null) {
                lastPathSegment = ""
            }
            type = Util.inferContentTypeForExtension(lastPathSegment)
        } else {
            type = when (formatHint) {
                FORMAT_SS -> C.CONTENT_TYPE_SS
                FORMAT_DASH -> C.CONTENT_TYPE_DASH
                FORMAT_HLS -> C.CONTENT_TYPE_HLS
                FORMAT_OTHER -> C.CONTENT_TYPE_OTHER
                else -> -1
            }
        }
        val mediaItemBuilder = MediaItem.Builder()
        mediaItemBuilder.setUri(uri)
        if (cacheKey != null && cacheKey.isNotEmpty()) {
            mediaItemBuilder.setCustomCacheKey(cacheKey)
        }
        val mediaItem = mediaItemBuilder.build()
        var drmSessionManagerProvider: DrmSessionManagerProvider? = null
        drmSessionManager?.let { drmSessionManager ->
            drmSessionManagerProvider = DrmSessionManagerProvider { drmSessionManager }
        }
        return when (type) {
            C.CONTENT_TYPE_SS -> SsMediaSource.Factory(
                DefaultSsChunkSource.Factory(mediaDataSourceFactory),
                DefaultDataSource.Factory(context, mediaDataSourceFactory)
            ).apply {
                if (drmSessionManagerProvider != null) {
                    setDrmSessionManagerProvider(drmSessionManagerProvider!!)
                }
            }.createMediaSource(mediaItem)
            C.CONTENT_TYPE_DASH -> DashMediaSource.Factory(
                DefaultDashChunkSource.Factory(mediaDataSourceFactory),
                DefaultDataSource.Factory(context, mediaDataSourceFactory)
            ).apply {
                if (drmSessionManagerProvider != null) {
                    setDrmSessionManagerProvider(drmSessionManagerProvider!!)
                }
            }.createMediaSource(mediaItem)
            C.CONTENT_TYPE_HLS -> HlsMediaSource.Factory(mediaDataSourceFactory)
                .apply {
                    if (drmSessionManagerProvider != null) {
                        setDrmSessionManagerProvider(drmSessionManagerProvider!!)
                    }
                }.createMediaSource(mediaItem)
            C.CONTENT_TYPE_OTHER -> ProgressiveMediaSource.Factory(
                mediaDataSourceFactory,
                DefaultExtractorsFactory()
            ).apply {
                if (drmSessionManagerProvider != null) {
                    setDrmSessionManagerProvider(drmSessionManagerProvider!!)
                }
            }.createMediaSource(mediaItem)
            else -> {
                throw IllegalStateException("Unsupported type: $type")
            }
        }
    }

    private fun setupVideoPlayer(
        eventChannel: EventChannel, textureEntry: SurfaceTextureEntry, result: MethodChannel.Result
    ) {
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(o: Any?, sink: EventSink) {
                    eventSink.setDelegate(sink)
                }

                override fun onCancel(o: Any?) {
                    eventSink.setDelegate(null)
                }
            })
        surface = Surface(textureEntry.surfaceTexture())
        exoPlayer?.setVideoSurface(surface)
        setAudioAttributes(exoPlayer, true)
        exoPlayer?.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_BUFFERING -> {
                        sendBufferingUpdate(true)
                        val event: MutableMap<String, Any> = HashMap()
                        event["event"] = "bufferingStart"
                        eventSink.success(event)
                    }
                    Player.STATE_READY -> {
                        if (!isInitialized) {
                            isInitialized = true
                            sendInitialized()
                        }
                        val event: MutableMap<String, Any> = HashMap()
                        event["event"] = "bufferingEnd"
                        eventSink.success(event)
                    }
                    Player.STATE_ENDED -> {
                        val event: MutableMap<String, Any?> = HashMap()
                        event["event"] = "completed"
                        event["key"] = key
                        eventSink.success(event)
                    }
                    Player.STATE_IDLE -> {
                        //no-op
                    }
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                eventSink.error("VideoError", "Video player had error $error", "")
            }
        })
        val reply: MutableMap<String, Any> = HashMap()
        reply["textureId"] = textureEntry.id()
        result.success(reply)
    }

    fun sendBufferingUpdate(isFromBufferingStart: Boolean) {
        val bufferedPosition = exoPlayer?.bufferedPosition ?: 0L
        if (isFromBufferingStart || bufferedPosition != lastSendBufferedPosition) {
            val event: MutableMap<String, Any> = HashMap()
            event["event"] = "bufferingUpdate"
            val range: List<Number?> = listOf(0, bufferedPosition)
            // iOS supports a list of buffered ranges, so here is a list with a single range.
            event["values"] = listOf(range)
            eventSink.success(event)
            lastSendBufferedPosition = bufferedPosition
        }
    }

    @Suppress("DEPRECATION")
    private fun setAudioAttributes(exoPlayer: ExoPlayer?, mixWithOthers: Boolean) {
        val audioComponent = exoPlayer?.audioComponent ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            audioComponent.setAudioAttributes(
                AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
                !mixWithOthers
            )
        } else {
            audioComponent.setAudioAttributes(
                AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(),
                !mixWithOthers
            )
        }
    }

    fun play() {
        exoPlayer?.playWhenReady = true
    }

    fun pause() {
        exoPlayer?.playWhenReady = false
    }

    fun setLooping(value: Boolean) {
        exoPlayer?.repeatMode = if (value) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
    }

    fun setVolume(value: Double) {
        val bracketedValue = max(0.0, min(1.0, value))
            .toFloat()
        exoPlayer?.volume = bracketedValue
    }

    fun setSpeed(value: Double) {
        val bracketedValue = value.toFloat()
        val playbackParameters = PlaybackParameters(bracketedValue)
        exoPlayer?.playbackParameters = playbackParameters
    }

    fun setTrackParameters(width: Int, height: Int, bitrate: Int) {
        val parametersBuilder = trackSelector.buildUponParameters()
        if (width != 0 && height != 0) {
            parametersBuilder.setMaxVideoSize(width, height)
        }
        if (bitrate != 0) {
            parametersBuilder.setMaxVideoBitrate(bitrate)
        }
        if (width == 0 && height == 0 && bitrate == 0) {
            parametersBuilder.clearVideoSizeConstraints()
            parametersBuilder.setMaxVideoBitrate(Int.MAX_VALUE)
        }
        trackSelector.setParameters(parametersBuilder)
    }

    fun seekTo(location: Int) {
        exoPlayer?.seekTo(location.toLong())
    }

    val position: Long
        get() = exoPlayer?.currentPosition ?: 0L

    val absolutePosition: Long
        get() {
            val timeline = exoPlayer?.currentTimeline
            timeline?.let {
                if (!timeline.isEmpty) {
                    val windowStartTimeMs =
                        timeline.getWindow(0, Timeline.Window()).windowStartTimeMs
                    val pos = exoPlayer?.currentPosition ?: 0L
                    return windowStartTimeMs + pos
                }
            }
            return exoPlayer?.currentPosition ?: 0L
        }

    private fun sendInitialized() {
        if (isInitialized) {
            val event: MutableMap<String, Any?> = HashMap()
            event["event"] = "initialized"
            event["key"] = key
            event["duration"] = getDuration()
            if (exoPlayer?.videoFormat != null) {
                val videoFormat = exoPlayer.videoFormat
                var width = videoFormat?.width
                var height = videoFormat?.height
                val rotationDegrees = videoFormat?.rotationDegrees
                // Switch the width/height if video was taken in portrait mode
                if (rotationDegrees == 90 || rotationDegrees == 270) {
                    width = exoPlayer.videoFormat?.height
                    height = exoPlayer.videoFormat?.width
                }
                event["width"] = width
                event["height"] = height
            }
            eventSink.success(event)
        }
    }

    private fun getDuration(): Long = exoPlayer?.duration ?: 0L

    /**
     * Create media session which will be used in notifications, pip mode.
     *
     * @param context                - android context
     * @return - configured MediaSession instance
     */
    @SuppressLint("InlinedApi")
    fun setupMediaSession(context: Context?): MediaSessionCompat? {
        mediaSession?.release()
        context?.let {

            val mediaButtonIntent = Intent(Intent.ACTION_MEDIA_BUTTON)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                0, mediaButtonIntent,
                PendingIntent.FLAG_IMMUTABLE
            )
            val mediaSession = MediaSessionCompat(context, TAG, null, pendingIntent)
            mediaSession.setCallback(object : MediaSessionCompat.Callback() {
                override fun onSeekTo(pos: Long) {
                    sendSeekToEvent(pos)
                    super.onSeekTo(pos)
                }
            })
            mediaSession.isActive = true
            val mediaSessionConnector = MediaSessionConnector(mediaSession)
            mediaSessionConnector.setPlayer(exoPlayer)
            this.mediaSession = mediaSession
            return mediaSession
        }
        return null

    }

    fun onPictureInPictureStatusChanged(inPip: Boolean) {
        val event: MutableMap<String, Any> = HashMap()
        event["event"] = if (inPip) "pipStart" else "pipStop"
        eventSink.success(event)
    }

    fun disposeMediaSession() {
        if (mediaSession != null) {
            mediaSession?.release()
        }
        mediaSession = null
    }

    fun setAudioTrack(name: String, index: Int) {
        try {
            val mappedTrackInfo = trackSelector.currentMappedTrackInfo
            if (mappedTrackInfo != null) {
                for (rendererIndex in 0 until mappedTrackInfo.rendererCount) {
                    if (mappedTrackInfo.getRendererType(rendererIndex) != C.TRACK_TYPE_AUDIO) {
                        continue
                    }
                    val trackGroupArray = mappedTrackInfo.getTrackGroups(rendererIndex)
                    var hasElementWithoutLabel = false
                    var hasStrangeAudioTrack = false
                    for (groupIndex in 0 until trackGroupArray.length) {
                        val group = trackGroupArray[groupIndex]
                        for (groupElementIndex in 0 until group.length) {
                            val format = group.getFormat(groupElementIndex)
                            if (format.label == null) {
                                hasElementWithoutLabel = true
                            }
                            if (format.id != null && format.id == "1/15") {
                                hasStrangeAudioTrack = true
                            }
                        }
                    }
                    for (groupIndex in 0 until trackGroupArray.length) {
                        val group = trackGroupArray[groupIndex]
                        for (groupElementIndex in 0 until group.length) {
                            val label = group.getFormat(groupElementIndex).label
                            if (name == label && index == groupIndex) {
                                setAudioTrack(rendererIndex, groupIndex, groupElementIndex)
                                return
                            }

                            ///Fallback option
                            if (!hasStrangeAudioTrack && hasElementWithoutLabel && index == groupIndex) {
                                setAudioTrack(rendererIndex, groupIndex, groupElementIndex)
                                return
                            }
                            ///Fallback option
                            if (hasStrangeAudioTrack && name == label) {
                                setAudioTrack(rendererIndex, groupIndex, groupElementIndex)
                                return
                            }
                        }
                    }
                }
            }
        } catch (exception: Exception) {
            Log.e(TAG, "setAudioTrack failed$exception")
        }
    }

    private fun setAudioTrack(rendererIndex: Int, groupIndex: Int, groupElementIndex: Int) {
        val mappedTrackInfo = trackSelector.currentMappedTrackInfo
        if (mappedTrackInfo != null) {
            val builder = trackSelector.parameters.buildUpon()
                .setRendererDisabled(rendererIndex, false)
                .addOverride(
                    TrackSelectionOverride(
                        mappedTrackInfo.getTrackGroups(rendererIndex).get(groupIndex),
                        mappedTrackInfo.getTrackGroups(rendererIndex)
                            .indexOf(mappedTrackInfo.getTrackGroups(rendererIndex).get(groupIndex))
                    )
                )

            trackSelector.setParameters(builder)
        }
    }

    private fun sendSeekToEvent(positionMs: Long) {
        exoPlayer?.seekTo(positionMs)
        val event: MutableMap<String, Any> = HashMap()
        event["event"] = "seek"
        event["position"] = positionMs
        eventSink.success(event)
    }

    fun setMixWithOthers(mixWithOthers: Boolean) {
        setAudioAttributes(exoPlayer, mixWithOthers)
    }

    fun dispose() {
        disposeMediaSession()
        disposeRemoteNotifications()
        if (isInitialized) {
            exoPlayer?.stop()
        }
        textureEntry.release()
        eventChannel.setStreamHandler(null)
        surface?.release()
        exoPlayer?.release()
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || javaClass != other.javaClass) return false
        val that = other as BetterPlayer
        if (if (exoPlayer != null) exoPlayer != that.exoPlayer else that.exoPlayer != null) return false
        return if (surface != null) surface == that.surface else that.surface == null
    }

    override fun hashCode(): Int {
        var result = exoPlayer?.hashCode() ?: 0
        result = 31 * result + if (surface != null) surface.hashCode() else 0
        return result
    }

    companion object {
        private const val TAG = "BetterPlayer"
        private const val FORMAT_SS = "ss"
        private const val FORMAT_DASH = "dash"
        private const val FORMAT_HLS = "hls"
        private const val FORMAT_OTHER = "other"
        private const val DEFAULT_NOTIFICATION_CHANNEL = "BETTER_PLAYER_NOTIFICATION"
        private const val NOTIFICATION_ID = 20772077

        //Clear cache without accessing BetterPlayerCache.
        fun clearCache(context: Context?, result: MethodChannel.Result) {
            try {
                context?.let {
                    val file = File(it.cacheDir, "betterPlayerCache")
                    deleteDirectory(file)
                }
                result.success(null)
            } catch (exception: Exception) {
                Log.e(TAG, exception.toString())
                result.error("", "", "")
            }
        }

        private fun deleteDirectory(file: File) {
            if (file.isDirectory) {
                val entries = file.listFiles()
                if (entries != null) {
                    for (entry in entries) {
                        deleteDirectory(entry)
                    }
                }
            }
            if (!file.delete()) {
                Log.e(TAG, "Failed to delete cache dir.")
            }
        }

        //Start pre cache of video. Invoke work manager job and start caching in background.
        fun preCache(
            context: Context?, dataSource: String?, preCacheSize: Long,
            maxCacheSize: Long, maxCacheFileSize: Long, headers: Map<String, String?>,
            cacheKey: String?, result: MethodChannel.Result
        ) {
            val dataBuilder = Data.Builder()
                .putString(BetterPlayerPlugin.URL_PARAMETER, dataSource)
                .putLong(BetterPlayerPlugin.PRE_CACHE_SIZE_PARAMETER, preCacheSize)
                .putLong(BetterPlayerPlugin.MAX_CACHE_SIZE_PARAMETER, maxCacheSize)
                .putLong(BetterPlayerPlugin.MAX_CACHE_FILE_SIZE_PARAMETER, maxCacheFileSize)
            if (cacheKey != null) {
                dataBuilder.putString(BetterPlayerPlugin.CACHE_KEY_PARAMETER, cacheKey)
            }
            for (headerKey in headers.keys) {
                dataBuilder.putString(
                    BetterPlayerPlugin.HEADER_PARAMETER + headerKey,
                    headers[headerKey]
                )
            }
            if (dataSource != null && context != null) {
                val cacheWorkRequest = OneTimeWorkRequest.Builder(CacheWorker::class.java)
                    .addTag(dataSource)
                    .setInputData(dataBuilder.build()).build()
                WorkManager.getInstance(context).enqueue(cacheWorkRequest)
            }
            result.success(null)
        }

        //Stop pre cache of video with given url. If there's no work manager job for given url, then
        //it will be ignored.
        fun stopPreCache(context: Context?, url: String?, result: MethodChannel.Result) {
            if (url != null && context != null) {
                WorkManager.getInstance(context).cancelAllWorkByTag(url)
            }
            result.success(null)
        }
    }
}