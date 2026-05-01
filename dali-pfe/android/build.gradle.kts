allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

fun Project.ensureNamespaceFromManifest() {
    val androidExtension = extensions.findByName("android") ?: return

    val getNamespace = runCatching {
        androidExtension.javaClass.getMethod("getNamespace")
    }.getOrNull() ?: return

    val setNamespace = runCatching {
        androidExtension.javaClass.getMethod("setNamespace", String::class.java)
    }.getOrNull() ?: return

    val currentNamespace = runCatching {
        getNamespace.invoke(androidExtension) as? String
    }.getOrNull()

    if (!currentNamespace.isNullOrBlank()) return

    val manifestFile = file("src/main/AndroidManifest.xml")
    if (!manifestFile.exists()) return

    val packageName = Regex("package\\s*=\\s*\"([^\"]+)\"")
        .find(manifestFile.readText())
        ?.groupValues
        ?.getOrNull(1)
        ?.trim()

    if (!packageName.isNullOrBlank()) {
        runCatching {
            setNamespace.invoke(androidExtension, packageName)
        }
    }
}

subprojects {
    plugins.withId("com.android.library") { ensureNamespaceFromManifest() }
    plugins.withId("com.android.application") { ensureNamespaceFromManifest() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
