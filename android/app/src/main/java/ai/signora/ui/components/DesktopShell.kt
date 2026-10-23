package ai.signora.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Backspace
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CloseFullscreen
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.SpaceBar
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ai.signora.engine.DebounceEngine
import ai.signora.models.DebounceState
import ai.signora.models.DwellStatus
import ai.signora.models.NlpState
import ai.signora.models.RecognitionMode
import ai.signora.ui.theme.AppTheme

private val DESKTOP_SHORTCUTS = listOf("Ctrl 1", "Ctrl 2", "Ctrl 3", "Ctrl 4", "Ctrl 5")

/**
 * DeskStage navigation drawer. It is intentionally an overlay rather than a
 * layout column: the stage keeps the full widescreen width and the drawer
 * slides over it, then disappears into the S badge in the top-right corner.
 */
@Composable
fun DesktopSidebar(
    currentDestination: AppDestination,
    onNavigate: (AppDestination) -> Unit,
    onExitDeskStage: () -> Unit,
    onClose: () -> Unit,
    autoCollapseEnabled: Boolean,
    onAutoCollapseChange: (Boolean) -> Unit,
    assetReady: Boolean,
    modifier: Modifier = Modifier
) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        contentColor = MaterialTheme.colorScheme.onSurface,
        shape = RoundedCornerShape(topEnd = 28.dp, bottomEnd = 28.dp),
        shadowElevation = 20.dp,
        modifier = modifier
    ) {
        Column(
            modifier = Modifier
                .fillMaxHeight()
                .width(268.dp)
                .padding(horizontal = 16.dp, vertical = 20.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(46.dp)
                        .clip(RoundedCornerShape(15.dp))
                        .background(MaterialTheme.colorScheme.primary),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "S",
                        style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Black),
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                }
                Spacer(modifier = Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Signora",
                        style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Black),
                        maxLines = 1
                    )
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(6.dp)
                                .background(
                                    if (assetReady) AppTheme.semantic.success
                                    else MaterialTheme.colorScheme.tertiary,
                                    CircleShape
                                )
                        )
                        Text(
                            text = if (assetReady) "DeskStage · live" else "DeskStage · loading",
                            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                IconButton(onClick = onClose, modifier = Modifier.size(36.dp)) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Close menu",
                        modifier = Modifier.size(18.dp)
                    )
                }
            }

            Spacer(modifier = Modifier.height(28.dp))
            Text(
                text = "WORKSPACE",
                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.65f),
                modifier = Modifier.padding(horizontal = 12.dp)
            )
            Spacer(modifier = Modifier.height(8.dp))

            AppDestination.values().forEachIndexed { index, destination ->
                DesktopNavItem(
                    destination = destination,
                    selected = currentDestination == destination,
                    shortcut = DESKTOP_SHORTCUTS.getOrElse(index) { "" },
                    onClick = {
                        onNavigate(destination)
                        onClose()
                    }
                )
                Spacer(modifier = Modifier.height(2.dp))
            }

            Spacer(modifier = Modifier.weight(1f))

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f))
            Spacer(modifier = Modifier.height(10.dp))

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .clickable { onAutoCollapseChange(!autoCollapseEnabled) }
                    .padding(horizontal = 8.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.TouchApp,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(18.dp)
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Compact while signing",
                        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold)
                    )
                    Text(
                        text = "Hide the command bar when a hand appears",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Switch(
                    checked = autoCollapseEnabled,
                    onCheckedChange = onAutoCollapseChange
                )
            }

            Spacer(modifier = Modifier.height(10.dp))
            OutlinedButton(
                onClick = onExitDeskStage,
                shape = RoundedCornerShape(14.dp),
                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 10.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(
                    imageVector = Icons.Default.CloseFullscreen,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text("Exit DeskStage", style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}

@Composable
fun DesktopLogoButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(15.dp),
        color = MaterialTheme.colorScheme.primary,
        contentColor = MaterialTheme.colorScheme.onPrimary,
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.18f)),
        shadowElevation = 12.dp,
        modifier = modifier.size(46.dp)
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                text = "S",
                style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Black)
            )
        }
    }
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun DesktopNavItem(
    destination: AppDestination,
    selected: Boolean,
    shortcut: String,
    onClick: () -> Unit
) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    val background by androidx.compose.animation.animateColorAsState(
        targetValue = when {
            selected -> MaterialTheme.colorScheme.primaryContainer
            hovered -> MaterialTheme.colorScheme.surfaceContainerHighest
            else -> Color.Transparent
        },
        animationSpec = androidx.compose.animation.core.tween(140),
        label = "DesktopNavHover"
    )
    val foreground = if (selected) {
        MaterialTheme.colorScheme.onPrimaryContainer
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }

    Surface(
        shape = RoundedCornerShape(13.dp),
        color = background,
        contentColor = foreground,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .hoverable(interaction)
            .pointerHoverIcon(PointerIcon.Hand)
            .clickable(
                interactionSource = interaction,
                indication = null,
                onClick = onClick
            )
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(
                imageVector = if (selected) destination.selectedIcon else destination.unselectedIcon,
                contentDescription = destination.title,
                modifier = Modifier.size(21.dp)
            )
            Text(
                text = destination.title,
                style = MaterialTheme.typography.bodyMedium.copy(
                    fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium
                ),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            Text(
                text = shortcut,
                style = MaterialTheme.typography.labelSmall,
                color = foreground.copy(alpha = 0.5f)
            )
        }
    }
}

/**
 * DeskStage command bar. Idle state is a single wide strip; as soon as a hand
 * is present it collapses into the same floating pill + speak button used by
 * the phone build, keeping the stage unobstructed while signing.
 */
@Composable
fun DesktopCommandBar(
    shouldCollapse: Boolean,
    debounceState: DebounceState,
    nlpState: NlpState,
    currentMode: RecognitionMode,
    activeAnchorZone: String,
    onPinExpanded: () -> Unit,
    onSpace: () -> Unit,
    onBackspace: () -> Unit,
    onClear: () -> Unit,
    onSpeak: () -> Unit,
    onOpenSpeechToSign: () -> Unit,
    modifier: Modifier = Modifier
) {
    val collapseProgress by animateFloatAsState(
        targetValue = if (shouldCollapse) 1f else 0f,
        animationSpec = spring(dampingRatio = 0.82f, stiffness = 420f),
        label = "DesktopBarCollapse"
    )

    val hasTranscript = debounceState.transcript.isNotBlank()

    Box(
        modifier = modifier,
        contentAlignment = Alignment.BottomCenter
    ) {
        if (collapseProgress < 0.99f) {
            Surface(
                shape = RoundedCornerShape(24.dp),
                color = MaterialTheme.colorScheme.surfaceContainer.copy(alpha = 0.96f),
                contentColor = MaterialTheme.colorScheme.onSurface,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)),
                shadowElevation = 14.dp,
                modifier = Modifier
                    .fillMaxWidth()
                    .graphicsLayer {
                        alpha = 1f - collapseProgress
                        translationY = collapseProgress * 24f
                        scaleY = 1f - collapseProgress * 0.06f
                    }
            ) {
                Row(
                    modifier = Modifier.padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    CompactSignBadge(
                        candidate = debounceState.candidate,
                        confidence = debounceState.confidence,
                        dwellProgressProvider = { debounceState.dwellProgress },
                        status = debounceState.status,
                        modifier = Modifier.size(64.dp)
                    )

                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Text(
                                text = "LIVE · ${currentMode.displayName}",
                                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                                color = MaterialTheme.colorScheme.primary
                            )
                            if (activeAnchorZone != "OPEN_SPACE") {
                                Surface(
                                    shape = RoundedCornerShape(6.dp),
                                    color = AppTheme.semantic.success.copy(alpha = 0.14f)
                                ) {
                                    Text(
                                        text = activeAnchorZone,
                                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                                        color = AppTheme.semantic.success,
                                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 1.dp)
                                    )
                                }
                            }
                            Spacer(modifier = Modifier.weight(1f))
                            Text(
                                text = "${(debounceState.confidence * 100).toInt()}%",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }

                        Text(
                            text = if (hasTranscript) {
                                DebounceEngine.formatTranscriptForDisplay(debounceState.transcript)
                            } else {
                                "Sign with your hands…"
                            },
                            style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
                            color = if (hasTranscript) MaterialTheme.colorScheme.onSurface
                            else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.65f),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )

                        Text(
                            text = subtitleFor(debounceState, nlpState),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }

                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        IconButton(onClick = onSpace, modifier = Modifier.size(38.dp)) {
                            Icon(Icons.Default.SpaceBar, "Insert space", modifier = Modifier.size(18.dp))
                        }
                        IconButton(
                            onClick = onBackspace,
                            enabled = hasTranscript,
                            modifier = Modifier.size(38.dp)
                        ) {
                            Icon(
                                Icons.AutoMirrored.Filled.Backspace,
                                "Delete last",
                                modifier = Modifier.size(18.dp)
                            )
                        }
                        IconButton(
                            onClick = onClear,
                            enabled = hasTranscript,
                            modifier = Modifier.size(38.dp)
                        ) {
                            Icon(
                                Icons.Default.DeleteOutline,
                                "Clear transcript",
                                tint = if (hasTranscript) MaterialTheme.colorScheme.error
                                else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.35f),
                                modifier = Modifier.size(18.dp)
                            )
                        }
                        IconButton(onClick = onOpenSpeechToSign, modifier = Modifier.size(38.dp)) {
                            Icon(
                                Icons.Default.RecordVoiceOver,
                                "Speech to sign",
                                tint = AppTheme.semantic.success,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }

                    FilledIconButton(
                        onClick = onSpeak,
                        enabled = hasTranscript,
                        shape = RoundedCornerShape(18.dp),
                        modifier = Modifier.size(54.dp)
                    ) {
                        Icon(
                            Icons.AutoMirrored.Filled.VolumeUp,
                            "Speak transcript",
                            modifier = Modifier.size(24.dp)
                        )
                    }
                }
            }
        }

        if (collapseProgress > 0.01f) {
            Row(
                modifier = Modifier
                    .height(72.dp)
                    .graphicsLayer {
                        alpha = collapseProgress
                        scaleX = 0.96f + collapseProgress * 0.04f
                        scaleY = 0.96f + collapseProgress * 0.04f
                        translationY = (1f - collapseProgress) * 18f
                    },
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Surface(
                    onClick = onPinExpanded,
                    shape = RoundedCornerShape(26.dp),
                    color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.96f),
                    contentColor = MaterialTheme.colorScheme.onSurface,
                    shadowElevation = 10.dp,
                    modifier = Modifier.fillMaxHeight()
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxHeight()
                            .padding(horizontal = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        CompactSignBadge(
                            candidate = debounceState.candidate,
                            confidence = debounceState.confidence,
                            dwellProgressProvider = { debounceState.dwellProgress },
                            status = debounceState.status,
                            modifier = Modifier.size(48.dp)
                        )

                        Text(
                            text = if (hasTranscript) {
                                DebounceEngine.formatTranscriptForDisplay(debounceState.transcript)
                            } else {
                                "Listening…"
                            },
                            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Medium),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.widthIn(max = 220.dp)
                        )

                        IconButton(onClick = onSpace, modifier = Modifier.size(36.dp)) {
                            Icon(Icons.Default.SpaceBar, "Insert space", modifier = Modifier.size(17.dp))
                        }
                        IconButton(
                            onClick = onBackspace,
                            enabled = hasTranscript,
                            modifier = Modifier.size(36.dp)
                        ) {
                            Icon(
                                Icons.AutoMirrored.Filled.Backspace,
                                "Delete last",
                                modifier = Modifier.size(17.dp)
                            )
                        }
                        IconButton(
                            onClick = onClear,
                            enabled = hasTranscript,
                            modifier = Modifier.size(36.dp)
                        ) {
                            Icon(
                                Icons.Default.DeleteOutline,
                                "Clear transcript",
                                tint = if (hasTranscript) MaterialTheme.colorScheme.error
                                else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.35f),
                                modifier = Modifier.size(17.dp)
                            )
                        }
                    }
                }

                FilledIconButton(
                    onClick = onSpeak,
                    enabled = hasTranscript,
                    shape = RoundedCornerShape(22.dp),
                    modifier = Modifier.size(64.dp)
                ) {
                    Icon(
                        Icons.AutoMirrored.Filled.VolumeUp,
                        "Speak transcript",
                        modifier = Modifier.size(26.dp)
                    )
                }
            }
        }
    }
}

private fun subtitleFor(debounceState: DebounceState, nlpState: NlpState): String {
    if (nlpState.synthesizedSentence.isNotBlank()) return nlpState.synthesizedSentence
    if (nlpState.pendingGlosses.isNotEmpty()) {
        return "Gloss · " + nlpState.pendingGlosses.takeLast(4).joinToString(" ") {
            DebounceEngine.formatDisplayText(it)
        }
    }
    return if (debounceState.status == DwellStatus.NO_HAND) {
        "Show a hand to the camera"
    } else if (debounceState.candidate.isBlank()) {
        "Hold a sign to commit it"
    } else {
        "${(debounceState.confidence * 100).toInt()}% · ${debounceState.status.name.lowercase()}"
    }
}

@Composable
private fun CompactSignBadge(
    candidate: String,
    confidence: Float,
    dwellProgressProvider: () -> Float,
    status: DwellStatus,
    modifier: Modifier = Modifier
) {
    val isCommitted = status == DwellStatus.COMMITTED
    val primary = MaterialTheme.colorScheme.primary
    val success = AppTheme.semantic.success
    val track = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.45f)

    Surface(
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        modifier = modifier
    ) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            Canvas(modifier = Modifier.fillMaxSize().padding(3.dp)) {
                val stroke = 3.dp.toPx()
                drawCircle(color = track, style = Stroke(width = stroke))
                val progress = dwellProgressProvider().coerceIn(0f, 1f)
                if (progress > 0f) {
                    drawArc(
                        color = if (isCommitted) success else primary,
                        startAngle = -90f,
                        sweepAngle = progress * 360f,
                        useCenter = false,
                        style = Stroke(width = stroke, cap = StrokeCap.Round)
                    )
                }
            }

            when {
                candidate == "SPACE" -> Icon(
                    imageVector = Icons.Default.SpaceBar,
                    contentDescription = "Space",
                    tint = primary,
                    modifier = Modifier.size(20.dp)
                )
                candidate.isNotBlank() -> {
                    val display = DebounceEngine.formatDisplayText(candidate)
                    Text(
                        text = display,
                        style = if (display.length > 2) {
                            MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black)
                        } else {
                            MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Black)
                        },
                        color = if (isCommitted) AppTheme.semantic.success else MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(horizontal = 4.dp)
                    )
                }
                else -> Icon(
                    imageVector = Icons.Default.TouchApp,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                    modifier = Modifier.size(20.dp)
                )
            }
        }
    }
}
