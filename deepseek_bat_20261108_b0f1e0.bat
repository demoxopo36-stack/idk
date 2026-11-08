@echo off
setlocal enabledelayedexpansion
title PBaseFinder Auto-Build

echo ============================================
echo   PBaseFinder - auto build
echo ============================================
echo.

REM ---- 1. sprawdz JDK 21 ----
where java >nul 2>nul
if %errorlevel% neq 0 (
    echo [X] Brak Javy. Instaluje Temurin 21...
    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%%2B11/OpenJDK21U-jdk_x64_windows_hotspot_21.0.5_11.msi' -OutFile '%TEMP%\jdk21.msi'"
    msiexec /i "%TEMP%\jdk21.msi" /quiet ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJavaHome
    set "PATH=%ProgramFiles%\Eclipse Adoptium\jdk-21.0.5.11-hotspot\bin;%PATH%"
)

REM ---- 2. sprawdz Gradle ----
where gradle >nul 2>nul
if %errorlevel% neq 0 (
    echo [X] Brak Gradle. Pobieram...
    powershell -Command "Invoke-WebRequest -Uri 'https://services.gradle.org/distributions/gradle-8.10-bin.zip' -OutFile '%TEMP%\gradle.zip'"
    powershell -Command "Expand-Archive -Path '%TEMP%\gradle.zip' -DestinationPath '%USERPROFILE%\gradle-dist' -Force"
    set "PATH=%USERPROFILE%\gradle-dist\gradle-8.10\bin;%PATH%"
)

REM ---- 3. utworz folder projektu ----
set "PROJ=%USERPROFILE%\Desktop\PBaseFinder"
if exist "%PROJ%" rmdir /s /q "%PROJ%"
mkdir "%PROJ%"
cd /d "%PROJ%"

echo [*] Tworze strukture...

mkdir src\main\java\com\pbasefinder\modules 2>nul
mkdir src\main\resources 2>nul

REM ---- 4. pliki projektu ----

> gradle.properties (
echo org.gradle.jvmargs=-Xmx2G
echo minecraft_version=1.21.1
echo yarn_mappings=1.21.1+build.3
echo loader_version=0.16.9
echo fabric_version=0.116.5+1.21.1
echo meteor_version=1.21.1-SNAPSHOT
echo mod_version=1.0.0
echo maven_group=com.pbasefinder
echo archives_base_name=pbasefinder
)

> settings.gradle (
echo pluginManagement {
echo     repositories {
echo         maven { url = 'https://maven.fabricmc.net/' }
echo         mavenCentral()
echo         gradlePluginPortal()
echo     }
echo }
)

> build.gradle (
echo plugins {
echo     id 'fabric-loom' version '1.7-SNAPSHOT'
echo }
echo version = project.mod_version
echo group = project.maven_group
echo base { archivesName = project.archives_base_name }
echo repositories {
echo     maven { url 'https://maven.meteordev.org/releases' }
echo     maven { url 'https://maven.meteordev.org/snapshots' }
echo     mavenCentral()
echo }
echo dependencies {
echo     minecraft "com.mojang:minecraft:${project.minecraft_version}"
echo     mappings "net.fabricmc:yarn:${project.yarn_mappings}:v2"
echo     modImplementation "net.fabricmc:fabric-loader:${project.loader_version}"
echo     modImplementation "net.fabricmc.fabric-api:fabric-api:${project.fabric_version}"
echo     modImplementation "meteordevelopment:meteor-client:${project.meteor_version}"
echo }
echo processResources {
echo     inputs.property "version", project.version
echo     filesMatching("fabric.mod.json") { expand "version": project.version }
echo }
echo tasks.withType(JavaCompile).configureEach { it.options.release = 21 }
echo java {
echo     sourceCompatibility = JavaVersion.VERSION_21
echo     targetCompatibility = JavaVersion.VERSION_21
echo }
)

> src\main\resources\fabric.mod.json (
echo {
echo   "schemaVersion": 1,
echo   "id": "pbasefinder",
echo   "version": "${version}",
echo   "name": "PBaseFinder",
echo   "description": "DonutSMP base finder addon for Meteor.",
echo   "authors": ["He"],
echo   "environment": "client",
echo   "entrypoints": {
echo     "meteor": ["com.pbasefinder.PBaseFinder"]
echo   },
echo   "depends": {
echo     "fabricloader": ">=0.16.0",
echo     "fabric-api": "*",
echo     "minecraft": "~1.21.1",
echo     "meteor-client": "*"
echo   }
echo }
)

> src\main\java\com\pbasefinder\PBaseFinder.java (
echo package com.pbasefinder;
echo import com.mojang.logging.LogUtils;
echo import com.pbasefinder.modules.BaseFinder;
echo import meteordevelopment.meteorclient.addons.MeteorAddon;
echo import meteordevelopment.meteorclient.systems.modules.Category;
echo import meteordevelopment.meteorclient.systems.modules.Modules;
echo import org.slf4j.Logger;
echo public class PBaseFinder extends MeteorAddon {
echo     public static final Logger LOG = LogUtils.getLogger();
echo     public static final Category CATEGORY = new Category("P Base Finder");
echo     @Override
echo     public void onInitialize() {
echo         LOG.info("PBaseFinder init");
echo         Modules.get().add(new BaseFinder());
echo     }
echo     @Override
echo     public void onRegisterCategories() {
echo         Modules.registerCategory(CATEGORY);
echo     }
echo     @Override
echo     public String getPackage() { return "com.pbasefinder"; }
echo }
)

> src\main\java\com\pbasefinder\modules\BaseFinder.java (
echo package com.pbasefinder.modules;
echo import com.pbasefinder.PBaseFinder;
echo import meteordevelopment.meteorclient.events.render.Render3DEvent;
echo import meteordevelopment.meteorclient.events.world.TickEvent;
echo import meteordevelopment.meteorclient.renderer.ShapeMode;
echo import meteordevelopment.meteorclient.settings.*;
echo import meteordevelopment.meteorclient.systems.modules.Module;
echo import meteordevelopment.meteorclient.utils.render.color.SettingColor;
echo import meteordevelopment.orbit.EventHandler;
echo import net.minecraft.block.entity.*;
echo import net.minecraft.util.math.BlockPos;
echo import net.minecraft.util.math.ChunkPos;
echo import net.minecraft.world.chunk.WorldChunk;
echo import java.util.*;
echo public class BaseFinder extends Module {
echo     private final SettingGroup sgGeneral = settings.getDefaultGroup();
echo     private final Setting^<Integer^> range = sgGeneral.add(new IntSetting.Builder()
echo         .name("range").defaultValue(8).min(1).max(32).build());
echo     private final Setting^<Boolean^> findChests = sgGeneral.add(new BoolSetting.Builder()
echo         .name("chests").defaultValue(true).build());
echo     private final Setting^<Boolean^> findSpawners = sgGeneral.add(new BoolSetting.Builder()
echo         .name("spawners").defaultValue(true).build());
echo     private final Setting^<Boolean^> findEnderChests = sgGeneral.add(new BoolSetting.Builder()
echo         .name("ender-chests").defaultValue(true).build());
echo     private final Setting^<SettingColor^> sideColor = sgGeneral.add(new ColorSetting.Builder()
echo         .name("side-color").defaultValue(new SettingColor(255, 0, 0, 50)).build());
echo     private final Setting^<SettingColor^> lineColor = sgGeneral.add(new ColorSetting.Builder()
echo         .name("line-color").defaultValue(new SettingColor(255, 0, 0, 255)).build());
echo     private final Setting^<Integer^> scanInterval = sgGeneral.add(new IntSetting.Builder()
echo         .name("scan-interval").defaultValue(40).min(10).max(200).build());
echo     private final List^<BlockPos^> found = new ArrayList^<^>();
echo     private int timer = 0;
echo     public BaseFinder() {
echo         super(PBaseFinder.CATEGORY, "base-finder", "Scans chunks for base blocks.");
echo     }
echo     @Override
echo     public void onActivate() { found.clear(); timer = 0; }
echo     @Override
echo     public void onDeactivate() { found.clear(); }
echo     @EventHandler
echo     private void onTick(TickEvent.Post event) {
echo         if (mc.player == null || mc.world == null) return;
echo         if (timer-- ^> 0) return;
echo         timer = scanInterval.get();
echo         found.clear();
echo         ChunkPos center = mc.player.getChunkPos();
echo         int r = range.get();
echo         for (int dx = -r; dx ^<= r; dx++) {
echo             for (int dz = -r; dz ^<= r; dz++) {
echo                 ChunkPos cp = new ChunkPos(center.x + dx, center.z + dz);
echo                 if (!mc.world.isChunkLoaded(cp.x, cp.z)) continue;
echo                 WorldChunk chunk = mc.world.getChunk(cp.x, cp.z);
echo                 if (chunk == null) continue;
echo                 for (Map.Entry^<BlockPos, BlockEntity^> e : chunk.getBlockEntities().entrySet()) {
echo                     BlockEntity be = e.getValue();
echo                     BlockPos pos = e.getKey();
echo                     if (findChests.get() ^&^& (be instanceof ChestBlockEntity || be instanceof BarrelBlockEntity
echo                         || be instanceof ShulkerBoxBlockEntity || be instanceof TrappedChestBlockEntity)) {
echo                         found.add(pos);
echo                     }
echo                     if (findEnderChests.get() ^&^& be instanceof EnderChestBlockEntity) found.add(pos);
echo                     if (findSpawners.get() ^&^& be instanceof MobSpawnerBlockEntity) found.add(pos);
echo                 }
echo             }
echo         }
echo     }
echo     @EventHandler
echo     private void onRender(Render3DEvent event) {
echo         for (BlockPos pos : found) {
echo             event.renderer.box(pos, sideColor.get(), lineColor.get(), ShapeMode.Both, 0);
echo         }
echo     }
echo }
)

REM ---- 5. build ----
echo.
echo [*] Buduje... (pierwszy raz moze potrwac 2-3 min)
gradle build --no-daemon

if %errorlevel% neq 0 (
    echo.
    echo [X] Build nie wyszedl. Zobacz bledy wyzej.
    pause
    exit /b 1
)

REM ---- 6. kopiuj jar do mods ----
set "MODS=%APPDATA%\.minecraft\mods"
if not exist "%MODS%" mkdir "%MODS%"

for %%f in (build\libs\pbasefinder-*.jar) do (
    copy "%%f" "%MODS%\" >nul
    echo.
    echo [OK] Skopiowano: %%~nxf -^> %MODS%
)

echo.
echo ============================================
echo   GOTOWE. Odpal Minecraft z Fabric 1.21.1
echo   i Meteor Client w mods.
echo ============================================
pause