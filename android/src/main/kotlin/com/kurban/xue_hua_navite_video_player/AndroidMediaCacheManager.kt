package com.kurban.xue_hua_navite_video_player

import android.content.Context
import androidx.core.net.toUri
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.FileDataSource
import androidx.media3.datasource.cache.Cache
import androidx.media3.datasource.cache.CacheDataSink
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.CacheEvictor
import androidx.media3.datasource.cache.CacheKeyFactory
import androidx.media3.datasource.cache.CacheSpan
import androidx.media3.datasource.cache.CacheWriter
import androidx.media3.datasource.cache.ContentMetadata
import androidx.media3.datasource.cache.SimpleCache
import java.io.File
import java.io.IOException
import java.util.TreeSet
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService

private const val DEFAULT_USER_AGENT =
    "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

/**
 * 动态可调容量的 LRU 缓存淘汰器，支持活跃会话 `pinnedKeys` 引用保护。
 */
@UnstableApi
internal class DynamicLruCacheEvictor(
    @Volatile var maxBytes: Long,
    private val isPinned: (String) -> Boolean,
) : CacheEvictor {

    private val leastRecentlyUsed = TreeSet<CacheSpan> { lhs, rhs ->
        val touchDelta = lhs.lastTouchTimestamp - rhs.lastTouchTimestamp
        when {
            touchDelta == 0L -> lhs.compareTo(rhs)
            touchDelta < 0L -> -1
            else -> 1
        }
    }

    private var currentSize: Long = 0L

    override fun requiresCacheSpanTouches(): Boolean = true

    override fun onCacheInitialized() {}

    @Synchronized
    override fun onStartFile(cache: Cache, key: String, position: Long, length: Long) {
        if (length != C.LENGTH_UNSET.toLong()) {
            evictCache(cache, length)
        }
    }

    @Synchronized
    override fun onSpanAdded(cache: Cache, span: CacheSpan) {
        leastRecentlyUsed.add(span)
        currentSize += span.length
        evictCache(cache, 0L)
    }

    @Synchronized
    override fun onSpanRemoved(cache: Cache, span: CacheSpan) {
        leastRecentlyUsed.remove(span)
        currentSize -= span.length
    }

    @Synchronized
    override fun onSpanTouched(cache: Cache, oldSpan: CacheSpan, newSpan: CacheSpan) {
        onSpanRemoved(cache, oldSpan)
        onSpanAdded(cache, newSpan)
    }

    @Synchronized
    fun evictNow(cache: Cache) {
        evictCache(cache, 0L)
    }

    private fun evictCache(cache: Cache, requiredSpace: Long) {
        val limit = maxBytes.coerceAtLeast(0L)
        if (currentSize + requiredSpace <= limit) return

        val snapshot = ArrayList(leastRecentlyUsed)
        for (span in snapshot) {
            if (currentSize + requiredSpace <= limit) break
            if (isPinned(span.key)) continue
            try {
                cache.removeSpan(span)
            } catch (_: Throwable) {
            }
        }
    }
}

/**
 * 进程级 Media3 `SimpleCache` 单例管理器。
 *
 * Media3 强制要求同一缓存目录在进程内只能绑定唯一一个 [SimpleCache] 实例；
 * 本类按规范化目录路径统一持有实例，支持：
 * - 边播边存 (`CacheDataSource.Factory` + `FLAG_IGNORE_CACHE_ON_ERROR`)；
 * - 自定义 `cacheKey`（通过 `MediaItem.customCacheKey` / `DataSpec.key`）；
 * - 单源自定义 HTTP `headers`；
 * - 单文件大小上限旁路（通过带检查的 `DataSink.Factory` + `FLAG_IGNORE_CACHE_ON_ERROR`）；
 * - 后台首包或整包预热（`CacheWriter`）及随时取消；
 * - 容量统计、单源清理与一键清空（自动跳过活跃 `pinned` 资源）。
 */
@UnstableApi
internal object AndroidMediaCacheManager {
    private val cacheLock = Any()
    private val cachesByCanonicalDir = HashMap<String, Pair<SimpleCache, DynamicLruCacheEvictor>>()
    private var dbProvider: StandaloneDatabaseProvider? = null

    private val pinnedKeys = ConcurrentHashMap.newKeySet<String>()
    private val activePrecacheWriters = ConcurrentHashMap<String, CacheWriter>()

    @Volatile
    var enabled: Boolean = true
        private set

    @Volatile
    var maxCacheBytes: Long = 512L * 1024L * 1024L
        private set

    @Volatile
    var maxSingleFileBytes: Long = 256L * 1024L * 1024L
        private set

    @Volatile
    private var configuredCacheDir: String? = null

    val cacheKeyFactory = CacheKeyFactory { dataSpec: DataSpec ->
        dataSpec.key ?: dataSpec.uri.toString()
    }

    fun configure(
        context: Context,
        enabled: Boolean,
        maxCacheBytes: Long,
        maxSingleFileBytes: Long,
        cacheDir: String?,
    ) {
        this.enabled = enabled
        this.maxCacheBytes = maxCacheBytes.coerceAtLeast(0L)
        this.maxSingleFileBytes = maxSingleFileBytes.coerceAtLeast(0L)
        if (!cacheDir.isNullOrBlank()) {
            this.configuredCacheDir = cacheDir
        }

        val entry = getOrCreateCacheEntry(context, cacheDir) ?: return
        entry.second.maxBytes = this.maxCacheBytes
        if (this.maxCacheBytes == 0L) {
            clearCache(context, cacheDir)
        } else {
            entry.second.evictNow(entry.first)
        }
    }

    fun pin(cacheKey: String?) {
        if (!cacheKey.isNullOrBlank()) {
            pinnedKeys.add(cacheKey)
        }
    }

    fun unpin(cacheKey: String?) {
        if (!cacheKey.isNullOrBlank()) {
            pinnedKeys.remove(cacheKey)
        }
    }

    fun buildHttpDataSourceFactory(headers: Map<String, String>? = null): DefaultHttpDataSource.Factory {
        val factory = DefaultHttpDataSource.Factory()
            .setUserAgent(DEFAULT_USER_AGENT)
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(15_000)
        if (!headers.isNullOrEmpty()) {
            val cleanHeaders = HashMap<String, String>()
            for ((k, v) in headers) {
                if (k.equals("user-agent", ignoreCase = true)) {
                    factory.setUserAgent(v)
                } else {
                    cleanHeaders[k] = v
                }
            }
            if (cleanHeaders.isNotEmpty()) {
                factory.setDefaultRequestProperties(cleanHeaders)
            }
        }
        return factory
    }

    fun buildDataSourceFactory(
        context: Context,
        headers: Map<String, String>? = null,
        enableCacheOverride: Boolean? = null,
    ): DataSource.Factory {
        val upstreamFactory = DefaultDataSource.Factory(
            context,
            buildHttpDataSourceFactory(headers),
        )
        val useCache = (enableCacheOverride ?: enabled) && maxCacheBytes > 0L && maxSingleFileBytes > 0L
        if (!useCache) {
            return upstreamFactory
        }

        val cache = getOrCreateCacheEntry(context, configuredCacheDir)?.first
            ?: return upstreamFactory

        // Keep contiguous files on disk where possible so MediaMetadataRetriever can inspect cached MP4s offline.
        val baseSinkFactory = CacheDataSink.Factory()
            .setCache(cache)
            .setFragmentSize(Long.MAX_VALUE)

        val boundedSinkFactory = androidx.media3.datasource.DataSink.Factory {
            val delegate = baseSinkFactory.createDataSink()
            object : androidx.media3.datasource.DataSink {
                override fun open(dataSpec: DataSpec) {
                    val limit = maxSingleFileBytes
                    if (limit <= 0L) {
                        throw IOException("Single file cache disabled")
                    }
                    if (dataSpec.length != C.LENGTH_UNSET.toLong() && dataSpec.length > limit) {
                        throw IOException("Media exceeds maxSingleFileBytes ($limit)")
                    }
                    val key = cacheKeyFactory.buildCacheKey(dataSpec)
                    val knownLen = ContentMetadata.getContentLength(cache.getContentMetadata(key))
                    if (knownLen != C.LENGTH_UNSET.toLong() && knownLen > limit) {
                        throw IOException("Media contentLength ($knownLen) exceeds maxSingleFileBytes ($limit)")
                    }
                    delegate.open(dataSpec)
                }

                override fun write(buffer: ByteArray, offset: Int, length: Int) {
                    delegate.write(buffer, offset, length)
                }

                override fun close() {
                    delegate.close()
                }
            }
        }

        return CacheDataSource.Factory()
            .setCache(cache)
            .setUpstreamDataSourceFactory(upstreamFactory)
            .setCacheReadDataSourceFactory(FileDataSource.Factory())
            .setCacheWriteDataSinkFactory(boundedSinkFactory)
            .setCacheKeyFactory(cacheKeyFactory)
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
    }

    fun precache(
        context: Context,
        executor: ExecutorService,
        url: String,
        cacheKey: String,
        cacheDir: String?,
        headers: Map<String, String>?,
        preloadBytes: Long?,
        onDone: () -> Unit,
    ) {
        if (!enabled || maxCacheBytes <= 0L || maxSingleFileBytes <= 0L) {
            onDone()
            return
        }
        val cache = getOrCreateCacheEntry(context, cacheDir)?.first ?: run {
            onDone()
            return
        }
        if (isCachedInternal(cache, cacheKey)) {
            onDone()
            return
        }
        if (activePrecacheWriters.containsKey(cacheKey)) {
            onDone()
            return
        }

        executor.execute {
            try {
                val maxLen = preloadBytes?.takeIf { it > 0L }?.coerceAtMost(maxSingleFileBytes)
                    ?: C.LENGTH_UNSET.toLong()
                val dataSpec = DataSpec.Builder()
                    .setUri(url.toUri())
                    .setKey(cacheKey)
                    .setPosition(0L)
                    .setLength(maxLen)
                    .build()

                val dsFactory = buildDataSourceFactory(
                    context = context,
                    headers = headers,
                    enableCacheOverride = true,
                ) as? CacheDataSource.Factory ?: return@execute

                val cacheDataSource = dsFactory.createDataSource()
                val writer = CacheWriter(
                    cacheDataSource,
                    dataSpec,
                    null,
                ) { requestLength, bytesCached, _ ->
                    if (bytesCached > maxSingleFileBytes ||
                        (requestLength != C.LENGTH_UNSET.toLong() && requestLength > maxSingleFileBytes)
                    ) {
                        activePrecacheWriters[cacheKey]?.cancel()
                    }
                }
                activePrecacheWriters[cacheKey] = writer
                writer.cache()
            } catch (_: Throwable) {
                // Quietly ignore cancellation or network failure during background precache.
            } finally {
                activePrecacheWriters.remove(cacheKey)
                onDone()
            }
        }
    }

    fun cancelPrecache(cacheKey: String) {
        activePrecacheWriters.remove(cacheKey)?.cancel()
    }

    fun isCached(context: Context, cacheDir: String?, cacheKey: String): Boolean {
        val cache = getOrCreateCacheEntry(context, cacheDir)?.first ?: return false
        return isCachedInternal(cache, cacheKey)
    }

    private fun isCachedInternal(cache: SimpleCache, cacheKey: String): Boolean {
        return try {
            val contentLength = ContentMetadata.getContentLength(cache.getContentMetadata(cacheKey))
            if (contentLength <= 0L) return false
            val cachedBytes = cache.getCachedBytes(cacheKey, 0L, contentLength)
            cachedBytes >= contentLength
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * 若 [cacheKey] 已作为单个完整连续文件缓存在磁盘中，返回该本地 [File] 供 `MediaMetadataRetriever` 离线抽帧/探测。
     */
    fun resolveCompleteCachedFile(context: Context, cacheKey: String?): File? {
        if (cacheKey.isNullOrBlank()) return null
        val cache = getOrCreateCacheEntry(context, configuredCacheDir)?.first ?: return null
        return try {
            val contentLength = ContentMetadata.getContentLength(cache.getContentMetadata(cacheKey))
            if (contentLength <= 0L) return null
            val spans = cache.getCachedSpans(cacheKey)
            if (spans.size == 1) {
                val span = spans.first()
                val f = span.file
                if (span.isCached && span.position == 0L && span.length >= contentLength && f != null && f.exists()) {
                    return f
                }
            }
            null
        } catch (_: Throwable) {
            null
        }
    }

    fun getCacheSize(context: Context, cacheDir: String?): Long {
        val cache = getOrCreateCacheEntry(context, cacheDir)?.first ?: return 0L
        return try {
            cache.cacheSpace.coerceAtLeast(0L)
        } catch (_: Throwable) {
            0L
        }
    }

    fun removeCache(context: Context, cacheDir: String?, cacheKey: String) {
        cancelPrecache(cacheKey)
        val cache = getOrCreateCacheEntry(context, cacheDir)?.first ?: return
        try {
            cache.removeResource(cacheKey)
        } catch (_: Throwable) {
        }
    }

    fun clearCache(context: Context, cacheDir: String?) {
        for ((_, writer) in activePrecacheWriters) {
            writer.cancel()
        }
        activePrecacheWriters.clear()

        val cache = getOrCreateCacheEntry(context, cacheDir)?.first ?: return
        try {
            val keys = HashSet(cache.keys)
            for (key in keys) {
                if (pinnedKeys.contains(key)) continue
                try {
                    cache.removeResource(key)
                } catch (_: Throwable) {
                }
            }
        } catch (_: Throwable) {
        }
    }

    private fun getOrCreateCacheEntry(
        context: Context,
        overrideDirPath: String?,
    ): Pair<SimpleCache, DynamicLruCacheEvictor>? {
        val appContext = context.applicationContext
        val basePath = overrideDirPath?.takeIf { it.isNotBlank() }
            ?: configuredCacheDir?.takeIf { it.isNotBlank() }
            ?: File(appContext.cacheDir, "xue_hua_navite_video_player/media_cache").absolutePath

        val exoDir = File(basePath, "exo_simple_cache")
        val canonical = try {
            exoDir.canonicalPath
        } catch (_: Throwable) {
            exoDir.absolutePath
        }

        synchronized(cacheLock) {
            cachesByCanonicalDir[canonical]?.let { return it }
            return try {
                if (!exoDir.exists()) {
                    exoDir.mkdirs()
                }
                val databaseProvider = dbProvider ?: StandaloneDatabaseProvider(appContext).also {
                    dbProvider = it
                }
                val evictor = DynamicLruCacheEvictor(maxCacheBytes) { key ->
                    pinnedKeys.contains(key)
                }
                val cache = SimpleCache(exoDir, evictor, databaseProvider)
                val pair = Pair(cache, evictor)
                cachesByCanonicalDir[canonical] = pair
                pair
            } catch (_: Throwable) {
                null
            }
        }
    }
}
