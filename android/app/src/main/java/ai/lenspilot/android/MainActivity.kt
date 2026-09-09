package ai.lenspilot.android

import android.Manifest
import android.annotation.SuppressLint
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.provider.MediaStore
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageAnalysis
import androidx.camera.view.CameraController
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import coil.compose.SubcomposeAsyncImage
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

private val Ink = Color(0xFF101313)
private val Mint = Color(0xFFBAF464)
private val Paper = Color(0xFFF4F7F2)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(primary = Mint, background = Ink, surface = Ink,
                onPrimary = Ink, onSurface = Paper)) { CameraScreen() }
        }
    }
}

@Composable
@SuppressLint("MissingPermission") // Binding is gated by the permission state, refreshed on every resume.
private fun CameraScreen() {
    val context = LocalContext.current
    val compactHeight = LocalConfiguration.current.screenHeightDp < 500
    val owner = LocalLifecycleOwner.current
    val executor = remember(context) { ContextCompat.getMainExecutor(context) }
    val preferences = remember { context.getSharedPreferences("camera_preferences", 0) }
    var rememberControls by rememberSaveable { mutableStateOf(preferences.getBoolean("remember", false)) }
    var grid by rememberSaveable { mutableStateOf(if (rememberControls) preferences.getBoolean("grid", true) else true) }
    var reference by rememberSaveable { mutableStateOf<String?>(null) }
    var lastCapture by rememberSaveable { mutableStateOf<String?>(null) }
    var viewer by rememberSaveable { mutableStateOf<String?>(null) }
    var front by rememberSaveable { mutableStateOf(false) }
    var flash by rememberSaveable { mutableStateOf(false) }
    var capturing by remember { mutableStateOf(false) }
    var timerSeconds by rememberSaveable { mutableStateOf(0) }
    var countdown by remember { mutableStateOf<Int?>(null) }
    val captureTimer = remember { CaptureTimer() }
    var ready by remember { mutableStateOf(false) }
    var settings by remember { mutableStateOf(false) }
    var cameraError by remember { mutableStateOf<String?>(null) }
    var captureError by remember { mutableStateOf<String?>(null) }
    var sceneName by rememberSaveable { mutableStateOf("GENERAL") }
    var instruction by rememberSaveable { mutableStateOf("") }
    var ideaIndex by rememberSaveable { mutableStateOf(0) }
    var ideasOpen by remember { mutableStateOf(false) }
    var showIdea by remember { mutableStateOf(false) }
    var light by remember { mutableStateOf(GuidanceEngine.Light.UNKNOWN) }
    var frameAt by remember { mutableStateOf(0L) }
    var resumed by remember { mutableStateOf(owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) }
    val scene = GuidanceEngine.sceneFor(instruction.replace('\n', ' '), GuidanceEngine.Scene.valueOf(sceneName))
    val lightingTip = GuidanceEngine.lightingTip(light, scene)
    val idea = GuidanceEngine.ideaForRequest(instruction, scene, reference != null, ideaIndex)
    val suggestion = if (!showIdea && lightingTip != null) lightingTip else idea
    var permission by remember { mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    val controller = remember(context) { LifecycleCameraController(context).apply {
        setEnabledUseCases(CameraController.IMAGE_CAPTURE or CameraController.IMAGE_ANALYSIS)
        imageAnalysisBackpressureStrategy = ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST
    } }
    val canCapture = ready && resumed && permission && viewer == null && !settings && !ideasOpen && !capturing
    val latestCanCapture by rememberUpdatedState(canCapture)
    val takePhoto: () -> Unit = {
        if (latestCanCapture && !capturing && owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
            capturing = true
            captureError = null
            try {
                controller.imageCaptureFlashMode = if (flash && !front && controller.cameraInfo?.hasFlashUnit() == true) ImageCapture.FLASH_MODE_ON else ImageCapture.FLASH_MODE_OFF
                val metadata = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, "LensPilot-${UUID.randomUUID()}.jpg")
                    put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/LensPilot")
                }
                val output = ImageCapture.OutputFileOptions.Builder(context.contentResolver, MediaStore.Images.Media.EXTERNAL_CONTENT_URI, metadata).build()
                controller.takePicture(output, executor, object : ImageCapture.OnImageSavedCallback {
                    override fun onImageSaved(result: ImageCapture.OutputFileResults) {
                        capturing = false
                        lastCapture = result.savedUri?.toString()
                        if (lastCapture == null) captureError = "Photo saved, but its preview is unavailable."
                    }
                    override fun onError(exception: ImageCaptureException) { capturing = false; captureError = "Photo could not be saved. Please try again." }
                })
            } catch (_: Exception) { capturing = false; captureError = "Capture failed. Please try again." }
        }
    }
    val latestTakePhoto by rememberUpdatedState(takePhoto)
    LaunchedEffect(countdown != null) {
        if (countdown != null) try {
            while (captureTimer.isActive) {
                val now = SystemClock.elapsedRealtime()
                if (captureTimer.consumeDue(now, latestCanCapture)) { latestTakePhoto(); break }
                if (!captureTimer.isActive) break
                countdown = captureTimer.remainingSeconds(now)
                kotlinx.coroutines.delay(100)
            }
        } finally { captureTimer.cancel(); countdown = null }
    }
    val permissionPicker = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { permission = it }
    val referencePicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) {
            try { context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: SecurityException) { /* Some picker providers only grant session access. */ }
            reference?.takeIf { it != uri.toString() }?.let {
                try { context.contentResolver.releasePersistableUriPermission(Uri.parse(it), Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: SecurityException) { }
            }
            reference = uri.toString()
        }
    }
    DisposableEffect(owner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                resumed = true
                permission = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
            }
            if (event == Lifecycle.Event.ON_PAUSE) {
                resumed = false; light = GuidanceEngine.Light.UNKNOWN
                captureTimer.cancel(); countdown = null
            }
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
    }
    DisposableEffect(controller, owner, permission, front) {
        var active = true
        ready = false
        cameraError = null
        if (permission) {
            try {
                controller.cameraSelector = if (front) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
                controller.bindToLifecycle(owner)
                controller.initializationFuture.addListener({
                    if (active) {
                        try {
                            controller.initializationFuture.get()
                            ready = controller.hasCamera(controller.cameraSelector)
                            if (!ready) cameraError = "This camera is unavailable."
                        } catch (_: Exception) { cameraError = "Could not start the camera." }
                    }
                }, executor)
            } catch (_: Exception) { cameraError = "This camera is unavailable. Try switching cameras." }
        }
        onDispose { active = false; controller.unbind() }
    }
    DisposableEffect(controller, ready, resumed, front, viewer) {
        val active = AtomicBoolean(true)
        val analyzer = Executors.newSingleThreadExecutor()
        light = GuidanceEngine.Light.UNKNOWN
        frameAt = 0L
        if (ready && resumed && viewer == null) {
            var lastRead = 0L
            var pending = GuidanceEngine.Light.UNKNOWN
            var repeated = 0
            controller.setImageAnalysisAnalyzer(analyzer) { image ->
                try {
                    val now = SystemClock.elapsedRealtime()
                    if (active.get() && now - lastRead >= 800) {
                        lastRead = now
                        val plane = image.planes.firstOrNull()
                        val measured = if (plane == null) GuidanceEngine.Light.UNKNOWN else
                            GuidanceEngine.measure(plane.buffer, image.width, image.height, plane.rowStride, plane.pixelStride)
                        // Require consecutive readings so auto-exposure changes do not flicker advice.
                        repeated = if (measured == pending) repeated + 1 else 1
                        pending = measured
                        if (repeated >= 2) executor.execute {
                            if (active.get()) { light = measured; frameAt = now }
                        }
                    }
                } finally { image.close() }
            }
        }
        onDispose { active.set(false); controller.clearImageAnalysisAnalyzer(); analyzer.shutdown() }
    }
    LaunchedEffect(light) { showIdea = false }
    LaunchedEffect(frameAt) {
        if (frameAt != 0L) {
            kotlinx.coroutines.delay(4000)
            light = GuidanceEngine.Light.UNKNOWN
        }
    }
    LaunchedEffect(grid, rememberControls) {
        preferences.edit().apply {
            putBoolean("remember", rememberControls)
            if (rememberControls) putBoolean("grid", grid) else remove("grid")
        }.apply()
    }

    Column(Modifier.fillMaxSize().background(Ink).safeDrawingPadding()
        .then(if (compactHeight) Modifier.verticalScroll(rememberScrollState()) else Modifier)) {
        Row(Modifier.fillMaxWidth().height(60.dp).padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("LensPilot", fontSize = 23.sp, modifier = Modifier.weight(1f), color = Paper)
            ToolIcon("Shot ideas", Icons.Outlined.Lightbulb, { ideasOpen = true }, tint = Mint)
            ToolIcon("Composition grid", Icons.Outlined.GridOn, { grid = !grid }, tint = if (grid) Mint else Paper)
            ToolIcon("Camera settings", Icons.Outlined.Settings, { settings = true })
        }
        Box(Modifier.fillMaxWidth().then(if (compactHeight) Modifier.height(220.dp) else Modifier.weight(1f)).clipToBounds().background(Color.Black)) {
            if (permission) {
                AndroidView(factory = { PreviewView(it).apply {
                    implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                    this.controller = controller
                } }, modifier = Modifier.fillMaxSize())
                if (grid && ready) Canvas(Modifier.fillMaxSize()) {
                    for (part in 1..2) {
                        val x = size.width * part / 3
                        val y = size.height * part / 3
                        drawLine(Color.White.copy(alpha = 0.35f), Offset(x, 0f), Offset(x, size.height), 1.dp.toPx())
                        drawLine(Color.White.copy(alpha = 0.35f), Offset(0f, y), Offset(size.width, y), 1.dp.toPx())
                    }
                }
            }
            if (!permission) Column(Modifier.align(Alignment.Center).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Outlined.CameraAlt, null, Modifier.size(40.dp), tint = Mint)
                Spacer(Modifier.height(16.dp))
                Text("Camera access is off", fontSize = 20.sp)
                Button(onClick = { permissionPicker.launch(Manifest.permission.CAMERA) }) { Text("Allow camera") }
                TextButton(onClick = { context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))) }) { Text("Open settings") }
            }
            if (permission && !ready && cameraError == null) CircularProgressIndicator(Modifier.align(Alignment.Center), color = Mint)
            cameraError?.let { Text(it, Modifier.align(Alignment.Center).background(Ink).padding(16.dp), color = Paper) }
            reference?.let { uri ->
                Box(Modifier.align(Alignment.TopEnd).padding(12.dp).width(88.dp).heightIn(max = 132.dp).fillMaxHeight(0.6f)
                    .clip(RoundedCornerShape(8.dp)).border(2.dp, Mint, RoundedCornerShape(8.dp))
                    .clickable { viewer = uri }) {
                    Photo(uri, "Open reference photo", Modifier.fillMaxSize(), ContentScale.Crop)
                    Text("Reference", Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(Ink).padding(6.dp), fontSize = 12.sp)
                }
            }
            Text(if (timerSeconds == 0) "PHOTO" else "PHOTO / ${timerSeconds}s", Modifier.align(Alignment.BottomStart).padding(16.dp).background(Ink).padding(8.dp), color = Mint, fontSize = 12.sp)
            countdown?.let { seconds ->
                Column(Modifier.align(Alignment.Center).background(Ink).padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(seconds.toString(), fontSize = 40.sp, color = Mint)
                    ToolIcon("Cancel timer", Icons.Outlined.Close, { captureTimer.cancel(); countdown = null })
                }
            }
        }
        Row(Modifier.fillMaxWidth().background(Color(0xFF202A24)).padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).clickable { ideasOpen = true }.padding(vertical = 10.dp)) {
                Text(if (!showIdea && lightingTip != null) "Light check" else "Shot idea", color = Mint, fontSize = 12.sp)
                Text(suggestion, fontSize = 14.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            ToolIcon("Next shot idea", Icons.Outlined.Refresh, {
                if (showIdea || lightingTip == null) ideaIndex = if (ideaIndex == Int.MAX_VALUE) 0 else ideaIndex + 1
                showIdea = true
            }, tint = Mint)
        }
        captureError?.let { Text(it, Modifier.padding(horizontal = 16.dp, vertical = 8.dp), color = MaterialTheme.colorScheme.error) }
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(modifier = Modifier.weight(1f), onClick = { referencePicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, enabled = countdown == null && !capturing) {
                Icon(Icons.Outlined.AddPhotoAlternate, null)
                Spacer(Modifier.width(8.dp)); Text(if (reference == null) "Add reference" else "Replace reference")
            }
            ToolIcon(if (timerSeconds == 0) "Timer off" else "Timer $timerSeconds seconds", Icons.Outlined.Timer, {
                timerSeconds = when (timerSeconds) { 0 -> 3; 3 -> 10; else -> 0 }
            }, enabled = countdown == null && !capturing, tint = if (timerSeconds == 0) Paper else Mint)
            if (reference != null) ToolIcon("Remove reference", Icons.Outlined.Close, {
                reference?.let {
                    try { context.contentResolver.releasePersistableUriPermission(Uri.parse(it), Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: SecurityException) { }
                }
                reference = null
            })
            ToolIcon(if (flash) "Disable flash" else "Enable flash", if (flash) Icons.Outlined.FlashOn else Icons.Outlined.FlashOff,
                { flash = !flash }, enabled = ready && !front && !capturing && countdown == null && controller.cameraInfo?.hasFlashUnit() == true)
        }
        Row(Modifier.fillMaxWidth().height(104.dp).padding(horizontal = 24.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            if (lastCapture != null) Photo(lastCapture, "Review last capture", Modifier.size(52.dp).clip(RoundedCornerShape(6.dp)).clickable { viewer = lastCapture }, ContentScale.Crop)
            else Icon(Icons.Outlined.PhotoLibrary, "No captures yet", Modifier.size(52.dp).padding(12.dp), tint = Color.Gray)
            FilledIconButton(enabled = canCapture && countdown == null, onClick = {
                if (timerSeconds == 0) takePhoto()
                else if (captureTimer.start(timerSeconds, SystemClock.elapsedRealtime())) countdown = timerSeconds
            }, modifier = Modifier.size(76.dp).border(2.dp, Paper, CircleShape).padding(5.dp), colors = IconButtonDefaults.filledIconButtonColors(containerColor = Paper, contentColor = Ink)) {
                if (capturing) CircularProgressIndicator(Modifier.size(28.dp), color = Ink)
                else Icon(Icons.Outlined.CameraAlt, "Take photo", Modifier.size(28.dp))
            }
            ToolIcon("Switch camera", Icons.Outlined.Cameraswitch, { front = !front; flash = false }, enabled = permission && !capturing && countdown == null)
        }
    }
    viewer?.let { uri ->
        Dialog(onDismissRequest = { viewer = null }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            Box(Modifier.fillMaxSize().background(Color.Black).safeDrawingPadding()) {
                Photo(uri, if (uri == reference) "Reference photo" else "Captured photo", Modifier.fillMaxSize(), ContentScale.Fit)
                Row(Modifier.align(Alignment.TopStart).fillMaxWidth().background(Ink), verticalAlignment = Alignment.CenterVertically) {
                    ToolIcon("Close photo", Icons.Outlined.Close, { viewer = null })
                    Text(if (uri == reference) "Reference" else "Saved to Pictures / LensPilot", Modifier.weight(1f))
                    if (uri == lastCapture && uri != reference) ToolIcon("Share photo", Icons.Outlined.Share, {
                        try {
                            val photoUri = Uri.parse(uri)
                            val share = Intent(Intent.ACTION_SEND).apply {
                                type = "image/jpeg"
                                putExtra(Intent.EXTRA_STREAM, photoUri)
                                clipData = android.content.ClipData.newUri(context.contentResolver, "LensPilot photo", photoUri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            context.startActivity(Intent.createChooser(share, "Share photo"))
                        } catch (_: Exception) { captureError = "Photo could not be shared. Check that it still exists."; viewer = null }
                    })
                }
            }
        }
    }
    if (settings) AlertDialog(onDismissRequest = { settings = false }, title = { Text("Camera settings") }, text = {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Remember grid preference", Modifier.weight(1f))
                Switch(rememberControls, { rememberControls = it })
            }
            Text("Local guidance: light checks and shot ideas", Modifier.padding(top = 16.dp))
            Text("Subject recognition: not connected", Modifier.padding(top = 8.dp))
            Text("Online references: not connected", Modifier.padding(top = 8.dp))
        }
    }, confirmButton = { TextButton(onClick = { settings = false }) { Text("Done") } })
    if (ideasOpen) AlertDialog(onDismissRequest = { ideasOpen = false }, title = { Text("Shot ideas") }, text = {
        Column(Modifier.verticalScroll(rememberScrollState())) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GuidanceEngine.Scene.values().forEach { choice ->
                    FilterChip(selected = sceneName == choice.name, onClick = { sceneName = choice.name; instruction = ""; ideaIndex = 0 },
                        label = { Text(choice.name.lowercase().replaceFirstChar { it.titlecase() }) })
                }
            }
            OutlinedTextField(value = instruction, onValueChange = { instruction = it.take(240); ideaIndex = 0 },
                label = { Text("Shot request") }, placeholder = { Text("Portrait, food, landscape, night...") },
                modifier = Modifier.fillMaxWidth(), minLines = 2, maxLines = 3)
            Text("Local tips / ${scene.name.lowercase()}", color = Mint, modifier = Modifier.padding(top = 16.dp))
            if (instruction.isNotBlank() && !GuidanceEngine.supportsRequest(instruction)) {
                Text("Request not recognized. Showing the selected scene's ideas.", modifier = Modifier.padding(top = 8.dp))
            }
            Text(idea, modifier = Modifier.padding(top = 8.dp))
            lightingTip?.let { Text(it, modifier = Modifier.padding(top = 12.dp)) }
            TextButton(onClick = { ideaIndex = if (ideaIndex == Int.MAX_VALUE) 0 else ideaIndex + 1; showIdea = true }) { Text("Another idea") }
        }
    }, confirmButton = { TextButton(onClick = { ideasOpen = false }) { Text("Done") } })
    BackHandler(viewer != null) { viewer = null }
    BackHandler(countdown != null) { captureTimer.cancel(); countdown = null }
}

@Composable
private fun Photo(uri: String?, label: String, modifier: Modifier, scale: ContentScale) {
    SubcomposeAsyncImage(model = uri, contentDescription = label, modifier = modifier, contentScale = scale,
        loading = { Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(20.dp)) } },
        error = { Box(Modifier.fillMaxSize().background(Ink), contentAlignment = Alignment.Center) { Icon(Icons.Outlined.BrokenImage, "Photo unavailable; select it again", tint = Paper) } })
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ToolIcon(label: String, icon: ImageVector, onClick: () -> Unit, enabled: Boolean = true, tint: Color = Paper) {
    TooltipBox(positionProvider = TooltipDefaults.rememberPlainTooltipPositionProvider(), tooltip = { PlainTooltip { Text(label) } }, state = rememberTooltipState()) {
        IconButton(onClick, enabled = enabled) { Icon(icon, label, tint = if (enabled) tint else Color.Gray) }
    }
}
