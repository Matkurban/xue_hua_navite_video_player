package com.kurban.xue_hua_navite_video_player

import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
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
}
