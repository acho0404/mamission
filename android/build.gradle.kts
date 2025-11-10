// Fichier : android/build.gradle.kts

// 🔧 Déclaration des plugins globaux
plugins {
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    // ➕ Plugin Google Services (Firebase)
    id("com.google.gms.google-services") version "4.4.4" apply false
}

// ⚙️ Configuration globale pour tous les sous-projets (app, etc.)
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// 🧱 (Optionnel) Redéfinit le dossier de build pour tout le projet
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// 📦 Garantit que le module app est évalué avant les autres
subprojects {
    project.evaluationDependsOn(":app")
}

// 🧹 Commande clean personnalisée
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// 🧩 Bloc buildscript pour activer le plugin Google Services (Firebase)
buildscript {
    dependencies {
        classpath("com.google.gms:google-services:4.4.4")
    }
}
