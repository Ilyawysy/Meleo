# Flutter Local Notifications - preserve Gson TypeToken generic signatures
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod

# Keep generic signature of TypeToken (used by flutter_local_notifications via Gson)
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Gson specific classes
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Keep flutter_local_notifications models and their constructors
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }

# Prevent R8 from leaving Data object members always null
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Retain generic signatures of TypeToken and its subclasses
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# App Blocker
-keep class com.sparcarclabs.meleo.AppBlockerService { *; }
-keep class com.sparcarclabs.meleo.BlockerOverlayView { *; }
