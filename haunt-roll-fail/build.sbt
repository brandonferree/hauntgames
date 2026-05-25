enablePlugins(ScalaJSPlugin)

Compile / mainClass := Some("hrf.HRF")

unmanagedSources / excludeFilter := "reflect-jvm.scala" || "log-jvm.scala" || "host-jvm.scala" || "grey-jvm.scala" || "timeline-jvm.scala" || "host.scala" || "convert-images.scala" || "extract-logs.scala"

scalaJSUseMainModuleInitializer := true

// scalaJSLinkerConfig ~= { _.withOptimizer(false) }
scalaJSLinkerConfig ~= { _.withOptimizer(true) }

// scalaJSLinkerConfig ~= { _.withModuleKind(ModuleKind.CommonJSModule) }

// Compile / fullLinkJS / scalaJSLinkerConfig ~= { _.withClosureCompiler(false) }

// Compile / unmanagedSourceDirectories += baseDirectory.value / "dom" / "scala"

// Compile / unmanagedSourceDirectories += baseDirectory.value / "dom" / "scala-2"

// Compile / unmanagedSourceDirectories += baseDirectory.value / "dom" / "scala-new-collections"

libraryDependencies += "org.scala-js" %%% "scalajs-dom" % "2.8.0-SNAPSHOT"
