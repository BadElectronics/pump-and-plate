# Adds the Android settings FitApp's packages need to the project files
# Flutter generated. Safe to run on every build: it only adds what's missing.
param([string]$AppDir)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$changed = @()

function Save($path, $text) { [System.IO.File]::WriteAllText($path, $text, $utf8) }

# ---------------------------------------------------------------- Gradle
$kts = Join-Path $AppDir 'android\app\build.gradle.kts'
$groovy = Join-Path $AppDir 'android\app\build.gradle'

if (Test-Path $kts) {
  $g = [System.IO.File]::ReadAllText($kts)
  $orig = $g
  if ($g -notmatch 'isCoreLibraryDesugaringEnabled') {
    $g = ([regex]'compileOptions\s*\{').Replace($g, "compileOptions {`n        isCoreLibraryDesugaringEnabled = true", 1)
  }
  $g = $g -replace 'JavaVersion\.VERSION_1_8', 'JavaVersion.VERSION_17'
  $g = $g -replace 'JavaVersion\.VERSION_11', 'JavaVersion.VERSION_17'
  $g = $g -replace 'jvmTarget\s*=\s*"11"', 'jvmTarget = "17"'
  $g = $g -replace 'JvmTarget\.JVM_11', 'JvmTarget.JVM_17'
  $g = $g -replace 'JvmTarget\.JVM_1_8', 'JvmTarget.JVM_17'
  $g = $g -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = maxOf(24, flutter.minSdkVersion)'
  # The app's permanent ID on the phone and in the app stores.
  $g = $g -replace 'applicationId\s*=\s*"[^"]*"', 'applicationId = "com.pumpandplate.app"'
  # Google Play requires apps to target Android 16 (API 36) or newer.
  $g = $g -replace 'compileSdk\s*=\s*flutter\.compileSdkVersion', 'compileSdk = maxOf(36, flutter.compileSdkVersion)'
  $g = $g -replace 'targetSdk\s*=\s*flutter\.targetSdkVersion', 'targetSdk = maxOf(36, flutter.targetSdkVersion)'
  # Store builds are signed with the upload key when android/key.properties
  # exists (the cloud build writes it from GitHub's encrypted secrets). Without
  # it, release builds keep using the debug key, as build.bat always has.
  if ($g -notmatch 'keystoreProperties') {
    $signing = @'
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

'@
    $g = ([regex]'(?m)^android\s*\{').Replace($g, $signing + "android {`n    signingConfigs {`n        create(""upload"") {`n            if (keystorePropertiesFile.exists()) {`n                keyAlias = keystoreProperties[""keyAlias""] as String`n                keyPassword = keystoreProperties[""keyPassword""] as String`n                storeFile = file(keystoreProperties[""storeFile""] as String)`n                storePassword = keystoreProperties[""storePassword""] as String`n            }`n        }`n    }", 1)
    # Imports go at the very top (inside Gradle files, "java." means Gradle's Java settings).
    $g = "import java.io.FileInputStream`nimport java.util.Properties`n`n" + $g
    $g = $g -replace 'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)', 'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("upload") else signingConfigs.getByName("debug")'
  }
  if ($g -notmatch 'desugar_jdk_libs') {
    $g = $g.TrimEnd() + "`n`ndependencies {`n    coreLibraryDesugaring(""com.android.tools:desugar_jdk_libs:2.1.4"")`n}`n"
  }
  # AppCompat theme for the fingerprint prompt (local_auth).
  if ($g -notmatch 'androidx.appcompat:appcompat') {
    $g = ([regex]'(?m)^dependencies\s*\{').Replace($g, "dependencies {`n    implementation(""androidx.appcompat:appcompat:1.7.0"")", 1)
  }
  # Leave out the Qualcomm NPU libraries (about 58 MB): models run on the
  # graphics chip or the processor, never the NPU, and nothing else needs them.
  if ($g -notmatch 'libQnn') {
    $g = ([regex]'(?m)^android\s*\{').Replace($g, "android {`n    packaging {`n        jniLibs {`n            excludes += setOf(""**/libQnn*.so"", ""**/libLiteRtDispatch_Qualcomm.so"")`n        }`n    }", 1)
  }
  if ($g -cne $orig) { Save $kts $g; $changed += 'build.gradle.kts' }
} elseif (Test-Path $groovy) {
  $g = [System.IO.File]::ReadAllText($groovy)
  $orig = $g
  if ($g -notmatch 'coreLibraryDesugaringEnabled') {
    $g = ([regex]'compileOptions\s*\{').Replace($g, "compileOptions {`n        coreLibraryDesugaringEnabled true", 1)
  }
  $g = $g -replace 'JavaVersion\.VERSION_1_8', 'JavaVersion.VERSION_17'
  $g = $g -replace 'JavaVersion\.VERSION_11', 'JavaVersion.VERSION_17'
  $g = $g -replace "jvmTarget\s*=\s*'11'", "jvmTarget = '17'"
  $g = $g -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion Math.max(24, flutter.minSdkVersion)'
  $g = $g -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = Math.max(24, flutter.minSdkVersion)'
  $g = $g -replace 'applicationId\s*=?\s*["''][^"'']*["'']', 'applicationId = "com.pumpandplate.app"'
  if ($g -notmatch 'desugar_jdk_libs') {
    $g = $g.TrimEnd() + "`n`ndependencies {`n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'`n}`n"
  }
  if ($g -notmatch 'androidx.appcompat:appcompat') {
    $g = ([regex]'(?m)^dependencies\s*\{').Replace($g, "dependencies {`n    implementation 'androidx.appcompat:appcompat:1.7.0'", 1)
  }
  if ($g -notmatch 'libQnn') {
    $g = ([regex]'(?m)^android\s*\{').Replace($g, "android {`n    packaging {`n        jniLibs {`n            excludes += ['**/libQnn*.so', '**/libLiteRtDispatch_Qualcomm.so']`n        }`n    }", 1)
  }
  if ($g -cne $orig) { Save $groovy $g; $changed += 'build.gradle' }
} else {
  throw "Could not find android\app\build.gradle.kts in $AppDir"
}

# ---------------------------------------------------------------- Manifest
$manifest = Join-Path $AppDir 'android\app\src\main\AndroidManifest.xml'
$m = [System.IO.File]::ReadAllText($manifest)
$orig = $m
if ($m -notmatch 'RECEIVE_BOOT_COMPLETED') {
  $m = ([regex]'(<manifest[^>]*>)').Replace($m, "`$1`n    <uses-permission android:name=""android.permission.RECEIVE_BOOT_COMPLETED""/>", 1)
}
if ($m -notmatch 'POST_NOTIFICATIONS') {
  $m = ([regex]'(<manifest[^>]*>)').Replace($m, "`$1`n    <uses-permission android:name=""android.permission.POST_NOTIFICATIONS""/>", 1)
}
if ($m -notmatch 'SCHEDULE_EXACT_ALARM') {
  $m = ([regex]'(<manifest[^>]*>)').Replace($m, "`$1`n    <uses-permission android:name=""android.permission.SCHEDULE_EXACT_ALARM""/>", 1)
}
if ($m -notmatch 'android.permission.INTERNET') {
  # Barcode lookups (Open Food Facts). Release builds don't include it by default.
  $m = ([regex]'(<manifest[^>]*>)').Replace($m, "`$1`n    <uses-permission android:name=""android.permission.INTERNET""/>", 1)
}
if ($m -notmatch 'USE_BIOMETRIC') {
  $m = ([regex]'(<manifest[^>]*>)').Replace($m, "`$1`n    <uses-permission android:name=""android.permission.USE_BIOMETRIC""/>", 1)
}
if ($m -notmatch 'FitAppWidget') {
  $widgetReceiver = @"
        <receiver android:name=".FitAppWidget" android:exported="true">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/fitapp_widget_info" />
        </receiver>
    </application>
"@
  $idx = $m.LastIndexOf('</application>')
  if ($idx -lt 0) { throw 'Could not find </application> in AndroidManifest.xml' }
  $m = $m.Substring(0, $idx) + $widgetReceiver.TrimStart() + $m.Substring($idx + '</application>'.Length)
}
# Names shown in the phone's widget picker (older installs had lower case).
foreach ($old in @('FitApp check-in', 'FitApp Check-In', 'Get Jacked Check-In')) { $m = $m.Replace('android:label="' + $old + '"', 'android:label="Pump and Plate Check-In"') }
foreach ($old in @('FitApp today', 'FitApp Today', 'Get Jacked Today')) { $m = $m.Replace('android:label="' + $old + '"', 'android:label="Pump and Plate Today"') }
# The name under the app icon: the <application> label.
$m = ([regex]'(<application\b[^>]*?android:label=")[^"]*(")').Replace($m, '${1}Pump and Plate${2}', 1)
$m = $m.Replace('<receiver android:name=".FitAppWidget" android:exported="true">', '<receiver android:name=".FitAppWidget" android:exported="true" android:label="Pump and Plate Check-In">')
if ($m -notmatch 'FitAppTodayWidget') {
  $todayReceiver = @"
        <receiver android:name=".FitAppTodayWidget" android:exported="true" android:label="Pump and Plate Today">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/fitapp_today_widget_info" />
        </receiver>
    </application>
"@
  $idx = $m.LastIndexOf('</application>')
  if ($idx -lt 0) { throw 'Could not find </application> in AndroidManifest.xml' }
  $m = $m.Substring(0, $idx) + $todayReceiver.TrimStart() + $m.Substring($idx + '</application>'.Length)
}
if ($m -notmatch 'HomeWidgetBackgroundReceiver') {
  # Lets widget buttons (meal ticks, sleep quality) save without opening the app.
  $bgReceiver = @"
        <receiver android:name="es.antonborri.home_widget.HomeWidgetBackgroundReceiver" android:exported="true">
            <intent-filter>
                <action android:name="es.antonborri.home_widget.action.BACKGROUND" />
            </intent-filter>
        </receiver>
    </application>
"@
  $idx = $m.LastIndexOf('</application>')
  if ($idx -lt 0) { throw 'Could not find </application> in AndroidManifest.xml' }
  $m = $m.Substring(0, $idx) + $bgReceiver.TrimStart() + $m.Substring($idx + '</application>'.Length)
}
if ($m -notmatch 'home_widget\.action\.LAUNCH') {
  # Lets the app know it was opened from the widget (to show the keypad).
  $act = $m.IndexOf('.MainActivity"')
  if ($act -lt 0) { throw 'Could not find MainActivity in AndroidManifest.xml' }
  $close = $m.IndexOf('</activity>', $act)
  if ($close -lt 0) { throw 'Could not find </activity> for MainActivity' }
  $filter = @"
            <intent-filter>
                <action android:name="es.antonborri.home_widget.action.LAUNCH" />
            </intent-filter>
        
"@
  $m = $m.Substring(0, $close) + $filter.TrimStart() + $m.Substring($close)
}
if ($m -notmatch 'android.permission.CAMERA') {
  $m = ([regex]'(<manifest[^>]*>)').Replace($m, "`$1`n    <uses-permission android:name=""android.permission.CAMERA""/>", 1)
}
if ($m -notmatch 'ScheduledNotificationReceiver') {
  $receivers = @"
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
    </application>
"@
  $idx = $m.LastIndexOf('</application>')
  if ($idx -lt 0) { throw 'Could not find </application> in AndroidManifest.xml' }
  $m = $m.Substring(0, $idx) + $receivers.TrimStart() + $m.Substring($idx + '</application>'.Length)
}
if ($m -notmatch 'android.permission.ACCESS_NETWORK_STATE') {
  # On-device AI: tells Wi-Fi from mobile data before a big model download.
  $m = ([regex]'(<manifest[^>]*>)').Replace($m, "`$1`n    <uses-permission android:name=""android.permission.ACCESS_NETWORK_STATE""/>", 1)
}
if ($m -notmatch 'FOREGROUND_SERVICE_DATA_SYNC') {
  # Large model downloads run as a foreground download so Android doesn't stop them.
  $m = ([regex]'(<manifest[^>]*>)').Replace($m, "`$1`n    <uses-permission android:name=""android.permission.FOREGROUND_SERVICE""/>`n    <uses-permission android:name=""android.permission.FOREGROUND_SERVICE_DATA_SYNC""/>", 1)
}
if ($m -notmatch 'xmlns:tools=') {
  $m = ([regex]'<manifest\b').Replace($m, '<manifest xmlns:tools="http://schemas.android.com/tools"', 1)
}
if ($m -notmatch 'androidx.work.impl.foreground.SystemForegroundService') {
  $svc = @"
        <service
            android:name="androidx.work.impl.foreground.SystemForegroundService"
            android:foregroundServiceType="dataSync"
            tools:node="merge" />

"@
  $endApp = $m.LastIndexOf('</application>')
  if ($endApp -lt 0) { throw 'Could not find </application> in AndroidManifest.xml' }
  $m = $m.Substring(0, $endApp) + $svc.TrimStart() + '    ' + $m.Substring($endApp)
}
if ($m -cne $orig) { Save $manifest $m; $changed += 'AndroidManifest.xml' }

# ---------------------------------------------------------------- Fingerprint unlock
# local_auth needs a FragmentActivity and an AppCompat theme.
$mainDir = Join-Path $AppDir 'android\app\src\main'
$main = Get-ChildItem -Path $mainDir -Recurse -Filter 'MainActivity.kt' | Select-Object -First 1
if ($null -eq $main) { throw "Could not find MainActivity.kt under $mainDir" }
$ma = [System.IO.File]::ReadAllText($main.FullName)
$orig = $ma
$ma = $ma -replace 'io\.flutter\.embedding\.android\.FlutterActivity\b', 'io.flutter.embedding.android.FlutterFragmentActivity'
$ma = $ma -replace ':\s*FlutterActivity\(\)', ': FlutterFragmentActivity()'
if ($ma -cne $orig) { Save $main.FullName $ma; $changed += 'MainActivity.kt' }
$pkg = ([regex]'(?m)^\s*package\s+([\w\.]+)').Match($ma).Groups[1].Value
if (-not $pkg) { throw 'Could not read the package name from MainActivity.kt' }

# The whole MainActivity: a FragmentActivity (fingerprint unlock) with a small
# channel the app uses to read memory, chip, storage and the connection type.
$mainKotlin = @'
package __PKG__

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.media.MediaPlayer
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.DocumentsContract
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private val pickFolder = 4711
    private var pendingPick: MethodChannel.Result? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fitapp/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "specs" -> result.success(specs())
                "network" -> result.success(network())
                "openUrl" -> result.success(openUrl(call.argument<String>("url") ?: ""))
                "email" -> result.success(
                    email(call.argument<String>("to") ?: "", call.argument<String>("subject") ?: "", call.argument<String>("body") ?: "")
                )
                "model" -> result.success("${Build.MANUFACTURER} ${Build.MODEL} - Android ${Build.VERSION.RELEASE}")
                "keepScreenOn" -> {
                    if (call.argument<Boolean>("on") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                "playSound" -> result.success(playSound(call.argument<String>("path") ?: ""))
                "stopSound" -> {
                    stopSound()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // Automatic backups: a folder picked once, written to from then on.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fitapp/backup").setMethodCallHandler { call, result ->
            val tree = call.argument<String>("tree")
            when (call.method) {
                "pick" -> {
                    if (pendingPick != null) {
                        result.error("busy", "The folder picker is already open.", null)
                    } else {
                        pendingPick = result
                        val i = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                        i.addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                        )
                        startActivityForResult(i, pickFolder)
                    }
                }
                "check" -> background(result) { folderOk(Uri.parse(tree!!)) }
                "write" -> background(result) {
                    writeFile(Uri.parse(tree!!), call.argument<String>("name")!!, call.argument<String>("path")!!)
                }
                "list" -> background(result) { listFiles(Uri.parse(tree!!)) }
                "delete" -> background(result) {
                    DocumentsContract.deleteDocument(
                        contentResolver,
                        DocumentsContract.buildDocumentUriUsingTree(Uri.parse(tree!!), call.argument<String>("id")!!)
                    )
                    null
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openUrl(url: String): Boolean = try {
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }

    /// Starts an email in the phone's email app; nothing is sent until Send is tapped there.
    private fun email(to: String, subject: String, body: String): Boolean = try {
        val i = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
        i.putExtra(Intent.EXTRA_EMAIL, arrayOf(to))
        i.putExtra(Intent.EXTRA_SUBJECT, subject)
        i.putExtra(Intent.EXTRA_TEXT, body)
        startActivity(i)
        true
    } catch (e: Exception) {
        false
    }

    private var player: MediaPlayer? = null

    /// The rest-is-up sound: a file the user picked, copied into the app.
    private fun playSound(path: String): Boolean {
        stopSound()
        return try {
            val p = MediaPlayer()
            p.setDataSource(path)
            p.setOnCompletionListener { it.release(); if (player === it) player = null }
            p.prepare()
            p.start()
            player = p
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun stopSound() {
        try {
            player?.stop()
        } catch (e: Exception) {
        }
        player?.release()
        player = null
    }

    /// File work off the main thread; the answer goes back on it.
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("io", e.message ?: e.toString(), null) }
            }
        }
    }

    @Deprecated("Uses the long-standing activity result callback.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickFolder) return
        val r = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            r.success(null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (e: Exception) {
        }
        r.success(mapOf("uri" to uri.toString(), "name" to folderName(uri)))
    }

    private fun folderDoc(tree: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))

    private fun folderName(tree: Uri): String {
        try {
            contentResolver.query(folderDoc(tree), arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
                ?.use { if (it.moveToFirst()) return it.getString(0) ?: "Chosen folder" }
        } catch (e: Exception) {
        }
        return "Chosen folder"
    }

    private fun folderOk(tree: Uri): Boolean {
        val allowed = contentResolver.persistedUriPermissions.any { it.uri == tree && it.isWritePermission }
        if (!allowed) return false
        return try {
            contentResolver.query(folderDoc(tree), arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)
                ?.use { it.moveToFirst() } ?: false
        } catch (e: Exception) {
            false
        }
    }

    private fun writeFile(tree: Uri, name: String, path: String): Long {
        val doc = DocumentsContract.createDocument(contentResolver, folderDoc(tree), "application/json", name)
            ?: throw Exception("Couldn't create the backup file in that folder.")
        try {
            val out = contentResolver.openOutputStream(doc) ?: throw Exception("Couldn't open the backup file.")
            out.use { o -> File(path).inputStream().use { it.copyTo(o) } }
        } catch (e: Exception) {
            // Don't leave a half-written backup behind (a full drive, say).
            try {
                DocumentsContract.deleteDocument(contentResolver, doc)
            } catch (x: Exception) {
            }
            throw e
        }
        return File(path).length()
    }

    private fun listFiles(tree: Uri): List<Map<String, String>> {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val out = ArrayList<Map<String, String>>()
        contentResolver.query(
            children,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null
        )?.use {
            while (it.moveToNext()) {
                out.add(mapOf("id" to (it.getString(0) ?: ""), "name" to (it.getString(1) ?: "")))
            }
        }
        return out
    }

    private fun specs(): Map<String, Any?> {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mem = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mem)
        val free = try { StatFs(filesDir.absolutePath).availableBytes } catch (e: Exception) { 0L }
        val soc = if (Build.VERSION.SDK_INT >= 31) Build.SOC_MODEL else Build.HARDWARE
        val maker = if (Build.VERSION.SDK_INT >= 31) Build.SOC_MANUFACTURER else ""
        return mapOf(
            "totalRam" to mem.totalMem,
            "freeStorage" to free,
            "soc" to soc,
            "socMaker" to maker,
            "model" to Build.MODEL,
            "brand" to Build.MANUFACTURER,
            "abis" to Build.SUPPORTED_ABIS.toList()
        )
    }

    private fun network(): String {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return "none"
        if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return "none"
        if (onWifi(caps)) return "unmetered"
        // Behind a VPN Android reports the VPN, which counts as metered by
        // default, so look at the real connection underneath it.
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
            @Suppress("DEPRECATION")
            for (n in cm.allNetworks) {
                val c = cm.getNetworkCapabilities(n) ?: continue
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
                if (c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) && onWifi(c)) return "unmetered"
            }
        }
        return "metered"
    }

    // Wi-Fi or a cable counts as Wi-Fi, even one Android marks as metered.
    private fun onWifi(c: NetworkCapabilities) =
        c.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) ||
            c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            c.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
}
'@

$res = Join-Path $mainDir 'res'
foreach ($dir in @('values', 'values-night')) {
  $f = Join-Path $res "$dir\styles.xml"
  if (Test-Path $f) {
    $x = [System.IO.File]::ReadAllText($f)
    $o = $x
    $x = $x -replace '(<style\s+name="LaunchTheme"\s+parent=")[^"]*(")', '${1}Theme.AppCompat.DayNight.NoActionBar${2}'
    $x = $x -replace '(<style\s+name="NormalTheme"\s+parent=")[^"]*(")', '${1}Theme.AppCompat.DayNight.NoActionBar${2}'
    if ($x -cne $o) { Save $f $x; $changed += "$dir\styles.xml" }
  }
}

# ---------------------------------------------------------------- Home screen widget
function Put($path, $text) {
  $dir = Split-Path $path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $old = if (Test-Path $path) { [System.IO.File]::ReadAllText($path) } else { '' }
  if ($old -cne $text) { Save $path $text; $script:changed += (Split-Path $path -Leaf) }
}

$kotlin = @'
package __PKG__

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Shared by both FitApp widgets. */
object FitAppWidgets {
    /** Opens the app at [link] (handled in Dart). */
    fun open(context: Context, link: String) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(link))

    /** Runs [link] in the background without opening the app (handled in Dart). */
    fun background(context: Context, link: String) =
        HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse(link))

    /** If the saved data is from an earlier day, asks the app to recompute it. */
    fun refreshIfStale(context: Context, data: SharedPreferences) {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val day = data.getString("data_day", null)
        if (day != null && day != today) {
            try {
                background(context, "fitapp://refresh").send()
            } catch (e: Exception) {
                // Next update will try again.
            }
        }
    }
}

/** Check-in widget: today's weigh-in and last night's sleep. */
class FitAppWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        FitAppWidgets.refreshIfStale(context, widgetData)
        val qualityIds = intArrayOf(R.id.fitapp_q1, R.id.fitapp_q2, R.id.fitapp_q3, R.id.fitapp_q4, R.id.fitapp_q5)
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.fitapp_widget)
            views.setTextViewText(R.id.fitapp_weight, widgetData.getString("weight", "\u2014"))
            views.setTextViewText(R.id.fitapp_weight_sub, widgetData.getString("weight_sub", "Tap to log"))
            views.setTextViewText(R.id.fitapp_sleep, widgetData.getString("sleep", "\u2014"))
            views.setTextViewText(R.id.fitapp_sleep_sub, widgetData.getString("sleep_sub", "Tap to log"))
            views.setOnClickPendingIntent(R.id.fitapp_weight_row, FitAppWidgets.open(context, "fitapp://weighin"))
            views.setOnClickPendingIntent(R.id.fitapp_sleep_row, FitAppWidgets.open(context, "fitapp://sleep"))
            val ask = widgetData.getBoolean("ask_quality", false)
            views.setViewVisibility(R.id.fitapp_quality_row, if (ask) View.VISIBLE else View.GONE)
            for ((i, id) in qualityIds.withIndex()) {
                views.setOnClickPendingIntent(id, FitAppWidgets.background(context, "fitapp://quality?q=" + (i + 1)))
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
'@
Put $main.FullName ($mainKotlin -replace '__PKG__', $pkg)
Put (Join-Path $main.DirectoryName 'FitAppWidget.kt') ($kotlin -replace '__PKG__', $pkg)

$todayKotlin = @'
package __PKG__

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/** Today widget: the workout (with Start) and today's planned meals to tick off. */
class FitAppTodayWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        FitAppWidgets.refreshIfStale(context, widgetData)
        val rows = intArrayOf(R.id.meal0_row, R.id.meal1_row, R.id.meal2_row, R.id.meal3_row)
        val checks = intArrayOf(R.id.meal0_check, R.id.meal1_check, R.id.meal2_check, R.id.meal3_check)
        val labels = intArrayOf(R.id.meal0_label, R.id.meal1_label, R.id.meal2_label, R.id.meal3_label)
        val texts = intArrayOf(R.id.meal0_text, R.id.meal1_text, R.id.meal2_text, R.id.meal3_text)
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.fitapp_today_widget)
            views.setTextViewText(R.id.today_title, widgetData.getString("day_title", "Today"))
            views.setTextViewText(R.id.today_kcal, widgetData.getString("kcal", ""))
            views.setTextViewText(R.id.today_workout, widgetData.getString("workout", "Open Pump and Plate to set up today"))
            views.setOnClickPendingIntent(R.id.today_header, FitAppWidgets.open(context, "fitapp://today"))
            val action = widgetData.getString("workout_action", "") ?: ""
            val workoutId = widgetData.getString("workout_id", "") ?: ""
            if (action.isEmpty()) {
                views.setViewVisibility(R.id.today_start, View.GONE)
            } else {
                views.setViewVisibility(R.id.today_start, View.VISIBLE)
                views.setTextViewText(R.id.today_start, action)
                views.setOnClickPendingIntent(
                    R.id.today_start,
                    FitAppWidgets.open(context, "fitapp://start?w=" + Uri.encode(workoutId))
                )
            }
            for (i in 0 until 4) {
                val has = widgetData.getBoolean("meal" + i + "_has", false)
                views.setViewVisibility(rows[i], if (has) View.VISIBLE else View.GONE)
                if (!has) continue
                val done = widgetData.getBoolean("meal" + i + "_done", false)
                views.setTextViewText(labels[i], widgetData.getString("meal" + i + "_label", ""))
                views.setTextViewText(texts[i], widgetData.getString("meal" + i + "_text", ""))
                views.setTextViewText(checks[i], if (done) "\u2713" else "")
                views.setInt(
                    checks[i],
                    "setBackgroundResource",
                    if (done) R.drawable.fitapp_check_on else R.drawable.fitapp_check_off
                )
                views.setOnClickPendingIntent(rows[i], FitAppWidgets.background(context, "fitapp://meal?slot=" + i))
            }
            val empty = widgetData.getBoolean("meals_empty", true)
            views.setViewVisibility(R.id.today_no_meals, if (empty) View.VISIBLE else View.GONE)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
'@
Put (Join-Path $main.DirectoryName 'FitAppTodayWidget.kt') ($todayKotlin -replace '__PKG__', $pkg)

# Check-in widget layout. Plain ASCII only: Windows PowerShell 5.1 reads this
# script as Windows-1252, so special characters are written as XML codes.
Put (Join-Path $res 'layout\fitapp_widget.xml') @'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/fitapp_widget_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@drawable/fitapp_widget_bg"
    android:orientation="vertical"
    android:padding="10dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginStart="4dp"
        android:layout_marginBottom="6dp"
        android:text="Pump and Plate &#183; Check-In"
        android:textColor="#6A6257"
        android:textSize="11sp"
        android:textStyle="bold" />

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal">

        <LinearLayout
            android:id="@+id/fitapp_weight_row"
            android:layout_width="0dp"
            android:layout_height="match_parent"
            android:layout_marginEnd="4dp"
            android:layout_weight="1"
            android:background="@drawable/fitapp_tile"
            android:orientation="vertical"
            android:padding="10dp">

            <TextView
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:letterSpacing="0.08"
                android:text="WEIGH-IN"
                android:textColor="#4D6A3C"
                android:textSize="10sp"
                android:textStyle="bold" />

            <TextView
                android:id="@+id/fitapp_weight"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="2dp"
                android:ellipsize="end"
                android:maxLines="1"
                android:text="&#8212;"
                android:textColor="#1F1C17"
                android:textSize="18sp" />

            <TextView
                android:id="@+id/fitapp_weight_sub"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:ellipsize="end"
                android:maxLines="1"
                android:text="Tap to log"
                android:textColor="#6A6257"
                android:textSize="11sp" />
        </LinearLayout>

        <LinearLayout
            android:id="@+id/fitapp_sleep_row"
            android:layout_width="0dp"
            android:layout_height="match_parent"
            android:layout_marginStart="4dp"
            android:layout_weight="1"
            android:background="@drawable/fitapp_tile"
            android:orientation="vertical"
            android:padding="10dp">

            <TextView
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:letterSpacing="0.08"
                android:text="LAST NIGHT"
                android:textColor="#4D6A3C"
                android:textSize="10sp"
                android:textStyle="bold" />

            <TextView
                android:id="@+id/fitapp_sleep"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="2dp"
                android:ellipsize="end"
                android:maxLines="1"
                android:text="&#8212;"
                android:textColor="#1F1C17"
                android:textSize="18sp" />

            <TextView
                android:id="@+id/fitapp_sleep_sub"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:ellipsize="end"
                android:maxLines="1"
                android:text="Tap to log"
                android:textColor="#6A6257"
                android:textSize="11sp" />

            <LinearLayout
                android:id="@+id/fitapp_quality_row"
                android:layout_width="match_parent"
                android:layout_height="26dp"
                android:layout_marginTop="4dp"
                android:orientation="horizontal"
                android:visibility="gone">

                <TextView android:id="@+id/fitapp_q1" android:layout_width="0dp" android:layout_height="match_parent" android:layout_weight="1" android:layout_margin="1dp" android:background="@drawable/fitapp_chip" android:gravity="center" android:text="1" android:textColor="#1F1C17" android:textSize="12sp" />
                <TextView android:id="@+id/fitapp_q2" android:layout_width="0dp" android:layout_height="match_parent" android:layout_weight="1" android:layout_margin="1dp" android:background="@drawable/fitapp_chip" android:gravity="center" android:text="2" android:textColor="#1F1C17" android:textSize="12sp" />
                <TextView android:id="@+id/fitapp_q3" android:layout_width="0dp" android:layout_height="match_parent" android:layout_weight="1" android:layout_margin="1dp" android:background="@drawable/fitapp_chip" android:gravity="center" android:text="3" android:textColor="#1F1C17" android:textSize="12sp" />
                <TextView android:id="@+id/fitapp_q4" android:layout_width="0dp" android:layout_height="match_parent" android:layout_weight="1" android:layout_margin="1dp" android:background="@drawable/fitapp_chip" android:gravity="center" android:text="4" android:textColor="#1F1C17" android:textSize="12sp" />
                <TextView android:id="@+id/fitapp_q5" android:layout_width="0dp" android:layout_height="match_parent" android:layout_weight="1" android:layout_margin="1dp" android:background="@drawable/fitapp_chip" android:gravity="center" android:text="5" android:textColor="#1F1C17" android:textSize="12sp" />
            </LinearLayout>
        </LinearLayout>
    </LinearLayout>
</LinearLayout>
'@

# Today widget layout. Only views allowed in home screen widgets (no plain <View>).
$mealRow = @'
        <LinearLayout
            android:id="@+id/mealN_row"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:gravity="center_vertical"
            android:minHeight="30dp"
            android:orientation="horizontal"
            android:visibility="gone">

            <TextView
                android:id="@+id/mealN_check"
                android:layout_width="20dp"
                android:layout_height="20dp"
                android:background="@drawable/fitapp_check_off"
                android:gravity="center"
                android:textColor="#FFFFFF"
                android:textSize="12sp"
                android:textStyle="bold" />

            <TextView
                android:id="@+id/mealN_label"
                android:layout_width="64dp"
                android:layout_height="wrap_content"
                android:layout_marginStart="8dp"
                android:textColor="#6A6257"
                android:textSize="11sp" />

            <TextView
                android:id="@+id/mealN_text"
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_weight="1"
                android:ellipsize="end"
                android:maxLines="1"
                android:textColor="#1F1C17"
                android:textSize="13sp" />
        </LinearLayout>

'@
$mealRows = ''
foreach ($n in 0..3) { $mealRows += $mealRow -replace 'mealN_', "meal$($n)_" }

Put (Join-Path $res 'layout\fitapp_today_widget.xml') (@'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/today_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@drawable/fitapp_widget_bg"
    android:orientation="vertical"
    android:padding="10dp">

    <LinearLayout
        android:id="@+id/today_header"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="6dp"
        android:gravity="center_vertical"
        android:orientation="horizontal"
        android:paddingStart="4dp"
        android:paddingEnd="4dp">

        <TextView
            android:id="@+id/today_title"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:ellipsize="end"
            android:maxLines="1"
            android:text="Pump and Plate &#183; Today"
            android:textColor="#6A6257"
            android:textSize="11sp"
            android:textStyle="bold" />

        <TextView
            android:id="@+id/today_kcal"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:maxLines="1"
            android:textColor="#6A6257"
            android:textSize="11sp" />
    </LinearLayout>

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:background="@drawable/fitapp_tile"
        android:gravity="center_vertical"
        android:orientation="horizontal"
        android:padding="10dp">

        <LinearLayout
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:orientation="vertical">

            <TextView
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:letterSpacing="0.08"
                android:text="WORKOUT"
                android:textColor="#4D6A3C"
                android:textSize="10sp"
                android:textStyle="bold" />

            <TextView
                android:id="@+id/today_workout"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="2dp"
                android:ellipsize="end"
                android:maxLines="2"
                android:text="Rest day"
                android:textColor="#1F1C17"
                android:textSize="15sp" />
        </LinearLayout>

        <TextView
            android:id="@+id/today_start"
            android:layout_width="wrap_content"
            android:layout_height="34dp"
            android:layout_marginStart="8dp"
            android:background="@drawable/fitapp_button"
            android:gravity="center"
            android:paddingStart="16dp"
            android:paddingEnd="16dp"
            android:text="Start"
            android:textColor="#FFFFFF"
            android:textSize="13sp"
            android:textStyle="bold"
            android:visibility="gone" />
    </LinearLayout>

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="6dp"
        android:background="@drawable/fitapp_tile"
        android:orientation="vertical"
        android:paddingStart="10dp"
        android:paddingTop="8dp"
        android:paddingEnd="10dp"
        android:paddingBottom="6dp">

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginBottom="2dp"
            android:letterSpacing="0.08"
            android:text="MEALS"
            android:textColor="#4D6A3C"
            android:textSize="10sp"
            android:textStyle="bold" />

        <TextView
            android:id="@+id/today_no_meals"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:paddingTop="4dp"
            android:paddingBottom="4dp"
            android:text="No meals planned today. Add them in Plan."
            android:textColor="#6A6257"
            android:textSize="12sp"
            android:visibility="gone" />

'@ + $mealRows + @'
    </LinearLayout>
</LinearLayout>
'@)

Put (Join-Path $res 'drawable\fitapp_widget_bg.xml') @'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#EDE7DB" />
    <corners android:radius="22dp" />
</shape>
'@

Put (Join-Path $res 'drawable\fitapp_tile.xml') @'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#FFFFFF" />
    <corners android:radius="16dp" />
</shape>
'@

Put (Join-Path $res 'drawable\fitapp_check_on.xml') @'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="oval">
    <solid android:color="#4D6A3C" />
</shape>
'@

Put (Join-Path $res 'drawable\fitapp_check_off.xml') @'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="oval">
    <solid android:color="#00000000" />
    <stroke android:width="2dp" android:color="#A39A8C" />
</shape>
'@

Put (Join-Path $res 'drawable\fitapp_button.xml') @'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#4D6A3C" />
    <corners android:radius="18dp" />
</shape>
'@

Put (Join-Path $res 'drawable\fitapp_chip.xml') @'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#F2EEE6" />
    <stroke android:width="1dp" android:color="#E3DCD0" />
    <corners android:radius="8dp" />
</shape>
'@

Put (Join-Path $res 'xml\fitapp_widget_info.xml') @'
<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:initialLayout="@layout/fitapp_widget"
    android:minWidth="250dp"
    android:minHeight="110dp"
    android:minResizeWidth="180dp"
    android:minResizeHeight="100dp"
    android:targetCellWidth="4"
    android:targetCellHeight="2"
    android:resizeMode="horizontal|vertical"
    android:updatePeriodMillis="1800000"
    android:widgetCategory="home_screen" />
'@

Put (Join-Path $res 'xml\fitapp_today_widget_info.xml') @'
<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:initialLayout="@layout/fitapp_today_widget"
    android:minWidth="250dp"
    android:minHeight="230dp"
    android:minResizeWidth="180dp"
    android:minResizeHeight="140dp"
    android:targetCellWidth="4"
    android:targetCellHeight="3"
    android:resizeMode="horizontal|vertical"
    android:updatePeriodMillis="1800000"
    android:widgetCategory="home_screen" />
'@

# App icon: adaptive on Android 8+, classic rounded icon on older phones.
$iconSrc = Join-Path $PSScriptRoot 'icons\res'
$script:iconChanged = $false
if (Test-Path $iconSrc) {
  $srcRoot = (Resolve-Path $iconSrc).Path
  Get-ChildItem -Path $srcRoot -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\', '/')
    $dest = Join-Path $res $rel
    $same = (Test-Path $dest) -and ((Get-FileHash $dest).Hash -eq (Get-FileHash $_.FullName).Hash)
    if (-not $same) {
      New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
      Copy-Item $_.FullName $dest -Force
      $script:iconChanged = $true
    }
  }
}
if ($script:iconChanged) { $changed += 'app icon' }

if ($changed.Count -gt 0) {
  Write-Host ("Updated Android project files: " + ($changed -join ', '))
} else {
  Write-Host 'Android project files already up to date.'
}
