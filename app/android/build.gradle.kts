allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Plusieurs plugins (alarm, printing, file_picker, permission_handler…) compilent
// encore contre Android 34/35 alors que leurs dépendances exigent 36 : on aligne
// le compileSdk de tous les plugins. Sans effet sur minSdk ni targetSdk.
// Doit rester avant evaluationDependsOn(":app") pour s'enregistrer à temps.
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library")) {
            extensions.findByName("android")?.withGroovyBuilder { "compileSdkVersion"(36) }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
