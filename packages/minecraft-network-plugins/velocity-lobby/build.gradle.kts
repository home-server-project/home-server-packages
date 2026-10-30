// Maintained by Home Server Packages: reviewed, verified compile inputs.
plugins { java }

group = "org.homeserverproject.justvoxel"
version = "1.0.0"

providers.gradleProperty("buildOutputDir").orNull?.let {
    layout.buildDirectory.set(file(it))
}

java { toolchain { languageVersion.set(JavaLanguageVersion.of(25)) } }
tasks.withType<JavaCompile>().configureEach {
    options.release.set(25)
    options.encoding = "UTF-8"
}

repositories {
    mavenCentral()
    maven("https://repo.papermc.io/repository/maven-public/")
    exclusiveContent {
        forRepository { maven("https://repo.opencollab.dev/main/") }
        filter { includeModule("org.geysermc.floodgate", "api") }
    }
}

val limboApiJar = providers.gradleProperty("limboApiJar")
val velocityVersion = providers.gradleProperty("velocityVersion").orNull
    ?.takeIf { it.isNotBlank() }
    ?: throw GradleException("Missing -PvelocityVersion: use the resolved stable Velocity version")
val velocityServerJar = providers.gradleProperty("velocityServerJar").orNull
    ?.takeIf { it.isNotBlank() }
    ?: throw GradleException("Missing -PvelocityServerJar: supply the verified official Velocity server JAR")
require(file(velocityServerJar).isFile) { "velocityServerJar must be an existing verified server JAR" }
val floodgateApiVersion = providers.gradleProperty("floodgateApiVersion").get()
require(Regex("""2\.2\.5-\d{8}\.\d{6}-[1-9][0-9]*""").matches(floodgateApiVersion)) {
    "An exact timestamped Floodgate snapshot is required"
}
val floodgateApiJar = providers.gradleProperty("floodgateApiJar").get()
// Resolve the exact POM for transitive compile dependencies and verify that
// Maven supplies the same API JAR as our independent official download.
val floodgateTransitives by configurations.creating
configurations.compileOnly { extendsFrom(floodgateTransitives) }
dependencies {
    // The verified official LimboAPI artifact; supplied at runtime.
    compileOnly(files(limboApiJar))
    compileOnly("com.velocitypowered:velocity-api:$velocityVersion")
    annotationProcessor("com.velocitypowered:velocity-api:$velocityVersion")
    // Only the LimboAPI/Floodgate PluginMessagePacket bridge needs server internals.
    compileOnly(files(velocityServerJar))
    compileOnly(files(floodgateApiJar))
    floodgateTransitives("org.geysermc.floodgate:api:$floodgateApiVersion")
    compileOnly("io.netty:netty-buffer:4.2.18.Final")
    testImplementation("org.junit.jupiter:junit-jupiter:5.12.2")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.jar {
    archiveFileName.set("justvoxel-lobby.jar")
    isPreserveFileTimestamps = false
    isReproducibleFileOrder = true
}
tasks.test { useJUnitPlatform() }

// The exact Maven API artifact must match the verified OpenCollab download.
tasks.withType<JavaCompile>().configureEach {
    doFirst {
        val api = floodgateTransitives.resolvedConfiguration.resolvedArtifacts.single {
            it.moduleVersion.id.group == "org.geysermc.floodgate" && it.name == "api"
        }.file
        require(api.readBytes().contentEquals(file(floodgateApiJar).readBytes())) {
            "Floodgate Maven artifact differs from the verified official artifact"
        }
    }
}
