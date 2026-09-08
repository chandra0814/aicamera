package ai.lenspilot.android

import android.Manifest
import android.annotation.SuppressLint
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
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
import androidx.camera.view.CameraController
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import coil.compose.SubcomposeAsyncImage
import java.util.UUID

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
    var ready by remember { mutableStateOf(false) }
    var settings by remember { mutableStateOf(false) }
    var cameraError by remember { mutableStateOf<String?>(null) }
    var captureError by remember { mutableStateOf<String?>(null) }
    var permission by remember { mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    val controller = remember(context) { LifecycleCameraController(context).apply { setEnabledUseCases(CameraController.IMAGE_CAPTURE) } }
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
                permission = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
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
    LaunchedEffect(grid, rememberControls) {
        preferences.edit().apply {
            putBoolean("remember", rememberControls)
            if (rememberControls) putBoolean("grid", grid) else remove("grid")
        }.apply()
    }

    Column(Modifier.fillMaxSize().background(Ink).safeDrawingPadding()) {
        Row(Modifier.fillMaxWidth().height(60.dp).padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("LensPilot", fontSize = 23.sp, modifier = Modifier.weight(1f), color = Paper)
            ToolIcon("Composition grid", Icons.Outlined.GridOn, { grid = !grid }, tint = if (grid) Mint else Paper)
            ToolIcon("Camera settings", Icons.Outlined.Settings, { settings = true })
        }
        Box(Modifier.fillMaxWidth().weight(1f).clipToBounds().background(Color.Black)) {
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
            Text("PHOTO", Modifier.align(Alignment.BottomStart).padding(16.dp).background(Ink).padding(8.dp), color = Mint, fontSize = 12.sp)
        }
        captureError?.let { Text(it, Modifier.padding(horizontal = 16.dp, vertical = 8.dp), color = MaterialTheme.colorScheme.error) }
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { referencePicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) {
                Icon(Icons.Outlined.AddPhotoAlternate, null)
                Spacer(Modifier.width(8.dp)); Text(if (reference == null) "Add reference" else "Replace reference")
            }
            Spacer(Modifier.weight(1f))
            if (reference != null) ToolIcon("Remove reference", Icons.Outlined.Close, {
                reference?.let {
                    try { context.contentResolver.releasePersistableUriPermission(Uri.parse(it), Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: SecurityException) { }
                }
                reference = null
            })
            ToolIcon(if (flash) "Disable flash" else "Enable flash", if (flash) Icons.Outlined.FlashOn else Icons.Outlined.FlashOff,
                { flash = !flash }, enabled = ready && !front && !capturing && controller.cameraInfo?.hasFlashUnit() == true)
        }
        Row(Modifier.fillMaxWidth().height(104.dp).padding(horizontal = 24.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            if (lastCapture != null) Photo(lastCapture, "Review last capture", Modifier.size(52.dp).clip(RoundedCornerShape(6.dp)).clickable { viewer = lastCapture }, ContentScale.Crop)
            else Icon(Icons.Outlined.PhotoLibrary, "No captures yet", Modifier.size(52.dp).padding(12.dp), tint = Color.Gray)
            FilledIconButton(enabled = ready && !capturing, onClick = {
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
            }, modifier = Modifier.size(76.dp).border(2.dp, Paper, CircleShape).padding(5.dp), colors = IconButtonDefaults.filledIconButtonColors(containerColor = Paper, contentColor = Ink)) {
                if (capturing) CircularProgressIndicator(Modifier.size(28.dp), color = Ink)
                else Icon(Icons.Outlined.CameraAlt, "Take photo", Modifier.size(28.dp))
            }
            ToolIcon("Switch camera", Icons.Outlined.Cameraswitch, { front = !front; flash = false }, enabled = permission && !capturing)
        }
    }
    viewer?.let { uri ->
        Dialog(onDismissRequest = { viewer = null }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            Box(Modifier.fillMaxSize().background(Color.Black).safeDrawingPadding()) {
                Photo(uri, if (uri == reference) "Reference photo" else "Captured photo", Modifier.fillMaxSize(), ContentScale.Fit)
                Row(Modifier.align(Alignment.TopStart).fillMaxWidth().background(Ink), verticalAlignment = Alignment.CenterVertically) {
                    ToolIcon("Close photo", Icons.Outlined.Close, { viewer = null })
                    Text(if (uri == reference) "Reference" else "Saved to Pictures / LensPilot")
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
            Text("On-device AI: not connected", Modifier.padding(top = 16.dp))
            Text("Online references: not connected", Modifier.padding(top = 8.dp))
        }
    }, confirmButton = { TextButton(onClick = { settings = false }) { Text("Done") } })
    BackHandler(viewer != null) { viewer = null }
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
