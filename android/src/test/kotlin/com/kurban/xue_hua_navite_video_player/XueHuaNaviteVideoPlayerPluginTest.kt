package com.kurban.xue_hua_navite_video_player

import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain

/*
 * Unit tests for the Android Pigeon PlayerHostApi implementation.
 *
 * Run with `./gradlew testDebugUnitTest` inside `example/android/`.
 */

@OptIn(ExperimentalCoroutinesApi::class)
internal class XueHuaNaviteVideoPlayerPluginTest {
    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun playWithoutCreate_throwsNoPlayer() {
        val plugin = XueHuaNaviteVideoPlayerPlugin()
        val error = assertFailsWith<FlutterError> {
            plugin.play()
        }
        assertEquals("NO_PLAYER", error.code)
        assertEquals("Player not initialized", error.message)
    }

    @Test
    fun openWithoutCreate_throwsNoPlayer() = runTest(testDispatcher) {
        val plugin = XueHuaNaviteVideoPlayerPlugin()
        val error = assertFailsWith<FlutterError> {
            plugin.open(OpenMediaRequest(url = "https://example.com/video.mp4"))
        }
        assertEquals("NO_PLAYER", error.code)
        assertEquals("Player not initialized", error.message)
    }

    @Test
    fun controlMethodsWithoutCreate_throwNoPlayer() {
        val plugin = XueHuaNaviteVideoPlayerPlugin()
        assertEquals("NO_PLAYER", assertFailsWith<FlutterError> { plugin.pause() }.code)
        assertEquals("NO_PLAYER", assertFailsWith<FlutterError> { plugin.seek(1000L) }.code)
        assertEquals("NO_PLAYER", assertFailsWith<FlutterError> { plugin.setVolume(0.5) }.code)
        assertEquals("NO_PLAYER", assertFailsWith<FlutterError> { plugin.setSpeed(1.5) }.code)
    }

    @Test
    fun showCastPickerAndStopCastingWithoutActivity_completeGracefully() {
        val plugin = XueHuaNaviteVideoPlayerPlugin()
        plugin.showCastPicker()
        plugin.stopCasting()
    }

    @Test
    fun getBrightnessWithoutActivity_returnsDefaultOne() {
        val plugin = XueHuaNaviteVideoPlayerPlugin()
        assertEquals(1.0, plugin.getBrightness())
    }

    @Test
    fun openWithEmptyUrl_throwsInvalidArg() = runTest(testDispatcher) {
        val plugin = XueHuaNaviteVideoPlayerPlugin()
        val error = assertFailsWith<FlutterError> {
            plugin.open(OpenMediaRequest(url = ""))
        }
        assertEquals("INVALID_ARG", error.code)
        assertEquals("url is required", error.message)
    }

    @Test
    fun openGeneration_invalidatesStaleOpenOnSupersedeAndDispose() {
        val plugin = XueHuaNaviteVideoPlayerPlugin()
        val engineGen = plugin.currentEngineGenerationForTest()
        val firstGen = plugin.bumpOpenGenerationForTest()
        assertTrue(plugin.isOpenGenerationValid(firstGen, engineGen))

        val secondGen = plugin.bumpOpenGenerationForTest()
        assertFalse(plugin.isOpenGenerationValid(firstGen, engineGen))
        assertTrue(plugin.isOpenGenerationValid(secondGen, engineGen))

        plugin.dispose()
        assertFalse(plugin.isOpenGenerationValid(secondGen, engineGen))
    }

    @Test
    fun eventLoop_deliversQueuedEventsInStrictFifoOrder() = runTest(testDispatcher) {
        val plugin = XueHuaNaviteVideoPlayerPlugin()
        val delivered = ArrayList<PlayerEventData>()
        val job = plugin.startEventLoop(this) { event ->
            delivered.add(event)
        }

        plugin.enqueueEventForTest(
            PlayerEventData(
                kind = NativePlayerEventType.CAST_STATE,
                castState = NativeCastState.NOT_CONNECTED,
            )
        )
        plugin.enqueueEventForTest(
            PlayerEventData(kind = NativePlayerEventType.DURATION, intValue = 12_000L)
        )
        plugin.enqueueEventForTest(
            PlayerEventData(kind = NativePlayerEventType.BUFFERING, boolValue = true)
        )
        plugin.enqueueEventForTest(
            PlayerEventData(kind = NativePlayerEventType.PLAYING, boolValue = true)
        )
        for (i in 0..9) {
            plugin.enqueueEventForTest(
                PlayerEventData(kind = NativePlayerEventType.POSITION, intValue = i * 200L)
            )
        }
        plugin.enqueueEventForTest(PlayerEventData(kind = NativePlayerEventType.COMPLETED))

        advanceUntilIdle()
        job.cancel()

        assertEquals(15, delivered.size)
        assertEquals(NativePlayerEventType.CAST_STATE, delivered[0].kind)
        assertEquals(NativePlayerEventType.DURATION, delivered[1].kind)
        assertEquals(12_000L, delivered[1].intValue)
        assertEquals(NativePlayerEventType.BUFFERING, delivered[2].kind)
        assertEquals(true, delivered[2].boolValue)
        assertEquals(NativePlayerEventType.PLAYING, delivered[3].kind)
        assertEquals(true, delivered[3].boolValue)
        for (i in 0..9) {
            val posEvent = delivered[4 + i]
            assertEquals(NativePlayerEventType.POSITION, posEvent.kind)
            assertEquals(i * 200L, posEvent.intValue)
        }
        assertEquals(NativePlayerEventType.COMPLETED, delivered[14].kind)
    }
}
