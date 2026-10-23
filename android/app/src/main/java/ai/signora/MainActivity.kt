package ai.signora

import android.Manifest
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.view.PreviewView
import androidx.compose.runtime.*
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import ai.signora.audio.SignAudio
import ai.signora.camera.CameraXManager
import ai.signora.engine.DebounceEngine
import ai.signora.ml.BodySegmentation
import ai.signora.ml.FeatureExtractor
import ai.signora.ml.SignoraMLP
import ai.signora.models.*
import ai.signora.nlp.EnglishToIslResult
import ai.signora.nlp.EnglishToIslSynthesizer
import ai.signora.nlp.GlossToken
import ai.signora.nlp.IslGrammarSynthesizer
import ai.signora.nlp.SentenceBuffer
import ai.signora.recovery.AutoAssetManager
import ai.signora.speech.SpeechState
import ai.signora.speech.SpeechToSignManager
import ai.signora.tts.SpeechManager
import ai.signora.profiler.TrackingProfiler
import ai.signora.ui.DeskStageMode
import ai.signora.ui.SignoraScreen
import ai.signora.ui.theme.AppThemeMode
import ai.signora.ui.theme.AppPalette
import ai.signora.ui.theme.SignoraTheme
import ai.signora.vision.HandLandmarkerHelper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {

    private lateinit var assetManager: AutoAssetManager
    private lateinit var speechManager: SpeechManager
    private lateinit var speechToSignManager: SpeechToSignManager
    private var cameraManager: CameraXManager? = null
    private var handHelper: HandLandmarkerHelper? = null
    private var poseHelper: ai.signora.vision.PoseLandmarkerHelper? = null

    private var aslMlp: SignoraMLP? = null
    private var islMlp: SignoraMLP? = null

    private val motionTracker = ai.signora.engine.HandMotionTracker(maxHistory = 30)
    private val debounceEngine = DebounceEngine(dwellMs = 1000L, threshold = 0.65f, minMargin = 0.08f, voteWindowSize = 7)

    // ── NLP Pipeline ─────────────────────────────────────────────────────────
    private var nlpState by mutableStateOf(NlpState())
    private val sentenceBuffer = SentenceBuffer(sentencePauseMs = 60000L) { /* Standard direct speech pipeline */ }

    private var hasCameraPermission by mutableStateOf(false)
    private var assetStatus by mutableStateOf(AutoAssetManager.AssetStatus(isReady = false, message = "Initializing..."))
    private var currentMode by mutableStateOf(RecognitionMode.ASL)
    private var dwellProfile by mutableStateOf(DwellProfile.STANDARD)
    private var customDwellMs by mutableStateOf(1000L)
    private var confidenceThreshold by mutableStateOf(0.65f)
    private var minMargin by mutableStateOf(0.08f)
    private var cameraResolution by mutableStateOf(Pair(480, 640))
    private var isMuted by mutableStateOf(false)
    private var isFrontCamera by mutableStateOf(true)
    private var isTorchOn by mutableStateOf(false)
    private var isPaused by mutableStateOf(false)
    private var autoCollapseEnabled by mutableStateOf(true)
    private var latestFrameId = 0L
    private var themeMode by mutableStateOf(AppThemeMode.DARK)
    private var selectedPalette by mutableStateOf(AppPalette.WALLPAPER)
    private var dynamicColorEnabled by mutableStateOf(true)
    private var deskStageEnabled by mutableStateOf(false)
    private var debounceState by mutableStateOf(DebounceState())
    private var activeLandmarks by mutableStateOf<List<HandLandmarks>>(emptyList())
    private var activePose by mutableStateOf<PoseLandmarks?>(null)
    @Volatile private var latestPose: PoseLandmarks? = null
    private var handsRestStartTimeMs = 0L
    private var lastLoggedLabel = ""

    private var frameCount = 0
    private var lastFpsTimestamp = System.currentTimeMillis()
    private var currentFps by mutableStateOf(30f)

    private lateinit var previewView: PreviewView

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasCameraPermission = granted
        if (granted) {
            setupVisionPipeline()
        }
    }

    private var hasAudioPermission by mutableStateOf(false)
    private val audioPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasAudioPermission = granted
        if (granted) {
            speechToSignManager.startListening()
        }
    }

    private var speechState by mutableStateOf<SpeechState>(SpeechState.Idle)
    private var speechPartialText by mutableStateOf("")
    private var speechSoundLevel by mutableStateOf(0f)
    private var speechTranslationResult by mutableStateOf<EnglishToIslResult?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        deskStageEnabled = DeskStageMode.isEnabled(this)
        applyDeskStageWindow(deskStageEnabled)

        assetManager = AutoAssetManager(this)
        speechManager = SpeechManager(this)
        speechToSignManager = SpeechToSignManager(this)

        lifecycleScope.launch {
            speechToSignManager.speechState.collect { state ->
                speechState = state
                if (state is SpeechState.Success) {
                    speechTranslationResult = EnglishToIslSynthesizer.translate(state.spokenText)
                }
            }
        }
        lifecycleScope.launch {
            speechToSignManager.partialText.collect { partial ->
                speechPartialText = partial
                if (partial.isNotBlank()) {
                    speechTranslationResult = EnglishToIslSynthesizer.translate(partial)
                }
            }
        }
        lifecycleScope.launch {
            speechToSignManager.soundLevel.collect { level ->
                speechSoundLevel = level
            }
        }

        previewView = PreviewView(this).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }

        setContent {
            SignoraTheme(
                themeMode = themeMode,
                selectedPalette = selectedPalette,
                dynamicColor = dynamicColorEnabled
            ) {
                SignoraScreen(
                    previewView = previewView,
                    hasCameraPermission = hasCameraPermission,
                    onRequestCameraPermission = { checkCameraPermission() },
                    debounceState = debounceState,
                    handLandmarks = activeLandmarks,
                    poseLandmarks = activePose,
                    currentMode = currentMode,
                    dwellProfile = dwellProfile,
                    isMuted = isMuted,
                    isFrontCamera = isFrontCamera,
                    isTorchOn = isTorchOn,
                    isPaused = isPaused,
                    fps = currentFps,
                    isDark = themeMode == AppThemeMode.DARK,
                    themeMode = themeMode,
                    selectedPalette = selectedPalette,
                    dynamicColor = dynamicColorEnabled,
                    desktopMode = deskStageEnabled,
                    onDesktopModeChange = { updateDeskStage(it) },
                    autoCollapseEnabled = autoCollapseEnabled,
                    latestFrameId = latestFrameId,
                    customDwellMs = customDwellMs,
                    confidenceThreshold = confidenceThreshold,
                    minMargin = minMargin,
                    cameraResolution = cameraResolution,
                    assetStatus = assetStatus,
                    nlpState = nlpState,
                    speechState = speechState,
                    speechPartialText = speechPartialText,
                    speechSoundLevel = speechSoundLevel,
                    speechTranslationResult = speechTranslationResult,
                    onStartSpeechListening = {
                        val granted = ContextCompat.checkSelfPermission(
                            this@MainActivity,
                            Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                        if (granted) {
                            hasAudioPermission = true
                            speechToSignManager.startListening()
                        } else {
                            audioPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        }
                    },
                    onStopSpeechListening = {
                        speechToSignManager.stopListening()
                    },
                    onManualTranslateText = { text ->
                        speechTranslationResult = EnglishToIslSynthesizer.translate(text)
                    },
                    onModeChange = { newMode ->
                        currentMode = newMode
                        debounceEngine.clear()
                        sentenceBuffer.clear()
                        nlpState = NlpState()
                        debounceState = debounceState.copy(candidate = "", confidence = 0f, dwellProgress = 0f)
                    },
                    onDwellProfileChange = { newProfile ->
                        dwellProfile = newProfile
                        customDwellMs = newProfile.dwellMs
                        debounceEngine.dwellMs = newProfile.dwellMs
                    },
                    onCustomDwellChange = { ms ->
                        customDwellMs = ms
                        debounceEngine.dwellMs = ms
                    },
                    onConfidenceThresholdChange = { conf ->
                        confidenceThreshold = conf
                        debounceEngine.confidenceThreshold = conf
                    },
                    onMinMarginChange = { margin ->
                        minMargin = margin
                        debounceEngine.minMargin = margin
                    },
                    onAutoCollapseChange = { autoCollapseEnabled = it },
                    onToggleMute = {
                        isMuted = !isMuted
                        speechManager.isMuted = isMuted
                    },
                    onToggleCamera = {
                        cameraManager?.toggleCamera()
                        isFrontCamera = cameraManager?.isFrontCamera ?: true
                        isTorchOn = false
                    },
                    onToggleTorch = {
                        isTorchOn = cameraManager?.toggleTorch() ?: false
                    },
                    onTogglePause = {
                        isPaused = !isPaused
                        cameraManager?.isPaused = isPaused
                    },
                    onToggleTheme = {
                        themeMode = if (themeMode == AppThemeMode.DARK) AppThemeMode.LIGHT else AppThemeMode.DARK
                    },
                    onThemeModeChange = { themeMode = it },
                    onPaletteChange = { selectedPalette = it },
                    onDynamicColorChange = { dynamicColorEnabled = it },
                    onTestVoice = {
                        speechManager.speak("Testing speech synthesis")
                    },
                    onBackspace = {
                        debounceEngine.backspace()
                        sentenceBuffer.pop()
                        val pending = sentenceBuffer.peek().map { it.label }
                        nlpState = nlpState.copy(pendingGlosses = pending)
                        debounceState = debounceState.copy(transcript = debounceEngine.getTranscript())
                    },
                    onClear = {
                        debounceEngine.clear()
                        sentenceBuffer.clear()
                        nlpState = NlpState()
                        debounceState = debounceState.copy(transcript = "")
                    },
                    onSpace = {
                        val state = debounceEngine.update(RecognitionResult("SPACE", 0.99f))
                        debounceState = state
                    },
                    onSpeak = {
                        val formatted = DebounceEngine.formatTranscriptForDisplay(debounceEngine.getTranscript())
                        if (formatted.isNotBlank()) {
                            speechManager.speak(formatted)
                        }
                    },
                    onReloadModels = {
                        lifecycleScope.launch {
                            loadNeuralEngines()
                        }
                    },
                    onAttachPreview = { view ->
                        cameraManager?.attachPreviewView(view)
                    }
                )

            }
        }

        // 1. Immediately verify and prompt for camera permission on startup
        checkCameraPermission()

        // 2. Initialize and self-heal model assets in background
        lifecycleScope.launch {
            val ok = assetManager.ensureModelAssets { status ->
                assetStatus = status
            }
            if (ok) {
                loadNeuralEngines()
                if (hasCameraPermission && cameraManager == null) {
                    setupVisionPipeline()
                }
            }
        }
    }

    private suspend fun loadNeuralEngines() = withContext(Dispatchers.Default) {
        try {
            val aslJson = assetManager.loadModelJsonString("asl_model.json")
            aslMlp = SignoraMLP.fromJson(aslJson)

            val islJson = assetManager.loadModelJsonString("isl_model.json")
            islMlp = SignoraMLP.fromJson(islJson)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun updateDeskStage(enabled: Boolean) {
        if (deskStageEnabled == enabled) return
        deskStageEnabled = enabled
        DeskStageMode.setEnabled(this, enabled)
        applyDeskStageWindow(enabled)
    }

    private fun applyDeskStageWindow(enabled: Boolean) {
        requestedOrientation = if (enabled) {
            ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        } else {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }

        val controller = WindowCompat.getInsetsController(window, window.decorView)
        if (enabled) {
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(WindowInsetsCompat.Type.systemBars())
        } else {
            controller.show(WindowInsetsCompat.Type.systemBars())
        }

        // requestedOrientation applies asynchronously; resync once the view has
        // been laid out in the new orientation.
        window.decorView.post {
            if (::previewView.isInitialized) {
                previewView.display?.rotation?.let { cameraManager?.updateTargetRotation(it) }
            }
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        window.decorView.post {
            if (::previewView.isInitialized) {
                previewView.display?.rotation?.let { cameraManager?.updateTargetRotation(it) }
            }
        }
    }

    private fun checkCameraPermission() {
        val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        hasCameraPermission = granted
        if (granted) {
            setupVisionPipeline()
        } else {
            permissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    private fun setupVisionPipeline() {
        if (cameraManager != null) return

        val landmarkerTaskFile = assetManager.getModelFile("hand_landmarker.task")
        val poseTaskFile = assetManager.getModelFile("pose_landmarker.task")

        handHelper = HandLandmarkerHelper(
            context = this,
            modelFile = landmarkerTaskFile,
            onResults = { hands, frameId, timestamp ->
                onHandsDetected(hands, frameId, timestamp)
            },
            onError = { _ ->
                // Vision pipeline logging
            }
        )

        poseHelper = ai.signora.vision.PoseLandmarkerHelper(
            context = this,
            modelFile = poseTaskFile,
            onResults = { pose, _, _ ->
                latestPose = pose
                runOnUiThread {
                    androidx.compose.runtime.snapshots.Snapshot.withMutableSnapshot {
                        activePose = pose
                    }
                }
            },
            onError = { msg -> android.util.Log.w("SignoraPose", msg) }
        )

        cameraManager = CameraXManager(
            context = this,
            lifecycleOwner = this,
            previewView = previewView,
            onFrame = { handImage, poseImage, rotationDegrees, isFront, frameId, frameTime ->
                handHelper?.detectLiveStream(handImage, rotationDegrees, isFront, frameId, frameTime)
                poseHelper?.detectLiveStream(poseImage, rotationDegrees, isFront, frameId, frameTime)
            }
        ).apply {
            onResolutionChanged = { w, h ->
                runOnUiThread {
                    cameraResolution = Pair(w, h)
                }
            }
        }
        cameraManager?.startCamera()
    }

    private fun onHandsDetected(hands: List<HandLandmarks>, frameId: Long, timestamp: Long) {
        if (isPaused) return

        latestFrameId = frameId

        // Calculate real-time FPS (throttled to at most once per second)
        frameCount++
        val now = System.currentTimeMillis()
        var newFps: Float? = null
        if (now - lastFpsTimestamp >= 1000L) {
            newFps = frameCount * 1000f / (now - lastFpsTimestamp)
            frameCount = 0
            lastFpsTimestamp = now
        }

        // Tick NLP boundary timer every frame regardless of momentary hand dropout
        sentenceBuffer.tick(now)

        // Kinetic rest-pose auto-commit: wrists dropped below chest (y > 0.82) or hands absent for >= 500 ms
        val isHandsAtRest = if (hands.isEmpty()) {
            true
        } else {
            val pt0 = hands[0].points.firstOrNull()
            pt0 != null && pt0.y > 0.82f
        }

        if (isHandsAtRest) {
            if (handsRestStartTimeMs == 0L) {
                handsRestStartTimeMs = now
            } else if ((now - handsRestStartTimeMs) >= 500L && sentenceBuffer.peek().isNotEmpty() && !sentenceBuffer.isFinalizedState) {
                sentenceBuffer.flush()
            }
        } else {
            handsRestStartTimeMs = 0L
        }

        if (hands.isEmpty()) {
            val emptyDebounce = debounceEngine.update(null, now).copy(fps = currentFps)
            TrackingProfiler.onVoteDwellDone(frameId)
            androidx.compose.runtime.snapshots.Snapshot.withMutableSnapshot {
                activeLandmarks = emptyList()
                debounceState = emptyDebounce
                if (newFps != null) currentFps = newFps
            }
            TrackingProfiler.onUiStateEmitted(frameId)
            return
        }

        // Extract features based on active mode
        val activeMlp = if (currentMode == RecognitionMode.ASL) aslMlp else islMlp
        if (activeMlp == null) {
            androidx.compose.runtime.snapshots.Snapshot.withMutableSnapshot {
                activeLandmarks = hands
                if (newFps != null) currentFps = newFps
            }
            TrackingProfiler.onUiStateEmitted(frameId)
            return
        }

        val currentPose = latestPose ?: activePose
        val feats = if (currentMode == RecognitionMode.ASL) {
            if (hands.size == 1) {
                FeatureExtractor.extractAslFeatures(hands[0].points, hands[0].isRightHand)
            } else {
                // If multiple hands, evaluate both and pick whichever hand produces higher confidence
                val f0 = FeatureExtractor.extractAslFeatures(hands[0].points, hands[0].isRightHand)
                val f1 = FeatureExtractor.extractAslFeatures(hands[1].points, hands[1].isRightHand)
                val r0 = activeMlp.predict(f0)
                val r1 = activeMlp.predict(f1)
                if ((r1?.confidence ?: 0f) > (r0?.confidence ?: 0f)) f1 else f0
            }
        } else {
            if (activeMlp.inDim == 220) {
                FeatureExtractor.extractSpatialFeatures(hands, currentPose)
            } else {
                FeatureExtractor.extractIslFeatures(hands)
            }
        }
        TrackingProfiler.onFeaturesExtracted(frameId)

        val activeSegs = BodySegmentation.detectActiveSegments(hands, currentPose)
        val activeAnchor = activeSegs.firstOrNull()?.id

        // Motion tracking for dynamic gesture recognition
        val rHand = hands.firstOrNull { it.isRightHand } ?: hands.firstOrNull()
        val lHand = if (hands.size > 1) hands.firstOrNull { !it.isRightHand && it != rHand } ?: hands.getOrNull(1) else null
        val rWrist = rHand?.points?.firstOrNull()?.let { Pair(it.x, it.y) }
        val lWrist = if (lHand != null && lHand != rHand) lHand.points.firstOrNull()?.let { Pair(it.x, it.y) } else null
        val motionState = motionTracker.update(
            rightWrist = rWrist,
            leftWrist = lWrist,
            timestampMs = now,
            rightHandLandmarks = rHand?.points,
            leftHandLandmarks = lHand?.points,
            activeAnchorZone = activeAnchor,
            poseLandmarks = currentPose?.points
        )

        // Run sub-ms neural forward pass
        val rawResult = activeMlp.predict(feats)
        TrackingProfiler.onMlpDone(frameId)

        if (rawResult.label != lastLoggedLabel && rawResult.top3.isNotEmpty()) {
            lastLoggedLabel = rawResult.label
            android.util.Log.d(
                "SignoraML",
                "${currentMode.name} top3=" + rawResult.top3.joinToString(" ") {
                    "${it.first}=${(it.second * 100).toInt()}%"
                } + " hands=${hands.size} right=${hands.firstOrNull()?.isRightHand}" +
                    " motion=${motionState.detectedGesture ?: "-"}:${(motionState.gestureConfidence * 100).toInt()}%" +
                    " speed=${(motionState.speed * 100).toInt() / 100f} pattern=${motionState.pattern}"
            )
        }

        // Dynamic motion gestures are a fallback only. A deliberate ISL motion
        // phrase (chest tap, wave, etc.) may override a static word, but never a
        // confidently detected single letter.
        val staticIsLetter = rawResult.label.length == 1
        val result = if (
            currentMode == RecognitionMode.ISL &&
            motionState.isMoving &&
            motionState.detectedGesture != null &&
            motionState.gestureConfidence >= 0.85f &&
            (!staticIsLetter || rawResult.confidence < 0.45f)
        ) {
            RecognitionResult(
                label = motionState.detectedGesture,
                confidence = motionState.gestureConfidence,
                margin = 0.50f,
                top3 = listOf(Pair(motionState.detectedGesture, motionState.gestureConfidence))
            )
        } else {
            rawResult
        }

        // Debounce and dwell tracking
        val handLandmarks = if (hands.isNotEmpty()) hands[0].points else null
        val newState = debounceEngine.update(result, now, handLandmarks, isMoving = motionState.isMoving).copy(fps = currentFps)
        TrackingProfiler.onVoteDwellDone(frameId)

        // ── Token push and immediate TTS voice playback on sign confirmation ──
        var updatedNlpState: NlpState? = null
        if (newState.confirmed && newState.lastConfirmed.isNotBlank() && newState.lastConfirmed != "SPACE") {
            // Consume dynamic gesture trajectory to prevent trailing repeat
            if (DebounceEngine.isMotionSign(newState.lastConfirmed)) {
                motionTracker.consumeGesture(now)
            }

            val confirmedLabel = DebounceEngine.cleanLabel(newState.lastConfirmed)
            val spokenText = DebounceEngine.formatDisplayText(confirmedLabel)

            // Immediate audio feedback: play the sign's bundled clip if it has one,
            // otherwise fall back to TTS
            if (!isMuted) {
                if (SignAudio.hasCue(confirmedLabel)) {
                    runOnUiThread { SignAudio.play(this@MainActivity, confirmedLabel) }
                } else {
                    speechManager.speak(spokenText)
                }
            }

            if (currentMode == RecognitionMode.ISL) {
                val bodyAnchor = activeSegs.joinToString("+") { it.id }.ifBlank { "" }
                val token = GlossToken(
                    label = confirmedLabel,
                    bodyAnchor = bodyAnchor,
                    timestamp = now,
                    confidence = newState.confidence
                )
                sentenceBuffer.push(token)
                val pending = sentenceBuffer.peek().map { it.label }
                updatedNlpState = nlpState.copy(
                    pendingGlosses = pending
                )
            }
        }

        // Atomically batch Compose snapshot state mutations in a single apply pass
        androidx.compose.runtime.snapshots.Snapshot.withMutableSnapshot {
            activeLandmarks = hands
            debounceState = newState
            if (newFps != null) currentFps = newFps
            if (updatedNlpState != null) nlpState = updatedNlpState
        }
        TrackingProfiler.onUiStateEmitted(frameId)
    }

    override fun onResume() {
        super.onResume()
        if (::previewView.isInitialized) {
            cameraManager?.attachPreviewView(previewView)
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && deskStageEnabled) {
            WindowCompat.getInsetsController(window, window.decorView)
                .hide(WindowInsetsCompat.Type.systemBars())
        }
    }

    override fun onPause() {
        super.onPause()
        if (::speechManager.isInitialized) {
            speechManager.stop()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        cameraManager?.stopCamera()
        handHelper?.close()
        poseHelper?.close()
        speechManager.shutdown()
        speechToSignManager.destroy()
    }
}
