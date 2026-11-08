import com.android.ide.common.signing.KeystoreHelper
import com.google.gson.JsonParser
import org.jose4j.json.internal.json_simple.JSONObject
import java.io.DataInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale

plugins {
    alias(libs.plugins.agp.app)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.nav.safeargs.kotlin)
}

val appPackageName = rootProject.extra["appPackageName"] as String
val crowdinProjectId = rootProject.extra["crowdinProjectId"] as String
val crowdinApiKey = rootProject.extra["crowdinApiKey"] as String
val localBuild = rootProject.extra["localBuild"] as Boolean
val officialBuild = rootProject.extra["officialBuild"] as Boolean

@Suppress("DEPRECATION")
afterEvaluate {
    val srcDir = file(android.sourceSets["main"].assets.directories.first())
    logger.lifecycle("Asset dir: $srcDir")
    if (!srcDir.exists()) srcDir.mkdirs()

    val translatorsMap = mutableMapOf(
        // I used GitHub to get translations before moving to Crowdin.
        // Since nearly all of GitHub translators are listed in Crowdin
        // too, I wanted to add one profile here.

        "cvnertnc" to "https://avatars.githubusercontent.com/u/148134890?v=4",
    )

    val urlConnection = if (crowdinApiKey.isNotBlank()) {
        logger.lifecycle("Found Crowdin API key")

        val url = URL("https://crowdin.com/api/v2/projects/$crowdinProjectId/members")
        (url.openConnection() as HttpURLConnection).apply {
            setRequestProperty("authorization", "Bearer $crowdinApiKey")
        }
    } else {
        val url = URL("https://github.com/frknkrc44/HMA-OSS/releases/latest/download/translators.json")
        url.openConnection() as HttpURLConnection
    }

    val inputStream = DataInputStream(urlConnection.getInputStream())
    val str = String(inputStream.readAllBytes())
    inputStream.close()
    urlConnection.disconnect()

    val json = JsonParser.parseString(str).asJsonObject

    if (crowdinApiKey.isNotBlank()) {
        val translators = json.getAsJsonArray("data")

        for (item in translators) {
            val translator = item.asJsonObject.getAsJsonObject("data")
            val avatarUrl = translator.get("avatarUrl").asString
            val username = translator.get("username").asString
            val fullName = try {
                translator.get("fullName").asString
            } catch (_: Throwable) {
                ""
            }

            if (fullName.isNotEmpty() && fullName != username) {
                translatorsMap["$fullName ($username)"] = avatarUrl
            } else {
                translatorsMap[username] = avatarUrl
            }
        }
    } else {
        json.keySet().forEach { translatorsMap[it] = json.get(it).asString }
    }

    val translatorJson = JSONObject(translatorsMap).toJSONString()
    File(srcDir, "translators.json").writeText(translatorJson)
}

android {
    namespace = appPackageName

    defaultConfig {
        buildConfigField("String[]", "SUPPORTED_LOCALES", generateSupportedLocales())
    }

    buildFeatures {
        buildConfig = true
        viewBinding = true
    }

    // Compile the original system_server hook implementation into the manager APK.
    // The old :zygote Gradle module and Zygisk packaging plugin are no longer used.
    sourceSets {
        getByName("main") {
            java.srcDir("../zygote/src/main/java")
            java.srcDir("../external/AndroidVMTools/src/main/java")
        }
    }

    packaging {
        dex.useLegacyPackaging = true
        resources {
            excludes += arrayOf(
                "/META-INF/*",
                "/META-INF/androidx/**",
                "/kotlin/**",
                "/okhttp3/**",
            )
        }
    }
}

base {
    archivesName = "${rootProject.name}-${android.defaultConfig.versionName!!.replace("/", "_")}"
}

kotlin {
    jvmToolchain(21)
}

// Inspired from https://github.com/XayahSuSuSu/Android-DataBackup/pull/260
fun generateSupportedLocales(): String {
    val foundLocales = StringBuilder()
    foundLocales.append("new String[]{")

    fun appendLangCode(code: String) {
        foundLocales.append("\"").append(code).append("\"").append(",")
    }

    appendLangCode("SYSTEM")

    fileTree(android.sourceSets["main"].res.directories.first()).files.mapNotNull {
        if (it.name == "strings.xml") {
            val baseName = it.parent.substringAfterLast(File.separator)
            if (baseName == "values") {
                "en"
            } else {
                baseName.substringAfter('-')
                    .replace("-r", "-")
            }
        } else {
            null
        }
    }.sortedWith { file1, file2 ->
        file1.compareTo(file2)
    }.forEach { appendLangCode(it) }

    return "${foundLocales.removeSuffix(",")}}"
}

dependencies {
    implementation(projects.common)
    compileOnly(projects.stub)

    implementation(libs.androidx.annotation.jvm)
    implementation(libs.io.github.vova7878.r8annotations)
    implementation(androidvmtools.panama.core)
    implementation(androidvmtools.panama.unsafe)
    implementation(androidvmtools.panama.llvm)
    implementation(androidvmtools.sun.cleaner)

    implementation(libs.androidx.navigation.fragment.ktx)
    implementation(libs.androidx.navigation.ui.ktx)
    implementation(libs.androidx.preference.ktx)
    implementation(libs.androidx.swiperefreshlayout)
    implementation(libs.io.coilkt.coil3.coil)
    implementation(libs.io.coilkt.coil3.coil.network.okhttp)
    implementation(libs.dev.androidbroadcast.vbpd)
    implementation(libs.dev.androidbroadcast.vbpd.reflection)

    implementation(libs.androidx.appcompat.appcompat)
    implementation(libs.material)
}

/**
 * The manager and the Xposed payload now share one signing identity.
 * HMAService verifies that identity before exposing its privileged Binder.
 */
abstract class GenerateSignInfoTask : DefaultTask() {
    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @get:Input
    @get:Optional
    abstract val storeType: Property<String>

    @get:InputFile
    @get:Optional
    abstract val storeFile: RegularFileProperty

    @get:Input
    @get:Optional
    abstract val keyAlias: Property<String>

    @get:Internal
    abstract val storePassword: Property<String>

    @get:Internal
    abstract val keyPassword: Property<String>

    @TaskAction
    fun generate() {
        val certificateInfo = KeystoreHelper.getCertificateInfo(
            storeType.orNull, storeFile.asFile.orNull,
            storePassword.orNull, keyPassword.orNull, keyAlias.orNull,
        )
        val target = outputDir.get().file("org/frknkrc44/hma_oss/zygote/Magic.java").asFile
        target.parentFile.mkdirs()
        target.writeText(buildString {
            appendLine("package org.frknkrc44.hma_oss.zygote;")
            appendLine("public final class Magic {")
            appendLine("public static final byte[] magicNumbers = {")
            appendLine(certificateInfo.certificate.encoded.joinToString(",") { it.toString() })
            appendLine("};")
            appendLine("}")
        })
    }
}

androidComponents {
    onVariants { variant ->
        val variantName = variant.name.lowercase(Locale.ROOT)
        val signing = android.buildTypes[variantName].signingConfig
        val generateSignInfo = tasks.register<GenerateSignInfoTask>(
            "generate${variant.name.replaceFirstChar { it.titlecase(Locale.ROOT) }}SignInfo"
        ) {
            storeType.set(signing?.storeType)
            storeFile.set(signing?.storeFile)
            storePassword.set(signing?.storePassword)
            keyAlias.set(signing?.keyAlias)
            keyPassword.set(signing?.keyPassword)
        }
        variant.sources.java?.addGeneratedSourceDirectory(
            generateSignInfo, GenerateSignInfoTask::outputDir,
        )
    }
}
