package ai.signora.ui

import androidx.camera.view.PreviewView
import androidx.compose.animation.*
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.*
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import ai.signora.models.*
import ai.signora.nlp.EnglishToIslResult
import ai.signora.recovery.AutoAssetManager
import ai.signora.speech.SpeechState
import ai.signora.ui.components.AppDestination
import ai.signora.ui.components.AppNavigationBar
import ai.signora.ui.components.AppNavigationRail
import ai.signora.ui.components.DesktopLogoButton
import ai.signora.ui.components.DesktopSidebar
import ai.signora.ui.components.SignoraIntro
import ai.signora.ui.screens.LearnScreen
import ai.signora.ui.screens.SettingsScreen
import ai.signora.ui.screens.TranslateScreen
import ai.signora.ui.theme.AppThemeMode

@Composable
fun SignoraScreen(
    previewView: PreviewView,
    hasCameraPermission: Boolean,
    onRequestCameraPermission: () -> Unit,
    debounceState: DebounceState,
    handLandmarks: List<HandLandmarks>,
    poseLandmarks: PoseLandmarks? = null,
    currentMode: RecognitionMode,
    dwellProfile: DwellProfile,
    isMuted: Boolean,
    isFrontCamera: Boolean,
    isTorchOn: Boolean = false,
    isPaused: Boolean = false,
    fps: Float = 30f,
    isDark: Boolean = true,
    themeMode: AppThemeMode = AppThemeMode.DARK,
    selectedPalette: ai.signora.ui.theme.AppPalette = ai.signora.ui.theme.AppPalette.WALLPAPER,
    dynamicColor: Boolean = true,
    desktopMode: Boolean = false,
    onDesktopModeChange: (Boolean) -> Unit = {},
    autoCollapseEnabled: Boolean = true,
    latestFrameId: Long = 0L,
    customDwellMs: Long = 1000L,
    confidenceThreshold: Float = 0.40f,
    minMargin: Float = 0.05f,
    cameraResolution: Pair<Int, Int> = Pair(480, 640),
    assetStatus: AutoAssetManager.AssetStatus,
    nlpState: NlpState = NlpState(),
    speechState: SpeechState = SpeechState.Idle,
    speechPartialText: String = "",
    speechSoundLevel: Float = 0f,
    speechTranslationResult: EnglishToIslResult? = null,
    onStartSpeechListening: () -> Unit = {},
    onStopSpeechListening: () -> Unit = {},
    onManualTranslateText: (String) -> Unit = {},
    onModeChange: (RecognitionMode) -> Unit,
    onDwellProfileChange: (DwellProfile) -> Unit,
    onCustomDwellChange: (Long) -> Unit = {},
    onConfidenceThresholdChange: (Float) -> Unit = {},
    onMinMarginChange: (Float) -> Unit = {},
    onAutoCollapseChange: (Boolean) -> Unit = {},
    onToggleMute: () -> Unit,
    onToggleCamera: () -> Unit,
    onToggleTorch: () -> Unit = {},
    onTogglePause: () -> Unit = {},
    onToggleTheme: () -> Unit = {},
    onThemeModeChange: (AppThemeMode) -> Unit = {},
    onPaletteChange: (ai.signora.ui.theme.AppPalette) -> Unit = {},
    onDynamicColorChange: (Boolean) -> Unit = {},
    onTestVoice: () -> Unit = {},
    onBackspace: () -> Unit,
    onClear: () -> Unit,
    onSpace: () -> Unit,
    onSpeak: () -> Unit,
    onReloadModels: () -> Unit = {},
    onAttachPreview: (PreviewView) -> Unit = {}
) {
    var currentDestination by remember { mutableStateOf(AppDestination.TRANSLATE) }
    var sidebarExpanded by remember { mutableStateOf(false) }

    val configuration = LocalConfiguration.current
    val isWideScreen = desktopMode ||
        configuration.screenWidthDp >= 600 ||
        configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE

    var showIntro by remember { mutableStateOf(true) }

    val desktopFocus = remember { FocusRequester() }
    LaunchedEffect(desktopMode) {
        if (desktopMode) {
            runCatching { desktopFocus.requestFocus() }
        } else {
            sidebarExpanded = false
        }
    }

    fun onDesktopKey(event: KeyEvent): Boolean {
        if (event.type != KeyEventType.KeyDown) return false
        if (event.isCtrlPressed) {
            val destination = when (event.key) {
                Key.One -> AppDestination.TRANSLATE
                Key.Two -> AppDestination.STUDIO
                Key.Three -> AppDestination.GAME
                Key.Four -> AppDestination.LEARN
                Key.Five -> AppDestination.SETTINGS
                else -> null
            }
            if (destination != null) {
                currentDestination = destination
                sidebarExpanded = false
                return true
            }
            return false
        }
        if (event.key == Key.Escape && sidebarExpanded) {
            sidebarExpanded = false
            return true
        }
        if (currentDestination != AppDestination.TRANSLATE) {
            if (event.key == Key.Escape) {
                currentDestination = AppDestination.TRANSLATE
                return true
            }
            return false
        }
        return when (event.key) {
            Key.Spacebar -> {
                onSpace()
                true
            }
            Key.Backspace, Key.Delete -> {
                onBackspace()
                true
            }
            Key.Enter -> {
                onSpeak()
                true
            }
            else -> false
        }
    }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(if (desktopMode) Color.Black else Color.Transparent)
    ) {
        // DeskStage renders into a true 16:9 stage. On a 20:9 phone this
        // pillarboxes instead of stretching the desktop layout.
        val stageWidth = if (desktopMode) minOf(maxWidth, maxHeight * 16f / 9f) else maxWidth
        val stageHeight = if (desktopMode) stageWidth * 9f / 16f else maxHeight

        Box(
            modifier = Modifier
                .align(Alignment.Center)
                .size(stageWidth, stageHeight)
        ) {
        Row(
            modifier = Modifier
                .fillMaxSize()
                .then(
                    if (desktopMode) {
                        Modifier
                            .focusRequester(desktopFocus)
                            .focusable()
                            .onKeyEvent { onDesktopKey(it) }
                    } else {
                        Modifier
                    }
                )
        ) {
            // DeskStage keeps the stage full-width; navigation lives in an
            // overlay drawer that collapses to the S badge.
            if (!desktopMode && isWideScreen) {
                AppNavigationRail(
                    currentDestination = currentDestination,
                    onNavigate = { currentDestination = it }
                )
            }

            Scaffold(
                bottomBar = {
                    if (!isWideScreen && !desktopMode) {
                        AppNavigationBar(
                            currentDestination = currentDestination,
                            onNavigate = { currentDestination = it }
                        )
                    }
                },
                containerColor = MaterialTheme.colorScheme.background,
                contentWindowInsets = WindowInsets(0, 0, 0, 0),
                modifier = Modifier.weight(1f)
            ) { innerPadding ->
                AnimatedContent(
                    targetState = currentDestination,
                    transitionSpec = {
                        val forward = targetState.ordinal >= initialState.ordinal
                        val dir = if (forward) 1 else -1
                        (slideInHorizontally(
                            animationSpec = spring(dampingRatio = 0.82f, stiffness = 380f),
                            initialOffsetX = { it / 5 * dir }
                        ) + fadeIn(tween(220)) + scaleIn(initialScale = 0.97f, animationSpec = tween(260))) togetherWith
                            (slideOutHorizontally(
                                animationSpec = tween(190, easing = FastOutLinearInEasing),
                                targetOffsetX = { -it / 8 * dir }
                            ) + fadeOut(tween(140)))
                    },
                    label = "ScreenTransition"
                ) { destination ->
                    when (destination) {
                        AppDestination.TRANSLATE -> {
                            TranslateScreen(
                                previewView = previewView,
                                hasCameraPermission = hasCameraPermission,
                                onRequestCameraPermission = onRequestCameraPermission,
                                debounceState = debounceState,
                                handLandmarks = handLandmarks,
                                poseLandmarks = poseLandmarks,
                                currentMode = currentMode,
                                isMuted = isMuted,
                                isFrontCamera = isFrontCamera,
                                isTorchOn = isTorchOn,
                                isPaused = isPaused,
                                fps = fps,
                                isDark = isDark,
                                autoCollapseEnabled = autoCollapseEnabled,
                                desktopMode = desktopMode,
                                latestFrameId = latestFrameId,
                                assetStatus = assetStatus,
                                nlpState = nlpState,
                                onModeChange = onModeChange,
                                onToggleMute = onToggleMute,
                                onToggleCamera = onToggleCamera,
                                onToggleTorch = onToggleTorch,
                                onTogglePause = onTogglePause,
                                onToggleTheme = onToggleTheme,
                                onOpenSettings = { currentDestination = AppDestination.SETTINGS },
                                onBackspace = onBackspace,
                                onClear = onClear,
                                onSpace = onSpace,
                                onSpeak = onSpeak,
                                cameraResolution = cameraResolution,
                                bottomBarPadding = innerPadding.calculateBottomPadding(),
                                speechState = speechState,
                                speechPartialText = speechPartialText,
                                speechSoundLevel = speechSoundLevel,
                                speechTranslationResult = speechTranslationResult,
                                onStartSpeechListening = onStartSpeechListening,
                                onStopSpeechListening = onStopSpeechListening,
                                onManualTranslateText = onManualTranslateText,
                                onAttachPreview = onAttachPreview
                            )
                        }


                        AppDestination.STUDIO -> {
                            ai.signora.ui.screens.TrainStudioScreen(
                                previewView = previewView,
                                hands = handLandmarks,
                                pose = poseLandmarks,
                                onToggleCamera = onToggleCamera,
                                cameraResolution = cameraResolution,
                                onReloadModels = onReloadModels,
                                bottomBarPadding = innerPadding.calculateBottomPadding(),
                                onAttachPreview = onAttachPreview
                            )
                        }

                        AppDestination.GAME -> {
                            ai.signora.ui.screens.DinoGameScreen(
                                previewView = previewView,
                                debounceState = debounceState,
                                handLandmarks = handLandmarks,
                                currentMode = currentMode,
                                onModeChange = onModeChange,
                                onToggleCamera = onToggleCamera,
                                onAttachPreview = onAttachPreview
                            )
                        }

                        AppDestination.LEARN -> {
                            LearnScreen(
                                currentMode = currentMode,
                                onModeChange = onModeChange,
                                debounceState = debounceState,
                                previewView = previewView,
                                desktopMode = desktopMode
                            )
                        }

                        AppDestination.SETTINGS -> {
                            SettingsScreen(
                                themeMode = themeMode,
                                selectedPalette = selectedPalette,
                                dynamicColor = dynamicColor,
                                dwellProfile = dwellProfile,
                                customDwellMs = customDwellMs,
                                confidenceThreshold = confidenceThreshold,
                                minMargin = minMargin,
                                isMuted = isMuted,
                                isFrontCamera = isFrontCamera,
                                autoCollapseEnabled = autoCollapseEnabled,
                                desktopMode = desktopMode,
                                bottomBarPadding = innerPadding.calculateBottomPadding(),
                                onDesktopModeChange = onDesktopModeChange,
                                onThemeModeChange = onThemeModeChange,
                                onPaletteChange = onPaletteChange,
                                onDynamicColorChange = onDynamicColorChange,
                                onDwellProfileChange = onDwellProfileChange,
                                onCustomDwellChange = onCustomDwellChange,
                                onConfidenceThresholdChange = onConfidenceThresholdChange,
                                onMinMarginChange = onMinMarginChange,
                                onAutoCollapseChange = onAutoCollapseChange,
                                onToggleMute = onToggleMute,
                                onToggleCamera = onToggleCamera,
                                onTestVoice = onTestVoice
                            )
                        }
                    }
                }
            }
        }

        if (desktopMode) {
            AnimatedVisibility(
                visible = sidebarExpanded,
                enter = fadeIn(tween(180)),
                exit = fadeOut(tween(160)),
                modifier = Modifier.fillMaxSize(),
                label = "DeskStageScrim"
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black.copy(alpha = 0.52f))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null
                        ) { sidebarExpanded = false }
                )
            }

            AnimatedVisibility(
                visible = sidebarExpanded,
                enter = slideInHorizontally(
                    animationSpec = spring(dampingRatio = 0.86f, stiffness = 420f),
                    initialOffsetX = { -it }
                ) + fadeIn(tween(140)),
                exit = slideOutHorizontally(
                    animationSpec = tween(180, easing = FastOutLinearInEasing),
                    targetOffsetX = { -it }
                ) + fadeOut(tween(140)),
                modifier = Modifier.align(Alignment.CenterStart),
                label = "DeskStageDrawer"
            ) {
                DesktopSidebar(
                    currentDestination = currentDestination,
                    onNavigate = { currentDestination = it },
                    onExitDeskStage = { onDesktopModeChange(false) },
                    onClose = { sidebarExpanded = false },
                    autoCollapseEnabled = autoCollapseEnabled,
                    onAutoCollapseChange = onAutoCollapseChange,
                    assetReady = assetStatus.isReady
                )
            }

            AnimatedVisibility(
                visible = !sidebarExpanded,
                enter = fadeIn(tween(180)) + scaleIn(
                    initialScale = 0.9f,
                    animationSpec = spring(dampingRatio = 0.8f, stiffness = 500f)
                ),
                exit = fadeOut(tween(120)) + scaleOut(
                    targetScale = 0.9f,
                    animationSpec = tween(140)
                ),
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(16.dp),
                label = "DeskStageLogo"
            ) {
                DesktopLogoButton(onClick = { sidebarExpanded = true })
            }
        }
        } // end 16:9 stage

        AnimatedVisibility(
            visible = showIntro,
            enter = EnterTransition.None,
            exit = fadeOut(tween(360)) + scaleOut(targetScale = 1.05f, animationSpec = tween(360)),
            label = "IntroOverlay"
        ) {
            SignoraIntro(onFinished = { showIntro = false })
        }
    }
}
