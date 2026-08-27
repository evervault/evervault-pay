-keepclassmembers class com.evervault.googlepay.** {
  <init>();
}

# Google Pay creates the configured merchant authorization handler by class name.
-keep class * implements com.evervault.googlepay.GooglePayAuthorizationHandler {
  public <init>();
}
